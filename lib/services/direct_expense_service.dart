import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'mysql_service.dart';

class DirectExpenseService {
  static const int _transactionTypeExpense = 1;

  static Future<Map<String, dynamic>> addExpense({
    required double amount,
    double charges = 0,
    required String date,
    required Map<String, dynamic> account,
    String? description,
    String? categoryId,
    String? subCategoryId,
    String? capId,
    bool includeSplitwise = false,
    String? splitwiseGroupId,
    List<String>? splitwiseUserIds,
    String? splitType,
    Map<String, double>? customAmounts,
  }) async {
    final parsedAccount = _parseAccount(account);
    final epochTime = _parseDateToEpoch(date);
    final shouldUseSplitwise = includeSplitwise &&
        splitwiseGroupId != null &&
        splitwiseGroupId.trim().isNotEmpty &&
        splitwiseUserIds != null &&
        splitwiseUserIds.isNotEmpty;

    final splitPayload = shouldUseSplitwise
        ? _buildSplitPayload(
            amount: amount,
            splitwiseUserIds: splitwiseUserIds,
            splitType: splitType,
            customAmounts: customAmounts,
          )
        : null;

    final config = MySqlConfig.fromDotEnv();
    final service = MySqlService();
    await service.connect(config);

    try {
      String? splitwiseTransactionId;

      if (shouldUseSplitwise && splitPayload != null) {
        final splitwiseResponse = await _createSplitwiseExpense(
          amount: splitPayload.total,
          description: (description == null || description.trim().isEmpty)
              ? 'No description'
              : description,
          groupId: splitwiseGroupId,
          userIds: splitwiseUserIds,
          splitType: 'custom',
          customAmounts: splitPayload.customAmounts,
          date: date,
        );
        splitwiseTransactionId =
            splitwiseResponse['expenses']?[0]?['id']?.toString() ??
                splitwiseResponse['id']?.toString();
      }

      await service.executeWriteQuery('START TRANSACTION');
      try {
        final transactionId = await _insertExpenseTransaction(
          service: service,
          amount: amount,
          epochTime: epochTime,
          description: description,
          accountId: parsedAccount.id,
          categoryId: categoryId,
          subCategoryId: subCategoryId,
        );

        if (shouldUseSplitwise &&
            splitPayload != null &&
            splitwiseTransactionId != null) {
          final userMapping = await _createSplitwiseToDbMapping(service);
          final dummyTxId = await _insertDummyTransaction(
            service: service,
            epochTime: epochTime,
            description: description,
            categoryId: categoryId,
            subCategoryId: subCategoryId,
          );

          for (final userId in splitwiseUserIds) {
            if (_isCurrentUser(userId)) {
              continue;
            }

            final dbFriendId = userMapping[userId];
            if (dbFriendId == null) {
              continue;
            }

            final splitAmount = splitPayload.customAmounts[userId];
            if (splitAmount == null) {
              throw StateError('Custom amount not found for user $userId');
            }

            await _insertSplitwiseTransaction(
              service: service,
              splitwiseTransactionId: splitwiseTransactionId,
              transactionId: transactionId,
              friendId: dbFriendId,
              splitAmount: splitAmount,
              splitedTransactionId: dummyTxId,
            );
          }
        }

        if (capId != null &&
            capId.trim().isNotEmpty &&
            parsedAccount.type == 'Credit Card') {
          await _insertCreditCardTransaction(
            service: service,
            transactionId: transactionId,
            creditCardId: parsedAccount.id,
            capId: capId,
            amount: amount,
          );
        }

        if (charges > 0) {
          final chargesCategory = await _getChargesCategoryIds(service);
          await _insertExpenseTransaction(
            service: service,
            amount: charges,
            epochTime: epochTime,
            description: 'Charges for $transactionId',
            accountId: parsedAccount.id,
            categoryId: chargesCategory.categoryId,
            subCategoryId: chargesCategory.subCategoryId,
          );
        }

        await service.executeWriteQuery('COMMIT');
        return {
          'success': true,
          'message': 'Expense added successfully.',
          'transactionId': transactionId,
          'splitwiseTransactionId': splitwiseTransactionId,
        };
      } catch (error) {
        await service.executeWriteQuery('ROLLBACK');
        rethrow;
      }
    } finally {
      await service.disconnect();
    }
  }

