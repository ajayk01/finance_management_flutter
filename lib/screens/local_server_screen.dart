import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:finance_app/models/models.dart';
import 'package:intl/intl.dart';
import 'package:finance_app/services/direct_expense_service.dart';
import 'package:finance_app/services/direct_sql_service.dart';
import 'package:finance_app/services/splitwise_route_service.dart';
import 'package:finance_app/services/splitwise_session_service.dart';
import 'package:flutter/material.dart';

Map<String, dynamic> buildCreditCardCapsResponse(List<CreditCardCap> caps) {
  return {
    'caps': caps.map(_creditCardCapToJson).toList(),
  };
}

Map<String, dynamic> buildTransactionsResponse(List<TransactionModel> transactions) {
  return {
    'transactions': transactions.map(_transactionToJson).toList(),
  };
}

Map<String, dynamic> buildTotalInvestmentResponse({
  required List<TransactionModel> transactions,
  required List<InvestmentAccount> accounts,
}) {
  final investmentTransactions = transactions
      .where((transaction) => transaction.type == 'investment')
      .toList();

  return {
    'rawTransactions': investmentTransactions.map((transaction) {
      final accountId =
          transaction.investmentAccountId ?? transaction.accountId ?? '';
      final accountName =
          transaction.investmentAccountName ?? transaction.category ?? '';
      final description = transaction.description.trim().isNotEmpty
          ? transaction.description
          : accountName.isNotEmpty
              ? 'Total invested in $accountName'
              : 'Total investment';

      return {
        'id': transaction.id,
        'date': transaction.date.isNotEmpty ? transaction.date : null,
        'description': description,
        'amount': transaction.amount,
        'type': 'Investment',
        'category': accountName,
        'subCategory': '',
        'accountId': accountId,
      };
    }).toList(),
    'investmentAccounts': accounts
        .map((account) => {
              'id': account.id,
              'name': account.name,
            })
        .toList(),
  };
}

Map<String, dynamic> buildMonthlyIncomeResponse(
  List<TransactionModel> transactions,
  List<Category> categories, {
  required String month,
  required String year,
}) {
  final incomeTransactions =
      transactions.where((transaction) => transaction.type == 'income').toList();

  final groupedIncome = <String, Map<String, double>>{};

  void addAmount(String category, String subCategory, double amount) {
    final categoryName = category.isEmpty ? 'Uncategorized' : category;
    final subCategoryName = subCategory.isEmpty ? 'Uncategorized' : subCategory;
    final subCategories =
        groupedIncome.putIfAbsent(categoryName, () => <String, double>{});
    subCategories[subCategoryName] =
        (subCategories[subCategoryName] ?? 0) + amount;
  }

  for (final transaction in incomeTransactions) {
    addAmount(
      transaction.category ?? '',
      transaction.subCategory ?? '',
      transaction.amount,
    );
  }

  final parsedYear = int.tryParse(year);
  final monthlyIncome = <Map<String, dynamic>>[];
  for (final categoryEntry in groupedIncome.entries) {
    for (final subCategoryEntry in categoryEntry.value.entries) {
      if (subCategoryEntry.value == 0) {
        continue;
      }
      monthlyIncome.add({
        'year': parsedYear ?? DateTime.now().year,
        'month': month,
        'category': categoryEntry.key,
        'subCategory': subCategoryEntry.key,
        'expense': '₹${subCategoryEntry.value.toStringAsFixed(2)}',
      });
    }
  }

  return {
    'monthlyIncome': monthlyIncome,
    'rawTransactions': incomeTransactions
        .map((transaction) => {
              'id': transaction.id,
              'date': transaction.date,
              'description': transaction.description,
              'amount': transaction.amount,
              'type': 'Income',
              'category': transaction.category ?? '',
              'subCategory': transaction.subCategory ?? '',
            })
        .toList(),
    'categories': categories
        .map((category) => {
              'id': category.id,
              'name': category.name,
            })
        .toList(),
    'subCategories': categories
        .expand((category) => category.subCategories)
        .map((subCategory) => {
              'id': subCategory.id,
              'name': subCategory.name,
              'categoryId': subCategory.categoryId,
            })
        .toList(),
  };
}

