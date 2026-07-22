import 'package:flutter/foundation.dart' hide Category;
import 'package:finance_app/models/models.dart';
import 'package:finance_app/services/mysql_service.dart';

class ActiveAccountsResult {
    const ActiveAccountsResult({
        this.bankAccounts = const [],
        this.creditCardAccounts = const [],
        this.investmentAccounts = const [],
    });

    final List<BankAccount> bankAccounts;
    final List<CreditCardAccount> creditCardAccounts;
    final List<InvestmentAccount> investmentAccounts;
}

class DirectSqlService 
{
    static double _toDouble(dynamic value) {
        if (value == null) {
            return 0;
        }
        if (value is num) {
            return value.toDouble();
        }
        if (value is String) {
            return double.tryParse(value) ?? 0;
        }
        return 0;
    }

    static int _monthToNumber(String month) {
        final normalized = month.trim().toLowerCase();
        switch (normalized) {
            case '1':
            case '01':
            case 'jan':
            case 'january':
                return 1;
            case '2':
            case '02':
            case 'feb':
            case 'february':
                return 2;
            case '3':
            case '03':
            case 'mar':
            case 'march':
                return 3;
            case '4':
            case '04':
            case 'apr':
            case 'april':
                return 4;
            case '5':
            case '05':
            case 'may':
                return 5;
            case '6':
            case '06':
            case 'jun':
            case 'june':
                return 6;
            case '7':
            case '07':
            case 'jul':
            case 'july':
                return 7;
            case '8':
            case '08':
            case 'aug':
            case 'august':
                return 8;
            case '9':
            case '09':
            case 'sep':
            case 'sept':
            case 'september':
                return 9;
            case '10':
            case 'oct':
            case 'october':
                return 10;
            case '11':
            case 'nov':
            case 'november':
                return 11;
            case '12':
            case 'dec':
            case 'december':
                return 12;
            default:
                throw FormatException('Invalid month value: $month');
        }
    }

    static ({int fromTimestamp, int toTimestamp}) _getMonthRangeTimestamps(String month, String year) {
        final monthNumber = _monthToNumber(month);
        final yearNumber = int.tryParse(year);
        if (yearNumber == null || yearNumber < 1970) {
            throw FormatException('Invalid year value: $year');
        }

        final startOfMonth = DateTime(yearNumber, monthNumber, 1);
        final startOfNextMonth = monthNumber == 12
            ? DateTime(yearNumber + 1, 1, 1)
            : DateTime(yearNumber, monthNumber + 1, 1);

        // DATE is stored as epoch in bigint; use inclusive end-of-month range.
        final fromTimestamp = startOfMonth.millisecondsSinceEpoch;
        final toTimestamp = startOfNextMonth.millisecondsSinceEpoch - 1;
        return (fromTimestamp: fromTimestamp, toTimestamp: toTimestamp);
    }

    static String _mapTransactionType(dynamic value) {
        final typeValue = int.tryParse(value?.toString() ?? '') ?? 0;
        switch (typeValue) {
            case 1:
                return 'expense';
            case 2:
                return 'income';
            case 3:
                return 'transfer';
            case 4:
                return 'investment';
            default:
                return 'unknown';
        }
    }

