import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/models.dart';
import 'mysql_service.dart';
import 'splitwise_session_service.dart';

class SplitwiseRouteService {
  SplitwiseRouteService({MySqlService? mySqlService})
      : _mySqlService = mySqlService ?? MySqlService();

  final MySqlService _mySqlService;

  static String get _currentUserId =>
      (dotenv.env['SPLITWISE_CURRENT_USER_ID'] ?? '57391213').trim();

  Future<Map<String, dynamic>> _fetchSplitwise(
    String endpoint,
    Future<void> Function() reauthenticate,
  ) async {
    final url = Uri.parse('https://secure.splitwise.com/api/v3.0/$endpoint');
    final response = await SplitwiseSessionService.instance.get(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      reauthenticate: reauthenticate,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      Map<String, dynamic> errorBody = {'error': 'Failed to parse error body'};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          errorBody = decoded;
        }
      } catch (_) {}

      debugPrint(
        'Splitwise API error for endpoint $endpoint: '
        'status=${response.statusCode}, body=$errorBody',
      );
      throw Exception(
        'Splitwise API request failed with status ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException('Unexpected Splitwise response format');
  }

  Future<Map<String, dynamic>> _postSplitwise(
    String endpoint,
    Map<String, String> fields,
    Future<void> Function() reauthenticate,
  ) async {
    final body = fields.entries
        .map((entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');
    final response = await SplitwiseSessionService.instance.post(
      Uri.parse('https://secure.splitwise.com/api/v3.0/$endpoint'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
      reauthenticate: reauthenticate,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Splitwise API request failed with status ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected Splitwise response format');
    }
    if (decoded['errors'] is Map && (decoded['errors'] as Map).isNotEmpty) {
      throw StateError((decoded['errors'] as Map).toString());
    }
    return decoded;
  }

  Future<List<Map<String, dynamic>>> getFriends({
    Future<void> Function()? reauthenticate,
  }) async {
    final config = MySqlConfig.fromDotEnv();
    await _mySqlService.connect(config);

    try {
      final dbFriendsResult = await _mySqlService.executeReadQuery(
        'SELECT ID, SPLITWISE_FRIEND_ID, NAME, TOTAL_OWNS '
        'FROM SplitwiseFriends '
        'WHERE SPLITWISE_FRIEND_ID IS NOT NULL '
        'ORDER BY NAME',
      );
      final dbFriends = dbFriendsResult['rows'] as List? ?? const [];
      final response = await _fetchSplitwise(
        'get_friends',
        reauthenticate ?? _missingReauthentication,
      );
      final apiFriends = response['friends'] as List? ?? const [];
      final apiFriendsById = <String, Map<String, dynamic>>{};
      for (final friend in apiFriends.whereType<Map>()) {
        final data = Map<String, dynamic>.from(friend);
        final friendId = data['id']?.toString() ?? '';
        if (friendId.isNotEmpty) {
          apiFriendsById[friendId] = data;
        }
      }

      final friends = <Map<String, dynamic>>[];
      for (final friend in dbFriends.whereType<Map>()) {
        final data = Map<String, dynamic>.from(friend);
        final splitwiseFriendId = data['SPLITWISE_FRIEND_ID']?.toString() ?? '';
        final apiFriend = apiFriendsById[splitwiseFriendId];
        final dbAmount = _toDouble(data['TOTAL_OWNS']);
        final splitwiseAmount = apiFriend == null
            ? 0.0
            : _parseFriendBalance(apiFriend);
        if (dbAmount <= 0 || splitwiseAmount <= 0) {
          continue;
        }

        friends.add({
          'dbFriendId': data['ID']?.toString() ?? '',
          'friendId': splitwiseFriendId,
          'name': data['NAME']?.toString() ?? '',
          'notionAmount': dbAmount,
          'splitwiseAmount': splitwiseAmount,
        });
      }
      return friends;
    } finally {
      await _mySqlService.disconnect();
    }
  }

  Future<List<Map<String, dynamic>>> getFriendExpenses({
    required String friendId,
    Future<void> Function()? reauthenticate,
  }) async {
    final response = await _fetchSplitwise(
      'get_expenses?friend_id=${Uri.encodeQueryComponent(friendId)}&limit=100',
      reauthenticate ?? _missingReauthentication,
    );
    final expenses = response['expenses'] as List? ?? const [];
    return expenses.whereType<Map>().map((expense) {
      final data = Map<String, dynamic>.from(expense);
      final users = data['users'] as List? ?? const [];
      final friend = users.whereType<Map>().cast<Map>().firstWhere(
            (user) =>
                user['user'] is Map &&
                (user['user'] as Map)['id']?.toString() == friendId,
            orElse: () => const <String, dynamic>{},
          );
      final friendOwed = _toDouble(friend['owed_share']);
      final friendPaid = _toDouble(friend['paid_share']);
      return {
        'id': data['id']?.toString() ?? '',
        'description': data['description']?.toString() ?? '',
        'date': data['date']?.toString() ?? '',
        'amount': friendOwed - friendPaid,
        'totalAmount': friendOwed - friendPaid,
      };
    }).toList();
  }

  Future<void> createPayment({
    required String friendId,
    required double amount,
    required bool currentUserPays,
    Future<void> Function()? reauthenticate,
  }) async {
    final currentPaidShare = currentUserPays ? amount : 0;
    final friendPaidShare = currentUserPays ? 0 : amount;
    final currentOwedShare = friendPaidShare;
    final friendOwedShare = currentPaidShare;
    await _postSplitwise(
      'create_expense',
      {
        'cost': amount.toStringAsFixed(2),
        'description': 'Settlement',
        'currency_code': 'INR',
        'payment': 'true',
        'split_equally': 'false',
        'users__0__user_id': _currentUserId,
        'users__0__paid_share': currentPaidShare.toStringAsFixed(2),
        'users__0__owed_share': currentOwedShare.toStringAsFixed(2),
        'users__1__user_id': friendId,
        'users__1__paid_share': friendPaidShare.toStringAsFixed(2),
        'users__1__owed_share': friendOwedShare.toStringAsFixed(2),
      },
      reauthenticate ?? _missingReauthentication,
    );
  }

  Future<List<SplitwiseGroup>> getGroupsWithMembers({
    Future<void> Function()? reauthenticate,
  }) async {
    final renewSession = reauthenticate ?? _missingReauthentication;

    final config = MySqlConfig.fromDotEnv();
    await _mySqlService.connect(config);

    try {
      final dbFriendsResult = await _mySqlService.executeReadQuery(
        'SELECT ID, SPLITWISE_FRIEND_ID, NAME FROM SplitwiseFriends',
      );

      final splitwiseFriendIdToDbId = <String, int>{};
      final dbFriendsRows = (dbFriendsResult['rows'] as List? ?? []);
      for (final row in dbFriendsRows) {
        final rowMap = Map<String, dynamic>.from(row as Map);
        final splitwiseFriendId = rowMap['SPLITWISE_FRIEND_ID']?.toString();
        final dbId = int.tryParse(rowMap['ID']?.toString() ?? '');
        if (splitwiseFriendId != null &&
            splitwiseFriendId.isNotEmpty &&
            dbId != null) {
          splitwiseFriendIdToDbId[splitwiseFriendId] = dbId;
        }
      }

      final groupsResponse = await _fetchSplitwise('get_groups', renewSession);
      final rawGroups = (groupsResponse['groups'] as List? ?? []);

      final groupsWithMembers = <SplitwiseGroup>[];
      for (final groupItem in rawGroups) {
        final groupMap = Map<String, dynamic>.from(groupItem as Map);
        final groupId = groupMap['id']?.toString();
        if (groupId == null || groupId.isEmpty) {
          continue;
        }

        final groupDetails = await _fetchSplitwise(
          'get_group/$groupId',
          renewSession,
        );

        final groupPayload = groupDetails['group'];
        final membersRaw = groupPayload is Map<String, dynamic>
            ? (groupPayload['members'] as List? ?? [])
            : <dynamic>[];

        final members = membersRaw.map((memberItem) {
          final memberMap = Map<String, dynamic>.from(memberItem as Map);
          final memberId = memberMap['id']?.toString() ?? '';
          final firstName = memberMap['first_name']?.toString() ?? '';
          final lastName = memberMap['last_name']?.toString() ?? '';
          final fullName = '$firstName $lastName'.trim();

          return SplitwiseMember(
            id: memberId,
            friendId: (splitwiseFriendIdToDbId[memberId] ?? '').toString(),
            name: fullName,
          );
        }).toList();

        groupsWithMembers.add(
          SplitwiseGroup(
            id: groupId,
            name: groupMap['name']?.toString() ?? '',
            members: members,
          ),
        );
      }

      return groupsWithMembers;
    } catch (error) {
      debugPrint('Error fetching Splitwise data: $error');
      rethrow;
    } finally {
      await _mySqlService.disconnect();
    }
  }

  Future<void> _missingReauthentication() {
    throw StateError('Splitwise session expired. Please sign in again.');
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _parseFriendBalance(Map<String, dynamic> friend) {
    final balance = friend['balance'] ?? friend['balances'];
    if (balance is List) {
      return balance.whereType<Map>().fold<double>(0, (total, entry) {
        if (entry['currency_code']?.toString() != 'INR') {
          return total;
        }
        return total + _toDouble(entry['amount'] ?? entry['balance']);
      });
    }
    if (balance is Map) {
      return _toDouble(balance['amount'] ?? balance['balance']);
    }
    return _toDouble(friend['amount']);
  }
}
