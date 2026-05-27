import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_data_cache.dart';

class PayCcBillSheet extends StatefulWidget {
  const PayCcBillSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PayCcBillSheet(),
    );
  }

  @override
  State<PayCcBillSheet> createState() => _PayCcBillSheetState();
}

class _PayCcBillSheetState extends State<PayCcBillSheet> {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();
  final _cache = AppDataCache();

  final _amountController = TextEditingController();
  final _descController = TextEditingController();

  CreditCardAccount? _selectedCard;
  BankAccount? _selectedBank;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  bool _loading = true;
  bool _submitting = false;

  List<CreditCardAccount> _creditCards = [];
  List<BankAccount> _bankAccounts = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    await _cache.ensureAccounts();
    if (mounted) {
      setState(() {
        _creditCards = _cache.activeCreditCardAccounts;
        _bankAccounts = _cache.activeBankAccounts;
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && mounted) {
      setState(() => _selectedTime = picked);
    }
  }

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
      final amount = double.tryParse(_amountController.text.trim()) ?? 0;
      final dt = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      final dateEpoch = dt.millisecondsSinceEpoch;
      final desc = _descController.text.trim();

      await _api.payCcBill(
        creditCardId: _selectedCard!.id,
        bankAccountId: _selectedBank!.id,
        amount: amount,
        date: dateEpoch,
        description: desc.isNotEmpty ? desc : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CC bill paid successfully'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pay CC bill: $e'),
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 4),
              Text(
                'Transfer money from your bank account to pay off credit card bill.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),
              _buildLabel('Credit Card'),
              const SizedBox(height: 6),
              _buildDropdown<CreditCardAccount>(
                value: _selectedCard,
                hint: 'Select credit card',
                items: _creditCards,
                itemLabel: (c) => c.name,
                onChanged: (v) => setState(() => _selectedCard = v),
              ),
              const SizedBox(height: 16),
              _buildLabel('Amount'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter amount';
                  final parsed = double.tryParse(v.trim());
                  if (parsed == null || parsed <= 0) return 'Enter a valid amount';
                  return null;
                },
                decoration: _inputDecoration(hint: 'Enter amount'),
              ),
              const SizedBox(height: 16),
              _buildLabel('Bank Account'),
              const SizedBox(height: 6),
              _buildDropdown<BankAccount>(
                value: _selectedBank,
                hint: 'Select bank account',
                items: _bankAccounts,
                itemLabel: (b) => b.name,
                onChanged: (v) => setState(() => _selectedBank = v),
              ),
              const SizedBox(height: 16),
              _buildLabel('Date'),
              const SizedBox(height: 6),
              _buildPickerBox(
                text: DateFormat('MMM dd, yyyy').format(_selectedDate),
                icon: Icons.calendar_today_outlined,
                onTap: _pickDate,
              ),
              const SizedBox(height: 16),
              _buildLabel('Time'),
              const SizedBox(height: 6),
              _buildPickerBox(
                text: _selectedTime.format(context),
                icon: Icons.access_time_outlined,
                onTap: _pickTime,
              ),
              const SizedBox(height: 16),
              _buildLabel('Description (Optional)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descController,
                decoration: _inputDecoration(hint: 'Payment description'),
              ),
              const SizedBox(height: 24),
              _buildButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Text(
          'Pay Credit Card Bill',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Icon(Icons.close, color: Colors.grey.shade500, size: 22),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF374151),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T? value,
    required String hint,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: _inputDecoration(hint: ''),
      hint: Text(hint, style: TextStyle(color: Colors.grey.shade400)),
      validator: (v) => v == null ? 'This field is required' : null,
      items: _loading
          ? []
          : items
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(
                      itemLabel(item),
                      style: const TextStyle(
                          fontSize: 15, color: Color(0xFF1E293B)),
                    ),
                  ))
              .toList(),
      onChanged: onChanged,
      icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade500),
    );
  }

  Widget _buildPickerBox({
    required String text,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            Icon(icon, size: 18, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        const Spacer(),
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            disabledBackgroundColor: Colors.grey.shade300,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                  'Pay Bill',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
        ),
      ],
    );
  }
}