  static Future<Map<String, dynamic>> updateExpense({
    required String id,
    required double amount,
    double charges = 0,
    required String date,
    required Map<String, dynamic> account,
    required String categoryId,
    String? subCategoryId,
    String? description,
    String? capId,
    bool updateSplitwise = true,
    bool includeSplitwise = false,
    String? splitwiseGroupId,
    List<String>? splitwiseUserIds,
    String? splitType,
    Map<String, double>? customAmounts,
  }) async {
    final transactionId = int.tryParse(id);
    if (transactionId == null || transactionId <= 0) {
      throw ArgumentError('Invalid transaction id: $id');
    }

    final parsedAccount = _parseAccount(account);
    final epochTime = _parseDateToEpoch(date);

    final shouldUseSplitwise = includeSplitwise &&
        splitwiseGroupId != null &&
        splitwiseGroupId.trim().isNotEmpty &&
        splitwiseUserIds != null &&
        splitwiseUserIds.isNotEmpty;

    final splitPayload = shouldUseSplitwise
        ? _buildSplitPayload(
            amount: amount,
            splitwiseUserIds: splitwiseUserIds,
            splitType: splitType,
            customAmounts: customAmounts,
          )
        : null;

    final config = MySqlConfig.fromDotEnv();
    final service = MySqlService();
    await service.connect(config);

    try {
      await service.executeWriteQuery('START TRANSACTION');
      try {
        await service.executeWriteQuery(
          '''
UPDATE Transactions
SET DATE = :date,
    NOTES = :notes,
    AMOUNT = :amount,
    FROM_ACCOUNT_ID = :fromAccountId,
    CATEGORY_ID = :categoryId,
    SUB_CATEGORY_ID = :subCategoryId
WHERE ID = :id AND TRANSCATION_TYPE = :transactionType
''',
          {
            'date': epochTime,
            'notes': (description ?? '').trim(),
            'amount': amount,
            'fromAccountId': parsedAccount.id,
            'categoryId': int.parse(categoryId),
            'subCategoryId': _parseNullableInt(subCategoryId),
            'id': transactionId,
            'transactionType': _transactionTypeExpense,
          },
        );

        if (parsedAccount.type == 'Credit Card') {
          await service.executeWriteQuery(
            'DELETE FROM CreditCardTransactions WHERE TransactionId = :id',
            {'id': transactionId},
          );

          if (capId != null && capId.trim().isNotEmpty) {
            await _insertCreditCardTransaction(
              service: service,
              transactionId: transactionId,
              creditCardId: parsedAccount.id,
              capId: capId,
              amount: amount,
            );
          }
        }

        if (updateSplitwise) {
          final existingSplitwiseRows = await service.executeReadQuery(
            '''
SELECT SPLITWISE_TRANSACTION_ID, FRIEND_ID, SPLITED_TRANSACTION_ID
FROM SplitwiseTransactions
WHERE TRANSACTION_ID = $transactionId
''',
          );

          final existingRows =
              (existingSplitwiseRows['rows'] as List? ?? const <dynamic>[])
                  .map((row) => Map<String, dynamic>.from(row as Map))
                  .toList();

          if (existingRows.isNotEmpty) {
            final splitwiseIds = existingRows
                .map((row) => row['SPLITWISE_TRANSACTION_ID']?.toString() ?? '')
                .where((value) => value.isNotEmpty)
                .toSet();

            for (final splitwiseId in splitwiseIds) {
              await _deleteSplitwiseExpense(splitwiseId);
            }

            final dummyTxIds = existingRows
                .map((row) => _toInt(row['SPLITED_TRANSACTION_ID']))
                .where((id) => id != null)
                .cast<int>()
                .toSet();

            await service.executeWriteQuery(
              'DELETE FROM SplitwiseTransactions WHERE TRANSACTION_ID = :id',
              {'id': transactionId},
            );

            for (final dummyTxId in dummyTxIds) {
              await service.executeWriteQuery(
                'DELETE FROM Transactions WHERE ID = :id AND AMOUNT = 0',
                {'id': dummyTxId},
              );
            }
          }

          if (shouldUseSplitwise && splitPayload != null) {
            final splitwiseResponse = await _createSplitwiseExpense(
              amount: splitPayload.total,
              description: (description == null || description.trim().isEmpty)
                  ? 'No description'
                  : description,
              groupId: splitwiseGroupId,
              userIds: splitwiseUserIds,
              splitType: 'custom',
              customAmounts: splitPayload.customAmounts,
              date: date,
            );

            final splitwiseTransactionId =
                splitwiseResponse['expenses']?[0]?['id']?.toString() ??
                    splitwiseResponse['id']?.toString();

            if (splitwiseTransactionId != null) {
              final userMapping = await _createSplitwiseToDbMapping(service);
              final dummyTxId = await _insertDummyTransaction(
                service: service,
                epochTime: epochTime,
                description: description,
                categoryId: categoryId,
                subCategoryId: subCategoryId,
              );

              for (final userId in splitwiseUserIds) {
                if (_isCurrentUser(userId)) {
                  continue;
                }

                final dbFriendId = userMapping[userId];
                if (dbFriendId == null) {
                  continue;
                }

                final splitAmount = splitPayload.customAmounts[userId];
                if (splitAmount == null) {
                  throw StateError('Custom amount not found for user $userId');
                }

                await _insertSplitwiseTransaction(
                  service: service,
                  splitwiseTransactionId: splitwiseTransactionId,
                  transactionId: transactionId,
                  friendId: dbFriendId,
                  splitAmount: splitAmount,
                  splitedTransactionId: dummyTxId,
                );
              }
            }
          }
        }

        if (charges > 0) {
          final chargesCategory = await _getChargesCategoryIds(service);
          await _insertExpenseTransaction(
            service: service,
            amount: charges,
            epochTime: epochTime,
            description: 'Charges for $id',
            accountId: parsedAccount.id,
            categoryId: chargesCategory.categoryId,
            subCategoryId: chargesCategory.subCategoryId,
          );
        }

        await service.executeWriteQuery('COMMIT');
        return {
          'success': true,
          'message': 'Expense updated successfully.',
        };
      } catch (error) {
        await service.executeWriteQuery('ROLLBACK');
        rethrow;
      }
    } finally {
      await service.disconnect();
    }
  }

