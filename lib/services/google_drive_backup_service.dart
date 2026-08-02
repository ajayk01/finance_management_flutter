import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GoogleDriveBackupService {
  GoogleDriveBackupService._();

  static final GoogleDriveBackupService instance = GoogleDriveBackupService._();

  static const _driveUploadUrl =
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart';
  static const _driveFilesUrl = 'https://www.googleapis.com/drive/v3/files';
  static const _defaultBackupFolderName = 'Personal Projects MYSQL Dump';
  static const _sessionEmailKey = 'gdrive_backup_session_email';
  static const _sessionEnabledKey = 'gdrive_backup_session_enabled';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const ['https://www.googleapis.com/auth/drive.file'],
  );

  Future<void> authorizeInteractive() async {
    var account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();
    account ??= await _googleSignIn.signIn();

    if (account == null) {
      throw StateError('Google sign-in was cancelled.');
    }

    final authHeaders = await account.authHeaders;
    final authorization = authHeaders['Authorization'];
    if (authorization == null || authorization.trim().isEmpty) {
      throw StateError('Google authorization token not available.');
    }
    await _saveSessionState(account.email);
  }

  Future<void> clearSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionEmailKey);
    await prefs.remove(_sessionEnabledKey);
    await _googleSignIn.signOut();
  }

  Future<bool> hasSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_sessionEnabledKey) ?? false;
    final email = prefs.getString(_sessionEmailKey) ?? '';
    return enabled && email.trim().isNotEmpty;
  }

  Future<void> _saveSessionState(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sessionEnabledKey, true);
    await prefs.setString(_sessionEmailKey, email);
  }

  Future<GoogleSignInAccount?> _resolveAccount({
    required bool allowInteractiveSignIn,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSavedSession = prefs.getBool(_sessionEnabledKey) ?? false;

    GoogleSignInAccount? account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();

    if (account == null && allowInteractiveSignIn) {
      try {
        account = await _googleSignIn.signIn();
      } on PlatformException catch (e) {
        final details = '${e.code} ${e.message ?? ''}';
        if (details.contains('ApiException: 10') ||
            details.toLowerCase().contains('sign_in_failed')) {
          throw StateError(
            'Google Sign-In configuration error (ApiException: 10). '
            'Add SHA-1/SHA-256 for this Android app in Firebase, '
            'enable Google Sign-In in Firebase Auth, then download a '
            'fresh google-services.json.',
          );
        }
        rethrow;
      }
    }

    if (account != null) {
      await _saveSessionState(account.email);
      return account;
    }

    if (hasSavedSession && !allowInteractiveSignIn) {
      throw StateError(
        'Saved Google session exists but silent sign-in failed. '
        'Open the app and re-authorize Google Drive once.',
      );
    }

    return null;
  }

  Future<Map<String, dynamic>> uploadBackupFile({
    required String filePath,
    String? folderId,
    bool allowInteractiveSignIn = false,
  }) async {
    final file = File(filePath);
    final exists = await file.exists();
    if (!exists) {
      throw FileSystemException('Backup file not found.', filePath);
    }

    final account = await _resolveAccount(
      allowInteractiveSignIn: allowInteractiveSignIn,
    );
    if (account == null) {
      throw StateError(
        'Google session not available. Call authorizeInteractive() once first.',
      );
    }

    final authHeaders = await account.authHeaders;
    final authorization = authHeaders['Authorization'];
    if (authorization == null || authorization.trim().isEmpty) {
      throw StateError('Google authorization token not available.');
    }

    final driveFolderId = await _resolveOrCreateTargetFolderId(
      authorization: authorization,
      explicitFolderId: folderId,
    );
    final metadata = <String, dynamic>{
      'name': file.uri.pathSegments.last,
      if (driveFolderId.isNotEmpty) 'parents': [driveFolderId],
    };

    final request = http.MultipartRequest('POST', Uri.parse(_driveUploadUrl));
    request.headers['Authorization'] = authorization;
    request.files.add(
      http.MultipartFile.fromString(
        'metadata',
        jsonEncode(metadata),
        contentType: MediaType('application', 'json', {'charset': 'utf-8'}),
      ),
    );
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        filePath,
        contentType: MediaType('text', 'plain', {'charset': 'utf-8'}),
      ),
    );

    final streamedResponse = await request.send();
    final responseBody = await streamedResponse.stream.bytesToString();

    if (streamedResponse.statusCode < 200 || streamedResponse.statusCode >= 300) {
      throw HttpException(
        'Google Drive upload failed (${streamedResponse.statusCode}): $responseBody',
      );
    }

    final json = jsonDecode(responseBody) as Map<String, dynamic>;
    return {
      'id': json['id'],
      'name': json['name'] ?? metadata['name'],
      'mimeType': json['mimeType'],
      'folderId': driveFolderId,
    };
  }

  Future<String> _resolveOrCreateTargetFolderId({
    required String authorization,
    String? explicitFolderId,
  }) async {
    final envFolderId = (dotenv.env['GOOGLE_DRIVE_FOLDER_ID'] ?? '').trim();
    final configuredFolderId = (explicitFolderId ?? envFolderId).trim();
    if (configuredFolderId.isNotEmpty) {
      return configuredFolderId;
    }

    final folderName =
        (dotenv.env['GOOGLE_DRIVE_FOLDER_NAME'] ?? _defaultBackupFolderName)
            .trim();
    final existingId = await _findFolderIdByName(
      authorization: authorization,
      folderName: folderName,
    );
    if (existingId != null) {
      return existingId;
    }

    return _createFolder(
      authorization: authorization,
      folderName: folderName,
    );
  }

  Future<String?> _findFolderIdByName({
    required String authorization,
    required String folderName,
  }) async {
    final escapedName = folderName.replaceAll("'", "\\'");
    final query =
        "mimeType='application/vnd.google-apps.folder' and trashed=false and name='$escapedName'";
    final uri = Uri.parse(_driveFilesUrl).replace(queryParameters: {
      'q': query,
      'fields': 'files(id,name)',
      'spaces': 'drive',
      'pageSize': '1',
    });

    final response = await http.get(
      uri,
      headers: {'Authorization': authorization},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Google Drive folder lookup failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final files = (data['files'] as List?) ?? const [];
    if (files.isEmpty) {
      return null;
    }

    final first = files.first as Map<String, dynamic>;
    return (first['id'] as String?)?.trim();
  }

  Future<String> _createFolder({
    required String authorization,
    required String folderName,
  }) async {
    final response = await http.post(
      Uri.parse(_driveFilesUrl),
      headers: {
        'Authorization': authorization,
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({
        'name': folderName,
        'mimeType': 'application/vnd.google-apps.folder',
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Google Drive folder creation failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final folderId = (data['id'] as String?)?.trim() ?? '';
    if (folderId.isEmpty) {
      throw StateError('Google Drive folder created but no folder ID returned.');
    }
    return folderId;
  }
}