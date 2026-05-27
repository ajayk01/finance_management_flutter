import 'package:flutter/material.dart';
import 'add_account_screen.dart';
import 'add_category_screen.dart';
import 'add_credit_cap_screen.dart';
import 'add_subcategory_screen.dart';
import 'add_transfer_screen.dart';
import 'analytics_screen.dart';
import 'pay_cc_bill_screen.dart';
import 'splitwise_screen.dart';
import 'unaudited_expense_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(context),
            const SizedBox(height: 24),
            _buildSectionHeader('Reports'),
            const SizedBox(height: 8),
            _buildOptionTile(
              icon: Icons.insert_chart_outlined_rounded,
              title: 'Analytics',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
                );
              },
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('Tracking'),
            const SizedBox(height: 8),
            _buildOptionTile(
              icon: Icons.group_outlined,
              title: 'Splitwise',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SplitwiseScreen()),
                );
              },
            ),
            _buildOptionTile(
              icon: Icons.pending_actions_outlined,
              title: 'Unaudited Expense',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const UnauditedExpenseScreen()),
                );
              },
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('Accounts & Transfers'),
            const SizedBox(height: 8),
            _buildOptionTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Add Account',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddAccountScreen()),
                );
              },
            ),
            _buildOptionTile(
              icon: Icons.swap_horiz_rounded,
              title: 'Add Transfer',
              onTap: () => AddTransferSheet.show(context),
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('Categories'),
            const SizedBox(height: 8),
            _buildOptionTile(
              icon: Icons.category_outlined,
              title: 'Add Category',
              onTap: () => AddCategorySheet.show(context),
            ),
            _buildOptionTile(
              icon: Icons.subdirectory_arrow_right_rounded,
              title: 'Add Sub Category',
              onTap: () => AddSubCategorySheet.show(context),
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('Credit & Bills'),
            const SizedBox(height: 8),
            _buildOptionTile(
              icon: Icons.credit_score_outlined,
              title: 'Add Credit Cap',
              onTap: () => AddCreditCapSheet.show(context),
            ),
            _buildOptionTile(
              icon: Icons.payment_rounded,
              title: 'Pay CC Bill',
              onTap: () => PayCcBillSheet.show(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return const Center(
      child: Text(
        'More Options',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Color(0xFF6B7280),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF1E293B), size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 22),
        onTap: onTap,
      ),
    );
  }
}
