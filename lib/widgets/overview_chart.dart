import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import '../utils/currency_formatter.dart';

class OverviewChart extends StatefulWidget {
  const OverviewChart({super.key});

  @override
  State<OverviewChart> createState() => _OverviewChartState();
}

class _OverviewChartState extends State<OverviewChart> {
  final _api = ApiService();
  bool _loading = true;
  List<String> _months = [];
  List<double> _expense = [];
  List<double> _income = [];
  List<double> _investment = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final data = await _api.getYearlySummary(
        DateTime.now().year.toString(),
      );
      final summary = data['summaryData'] as List? ?? data['summary'] as List? ?? [];
      final months = <String>[];
      final expense = <double>[];
      final income = <double>[];
      final investment = <double>[];
      for (final item in summary) {
        final m = item as Map<String, dynamic>;
        months.add((m['month'] ?? '').toString());
        expense.add((m['expense'] ?? m['totalExpense'] ?? 0).toDouble());
        income.add((m['income'] ?? m['totalIncome'] ?? 0).toDouble());
        investment.add((m['investment'] ?? m['totalInvestment'] ?? 0).toDouble());
      }
      if (mounted) {
        setState(() {
          _months = months;
          _expense = expense;
          _income = income;
          _investment = investment;
          _loading = false;
        });
      }
    } catch (_) {
      // Use fallback static data
      if (mounted) {
        setState(() {
          _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep'];
          _expense = [800, 950, 1100, 1000, 1200, 1350, 1150, 1400, 1650];
          _income = [2000, 2100, 2200, 2150, 2300, 2400, 2350, 2500, 2600];
          _investment = [300, 350, 400, 450, 500, 550, 600, 650, 700];
          _loading = false;
        });
      }
    }
  }

  double get _totalExpense => _expense.isEmpty ? 0 : _expense.reduce((a, b) => a + b);
  double get _totalIncome => _income.isEmpty ? 0 : _income.reduce((a, b) => a + b);
  double get _totalInvestment => _investment.isEmpty ? 0 : _investment.reduce((a, b) => a + b);
  double get _totalAmount => _totalExpense + _totalIncome + _totalInvestment;

  List<FlSpot> _spots(List<double> data) =>
      List.generate(data.length, (i) => FlSpot(i.toDouble(), data[i]));

  double get _maxY {
    if (_income.isEmpty && _expense.isEmpty && _investment.isEmpty) return 3000;
    final all = [..._income, ..._expense, ..._investment];
    final max = all.reduce((a, b) => a > b ? a : b);
    return (max * 1.2).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const SizedBox(height: 260, child: Center(child: CircularProgressIndicator())),
      );
    }
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
            'Overview',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Total: ${formatINR(_totalAmount, decimals: 0)}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 500,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 500,
                      getTitlesWidget: (value, _) => Text(
                        '${(value / 1000).toStringAsFixed(1)}k',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= _months.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _months[i],
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minY: 0,
                maxY: _maxY,
                lineBarsData: [
                  // Income line
                  LineChartBarData(
                    spots: _spots(_income),
                    isCurved: true,
                    color: const Color(0xFF3B3BF9),
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF3B3BF9).withValues(alpha: 0.08),
                    ),
                  ),
                  // Expense line
                  LineChartBarData(
                    spots: _spots(_expense),
                    isCurved: true,
                    color: const Color(0xFFFF6B6B),
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                  ),
                  // Investment line
                  LineChartBarData(
                    spots: _spots(_investment),
                    isCurved: true,
                    color: const Color(0xFF2ECC71),
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                  ),
                ],
                lineTouchData: const LineTouchData(enabled: true),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _legendItem(const Color(0xFF3B3BF9), 'Income', _totalIncome),
              _legendItem(const Color(0xFFFF6B6B), 'Expense', _totalExpense),
              _legendItem(const Color(0xFF2ECC71), 'Investment', _totalInvestment),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label, double amount) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ${formatINR(amount, decimals: 0)}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
