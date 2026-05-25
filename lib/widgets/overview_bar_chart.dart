import 'package:flutter/material.dart';
import '../utils/currency_formatter.dart';

class OverviewBarChart extends StatelessWidget {
  final double income;
  final double expense;
  final double investment;

  const OverviewBarChart({
    super.key,
    this.income = 2600.0,
    this.expense = 1650.0,
    this.investment = 700.0,
  });

  double get _total => income + expense + investment;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Overview',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade900,
                ),
              ),
              Row(
                children: [
                  _legendItem(const Color(0xFF2ECC71), 'Income'),
                  const SizedBox(width: 12),
                  _legendItem(const Color(0xFFE53935), 'Expense'),
                  const SizedBox(width: 12),
                  _legendItem(const Color(0xFF00695C), 'Investment'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  Expanded(
                    flex: _total > 0 ? (income * 100 ~/ _total) : 1,
                    child: Container(color: const Color(0xFF2ECC71)),
                  ),
                  Expanded(
                    flex: _total > 0 ? (expense * 100 ~/ _total) : 1,
                    child: Container(color: const Color(0xFFE53935)),
                  ),
                  Expanded(
                    flex: _total > 0 ? (investment * 100 ~/ _total) : 1,
                    child: Container(color: const Color(0xFF00695C)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total: ${formatINR(_total, decimals: 0)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              Text(
                '${formatINR(income, decimals: 0)} · ${formatINR(expense, decimals: 0)} · ${formatINR(investment, decimals: 0)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}