  static _ParsedAccount _parseAccount(Map<String, dynamic> account) {
    final id = account['id']?.toString() ?? '';
    final type = account['type']?.toString() ?? '';

    final parsedId = int.tryParse(id);
    if (parsedId == null || parsedId <= 0) {
      throw ArgumentError('Invalid account id: $id');
    }

    if (type != 'Bank' && type != 'Credit Card') {
      throw ArgumentError('Invalid account type: $type');
    }

    return _ParsedAccount(id: parsedId, type: type);
  }

  static int _parseDateToEpoch(String date) {
    try {
      return DateTime.parse(date).millisecondsSinceEpoch;
    } catch (_) {
      throw ArgumentError('Invalid date: $date. Expected yyyy-MM-dd');
    }
  }

  static _SplitPayload _buildSplitPayload({
    required double amount,
    required List<String> splitwiseUserIds,
    required String? splitType,
    required Map<String, double>? customAmounts,
  }) {
    if (splitwiseUserIds.isEmpty) {
      throw ArgumentError('splitwiseUserIds cannot be empty');
    }

    final shouldUseCustom =
        splitType == 'custom' && customAmounts != null && customAmounts.isNotEmpty;

    if (shouldUseCustom) {
      final total = customAmounts.values.fold<double>(0, (sum, v) => sum + v);
      if ((total - amount).abs() > 0.01) {
        throw StateError(
          'Custom amounts must total the expense amount. Total: $total, Expected: $amount',
        );
      }
      return _SplitPayload(customAmounts: Map<String, double>.from(customAmounts), total: total);
    }

    final totalCents = (amount * 100).round();
    final baseCents = totalCents ~/ splitwiseUserIds.length;
    final remainderCents = totalCents - (baseCents * splitwiseUserIds.length);

    final computed = <String, double>{};
    for (var i = 0; i < splitwiseUserIds.length; i++) {
      final cents = baseCents + (i < remainderCents ? 1 : 0);
      computed[splitwiseUserIds[i]] = cents / 100;
    }

    final total = computed.values.fold<double>(0, (sum, v) => sum + v);
    return _SplitPayload(customAmounts: computed, total: total);
  }

