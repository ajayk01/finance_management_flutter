import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_data_cache.dart';

class AddTransactionScreen extends StatefulWidget {
  final TransactionModel? prefill;
  final bool isEdit;
  final bool fromNotification;
  final Set<String> lockFields;
  const AddTransactionScreen({super.key, this.prefill, this.isEdit = false, this.fromNotification = false, this.lockFields = const {}});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  int _selectedType = 0; // 0=Income, 1=Expense, 2=Transfer, 3=Investment
  String _selectedCategory = '';
  String _selectedSubCategory = '';
  String _selectedAccount = '';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  final TextEditingController _amountController = TextEditingController(text: '');
  final TextEditingController _chargesController = TextEditingController(text: '');
  final TextEditingController _descController = TextEditingController();
  double _previousCharges = 0; // Track previous charges for auto-adjustment
  bool _showSplitwise = false;
  String _selectedGroup = '';
  final List<String> _selectedPeople = [];
  String _splitType = 'Equal';
  final Map<String, TextEditingController> _customAmountControllers = {};
  String? _accountError;
  String? _categoryError;
  String? _subCategoryError;
  String _selectedFromAccount = '';
  String _selectedToAccount = '';
  String? _fromAccountError;
  String? _toAccountError;
  final _api = ApiService();

  static const _typeIcons = [
    Icons.arrow_downward_outlined,
    Icons.arrow_upward_outlined,
    Icons.swap_horiz_outlined,
    Icons.trending_up_outlined,
  ];

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
    //_loadFormData();
    _applyPrefill();
    
