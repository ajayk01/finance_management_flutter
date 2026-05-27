import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_data_cache.dart';

class AddCreditCapSheet extends StatefulWidget {
  const AddCreditCapSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddCreditCapSheet(),
    );
  }

  @override
  State<AddCreditCapSheet> createState() => _AddCreditCapSheetState();
}

class _AddCreditCapSheetState extends State<AddCreditCapSheet> {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();
  final _cache = AppDataCache();

  final _capNameController = TextEditingController();
  final _totalAmountController = TextEditingController(text: '0.00');
  final _percentageController = TextEditingController(text: '0');
  final _rewardPerAmountController = TextEditingController(text: '100');

  CreditCardAccount? _selectedCard;
  bool _loading = true;
  bool _submitting = false;

  List<CreditCardAccount> _creditCards = [];

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  @override
  void dispose() {
    _capNameController.dispose();
    _totalAmountController.dispose();
    _percentageController.dispose();
    _rewardPerAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    await _cache.ensureAccounts();
    if (mounted) {
      setState(() {
        _creditCards = _cache.activeCreditCardAccounts;
        _loading = false;
      });
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
      final totalAmount =
          double.tryParse(_totalAmountController.text.trim()) ?? 0;
      final percentage =
          double.tryParse(_percentageController.text.trim()) ?? 0;
      final rewardPer =
          double.tryParse(_rewardPerAmountController.text.trim()) ?? 100;

      await _api.createCreditCardCap(
        creditCardId: _selectedCard!.id,
        capName: _capNameController.text.trim(),
        capTotalAmount: totalAmount,
        capPercentage: percentage,
        rewardPerAmount: rewardPer,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Credit cap created successfully'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create credit cap: $e'),
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
                'Create a new reward cap for a credit card.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),
              _buildLabel('Credit Card'),
              const SizedBox(height: 6),
              DropdownButtonFormField<CreditCardAccount>(
                value: _selectedCard,
                isExpanded: true,
                decoration: _inputDecoration(hint: ''),
                hint: Text('Select a card',
                    style: TextStyle(color: Colors.grey.shade400)),
                validator: (v) => v == null ? 'Select a credit card' : null,
                items: _loading
                    ? []
                    : _creditCards
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.name,
                                  style: const TextStyle(
                                      fontSize: 15, color: Color(0xFF1E293B))),
                            ))
                        .toList(),
                onChanged: (v) => setState(() => _selectedCard = v),
                icon: Icon(Icons.keyboard_arrow_down,
                    color: Colors.grey.shade500),
              ),
              const SizedBox(height: 16),
              _buildLabel('Cap Name'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _capNameController,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter cap name'
                    : null,
                decoration:
                    _inputDecoration(hint: 'e.g., Fuel, Grocery, Travel'),
              ),
              const SizedBox(height: 16),
              _buildLabel('Total Cap Amount'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _totalAmountController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(hint: '0.00'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter total cap amount';
                  final parsed = double.tryParse(v.trim());
                  if (parsed == null || parsed < 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildLabel('Cap Percentage (%)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _percentageController,
                keyboardType: TextInputType.number,
                decoration: _inputDecorationWithStepper(
                  hint: '0',
                  controller: _percentageController,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter cap percentage';
                  final parsed = double.tryParse(v.trim());
                  if (parsed == null || parsed < 0 || parsed > 100) return 'Enter a valid percentage (0-100)';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildLabel('Reward Per Amount'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _rewardPerAmountController,
                keyboardType: TextInputType.number,
                decoration: _inputDecorationWithStepper(
                  hint: '100',
                  controller: _rewardPerAmountController,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter reward per amount';
                  final parsed = double.tryParse(v.trim());
                  if (parsed == null || parsed <= 0) return 'Enter a valid amount';
                  return null;
                },
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
          'Add Credit Cap',
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

  InputDecoration _inputDecorationWithStepper({
    required String hint,
    required TextEditingController controller,
  }) {
    return _inputDecoration(hint: hint).copyWith(
      suffixIcon: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: () {
              final current = double.tryParse(controller.text) ?? 0;
              controller.text = (current + 1).toStringAsFixed(0);
            },
            child: Icon(Icons.keyboard_arrow_up,
                size: 20, color: Colors.grey.shade500),
          ),
          InkWell(
            onTap: () {
              final current = double.tryParse(controller.text) ?? 0;
              if (current > 0) {
                controller.text = (current - 1).toStringAsFixed(0);
              }
            },
            child: Icon(Icons.keyboard_arrow_down,
                size: 20, color: Colors.grey.shade500),
          ),
        ],
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
                  'Add Cap',
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