  static Future<Map<String, int>> _createSplitwiseToDbMapping(
    MySqlService service,
  ) async {
    final results = await service.executeReadQuery(
      '''
SELECT ID, SPLITWISE_FRIEND_ID
FROM SplitwiseFriends
WHERE SPLITWISE_FRIEND_ID IS NOT NULL
''',
    );

    final mapping = <String, int>{};
    final rows = (results['rows'] as List? ?? const <dynamic>[]);
    for (final row in rows) {
      final rowMap = Map<String, dynamic>.from(row as Map);
      final splitwiseId = rowMap['SPLITWISE_FRIEND_ID']?.toString();
      final dbId = _toInt(rowMap['ID']);
      if (splitwiseId != null && splitwiseId.isNotEmpty && dbId != null) {
        mapping[splitwiseId] = dbId;
      }
    }

    return mapping;
  }

  static Future<int> _insertExpenseTransaction({
    required MySqlService service,
    required double amount,
    required int epochTime,
    required String? description,
    required int accountId,
    required String? categoryId,
    required String? subCategoryId,
  }) async {
    await service.executeWriteQuery(
      '''
INSERT INTO Transactions (
    DATE,
    NOTES,
    AMOUNT,
    FROM_ACCOUNT_ID,
    CATEGORY_ID,
    SUB_CATEGORY_ID,
    TRANSCATION_TYPE
) VALUES (
    :date,
    :notes,
    :amount,
    :fromAccountId,
    :categoryId,
    :subCategoryId,
    :transactionType
)
''',
      {
        'date': epochTime,
        'notes': (description ?? '').trim(),
        'amount': amount,
        'fromAccountId': accountId,
        'categoryId': _parseNullableInt(categoryId),
        'subCategoryId': _parseNullableInt(subCategoryId),
        'transactionType': _transactionTypeExpense,
      },
    );

    return _readLastInsertId(service);
  }

  static Future<int> _insertDummyTransaction({
    required MySqlService service,
    required int epochTime,
    required String? description,
    required String? categoryId,
    required String? subCategoryId,
  }) async {
    await service.executeWriteQuery(
      '''
INSERT INTO Transactions (
    DATE,
    NOTES,
    AMOUNT,
    FROM_ACCOUNT_ID,
    CATEGORY_ID,
    SUB_CATEGORY_ID,
    TRANSCATION_TYPE
) VALUES (
    :date,
    :notes,
    0,
    NULL,
    :categoryId,
    :subCategoryId,
    :transactionType
)
''',
      {
        'date': epochTime,
        'notes': (description ?? '').trim(),
        'categoryId': _parseNullableInt(categoryId),
        'subCategoryId': _parseNullableInt(subCategoryId),
        'transactionType': _transactionTypeExpense,
      },
    );

    return _readLastInsertId(service);
  }

  static Future<void> _insertSplitwiseTransaction({
    required MySqlService service,
    required String splitwiseTransactionId,
    required int transactionId,
    required int friendId,
    required double splitAmount,
    required int splitedTransactionId,
  }) async {
    await service.executeWriteQuery(
      '''
INSERT INTO SplitwiseTransactions (
    SPLITWISE_TRANSACTION_ID,
    TRANSACTION_ID,
    FRIEND_ID,
    SPLITED_AMOUNT,
    SPLITED_TRANSACTION_ID
) VALUES (
    :splitwiseTransactionId,
    :transactionId,
    :friendId,
    :splitAmount,
    :splitedTransactionId
)
''',
      {
        'splitwiseTransactionId': splitwiseTransactionId,
        'transactionId': transactionId,
        'friendId': friendId,
        'splitAmount': splitAmount,
        'splitedTransactionId': splitedTransactionId,
      },
    );
  }

