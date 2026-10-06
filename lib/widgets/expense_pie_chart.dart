import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'dart:math';
import '../services/direct_sql_service.dart';
import '../models/models.dart' show Category;
import '../utils/currency_formatter.dart';

class ExpensePieChart extends StatefulWidget {
  const ExpensePieChart({super.key, this.categories});

  final List<Category>? categories;

  @override
  State<ExpensePieChart> createState() => _ExpensePieChartState();
}

class _ExpensePieChartState extends State<ExpensePieChart> {
  late int _selectedYear;
  late int _selectedMonth;
  int _currentPage = 0;

  bool _loading = true;
  int _loadRequestId = 0;
  final ScrollController _headerControlsController = ScrollController();
  int? _touchedIndex;
  bool _showTable = false;
  String? _selectedTableCategory;
  double _budget = 0;
  List<MonthlyPieChartCategory> _expenseData = [];
  List<MonthlyPieChartCategory> _incomeData = [];
  List<MonthlyPieChartCategory> _investmentData = [];
  List<_ExpenseCategory> _categories = [];
  List<_ExpenseCategory> _incomeCategories = [];
  List<_ExpenseCategory> _investmentCategories = [];

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const _expenseColors = [
    Color(0xFFE53935), Color(0xFFEF5350), Color(0xFFF44336),
    Color(0xFFE57373), Color(0xFFEF9A9A), Color(0xFFFFCDD2),
    Color(0xFFC62828), Color(0xFFFF8A80),
  ];
  static const _incomeColors = [
    Color(0xFF22C55E), Color(0xFF4ADE80), Color(0xFF86EFAC),
    Color(0xFF16A34A), Color(0xFF15803D), Color(0xFFA7F3D0),
  ];
  static const _investColors = [
    Color(0xFF0891B2), Color(0xFF06B6D4), Color(0xFF67E8F9),
    Color(0xFF0E7490), Color(0xFF155E75), Color(0xFFA5F3FC),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _loadPieData();
  }

