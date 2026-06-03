import 'package:flutter/foundation.dart' hide Category;
import '../models/models.dart';
import 'api_service.dart';

/// Centralized in-memory cache for shared data (accounts, categories, etc.).
/// Singleton — use `AppDataCache()` to access.
class AppDataCache {
  static final AppDataCache _instance = AppDataCache._internal();
  factory AppDataCache() => _instance;
  AppDataCache._internal();

  final _api = ApiService();

  // ─── Cached data ──────────────────────────────────────────
  List<BankAccount> _bankAccounts = [];
  List<CreditCardAccount> _creditCardAccounts = [];
  List<InvestmentAccount> _investmentAccounts = [];
  List<Category> _categories = [];
  List<CreditCardCap> _creditCardCaps = [];
  List<SplitwiseGroup> _splitwiseGroups = [];

  bool _accountsLoaded = false;
  bool _categoriesLoaded = false;
  bool _capsLoaded = false;
  bool _groupsLoaded = false;

  // ─── Transaction cache (keyed by "month-year") ────────────
  final Map<String, List<TransactionModel>> _transactionsCache = {};
  final Map<String, Map<String, double>> _expenseByCategoryCache = {};
  final Map<String, Map<String, double>> _incomeByCategoryCache = {};

  // ─── Getters ──────────────────────────────────────────────

  List<BankAccount> get bankAccounts => _bankAccounts;
  List<BankAccount> get activeBankAccounts =>
      _bankAccounts.where((a) => a.isActive).toList();

  List<CreditCardAccount> get creditCardAccounts => _creditCardAccounts;
  List<CreditCardAccount> get activeCreditCardAccounts =>
      _creditCardAccounts.where((a) => a.isActive).toList();

  List<InvestmentAccount> get investmentAccounts => _investmentAccounts;
  List<InvestmentAccount> get activeInvestmentAccounts =>
      _investmentAccounts.where((a) => a.isActive).toList();

  List<Category> get categories => _categories;
  List<CreditCardCap> get creditCardCaps => _creditCardCaps;
  List<SplitwiseGroup> get splitwiseGroups => _splitwiseGroups;

  // ─── Transaction cache getters/setters ────────────────────

  String _txKey(String month, String year) => '$month-$year';

  bool hasTransactionCache(String month, String year) =>
      _transactionsCache.containsKey(_txKey(month, year));

  List<TransactionModel>? getCachedTransactions(String month, String year) =>
      _transactionsCache[_txKey(month, year)];

  Map<String, double>? getCachedExpenseByCategory(String month, String year) =>
      _expenseByCategoryCache[_txKey(month, year)];

  Map<String, double>? getCachedIncomeByCategory(String month, String year) =>
      _incomeByCategoryCache[_txKey(month, year)];

  void updateTransactionCache({
    required String month,
    required String year,
    required List<TransactionModel> transactions,
    required Map<String, double> expenseByCategory,
    required Map<String, double> incomeByCategory,
  }) {
    final key = _txKey(month, year);
    _transactionsCache[key] = transactions;
    _expenseByCategoryCache[key] = expenseByCategory;
    _incomeByCategoryCache[key] = incomeByCategory;
  }

  void removeTransaction(String month, String year, String txId) {
    final key = _txKey(month, year);
    _transactionsCache[key]?.removeWhere((t) => t.id == txId);
  }

  void invalidateTransactionCache(String month, String year) {
    final key = _txKey(month, year);
    _transactionsCache.remove(key);
    _expenseByCategoryCache.remove(key);
    _incomeByCategoryCache.remove(key);
  }

  void invalidateAllTransactionCaches() {
    _transactionsCache.clear();
    _expenseByCategoryCache.clear();
    _incomeByCategoryCache.clear();
  }

  // ─── Load from cache (SharedPreferences) ──────────────────

  Future<void> loadFromLocal() async {
    final results = await Future.wait([
      _api.getCachedAccounts(),
      _api.getCachedCategories(),
      _api.getCachedCreditCardCaps(),
      _api.getCachedSplitwiseGroups(),
    ]);

    final accountsData = results[0] as Map<String, dynamic>?;
    final catData = results[1] as Map<String, dynamic>?;
    final capsData = results[2] as Map<String, dynamic>?;
    final groupsData = results[3] as Map<String, dynamic>?;

    if (accountsData != null) _parseAccounts(accountsData);
    if (catData != null) _parseCategories(catData);
    if (capsData != null) _parseCaps(capsData);
    if (groupsData != null) _parseGroups(groupsData);
  }

  // ─── Fetch fresh from API ─────────────────────────────────

  Future<void> refreshAccounts() async {
    try {
      final data = await _api.getAccounts();
      _parseAccounts(data);
    } catch (e) {
      debugPrint('[AppDataCache] refreshAccounts failed: $e');
    }
  }