  static Future<void> _insertCreditCardTransaction({
    required MySqlService service,
    required int transactionId,
    required int creditCardId,
    required String capId,
    required double amount,
  }) async {
    final parsedCapId = int.tryParse(capId);
    if (parsedCapId == null || parsedCapId <= 0) {
      throw ArgumentError('Invalid capId: $capId');
    }

    final capRowsResult = await service.executeReadQuery(
      'SELECT CAP_PERCENTAGE, REWARD_PER_AMOUNT FROM CreditCardCapDetails WHERE ID = $parsedCapId',
    );
    final rows = (capRowsResult['rows'] as List? ?? const <dynamic>[]);
    if (rows.isEmpty) {
      return;
    }

    final rowMap = Map<String, dynamic>.from(rows.first as Map);
    final capPercentage = _toDouble(rowMap['CAP_PERCENTAGE']);
    final rewardPerAmount = _toDouble(rowMap['REWARD_PER_AMOUNT']);
    final denominator = rewardPerAmount == 0 ? 100 : rewardPerAmount;
    final rewards = (amount.truncate() * capPercentage) / denominator;

    await service.executeWriteQuery(
      '''
INSERT INTO CreditCardTransactions (
    TransactionId,
    CreditCardId,
    CapId,
    Rewards
) VALUES (
    :transactionId,
    :creditCardId,
    :capId,
    :rewards
)
''',
      {
        'transactionId': transactionId,
        'creditCardId': creditCardId,
        'capId': parsedCapId,
        'rewards': rewards,
      },
    );
  }

  static Future<_ChargesCategoryIds> _getChargesCategoryIds(
    MySqlService service,
  ) async {
    final catResult =
        await service.executeReadQuery("SELECT ID FROM Category WHERE CATEGORY_NAME = 'Charges' LIMIT 1");
    final catRows = (catResult['rows'] as List? ?? const <dynamic>[]);
    if (catRows.isEmpty) {
      throw StateError('Charges category not found in database');
    }

    final catId = _toInt(Map<String, dynamic>.from(catRows.first as Map)['ID']);
    if (catId == null) {
      throw StateError('Charges category id is invalid');
    }

    final subResult = await service.executeReadQuery(
      "SELECT ID FROM SubCategory WHERE CATEGORY_ID = $catId AND SUB_CATEGORY_NAME = 'Platform Fee' LIMIT 1",
    );
    final subRows = (subResult['rows'] as List? ?? const <dynamic>[]);
    final subId = subRows.isEmpty
        ? null
        : _toInt(Map<String, dynamic>.from(subRows.first as Map)['ID']);

    return _ChargesCategoryIds(categoryId: catId.toString(), subCategoryId: subId?.toString());
  }

  static Future<int> _readLastInsertId(MySqlService service) async {
    final result = await service.executeReadQuery('SELECT LAST_INSERT_ID() AS id');
    final rows = (result['rows'] as List? ?? const <dynamic>[]);
    if (rows.isEmpty) {
      throw StateError('Unable to resolve inserted id from MySQL');
    }

    final rowMap = Map<String, dynamic>.from(rows.first as Map);
    final insertedId = _toInt(rowMap['id'] ?? rowMap['ID']);
    if (insertedId == null || insertedId <= 0) {
      throw StateError('Unable to resolve inserted id from MySQL');
    }
    return insertedId;
  }

