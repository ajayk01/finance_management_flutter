import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ZohoMailService {
  static final ZohoMailService _instance = ZohoMailService._internal();
  factory ZohoMailService() => _instance;
  ZohoMailService._internal();

  static const String _zohoMailBase = 'https://mail.zoho.in/api';
  static const String _zohoAccountsBase = 'https://accounts.zoho.in/oauth/v2';

  static String get _clientId => dotenv.env['ZOHO_CLIENT_ID'] ?? '';
  static String get _clientSecret => dotenv.env['ZOHO_CLIENT_SECRET'] ?? '';
  static const String _scope = 'ZohoMail.messages.READ,ZohoMail.attachments.READ,ZohoMail.accounts.ALL';

  String? _accessToken;
  String? _refreshToken;

  bool get isAuthenticated => _refreshToken != null;

  // ─── Token Management ──────────────────────────────────────

  Future<void> loadTokens() async {
    _refreshToken = dotenv.env['ZOHO_REFRESH_TOKEN'];
  }

  Future<String> _getAccessToken() async {
    if (_accessToken != null) return _accessToken!;
    if (_refreshToken == null) {
      throw ZohoException(0, 'Not authenticated');
    }
    await _refreshAccessToken();
    if (_accessToken == null) {
      throw ZohoException(0, 'Failed to obtain access token after refresh');
    }
    return _accessToken!;
  }

  /// Opens Zoho consent page in browser, prompts user to paste the
  /// authorization code, and exchanges it for refresh + access tokens.
  /// Returns true if authentication succeeded.
  Future<bool> authenticate(BuildContext context) async {
    final authUrl = Uri.parse(
      '$_zohoAccountsBase/auth'
      '?scope=$_scope'
      '&client_id=$_clientId'
      '&response_type=code'
      '&access_type=offline'
      '&redirect_uri=http://localhost:8080/'
      '&prompt=consent',
    );

    // Open browser for user to authorize
    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      throw ZohoException(0, 'Could not open browser');
    }

    if (!context.mounted) return false;

    // Ask user to paste the authorization code from redirect URL
    final code = await _showCodeDialog(context);
    if (code == null || code.isEmpty) return false;

    await generateRefreshToken(code);
    return isAuthenticated;
  }

  Future<String?> _showCodeDialog(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Zoho Authorization'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'After authorizing in the browser, copy the "code" parameter from the redirect URL and paste it below.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Authorization Code',
                hintText: 'Paste code here...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshAccessToken() async {
    if (_refreshToken == null) {
      throw ZohoException(0, 'No refresh token');
    }

    final uri = Uri.parse('$_zohoAccountsBase/token');
    final response = await http.post(uri, body: {
      'refresh_token': _refreshToken!,
      'client_id': _clientId,
      'client_secret': _clientSecret,
      'grant_type': 'refresh_token',
    });

    debugPrint('[Zoho] Token refresh → ${response.statusCode}');
    debugPrint('[Zoho] Token refresh body → ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('[Zoho] Parsed keys: ${data.keys.toList()}');

      // Zoho returns 200 even on errors like invalid_code
      if (data.containsKey('error')) {
        debugPrint('[Zoho] Token refresh error: ${data['error']}');
        // Clear invalid tokens so isAuthenticated returns false
        _accessToken = null;
        _refreshToken = null;
        throw ZohoException(0, 'Refresh token invalid: ${data['error']}');
      }

      _accessToken = data['access_token'] as String?;
      // If a new refresh token is returned, update in memory
      if (data['refresh_token'] != null) {
        _refreshToken = data['refresh_token'] as String;
      }
    } else {
      throw ZohoException(response.statusCode, 'Failed to refresh token: ${response.body}');
    }
  }

  /// Generate initial refresh token using an authorization code.
  /// Call this once after the user grants access via Zoho OAuth consent.
  Future<void> generateRefreshToken(String authCode) async {
    final uri = Uri.parse('$_zohoAccountsBase/token');
    final response = await http.post(uri, body: {
      'code': authCode,
      'client_id': _clientId,
      'client_secret': _clientSecret,
      'redirect_uri': 'http://localhost:8080/',
      'grant_type': 'authorization_code',
    });

    debugPrint('[Zoho] Auth code exchange → ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _accessToken = data['access_token'] as String?;
      _refreshToken = data['refresh_token'] as String?;
    } else {
      throw ZohoException(response.statusCode, 'Failed to exchange auth code: ${response.body}');
    }
  }

  /// Set a pre-existing refresh token directly
  Future<void> setRefreshToken(String token) async {
    _refreshToken = token;
  }

  // ─── Mail API ──────────────────────────────────────────────

  /// Fetch attachment details for a message
  Future<List<Map<String, dynamic>>> getAttachments({
    required String userId,
    required String folderId,
    required String messageId,
  }) async {
    final token = await _getAccessToken();
    final uri = Uri.parse(
      '$_zohoMailBase/accounts/$userId/folders/$folderId/messages/$messageId/attachmentinfo',
    );
    debugPrint('[Zoho] GET $uri');

    final headers = {
      'Authorization': 'Zoho-oauthtoken $token',
    };
    debugPrint('[Zoho] Headers: $headers');

    final response = await http.get(uri, headers: headers);

    debugPrint('[Zoho] Get attachments → ${response.statusCode}');
    debugPrint('[Zoho] Response body → ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map && data['data'] != null) {
        final attachments = data['data']['attachments'] as List? ?? [];
        return attachments.cast<Map<String, dynamic>>();
      }
      return [];
    } else if (response.statusCode == 401) {
      // Token expired, refresh and retry
      _accessToken = null;
      await _refreshAccessToken();
      return getAttachments(
        userId: userId,
        folderId: folderId,
        messageId: messageId,
      );
    }
    throw ZohoException(response.statusCode, response.body);
  }

  /// Download a specific attachment and save to temp directory.
  /// Returns the file path.
  Future<String> downloadAttachment({
    required String userId,
    required String folderId,
    required String messageId,
    required String attachmentId,
    required String fileName,
  }) async {
    final token = await _getAccessToken();
    final uri = Uri.parse(
      '$_zohoMailBase/accounts/$userId/folders/$folderId/messages/$messageId/attachments/$attachmentId',
    );

    final response = await http.get(uri, headers: {
      'Authorization': 'Zoho-oauthtoken $token',
    });

    debugPrint('[Zoho] Download attachment → ${response.statusCode} (${response.bodyBytes.length} bytes)');

    if (response.statusCode == 200) {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      debugPrint('[Zoho] Saved attachment to $filePath');
      return filePath;
    } else if (response.statusCode == 401) {
      _accessToken = null;
      await _refreshAccessToken();
      return downloadAttachment(
        userId: userId,
        folderId: folderId,
        messageId: messageId,
        attachmentId: attachmentId,
        fileName: fileName,
      );
    }
    throw ZohoException(response.statusCode, response.body);
  }

  /// Fetch attachments for a message and download the first PDF found.
  /// Returns the local file path.
  Future<String> fetchPdfAttachment({
    required String userId,
    required String folderId,
    required String messageId,
  }) async {
    final attachments = await getAttachments(
      userId: userId,
      folderId: folderId,
      messageId: messageId,
    );

    // Find the first PDF attachment
    final pdf = attachments.firstWhere(
      (a) =>
          (a['attachmentName'] as String? ?? '').toLowerCase().endsWith('.pdf'),
      orElse: () => throw ZohoException(0, 'No PDF attachment found'),
    );

    final attachmentId = pdf['attachmentId']?.toString() ?? '';
    final fileName = pdf['attachmentName'] as String? ?? 'statement.pdf';

    return downloadAttachment(
      userId: userId,
      folderId: folderId,
      messageId: messageId,
      attachmentId: attachmentId,
      fileName: fileName,
    );
  }
}

class ZohoException implements Exception {
  final int statusCode;
  final String message;
  ZohoException(this.statusCode, this.message);

  @override
  String toString() => 'ZohoException($statusCode): $message';
}
