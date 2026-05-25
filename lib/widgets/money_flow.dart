import 'package:flutter/material.dart';
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

  const MoneyFlow({
    super.key,
    this.income = 5300,
    this.expense = 3900,
    this.investment = 1200,
  });

  List<_FlowItem> get _data => [
        _FlowItem(
          category: 'Expense',
          amount: expense,
          color: const Color(0xFFE53935),
          icon: Icons.arrow_upward,
          iconBg: const Color(0xFFFEECEC),
        ),
        _FlowItem(
          category: 'Income',
          amount: income,
          color: const Color(0xFF2ECC71),
          icon: Icons.arrow_downward,
          iconBg: const Color(0xFFE8F8F0),
        ),
        _FlowItem(
          category: 'Investments',
          amount: investment,
          color: const Color(0xFF00695C),
          icon: Icons.trending_up,
          iconBg: const Color(0xFFE0F2F1),
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
            Text(
              'May 2026',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
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
              // Table rows
              ..._data.map((item) => _buildRow(item)),
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
