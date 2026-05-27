import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_data_cache.dart';

class AddSubCategorySheet extends StatefulWidget {
  const AddSubCategorySheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddSubCategorySheet(),
    );
  }

  @override
  State<AddSubCategorySheet> createState() => _AddSubCategorySheetState();
}

class _AddSubCategorySheetState extends State<AddSubCategorySheet> {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();
  final _cache = AppDataCache();

  final _nameController = TextEditingController();
  final _budgetController = TextEditingController(text: '0');

  String _typeFilter = 'All Categories';
  Category? _selectedCategory;
  bool _loading = true;
  bool _submitting = false;

  List<Category> _allCategories = [];

  static const _typeFilters = ['All Categories', 'Expense', 'Income'];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    await _cache.ensureCategories();
    if (mounted) {
      setState(() {
        _allCategories = _cache.categories;
        _loading = false;
      });
    }
  }

  List<Category> get _filteredCategories {
    if (_typeFilter == 'All Categories') return _allCategories;
    return _allCategories
        .where((c) => c.type.toLowerCase() == _typeFilter.toLowerCase())
        .toList();
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
      final budget = double.tryParse(_budgetController.text.trim()) ?? 0;
      await _api.createSubcategory(
        categoryId: int.parse(_selectedCategory!.id),
        subCategoryName: _nameController.text.trim(),
        budget: budget,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sub-category created successfully'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create sub-category: $e'),
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
                'Create a new sub-category under an existing category.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),
              _buildLabel('Filter by Type'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _typeFilter,
                isExpanded: true,
                decoration: _inputDecoration(hint: ''),
                validator: (v) => v == null ? 'Select a type filter' : null,
                items: _typeFilters
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t,
                              style: const TextStyle(
                                  fontSize: 15, color: Color(0xFF1E293B))),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _typeFilter = v ?? 'All Categories';
                    // Reset selected category if it's no longer in the filtered list
                    if (_selectedCategory != null &&
                        !_filteredCategories.contains(_selectedCategory)) {
                      _selectedCategory = null;
                    }
                  });
                },
                icon: Icon(Icons.keyboard_arrow_down,
                    color: Colors.grey.shade500),
              ),
              const SizedBox(height: 16),
              _buildLabel('Parent Category'),
              const SizedBox(height: 6),
              DropdownButtonFormField<Category>(
                value: _selectedCategory,
                isExpanded: true,
                decoration: _inputDecoration(hint: ''),
                hint: Text('Select a category',
                    style: TextStyle(color: Colors.grey.shade400)),
                validator: (v) => v == null ? 'Select a parent category' : null,
                items: _loading
                    ? []
                    : _filteredCategories
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.name,
                                  style: const TextStyle(
                                      fontSize: 15, color: Color(0xFF1E293B))),
                            ))
                        .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
                icon: Icon(Icons.keyboard_arrow_down,
                    color: Colors.grey.shade500),
              ),
              const SizedBox(height: 16),
              _buildLabel('Sub-Category Name'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter sub-category name'
                    : null,
                decoration: _inputDecoration(
                    hint: 'e.g., Groceries, Petrol, Bonus'),
              ),
              const SizedBox(height: 16),
              _buildLabel('Budget (Optional)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _budgetController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(hint: '0'),
                validator: (v) {
                  if (v != null && v.trim().isNotEmpty) {
                    final parsed = double.tryParse(v.trim());
                    if (parsed == null || parsed < 0) return 'Enter a valid budget';
                  }
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
          'Add Sub-Category',
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
                  'Add Sub-Category',
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