    // Setup listener for charges to auto-adjust amount
    _chargesController.addListener(_onChargesChanged);
  }

  void _onChargesChanged() {
    // Only apply auto-adjustment for expense type
    if (_selectedType != 1) return;
    
    final currentAmount = double.tryParse(_amountController.text) ?? 0;
    final newCharges = double.tryParse(_chargesController.text) ?? 0;
    
    // Calculate net amount (what was actually paid)
    final netAmount = currentAmount + _previousCharges;
    
    // Calculate new transaction amount: net - new charges
    final newAmount = netAmount - newCharges;
    
    // Only update if the new amount is valid and different
    if (newAmount > 0 && (newAmount - currentAmount).abs() > 0.01) {
      _amountController.text = newAmount == newAmount.roundToDouble() && newAmount == newAmount.truncateToDouble()
          ? newAmount.toStringAsFixed(0)
          : newAmount.toStringAsFixed(2);
    }
    
    // Update tracked charges
    _previousCharges = newCharges;
  }

  void _applyPrefill() {
    final tx = widget.prefill;
    if (tx == null) return;
    switch (tx.type.toLowerCase()) {
      case 'income':
        _selectedType = 0;
        break;
      case 'expense':
        _selectedType = 1;
        break;
      case 'transfer':
        _selectedType = 2;
        break;
      case 'investment':
        _selectedType = 3;
        break;
    }
    _amountController.text = tx.amount == tx.amount.roundToDouble() && tx.amount == tx.amount.truncateToDouble()
        ? tx.amount.toStringAsFixed(0)
        : tx.amount.toString();
    _chargesController.text = tx.charges > 0
        ? (tx.charges == tx.charges.roundToDouble() && tx.charges == tx.charges.truncateToDouble()
            ? tx.charges.toStringAsFixed(0)
            : tx.charges.toString())
        : '';
    _previousCharges = tx.charges;
    _descController.text = tx.description;
    try {
      _selectedDate = DateTime.parse(tx.date);
    } catch (_) {}
    if (tx.time != null) {
      final parts = tx.time!.split(':');
      if (parts.length >= 2) {
        _selectedTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 0,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
    if (tx.category != null) _selectedCategory = tx.category!;
    if (tx.subCategory != null) _selectedSubCategory = tx.subCategory!;
    if (tx.accountName != null) _selectedAccount = tx.accountName!;

    // For Transfer: accountName is the from account
    if (tx.type.toLowerCase() == 'transfer' && tx.accountName != null) {
      _selectedFromAccount = tx.accountName!;
    }
    // For Investment: accountName is the from (bank) account, investmentAccountName is the to account
    if (tx.type.toLowerCase() == 'investment') {
      if (tx.accountName != null) _selectedFromAccount = tx.accountName!;
      if (tx.investmentAccountName != null) _selectedToAccount = tx.investmentAccountName!;
    }

    // Splitwise details
    final sw = tx.splitwiseDetails;
    if (sw != null && sw.isNotEmpty) {
      _showSplitwise = true;
      final first = sw.first;
      if (first is Map) {
        final groupId = (first['groupId'] ?? first['splitwiseGroupId'])?.toString();
        _splitType = (first['splitType'] ?? 'Equal').toString();
        if (groupId != null) {
          _pendingSplitwiseGroupId = groupId;
        }
      }
      // Collect friend IDs from splitwise details
      _pendingSplitwiseMemberIds = sw
          .where((e) => e is Map)
          .map((e) {
            final id = (e['friendId'] ?? e['userId'] ?? e['splitwiseUserId'])?.toString();
            return id;
          })
          .where((id) => id != null)
          .cast<String>()
          .toList();
      // Also collect friend names as fallback for direct matching
      _pendingSplitwiseFriendNames = sw
          .where((e) => e is Map && e['friendName'] != null)
          .map((e) => e['friendName'].toString())
          .toList();
    }

    // Fallback: use top-level splitwise fields from the transaction
    if (tx.includeSplitwise || tx.splitwiseGroupId != null) {
      _showSplitwise = true;
      if (tx.splitwiseGroupId != null && _pendingSplitwiseGroupId == null) {
        _pendingSplitwiseGroupId = tx.splitwiseGroupId;
      }
      if (tx.splitType != null) {
        _splitType = tx.splitType!;
      }
      if (tx.splitwiseUserIds != null && _pendingSplitwiseMemberIds.isEmpty) {
        _pendingSplitwiseMemberIds = tx.splitwiseUserIds!
            .map((e) => e.toString())
            .toList();
      }
    }
  }

  String? _pendingSplitwiseGroupId;
  List<String> _pendingSplitwiseMemberIds = [];
  List<String> _pendingSplitwiseFriendNames = [];

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
      if (banks.isNotEmpty && _selectedFromAccount.isEmpty) {
        _selectedFromAccount = banks.first.name;
      }
      if (invs.isNotEmpty && _selectedToAccount.isEmpty && _selectedType == 3) {
        _selectedToAccount = invs.first.name;
      }
      if (banks.isNotEmpty && _selectedToAccount.isEmpty && _selectedType == 2 && banks.length > 1) {
        _selectedToAccount = banks[1].name;
      }
      if (groups.isNotEmpty && _selectedGroup.isEmpty) {
        _selectedGroup = groups.first.name;
      }

      // Resolve pending splitwise prefill
      if ((_pendingSplitwiseGroupId != null || _pendingSplitwiseMemberIds.isNotEmpty || _pendingSplitwiseFriendNames.isNotEmpty) && groups.isNotEmpty) {
        SplitwiseGroup? matchedGroup;

        // Try to match by group ID first
        if (_pendingSplitwiseGroupId != null) {
          matchedGroup = groups.where((g) => g.id == _pendingSplitwiseGroupId).firstOrNull;
        }

        // If no group ID, find the group that contains the most matching friends
        if (matchedGroup == null && _pendingSplitwiseMemberIds.isNotEmpty) {
          int bestMatchCount = 0;
          for (final g in groups) {
            final matchCount = _pendingSplitwiseMemberIds
                .where((fid) => g.members.any((m) => m.friendId == fid || m.id == fid))
                .length;
            if (matchCount > bestMatchCount) {
              bestMatchCount = matchCount;
              matchedGroup = g;
            }
          }
        }

        if (matchedGroup != null) {
          _selectedGroup = matchedGroup.name;
          _selectedPeople.clear();
          // Match members by friendId or member id
          for (final fid in _pendingSplitwiseMemberIds) {
            final m = matchedGroup.members.where((m) => m.friendId == fid || m.id == fid).firstOrNull;
            if (m != null) _selectedPeople.add(m.name);
          }
          // If no members matched by ID, fall back to friend names
          if (_selectedPeople.isEmpty && _pendingSplitwiseFriendNames.isNotEmpty) {
            for (final fname in _pendingSplitwiseFriendNames) {
              final m = matchedGroup.members.where((m) => m.name == fname).firstOrNull;
              if (m != null) {
                _selectedPeople.add(m.name);
              }
            }
          }
        }
        _pendingSplitwiseGroupId = null;
        _pendingSplitwiseMemberIds = [];
        _pendingSplitwiseFriendNames = [];
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

  List<String> get _bankOnlyAccounts {
    final items = <String>[];
    for (final b in _bankAccounts) { items.add(b.name); }
    for (final c in _creditCards) { items.add(c.name); }
    if (items.isEmpty) return ['Chase Bank', 'Bank of America'];
    return items;
  }

  List<String> get _investmentAccountNames {
    final items = <String>[];
    for (final a in _investmentAccounts) { items.add(a.name); }
    if (items.isEmpty) return ['Investment Account'];
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

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFEF4444),
      ),
    );
  }

  Future<void> _submitTransaction() async {
    final formValid = _formKey.currentState!.validate();

    // Validate tappable fields
    bool tappableValid = true;
    final isTransferOrInvestment = _selectedType == 2 || _selectedType == 3;
    setState(() {
      if (isTransferOrInvestment) {
        // Validate from/to accounts
        _accountError = null;
        _categoryError = null;
        _subCategoryError = null;
        if (_selectedFromAccount.isEmpty) {
          _fromAccountError = 'Please select a from account';
          tappableValid = false;
        } else {
          _fromAccountError = null;
        }
        if (_selectedToAccount.isEmpty) {
          _toAccountError = 'Please select a to account';
          tappableValid = false;
        } else {
          _toAccountError = null;
        }
      } else {
        // Validate single account + category/subcategory
        _fromAccountError = null;
        _toAccountError = null;
        if (_selectedAccount.isEmpty) {
          _accountError = 'Please select an account';
          tappableValid = false;
        } else {
          _accountError = null;
        }
        if (_selectedCategory.isEmpty) {
          _categoryError = 'Please select a category';
          tappableValid = false;
        } else {
          _categoryError = null;
        }
        if (_selectedSubCategory.isEmpty) {
          _subCategoryError = 'Please select a sub category';
          tappableValid = false;
        } else {
          _subCategoryError = null;
        }
      }
    });

    if (!formValid || !tappableValid) {
      _showValidationError('Please fill in all required fields');
      return;
    }

    // Splitwise validations
    if (_showSplitwise && _selectedType == 1) {
      if (_selectedGroup.isEmpty) {
        _showValidationError('Please select a Splitwise group');
        return;
      }
      if (_selectedPeople.isEmpty) {
        _showValidationError('Please select at least one person to split with');
        return;
      }
      if (_splitType == 'Custom') {
        final totalAmount = double.tryParse(_amountController.text) ?? 0;
        double allocated = 0;
        for (final c in _customAmountControllers.values) {
          allocated += double.tryParse(c.text.trim()) ?? 0;
        }
        if (allocated <= 0) {
          _showValidationError('Please enter custom amounts for each person');
          return;
        }
        final remaining = totalAmount - allocated;
        if (remaining.abs() > 0.01) {
          _showValidationError(
            'Custom amounts must equal the total amount (₹${remaining.toStringAsFixed(2)} remaining)',
          );
          return;
        }
      }
    }

    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final amount = double.tryParse(_amountController.text) ?? 0;
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

      // ── Edit mode: call update APIs ──
      if (widget.isEdit && widget.prefill != null) {
        final body = <String, dynamic>{
          'id': widget.prefill!.id,
          'amount': amount,
          'date': dateStr,
          'description': _descController.text,
          'categoryId': catObj.id,
          'subCategoryId': subCatObj.id,
        };

        // Add charges for expense edit
        if (_selectedType == 1) {
          final charges = double.tryParse(_chargesController.text) ?? 0;
          body['charges'] = charges;
        }

        // Resolve account
        final isCreditCard = _creditCards.any((c) => c.name == _selectedAccount);
        if (isCreditCard) {
          final card = _creditCards.firstWhere((c) => c.name == _selectedAccount);
          body['account'] = {'type': 'Credit Card', 'id': card.id};
          body['accountId'] = card.id;
        } else {
          final bank = _bankAccounts.firstWhere(
            (b) => b.name == _selectedAccount,
            orElse: () => BankAccount(id: '', name: _selectedAccount, balance: 0),
          );
          body['account'] = {'type': 'Bank', 'id': bank.id};
          body['accountId'] = bank.id;
        }

        // Splitwise for expense edit
        if (_selectedType == 1 && _showSplitwise && _splitwiseGroups.isNotEmpty) {
          body['includeSplitwise'] = true;
          final group = _splitwiseGroups.firstWhere(
            (g) => g.name == _selectedGroup,
            orElse: () => _splitwiseGroups.first,
          );
          body['splitwiseGroupId'] = group.id;
          body['splitwiseUserIds'] = _selectedPeople
              .map((name) => group.members
                  .firstWhere((m) => m.name == name, orElse: () => group.members.first)
                  .id)
              .toList();
          body['splitType'] = _splitType.toLowerCase();
          if (_splitType == 'Custom') {
            final customAmounts = <String, double>{};
            for (final entry in _customAmountControllers.entries) {
              final val = double.tryParse(entry.value.text.trim());
              if (val != null && val > 0) {
                customAmounts[entry.key] = val;
              }
            }
            if (customAmounts.isNotEmpty) {
              body['customAmounts'] = customAmounts;
            }
          }
        }

        switch (_selectedType) {
          case 0:
            await _api.updateIncome(body);
            break;
          case 1:
            await _api.updateExpense(body);
            break;
          case 3:
            body['investmentAccountId'] = widget.prefill!.investmentAccountId;
            await _api.updateInvestment(body);
            break;
        }

        if (mounted) Navigator.pop(context, true);
        return;
      }

      // ── Create mode (existing logic) ──
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
          final charges = double.tryParse(_chargesController.text) ?? 0;
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
            charges: charges,
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
            customAmounts: _showSplitwise && _splitType == 'Custom'
                ? () {
                    final m = <String, double>{};
                    for (final entry in _customAmountControllers.entries) {
                      final val = double.tryParse(entry.value.text.trim());
                      if (val != null && val > 0) m[entry.key] = val;
                    }
                    return m.isNotEmpty ? m : null;
                  }()
                : null,
          );
          break;
        case 2: // Transfer
          final fromAccount = _bankAccounts.firstWhere(
            (b) => b.name == _selectedFromAccount,
            orElse: () => _creditCards.isNotEmpty
                ? BankAccount(id: _creditCards.firstWhere((c) => c.name == _selectedFromAccount, orElse: () => _creditCards.first).id, name: _selectedFromAccount, balance: 0)
                : BankAccount(id: '', name: _selectedFromAccount, balance: 0),
          );
          final toAccount = _bankAccounts.firstWhere(
            (b) => b.name == _selectedToAccount,
            orElse: () => _creditCards.isNotEmpty
                ? BankAccount(id: _creditCards.firstWhere((c) => c.name == _selectedToAccount, orElse: () => _creditCards.first).id, name: _selectedToAccount, balance: 0)
                : BankAccount(id: '', name: _selectedToAccount, balance: 0),
          );
          await _api.addTransfer(
            fromAccountId: int.tryParse(fromAccount.id) ?? 0,
            toAccountId: int.tryParse(toAccount.id) ?? 0,
            amount: amount,
            date: dateStr,
            description: _descController.text,
          );
          break;
        case 3: // Investment
          final fromBank = _bankAccounts.firstWhere(
            (b) => b.name == _selectedFromAccount,
            orElse: () => BankAccount(id: '', name: _selectedFromAccount, balance: 0),
          );
          final inv = _investmentAccounts.firstWhere(
            (a) => a.name == _selectedToAccount,
            orElse: () => InvestmentAccount(id: '', name: _selectedToAccount),
          );
          await _api.addInvestment(
            accountId: fromBank.id,
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
    _amountController.dispose();
    _chargesController.dispose();
    _descController.dispose();
    for (final c in _customAmountControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F8),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(widget.isEdit ? 'Update Transaction' : 'Add Transaction',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isEdit ? 'Update Transaction' : 'Add Transaction',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Type Selector ──
              _buildTypeTabs(),
              const SizedBox(height: 24),

              // ── Budget Alert ──
              if (_selectedType == 1) ...[
                _buildBudgetAlert(),
                const SizedBox(height: 16),
              ],

              // ── Amount ──
              _buildTextField(
                label: 'Amount',
                controller: _amountController,
                hint: '0',
                icon: Icons.currency_rupee_outlined,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                prefix: '₹ ',
                readOnly: widget.fromNotification || widget.lockFields.contains('amount') || (widget.isEdit && _selectedType == 1),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter amount';
                  final parsed = double.tryParse(v.trim());
                  if (parsed == null) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── Charges (Expense only, enabled in edit mode) ──
              if (_selectedType == 1) ...[
                _buildTextField(
                  label: 'Charges',
                  controller: _chargesController,
                  hint: '0',
                  icon: Icons.discount_outlined,
                  keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: true),
                  prefix: '₹ ',
                  readOnly: widget.fromNotification && !widget.isEdit,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  validator: (v) {
                    if (v != null && v.trim().isNotEmpty) {
                      final parsed = double.tryParse(v.trim());
                      if (parsed == null) return 'Enter a valid charges amount';
                      if (parsed < 0) return 'Charges cannot be negative';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                // ── Net Amount Display ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Builder(
                    builder: (context) {
                      final amount = double.tryParse(_amountController.text) ?? 0;
                      final charges = double.tryParse(_chargesController.text) ?? 0;
                      final netAmount = amount + charges;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Net Amount',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            '₹${netAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: netAmount >= 0 ? const Color(0xFF5BC5A7) : const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Date & Time ──
              _buildDateTimeField(),
              const SizedBox(height: 16),

              // ── Account / From-To Accounts ──
              if (_selectedType == 2 || _selectedType == 3) ...[
                // From Account
                _buildTappableField(
                  label: 'From Account',
                  value: _selectedFromAccount,
                  icon: Icons.account_balance_outlined,
                  onTap: (widget.fromNotification || widget.lockFields.contains('account')) ? null : () => _showFromAccountPicker(),
                  errorText: _fromAccountError,
                ),
                const SizedBox(height: 16),
                // To Account
                _buildTappableField(
                  label: 'To Account',
                  value: _selectedToAccount,
                  icon: _selectedType == 3 ? Icons.trending_up : Icons.account_balance_outlined,
                  onTap: widget.lockFields.contains('account') ? null : () => _showToAccountPicker(),
                  errorText: _toAccountError,
                ),
                const SizedBox(height: 16),
              ] else ...[
                _buildTappableField(
                  label: 'Account',
                  value: _selectedAccount,
                  icon: _isCreditCard
                      ? Icons.credit_card
                      : Icons.account_balance_outlined,
                  onTap: (widget.fromNotification || widget.lockFields.contains('account')) ? null : () => _showAccountPicker(),
                  errorText: _accountError,
                ),
                const SizedBox(height: 16),

                // ── Credit Cap ──
                if (_isCreditCard) ...[
                  _buildCreditCapAlert(),
                  const SizedBox(height: 16),
                ],

                // ── Category & Sub Category ──
                _buildCategoryRow(),
                const SizedBox(height: 16),
              ],

              // ── Description ──
              _buildTextField(
                label: 'Description',
                controller: _descController,
                hint: 'Add a description...',
                icon: Icons.notes_outlined,
                maxLines: 2,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a description' : null,
              ),

              // ── Splitwise Toggle (edit mode) ──
              if (widget.isEdit && _selectedType == 1) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => setState(() => _showSplitwise = !_showSplitwise),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _showSplitwise,
                          onChanged: (v) => setState(() => _showSplitwise = v ?? false),
                          activeColor: const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Edit Splitwise',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Splitwise Form ──
              if (_showSplitwise && _selectedType == 1) ...[
                const SizedBox(height: 16),
                _buildSplitwiseForm(),
              ],

              const SizedBox(height: 32),

              // ── Bottom Buttons ──
              if (!widget.isEdit && _selectedType == 1)
                Row(
                  children: [
                    Expanded(child: _buildSubmitButton()),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            if (!_showSplitwise) {
                              // Validate required fields before opening Splitwise
                              final errors = <String>[];
                              final amount = double.tryParse(_amountController.text.trim()) ?? 0;
                              if (amount <= 0) errors.add('Amount');
                              if (_selectedAccount.isEmpty) errors.add('Account');
                              if (_selectedCategory.isEmpty) errors.add('Category');
                              if (_selectedSubCategory.isEmpty) errors.add('Sub Category');
                              if (_descController.text.trim().isEmpty) errors.add('Description');
                              if (errors.isNotEmpty) {
                                _showValidationError(
                                  'Please fill ${errors.join(", ")} before adding Splitwise',
                                );
                                return;
                              }
                            }
                            setState(() => _showSplitwise = !_showSplitwise);
                          },
                          icon: Image.asset('assets/images/splitwise_logo.png',
                              width: 20, height: 20),
                          label: const Text(
                            'Splitwise',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Type Tabs ──
  Widget _buildTypeTabs() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEF0),
        borderRadius: BorderRadius.circular(30),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(_typeLabels.length, (i) {
          final selected = _selectedType == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() {
                  _selectedType = i;
                  // Sync account fields when switching between types
                  if (i == 2 || i == 3) {
                    // Switching to Transfer/Investment: carry Account → From Account
                    if (_selectedAccount.isNotEmpty) {
                      _selectedFromAccount = _selectedAccount;
                    }
                  } else {
                    // Switching to Income/Expense: carry From Account → Account
                    if (_selectedFromAccount.isNotEmpty) {
                      _selectedAccount = _selectedFromAccount;
                    }
                  }
                  final cats = _categories;
                  if (cats.isNotEmpty) {
                    _selectedCategory = cats.first;
                    final subs = _subCategories[_selectedCategory] ?? ['Others'];
                    _selectedSubCategory = subs.first;
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                decoration: BoxDecoration(
                  color: selected ? Colors.black : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Center(
                  child: Text(
                    _typeLabels[i],
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : Colors.grey.shade600,
                    ),
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

  // ── Text Field (matching Add Account style) ──
  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? prefix,
    String? Function(String?)? validator,
    int maxLines = 1,
    bool readOnly = false,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          readOnly: readOnly,
          inputFormatters: inputFormatters,
          style: readOnly
              ? TextStyle(color: Colors.grey.shade500)
              : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Icon(icon, color: const Color(0xFF6B7280), size: 20),
            prefixText: prefix,
            prefixStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
            filled: true,
            fillColor: readOnly ? Colors.grey.shade100 : Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF1E293B), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFEF4444)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Date & Time Field ──
  Widget _buildDateTimeField() {
    final locked = widget.fromNotification;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date & Time',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: locked
              ? null
              : () async {
            FocusManager.instance.primaryFocus?.unfocus();
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: locked ? Colors.grey.shade100 : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 20, color: Color(0xFF6B7280)),
                const SizedBox(width: 12),
                Text(
                  '$_formattedDate, $_formattedTime',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: locked ? Colors.grey.shade500 : const Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                Icon(Icons.keyboard_arrow_down,
                    size: 20, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Tappable Field (for Account, etc.) ──
  Widget _buildTappableField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback? onTap,
    String? errorText,
  }) {
    final hasError = errorText != null && errorText.isNotEmpty;
    final locked = onTap == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap == null
              ? null
              : () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  onTap();
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: locked ? Colors.grey.shade100 : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasError ? const Color(0xFFEF4444) : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xFF6B7280)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value.isEmpty ? 'Select...' : value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: value.isEmpty
                          ? Colors.grey.shade400
                          : locked
                              ? Colors.grey.shade500
                              : const Color(0xFF1E293B),
                    ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down,
                    size: 20, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              errorText,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Credit Cap Alert ──
  Widget _buildCreditCapAlert() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCC80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.credit_score, size: 18, color: Color(0xFFF57C00)),
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
    );
  }

  // ── Submit Button ──
  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submitTransaction,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E293B),
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                widget.isEdit ? 'Update Transaction' : 'Add Transaction',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
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
                    setState(() {
                      _selectedAccount = a;
                      _accountError = null;
                    });
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

  void _showFromAccountPicker() {
    _showGenericAccountPicker(
      title: 'Select From Account',
      accounts: _bankOnlyAccounts,
      selected: _selectedFromAccount,
      onSelected: (val) {
        setState(() {
          _selectedFromAccount = val;
          _fromAccountError = null;
        });
      },
    );
  }

  void _showToAccountPicker() {
    final accounts = _selectedType == 3 ? _investmentAccountNames : _bankOnlyAccounts;
    _showGenericAccountPicker(
      title: 'Select To Account',
      accounts: accounts,
      selected: _selectedToAccount,
      onSelected: (val) {
        setState(() {
          _selectedToAccount = val;
          _toAccountError = null;
        });
      },
    );
  }

  void _showGenericAccountPicker({
    required String title,
    required List<String> accounts,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: accounts.map((a) {
                    final isSel = selected == a;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSel
                              ? const Color(0xFF3B3BF9).withValues(alpha: 0.1)
                              : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.account_balance_outlined,
                          size: 20,
                          color: isSel
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
                        onSelected(a);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTappableField(
          label: 'Category',
          value: _selectedCategory,
          icon: Icons.category_outlined,
          errorText: _categoryError,
          onTap: () => _showDropdownMenu(
            items: _categories,
            selected: _selectedCategory,
            onSelected: (val) {
              setState(() {
                _selectedCategory = val;
                _categoryError = null;
                _selectedSubCategory =
                    (_subCategories[val] ?? ['Others']).first;
              });
            },
          ),
        ),
        const SizedBox(height: 16),
        _buildTappableField(
          label: 'Sub Category',
          value: _selectedSubCategory,
          icon: Icons.subdirectory_arrow_right,
          errorText: _subCategoryError,
          onTap: () => _showDropdownMenu(
            items: subs,
            selected: _selectedSubCategory,
            onSelected: (val) => setState(() {
              _selectedSubCategory = val;
              _subCategoryError = null;
            }),
          ),
        ),
      ],
    );
  }

  void _showDropdownMenu({
    required List<String> items,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
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
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: items.map((item) {
                    final isSel = item == selected;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                          color: isSel
                              ? const Color(0xFF1E293B)
                              : const Color(0xFF374151),
                        ),
                      ),
                      trailing: isSel
                          ? const Icon(Icons.check_circle,
                              color: Color(0xFF1E293B), size: 22)
                          : Icon(Icons.circle_outlined,
                              color: Colors.grey.shade300, size: 22),
                      onTap: () {
                        onSelected(item);
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
              Image.asset('assets/images/splitwise_logo.png',
                  width: 20, height: 20),
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
                isScrollControlled: true,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
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
                isScrollControlled: true,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
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
                                const Color(0xFF5BC5A7).withValues(alpha: 0.1),
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
                                  color: Color(0xFF5BC5A7),
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
                                    size: 14, color: Color(0xFF5BC5A7)),
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
                            ? const Color(0xFF5BC5A7)
                            : const Color(0xFFF8F8FB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF5BC5A7)
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

          // ── Custom Amount Inputs ──
          if (_splitType == 'Custom' && _selectedPeople.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Custom Amounts',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 6),
            ..._selectedPeople.map((person) {
              final group = _splitwiseGroups.firstWhere(
                (g) => g.name == _selectedGroup,
                orElse: () => _splitwiseGroups.first,
              );
              final member = group.members.firstWhere(
                (m) => m.name == person,
                orElse: () => group.members.first,
              );
              _customAmountControllers.putIfAbsent(
                member.id,
                () => TextEditingController(),
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: const Color(0xFF5BC5A7).withValues(alpha: 0.1),
                      child: const Icon(Icons.person, size: 14, color: Color(0xFF5BC5A7)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Text(
                        person,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _customAmountControllers[member.id],
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          prefixText: '₹ ',
                          prefixStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8F8FB),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFF5BC5A7), width: 1.5),
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),
            Builder(builder: (_) {
              final totalAmount = double.tryParse(_amountController.text) ?? 0;
              double allocated = 0;
              for (final c in _customAmountControllers.values) {
                allocated += double.tryParse(c.text.trim()) ?? 0;
              }
              final remaining = totalAmount - allocated;
              return Column(
                children: [
                  _buildSummaryRow('Total Amount:', '₹${totalAmount.toStringAsFixed(0)}', const Color(0xFF1E293B)),
                  const SizedBox(height: 4),
                  _buildSummaryRow('Allocated:', '₹${allocated.toStringAsFixed(2)}', const Color(0xFF1E293B)),
                  const SizedBox(height: 4),
                  _buildSummaryRow(
                    'Remaining:',
                    '₹${remaining.toStringAsFixed(2)}',
                    remaining == 0
                        ? const Color(0xFF22C55E)
                        : remaining < 0
                            ? const Color(0xFFEF4444)
                            : const Color(0xFFF59E0B),
                  ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
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
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: items.map((item) {
                final isSel = item == selected;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isSel
                          ? const Color(0xFF5BC5A7).withValues(alpha: 0.1)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.group,
                        size: 18,
                        color: isSel
                            ? const Color(0xFF5BC5A7)
                            : Colors.grey.shade500),
                  ),
                  title: Text(
                    item,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                      color: isSel
                          ? const Color(0xFF5BC5A7)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  trailing: isSel
                      ? const Icon(Icons.check_circle,
                          color: Color(0xFF5BC5A7), size: 22)
                      : Icon(Icons.circle_outlined,
                          color: Colors.grey.shade300, size: 22),
                  onTap: () {
                    onSelected(item);
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ),
          ),
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
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _splitPeople.map((person) {
                    final isSel = _selectedPeople.contains(person);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: isSel
                            ? const Color(0xFF5BC5A7).withValues(alpha: 0.1)
                            : const Color(0xFFF3F4F6),
                        child: Icon(Icons.person,
                            size: 18,
                            color: isSel
                                ? const Color(0xFF5BC5A7)
                                : Colors.grey.shade500),
                      ),
                      title: Text(
                        person,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isSel ? FontWeight.w600 : FontWeight.w500,
                          color: isSel
                              ? const Color(0xFF5BC5A7)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                      trailing: Icon(
                        isSel
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: isSel
                            ? const Color(0xFF5BC5A7)
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
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5BC5A7),
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
}