  Future<void> _loadPieData() async {
    final requestId = ++_loadRequestId;
    final selectedYear = _selectedYear;
    final selectedMonth = _selectedMonth;
    setState(() => _loading = true);
    try {
      final month = DateFormat('MMM')
        .format(DateTime(selectedYear, selectedMonth))
        .toLowerCase();
      final chartData = await DirectSqlService.getMonthlyPieChartData(
      month,
      selectedYear.toString(),
      );
      final expenseCategories =
          _fromAggregates(chartData.expenses, _expenseColors);
      final incomeCategories =
          _fromAggregates(chartData.income, _incomeColors);
      final investmentCategories =
          _fromAggregates(chartData.investments, _investColors);
      final budget = (widget.categories ?? const <Category>[])
        .where((category) => category.type == 'expense')
        .fold<double>(0, (sum, category) => sum + category.budget);
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      setState(() {
        _expenseData = chartData.expenses;
        _incomeData = chartData.income;
        _investmentData = chartData.investments;
        _categories = expenseCategories;
        _incomeCategories = incomeCategories;
        _investmentCategories = investmentCategories;
        _budget = budget;
        _selectedTableCategory = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      setState(() => _loading = false);
    }
  }

  List<_ExpenseCategory> _fromAggregates(
    List<MonthlyPieChartCategory> categories,
    List<Color> colors,
  ) {
    return categories
        .where((category) => category.amount != 0)
        .toList()
        .asMap()
        .entries
        .map((entry) => _ExpenseCategory(
              entry.value.name,
              entry.value.amount,
              colors[entry.key % colors.length],
            ))
        .toList();
  }

  double get _total =>
      _categories.fold(0, (sum, c) => sum + c.amount);

  double get _incomeTotal =>
      _incomeCategories.fold(0, (sum, c) => sum + c.amount);

  double get _investmentTotal =>
      _investmentCategories.fold(0, (sum, c) => sum + c.amount);

  @override
  void dispose() {
    _headerControlsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          Text(
            _pageTitles[_currentPage],
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 12),
          Scrollbar(
            controller: _headerControlsController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _headerControlsController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _dropdownButton(
                    label: _monthNames[_selectedMonth - 1].substring(0, 3),
                    onTap: () => _showMonthDropdown(),
                  ),
                  const SizedBox(width: 10),
                  _dropdownButton(
                    label: '$_selectedYear',
                    onTap: () => _showYearDropdown(),
                  ),
                  const SizedBox(width: 10),
                  _dropdownButton(
                    label: _showTable ? 'Chart' : 'Table',
                    icon: _showTable
                        ? Icons.pie_chart_outline
                        : Icons.table_chart_outlined,
                    onTap: _loading
                        ? () {}
                        : () => setState(() {
                              _showTable = !_showTable;
                              _selectedTableCategory = null;
                            }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 300,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _showTable
                    ? _buildTableView()
                    : PageView(
              controller: PageController(initialPage: _currentPage),
              onPageChanged: (index) => setState(() {
                _currentPage = index;
                _touchedIndex = null;
              }),
              children: [
                _buildDonutPage(_categories, _total, showBudget: true),
                _buildDonutPage(_incomeCategories, _incomeTotal),
                _buildDonutPage(_investmentCategories, _investmentTotal),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loading || _showTable)
            const SizedBox.shrink()
          else
            _buildCategoryLegend(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) => _dot(i)),
          ),
        ],
      ),
    );
  }

  static const _pageTitles = ['Expenses', 'Income', 'Investments'];

  Widget _dot(int index) {
    final isActive = index == _currentPage;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF3B3BF9) : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildDonutPage(List<_ExpenseCategory> cats, double total, {bool showBudget = false}) {
    return GestureDetector(
      onTapDown: (details) {
        _handleTouch(details.localPosition, cats, total);
      },
      child: CustomPaint(
        painter: _DonutWithLabelsPainter(
          cats,
          total,
          budget: showBudget ? _budget : 0,
          touchedIndex: _touchedIndex,
        ),
      ),
    );
  }

  void _handleTouch(Offset pos, List<_ExpenseCategory> cats, double total) {
    if (cats.isEmpty || total <= 0) return;
    final center = Offset(MediaQuery.of(context).size.width / 2 - 20, 150);
    final dx = pos.dx - center.dx;
    final dy = pos.dy - center.dy;
    final distance = sqrt(dx * dx + dy * dy);

    if (distance < 82 || distance > 138) {
      setState(() => _touchedIndex = null);
      return;
    }

    var angle = atan2(dy, dx);
    if (angle < -pi / 2) angle += 2 * pi;
    angle += pi / 2;
    if (angle > 2 * pi) angle -= 2 * pi;

    double cumulative = 0;
    for (int i = 0; i < cats.length; i++) {
      cumulative += (cats[i].amount / total) * 2 * pi;
      if (angle <= cumulative) {
        setState(() => _touchedIndex = i);
        return;
      }
    }
  }

  List<_ExpenseCategory> get _currentCategories {
    switch (_currentPage) {
      case 1: return _incomeCategories;
      case 2: return _investmentCategories;
      default: return _categories;
    }
  }

  double get _currentTotal {
    switch (_currentPage) {
      case 1: return _incomeTotal;
      case 2: return _investmentTotal;
      default: return _total;
    }
  }

  List<MonthlyPieChartCategory> get _currentTableData {
    switch (_currentPage) {
      case 1:
        return _incomeData;
      case 2:
        return _investmentData;
      default:
        return _expenseData;
    }
  }

  Widget _buildTableView() {
    final isShowingSubcategories = _selectedTableCategory != null;
    final selectedCategory = isShowingSubcategories
        ? _currentTableData.firstWhere(
            (category) => category.name == _selectedTableCategory,
          )
        : null;
    final rows = isShowingSubcategories
        ? selectedCategory!.subcategories.entries.toList()
        : _currentTableData
            .map((category) => MapEntry(category.name, category.amount))
            .toList();
    rows.sort((first, second) => second.value.compareTo(first.value));
    final isInvestmentTable = _currentPage == 2;
    final firstColumnTitle = isInvestmentTable && !isShowingSubcategories
        ? 'Investment account'
        : isShowingSubcategories
            ? 'Subcategory'
            : 'Category';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isShowingSubcategories)
          TextButton.icon(
            onPressed: () => setState(() => _selectedTableCategory = null),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(_selectedTableCategory!),
          )
        else
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Category totals',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No transactions for this period.'))
              : SingleChildScrollView(
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(),
                      1: IntrinsicColumnWidth(),
                    },
                    border: const TableBorder(
                      horizontalInside: BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: Color(0xFFF5F5F8)),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(firstColumnTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Total', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      ...rows.map((entry) => TableRow(
                            children: [
                              InkWell(
                                onTap: isShowingSubcategories || isInvestmentTable
                                    ? null
                                    : () => setState(() {
                                          _selectedTableCategory = entry.key;
                                        }),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(entry.key)),
                                      if (!isShowingSubcategories)
                                        const Icon(Icons.chevron_right, size: 18),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  formatINR(entry.value),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          )),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildCategoryLegend() {
    final cats = _currentCategories;
    final total = _currentTotal;
    if (cats.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 16,
      runSpacing: 10,
      children: List.generate(cats.length, (i) {
        final cat = cats[i];
        final percent = total > 0 ? (cat.amount / total * 100).round() : 0;
        final isSelected = i == _touchedIndex;
        return GestureDetector(
          onTap: () => setState(() => _touchedIndex = _touchedIndex == i ? null : i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? cat.color.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: cat.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${cat.name} $percent%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _showMonthDropdown() async {
    final result = await showMenu<int>(
      context: context,
      position: const RelativeRect.fromLTRB(200, 80, 20, 0),
      items: List.generate(12, (i) {
        return PopupMenuItem(
          value: i + 1,
          child: Text(_monthNames[i]),
        );
      }),
    );
    if (result != null) {
      setState(() {
        _selectedMonth = result;
      });
      _loadPieData();
    }
  }

  void _showYearDropdown() async {
    final currentYear = DateTime.now().year;
    final result = await showMenu<int>(
      context: context,
      position: const RelativeRect.fromLTRB(280, 80, 20, 0),
      items: List.generate(5, (i) {
        final year = currentYear - i;
        return PopupMenuItem(
          value: year,
          child: Text('$year'),
        );
      }),
    );
    if (result != null) {
      setState(() {
        _selectedYear = result;
      });
      _loadPieData();
    }
  }

  Widget _dropdownButton({
    required String label,
    required VoidCallback onTap,
    IconData icon = Icons.keyboard_arrow_down,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 16, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }
}

class _ExpenseCategory {
  final String name;
  final double amount;
  final Color color;

  const _ExpenseCategory(this.name, this.amount, this.color);
}

class _DonutWithLabelsPainter extends CustomPainter {
  final List<_ExpenseCategory> categories;
  final double total;
  final double budget;
  final int? touchedIndex;

  _DonutWithLabelsPainter(this.categories, this.total, {this.budget = 0, this.touchedIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const outerRadius = 100.0;
    const strokeWidth = 18.0;
    const gapAngle = 0.08;

    if (categories.isEmpty || total <= 0) {
      // Draw empty ring
      final emptyPaint = Paint()
        ..color = const Color(0xFFE8E8E8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(center, outerRadius, emptyPaint);
      _drawCenterText(canvas, center, size, 0);
      return;
    }

    // Draw donut segments
    double startAngle = -pi / 2;
    final midAngles = <double>[];

    for (int i = 0; i < categories.length; i++) {
      final fraction = categories[i].amount / total;
      final sweepAngle = fraction * 2 * pi - gapAngle;

      final isSelected = i == touchedIndex;
      final radius = isSelected ? outerRadius + 4 : outerRadius;
      final width = isSelected ? strokeWidth + 4 : strokeWidth;

      final paint = Paint()
        ..color = categories[i].color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + gapAngle / 2,
        sweepAngle,
        false,
        paint,
      );

      midAngles.add(startAngle + (fraction * 2 * pi) / 2);
      startAngle += fraction * 2 * pi;
    }

    // Draw percentage labels around the donut
    for (int i = 0; i < categories.length; i++) {
      final angle = midAngles[i];
      final fraction = categories[i].amount / total;
      final percent = (fraction * 100).round();
      if (percent < 2) continue;

      const labelRadius = outerRadius + strokeWidth / 2 + 20;
      final labelPos = Offset(
        center.dx + labelRadius * cos(angle),
        center.dy + labelRadius * sin(angle),
      );

      final labelPainter = TextPainter(
        text: TextSpan(
          text: '$percent%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();

      labelPainter.paint(
        canvas,
        labelPos - Offset(labelPainter.width / 2, labelPainter.height / 2),
      );
    }

    // Draw center text
    _drawCenterText(canvas, center, size, total);
  }

  void _drawCenterText(Canvas canvas, Offset center, Size size, double total) {
    final selected = (touchedIndex != null && touchedIndex! < categories.length)
        ? categories[touchedIndex!]
        : null;

    if (selected != null) {
      // Show selected category info
      final percent = total > 0 ? (selected.amount / total * 100).round() : 0;

      // Percentage pill
      final pillText = TextPainter(
        text: TextSpan(
          text: '$percent%',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B7280),
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      final pillWidth = pillText.width + 20;
      const pillHeight = 28.0;
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(center.dx, center.dy - 48), width: pillWidth, height: pillHeight),
        const Radius.circular(14),
      );
      canvas.drawRRect(pillRect, Paint()..color = const Color(0xFFF0F0F0));
      pillText.paint(canvas, Offset(center.dx - pillText.width / 2, center.dy - 48 - pillText.height / 2));

      // Category name
      final nameLabel = TextPainter(
        text: TextSpan(
          text: selected.name,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      nameLabel.paint(canvas, Offset(center.dx - nameLabel.width / 2, center.dy - 22));

      // Category amount
      final amountPainter = TextPainter(
        text: TextSpan(
          text: formatINR(selected.amount),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade900,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      amountPainter.paint(canvas, Offset(center.dx - amountPainter.width / 2, center.dy - 4));

      // "of total"
      final ofLabel = TextPainter(
        text: TextSpan(
          text: 'of ${formatINR(total)}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      ofLabel.paint(canvas, Offset(center.dx - ofLabel.width / 2, center.dy + 24));
      return;
    }

    // Default: show total
    final percent = budget > 0 ? ((total / budget) * 100).round() : 0;

    // Draw percentage pill if budget exists
    if (budget > 0) {
      final pillText = TextPainter(
        text: TextSpan(
          text: '$percent%',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B7280),
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();

      final pillWidth = pillText.width + 20;
      const pillHeight = 28.0;
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(center.dx, center.dy - 48), width: pillWidth, height: pillHeight),
        const Radius.circular(14),
      );
      canvas.drawRRect(pillRect, Paint()..color = const Color(0xFFF0F0F0));
      pillText.paint(canvas, Offset(center.dx - pillText.width / 2, center.dy - 48 - pillText.height / 2));
    }

    // "You've Spent" label
    final spentLabel = TextPainter(
      text: TextSpan(
        text: "You've Spent",
        style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    spentLabel.paint(canvas, Offset(center.dx - spentLabel.width / 2, center.dy - 22));

    // Amount
    final amountPainter = TextPainter(
      text: TextSpan(
        text: formatINR(total),
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Colors.grey.shade900,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    amountPainter.paint(canvas, Offset(center.dx - amountPainter.width / 2, center.dy - 4));

    // "of ₹X" below amount
    if (budget > 0) {
      final ofLabel = TextPainter(
        text: TextSpan(
          text: 'of ${formatINR(budget)}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      ofLabel.paint(canvas, Offset(center.dx - ofLabel.width / 2, center.dy + 24));
    }
  }

  @override
  bool shouldRepaint(covariant _DonutWithLabelsPainter oldDelegate) {
    if (oldDelegate.total != total ||
        oldDelegate.budget != budget ||
        oldDelegate.touchedIndex != touchedIndex ||
        oldDelegate.categories.length != categories.length) {
      return true;
    }

    for (var index = 0; index < categories.length; index++) {
      final previous = oldDelegate.categories[index];
      final current = categories[index];
      if (previous.name != current.name ||
          previous.amount != current.amount ||
          previous.color != current.color) {
        return true;
      }
    }
    return false;
  }
}