    static Future<ActiveAccountsResult> getAllActiveAccounts() async
    {
        String sql = "SELECT ID,ACCOUNT_NAME,CURRENT_BALANCE, INITIAL_BALANCE, ACCOUNT_TYPE, IMG FROM Accounts WHERE IS_ACTIVE = 1";
        MySqlConfig config = MySqlConfig.fromDotEnv();
        MySqlService service = MySqlService();
        await service.connect(config);
        final results = await service.executeReadQuery(sql);

        final bankAccounts = <BankAccount>[];
        final creditCardAccounts = <CreditCardAccount>[];
        final investmentAccounts = <InvestmentAccount>[];

        for (final row in results['rows'] as List) 
        {
            final rowMap = Map<String, dynamic>.from(row as Map);
            final accountType = int.tryParse(rowMap['ACCOUNT_TYPE'].toString()) ?? 0;

            if (accountType == 1) {
                bankAccounts.add(
                    BankAccount.fromJson({
                        'id': rowMap['ID'],
                        'name': rowMap['ACCOUNT_NAME'],
                        'currentBalance': rowMap['CURRENT_BALANCE'],
                        'initialBalance': rowMap['INITIAL_BALANCE'],
                        'isActive': true,
                        'logo': rowMap['IMG'],
                    }),
                );
            } else if (accountType == 2) {
                creditCardAccounts.add(
                    CreditCardAccount.fromJson({
                        'id': rowMap['ID'],
                        'name': rowMap['ACCOUNT_NAME'],
                        'usedAmount': rowMap['CURRENT_BALANCE'],
                        'totalLimit': rowMap['INITIAL_BALANCE'],
                        'availableCredit': 0,
                        'rewardPoints': 0,
                        'isActive': true,
                        'logo': rowMap['IMG'],
                    }),
                );
            } else if (accountType == 3) {
                investmentAccounts.add(
                    InvestmentAccount.fromJson({
                        'id': rowMap['ID'],
                        'name': rowMap['ACCOUNT_NAME'],
                        'totalInvested': rowMap['CURRENT_BALANCE'],
                        'currentValue': 0,
                        'totalWithdraw': 0,
                        'xirr': 0,
                        'isActive': true,
                    }),
                );
            }
        }

        return ActiveAccountsResult(
            bankAccounts: bankAccounts,
            creditCardAccounts: creditCardAccounts,
            investmentAccounts: investmentAccounts,
        );
    }