Map<String, dynamic> buildMonthlyInvestmentsResponse({
  required List<TransactionModel> transactions,
  required List<InvestmentAccount> accounts,
  required String month,
  required String year,
}) {
  final investmentTransactions = transactions
      .where((transaction) => transaction.type == 'investment')
      .toList();

  final groupedInvestments = <String, double>{};
  for (final transaction in investmentTransactions) {
    final category = transaction.category ?? '';
    groupedInvestments[category.isEmpty ? 'Uncategorized' : category] =
        (groupedInvestments[category.isEmpty ? 'Uncategorized' : category] ?? 0) +
            transaction.amount;
  }

  final parsedYear = int.tryParse(year);
  final monthlyInvestments = groupedInvestments.entries.map((entry) {
    return {
      'year': parsedYear ?? DateTime.now().year,
      'month': month,
      'category': entry.key,
      'subCategory': '',
      'expense': '₹${entry.value.toStringAsFixed(2)}',
    };
  }).toList();

  return {
    'monthlyInvestments': monthlyInvestments,
    'rawTransactions': investmentTransactions
        .map((transaction) => {
              'id': transaction.id,
              'date': transaction.date,
              'description': transaction.description,
              'amount': transaction.amount,
              'type': 'Investment',
              'category': transaction.category ?? '',
              'subCategory': transaction.subCategory ?? '',
            })
        .toList(),
    'investmentAccounts': accounts
        .map((account) => {
              'id': account.id,
              'name': account.name,
            })
        .toList(),
  };
}

Map<String, dynamic> _creditCardCapToJson(CreditCardCap cap) {
  return {
    'id': cap.id,
    'creditCardId': cap.creditCardId,
    'capName': cap.capName,
    'capTotalAmount': cap.capTotalAmount,
    'capPercentage': cap.capPercentage,
    'capCurrentAmount': cap.capCurrentAmount,
    'remainingAmount': cap.remainingAmount,
    'totalRewards': cap.totalRewards,
    'rewardPerAmount': cap.rewardPerAmount,
  };
}

Map<String, dynamic> _transactionToJson(TransactionModel transaction) {
  return {
    'id': transaction.id,
    'date': transaction.date,
    'time': transaction.time,
    'description': transaction.description,
    'amount': transaction.amount,
    'charges': transaction.charges,
    'rewards': transaction.rewards,
    'type': transaction.type,
    'category': transaction.category,
    'subCategory': transaction.subCategory,
    'accountId': transaction.accountId,
    'accountName': transaction.accountName,
    'categoryId': transaction.categoryId,
    'subCategoryId': transaction.subCategoryId,
    'investmentAccountId': transaction.investmentAccountId,
    'investmentAccountName': transaction.investmentAccountName,
    'splitwiseDetails': transaction.splitwiseDetails ?? const <dynamic>[],
    'splitwiseGroupId': transaction.splitwiseGroupId,
    'splitwiseUserIds': transaction.splitwiseUserIds ?? const <dynamic>[],
    'includeSplitwise': transaction.includeSplitwise,
    'splitType': transaction.splitType,
    'mccCodeId': transaction.mccCodeId,
  };
}

class LocalServerScreen extends StatefulWidget {
  const LocalServerScreen({super.key});

  @override
  State<LocalServerScreen> createState() => _LocalServerScreenState();
}

class _LocalServerScreenState extends State<LocalServerScreen> {
  HttpServer? _server;
  bool _starting = false;
  String? _address;
  String? _deviceIp;  String? _publicIp;
  int? _port;

  bool get _isRunning => _server != null;

