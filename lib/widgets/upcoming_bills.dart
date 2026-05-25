import 'package:flutter/material.dart';
import '../utils/currency_formatter.dart';

class BillItem {
  final String name;
  final String dueDate;
  final String daysLeft;
  final double amount;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;

  const BillItem({
    required this.name,
    required this.dueDate,
    required this.daysLeft,
    required this.amount,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
  });
}

class UpcomingBills extends StatelessWidget {
  const UpcomingBills({super.key});

  static const List<BillItem> _bills = [
    BillItem(
      name: 'Internet - Indihome',
      dueDate: 'Due 24 Jan',
      daysLeft: '3 days left',
      amount: 120.00,
      icon: Icons.wifi,
      iconColor: Color(0xFF3B82F6),
      iconBgColor: Color(0xFFEFF6FF),
    ),
    BillItem(
      name: 'Electicity - PLN',
      dueDate: 'Due 29 Jan',
      daysLeft: '5 days left',
      amount: 120.00,
      icon: Icons.bolt,
      iconColor: Color(0xFFF59E0B),
      iconBgColor: Color(0xFFFFFBEB),
    ),
    BillItem(
      name: 'Mobile - Telkom',
      dueDate: 'Due 01 Feb',
      daysLeft: '10 days left',
      amount: 140.00,
      icon: Icons.phone_android,
      iconColor: Color(0xFFEF4444),
      iconBgColor: Color(0xFFFEF2F2),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Upcoming Bills',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade900,
              ),
            ),
            TextButton(
              onPressed: () {},
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View All',
                    style: TextStyle(
                      color: Color(0xFF3B3BF9),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right,
                    color: Color(0xFF3B3BF9),
                    size: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _bills.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 72,
              color: Colors.grey.shade100,
            ),
            itemBuilder: (context, index) => _buildBillTile(_bills[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildBillTile(BillItem bill) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: bill.iconBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(bill.icon, color: bill.iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bill.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 13,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      bill.dueDate,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '•',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      bill.daysLeft,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            formatINR(bill.amount),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade900,
            ),
          ),
        ],
      ),
    );
  }
}
