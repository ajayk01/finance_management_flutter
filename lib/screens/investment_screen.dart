import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/app_data_cache.dart';
import '../services/direct_sql_service.dart';
import '../utils/currency_formatter.dart';

class _InvestmentWithdrawal {
  const _InvestmentWithdrawal({
    required this.amount,
    required this.bankAccountId,
  });

  final double amount;
  final String bankAccountId;
}

class _CurrentValueEditorDialog extends StatefulWidget {
  const _CurrentValueEditorDialog({
    required this.accountName,
    required this.currentValue,
  });

  final String accountName;
  final double currentValue;

  @override
  State<_CurrentValueEditorDialog> createState() =>
      _CurrentValueEditorDialogState();
}

class _CurrentValueEditorDialogState extends State<_CurrentValueEditorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentValue.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Update ${widget.accountName}'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Current value',
            prefixText: 'Rs. ',
          ),
          onSubmitted: (input) => Navigator.pop(
            context,
            double.tryParse(input.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              double.tryParse(_controller.text.trim()),
            ),
            child: const Text('Save'),
          ),
        ],
      );
}

class _XirrEditorDialog extends StatefulWidget {
  const _XirrEditorDialog({required this.accountName, required this.xirr});

  final String accountName;
  final double xirr;

  @override
  State<_XirrEditorDialog> createState() => _XirrEditorDialogState();
}

class _XirrEditorDialogState extends State<_XirrEditorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.xirr.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Update ${widget.accountName} XIRR'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: const InputDecoration(
            labelText: 'XIRR',
            suffixText: '%',
          ),
          onSubmitted: (input) => Navigator.pop(
            context,
            double.tryParse(input.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              double.tryParse(_controller.text.trim()),
            ),
            child: const Text('Save'),
          ),
        ],
      );
}

class InvestmentScreen extends StatefulWidget {
  const InvestmentScreen({super.key});

  @override
  State<InvestmentScreen> createState() => _InvestmentScreenState();
}

class _InvestmentScreenState extends State<InvestmentScreen> {
  bool _loading = true;
  List<InvestmentAccount> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final cache = AppDataCache();

