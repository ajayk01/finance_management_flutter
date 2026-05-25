import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/currency_formatter.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _api = ApiService();
  int _mainTab = 0; // 0=Income, 1=Outcome, 2=Budget
  int _categoryFilter = 0; // 0=All, then dynamic category indices
  bool _loading = true;
  bool _tableLoading = false;

  // Yearly bar chart data
  List<String> _months = [];
  List<double> _barValues = [];
  int _highlightedBar = -1;

  // Transactions
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _filteredTransactions = [];

  // Categories for filter
  List<String> _categoryNames = ['All'];

  // Summary
  double _totalAmount = 0;
  double _changePercent = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  double _parseAmount(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;
    return 0;
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final month = DateFormat('MMM').format(now).toLowerCase();
    final year = now.year.toString();

    try {
      final results = await Future.wait([
        _api.getYearlySummary(year),
        _mainTab == 0
            ? _api.getMonthlyIncome(month: month, year: year)
            : _mainTab == 1
                ? _api.getMonthlyExpenses(month: month, year: year)
                : _api.getCategories(type: 'expense'),
      ]);

      final yearlyData = results[0];
      final detailData = results[1];

      // Parse yearly summary for bar chart
      final summary = yearlyData['summaryData'] as List? ?? [];
      final months = <String>[];
      final values = <double>[];
      for (final item in summary) {
        final m = item as Map<String, dynamic>;
        final monthName = (m['month'] ?? '').toString();
        if (monthName.isNotEmpty) months.add(monthName.substring(0, 3));
        if (_mainTab == 0) {
          values.add(_parseAmount(m['income'] ?? m['totalIncome']));
        } else if (_mainTab == 1) {
          values.add(_parseAmount(m['expense'] ?? m['totalExpense']));
        } else {
          values.add(_parseAmount(m['expense'] ?? m['totalExpense']));
        }
      }

      // Find current month index for highlight
      final currentMonthAbbr = DateFormat('MMM').format(now);
      int highlightIdx = months.indexWhere(
          (m) => m.toLowerCase() == currentMonthAbbr.toLowerCase());
      if (highlightIdx < 0 && months.isNotEmpty) highlightIdx = months.length - 1;

      // Parse transactions – use same source as ExpensePieChart for consistency
      List<Map<String, dynamic>> txns = [];
      if (_mainTab == 0) {
        txns = (detailData['monthlyIncome'] as List?
                ?? detailData['rawTransactions'] as List?
                ?? [])
            .map((e) => e as Map<String, dynamic>)
            .toList();
      } else if (_mainTab == 1) {
        txns = (detailData['monthlyExpenses'] as List?
                ?? detailData['rawTransactions'] as List?
                ?? [])
            .map((e) => e as Map<String, dynamic>)
            .toList();
      }

      // Extract unique categories
      final catSet = <String>{'All'};
      for (final t in txns) {
        final cat = (t['category'] ?? t['subCategory'] ?? '').toString();
        if (cat.isNotEmpty) catSet.add(cat);
      }

      // Calculate change %
      double change = 0;
      if (values.length >= 2) {
        final prev = values[values.length - 2];
        final curr = values.last;
        if (prev > 0) change = ((curr - prev) / prev) * 100;
      }

      // Current month total from transactions – use 'expense' key first (same as ExpensePieChart & HomeScreen)
      double currentMonthTotal = 0;
      for (final t in txns) {
        currentMonthTotal += _parseAmount(t['expense'] ?? t['amount']);
      }

      if (mounted) {
        setState(() {
          _months = months;
          _barValues = values;
          _highlightedBar = highlightIdx;
          _transactions = txns;
          _filteredTransactions = txns;
          _categoryNames = catSet.toList();
          _totalAmount = currentMonthTotal > 0 ? currentMonthTotal : (values.isNotEmpty ? values.last : 0);
          _changePercent = change;
          _categoryFilter = 0;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[AnalyticsScreen] Error: $e');
      if (mounted) {
        setState(() {
          _months = ['Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
          _barValues = [2800, 3100, 2600, 3400, 2500, 2200];
          _highlightedBar = 3;
          _transactions = [];
          _filteredTransactions = [];
          _totalAmount = 1980;
          _changePercent = 5.2;
          _loading = false;
        });
      }
    }
  }

  /// Map 3-letter month abbreviation to the lowercase form expected by the API.
  String _monthAbbr(int barIndex) {
    if (barIndex < 0 || barIndex >= _months.length) {
      return DateFormat('MMM').format(DateTime.now()).toLowerCase();
    }
    return _months[barIndex].toLowerCase();
  }

  /// Fetch transactions for the month represented by [barIndex].
  Future<void> _loadMonthData(int barIndex) async {
    setState(() => _tableLoading = true);
    final month = _monthAbbr(barIndex);
    final year = DateTime.now().year.toString();

    try {
      final detailData = _mainTab == 0
          ? await _api.getMonthlyIncome(month: month, year: year)
          : await _api.getMonthlyExpenses(month: month, year: year);

      List<Map<String, dynamic>> txns = [];
      if (_mainTab == 0) {
        txns = (detailData['monthlyIncome'] as List?
                ?? detailData['rawTransactions'] as List?
                ?? [])
            .map((e) => e as Map<String, dynamic>)
            .toList();
      } else {
        txns = (detailData['monthlyExpenses'] as List?
                ?? detailData['rawTransactions'] as List?
                ?? [])
            .map((e) => e as Map<String, dynamic>)
            .toList();
      }

      final catSet = <String>{'All'};
      for (final t in txns) {
        final cat = (t['category'] ?? t['subCategory'] ?? '').toString();
        if (cat.isNotEmpty) catSet.add(cat);
      }

      double monthTotal = 0;
      for (final t in txns) {
        monthTotal += _parseAmount(t['expense'] ?? t['amount']);
      }

      if (mounted) {
        setState(() {
          _transactions = txns;
          _filteredTransactions = txns;
          _categoryNames = catSet.toList();
          _categoryFilter = 0;
          _totalAmount = monthTotal > 0
              ? monthTotal
              : (barIndex >= 0 && barIndex < _barValues.length
                  ? _barValues[barIndex]
                  : 0);
          _tableLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[AnalyticsScreen] _loadMonthData error: $e');
      if (mounted) setState(() => _tableLoading = false);
    }
  }

  void _filterByCategory(int index) {
    setState(() {
      _categoryFilter = index;
      if (index == 0) {
        _filteredTransactions = _transactions;
      } else {
        final cat = _categoryNames[index];
        _filteredTransactions = _transactions.where((t) {
          final tCat = (t['category'] ?? t['subCategory'] ?? '').toString();
          return tCat.toLowerCase() == cat.toLowerCase();
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F8),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildMainTabs(),
                      const SizedBox(height: 20),
                      if (_loading)
                        const SizedBox(
                          height: 300,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        _buildAnalyticsCard(),
                        const SizedBox(height: 24),
                        if (_mainTab != 2) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildCategoryTabs(),
                                Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  color: Colors.grey.shade200,
                                ),
                                if (_tableLoading)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 40),
                                    child: Center(child: CircularProgressIndicator()),
                                  )
                                else
                                  _buildTransactionList(),
                              ],
                            ),
                          ),
                        ] else
                          _buildBudgetView(),
                      ],
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── App Bar ───────────────────────────────────────────────

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Scaffold.of(context).openDrawer(),
            child: Icon(Icons.menu, color: Colors.grey.shade800, size: 24),
          ),
          const Expanded(
            child: Text(
              'Analytics',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
          Icon(Icons.file_download_outlined, color: Colors.grey.shade800, size: 24),
        ],
      ),
    );
  }

  // ─── Main Tabs (Income / Outcome / Budget) ─────────────────

  Widget _buildMainTabs() {
    final labels = ['Income', 'Outcome', 'Budget'];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEF0),
        borderRadius: BorderRadius.circular(30),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = _mainTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_mainTab != i) {
                  setState(() => _mainTab = i);
                  _loadData();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? Colors.black : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── Analytics Card with Bar Chart ─────────────────────────

  Widget _buildAnalyticsCard() {
    final typeLabel = _mainTab == 0
        ? 'Income'
        : _mainTab == 1
            ? 'Expense'
            : 'Budget';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                '$typeLabel Analytics',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Monthly',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Amount and change
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatINR(_totalAmount),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${_changePercent >= 0 ? '↗' : '↘'}${_changePercent.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _changePercent >= 0
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Bar Chart
          SizedBox(
            height: 220,
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _barValues.length * 60.0 < MediaQuery.of(context).size.width - 80
                      ? MediaQuery.of(context).size.width - 80
                      : _barValues.length * 60.0,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _buildBarChart(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    if (_barValues.isEmpty) {
      return const Center(child: Text('No data'));
    }

    final maxVal = _barValues.reduce((a, b) => a > b ? a : b);
    final maxY = (maxVal * 1.3).ceilToDouble();
    final interval = _calculateInterval(maxY);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        minY: 0,
        barTouchData: BarTouchData(
          touchCallback: (event, response) {
            if (response != null &&
                response.spot != null &&
                event is FlTapUpEvent) {
              final tappedIndex = response.spot!.touchedBarGroupIndex;
              setState(() {
                _highlightedBar = tappedIndex;
              });
              if (_mainTab != 2) {
                _loadMonthData(tappedIndex);
              }
            }
          },
          touchTooltipData: BarTouchTooltipData(
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            tooltipMargin: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                formatINR(rod.toY, decimals: 0),
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: interval,
              getTitlesWidget: (value, _) {
                if (value == 0) return const SizedBox.shrink();
                String label;
                if (value >= 1000) {
                  label = '₹${(value / 1000).toStringAsFixed(0)}k';
                } else {
                  label = '₹${value.toInt()}';
                }
                return Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= _months.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _months[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: i == _highlightedBar
                          ? Colors.black
                          : Colors.grey.shade400,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.grey.shade100,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(_barValues.length, (i) {
          final isHighlighted = i == _highlightedBar;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: _barValues[i],
                width: 28,
                borderRadius: BorderRadius.circular(6),
                color: isHighlighted
                    ? const Color(0xFF1E1E2D)
                    : const Color(0xFFE8E8EC),
              ),
            ],
          );
        }),
      ),
    );
  }

  double _calculateInterval(double maxY) {
    if (maxY <= 5000) return 1000;
    if (maxY <= 10000) return 2000;
    if (maxY <= 50000) return 10000;
    if (maxY <= 100000) return 20000;
    return 50000;
  }

  // ─── Category Filter Tabs ─────────────────────────────────

  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categoryNames.length,
        separatorBuilder: (_, __) => const SizedBox(width: 24),
        itemBuilder: (_, i) {
          final selected = _categoryFilter == i;
          return GestureDetector(
            onTap: () => _filterByCategory(i),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _categoryNames[i],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? Colors.black : Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 6),
                if (selected)
                  Container(
                    height: 2,
                    width: 24,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Category Summary (for "All" tab) ──────────────────────

  List<Map<String, dynamic>> get _categorySummary {
    final catTotals = <String, double>{};
    for (final t in _transactions) {
      final cat = (t['category'] ?? t['subCategory'] ?? 'Other').toString();
      final amt = _parseAmount(t['amount'] ?? t['expense']);
      catTotals[cat] = (catTotals[cat] ?? 0) + amt;
    }
    // Sort by amount descending
    final sorted = catTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .map((e) => {'category': e.key, 'total': e.value})
        .toList();
  }

  // ─── Transaction List ──────────────────────────────────────

  Widget _buildTransactionList() {
    // "All" tab → show category totals
    if (_categoryFilter == 0) {
      final summary = _categorySummary;
      if (summary.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              'No transactions found',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ),
        );
      }
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: summary.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 0.5,
          color: Colors.grey.shade200,
        ),
        itemBuilder: (_, i) => _buildCategorySummaryTile(summary[i]),
      );
    }

    // Specific category tab → show transactions grouped by subcategory
    if (_filteredTransactions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'No transactions found',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ),
      );
    }

    // Group by subcategory
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final t in _filteredTransactions) {
      final sub = (t['subCategory'] ?? 'Other').toString();
      grouped.putIfAbsent(sub, () => []).add(t);
    }
    final subCategories = grouped.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int s = 0; s < subCategories.length; s++) ...[
          if (s > 0)
            Divider(height: 1, thickness: 0.5, color: Colors.grey.shade200),
          _buildSubCategoryHeader(
            subCategories[s],
            grouped[subCategories[s]]!,
          ),
          ...grouped[subCategories[s]]!.asMap().entries.map((entry) {
            final widgets = <Widget>[];
            if (entry.key > 0) {
              widgets.add(Padding(
                padding: const EdgeInsets.only(left: 58),
                child: Divider(height: 1, thickness: 0.5, color: Colors.grey.shade100),
              ));
            }
            widgets.add(_buildTransactionTile(entry.value));
            return Column(children: widgets);
          }),
        ],
      ],
    );
  }

  Widget _buildSubCategoryHeader(
      String subCategory, List<Map<String, dynamic>> txns) {
    final total = txns.fold<double>(
        0, (sum, t) => sum + _parseAmount(t['amount'] ?? t['expense']));
    final isIncome = _mainTab == 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(
        children: [
          Text(
            subCategory,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(${txns.length})',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
          const Spacer(),
          Text(
            '${isIncome ? '+' : '-'}${formatINR(total)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isIncome
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySummaryTile(Map<String, dynamic> item) {
    final category = (item['category'] ?? '').toString();
    final total = (item['total'] as double?) ?? 0;
    final isIncome = _mainTab == 0;

    final colorIndex = category.hashCode.abs() % _avatarColors.length;
    final avatarColor = _avatarColors[colorIndex];
    final initials = category.isNotEmpty
        ? category.split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase()
        : '?';

    // Count transactions in this category
    final count = _transactions.where((t) {
      final cat = (t['category'] ?? t['subCategory'] ?? 'Other').toString();
      return cat == category;
    }).length;

    return GestureDetector(
      onTap: () {
        // Tap to switch to that category's tab
        final idx = _categoryNames.indexWhere(
            (c) => c.toLowerCase() == category.toLowerCase());
        if (idx > 0) _filterByCategory(idx);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: avatarColor.withValues(alpha: 0.15),
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: avatarColor,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$count transaction${count == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${isIncome ? '+' : '-'}${formatINR(total)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isIncome
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFEF4444),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> txn) {
    final description = (txn['description'] ?? 'Transaction').toString();
    final amount = _parseAmount(txn['amount'] ?? txn['expense']);
    final date = (txn['date'] ?? '').toString();
    final subCategory = (txn['subCategory'] ?? '').toString();
    final isIncome = _mainTab == 0;

    // Generate avatar color from description
    final colorIndex = description.hashCode.abs() % _avatarColors.length;
    final avatarColor = _avatarColors[colorIndex];
    final initials = description.isNotEmpty
        ? description.split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase()
        : '?';

    // Format date
    String formattedDate = date;
    try {
      final parsed = DateTime.tryParse(date);
      if (parsed != null) {
        formattedDate = DateFormat('dd MMM yyyy').format(parsed);
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          CircleAvatar(
            radius: 22,
            backgroundColor: avatarColor.withValues(alpha: 0.15),
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: avatarColor,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Title and date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  formattedDate,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),

          // Amount and subcategory
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isIncome ? '+' : '-'}${formatINR(amount)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isIncome
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444),
                ),
              ),
              if (subCategory.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subCategory,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static const _avatarColors = [
    Color(0xFF6366F1),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
    Color(0xFFEF4444),
    Color(0xFF22C55E),
  ];

  // ─── Budget View ───────────────────────────────────────────

  Widget _buildBudgetView() {
    return Column(
      children: [
        if (_transactions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'Budget data shown in chart above',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              ),
            ),
          ),
      ],
    );
  }
}
