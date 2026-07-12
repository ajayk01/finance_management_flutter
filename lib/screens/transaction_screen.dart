import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_data_cache.dart';
import '../services/direct_sql_service.dart';
import '../utils/currency_formatter.dart';
import '../widgets/overview_bar_chart.dart';
import 'add_transaction_screen.dart';

// ─── Data Models ─────────────────────────────────────────────

enum TransactionType { expense, income, transfer, investment }

class Transaction {
  final String title;
  final String subtitle;
  final double amount;
  final TransactionType type;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String? avatarUrl;
  final String account;
  final TransactionModel? model;

  const Transaction({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.type,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    this.avatarUrl,
    this.account = 'Chase Bank',
    this.model,
  });

  String get typeLabel {
    switch (type) {
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.income:
        return 'Income';
      case TransactionType.transfer:
        return 'Transfer';
      case TransactionType.investment:
        return 'Investment';
    }
  }
}

class DayGroup {
  final int day;
  final String weekday;
  final String monthYear;
  final List<Transaction> transactions;

  const DayGroup({
    required this.day,
    required this.weekday,
    required this.monthYear,
    required this.transactions,
  });
}

// ─── Spend Category for the bar ──────────────────────────────

class _SpendCategory {
  final String name;
  final double amount;
  final Color color;

  const _SpendCategory(this.name, this.amount, this.color);
}

// ─── Screen ──────────────────────────────────────────────────

class TransactionScreen extends StatefulWidget {
  final String? initialAccount;

  const TransactionScreen({super.key, this.initialAccount});

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  String _selectedFilter = 'All';
  DateTime _currentDate = DateTime.now();
  String _selectedAccount = 'All';
  final _api = ApiService();