  Future<void> _startServer() async {
    if (_isRunning || _starting) return;

    setState(() => _starting = true);

    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      _server = server;
      _address = 'localhost';
      final ipResults = await Future.wait<String?>([
        _getDeviceIp(),
        _getPublicIp(),
      ]);
      _deviceIp = ipResults[0];
      _publicIp = ipResults[1];
      _port = server.port;

      unawaited(_serveRequests(server));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _deviceIp == null
                ? 'Server started on http://${_address ?? 'localhost'}:${server.port}'
                : 'Server started on http://${_deviceIp!}:${server.port}',
          ),
        ),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start server: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  Future<void> _stopServer() async {
    final server = _server;
    if (server == null) return;

    await server.close(force: true);

    if (!mounted) return;
    setState(() {
      _server = null;
      _address = null;
      _deviceIp = null;
      _publicIp = null;
      _port = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server stopped')),
    );
  }

  Future<void> _serveRequests(HttpServer server) async {
    await for (final request in server) {
      final path = request.uri.path;

      if (request.method == 'OPTIONS') {
        _writeCorsHeaders(request.response);
        request.response.statusCode = HttpStatus.noContent;
        unawaited(request.response.close());
        continue;
      }

      if (path == '/health') {
        _writeJson(request.response, {
          'ok': true,
          'message': 'Server is running',
          'timestamp': DateTime.now().toIso8601String(),
        });
        continue;
      }

      if (path == '/api/transactions') {
        await _serveTransactions(
          request.response,
          request.uri.queryParameters,
        );
        continue;
      }

      if (path.startsWith('/api/transactions')) {
        await _handleTransactionsRoute(request);
        continue;
      }

      if (request.method != 'GET') {
        _writeJson(
          request.response,
          {
            'ok': false,
            'error': 'Only GET is supported for this endpoint',
          },
          statusCode: HttpStatus.methodNotAllowed,
        );
        continue;
      }

      if (path == '/api/bank-details') {
        await _serveBankDetails(request.response);
        continue;
      }

      if (path == '/api/transactions') {
        await _serveTransactions(
          request.response,
          request.uri.queryParameters,
        );
        continue;
      }

      if (path == '/api/credit-card-caps') {
        await _serveCreditCardCaps(
          request.response,
          request.uri.queryParameters,
        );
        continue;
      }

      if (path == '/api/monthly-income') {
        await _serveMonthlyIncome(
          request.response,
          request.uri.queryParameters,
        );
        continue;
      }

      if (path == '/api/total-investments') {
        await _serveTotalInvestments(
          request.response,
          request.uri.queryParameters,
        );
        continue;
      }

      if (path == '/api/monthly-investments') {
        await _serveMonthlyInvestments(
          request.response,
          request.uri.queryParameters,
        );
        continue;
      }

      if (path == '/api/monthly-expenses') {
        await _serveMonthlyExpenses(
          request.response,
          request.uri.queryParameters,
        );
        continue;
      }

      if (path == '/api/splitwise') {
        await _serveSplitwiseGroups(request.response);
        continue;
      }

      if (path == '/' || path == '/api/accounts') {
        await _serveActiveAccounts(request.response);
        continue;
      }

      _writeJson(
        request.response,
        {
          'ok': false,
          'error': 'Endpoint not found',
        },
        statusCode: HttpStatus.notFound,
      );
    }
  }

  Future<void> _serveTransactions(
    HttpResponse response,
    Map<String, String> queryParameters,
  ) async {
    final month = queryParameters['month'];
    final year = queryParameters['year'];
    final accountId = queryParameters['accountId'];
    if (month == null || month.isEmpty || year == null || year.isEmpty) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': 'Month and year are required query parameters.',
        },
        statusCode: HttpStatus.badRequest,
      );
      return;
    }

    try {
      final transactions = await DirectSqlService.getAllTransactions(
        month,
        year,
        accountId: accountId,
      );
      _writeJson(response, buildTransactionsResponse(transactions));
    } on FormatException catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.message,
        },
        statusCode: HttpStatus.badRequest,
      );
    } catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.toString(),
        },
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  Future<void> _serveMonthlyIncome(
    HttpResponse response,
    Map<String, String> queryParameters,
  ) async {
    final month = queryParameters['month'];
    final year = queryParameters['year'];
    if (month == null || month.isEmpty || year == null || year.isEmpty) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': 'Month and year are required query parameters.',
        },
        statusCode: HttpStatus.badRequest,
      );
      return;
    }

    try {
      final transactions = await DirectSqlService.getAllTransactions(month, year);
      final categories = await DirectSqlService.getAllCategoriesAndSubCategories(
        type: 'income',
      );
      _writeJson(
        response,
        buildMonthlyIncomeResponse(
          transactions,
          categories,
          month: month,
          year: year,
        ),
      );
    } on FormatException catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.message,
        },
        statusCode: HttpStatus.badRequest,
      );
    } catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.toString(),
        },
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  Future<void> _serveTotalInvestments(
    HttpResponse response,
    Map<String, String> queryParameters,
  ) async {
    final month = queryParameters['month'];
    final year = queryParameters['year'];

    try {
      final accountsResult = await DirectSqlService.getAllActiveAccounts();
      final targetMonth = month ?? DateFormat('MMM').format(DateTime.now()).toLowerCase();
      final targetYear = year ?? DateTime.now().year.toString();
      final transactions = await DirectSqlService.getAllTransactions(
        targetMonth,
        targetYear,
      );

      _writeJson(
        response,
        buildTotalInvestmentResponse(
          transactions: transactions,
          accounts: accountsResult.investmentAccounts,
        ),
      );
    } on FormatException catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.message,
        },
        statusCode: HttpStatus.badRequest,
      );
    } catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.toString(),
        },
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  Future<void> _serveMonthlyInvestments(
    HttpResponse response,
    Map<String, String> queryParameters,
  ) async {
    final month = queryParameters['month'];
    final year = queryParameters['year'];
    if (month == null || month.isEmpty || year == null || year.isEmpty) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': 'Month and year are required query parameters.',
        },
        statusCode: HttpStatus.badRequest,
      );
      return;
    }

    try {
      final accountsResult = await DirectSqlService.getAllActiveAccounts();
      final transactions = await DirectSqlService.getAllTransactions(month, year);
      _writeJson(
        response,
        buildMonthlyInvestmentsResponse(
          transactions: transactions,
          accounts: accountsResult.investmentAccounts,
          month: month,
          year: year,
        ),
      );
    } on FormatException catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.message,
        },
        statusCode: HttpStatus.badRequest,
      );
    } catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.toString(),
        },
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  Future<void> _serveMonthlyExpenses(
    HttpResponse response,
    Map<String, String> queryParameters,
  ) async {
    final month = queryParameters['month'];
    final year = queryParameters['year'];
    if (month == null || month.isEmpty || year == null || year.isEmpty) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': 'Month and year are required query parameters.',
        },
        statusCode: HttpStatus.badRequest,
      );
      return;
    }

    try {
      _writeJson(
        response,
        await DirectSqlService.getMonthlyExpenses(month, year),
      );
    } on FormatException catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.message,
        },
        statusCode: HttpStatus.badRequest,
      );
    } catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.toString(),
        },
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  // Dispatches POST/PUT/DELETE under /api/transactions to the add/edit/delete handlers.
  Future<void> _handleTransactionsRoute(HttpRequest request) async {
    final response = request.response;
    final segments = request.uri.pathSegments; // ['api', 'transactions', ...]
    final rest = segments.length > 2 ? segments.sublist(2) : const <String>[];

    try {
      if (request.method == 'GET' && rest.isEmpty) {
        await _serveTransactions(response, request.uri.queryParameters);
        return;
      }
      if (request.method == 'POST' && rest.length == 1) {
        await _addTransaction(rest[0], request, response);
        return;
      }
      if (request.method == 'PUT' && rest.length == 2) {
        await _updateTransaction(rest[0], rest[1], request, response);
        return;
      }
      if (request.method == 'DELETE' && rest.isEmpty) {
        await _bulkDeleteTransactions(request, response);
        return;
      }
      if (request.method == 'DELETE' && rest.length == 1) {
        await DirectSqlService.deleteTransaction(rest[0]);
        _writeJson(response, {'success': true});
        return;
      }

      _writeJson(
        response,
        {'ok': false, 'error': 'Endpoint not found'},
        statusCode: HttpStatus.notFound,
      );
    } on ArgumentError catch (e) {
      _writeJson(
        response,
        {'ok': false, 'error': e.message.toString()},
        statusCode: HttpStatus.badRequest,
      );
    } on FormatException catch (e) {
      _writeJson(
        response,
        {'ok': false, 'error': e.message},
        statusCode: HttpStatus.badRequest,
      );
    } catch (e) {
      _writeJson(
        response,
        {'ok': false, 'error': e.toString()},
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  Future<void> _addTransaction(
    String type,
    HttpRequest request,
    HttpResponse response,
  ) async {
    final body = await _readJsonBody(request);

    switch (type) {
      case 'income':
        await DirectSqlService.addIncomeTransaction(
          amount: _requireDouble(body, 'amount'),
          accountId: _requireString(body, 'accountId'),
          categoryId: _requireString(body, 'categoryId'),
          subCategoryId: body['subCategoryId']?.toString(),
          notes: (body['notes'] ?? '').toString(),
          date: _parseDate(body['date']),
        );
        break;
      case 'expense':
        final includeSplitwise = body['includeSplitwise'] == true;
        await DirectExpenseService.addExpense(
          amount: _requireDouble(body, 'amount'),
          charges: (body['charges'] as num?)?.toDouble() ?? 0,
          date: _requireString(body, 'date'),
          account: _requireMap(body, 'account'),
          description: body['description']?.toString(),
          categoryId: body['categoryId']?.toString(),
          subCategoryId: body['subCategoryId']?.toString(),
          capId: body['capId']?.toString(),
          mccCodeId: body['mccCodeId']?.toString(),
          includeSplitwise: includeSplitwise,
          splitwiseGroupId: body['splitwiseGroupId']?.toString(),
          splitwiseUserIds: _optionalStringList(body['splitwiseUserIds']),
          splitType: body['splitType']?.toString(),
          customAmounts: _optionalDoubleMap(body['customAmounts']),
          reauthenticateSplitwise:
              includeSplitwise ? _reauthenticateSplitwise : null,
        );
        break;
      case 'transfer':
        await DirectSqlService.addTransferTransaction(
          amount: _requireDouble(body, 'amount'),
          fromAccountId: _requireString(body, 'fromAccountId'),
          toAccountId: _requireString(body, 'toAccountId'),
          notes: body['notes']?.toString(),
          date: _parseDate(body['date']),
        );
        break;
      case 'investment':
        await DirectSqlService.addInvestmentTransaction(
          amount: _requireDouble(body, 'amount'),
          fromAccountId: _requireString(body, 'fromAccountId'),
          investmentAccountId: _requireString(body, 'investmentAccountId'),
          notes: body['notes']?.toString(),
          date: _parseDate(body['date']),
        );
        break;
      default:
        _writeJson(
          response,
          {'ok': false, 'error': 'Unknown transaction type: $type'},
          statusCode: HttpStatus.badRequest,
        );
        return;
    }

    _writeJson(response, {'success': true}, statusCode: HttpStatus.created);
  }

  Future<void> _updateTransaction(
    String type,
    String id,
    HttpRequest request,
    HttpResponse response,
  ) async {
    final body = await _readJsonBody(request);

    switch (type) {
      case 'income':
        await DirectSqlService.updateIncomeTransaction(
          transactionId: id,
          amount: _requireDouble(body, 'amount'),
          accountId: _requireString(body, 'accountId'),
          categoryId: _requireString(body, 'categoryId'),
          subCategoryId: body['subCategoryId']?.toString(),
          notes: (body['notes'] ?? '').toString(),
          date: _parseDate(body['date']),
        );
        break;
      case 'expense':
        await DirectExpenseService.updateExpense(
          id: id,
          amount: _requireDouble(body, 'amount'),
          charges: (body['charges'] as num?)?.toDouble() ?? 0,
          date: _requireString(body, 'date'),
          account: _requireMap(body, 'account'),
          categoryId: _requireString(body, 'categoryId'),
          subCategoryId: body['subCategoryId']?.toString(),
          description: body['description']?.toString(),
          capId: body['capId']?.toString(),
          mccCodeId: body['mccCodeId']?.toString(),
          updateSplitwise: body['updateSplitwise'] != false,
          includeSplitwise: body['includeSplitwise'] == true,
          splitwiseGroupId: body['splitwiseGroupId']?.toString(),
          splitwiseUserIds: _optionalStringList(body['splitwiseUserIds']),
          splitType: body['splitType']?.toString(),
          customAmounts: _optionalDoubleMap(body['customAmounts']),
          reauthenticateSplitwise: _reauthenticateSplitwise,
        );
        break;
      case 'transfer':
        await DirectSqlService.updateTransferTransaction(
          transactionId: id,
          amount: _requireDouble(body, 'amount'),
          fromAccountId: _requireString(body, 'fromAccountId'),
          toAccountId: _requireString(body, 'toAccountId'),
          notes: body['notes']?.toString(),
          date: _parseDate(body['date']),
        );
        break;
      case 'investment':
        await DirectSqlService.updateInvestmentTransaction(
          transactionId: id,
          amount: _requireDouble(body, 'amount'),
          fromAccountId: _requireString(body, 'fromAccountId'),
          investmentAccountId: _requireString(body, 'investmentAccountId'),
          notes: body['notes']?.toString(),
          date: _parseDate(body['date']),
        );
        break;
      default:
        _writeJson(
          response,
          {'ok': false, 'error': 'Unknown transaction type: $type'},
          statusCode: HttpStatus.badRequest,
        );
        return;
    }

    _writeJson(response, {'success': true});
  }

  Future<void> _bulkDeleteTransactions(
    HttpRequest request,
    HttpResponse response,
  ) async {
    final body = await _readJsonBody(request);
    final ids = (body['ids'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    if (ids.isEmpty) {
      throw ArgumentError('ids must be a non-empty array');
    }

    await DirectSqlService.deleteTransactions(ids);
    _writeJson(response, {'success': true, 'deletedCount': ids.length});
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final content = await utf8.decoder.bind(request).join();
    if (content.trim().isEmpty) return {};
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Request body must be a JSON object');
    }
    return decoded;
  }

  String _requireString(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value == null || value.toString().trim().isEmpty) {
      throw ArgumentError('Missing required field: $key');
    }
    return value.toString();
  }

  double _requireDouble(Map<String, dynamic> body, String key) {
    final value = body[key];
    final parsed =
        value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      throw ArgumentError('Missing/invalid required field: $key');
    }
    return parsed;
  }

  Map<String, dynamic> _requireMap(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value is! Map) {
      throw ArgumentError('Missing required field: $key');
    }
    return Map<String, dynamic>.from(value);
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  List<String>? _optionalStringList(dynamic value) {
    if (value is! List) return null;
    return value.map((e) => e.toString()).toList();
  }

  Map<String, double>? _optionalDoubleMap(dynamic value) {
    if (value is! Map) return null;
    return value.map(
      (key, val) => MapEntry(key.toString(), (val as num).toDouble()),
    );
  }

  // Reuses the same Splitwise re-login flow the transaction screens use.
  Future<void> _reauthenticateSplitwise() {
    return SplitwiseSessionService.instance
        .ensureAuthenticated(context, force: true);
  }

  Future<void> _serveBankDetails(HttpResponse response) async {
    try {
      final accounts = await DirectSqlService.getAllActiveAccounts();

      _writeJson(response, {
        'bankAccounts': accounts.bankAccounts.map(_bankDetailsToJson).toList(),
        'creditCardAccounts':
            accounts.creditCardAccounts.map(_creditCardAccountToJson).toList(),
        'investmentAccounts':
            accounts.investmentAccounts.map(_investmentAccountToJson).toList(),
      });
    } catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.toString(),
        },
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  Future<void> _serveCreditCardCaps(
    HttpResponse response,
    Map<String, String> queryParameters,
  ) async {
    try {
      final creditCardId = queryParameters['creditCardId'];
      final caps = await DirectSqlService.getAllCreditCardCaps(
        creditCardId: creditCardId,
      );

      _writeJson(response, buildCreditCardCapsResponse(caps));
    } catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.toString(),
        },
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  Future<void> _serveSplitwiseGroups(HttpResponse response) async {
    try {
      final groups = await SplitwiseRouteService().getGroupsWithMembers(
        reauthenticate: _reauthenticateSplitwise,
      );

      _writeJson(response, {
        'groups': groups.map(_splitwiseGroupToJson).toList(),
      });
    } catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.toString(),
        },
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  Future<void> _serveActiveAccounts(HttpResponse response) async {
    try {
      final accounts = await DirectSqlService.getAllActiveAccounts();
      _writeJson(
        response,
        {
          'ok': true,
          'bankAccounts': accounts.bankAccounts.map(_bankAccountToJson).toList(),
          'creditCardAccounts': accounts.creditCardAccounts.map(_creditCardAccountToJson).toList(),
          'investmentAccounts': accounts.investmentAccounts.map(_investmentAccountToJson).toList(),
        },
      );
    } catch (e) {
      _writeJson(
        response,
        {
          'ok': false,
          'error': e.toString(),
        },
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  Map<String, dynamic> _bankAccountToJson(dynamic account) {
    return {
      'id': account.id,
      'name': account.name,
      'balance': account.balance,
      'initialBalance': account.initialBalance,
      'isActive': account.isActive,
      'logo': account.logo,
    };
  }

  Map<String, dynamic> _bankDetailsToJson(dynamic account) {
    return {
      'id': account.id,
      'name': account.name,
      'balance': account.balance,
      'initialBalance': account.initialBalance,
      'logo': account.logo,
    };
  }

  Map<String, dynamic> _creditCardAccountToJson(dynamic account) {
    return {
      'id': account.id,
      'name': account.name,
      'usedAmount': account.usedAmount,
      'totalLimit': account.totalLimit,
      'availableCredit': account.availableCredit,
      'rewardPoints': account.rewardPoints,
      'isActive': account.isActive,
      'logo': account.logo,
    };
  }

  Map<String, dynamic> _investmentAccountToJson(dynamic account) {
    return {
      'id': account.id,
      'name': account.name,
      'totalInvested': account.totalInvested,
      'totalWithdraw': account.totalWithdraw,
      'currentValue': account.currentValue,
      'xirr': account.xirr,
      'isActive': account.isActive,
    };
  }

  Map<String, dynamic> _splitwiseGroupToJson(dynamic group) {
    return {
      'id': group.id,
      'name': group.name,
      'members': (group.members as List).map(_splitwiseMemberToJson).toList(),
    };
  }

  Map<String, dynamic> _splitwiseMemberToJson(dynamic member) {
    final friendId = member.friendId?.toString();
    return {
      'id': member.id,
      'friendId': friendId == null || friendId.isEmpty
          ? null
          : int.tryParse(friendId) ?? friendId,
      'name': member.name,
    };
  }

  void _writeJson(
    HttpResponse response,
    Map<String, dynamic> data, {
    int statusCode = HttpStatus.ok,
  }) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    _writeCorsHeaders(response);
    response.write(jsonEncode(data));
    unawaited(response.close());
  }

  void _writeCorsHeaders(HttpResponse response) {
    response.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
    response.headers.set(HttpHeaders.accessControlAllowMethodsHeader, 'GET, OPTIONS');
    response.headers.set(HttpHeaders.accessControlAllowHeadersHeader, 'Content-Type');
  }

  Future<String?> _getDeviceIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (!ip.startsWith('127.')) {
            return ip;
          }
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<String?> _getPublicIp() async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse('https://api.ipify.org?format=json'));
      final response = await request.close().timeout(const Duration(seconds: 5));

      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final body = await utf8.decoder.bind(response).join();
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        final ip = data['ip']?.toString();
        if (ip != null && ip.isNotEmpty) {
          return ip;
        }
      }
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }

    return null;
  }

  @override
  void dispose() {
    final server = _server;
    _server = null;
    if (server != null) {
      unawaited(server.close(force: true));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localhostUrl = 'http://${_address ?? 'localhost'}:${_port ?? 8080}';
    final deviceUrl = _deviceIp == null ? null : 'http://${_deviceIp!}:${_port ?? 8080}';
    final publicUrl = _publicIp == null ? null : 'http://${_publicIp!}:${_port ?? 8080}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Server'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isRunning ? 'Server is running' : 'Server is stopped',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (_isRunning) ...[
              const SizedBox(height: 8),
              Text('Local: $localhostUrl', style: const TextStyle(fontSize: 14)),
              if (deviceUrl != null)
                Text('Network: $deviceUrl', style: const TextStyle(fontSize: 14)),
              if (publicUrl != null)
                Text('Public: $publicUrl', style: const TextStyle(fontSize: 14)),
              if (publicUrl == null)
                const Text(
                  'Public IP not available (internet lookup failed).',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Endpoints:\nGET /health\nGET /api/bank-details\nGET /api/transactions?month=sep&year=2026\nGET /api/credit-card-caps?creditCardId=12\nGET /api/monthly-expenses?month=sep&year=2026\nGET /api/splitwise\nGET /api/accounts\nGET / (returns all active accounts)\n'
              'POST /api/transactions/income|expense|transfer|investment\n'
              'PUT /api/transactions/{type}/{id}\n'
              'DELETE /api/transactions/{id}\n'
              'DELETE /api/transactions (bulk, body: {"ids": [...]})',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            const Text(
              'Note: Public URL works only if router/firewall allows inbound port forwarding to this device.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _starting
                    ? null
                    : _isRunning
                        ? _stopServer
                        : _startServer,
                child: Text(_isRunning ? 'Stop Server' : 'Start Server'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
