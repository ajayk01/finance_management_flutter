import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/currency_formatter.dart';

class CreditCardCapCarousel extends StatelessWidget {
  const CreditCardCapCarousel({super.key, required this.caps});

  final List<CreditCardCap> caps;

  @override
  Widget build(BuildContext context) {
    if (caps.length == 1) {
      return _CreditCardCapOverview(cap: caps.first);
    }

    return SizedBox(
      height: 220,
      child: PageView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: caps.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: _CreditCardCapOverview(cap: caps[index]),
        ),
      ),
    );
  }
}

class _CreditCardCapOverview extends StatelessWidget {
  const _CreditCardCapOverview({required this.cap});

  final CreditCardCap cap;

  @override
  Widget build(BuildContext context) {
    final usedAmount = cap.capCurrentAmount;
    final totalSpend = cap.capCurrentSpend;
    final totalAmount = cap.capTotalAmount;
    final remainingAmount = cap.remainingAmount.clamp(0, double.infinity);
    final utilization =
        totalAmount <= 0 ? 0.0 : (usedAmount / totalAmount).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.workspace_premium_outlined,
                    size: 20, color: Color(0xFF0284C7)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(cap.capName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
                Text('${formatINR(totalSpend, decimals: 0)} spend',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2563EB))),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: utilization,
              minHeight: 10,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF2563EB)),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Metric(
                      label: 'Total amount',
                      amount: totalAmount,
                      color: const Color(0xFF1E293B),
                      width: itemWidth),
                  _Metric(
                      label: 'Used',
                      amount: usedAmount,
                      color: const Color(0xFF2563EB),
                      width: itemWidth),
                  _Metric(
                      label: 'Remaining',
                      amount: remainingAmount.toDouble(),
                      color: const Color(0xFF16A34A),
                      width: itemWidth),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.amount,
    required this.color,
    required this.width,
  });

  final String label;
  final double amount;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 3),
          Text(formatINR(amount, decimals: 0),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
