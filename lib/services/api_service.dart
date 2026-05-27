import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'local_storage_service.dart';

class ApiService {
  // TODO: Update with your actual base URL
  static const String baseUrl = 'https://firebase-finance.vercel.app/api';

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final http.Client _client = http.Client();
  final LocalStorageService _localStorage = LocalStorageService();

  String? _sessionCookie;

  Map<String, String> get _headers {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (_sessionCookie != null) h['Cookie'] = _sessionCookie!;
    return h;
  }

  Future<void> loadCookie() async {
    _sessionCookie = await _localStorage.getSessionCookie();
  }

  void setCookie(String cookie) {
    _sessionCookie = cookie;
  }

  void clearCookie() {
    _sessionCookie = null;
  }

  // ─── Auth ────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String username, String password) async {
    final uri = Uri.parse('$baseUrl/login');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    debugPrint('[API POST] /login → ${response.statusCode}');
    if (response.statusCode == 200) {
      // Extract session cookie from Set-Cookie header
      final setCookie = response.headers['set-cookie'];
      if (setCookie != null) {
        // Parse the cookie name=value (ignore attributes)
        final cookieValue = setCookie.split(';').first;
        _sessionCookie = cookieValue;
        await _localStorage.saveSessionCookie(cookieValue);
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['username'] != null) {
        await _localStorage.saveUsername(data['username'] as String);
      }
      return data;
    }
    throw ApiException(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> checkSession() async {
    final uri = Uri.parse('$baseUrl/logout');
    final response = await _client.get(uri, headers: _headers);
    debugPrint('[API GET] /logout (session check) → ${response.statusCode}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException(response.statusCode, response.body);
  }

  Future<void> logout() async {
    final uri = Uri.parse('$baseUrl/logout');
    try {
      await _client.post(uri, headers: _headers);
    } catch (_) {}
    _sessionCookie = null;
    await _localStorage.clearSession();
  }

  // ─── Generic Helpers ───────────────────────────────────────

  Future<Map<String, dynamic>> _get(
      String endpoint, Map<String, String>? params) async 
    {
    final uri = Uri.parse('$baseUrl$endpoint')
        .replace(queryParameters: params);
    debugPrint('[API GET] $uri');
    final response = await _client.get(uri, headers: _headers);
    debugPrint('[API GET] $endpoint → ${response.statusCode}');
    if (response.statusCode == 200) 
    {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('[API GET] $endpoint response keys: $data');
      return data;
    }
    debugPrint('[API GET] $endpoint ERROR: ${response.body}');
    throw ApiException(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> _post(
      String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    debugPrint('[API POST] $uri body: ${jsonEncode(body)}');
    final response =
        await _client.post(uri, headers: _headers, body: jsonEncode(body));
    debugPrint('[API POST] $endpoint → ${response.statusCode}');
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('[API POST] $endpoint response: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');
      return data;
    }
    debugPrint('[API POST] $endpoint ERROR: ${response.body}');
    throw ApiException(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> _put(
      String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    debugPrint('[API PUT] $uri body: ${jsonEncode(body)}');
    final response =
        await _client.put(uri, headers: _headers, body: jsonEncode(body));
    debugPrint('[API PUT] $endpoint → ${response.statusCode}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    debugPrint('[API PUT] $endpoint ERROR: ${response.body}');
    throw ApiException(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> _delete(
      String endpoint, Map<String, String>? params) async {
    final uri = Uri.parse('$baseUrl$endpoint')
        .replace(queryParameters: params);
    debugPrint('[API DELETE] $uri');
    final response = await _client.delete(uri, headers: _headers);
    debugPrint('[API DELETE] $endpoint → ${response.statusCode}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    debugPrint('[API DELETE] $endpoint ERROR: ${response.body}');
    throw ApiException(response.statusCode, response.body);
  }

  // ─── 1. Accounts ──────────────────────────────────────────

  Future<Map<String, dynamic>> getAccounts({String type = 'all'}) async {
    final data = await _get('/accounts', {'type': type});
    if (type == 'all') _localStorage.saveAccounts(data);
    return data;
  }

  Future<Map<String, dynamic>?> getCachedAccounts() =>
      _localStorage.loadAccounts();

  Future<Map<String, dynamic>> createAccount({
    required String accountName,
    required String accountType,
    double initialBalance = 0,
    double? totalLimit,
  }) {
    final body = <String, dynamic>{
      'accountName': accountName,
      'accountType': accountType,
      'initialBalance': initialBalance,
    };
    if (totalLimit != null) body['totalLimit'] = totalLimit;
    return _post('/accounts', body);
  }

  // ─── 2. Add Expense ───────────────────────────────────────

  Future<Map<String, dynamic>> addExpense({
    required double amount,
    required String date,
    required Map<String, dynamic> account,
    double charges = 0,
    String? description,
    String? categoryId,
    String? subCategoryId,
    String? capId,
    bool includeSplitwise = false,
    String? splitwiseGroupId,
    List<String>? splitwiseUserIds,
    String? splitType,
    Map<String, double>? customAmounts,
  }) {
    final body = <String, dynamic>{
      'amount': amount,
      'date': date,
      'account': account,
      'charges': charges,
    };
    if (description != null) body['description'] = description;
    if (categoryId != null) body['categoryId'] = categoryId;
    if (subCategoryId != null) body['subCategoryId'] = subCategoryId;
    if (capId != null) body['capId'] = capId;
    if (includeSplitwise) {
      body['includeSplitwise'] = true;
      if (splitwiseGroupId != null) {
        body['splitwiseGroupId'] = splitwiseGroupId;
      }
      if (splitwiseUserIds != null) {
        body['splitwiseUserIds'] = splitwiseUserIds;
      }
      if (splitType != null) body['splitType'] = splitType;
      if (customAmounts != null) body['customAmounts'] = customAmounts;
    }
    return _post('/add-expense', body);
  }

  Future<Map<String, dynamic>> updateExpense(Map<String, dynamic> body) =>
      _put('/add-expense', body);

  // ─── 3. Add Income ────────────────────────────────────────

  Future<Map<String, dynamic>> addIncome({
    required double amount,
    required String date,
    required String description,
    required Map<String, dynamic> account,
    required String categoryId,
    String? subCategoryId,
  }) {
    final body = <String, dynamic>{
      'amount': amount,
      'date': date,
      'description': description,
      'account': account,
      'categoryId': categoryId,
    };
    if (subCategoryId != null) body['subCategoryId'] = subCategoryId;
    return _post('/add-income', body);
  }

  Future<Map<String, dynamic>> updateIncome(Map<String, dynamic> body) =>
      _put('/add-income', body);

  // ─── 4. Add Investment ────────────────────────────────────

  Future<Map<String, dynamic>> addInvestment({
    required double amount,
    required String date,
    required String description,
    required String accountId,
    required String investmentAccountId,
  }) =>
      _post('/add-investment', {
        'amount': amount,
        'date': date,
        'description': description,
        'accountId': accountId,
        'investmentAccountId': investmentAccountId,
      });

  Future<Map<String, dynamic>> updateInvestment(Map<String, dynamic> body) =>
      _put('/add-investment', body);

  // ─── 5. Add Transfer ──────────────────────────────────────

  Future<Map<String, dynamic>> addTransfer({
    required int fromAccountId,
    required int toAccountId,
    required double amount,
    required String date,
    required String description,
  }) =>
      _post('/add-transfer', {
        'fromAccountId': fromAccountId,
        'toAccountId': toAccountId,
        'amount': amount,
        'date': date,
        'description': description,
      });

  // ─── 6. All Transactions ──────────────────────────────────

  Future<Map<String, dynamic>> getAllTransactions({
    required String month,
    required String year,
  }) =>
      _get('/all-transactions', {'month': month, 'year': year});

  Future<Map<String, dynamic>> bulkDeleteTransactions(
          List<String> transactionIds) =>
      _post('/all-transactions',
          {'action': 'bulk-delete', 'transactionIds': transactionIds});

  Future<Map<String, dynamic>> deleteTransaction(String id) =>
      _delete('/all-transactions', {'id': id});

  Future<Map<String, dynamic>> getTransactionById(String id) =>
      _get('/all-transactions', {'id': id});

  // ─── 7. Bank Details ──────────────────────────────────────

  Future<Map<String, dynamic>> getBankDetails() =>
      _get('/bank-details', null);

  // ─── 8. Bank Transactions ─────────────────────────────────

  Future<Map<String, dynamic>> getBankTransactions({
    required String accountId,
    String? month,
    String? year,
  }) {
    final params = <String, String>{'accountId': accountId};
    if (month != null) params['month'] = month;
    if (year != null) params['year'] = year;
    return _get('/bank-transactions', params);
  }

  // ─── 9. Calculate XIRR ────────────────────────────────────

  Future<Map<String, dynamic>> calculateXirr(String investmentAccountId) =>
      _post('/calculate-xirr',
          {'investmentAccountId': investmentAccountId});

  // ─── 10. Categories ───────────────────────────────────────

  Future<Map<String, dynamic>> getCategories({String type = 'all'}) async {
    final data = await _get('/categories', {'type': type});
    _localStorage.saveCategories(data);
    return data;
  }

  Future<Map<String, dynamic>?> getCachedCategories() =>
      _localStorage.loadCategories();

  Future<Map<String, dynamic>> createCategory({
    required String categoryName,
    required String categoryType,
    double budget = 0,
  }) =>
      _post('/categories', {
        'categoryName': categoryName,
        'categoryType': categoryType,
        'budget': budget,
      });

  // ─── 11. Subcategory ──────────────────────────────────────

  Future<Map<String, dynamic>> createSubcategory({
    required int categoryId,
    required String subCategoryName,
    double budget = 0,
  }) =>
      _post('/categories/subcategory', {
        'categoryId': categoryId,
        'subCategoryName': subCategoryName,
        'budget': budget,
      });

  // ─── 12. Credit Card Caps ─────────────────────────────────

  Future<Map<String, dynamic>> getCreditCardCaps({String? creditCardId}) async {
    final params = <String, String>{};
    if (creditCardId != null) params['creditCardId'] = creditCardId;
    final data = await _get('/credit-card-caps', params.isEmpty ? null : params);
    if (creditCardId == null) _localStorage.saveCreditCardCaps(data);
    return data;
  }

  Future<Map<String, dynamic>?> getCachedCreditCardCaps() =>
      _localStorage.loadCreditCardCaps();

  Future<Map<String, dynamic>> createCreditCardCap({
    required String creditCardId,
    required String capName,
    required double capTotalAmount,
    required double capPercentage,
    double rewardPerAmount = 100,
  }) =>
      _post('/credit-card-caps', {
        'creditCardId': creditCardId,
        'capName': capName,
        'capTotalAmount': capTotalAmount,
        'capPercentage': capPercentage,
        'rewardPerAmount': rewardPerAmount,
      });

  // ─── 13. Credit Card Details ──────────────────────────────

  Future<Map<String, dynamic>> getCreditCardDetails() =>
      _get('/credit-card-details', null);

  // ─── 14. Credit Card Transactions ─────────────────────────

  Future<Map<String, dynamic>> getCreditCardTransactions({
    required String creditCardId,
    String? month,
    String? year,
  }) {
    final params = <String, String>{'creditCardId': creditCardId};
    if (month != null) params['month'] = month;
    if (year != null) params['year'] = year;
    return _get('/credit-card-transactions', params);
  }

  // ─── 15. Financial Details ────────────────────────────────

  Future<Map<String, dynamic>> getFinancialDetails({
    required String month,
    required String year,
  }) =>
      _get('/financial-details', {'month': month, 'year': year});

  // ─── 16. Friend Transactions ──────────────────────────────

  Future<Map<String, dynamic>> getFriendTransactions({
    required String friendId,
    String? friendName,
  }) {
    final params = <String, String>{'friendId': friendId};
    if (friendName != null) params['friendName'] = friendName;
    return _get('/friend-transactions', params);
  }

  // ─── 17. Friends Balance ──────────────────────────────────

  Future<Map<String, dynamic>> getFriendsBalance({bool refresh = false}) =>
      _get('/friends-balance',
          refresh ? {'refresh': 'true'} : null);

  // ─── 18. Investment Accounts ──────────────────────────────

  Future<List<dynamic>> getInvestmentAccounts() async {
    final uri = Uri.parse('$baseUrl/investment-accounts');
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _localStorage.saveInvestmentAccounts(data);
      return data;
    }
    throw ApiException(response.statusCode, response.body);
  }

  Future<List<dynamic>?> getCachedInvestmentAccounts() =>
      _localStorage.loadInvestmentAccounts();

  // ─── 19. MF NAV Data ─────────────────────────────────────

  Future<Map<String, dynamic>> getMfNavData({
    String? schemeCode,
    String? search,
    String period = '1y',
  }) {
    final params = <String, String>{'period': period};
    if (schemeCode != null) params['schemeCode'] = schemeCode;
    if (search != null) params['search'] = search;
    return _get('/mf-nav-data', params);
  }

  // ─── 20. MF Portfolio Analysis ────────────────────────────

  Future<Map<String, dynamic>> analyzeMfPortfolio(
          List<Map<String, dynamic>> transactions) =>
      _post('/mf-portfolio-analysis', {'transactions': transactions});

  // ─── 21. Monthly Expenses ─────────────────────────────────

  Future<Map<String, dynamic>> getMonthlyExpenses({
    required String month,
    required String year,
  }) =>
      _get('/monthly-expenses', {'month': month, 'year': year});

  // ─── 22. Monthly Income ───────────────────────────────────

  Future<Map<String, dynamic>> getMonthlyIncome({
    required String month,
    required String year,
  }) =>
      _get('/monthly-income', {'month': month, 'year': year});

  // ─── 23. Monthly Investments ──────────────────────────────

  Future<Map<String, dynamic>> getMonthlyInvestments({
    required String month,
    required String year,
  }) =>
      _get('/monthly-investments', {'month': month, 'year': year});

  // ─── 24. Pay CC Bill ──────────────────────────────────────

  Future<Map<String, dynamic>> payCcBill({
    required String creditCardId,
    required String bankAccountId,
    required double amount,
    int? date,
    String? description,
  }) {
    final body = <String, dynamic>{
      'creditCardId': creditCardId,
      'bankAccountId': bankAccountId,
      'amount': amount,
    };
    if (date != null) body['date'] = date;
    if (description != null) body['description'] = description;
    return _post('/pay-cc-bill', body);
  }

  // ─── 25. Settle Up ────────────────────────────────────────

  Future<Map<String, dynamic>> settleUp({
    required String friendId,
    required String bankAccountId,
    required double totalSettlementAmount,
    List<Map<String, dynamic>>? unsettledExpenses,
    List<String>? settledTransactionIds,
    int? date,
  }) {
    final body = <String, dynamic>{
      'friendId': friendId,
      'bankAccountId': bankAccountId,
      'totalSettlementAmount': totalSettlementAmount,
    };
    if (unsettledExpenses != null) {
      body['unsettledExpenses'] = unsettledExpenses;
    }
    if (settledTransactionIds != null) {
      body['settledTransactionIds'] = settledTransactionIds;
    }
    if (date != null) body['date'] = date;
    return _post('/settle-up', body);
  }

  // ─── 26. Splitwise ────────────────────────────────────────

  Future<Map<String, dynamic>> getSplitwiseGroups() async {
    final data = await _get('/splitwise', null);
    _localStorage.saveSplitwiseGroups(data);
    return data;
  }

  Future<Map<String, dynamic>?> getCachedSplitwiseGroups() =>
      _localStorage.loadSplitwiseGroups();

  // ─── 27. Splitwise Sync ───────────────────────────────────

  Future<Map<String, dynamic>> syncSplitwise() =>
      _get('/splitwise-sync', null);

  // ─── 28. Total Investments ────────────────────────────────

  Future<Map<String, dynamic>> getTotalInvestments() =>
      _get('/total-investments', null);

  // ─── 29. Unaudited Expenses ───────────────────────────────

  Future<Map<String, dynamic>> getUnauditedExpenses() =>
      _get('/unaudited-expenses', null);

  Future<Map<String, dynamic>> updateUnauditedExpenses(
          List<Map<String, dynamic>> updates) =>
      _put('/unaudited-expenses', {'updates': updates});

  Future<Map<String, dynamic>> deleteUnauditedExpenses(
      List<String> ids) async {
    final uri = Uri.parse('$baseUrl/unaudited-expenses');
    final request = http.Request('DELETE', uri)
      ..headers.addAll(_headers)
      ..body = jsonEncode({'ids': ids});
    debugPrint('[API DELETE] $uri body: ${request.body}');
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    debugPrint('[API DELETE] /unaudited-expenses → ${response.statusCode}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException(response.statusCode, response.body);
  }

  // ─── 30. Unsettled Splitwise Expenses ─────────────────────

  Future<Map<String, dynamic>> getUnsettledSplitwiseExpenses(
          String friendId) =>
      _get('/unsettled-splitwise-expenses', {'friendId': friendId});

  // ─── 31. Yearly Summary ───────────────────────────────────

  Future<Map<String, dynamic>> getYearlySummary(String year) =>
      _get('/yearly-summary', {'year': year});
}

class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException($statusCode): $body';
}
