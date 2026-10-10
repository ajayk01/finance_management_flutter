import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/currency_formatter.dart';

class _FlowItem {
  final String category;
  final double amount;
  final Color color;
  final IconData icon;
  final Color iconBg;

  const _FlowItem({
    required this.category,
    required this.amount,
    required this.color,
    required this.icon,
    required this.iconBg,
  });
}

class MoneyFlow extends StatelessWidget {
  final double income;
  final double expense;
  final double investment;
  final DateTime selectedPeriod;
  final ValueChanged<DateTime> onPeriodChanged;
  final bool loading;
  final String? errorMessage;

  const MoneyFlow({
    super.key,
    required this.income,
    required this.expense,
    required this.investment,
    required this.selectedPeriod,
    required this.onPeriodChanged,
    this.loading = false,
    this.errorMessage,
  });

  List<_FlowItem> get _data => [
        _FlowItem(
          category: 'Total income',
          amount: income,
          color: const Color(0xFF2ECC71),
          icon: Icons.arrow_downward,
          iconBg: const Color(0xFFE8F8F0),
        ),
        _FlowItem(
          category: 'Total expense',
          amount: expense,
          color: const Color(0xFFE53935),
          icon: Icons.arrow_upward,
          iconBg: const Color(0xFFFEECEC),
        ),
        _FlowItem(
          category: 'Total investment',
          amount: investment,
          color: const Color(0xFF00695C),
          icon: Icons.trending_up,
          iconBg: const Color(0xFFE0F2F1),
        ),
        _FlowItem(
          category: 'Net change',
          amount: income - expense - investment,
          color: const Color(0xFF1565C0),
          icon: Icons.account_balance_wallet_outlined,
          iconBg: const Color(0xFFE3F2FD),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Money Flow',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade900,
              ),
            ),
            _PeriodSelector(
              selectedPeriod: selectedPeriod,
              onChanged: loading ? null : onPeriodChanged,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Table header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Category',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Amount',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                ..._data.map((item) => _buildRow(item)),
                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFC62828),
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(_FlowItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: item.iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, size: 16, color: item.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              item.category,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatINR(item.amount, decimals: 0),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: item.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.selectedPeriod,
    required this.onChanged,
  });

  final DateTime selectedPeriod;
  final ValueChanged<DateTime>? onChanged;

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = List.generate(currentYear - 1999, (index) => 2000 + index);
    final textStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Colors.grey.shade600,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: selectedPeriod.month,
            isDense: true,
            style: textStyle,
            items: List.generate(
              12,
              (index) => DropdownMenuItem(
                value: index + 1,
                child:
                    Text(DateFormat('MMM').format(DateTime(2000, index + 1))),
              ),
            ),
            onChanged: (month) {
              if (month != null && onChanged != null) {
                onChanged!(DateTime(selectedPeriod.year, month));
              }
            },
          ),
        ),
        const SizedBox(width: 4),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: selectedPeriod.year,
            isDense: true,
            style: textStyle,
            items: years
                .map((year) => DropdownMenuItem(
                      value: year,
                      child: Text(year.toString()),
                    ))
                .toList(),
            onChanged: (year) {
              if (year != null && onChanged != null) {
                onChanged!(DateTime(year, selectedPeriod.month));
              }
            },
          ),
        ),
      ],
    );
  }
}