  bool _loading = true;
  bool _deleting = false;
  List<TransactionModel> _transactions = [];
  List<BankAccount> _bankAccounts = [];
  List<CreditCardAccount> _creditCardAccounts = [];
  Map<String, double> _apiExpenseByCategory = {};
  Map<String, double> _apiIncomeByCategory = {};
  double _totalIncome = 0;
  double _totalExpense = 0;
  double _totalInvestment = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialAccount != null) {
      _selectedAccount = widget.initialAccount!;
    }
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    final month = DateFormat('MMM').format(_currentDate).toLowerCase();
    final year = _currentDate.year.toString();
    final cache = AppDataCache();

    final cachedMonthlyExp =
      cache.getCachedMonthlyExpenseByCategory(month, year) ?? {};
    final cachedMonthlyInc =
      cache.getCachedMonthlyIncomeByCategory(month, year) ?? {};
    final cachedTotalIncome = cache.getCachedTotalIncome(month, year) ?? 0;
    final cachedTotalExpense = cache.getCachedTotalExpense(month, year) ?? 0;
    final cachedTotalInvestment =
      cache.getCachedTotalInvestment(month, year) ?? 0;

    // Show cached data immediately as placeholder (non-blocking)
    if (cache.hasTransactionCache(month, year)) {
      final cachedTx = cache.getCachedTransactions(month, year)!;
      final cachedExp = cachedMonthlyExp.isNotEmpty
          ? cachedMonthlyExp
          : (cache.getCachedExpenseByCategory(month, year) ?? {});
      final cachedInc = cachedMonthlyInc.isNotEmpty
          ? cachedMonthlyInc
          : (cache.getCachedIncomeByCategory(month, year) ?? {});
      setState(() {
        _transactions = cachedTx;
        _bankAccounts = cache.bankAccounts;
        _creditCardAccounts = cache.creditCardAccounts;
        _apiExpenseByCategory = cachedExp;
        _apiIncomeByCategory = cachedInc;
        _totalIncome = cachedTotalIncome;
        _totalExpense = cachedTotalExpense;
        _totalInvestment = cachedTotalInvestment;
        _loading = false;
      });
    } else if (cache.hasAccountsSnapshot || cache.hasMonthlySummaryCache(month, year)) {
      // Show available summary/account cache while transactions are loading.
      setState(() {
        _bankAccounts = cache.bankAccounts;
        _creditCardAccounts = cache.creditCardAccounts;
        _apiExpenseByCategory = cachedMonthlyExp;
        _apiIncomeByCategory = cachedMonthlyInc;
        _totalIncome = cachedTotalIncome;
        _totalExpense = cachedTotalExpense;
        _totalInvestment = cachedTotalInvestment;
        _loading = true;
      });
    } else {
      setState(() => _loading = true);
    }

    // Always fetch fresh data from API
    await _fetchAndUpdateTransactions(month, year, cache);
  }

  Future<void> _fetchAndUpdateTransactions(String month, String year, AppDataCache cache) async {
    try {
      final shouldFetchAccounts = !cache.hasAccountsSnapshot;
      final shouldFetchMonthly = !cache.hasMonthlySummaryCache(month, year);

      final requests = <Future<dynamic>>[
        DirectSqlService.getAllTransactions(month, year),
      ];
      if (shouldFetchAccounts) {
        requests.add(_api.getAccounts());
      }
      if (shouldFetchMonthly) {
        requests.add(DirectSqlService.getExpenseCategories(month, year));
      }

      final results = await Future.wait(requests);

      var resultIdx = 0;
  final txList = results[resultIdx++] as List<TransactionModel>;
      Map<String, dynamic>? accountsData;
      ({
        List<Category> categories,
        double totalIncome,
        double totalExpense,
        double totalInvestment
      })? monthlyData;

      if (shouldFetchAccounts) {
        accountsData = results[resultIdx++] as Map<String, dynamic>;
      }
      if (shouldFetchMonthly) {
        monthlyData = results[resultIdx++] as ({
          List<Category> categories,
          double totalIncome,
          double totalExpense,
          double totalInvestment
        });
      }

      // Update cache with fresh accounts
      if (accountsData != null && accountsData.isNotEmpty) {
        cache.updateAccounts(accountsData);
      }
      final banks = cache.bankAccounts;
      final cards = cache.creditCardAccounts;

      Map<String, double> expByCat;
      Map<String, double> incByCat;
      double totalIncome;
      double totalExpense;
      double totalInvestment;

      if (shouldFetchMonthly) {
        expByCat = <String, double>{};
        incByCat = <String, double>{};
        for (final category in monthlyData?.categories ?? const <Category>[]) {
          if (category.amount <= 0) continue;
          if (category.type == 'expense') {
            expByCat[category.name] =
                (expByCat[category.name] ?? 0) + category.amount;
          } else if (category.type == 'income') {
            incByCat[category.name] =
                (incByCat[category.name] ?? 0) + category.amount;
          }
        }

        totalIncome = monthlyData?.totalIncome ?? 0;
        totalExpense = monthlyData?.totalExpense ?? 0;
        totalInvestment = monthlyData?.totalInvestment ?? 0;

        cache.updateMonthlySummaryCache(
          month: month,
          year: year,
          expenseByCategory: expByCat,
          incomeByCategory: incByCat,
          totalIncome: totalIncome,
          totalExpense: totalExpense,
          totalInvestment: totalInvestment,
        );
      } else {
        expByCat = Map.of(cache.getCachedMonthlyExpenseByCategory(month, year) ??
            cache.getCachedExpenseByCategory(month, year) ??
            {});
        incByCat = Map.of(cache.getCachedMonthlyIncomeByCategory(month, year) ??
            cache.getCachedIncomeByCategory(month, year) ??
            {});
        totalIncome = cache.getCachedTotalIncome(month, year) ?? 0;
        totalExpense = cache.getCachedTotalExpense(month, year) ?? 0;
        totalInvestment = cache.getCachedTotalInvestment(month, year) ?? 0;
      }

      // Store in cache
      cache.updateTransactionCache(
        month: month,
        year: year,
        transactions: txList,
        expenseByCategory: expByCat,
        incomeByCategory: incByCat,
      );

      if (mounted) {
        setState(() {
          _transactions = txList;
          _bankAccounts = banks;
          _creditCardAccounts = cards;
          _apiExpenseByCategory = expByCat;
          _apiIncomeByCategory = incByCat;
          _totalIncome = totalIncome;
          _totalExpense = totalExpense;
          _totalInvestment = totalInvestment;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _filters = ['All', 'Income', 'Expense', 'Transfer', 'Investment'];

  static const _expenseColors = [
    Color(0xFFEF4444),
    Color(0xFFF87171),
    Color(0xFFDC2626),
    Color(0xFFFCA5A5),
    Color(0xFFB91C1C),
    Color(0xFFFF6B6B),
    Color(0xFFE11D48),
    Color(0xFFFB7185),
  ];

  static const _incomeColors = [
    Color(0xFF22C55E),
    Color(0xFF4ADE80),
    Color(0xFF16A34A),
    Color(0xFF86EFAC),
    Color(0xFF15803D),
    Color(0xFF34D399),
    Color(0xFF059669),
    Color(0xFF6EE7B7),
  ];

  static const _defaultColors = [
    Color(0xFF3B82F6),
    Color(0xFF22C55E),
    Color(0xFFF97316),
    Color(0xFF94A3B8),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
  ];

  List<_SpendCategory> get _categories {
    final typeFilter = _selectedFilter.toLowerCase();
    Map<String, double> catMap;

    if (typeFilter == 'all' || typeFilter == 'expense') {
      catMap = Map.of(_apiExpenseByCategory);
    } else if (typeFilter == 'income') {
      catMap = Map.of(_apiIncomeByCategory);
    } else {
      // For Transfer/Investment, compute from raw transactions
      catMap = <String, double>{};
      for (final tx in _transactions) {
        if (tx.type.toLowerCase() == typeFilter) {
          final cat = tx.category ?? 'Others';
          catMap[cat] = (catMap[cat] ?? 0) + tx.amount;
        }
      }
    }

    // Remove categories with zero or negative net amounts
    catMap.removeWhere((_, v) => v <= 0);
    final colors = typeFilter == 'expense'
        ? _expenseColors
        : typeFilter == 'income'
            ? _incomeColors
            : _defaultColors;
    return catMap.entries.toList().asMap().entries.map((entry) {
      final e = entry.value;
      return _SpendCategory(
        e.key,
        e.value,
        colors[entry.key % colors.length],
      );
    }).toList();
  }

  List<DayGroup> get _filteredGroups {
    // Group API transactions by day
    var filtered = _transactions.toList();

    // Filter by type
    if (_selectedFilter != 'All') {
      filtered = filtered
          .where((t) =>
              t.type.toLowerCase() == _selectedFilter.toLowerCase())
          .toList();
    }

    // Filter by account (for transfers/investments, also match destination account)
    if (_selectedAccount != 'All') {
      filtered = filtered
          .where((t) =>
              t.accountName == _selectedAccount ||
              (t.type.toLowerCase() == 'transfer' && t.subCategory == _selectedAccount) ||
              (t.type.toLowerCase() == 'investment' && t.investmentAccountName == _selectedAccount))
          .toList();
    }

    // Group by day
    final Map<String, List<Transaction>> dayMap = {};
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    for (final tx in filtered) {
      final dateStr = tx.date;
      if (!dayMap.containsKey(dateStr)) {
        dayMap[dateStr] = [];
      }
      final isExpense =
          tx.type.toLowerCase() == 'expense';
      final isIncome = tx.type.toLowerCase() == 'income';
      final isTransfer = tx.type.toLowerCase() == 'transfer';
      dayMap[dateStr]!.add(Transaction(
        title: tx.description,
        subtitle: [
          tx.category ?? tx.type,
          if (tx.subCategory != null && tx.subCategory!.isNotEmpty) tx.subCategory!,
        ].join(' • '),
        amount: tx.amount,
        type: _mapType(tx.type),
        icon: _iconForCategory(tx.category),
        iconColor: isExpense
            ? Colors.white
            : isIncome
                ? const Color(0xFF6B7280)
                : isTransfer
                    ? const Color(0xFF1E40AF)
                    : const Color(0xFF00695C),
        iconBg: isExpense
            ? const Color(0xFFFEECEC)
            : isIncome
                ? const Color(0xFFE5E7EB)
                : isTransfer
                    ? const Color(0xFFDBEAFE)
                    : const Color(0xFFE0F2F1),
        account: tx.accountName ?? '',
        model: tx,
      ));
    }

    final groups = <DayGroup>[];
    final sortedDates = dayMap.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final dateStr in sortedDates) {
      try {
        final dt = DateTime.parse(dateStr);
        groups.add(DayGroup(
          day: dt.day,
          weekday: weekdays[dt.weekday - 1],
          monthYear: '${dt.month.toString().padLeft(2, '0')}.${dt.year}',
          transactions: dayMap[dateStr]!,
        ));
      } catch (_) {
        // Skip unparseable dates
      }
    }
    return groups;
  }

  TransactionType _mapType(String type) {
    switch (type.toLowerCase()) {
      case 'income':
        return TransactionType.income;
      case 'transfer':
        return TransactionType.transfer;
      case 'investment':
        return TransactionType.investment;
      default:
        return TransactionType.expense;
    }
  }

  IconData _iconForCategory(String? category) {
    switch (category?.toLowerCase()) {
      case 'shopping':
        return Icons.shopping_bag;
      case 'food & drink':
        return Icons.restaurant;
      case 'subscription':
        return Icons.subscriptions;
      case 'education':
        return Icons.school;
      case 'transportation':
        return Icons.directions_car;
      case 'entertainment':
        return Icons.movie;
      case 'health':
        return Icons.favorite;
      default:
        return Icons.receipt_long;
    }
  }

  void _changeMonth(int offset) {
    setState(() {
      _currentDate = DateTime(
        _currentDate.year,
        _currentDate.month + offset,
      );
    });
    _loadTransactions();
  }

  String get _formattedMonth {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[_currentDate.month - 1]} ${_currentDate.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final totalSpend = _categories.fold<double>(0, (s, c) => s + c.amount);

    return Stack(
      children: [
      SafeArea(
      child: Column(
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _currentDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      initialDatePickerMode: DatePickerMode.year,
                    );
                    if (picked != null) {
                      setState(() {
                        _currentDate = DateTime(picked.year, picked.month);
                      });
                      _loadTransactions();
                    }
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Icon(Icons.calendar_month_outlined,
                        size: 18, color: Colors.grey.shade700),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _changeMonth(-1),
                  child:
                      Icon(Icons.chevron_left, size: 22, color: Colors.grey.shade700),
                ),
                const SizedBox(width: 6),
                Text(
                  _formattedMonth,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _changeMonth(1),
                  child: Icon(Icons.chevron_right,
                      size: 22, color: Colors.grey.shade700),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showAccountFilter(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _selectedAccount != 'All'
                          ? const Color(0xFF3B3BF9).withValues(alpha: 0.1)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _selectedAccount != 'All'
                            ? const Color(0xFF3B3BF9)
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Icon(
                      Icons.filter_list_rounded,
                      size: 18,
                      color: _selectedAccount != 'All'
                          ? const Color(0xFF3B3BF9)
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Filter Chips ──
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final f = _filters[i];
                final selected = f == _selectedFilter;
                return GestureDetector(
                  onTap: () => setState(() => _selectedFilter = f),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color:
                            selected ? const Color(0xFF1E293B) : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      f,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: selected ? Colors.white : Colors.grey.shade700,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // ── Overview (only for All filter) ──
          if (_selectedFilter == 'All') ...[            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OverviewBarChart(
                income: _totalIncome,
                expense: _totalExpense,
                investment: _totalInvestment,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Total Spend + Segmented Bar (Overview style) ──
          if (totalSpend > 0 && _selectedFilter != 'All')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedFilter == 'Income'
                            ? 'Total Income'
                            : _selectedFilter == 'Investment'
                                ? 'Total Investment'
                                : 'Total Spend',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      Flexible(
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          alignment: WrapAlignment.end,
                          children: _categories.map((c) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: c.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  c.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 14,
                      child: Row(
                        children: _categories.asMap().entries.map((entry) {
                          final i = entry.key;
                          final c = entry.value;
                          return Expanded(
                            flex: (c.amount * 100 / totalSpend).round().clamp(1, 100),
                            child: Container(
                              margin: EdgeInsets.only(
                                right: i < _categories.length - 1 ? 2 : 0,
                              ),
                              color: c.color,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total: ${formatINR(totalSpend, decimals: 0)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _categories.map((c) => formatINR(c.amount, decimals: 0)).join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Transaction List ──
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshTransactions,
              child: Builder(
                builder: (context) {
                  final groups = _filteredGroups;
                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: groups.length,
                    itemBuilder: (context, i) =>
                        _buildDayGroupWidget(groups[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
    if (_deleting)
      Container(
        color: Colors.black26,
        child: const Center(child: CircularProgressIndicator()),
      ),
    ],
    );
  }

  // Account filter lists built from API data
  List<Map<String, String>> get _bankAccountOptions => _bankAccounts.isNotEmpty
      ? _bankAccounts
          .map((a) => {'name': a.name, 'number': ''})
          .toList()
      : [
          {'name': 'Chase Bank', 'number': '••6789'},
          {'name': 'Bank of America', 'number': '••3421'},
        ];

  List<Map<String, String>> get _creditCardOptions => _creditCardAccounts.isNotEmpty
      ? _creditCardAccounts
          .map((a) => {'name': a.name, 'number': ''})
          .toList()
      : [
          {'name': 'Visa', 'number': '••4521'},
          {'name': 'Mastercard', 'number': '••8832'},
        ];

  void _showAccountFilter(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Filter by Account',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  if (_selectedAccount != 'All')
                    GestureDetector(
                      onTap: () {
                        setState(() => _selectedAccount = 'All');
                        Navigator.pop(ctx);
                      },
                      child: const Text(
                        'Clear',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF3B3BF9),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              // Bank Accounts section
              Text(
                'BANK ACCOUNTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              ..._bankAccountOptions.map((a) => _buildAccountOption(
                ctx,
                a['name']!,
                a['number']!,
                Icons.account_balance_outlined,
              )),
              const SizedBox(height: 16),
              // Credit Cards section
              Text(
                'CREDIT CARDS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              ..._creditCardOptions.map((a) => _buildAccountOption(
                ctx,
                a['name']!,
                a['number']!,
                Icons.credit_card,
              )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccountOption(
      BuildContext ctx, String name, String number, IconData icon) {
    final label = number.isNotEmpty ? '$name $number' : name;
    final selected = _selectedAccount == label;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF3B3BF9).withValues(alpha: 0.1)
              : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            size: 20,
            color: selected ? const Color(0xFF3B3BF9) : Colors.grey.shade600),
      ),
      title: Text(
        name,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? const Color(0xFF3B3BF9) : const Color(0xFF1E293B),
        ),
      ),
      subtitle: Text(
        number,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade500,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle, color: Color(0xFF3B3BF9), size: 22)
          : Icon(Icons.circle_outlined, color: Colors.grey.shade300, size: 22),
      onTap: () {
        setState(() => _selectedAccount = label);
        Navigator.pop(ctx);
      },
    );
  }

  Widget _buildDayGroupWidget(DayGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '${group.day}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
                height: 1,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${group.weekday}  ${group.monthYear}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: Colors.grey.shade500,
                height: 1,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 1,
                color: Colors.grey.shade200,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...group.transactions.map((t) => _buildTransactionTile(t)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTransactionTile(Transaction t) {
    String amountStr;
    Color amountColor;
    switch (t.type) {
      case TransactionType.expense:
        amountStr = t.amount < 0
            ? '-${formatINR(t.amount.abs())}'
            : formatINR(t.amount.abs());
        amountColor = const Color(0xFFEF4444);
        break;
      case TransactionType.income:
        amountStr = formatINR(t.amount.abs());
        amountColor = const Color(0xFF22C55E);
        break;
      case TransactionType.transfer:
        amountStr = formatINR(t.amount.abs());
        amountColor = const Color(0xFF3B82F6);
        break;
      case TransactionType.investment:
        amountStr = formatINR(t.amount.abs());
        amountColor = const Color(0xFF6366F1);
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Icon / Avatar
          if (t.avatarUrl != null)
            CircleAvatar(
              radius: 20,
              backgroundImage: NetworkImage(t.avatarUrl!),
            )
          else
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: t.iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(t.icon, size: 20, color: t.iconColor),
            ),
          const SizedBox(width: 12),
          // Title + Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          // Amount + Type
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amountStr,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: amountColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                t.typeLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          // Actions popup
          if (t.model != null)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 20, color: Colors.grey.shade400),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: Color(0xFF3B3BF9)),
                    SizedBox(width: 8),
                    Text('Edit'),
                  ],
                )),
                const PopupMenuItem(value: 'copy', child: Row(
                  children: [
                    Icon(Icons.copy_outlined, size: 18, color: Color(0xFF6B7280)),
                    SizedBox(width: 8),
                    Text('Copy as New'),
                  ],
                )),
                const PopupMenuItem(value: 'delete', child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
                  ],
                )),
              ],
              onSelected: (action) {
                switch (action) {
                  case 'edit':
                    _showEditDialog(t.model!);
                    break;
                  case 'copy':
                    _copyTransaction(t.model!);
                    break;
                  case 'delete':
                    _deleteTransaction(t.model!);
                    break;
                }
              },
            ),
        ],
      ),
    );
  }

  Future<void> _deleteTransaction(TransactionModel tx) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: Text('Delete "${tx.description}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _deleting = true);
      try {
        await _api.deleteTransaction(tx.id);
        final month = DateFormat('MMM').format(_currentDate).toLowerCase();
        final year = _currentDate.year.toString();
        AppDataCache().removeTransaction(month, year, tx.id);
        if (mounted) {
          setState(() {
            _transactions.removeWhere((t) => t.id == tx.id);
            _deleting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transaction deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _deleting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }

  void _copyTransaction(TransactionModel tx) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(prefill: tx),
      ),
    ).then((result) {
      if (result == true) _refreshTransactions();
    });
  }

  void _showEditDialog(TransactionModel tx) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(prefill: tx, isEdit: true),
      ),
    ).then((result) {
      if (result == true) _refreshTransactions();
    });
  }

  Future<void> _refreshTransactions() async {
    final month = DateFormat('MMM').format(_currentDate).toLowerCase();
    final year = _currentDate.year.toString();
    AppDataCache().invalidateTransactionCache(month, year);
    await _loadTransactions();
  }
}
