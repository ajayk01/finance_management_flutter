import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/app_data_cache.dart';
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
              final dbFriendId = (f['dbFriendId'] ?? '').toString();
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
                    dbFriendId: dbFriendId,
                    friendName: name,
                    dbAmount: dbAmt,
                    balance: swAmt,
                  ),
                  _buildTappableCell(
                    child: _buildAmountCell(dbAmt, negativeIsRed: true),
                    friendId: friendId,
                    dbFriendId: dbFriendId,
                    friendName: name,
                    dbAmount: dbAmt,
                    balance: swAmt,
                  ),
                  _buildTappableCell(
                    child: _buildAmountCell(swAmt, negativeIsRed: true),
                    friendId: friendId,
                    dbFriendId: dbFriendId,
                    friendName: name,
                    dbAmount: dbAmt,
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
    required String dbFriendId,
    required String friendName,
    required double dbAmount,
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
              dbFriendId: dbFriendId,
              friendName: friendName,
              balance: balance,
              dbAmount: dbAmount,
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
  final String dbFriendId;
  final String friendName;
  final double balance;
  final double dbAmount;
  final VoidCallback onSettled;

  const _FriendTransactionsPage({
    required this.friendId,
    required this.dbFriendId,
    required this.friendName,
    required this.balance,
    required this.dbAmount,
    required this.onSettled,
  });

  @override
  State<_FriendTransactionsPage> createState() =>
      _FriendTransactionsPageState();
}