    static Future<List<TransactionModel>> getAllTransactions(String month, String year) async
    {
        final range = _getMonthRangeTimestamps(month, year);
        final fromTimestamp = range.fromTimestamp;
        final toTimestamp = range.toTimestamp;

        final sql = "SELECT "
            "t.ID AS id, "
            "t.DATE AS date, "
            "t.NOTES AS description, "
            "t.AMOUNT AS amount, "
            "t.TRANSCATION_TYPE AS transaction_type, "
            "t.CATEGORY_ID AS category_id, "
            "t.SUB_CATEGORY_ID AS sub_category_id, "
            "t.FROM_ACCOUNT_ID AS from_account_id, "
            "t.TO_ACCOUNT_ID AS to_account_id, "
            "c.CATEGORY_NAME AS category_name, "
            "s.SUB_CATEGORY_NAME AS sub_category_name, "
            "fa.ACCOUNT_NAME AS from_account_name, "
            "ta.ACCOUNT_NAME AS to_account_name "
            "FROM Transactions t "
            "LEFT JOIN Category c ON c.ID = t.CATEGORY_ID "
            "LEFT JOIN SubCategory s ON s.ID = t.SUB_CATEGORY_ID "
            "LEFT JOIN Accounts fa ON fa.ID = t.FROM_ACCOUNT_ID "
            "LEFT JOIN Accounts ta ON ta.ID = t.TO_ACCOUNT_ID "
            "WHERE t.DATE >= $fromTimestamp AND t.DATE <= $toTimestamp "
            "ORDER BY t.DATE DESC, t.ID DESC";

        debugPrint('getAllTransactions SQL:\n$sql', wrapWidth: 1024);
        final config = MySqlConfig.fromDotEnv();
        final service = MySqlService();
        await service.connect(config);
        final results = await service.executeReadQuery(sql);

        final rows = (results['rows'] as List? ?? []);
        final transactionIds = rows
            .map((row) => Map<String, dynamic>.from(row as Map)['id']?.toString())
            .where((id) => id != null && id.isNotEmpty)
            .cast<String>()
            .toList();

        final splitwiseByTransaction = <String, List<Map<String, dynamic>>>{};
        if (transactionIds.isNotEmpty) {
            final inClause = transactionIds.join(',');
            final splitwiseSql = "SELECT "
                "st.TRANSACTION_ID AS transaction_id, "
                "st.SPLITWISE_TRANSACTION_ID AS splitwise_transaction_id, "
                "st.SPLITED_AMOUNT AS splited_amount, "
                "sf.ID AS db_friend_id, "
                "sf.SPLITWISE_FRIEND_ID AS splitwise_friend_id, "
                "sf.NAME AS friend_name "
                "FROM SplitwiseTransactions st "
                "JOIN SplitwiseFriends sf ON sf.ID = st.FRIEND_ID "
                "WHERE st.TRANSACTION_ID IN ($inClause) "
                "ORDER BY st.TRANSACTION_ID, sf.NAME";
            debugPrint('getAllTransactions splitwise SQL:\n$splitwiseSql', wrapWidth: 1024);
            final splitwiseResults = await service.executeReadQuery(splitwiseSql);
            final splitwiseRows = (splitwiseResults['rows'] as List? ?? []);
            for (final splitwiseRow in splitwiseRows) {
                final splitwiseMap = Map<String, dynamic>.from(splitwiseRow as Map);
                final transactionId = splitwiseMap['transaction_id']?.toString();
                if (transactionId == null || transactionId.isEmpty) {
                    continue;
                }
                final splitwiseFriendId = splitwiseMap['splitwise_friend_id']?.toString();
                final dbFriendId = splitwiseMap['db_friend_id']?.toString();
                splitwiseByTransaction.putIfAbsent(transactionId, () => []).add({
                    'splitwiseTransactionId': splitwiseMap['splitwise_transaction_id']?.toString() ?? '',
                    'friendId': splitwiseFriendId ?? dbFriendId ?? '',
                    'userId': splitwiseFriendId ?? dbFriendId ?? '',
                    'splitwiseUserId': splitwiseFriendId ?? dbFriendId ?? '',
                    'friendName': splitwiseMap['friend_name']?.toString() ?? '',
                    'splitedAmount': _toDouble(splitwiseMap['splited_amount']),
                });
            }
        }

        return rows.map((row) {
            final rowMap = Map<String, dynamic>.from(row as Map);
            final transactionId = rowMap['id']?.toString() ?? '';
            final type = _mapTransactionType(rowMap['transaction_type']);
            final isTransfer = type == 'transfer';
            final isInvestment = type == 'investment';
            final splitwiseDetails = splitwiseByTransaction[transactionId] ?? const <Map<String, dynamic>>[];
            final splitwiseUserIds = splitwiseDetails
                .map((detail) => (detail['splitwiseUserId'] ?? detail['friendId'])?.toString())
                .where((id) => id != null && id.isNotEmpty)
                .cast<String>()
                .toList();

            return TransactionModel.fromJson({
                'id': rowMap['id'],
                'date': rowMap['date'],
                'description': rowMap['description'] ?? '',
                'amount': rowMap['amount'],
                'type': type,
                'category': isTransfer
                    ? 'Transfer'
                    : (rowMap['category_name']?.toString() ?? (isInvestment ? 'Investment' : null)),
                'subCategory': isTransfer ? rowMap['to_account_name'] : rowMap['sub_category_name'],
                'accountId': rowMap['from_account_id']?.toString(),
                'accountName': rowMap['from_account_name'],
                'categoryId': rowMap['category_id']?.toString(),
                'subCategoryId': rowMap['sub_category_id']?.toString(),
                'investmentAccountId': isInvestment ? rowMap['to_account_id']?.toString() : null,
                'investmentAccountName': isInvestment ? rowMap['to_account_name'] : null,
                'splitwiseDetails': splitwiseDetails.map((detail) => {
                    ...detail,
                    'date': rowMap['date'],
                    'description': rowMap['description'] ?? '',
                    'totalAmount': _toDouble(rowMap['amount']),
                    'categoryId': rowMap['category_id']?.toString(),
                    'subCategoryId': rowMap['sub_category_id']?.toString(),
                }).toList(),
                'splitwiseUserIds': splitwiseUserIds,
                'includeSplitwise': splitwiseDetails.isNotEmpty,
            });
        }).toList();
    }

