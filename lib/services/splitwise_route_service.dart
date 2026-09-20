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
        final splitwiseAmount =
            apiFriend == null ? 0.0 : _parseFriendBalance(apiFriend);
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

  Future<List<Map<String, dynamic>>> getUnsettledFriendExpenses({
    required String dbFriendId,
    Future<void> Function()? reauthenticate,
  }) async {
    final friendId = _toInt(dbFriendId);
    if (friendId == null) {
      throw ArgumentError('Invalid friend ID');
    }

    final config = MySqlConfig.fromDotEnv();
    await _mySqlService.connect(config);
    try {
      final result = await _mySqlService.executeReadQuery(
        'SELECT st.SPLITWISE_TRANSACTION_ID, st.TRANSACTION_ID, '
        'st.SPLITED_AMOUNT, t.DATE, t.NOTES '
        'FROM SplitwiseTransactions st '
        'LEFT JOIN Transactions t ON t.ID = st.TRANSACTION_ID '
        'WHERE st.FRIEND_ID = :friendId '
        'AND COALESCE(st.IS_SETTLED, 0) = 0 '
        'ORDER BY t.DATE ASC',
        {'friendId': friendId},
      );
      final rows = result['rows'] as List? ?? const [];
      final expenses = <Map<String, dynamic>>[];
      for (final row in rows.whereType<Map>()) {
        final data = Map<String, dynamic>.from(row);
        final timestamp = _toInt(data['DATE']);
        final expense = <String, dynamic>{
          'id': data['SPLITWISE_TRANSACTION_ID']?.toString() ?? '',
          'transactionId': data['TRANSACTION_ID']?.toString() ?? '',
          'isImported': data['TRANSACTION_ID'] == null,
          'description': data['NOTES']?.toString() ?? 'Splitwise expense',
          'date': timestamp == null
              ? ''
              : DateTime.fromMillisecondsSinceEpoch(timestamp)
                  .toIso8601String(),
          'amount': _toDouble(data['SPLITED_AMOUNT']),
          'totalAmount': _toDouble(data['SPLITED_AMOUNT']),
        };
        if (expense['isImported'] == true &&
            expense['id'].toString().isNotEmpty) {
          final detail = await _fetchSplitwise(
            'get_expense/${expense['id']}',
            reauthenticate ?? _missingReauthentication,
          );
          final splitwiseExpense = detail['expense'];
          if (splitwiseExpense is Map) {
            expense['description'] =
                splitwiseExpense['description']?.toString() ??
                    expense['description'];
            expense['date'] =
                splitwiseExpense['date']?.toString() ?? expense['date'];
          }
        }
        expenses.add(expense);
      }
      return expenses;
    } finally {
      await _mySqlService.disconnect();
    }
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

  Future<void> settleLocalExpenses({
    required String dbFriendId,
    required String bankAccountId,
    required double clientAmount,
    required List<String> selectedSplitwiseTransactionIds,
    Map<String, Map<String, String?>> importedCategories = const {},
    Map<String, Map<String, dynamic>> importedExpenseDetails = const {},
    Map<String, String> updatedDescriptions = const {},
    DateTime? date,
  }) async {
    final friendId = _toInt(dbFriendId);
    final accountId = _toInt(bankAccountId);
    if (friendId == null || accountId == null) {
      throw ArgumentError('Invalid friend or bank account ID');
    }
    final selectedIds = selectedSplitwiseTransactionIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();
    if (selectedIds.isEmpty) {
      throw ArgumentError('Select at least one Splitwise expense');
    }

    final config = MySqlConfig.fromDotEnv();
    await _mySqlService.connect(config);
    try {
      final friendResult = await _mySqlService.executeReadQuery(
        'SELECT NAME FROM SplitwiseFriends WHERE ID = :friendId LIMIT 1',
        {'friendId': friendId},
      );
      final friendRows = friendResult['rows'] as List? ?? const [];
      if (friendRows.isEmpty) {
        throw StateError('Friend not found');
      }
      final friendName =
          Map<String, dynamic>.from(friendRows.first as Map)['NAME']
                  ?.toString() ??
              '';

      final selectedSql = List.generate(
        selectedIds.length,
        (index) => ':splitwiseId$index',
      ).join(', ');
      final splitParams = <String, dynamic>{'friendId': friendId};
      for (var index = 0; index < selectedIds.length; index++) {
        splitParams['splitwiseId$index'] = selectedIds[index];
      }
      final splitsResult = await _mySqlService.executeReadQuery(
        'SELECT st.SPLITWISE_TRANSACTION_ID, st.TRANSACTION_ID, '
        'st.SPLITED_AMOUNT, st.SPLITED_TRANSACTION_ID, t.NOTES, '
        't.CATEGORY_ID, t.SUB_CATEGORY_ID '
        'FROM SplitwiseTransactions st '
        'LEFT JOIN Transactions t ON t.ID = st.TRANSACTION_ID '
        'WHERE st.FRIEND_ID = :friendId AND COALESCE(st.IS_SETTLED, 0) = 0 '
        'AND st.SPLITWISE_TRANSACTION_ID IN ($selectedSql) '
        'ORDER BY t.DATE ASC',
        splitParams,
      );
      final splitRows = splitsResult['rows'] as List? ?? const [];
      final dbAmount = splitRows.whereType<Map>().fold<double>(0, (total, row) {
        return total + _toDouble(row['SPLITED_AMOUNT']);
      });
      if ((dbAmount - clientAmount).abs() > 0.01) {
        throw StateError(
          'Settlement amount must match the DB amount: ${dbAmount.toStringAsFixed(2)}',
        );
      }
      if (dbAmount <= 0) {
        throw StateError('No unpaid Splitwise expenses to settle');
      }

      await _mySqlService.executeWriteQuery('START TRANSACTION');
      try {
        final dummyTransactionIds = splitRows
            .whereType<Map>()
            .map((row) => _toInt(row['SPLITED_TRANSACTION_ID']))
            .whereType<int>()
            .join(', ');
        await _mySqlService.executeWriteQuery(
          'INSERT INTO Transactions '
          '(AMOUNT, DATE, NOTES, FROM_ACCOUNT_ID, CATEGORY_ID, SUB_CATEGORY_ID, TRANSCATION_TYPE) '
          'VALUES (:amount, :date, :notes, :accountId, NULL, NULL, :transactionType)',
          {
            'amount': -clientAmount,
            'date': (date ?? DateTime.now()).millisecondsSinceEpoch,
            'notes': 'Settlement : $friendName [$dummyTransactionIds]',
            'accountId': accountId,
            'transactionType': 5,
          },
        );

        for (final row in splitRows.whereType<Map>()) {
          final split = Map<String, dynamic>.from(row);
          final splitAmount = _toDouble(split['SPLITED_AMOUNT']);
          final dummyTransactionId = _toInt(split['SPLITED_TRANSACTION_ID']);
          final transactionId = _toInt(split['TRANSACTION_ID']);
          final splitwiseTransactionId =
              split['SPLITWISE_TRANSACTION_ID']?.toString() ?? '';
          final categoryAssignment = transactionId == null
              ? importedCategories[splitwiseTransactionId]
              : null;
          final importedExpense = transactionId == null
              ? importedExpenseDetails[splitwiseTransactionId]
              : null;
          final categoryId = categoryAssignment == null
              ? _toInt(split['CATEGORY_ID'])
              : _toInt(categoryAssignment['categoryId']);
          final subCategoryId = categoryAssignment == null
              ? _toInt(split['SUB_CATEGORY_ID'])
              : _toInt(categoryAssignment['subCategoryId']);

          if (transactionId == null && categoryId == null) {
            throw StateError(
              'Select a category for imported Splitwise expense $splitwiseTransactionId',
            );
          }

          if (dummyTransactionId != null) {
            await _mySqlService.executeWriteQuery(
              'UPDATE Transactions SET AMOUNT = AMOUNT - :amount, '
              'NOTES = CASE WHEN NOTES IS NULL OR NOTES = \'\' '
              'THEN CONCAT(:splitwiseId, \' : \', :friendName) '
              'ELSE CONCAT(NOTES, \', \', :friendName) END, '
              'CATEGORY_ID = COALESCE(CATEGORY_ID, :categoryId), '
              'SUB_CATEGORY_ID = COALESCE(SUB_CATEGORY_ID, :subCategoryId) '
              'WHERE ID = :id',
              {
                'amount': splitAmount,
                'splitwiseId': splitwiseTransactionId,
                'friendName': friendName,
                'categoryId': categoryId,
                'subCategoryId': subCategoryId,
                'id': dummyTransactionId,
              },
            );
          }

          if (transactionId == null) {
            final importedDate = DateTime.tryParse(
              importedExpense?['date']?.toString() ?? '',
            );
            final editedDescription =
                updatedDescriptions[splitwiseTransactionId]?.trim();
            final importedDescription = editedDescription?.isNotEmpty == true
                ? editedDescription
                : importedExpense?['description']?.toString().trim();
            await _mySqlService.executeWriteQuery(
              'INSERT INTO Transactions '
              '(AMOUNT, DATE, NOTES, FROM_ACCOUNT_ID, CATEGORY_ID, SUB_CATEGORY_ID, TRANSCATION_TYPE) '
              'VALUES (:amount, :date, :notes, NULL, :categoryId, :subCategoryId, :transactionType)',
              {
                'amount': -splitAmount,
                'date': (importedDate ?? date ?? DateTime.now())
                    .millisecondsSinceEpoch,
                'notes':
                    '${importedDescription?.isNotEmpty == true ? importedDescription : splitwiseTransactionId} : $friendName',
                'categoryId': categoryId,
                'subCategoryId': subCategoryId,
                'transactionType': 1,
              },
            );
            await _mySqlService.executeWriteQuery(
              'DELETE FROM SplitwiseTransactions '
              'WHERE SPLITWISE_TRANSACTION_ID = :splitwiseId '
              'AND FRIEND_ID = :friendId AND TRANSACTION_ID IS NULL '
              'AND COALESCE(IS_SETTLED, 0) = 0',
              {'splitwiseId': splitwiseTransactionId, 'friendId': friendId},
            );
          } else {
            await _mySqlService.executeWriteQuery(
              'UPDATE SplitwiseTransactions SET IS_SETTLED = 1 '
              'WHERE TRANSACTION_ID = :transactionId AND FRIEND_ID = :friendId '
              'AND COALESCE(IS_SETTLED, 0) = 0',
              {'transactionId': transactionId, 'friendId': friendId},
            );
          }
        }
        await _mySqlService.executeWriteQuery('COMMIT');
      } catch (_) {
        await _mySqlService.executeWriteQuery('ROLLBACK');
        rethrow;
      }
    } finally {
      await _mySqlService.disconnect();
    }
  }

  Future<int> syncNotifications({
    Future<void> Function()? reauthenticate,
  }) async {
    final renewSession = reauthenticate ?? _missingReauthentication;
    final config = MySqlConfig.fromDotEnv();
    await _mySqlService.connect(config);

    try {
      final syncTimeResult = await _mySqlService.executeReadQuery(
        'SELECT TIME FROM SplitwiseSyncTime LIMIT 1',
      );
      final syncRows = syncTimeResult['rows'] as List? ?? const [];
      final lastSyncTime = syncRows.isEmpty
          ? null
          : _toInt(Map<String, dynamic>.from(syncRows.first as Map)['TIME']);

      final notifications = await _getNewNotifications(
        lastSyncTime: lastSyncTime,
        reauthenticate: renewSession,
      );
      var importedCount = 0;

      for (final notification in notifications) {
        final source = notification['source'];
        final content = notification['content']?.toString().toLowerCase() ?? '';
        if (source is! Map ||
            source['type']?.toString() != 'Expense' ||
            source['id'] == null ||
            !content.contains('added')) {
          continue;
        }

        final expenseId = source['id'].toString();
        final expenseResponse = await _fetchSplitwise(
          'get_expense/$expenseId',
          renewSession,
        );
        final expense = expenseResponse['expense'];
        if (expense is! Map) {
          continue;
        }

        final repayment = (expense['repayments'] as List? ?? const [])
            .whereType<Map>()
            .cast<Map>()
            .firstWhere(
              (item) => item['from']?.toString() == _currentUserId,
              orElse: () => const <String, dynamic>{},
            );
        final splitwiseFriendId = repayment['to']?.toString();
        final amount = _toDouble(repayment['amount']);
        if (splitwiseFriendId == null ||
            splitwiseFriendId.isEmpty ||
            amount <= 0) {
          continue;
        }

        final existing = await _mySqlService.executeReadQuery(
          'SELECT SPLITWISE_TRANSACTION_ID FROM SplitwiseTransactions '
          'WHERE SPLITWISE_TRANSACTION_ID = :expenseId LIMIT 1',
          {'expenseId': expenseId},
        );
        if ((existing['rows'] as List? ?? const []).isNotEmpty) {
          continue;
        }

        final friendResult = await _mySqlService.executeReadQuery(
          'SELECT ID FROM SplitwiseFriends '
          'WHERE SPLITWISE_FRIEND_ID = :friendId LIMIT 1',
          {'friendId': splitwiseFriendId},
        );
        final friendRows = friendResult['rows'] as List? ?? const [];
        if (friendRows.isEmpty) {
          continue;
        }

        final localFriendId = _toInt(
          Map<String, dynamic>.from(friendRows.first as Map)['ID'],
        );
        if (localFriendId == null) {
          continue;
        }

        await _mySqlService.executeWriteQuery(
          'INSERT INTO SplitwiseTransactions '
          '(SPLITWISE_TRANSACTION_ID, FRIEND_ID, SPLITED_AMOUNT, IS_SETTLED) '
          'VALUES (:expenseId, :friendId, :amount, 0)',
          {
            'expenseId': expenseId,
            'friendId': localFriendId,
            'amount': amount,
          },
        );
        importedCount++;
      }

      await _mySqlService.executeWriteQuery('DELETE FROM SplitwiseSyncTime');
      await _mySqlService.executeWriteQuery(
        'INSERT INTO SplitwiseSyncTime (TIME) VALUES (:time)',
        {'time': DateTime.now().millisecondsSinceEpoch},
      );
      return importedCount;
    } finally {
      await _mySqlService.disconnect();
    }
  }

  Future<List<Map<String, dynamic>>> _getNewNotifications({
    required int? lastSyncTime,
    required Future<void> Function() reauthenticate,
  }) async {
    var limit = 50;
    var matchingNotifications = <Map<String, dynamic>>[];

    while (matchingNotifications.isEmpty && limit <= 200) {
      final response = await _fetchSplitwise(
        'get_notifications?limit=$limit',
        reauthenticate,
      );
      final notifications = (response['notifications'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (notifications.isEmpty) {
        break;
      }

      matchingNotifications = notifications.where((notification) {
        final content = notification['content']?.toString().toLowerCase() ?? '';
        final createdBy = notification['created_by']?.toString();
        final createdAt =
            DateTime.tryParse(notification['created_at']?.toString() ?? '');
        final isAfterLastSync = lastSyncTime == null ||
            (createdAt != null &&
                createdAt.millisecondsSinceEpoch > lastSyncTime);
        return !content.contains('settle all balance') &&
            createdBy != _currentUserId &&
            isAfterLastSync;
      }).toList();

      final oldest = DateTime.tryParse(
        notifications.last['created_at']?.toString() ?? '',
      );
      if (lastSyncTime != null &&
          oldest != null &&
          oldest.millisecondsSinceEpoch <= lastSyncTime) {
        break;
      }
      limit += 50;
    }

    return matchingNotifications;
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

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
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
