import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class TransactionDetailScreen extends StatefulWidget {
  final String transactionId;
  const TransactionDetailScreen({super.key, required this.transactionId});

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _error;
  TransactionModel? _transaction;

  @override
  void initState() {
    super.initState();
    _fetchTransaction();
  }

  Future<void> _fetchTransaction() async {
    try {
      final data = await _api.getTransactionById(widget.transactionId);
      final txJson = data['transaction'] ?? data;
      setState(() {
        _transaction = TransactionModel.fromJson(
          txJson is Map<String, dynamic> ? txJson : data,
        );
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load transaction';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Details'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: colorScheme.error),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: TextStyle(color: colorScheme.error)),
                    ],
                  ),
                )
              : _buildDetails(context),
    );
  }

  Widget _buildDetails(BuildContext context) {
    final tx = _transaction!;
    final colorScheme = Theme.of(context).colorScheme;

    // Parse date
    String formattedDate = tx.date;
    try {
      final date = DateTime.parse(tx.date);
      formattedDate = DateFormat('EEEE, dd MMM yyyy').format(date);
    } catch (_) {}

    // Format time
    String formattedTime = tx.time ?? '--';

    // Type color
    Color typeColor;
    IconData typeIcon;
    switch (tx.type.toLowerCase()) {
      case 'income':
        typeColor = Colors.green;
        typeIcon = Icons.arrow_downward_rounded;
        break;
      case 'expense':
        typeColor = Colors.red;
        typeIcon = Icons.arrow_upward_rounded;
        break;
      case 'transfer':
        typeColor = Colors.blue;
        typeIcon = Icons.swap_horiz_rounded;
        break;
      case 'investment':
        typeColor = Colors.purple;
        typeIcon = Icons.trending_up_rounded;
        break;
      default:
        typeColor = Colors.grey;
        typeIcon = Icons.receipt_long;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Amount hero
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 28),
                ),
                const SizedBox(height: 12),
                Text(
                  '₹${tx.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: typeColor,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tx.type.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: typeColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Detail rows
          _buildCard(context, [
            _buildRow(Icons.calendar_today, 'Date', formattedDate, colorScheme),
            _buildRow(Icons.access_time, 'Time', formattedTime, colorScheme),
            if (tx.accountName != null)
              _buildRow(Icons.account_balance, 'Account', tx.accountName!,
                  colorScheme),
            if (tx.description.isNotEmpty)
              _buildRow(Icons.description_outlined, 'Description',
                  tx.description, colorScheme),
          ]),
          const SizedBox(height: 12),

          if (tx.category != null || tx.subCategory != null)
            _buildCard(context, [
              if (tx.category != null)
                _buildRow(Icons.category_outlined, 'Category', tx.category!,
                    colorScheme),
              if (tx.subCategory != null)
                _buildRow(Icons.subdirectory_arrow_right, 'Sub Category',
                    tx.subCategory!, colorScheme),
            ]),

          if (tx.investmentAccountName != null) ...[
            const SizedBox(height: 12),
            _buildCard(context, [
              _buildRow(Icons.trending_up, 'Investment Account',
                  tx.investmentAccountName!, colorScheme),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildRow(
      IconData icon, String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