    static Future<Map<String, double>> getTransactionTypesSum(String month, String year) async 
    {
        final range = _getMonthRangeTimestamps(month, year);
        final fromTimestamp = range.fromTimestamp;
        final toTimestamp = range.toTimestamp;

        // For transactions that exist in SplitwiseTransactions, subtract the
        // sum of all SPLITED_AMOUNT entries from the transaction's AMOUNT.
        // For normal transactions (no splitwise rows), use the full AMOUNT.
        String sql = "SELECT "
            "COALESCE(SUM(CASE WHEN t.TRANSCATION_TYPE = 2 THEN t.AMOUNT - COALESCE(st.total_split, 0) ELSE 0 END), 0) AS total_income, "
            "COALESCE(SUM(CASE WHEN t.TRANSCATION_TYPE = 1 THEN t.AMOUNT - COALESCE(st.total_split, 0) ELSE 0 END), 0) AS total_expense, "
            "COALESCE(SUM(CASE WHEN t.TRANSCATION_TYPE = 3 THEN t.AMOUNT - COALESCE(st.total_split, 0) ELSE 0 END), 0) AS total_investment "
            "FROM Transactions t "
            "LEFT JOIN ("
                "SELECT TRANSACTION_ID, SUM(SPLITED_AMOUNT) AS total_split "
                "FROM SplitwiseTransactions "
                "GROUP BY TRANSACTION_ID"
            ") st ON st.TRANSACTION_ID = t.ID "
            "WHERE t.DATE >= $fromTimestamp AND t.DATE <= $toTimestamp";
        print('Executing SQL: $sql');
        MySqlConfig config = MySqlConfig.fromDotEnv();
        MySqlService service = MySqlService();
        await service.connect(config);
        final results = await service.executeReadQuery(sql);
        print('getAccountsSum results: $results');
        final rows = (results['rows'] as List? ?? []);
        final firstRow = rows.isNotEmpty ? Map<String, dynamic>.from(rows.first as Map) : const <String, dynamic>{};

        return {
            'total_income': _toDouble(firstRow['total_income']),
            'total_expense': _toDouble(firstRow['total_expense']),
            'total_investment': _toDouble(firstRow['total_investment']),
        };
    }

