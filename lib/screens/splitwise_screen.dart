import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/splitwise_route_service.dart';
import '../services/splitwise_session_service.dart';
import '../utils/currency_formatter.dart';

class SplitwiseScreen extends StatefulWidget {
  const SplitwiseScreen({super.key});

  @override
  State<SplitwiseScreen> createState() => _SplitwiseScreenState();
}

class _SplitwiseScreenState extends State<SplitwiseScreen> {
  final _splitwise = SplitwiseRouteService();
  bool _loading = true;
  bool _syncing = false;
  List<Map<String, dynamic>> _friends = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SplitwiseSessionService.instance.ensureAuthenticated(context);
      final friends = await _splitwise.getFriends(
        reauthenticate: _reauthenticateSplitwise,
      );
      setState(() {
        _friends = friends;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _reauthenticateSplitwise() {
    return SplitwiseSessionService.instance
        .ensureAuthenticated(context, force: true);
  }

  Future<void> _syncSplitwise() async {
    if (_syncing) {
      return;
    }

    setState(() => _syncing = true);
    try {
      await SplitwiseSessionService.instance.ensureAuthenticated(context);
      final importedCount = await _splitwise.syncNotifications(
        reauthenticate: _reauthenticateSplitwise,
      );
      await _loadFriends();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              importedCount == 0
                  ? 'Splitwise is already up to date'
                  : 'Imported $importedCount Splitwise expense${importedCount == 1 ? '' : 's'}',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Splitwise sync failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F8),
      appBar: AppBar(
        title: const Text(
          'Splitwise',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loading || _syncing ? null : _syncSplitwise,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, size: 22),
            tooltip: 'Sync Splitwise',
          ),
          IconButton(
            onPressed: _loading || _syncing ? null : _loadFriends,
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadFriends,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadFriends,
                  child: _buildContent(),
                ),
    );
  }

  Widget _buildContent() {
    if (_friends.isEmpty) {
      return const Center(
        child: Text('No Splitwise friends found',
            style: TextStyle(color: Color(0xFF6B7280))),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: _buildSummaryTable(_friends),
    );
  }

  Widget _buildSummaryTable(List<Map<String, dynamic>> friends) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(2),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFF1E293B)),
              children: [
                _buildHeaderCell('Friend'),
                _buildHeaderCell('DB Amt'),
                _buildHeaderCell('Splitwise Amt'),
              ],
            ),
            ...friends.asMap().entries.map((entry) {
              final i = entry.key;
              final f = entry.value;
              final name = (f['name'] ?? '').toString();
              final friendId = (f['friendId'] ?? '').toString();
              final dbAmt = _toDouble(f['notionAmount']);
              final swAmt = _toDouble(f['splitwiseAmount']);
              final isEven = i.isEven;
              final rowColor = isEven ? Colors.white : const Color(0xFFF9FAFB);
              return TableRow(
                decoration: BoxDecoration(color: rowColor),
                children: [
                  _buildTappableCell(
                    child: _buildDataCell(name),
                    friendId: friendId,
                    friendName: name,
                    balance: swAmt,
                  ),
                  _buildTappableCell(
                    child: _buildAmountCell(dbAmt, negativeIsRed: true),
                    friendId: friendId,
                    friendName: name,
                    balance: swAmt,
                  ),
                  _buildTappableCell(
                    child: _buildAmountCell(swAmt, negativeIsRed: true),
                    friendId: friendId,
                    friendName: name,
                    balance: swAmt,
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildDataCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }

  Widget _buildAmountCell(double amount, {bool negativeIsRed = false}) {
    Color color = const Color(0xFF1E293B);
    if (negativeIsRed) {
      color = amount < 0
          ? const Color(0xFFEF4444)
          : amount > 0
              ? const Color(0xFF22C55E)
              : const Color(0xFF6B7280);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        formatINR(amount, decimals: 0),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildTappableCell({
    required Widget child,
    required String friendId,
    required String friendName,
    required double balance,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _FriendTransactionsPage(
              friendId: friendId,
              friendName: friendName,
              balance: balance,
              onSettled: _loadFriends,
            ),
          ),
        );
      },
      child: child,
    );
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}

// ─── Friend Transactions Page ───────────────────────────────

class _FriendTransactionsPage extends StatefulWidget {
  final String friendId;
  final String friendName;
  final double balance;
  final VoidCallback onSettled;

  const _FriendTransactionsPage({
    required this.friendId,
    required this.friendName,
    required this.balance,
    required this.onSettled,
  });

  @override
  State<_FriendTransactionsPage> createState() =>
      _FriendTransactionsPageState();
}

class _FriendTransactionsPageState extends State<_FriendTransactionsPage> {
  final _splitwise = SplitwiseRouteService();
  bool _loading = true;
  List<Map<String, dynamic>> _transactions = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SplitwiseSessionService.instance.ensureAuthenticated(context);
      final txns = await _splitwise.getFriendExpenses(
        friendId: widget.friendId,
        reauthenticate: _reauthenticateSplitwise,
      );
      setState(() {
        _transactions = txns;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _reauthenticateSplitwise() {
    return SplitwiseSessionService.instance
        .ensureAuthenticated(context, force: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F8),
      appBar: AppBar(
        title: Text(
          widget.friendName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadTransactions,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTransactions,
                  child: _buildBody(),
                ),
    );
  }

  Widget _buildBody() {
    if (_transactions.isEmpty) {
      return const Center(
        child:
            Text('No transactions', style: TextStyle(color: Color(0xFF6B7280))),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(3),
                    1: FlexColumnWidth(2),
                  },
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(color: Color(0xFF1E293B)),
                      children: [
                        _TxnHeaderCell('Description'),
                        _TxnHeaderCell('Splitwise Amt'),
                      ],
                    ),
                    ..._transactions.asMap().entries.map((entry) {
                      final i = entry.key;
                      final txn = entry.value;
                      final swAmt = _toDouble(txn['totalAmount']);
                      final isEven = i.isEven;
                      final desc = (txn['description'] ?? '').toString();
                      final date = (txn['date'] ?? '').toString();
                      String formattedDate = '';
                      try {
                        final dt = DateTime.parse(date);
                        formattedDate = DateFormat('dd MMM yy').format(dt);
                      } catch (_) {
                        formattedDate = date;
                      }

                      return TableRow(
                        decoration: BoxDecoration(
                          color:
                              isEven ? Colors.white : const Color(0xFFF9FAFB),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  desc,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF1E293B)),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  formattedDate,
                                  style: const TextStyle(
                                      fontSize: 10, color: Color(0xFF9CA3AF)),
                                ),
                              ],
                            ),
                          ),
                          _buildTxnAmountCell(swAmt),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: widget.balance == 0
                    ? null
                    : () => _showSettleUpDialog(context),
                icon: const Icon(Icons.handshake_outlined, size: 18),
                label: Text(
                    'Settle Up  ${formatINR(widget.balance.abs(), decimals: 0)}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B3BF9),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTxnAmountCell(double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(
        formatINR(amount, decimals: 0),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }

  void _showSettleUpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _SettleUpDialog(
        friendId: widget.friendId,
        friendName: widget.friendName,
        initialAmount: widget.balance.abs(),
        currentUserPays: widget.balance < 0,
        onSettled: () {
          _loadTransactions();
          widget.onSettled();
        },
      ),
    );
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}

// ─── Table Header Cell (const-friendly) ─────────────────────

class _TxnHeaderCell extends StatelessWidget {
  final String text;
  const _TxnHeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ─── Settle Up Dialog ───────────────────────────────────────

class _SettleUpDialog extends StatefulWidget {
  final String friendId;
  final String friendName;
  final double? initialAmount;
  final bool currentUserPays;
  final VoidCallback onSettled;

  const _SettleUpDialog({
    required this.friendId,
    required this.friendName,
    this.initialAmount,
    required this.currentUserPays,
    required this.onSettled,
  });

  @override
  State<_SettleUpDialog> createState() => _SettleUpDialogState();
}

class _SettleUpDialogState extends State<_SettleUpDialog> {
  final _splitwise = SplitwiseRouteService();
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialAmount != null && widget.initialAmount! > 0) {
      _amountController.text = widget.initialAmount!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _settle() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final amount = double.parse(_amountController.text.trim());
      await _splitwise.createPayment(
        friendId: widget.friendId,
        amount: amount,
        currentUserPays: widget.currentUserPays,
        reauthenticate: _reauthenticateSplitwise,
      );
      widget.onSettled();
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settled successfully')),
        );
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _reauthenticateSplitwise() {
    return SplitwiseSessionService.instance
        .ensureAuthenticated(context, force: true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Settle Up with ${widget.friendName}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Enter amount';
                }
                final parsed = double.tryParse(v.trim());
                if (parsed == null || parsed <= 0) {
                  return 'Enter a valid amount';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _settle,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B3BF9),
            foregroundColor: Colors.white,
          ),
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Settle'),
        ),
      ],
    );
  }
}