    try {
      await cache.ensureAccounts();
      final cachedAccounts = cache.activeInvestmentAccounts;
      if (mounted && cachedAccounts.isNotEmpty) {
        setState(() {
          _accounts = cachedAccounts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _totalInvested => _accounts.fold<double>(
        0,
        (sum, account) => sum + account.totalInvested - account.totalWithdraw,
      );

  double get _totalCurrentValue =>
      _accounts.fold<double>(0, (s, a) => s + a.currentValue);

  double get _totalGain => _totalCurrentValue - _totalInvested;

  Future<void> _showCurrentValueEditor(InvestmentAccount account) async {
    final value = await showDialog<double>(
      context: context,
      builder: (_) => _CurrentValueEditorDialog(
        accountName: account.name,
        currentValue: account.currentValue,
      ),
    );

    if (value == null || value < 0 || !mounted) return;

    try {
      await DirectSqlService.updateInvestmentCurrentValue(
        investmentAccountId: account.id,
        currentValue: value,
      );
      final cache = AppDataCache();
      await cache.refreshAccounts();
      if (mounted) {
        setState(() => _accounts = cache.activeInvestmentAccounts);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update current value')),
        );
      }
    }
  }

  Future<void> _showWithdrawalDialog(InvestmentAccount account) async {
    final bankAccounts = AppDataCache().activeBankAccounts;
    if (bankAccounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a bank account before withdrawing')),
      );
      return;
    }

    final controller = TextEditingController();
    String selectedBankAccountId = bankAccounts.first.id;
    final withdrawal = await showDialog<_InvestmentWithdrawal>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Withdraw from ${account.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: 'Rs. ',
                  helperText:
                      'Available: ${formatINR(account.currentValue, decimals: 0)}',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedBankAccountId,
                decoration: const InputDecoration(labelText: 'Deposit to'),
                items: bankAccounts
                    .map(
                      (bankAccount) => DropdownMenuItem(
                        value: bankAccount.id,
                        child: Text(bankAccount.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedBankAccountId = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(controller.text.trim());
                if (amount == null ||
                    amount <= 0 ||
                    amount > account.currentValue) {
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _InvestmentWithdrawal(
                    amount: amount,
                    bankAccountId: selectedBankAccountId,
                  ),
                );
              },
              child: const Text('Withdraw'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    if (withdrawal == null || !mounted) return;

    try {
      await DirectSqlService.withdrawFromInvestment(
        amount: withdrawal.amount,
        investmentAccountId: account.id,
        toBankAccountId: withdrawal.bankAccountId,
      );
      final cache = AppDataCache();
      await cache.refreshAccounts();
      if (mounted) {
        setState(() => _accounts = cache.activeInvestmentAccounts);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not withdraw: $error')),
        );
      }
    }
  }

  Future<void> _calculateXirr(InvestmentAccount account) async {
    try {
      final xirr = await DirectSqlService.calculateInvestmentXirr(account.id);
      final cache = AppDataCache();
      await cache.refreshAccounts();
      if (mounted) {
        setState(() => _accounts = cache.activeInvestmentAccounts);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('XIRR updated to ${xirr.toStringAsFixed(1)}%')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not calculate XIRR: $error')),
        );
      }
    }
  }

  Future<void> _showXirrEditor(InvestmentAccount account) async {
    final xirr = await showDialog<double>(
      context: context,
      builder: (_) => _XirrEditorDialog(
        accountName: account.name,
        xirr: account.xirr,
      ),
    );

    if (xirr == null || !xirr.isFinite || !mounted) return;

    try {
      await DirectSqlService.updateInvestmentXirr(
        investmentAccountId: account.id,
        xirr: xirr,
      );
      final cache = AppDataCache();
      await cache.refreshAccounts();
      if (mounted) {
        setState(() => _accounts = cache.activeInvestmentAccounts);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update XIRR')),
        );
      }
    }
  }

  Future<void> _showInvestmentActions(InvestmentAccount account) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Update current value'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showCurrentValueEditor(account);
              },
            ),
            ListTile(
              leading: const Icon(Icons.south_west_outlined),
              title: const Text('Withdraw'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showWithdrawalDialog(account);
              },
            ),
            ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Calculate XIRR'),
              onTap: () {
                Navigator.pop(sheetContext);
                _calculateXirr(account);
              },
            ),
            ListTile(
              leading: const Icon(Icons.percent_outlined),
              title: const Text('Update XIRR manually'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showXirrEditor(account);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Center(
                child: Text(
                  'Investments',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Summary card
              _buildSummaryCard(),
              const SizedBox(height: 24),

              // Table
              if (_accounts.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Text(
                      'No investment accounts found',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                )
              else
                _buildInvestmentTable(),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final gainColor =
        _totalGain >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Invested',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 4),
                Text(
                  formatINR(_totalInvested),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.grey.shade200),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Value',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatINR(_totalCurrentValue),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: gainColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvestmentTable() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            _buildTableHeader(),
            Divider(height: 1, color: Colors.grey.shade100),
            ..._accounts.asMap().entries.map((entry) {
              final index = entry.key;
              final account = entry.value;
              return Column(
                children: [
                  _buildTableRow(account),
                  if (index < _accounts.length - 1)
                    Divider(height: 1, color: Colors.grey.shade100),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    const headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Color(0xFF64748B),
    );
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: const Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'Investment',
              overflow: TextOverflow.ellipsis,
              style: headerStyle,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Net invested',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: headerStyle,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Current',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: headerStyle,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('XIRR', textAlign: TextAlign.right, style: headerStyle),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(InvestmentAccount account) {
    final xirrColor =
        account.xirr >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final netInvestment = account.totalInvested - account.totalWithdraw;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showInvestmentActions(account),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(
                account.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                formatINR(netInvestment, decimals: 0),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                formatINR(account.currentValue, decimals: 0),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: account.currentValue >= netInvestment
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${account.xirr >= 0 ? '+' : ''}${account.xirr.toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: xirrColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