    static Future<({List<Category> categories, double totalIncome, double totalExpense, double totalInvestment})> getExpenseCategories(String month, String year) async
    {
        final range = _getMonthRangeTimestamps(month, year);
        final fromTimestamp = range.fromTimestamp;
        final toTimestamp = range.toTimestamp;

        // Pre-calculate all splits once to avoid redundant subqueries
        final sql = "WITH splits AS ("
            "  SELECT TRANSACTION_ID, SUM(SPLITED_AMOUNT) AS total_split "
            "  FROM SplitwiseTransactions "
            "  GROUP BY TRANSACTION_ID"
            "), "
            "expense_income_summary AS ("
            "  SELECT t.CATEGORY_ID, SUM(t.AMOUNT - COALESCE(s.total_split, 0)) AS total_amount "
            "  FROM Transactions t "
            "  LEFT JOIN splits s ON s.TRANSACTION_ID = t.ID "
            "  WHERE t.TRANSCATION_TYPE IN (1, 2) "
            "  AND t.DATE >= $fromTimestamp AND t.DATE <= $toTimestamp "
            "  GROUP BY t.CATEGORY_ID"
            "), "
            "investment_summary AS ("
            "  SELECT t.FROM_ACCOUNT_ID, SUM(t.AMOUNT - COALESCE(s.total_split, 0)) AS total_amount "
            "  FROM Transactions t "
            "  LEFT JOIN splits s ON s.TRANSACTION_ID = t.ID "
            "  WHERE t.TRANSCATION_TYPE = 3 "
            "  AND t.DATE >= $fromTimestamp AND t.DATE <= $toTimestamp "
            "  GROUP BY t.FROM_ACCOUNT_ID"
            ") "
            "SELECT "
            "  c.ID AS category_id, "
            "  c.CATEGORY_NAME AS category_name, "
            "  c.BUDGET AS category_budget, "
            "  c.CATEGORY_TYPE AS category_type, "
            "  s.ID AS sub_category_id, "
            "  s.CATEGORY_ID AS sub_category_parent_id, "
            "  s.SUB_CATEGORY_NAME AS sub_category_name, "
            "  s.BUDGET AS sub_category_budget, "
            "  COALESCE(eis.total_amount, 0) AS category_total_amount "
            "FROM Category c "
            "LEFT JOIN SubCategory s ON s.CATEGORY_ID = c.ID "
            "LEFT JOIN expense_income_summary eis ON eis.CATEGORY_ID = c.ID "
            "WHERE c.CATEGORY_TYPE IN (1, 2) "
            "UNION ALL "
            "SELECT "
            "  CONCAT('inv_', a.ID) AS category_id, "
            "  a.ACCOUNT_NAME AS category_name, "
            "  0 AS category_budget, "
            "  3 AS category_type, "
            "  NULL AS sub_category_id, "
            "  NULL AS sub_category_parent_id, "
            "  NULL AS sub_category_name, "
            "  0 AS sub_category_budget, "
            "  COALESCE(inv.total_amount, 0) AS category_total_amount "
            "FROM Accounts a "
            "LEFT JOIN investment_summary inv ON inv.FROM_ACCOUNT_ID = a.ID "
            "WHERE EXISTS (SELECT 1 FROM investment_summary WHERE FROM_ACCOUNT_ID = a.ID) "
            "ORDER BY category_name ASC, sub_category_name ASC";

        debugPrint('getExpenseCategories optimized SQL:\n$sql', wrapWidth: 1024);
        final config = MySqlConfig.fromDotEnv();
        final service = MySqlService();
        await service.connect(config);
        final results = await service.executeReadQuery(sql);

        final rows = (results['rows'] as List? ?? []);
        final categoriesById = <String, Category>{};

        for (final row in rows) 
        {
            final rowMap = Map<String, dynamic>.from(row as Map);
            final categoryId = rowMap['category_id']?.toString() ?? '';
            if (categoryId.isEmpty) 
            {
                continue;
            }

            final existing = categoriesById[categoryId];
            final categoryName = rowMap['category_name']?.toString() ?? '';
            final categoryBudget = _toDouble(rowMap['category_budget']);
            final categoryTypeValue = int.tryParse(rowMap['category_type']?.toString() ?? '0') ?? 0;
            final categoryType = categoryTypeValue == 1 ? 'expense' : categoryTypeValue == 2 ? 'income' : 'investment';
            final categoryTotalAmount = _toDouble(rowMap['category_total_amount']);

            if (existing == null) {
                categoriesById[categoryId] = Category(
                    id: categoryId,
                    name: categoryName,
                    budget: categoryBudget,
                    type: categoryType,
                    amount: categoryTotalAmount,
                    subCategories: const [],
                );
            }

            final subCategoryId = rowMap['sub_category_id'];
            if (subCategoryId != null) 
            {
                final currentCategory = categoriesById[categoryId]!;
                final updatedSubCategories = List<SubCategory>.from(currentCategory.subCategories)
                  ..add(
                    SubCategory(
                        id: subCategoryId.toString(),
                        categoryId: rowMap['sub_category_parent_id']?.toString() ?? categoryId,
                        name: rowMap['sub_category_name']?.toString() ?? '',
                        budget: _toDouble(rowMap['sub_category_budget']),
                    ),
                  );

                categoriesById[categoryId] = Category(
                    id: currentCategory.id,
                    name: currentCategory.name,
                    budget: currentCategory.budget,
                    type: currentCategory.type,
                    amount: currentCategory.amount,
                    subCategories: updatedSubCategories,
                );
            }
        }

        final categories = categoriesById.values.toList();

        double totalIncome = 0;
        double totalExpense = 0;
        double totalInvestment = 0;
        for (final cat in categories) {
            if (cat.type == 'expense') totalExpense += cat.amount;
            else if (cat.type == 'income') totalIncome += cat.amount;
            else if (cat.type == 'investment') totalInvestment += cat.amount;
        }

        return (
            categories: categories,
            totalIncome: totalIncome,
            totalExpense: totalExpense,
            totalInvestment: totalInvestment,
        );
    }




}