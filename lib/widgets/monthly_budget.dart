import 'package:flutter/material.dart';
import '../utils/currency_formatter.dart';

class MonthlyBudget extends StatelessWidget {
  final double spent;
  final double total;

  const MonthlyBudget({
    super.key,
    required this.spent,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = (spent / total * 100).round();
    final progress = spent / total;

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
            'Monthly Budget',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: const Color(0xFFE8E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF3B3BF9),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  children: [
                    const TextSpan(text: 'Spent '),
                    TextSpan(
                      text: formatINR(spent, decimals: 0),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    TextSpan(
                      text: ' / ${formatINR(total)}',
                    ),
                  ],
                ),
              ),
              Text(
                '$percentage%',
                style: const TextStyle(
                  color: Color(0xFF3B3BF9),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
