import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({super.key});

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();

  final _nameController = TextEditingController();
  final _initialBalanceController = TextEditingController();
  final _usedAmountController = TextEditingController();
  final _totalLimitController = TextEditingController();

  int _selectedType = 0; // 0=Bank, 1=Credit Card, 2=Investment
  bool _submitting = false;

  static const _typeLabels = ['Bank', 'Credit Card', 'Investment'];
  static const _typeIcons = [
    Icons.account_balance_outlined,
    Icons.credit_card_outlined,
    Icons.trending_up_outlined,
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _initialBalanceController.dispose();
    _usedAmountController.dispose();
    _totalLimitController.dispose();
    super.dispose();
  }

  String get _accountType {
    switch (_selectedType) {
      case 0:
        return 'bank';
      case 1:
        return 'credit_card';
      case 2:
        return 'investment';
      default:
        return 'bank';
    }
  }

  bool get _isCreditCard => _selectedType == 1;

  Future<void> _submit() async {
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
      final name = _nameController.text.trim();
      double initialBalance = 0;
      double? totalLimit;

      if (_isCreditCard) {
        initialBalance =
            double.tryParse(_usedAmountController.text.trim()) ?? 0;
        totalLimit =
            double.tryParse(_totalLimitController.text.trim()) ?? 0;
      } else {
        initialBalance =
            double.tryParse(_initialBalanceController.text.trim()) ?? 0;
      }

      await _api.createAccount(
        accountName: name,
        accountType: _accountType,
        initialBalance: initialBalance,
        totalLimit: _isCreditCard ? totalLimit : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create account: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Add Account',
          style: TextStyle(
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
              _buildTypeSelector(),
              const SizedBox(height: 24),
              _buildTextField(
                label: 'Account Name',
                controller: _nameController,
                hint: 'e.g. HDFC Savings',
                icon: _typeIcons[_selectedType],
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter account name' : null,
              ),
              const SizedBox(height: 16),
              if (_isCreditCard) ...[
                _buildTextField(
                  label: 'Current Used Amount',
                  controller: _usedAmountController,
                  hint: '0',
                  icon: Icons.money_off_outlined,
                  keyboardType: TextInputType.number,
                  prefix: '₹ ',
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter used amount';
                    final parsed = double.tryParse(v.trim());
                    if (parsed == null || parsed < 0) return 'Enter a valid amount';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'Total Limit',
                  controller: _totalLimitController,
                  hint: '0',
                  icon: Icons.shield_outlined,
                  keyboardType: TextInputType.number,
                  prefix: '₹ ',
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Enter total limit';
                    }
                    final parsed = double.tryParse(v.trim());
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a valid limit';
                    }
                    return null;
                  },
                ),
              ] else
                _buildTextField(
                  label: 'Initial Amount',
                  controller: _initialBalanceController,
                  hint: '0',
                  icon: Icons.account_balance_wallet_outlined,
                  keyboardType: TextInputType.number,
                  prefix: '₹ ',
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter initial amount';
                    final parsed = double.tryParse(v.trim());
                    if (parsed == null || parsed < 0) return 'Enter a valid amount';
                    return null;
                  },
                ),
              const SizedBox(height: 32),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
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
                if (_selectedType != i) {
                  setState(() => _selectedType = i);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? Colors.black : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _typeIcons[i],
                      size: 16,
                      color: selected ? Colors.white : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _typeLabels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? prefix,
    String? Function(String?)? validator,
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
            fillColor: Colors.white,
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

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submit,
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
            : const Text(
                'Create Account',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