  static Future<Map<String, dynamic>> _createSplitwiseExpense({
    required double amount,
    required String description,
    required String groupId,
    required List<String> userIds,
    required String splitType,
    required Map<String, double> customAmounts,
    required String date,
  }) async {
    final apiKey = _getRequiredEnv('SPLITWISE_API_KEY');

    final fields = <String, String>{
      'cost': amount.toString(),
      'description': description,
      'group_id': groupId,
      'currency_code': 'INR',
      'details': 'string',
      'date': DateTime.parse(date).toIso8601String(),
      'split_equally': (splitType == 'equal').toString(),
    };

    if (splitType == 'equal') {
      final totalCents = (amount * 100).round();
      final baseCents = totalCents ~/ userIds.length;
      final remainderCents = totalCents - (baseCents * userIds.length);

      final perUser = <String>[];
      for (var i = 0; i < userIds.length; i++) {
        final cents = baseCents + (i < remainderCents ? 1 : 0);
        perUser.add((cents / 100).toStringAsFixed(2));
      }

      fields['users__0__user_id'] = _currentUserId;
      fields['users__0__paid_share'] = amount.toString();
      final currentUserIndex = userIds.indexOf(_currentUserId);
      if (currentUserIndex != -1) {
        fields['users__0__owed_share'] = perUser[currentUserIndex];
      }

      for (var i = 0; i < userIds.length; i++) {
        final userId = userIds[i];
        if (_isCurrentUser(userId)) {
          continue;
        }
        final userIndex = i + 1;
        fields['users__${userIndex}__user_id'] = userId;
        fields['users__${userIndex}__paid_share'] = '0.00';
        fields['users__${userIndex}__owed_share'] = perUser[i];
      }
    } else {
      var userIndex = 0;
      fields['users__${userIndex}__user_id'] = _currentUserId;
      fields['users__${userIndex}__paid_share'] = amount.toString();
      final currentOwed = customAmounts[_currentUserId] ?? 0;
      fields['users__${userIndex}__owed_share'] = currentOwed.toStringAsFixed(2);
      userIndex++;

      for (final userId in userIds) {
        if (_isCurrentUser(userId)) {
          continue;
        }

        final owedAmount = customAmounts[userId] ?? 0;
        fields['users__${userIndex}__user_id'] = userId;
        fields['users__${userIndex}__paid_share'] = '0.00';
        fields['users__${userIndex}__owed_share'] = owedAmount.toStringAsFixed(2);
        userIndex++;
      }
    }

    final body = fields.entries
        .map((entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');

    final response = await http.post(
      Uri.parse('https://secure.splitwise.com/api/v3.0/create_expense'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Splitwise API failed: ${response.statusCode} - ${response.body}',
      );
    }

    final parsed = jsonDecode(response.body);
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('Unexpected Splitwise response format');
    }

    if (parsed['errors'] is Map && (parsed['errors'] as Map)['base'] != null) {
      throw StateError((parsed['errors'] as Map)['base'].toString());
    }

    return parsed;
  }

  static Future<void> _deleteSplitwiseExpense(String splitwiseTransactionId) async {
    final apiKey = dotenv.env['SPLITWISE_API_KEY']?.trim() ?? '';
    if (apiKey.isEmpty) {
      return;
    }

    final response = await http.post(
      Uri.parse(
        'https://secure.splitwise.com/api/v3.0/delete_expense/$splitwiseTransactionId',
      ),
      headers: {
        'Authorization': 'Bearer $apiKey',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Non-blocking to mimic route.ts behavior where old deletion failures are warnings.
      return;
    }
  }

  static String get _currentUserId =>
      (dotenv.env['SPLITWISE_CURRENT_USER_ID'] ?? '57391213').trim();

  static bool _isCurrentUser(String userId) {
    return userId.trim() == _currentUserId;
  }

  static String _getRequiredEnv(String key) {
    final value = dotenv.env[key]?.trim() ?? '';
    if (value.isEmpty) {
      throw StateError('$key is not configured');
    }
    return value;
  }

  static int? _parseNullableInt(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return int.tryParse(value);
  }

  static int? _toInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  static double _toDouble(dynamic value) {
    if (value == null) {
      return 0;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString()) ?? 0;
  }
}

class _ParsedAccount {
  const _ParsedAccount({required this.id, required this.type});

  final int id;
  final String type;
}

class _SplitPayload {
  const _SplitPayload({
    required this.customAmounts,
    required this.total,
  });

  final Map<String, double> customAmounts;
  final double total;
}

class _ChargesCategoryIds {
  const _ChargesCategoryIds({
    required this.categoryId,
    required this.subCategoryId,
  });

  final String categoryId;
  final String? subCategoryId;
}