class _FriendTransactionsPageState extends State<_FriendTransactionsPage> {
  final _splitwise = SplitwiseRouteService();
  final _cache = AppDataCache();
  bool _loading = true;
  bool _submitting = false;
  List<Map<String, dynamic>> _transactions = [];
  List<BankAccount> _bankAccounts = [];
  List<Category> _categories = [];
  final Set<String> _selectedExpenseIds = {};
  final Map<String, String?> _categoryIdsByExpense = {};
  final Map<String, String?> _subCategoryIdsByExpense = {};
  final Map<String, String> _descriptionsByExpense = {};
  String? _selectedAccountId;
  DateTime _settlementDate = DateTime.now();
  TimeOfDay _settlementTime = TimeOfDay.now();
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    _loadSettlementFormData();
  }

  Future<void> _loadSettlementFormData() async {
    await Future.wait([_cache.ensureAccounts(), _cache.ensureCategories()]);
    if (!mounted) {
      return;
    }
    setState(() {
      _bankAccounts = _cache.activeBankAccounts;
      _categories = _cache.categories;
      _selectedAccountId =
          _bankAccounts.isEmpty ? null : _bankAccounts.first.id;
    });
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SplitwiseSessionService.instance.ensureAuthenticated(context);
      final txns = await _splitwise.getUnsettledFriendExpenses(
        dbFriendId: widget.dbFriendId,
        reauthenticate: _reauthenticateSplitwise,
      );
      setState(() {
        _transactions = txns;
        _selectedExpenseIds
          ..clear()
          ..addAll(txns.map((transaction) => transaction['id'].toString()));
        _descriptionsByExpense.clear();
        _descriptionsByExpense.addEntries(
          txns.where((transaction) => transaction['isImported'] == true).map(
                (transaction) => MapEntry(
                  transaction['id'].toString(),
                  transaction['description']?.toString() ?? '',
                ),
              ),
        );
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
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSettlementDetailsSection(),
                const SizedBox(height: 20),
                _buildImportedExpensesSection(),
                const SizedBox(height: 20),
                _buildSplitTransactionsSection(),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedTotal <= 0 || _submitting ? null : _settle,
                icon: const Icon(Icons.handshake_outlined, size: 18),
                label: Text(
                    'Settle Up  ${formatINR(_selectedTotal, decimals: 0)}'),
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

  List<Map<String, dynamic>> get _importedExpenses => _transactions
      .where((transaction) => transaction['isImported'] == true)
      .toList();

  List<Map<String, dynamic>> get _splitTransactions => _transactions
      .where((transaction) => transaction['isImported'] != true)
      .toList();

  List<Category> get _expenseCategories => _categories
      .where((category) => category.type.toLowerCase() == 'expense')
      .toList();

  double get _selectedTotal => _transactions
      .where((transaction) => _selectedExpenseIds.contains(transaction['id']))
      .fold<double>(
          0,
          (total, transaction) =>
              total + _toDouble(transaction['totalAmount']));

  Widget _buildSettlementDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Settlement Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _selectedAccountId,
          decoration: const InputDecoration(
            labelText: 'Bank Account',
            border: OutlineInputBorder(),
          ),
          items: _bankAccounts
              .map((account) => DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _selectedAccountId = value),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pickSettlementDate,
                child: Text(DateFormat('dd MMM yyyy').format(_settlementDate)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _pickSettlementTime,
                child: Text(_settlementTime.format(context)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildImportedExpensesSection() {
    return _buildTransactionSection(
      title: 'Splitwise Expenses',
      transactions: _importedExpenses,
      includeCategories: true,
      emptyText: 'No imported Splitwise expenses',
    );
  }

  Widget _buildSplitTransactionsSection() {
    return _buildTransactionSection(
      title: 'Split Transactions',
      transactions: _splitTransactions,
      includeCategories: false,
      emptyText: 'No local split transactions',
    );
  }

  Widget _buildTransactionSection({
    required String title,
    required List<Map<String, dynamic>> transactions,
    required bool includeCategories,
    required String emptyText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (transactions.isEmpty)
          Text(emptyText, style: const TextStyle(color: Color(0xFF6B7280)))
        else
          ...transactions.map((transaction) => _buildSelectableExpense(
                transaction,
                includeCategories: includeCategories,
              )),
      ],
    );
  }

  Widget _buildSelectableExpense(
    Map<String, dynamic> expense, {
    required bool includeCategories,
  }) {
    final expenseId = expense['id'].toString();
    final amount = _toDouble(expense['totalAmount']);
    final date = DateTime.tryParse(expense['date']?.toString() ?? '');
    final categoryId = _categoryIdsByExpense[expenseId];
    final category =
        _categories.where((item) => item.id == categoryId).firstOrNull;
    final subCategories = category?.subCategories ?? const <SubCategory>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: _selectedExpenseIds.contains(expenseId),
            contentPadding: EdgeInsets.zero,
            title: Text(
                (expense['description'] ?? 'Splitwise expense').toString()),
            subtitle: Text(
              '${formatINR(amount, decimals: 0)}${date == null ? '' : ' - ${DateFormat('dd MMM yyyy').format(date)}'}',
            ),
            onChanged: (selected) => setState(() {
              if (selected == true) {
                _selectedExpenseIds.add(expenseId);
              } else {
                _selectedExpenseIds.remove(expenseId);
              }
            }),
          ),
          if (includeCategories && _selectedExpenseIds.contains(expenseId)) ...[
            TextFormField(
              key: ValueKey('splitwise-description-$expenseId'),
              initialValue: _descriptionsByExpense[expenseId] ??
                  expense['description']?.toString() ??
                  '',
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _descriptionsByExpense[expenseId] = value,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: categoryId,
              decoration: const InputDecoration(
                  labelText: 'Category', border: OutlineInputBorder()),
              items: _expenseCategories
                  .map((item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)))
                  .toList(),
              onChanged: (value) => setState(() {
                _categoryIdsByExpense[expenseId] = value;
                _subCategoryIdsByExpense.remove(expenseId);
              }),
            ),
            if (subCategories.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _subCategoryIdsByExpense[expenseId],
                decoration: const InputDecoration(
                    labelText: 'Subcategory', border: OutlineInputBorder()),
                items: subCategories
                    .map((item) => DropdownMenuItem(
                        value: item.id, child: Text(item.name)))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _subCategoryIdsByExpense[expenseId] = value),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _pickSettlementDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _settlementDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _settlementDate = picked);
    }
  }

  Future<void> _pickSettlementTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _settlementTime,
    );
    if (picked != null && mounted) {
      setState(() => _settlementTime = picked);
    }
  }

  Future<void> _settle() async {
    if (_selectedAccountId == null) {
      _showError('Select a bank account');
      return;
    }
    final selectedImported = _importedExpenses
        .where((expense) => _selectedExpenseIds.contains(expense['id']))
        .toList();
    for (final expense in selectedImported) {
      if (_categoryIdsByExpense[expense['id'].toString()] == null) {
        _showError('Select a category for every selected Splitwise expense');
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final settlementDateTime = DateTime(
        _settlementDate.year,
        _settlementDate.month,
        _settlementDate.day,
        _settlementTime.hour,
        _settlementTime.minute,
      );
      await _splitwise.settleLocalExpenses(
        dbFriendId: widget.dbFriendId,
        bankAccountId: _selectedAccountId!,
        clientAmount: _selectedTotal,
        selectedSplitwiseTransactionIds: _selectedExpenseIds.toList(),
        updatedDescriptions: {
          for (final expense in selectedImported)
            expense['id'].toString():
                _descriptionsByExpense[expense['id'].toString()] ?? '',
        },
        importedCategories: {
          for (final expense in selectedImported)
            expense['id'].toString(): {
              'categoryId': _categoryIdsByExpense[expense['id'].toString()],
              'subCategoryId':
                  _subCategoryIdsByExpense[expense['id'].toString()],
            },
        },
        importedExpenseDetails: {
          for (final expense in selectedImported)
            expense['id'].toString(): expense,
        },
        date: settlementDateTime,
      );
      await _loadTransactions();
      widget.onSettled();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settled successfully')),
        );
      }
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message), backgroundColor: const Color(0xFFEF4444)),
    );
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