  Future<void> refreshCategories() async {
    try {
      final data = await _api.getCategories();
      _parseCategories(data);
    } catch (e) {
      debugPrint('[AppDataCache] refreshCategories failed: $e');
    }
  }

  Future<void> refreshCaps() async {
    try {
      final data = await _api.getCreditCardCaps();
      _parseCaps(data);
    } catch (e) {
      debugPrint('[AppDataCache] refreshCaps failed: $e');
    }
  }

  Future<void> refreshGroups() async {
    try {
      final data = await _api.getSplitwiseGroups();
      _parseGroups(data);
    } catch (e) {
      debugPrint('[AppDataCache] refreshGroups failed: $e');
    }
  }

  Future<void> refreshAll() async {
    await Future.wait([
      refreshAccounts(),
      refreshCategories(),
      refreshCaps(),
      refreshGroups(),
    ]);
  }

  // ─── Ensure loaded (load from cache if not yet loaded) ────

  Future<void> ensureAccounts() async {
    if (!_accountsLoaded) {
      final cached = await _api.getCachedAccounts();
      if (cached != null) _parseAccounts(cached);
      _accountsLoaded = true;
    }
  }

  Future<void> ensureCategories() async {
    if (!_categoriesLoaded) {
      final cached = await _api.getCachedCategories();
      if (cached != null) _parseCategories(cached);
      _categoriesLoaded = true;
    }
  }

  Future<void> ensureCaps() async {
    if (!_capsLoaded) {
      final cached = await _api.getCachedCreditCardCaps();
      if (cached != null) _parseCaps(cached);
      _capsLoaded = true;
    }
  }

  Future<void> ensureGroups() async {
    if (!_groupsLoaded) {
      final cached = await _api.getCachedSplitwiseGroups();
      if (cached != null) _parseGroups(cached);
      _groupsLoaded = true;
    }
  }

  // ─── Direct update (when data already fetched elsewhere) ───

  void updateAccounts(Map<String, dynamic> data) => _parseAccounts(data);
  void updateCategories(Map<String, dynamic> data) => _parseCategories(data);
  void updateCaps(Map<String, dynamic> data) => _parseCaps(data);
  void updateGroups(Map<String, dynamic> data) => _parseGroups(data);

  // ─── Parsing helpers ──────────────────────────────────────

  void _parseAccounts(Map<String, dynamic> data) {
    _bankAccounts = (data['bankAccounts'] as List? ?? [])
        .map((j) => BankAccount.fromJson(j))
        .toList();
    _creditCardAccounts = (data['creditCardAccounts'] as List? ?? [])
        .map((j) => CreditCardAccount.fromJson(j))
        .toList();
    _investmentAccounts = (data['investmentAccounts'] as List? ?? [])
        .map((j) => InvestmentAccount.fromJson(j))
        .toList();
    _accountsLoaded = true;
  }

  void _parseCategories(Map<String, dynamic> data) {
    var cats = (data['categories'] as List? ?? [])
        .map((j) => Category.fromJson(j))
        .toList();
    final subCats = (data['subCategories'] as List? ?? [])
        .map((j) => SubCategory.fromJson(j))
        .toList();
    // Merge top-level subCategories into their parent categories
    for (int i = 0; i < cats.length; i++) {
      final cat = cats[i];
      if (cat.subCategories.isEmpty) {
        final matching =
            subCats.where((s) => s.categoryId == cat.id).toList();
        if (matching.isNotEmpty) {
          cats[i] = Category(
            id: cat.id,
            name: cat.name,
            budget: cat.budget,
            type: cat.type,
            subCategories: matching,
          );
        }
      }
    }
    _categories = cats;
    _categoriesLoaded = true;
  }

  void _parseCaps(Map<String, dynamic> data) {
    _creditCardCaps =
        (data['creditCardCaps'] as List? ?? data['caps'] as List? ?? [])
            .map((j) => CreditCardCap.fromJson(j))
            .toList();
    _capsLoaded = true;
  }

  void _parseGroups(Map<String, dynamic> data) {
    _splitwiseGroups = (data['groups'] as List? ?? [])
        .map((j) => SplitwiseGroup.fromJson(j))
        .toList();
    _groupsLoaded = true;
  }

  /// Clear all cached data (e.g. on logout)
  void clear() {
    _bankAccounts = [];
    _creditCardAccounts = [];
    _investmentAccounts = [];
    _categories = [];
    _creditCardCaps = [];
    _splitwiseGroups = [];
    _accountsLoaded = false;
    _categoriesLoaded = false;
    _capsLoaded = false;
    _groupsLoaded = false;
    _transactionsCache.clear();
    _expenseByCategoryCache.clear();
    _incomeByCategoryCache.clear();
  }
}
