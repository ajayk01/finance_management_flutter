import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_data_cache.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  int _selectedType = 0; // 0=Income, 1=Expense, 2=Transfer, 3=Investment
  String _amount = '0';
  String _selectedCategory = '';
  String _selectedSubCategory = '';
  String _selectedAccount = '';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  final TextEditingController _descController = TextEditingController();
  final FocusNode _descFocusNode = FocusNode();
  bool _showNumpad = true;
  bool _showSplitwise = false;
  String _selectedGroup = '';
  final List<String> _selectedPeople = [];
  String _splitType = 'Equal';
  final _api = ApiService();

  bool _loading = true;
  bool _submitting = false;
  List<Category> _apiCategories = [];
  List<BankAccount> _bankAccounts = [];
  List<CreditCardAccount> _creditCards = [];
  List<InvestmentAccount> _investmentAccounts = [];
  List<CreditCardCap> _creditCardCaps = [];
  List<SplitwiseGroup> _splitwiseGroups = [];

  static const _typeLabels = ['Income', 'Expense', 'Transfer', 'Investment'];

  @override
  void initState() {
    super.initState();
    _loadCachedFormData();
    _loadFormData();
  }

  void _applyFormData({
    required List<Category> cats,
    required List<BankAccount> banks,
    required List<CreditCardAccount> cards,
    required List<InvestmentAccount> invs,
    required List<CreditCardCap> caps,
    required List<SplitwiseGroup> groups,
  }) {
    if (!mounted) return;
    setState(() {
      _apiCategories = cats;
      _bankAccounts = banks;
      _creditCards = cards;
      _investmentAccounts = invs;
      _creditCardCaps = caps;
      _splitwiseGroups = groups;
      if (cats.isNotEmpty && _selectedCategory.isEmpty) {
        _selectedCategory = cats.first.name;
        if (cats.first.subCategories.isNotEmpty) {
          _selectedSubCategory = cats.first.subCategories.first.name;
        }
      }
      if (banks.isNotEmpty && _selectedAccount.isEmpty) {
        _selectedAccount = banks.first.name;
      }
      if (groups.isNotEmpty && _selectedGroup.isEmpty) {
        _selectedGroup = groups.first.name;
      }
      _loading = false;
    });
  }

  Future<void> _loadCachedFormData() async {
    final cache = AppDataCache();
    await cache.loadFromLocal();

    _applyFormData(
      cats: cache.categories,
      banks: cache.bankAccounts,
      cards: cache.creditCardAccounts,
      invs: cache.investmentAccounts,
      caps: cache.creditCardCaps,
      groups: cache.splitwiseGroups,
    );
  }

  Future<void> _loadFormData() async {
    try {
      final cache = AppDataCache();
      await cache.refreshAll();

      _applyFormData(
        cats: cache.categories,
        banks: cache.bankAccounts,
        cards: cache.creditCardAccounts,
        invs: cache.investmentAccounts,
        caps: cache.creditCardCaps,
        groups: cache.splitwiseGroups,
      );
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _categories {
    if (_apiCategories.isNotEmpty) {
      String typeFilter;
      switch (_selectedType) {
        case 0:
          typeFilter = 'income';
          break;
        case 3:
          typeFilter = 'investment';
          break;
        default:
          typeFilter = 'expense';
      }
      final filtered = _apiCategories
          .where((c) => c.type.toLowerCase() == typeFilter)
          .map((c) => c.name)
          .toList();
      if (filtered.isNotEmpty) return filtered;
      return _apiCategories.map((c) => c.name).toList();
    }
    return ['Shopping', 'Food & Drink', 'Subscription', 'Education', 'Transportation', 'Entertainment', 'Health', 'Others'];
  }

  Map<String, List<String>> get _subCategories {
    if (_apiCategories.isNotEmpty) {
      return {
        for (final c in _apiCategories)
          c.name: c.subCategories.isNotEmpty
              ? c.subCategories.map((s) => s.name).toList()
              : ['Others'],
      };
    }
    return {
      'Shopping': ['Clothing', 'Electronics', 'Groceries', 'Others'],
      'Food & Drink': ['Restaurant', 'Coffee', 'Delivery', 'Others'],
      'Subscription': ['Monthly', 'Yearly', 'Trial', 'Others'],
      'Education': ['Course', 'Books', 'Tuition', 'Others'],
      'Transportation': ['Fuel', 'Parking', 'Public Transit', 'Others'],
      'Entertainment': ['Movies', 'Games', 'Music', 'Others'],
      'Health': ['Medicine', 'Gym', 'Insurance', 'Others'],
      'Others': ['Miscellaneous'],
    };
  }

  List<String> get _accounts {
    final items = <String>[];
    for (final b in _bankAccounts) { items.add(b.name); }
    for (final c in _creditCards) { items.add(c.name); }
    if (items.isEmpty) return ['Chase Bank', 'Bank of America', 'Visa ••4521', 'Mastercard ••8832'];
    return items;
  }



  List<String> get _splitGroups => _splitwiseGroups.isNotEmpty
      ? _splitwiseGroups.map((g) => g.name).toList()
      : ['Roommates', 'Trip - Bali', 'Office Lunch', 'Family'];

  List<String> get _splitPeople {
    if (_splitwiseGroups.isNotEmpty) {
      final group = _splitwiseGroups.firstWhere(
        (g) => g.name == _selectedGroup,
        orElse: () => _splitwiseGroups.first,
      );
      return group.members.map((m) => m.name).toList();
    }
    return ['Sayuti', 'Zahra', 'Ahmad', 'Rina', 'Dian'];
  }

  double get _budgetPercent {
    final card = _creditCards.where((c) => c.name == _selectedAccount).firstOrNull;
    if (card != null && card.totalLimit > 0) {
      return card.usedAmount / card.totalLimit;
    }
    final cap = _creditCardCaps.firstOrNull;
    if (cap != null && cap.capTotalAmount > 0) {
      return cap.capCurrentAmount / cap.capTotalAmount;
    }
    return 0.57;
  }

  Future<void> _submitTransaction() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final amount = double.tryParse(_amount) ?? 0;
      final dateStr =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

      final catObj = _apiCategories.firstWhere(
        (c) => c.name == _selectedCategory,
        orElse: () => Category(id: '', name: _selectedCategory),
      );
      final subCatObj = catObj.subCategories.isNotEmpty
          ? catObj.subCategories.firstWhere(
              (s) => s.name == _selectedSubCategory,
              orElse: () => catObj.subCategories.first,
            )
          : SubCategory(id: '', name: _selectedSubCategory);

      switch (_selectedType) {
        case 0: // Income
          final bank = _bankAccounts.firstWhere(
            (b) => b.name == _selectedAccount,
            orElse: () => BankAccount(id: '', name: _selectedAccount, balance: 0),
          );
          await _api.addIncome(
            account: {'type': 'Bank', 'id': bank.id},
            amount: amount,
            date: dateStr,
            description: _descController.text,
            categoryId: catObj.id,
            subCategoryId: subCatObj.id,
          );
          break;
        case 1: // Expense
          final isCreditCard = _creditCards.any((c) => c.name == _selectedAccount);
          Map<String, dynamic> account;
          if (isCreditCard) {
            final card = _creditCards.firstWhere((c) => c.name == _selectedAccount);
            account = {'type': 'Credit Card', 'id': card.id};
          } else {
            final bank = _bankAccounts.firstWhere(
              (b) => b.name == _selectedAccount,
              orElse: () => BankAccount(id: '', name: _selectedAccount, balance: 0),
            );
            account = {'type': 'Bank', 'id': bank.id};
          }
          List<String>? splitUserIds;
          if (_showSplitwise && _splitwiseGroups.isNotEmpty) {
            final group = _splitwiseGroups.firstWhere(
              (g) => g.name == _selectedGroup,
              orElse: () => _splitwiseGroups.first,
            );
            splitUserIds = _selectedPeople
                .map((name) => group.members
                    .firstWhere((m) => m.name == name,
                        orElse: () => group.members.first)
                    .id)
                .toList();
          }
          await _api.addExpense(
            account: account,
            amount: amount,
            date: dateStr,
            description: _descController.text,
            categoryId: catObj.id,
            subCategoryId: subCatObj.id,
            includeSplitwise: _showSplitwise,
            splitwiseGroupId: _showSplitwise && _splitwiseGroups.isNotEmpty
                ? _splitwiseGroups.firstWhere((g) => g.name == _selectedGroup, orElse: () => _splitwiseGroups.first).id
                : null,
            splitwiseUserIds: splitUserIds,
            splitType: _showSplitwise ? _splitType.toLowerCase() : null,
          );
          break;
        case 2: // Transfer
          final fromBank = _bankAccounts.firstWhere(
            (b) => b.name == _selectedAccount,
            orElse: () => BankAccount(id: '', name: _selectedAccount, balance: 0),
          );
          await _api.addTransfer(
            fromAccountId: int.tryParse(fromBank.id) ?? 0,
            toAccountId: _bankAccounts.length > 1 ? (int.tryParse(_bankAccounts[1].id) ?? 0) : 0,
            amount: amount,
            date: dateStr,
            description: _descController.text,
          );
          break;
        case 3: // Investment
          final inv = _investmentAccounts.firstWhere(
            (a) => a.name == _selectedAccount,
            orElse: () => InvestmentAccount(id: '', name: _selectedAccount),
          );
          final bank = _bankAccounts.isNotEmpty ? _bankAccounts.first : BankAccount(id: '', name: '', balance: 0);
          await _api.addInvestment(
            accountId: bank.id,
            investmentAccountId: inv.id,
            amount: amount,
            date: dateStr,
            description: _descController.text,
          );
          break;
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onKeyTap(String key) {
    setState(() {
      if (key == '⌫') {
        if (_amount.length > 1) {
          _amount = _amount.substring(0, _amount.length - 1);
        } else {
          _amount = '0';
        }
      } else if (key == '.') {
        if (!_amount.contains('.')) {
          _amount += '.';
        }
      } else {
        if (_amount == '0') {
          _amount = key;
        } else {
          // Limit decimal places to 2
          if (_amount.contains('.')) {
            final parts = _amount.split('.');
            if (parts[1].length >= 2) return;
          }
          _amount += key;
        }
      }
    });
  }

  String get _formattedDate {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${_selectedDate.day} ${months[_selectedDate.month - 1]} ${_selectedDate.year}';
  }

  String get _formattedTime {
    final h = _selectedTime.hourOfPeriod == 0 ? 12 : _selectedTime.hourOfPeriod;
    final m = _selectedTime.minute.toString().padLeft(2, '0');
    final period = _selectedTime.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  @override
  void dispose() {
    _descController.dispose();
    _descFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F8),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF5F5F8),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF1E293B)),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Add Transaction',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Add Transaction',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 8),

                  // ── Type Tabs ──
                  _buildTypeTabs(),

                  const SizedBox(height: 16),

                  // ── Budget Alert ──
                  if (_selectedType == 1) _buildBudgetAlert(),

                  if (_selectedType == 1) const SizedBox(height: 16),

                  // ── Amount ──
                  GestureDetector(
                    onTap: () {
                      _descFocusNode.unfocus();
                      setState(() => _showNumpad = true);
                    },
                    child: Column(
                      children: [
                        Text(
                          'Amount',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹$_amount',
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            color: _showNumpad
                                ? const Color(0xFF3B3BF9)
                                : const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Date, Time & Account Row ──
                  _buildDateTimeAccountRow(),

                  const SizedBox(height: 16),

                  // ── Category & Sub Category ──
                  _buildCategoryRow(),

                  const SizedBox(height: 16),

                  // ── Description ──
                  _buildDescriptionField(),

                  // ── Splitwise Form ──
                  if (_showSplitwise && _selectedType == 1) ...[                    const SizedBox(height: 16),
                    _buildSplitwiseForm(),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // ── Number Pad ──
          if (_showNumpad) _buildNumberPad(),

          // ── Bottom Buttons ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submitTransaction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B3BF9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Add Transaction',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
                if (_selectedType == 1) ...[                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() => _showSplitwise = !_showSplitwise);
                        },
                        icon: const Icon(Icons.call_split,
                            size: 18, color: Color(0xFF3B3BF9)),
                        label: const Text(
                          'Splitwise',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF3B3BF9),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF3B3BF9)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Type Tabs ──
  Widget _buildTypeTabs() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(_typeLabels.length, (i) {
          final selected = _selectedType == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedType = i;
                final cats = _categories;
                if (cats.isNotEmpty) {
                  _selectedCategory = cats.first;
                  final subs = _subCategories[_selectedCategory] ?? ['Others'];
                  _selectedSubCategory = subs.first;
                }
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF1E293B) : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  _typeLabels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Budget Alert ──
  Widget _buildBudgetAlert() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20, color: Color(0xFFF9A825)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Budget Alert',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  'You\'ve spent ${(_budgetPercent * 100).toInt()}% of your monthly budget',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: Icon(Icons.close, size: 16, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  bool get _isCreditCard => _selectedAccount.contains('••');

  // ── Date, Time & Account Row ──
  Widget _buildDateTimeAccountRow() {
    return Column(
      children: [
        Row(
          children: [
            // Date & Time combined
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (pickedDate != null) {
                    setState(() => _selectedDate = pickedDate);
                  }
                  if (!mounted) return;
                  final pickedTime = await showTimePicker(
                    context: context,
                    initialTime: _selectedTime,
                  );
                  if (pickedTime != null) {
                    setState(() => _selectedTime = pickedTime);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 15, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(
                        '$_formattedDate, $_formattedTime',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.keyboard_arrow_down,
                          size: 16, color: Colors.grey.shade400),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Account
            Expanded(
              flex: 2,
              child: _buildChip(
                icon: _isCreditCard
                    ? Icons.credit_card
                    : Icons.account_balance_outlined,
                label: _selectedAccount.length > 12
                    ? '${_selectedAccount.substring(0, 12)}…'
                    : _selectedAccount,
                onTap: () => _showAccountPicker(),
              ),
            ),
          ],
        ),
        // Credit Cap row
        if (_isCreditCard) ...[          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFCC80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.credit_score,
                    size: 18, color: Color(0xFFF57C00)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Credit Cap: ₹5,000',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Available: ₹3,240 • Used: ₹1,760',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  void _showAccountPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select Account',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _accounts.map((a) {
                final selected = _selectedAccount == a;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF3B3BF9).withValues(alpha: 0.1)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      a.contains('••')
                          ? Icons.credit_card
                          : Icons.account_balance_outlined,
                      size: 20,
                      color: selected
                          ? const Color(0xFF3B3BF9)
                          : Colors.grey.shade600,
                    ),
                  ),
                  title: Text(
                    a,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? const Color(0xFF3B3BF9)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_circle,
                          color: Color(0xFF3B3BF9), size: 22)
                      : Icon(Icons.circle_outlined,
                          color: Colors.grey.shade300, size: 22),
                  onTap: () {
                    setState(() => _selectedAccount = a);
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Category & Sub Category ──
  Widget _buildCategoryRow() {
    final subs = _subCategories[_selectedCategory] ?? ['Others'];
    return Row(
      children: [
        Expanded(
          child: _buildDropdown(
            icon: Icons.category_outlined,
            label: _selectedCategory,
            items: _categories,
            onSelected: (val) {
              setState(() {
                _selectedCategory = val;
                _selectedSubCategory =
                    (_subCategories[val] ?? ['Others']).first;
              });
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildDropdown(
            icon: Icons.subdirectory_arrow_right,
            label: _selectedSubCategory,
            items: subs,
            onSelected: (val) => setState(() => _selectedSubCategory = val),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required IconData icon,
    required String label,
    required List<String> items,
    required ValueChanged<String> onSelected,
  }) {
    return Builder(
      builder: (dropdownContext) {
        return GestureDetector(
          onTap: () {
            final RenderBox box = dropdownContext.findRenderObject() as RenderBox;
            final offset = box.localToGlobal(Offset.zero);
            final size = box.size;
            showMenu<String>(
              context: dropdownContext,
              position: RelativeRect.fromLTRB(
                offset.dx,
                offset.dy + size.height,
                offset.dx + size.width,
                0,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              items: items
                  .map((item) => PopupMenuItem<String>(
                        value: item,
                        child: Text(
                          item,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: item == label
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: item == label
                                ? const Color(0xFF3B3BF9)
                                : const Color(0xFF1E293B),
                          ),
                        ),
                      ))
                  .toList(),
            ).then((val) {
              if (val != null) onSelected(val);
            });
          },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down,
                size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
      },
    );
  }

  // ── Description ──
  Widget _buildDescriptionField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: _descController,
        focusNode: _descFocusNode,
        maxLines: 2,
        onTap: () {
          setState(() => _showNumpad = false);
        },
        decoration: InputDecoration(
          hintText: 'Add a description...',
          hintStyle: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade400,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8, bottom: 16),
            child: Icon(Icons.notes, size: 18, color: Colors.grey.shade500),
          ),
          prefixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 0),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: InputBorder.none,
        ),
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }

  // ── Splitwise Form ──
  Widget _buildSplitwiseForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.call_split,
                  size: 18, color: Color(0xFF3B3BF9)),
              const SizedBox(width: 8),
              const Text(
                'Splitwise',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showSplitwise = false),
                child: Icon(Icons.close, size: 18, color: Colors.grey.shade400),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Group
          Text(
            'Group',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (ctx) => _buildSelectionSheet(
                  ctx,
                  'Select Group',
                  _splitGroups,
                  _selectedGroup,
                  (val) => setState(() => _selectedGroup = val),
                ),
              );
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8FB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.group_outlined,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Text(
                    _selectedGroup,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.keyboard_arrow_down,
                      size: 16, color: Colors.grey.shade400),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Split With
          Text(
            'Split With',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (ctx) => _buildPeopleSheet(ctx),
              );
            },
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8FB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: _selectedPeople.isEmpty
                  ? Text(
                      'Select people...',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                      ),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selectedPeople.map((p) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF3B3BF9).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                p,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF3B3BF9),
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedPeople.remove(p);
                                  });
                                },
                                child: const Icon(Icons.close,
                                    size: 14, color: Color(0xFF3B3BF9)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ),

          const SizedBox(height: 14),

          // Split Type
          Text(
            'Split Type',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: ['Equal', 'Custom'].map((type) {
              final selected = _splitType == type;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      right: type == 'Equal' ? 5 : 0,
                      left: type == 'Custom' ? 5 : 0),
                  child: GestureDetector(
                    onTap: () => setState(() => _splitType = type),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF3B3BF9)
                            : const Color(0xFFF8F8FB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF3B3BF9)
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            type == 'Equal'
                                ? Icons.drag_handle
                                : Icons.tune,
                            size: 16,
                            color: selected
                                ? Colors.white
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            type,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionSheet(
    BuildContext ctx,
    String title,
    List<String> items,
    String selected,
    ValueChanged<String> onSelected,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final isSel = item == selected;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isSel
                      ? const Color(0xFF3B3BF9).withValues(alpha: 0.1)
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.group,
                    size: 18,
                    color: isSel
                        ? const Color(0xFF3B3BF9)
                        : Colors.grey.shade500),
              ),
              title: Text(
                item,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                  color: isSel
                      ? const Color(0xFF3B3BF9)
                      : const Color(0xFF1E293B),
                ),
              ),
              trailing: isSel
                  ? const Icon(Icons.check_circle,
                      color: Color(0xFF3B3BF9), size: 22)
                  : Icon(Icons.circle_outlined,
                      color: Colors.grey.shade300, size: 22),
              onTap: () {
                onSelected(item);
                Navigator.pop(ctx);
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPeopleSheet(BuildContext ctx) {
    return StatefulBuilder(
      builder: (context, setSheetState) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Split With',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              ..._splitPeople.map((person) {
                final isSel = _selectedPeople.contains(person);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: isSel
                        ? const Color(0xFF3B3BF9).withValues(alpha: 0.1)
                        : const Color(0xFFF3F4F6),
                    child: Icon(Icons.person,
                        size: 18,
                        color: isSel
                            ? const Color(0xFF3B3BF9)
                            : Colors.grey.shade500),
                  ),
                  title: Text(
                    person,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSel ? FontWeight.w600 : FontWeight.w500,
                      color: isSel
                          ? const Color(0xFF3B3BF9)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  trailing: Icon(
                    isSel
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color: isSel
                        ? const Color(0xFF3B3BF9)
                        : Colors.grey.shade300,
                    size: 22,
                  ),
                  onTap: () {
                    setState(() {
                      if (isSel) {
                        _selectedPeople.remove(person);
                      } else {
                        _selectedPeople.add(person);
                      }
                    });
                    setSheetState(() {});
                  },
                );
              }),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B3BF9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Number Pad ──
  Widget _buildNumberPad() {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', '⌫'],
    ];

    return Container(
      color: const Color(0xFFF0F0F3),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Column(
        children: keys.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: row.map((key) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _onKeyTap(key),
                        child: Container(
                          height: 50,
                          alignment: Alignment.center,
                          child: key == '⌫'
                              ? Icon(Icons.backspace_outlined,
                                  size: 20, color: Colors.grey.shade700)
                              : Text(
                                  key,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}
