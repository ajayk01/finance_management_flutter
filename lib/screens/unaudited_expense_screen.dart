import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_data_cache.dart';
import '../utils/currency_formatter.dart';

class UnauditedExpenseScreen extends StatefulWidget {
  const UnauditedExpenseScreen({super.key});

  @override
  State<UnauditedExpenseScreen> createState() => _UnauditedExpenseScreenState();
}

class _UnauditedExpenseScreenState extends State<UnauditedExpenseScreen> {
  final _api = ApiService();
  final _cache = AppDataCache();

  bool _loading = true;
  bool _submitting = false;
  List<_UnauditedRow> _rows = [];
  List<Category> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      await _cache.ensureCategories();
      final cats = _cache.categories
          .where((c) => c.type == 'expense')
          .toList();
      final data = await _api.getUnauditedExpenses();
      final txns = (data['transactions'] as List? ?? [])
          .map((j) => TransactionModel.fromJson(j as Map<String, dynamic>))
          .toList();

      if (mounted) {
        setState(() {
          _categories = cats;
          _rows = txns
              .map((tx) => _UnauditedRow(
                    tx: tx,
                    selected: true,
                    selectedCategory: null,
                    selectedSubCategory: null,
                    descController:
                        TextEditingController(text: tx.description),
                  ))
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  bool get _allSelected =>
      _rows.isNotEmpty && _rows.every((r) => r.selected);

  int get _selectedCount => _rows.where((r) => r.selected).length;

  void _toggleAll() {
    final newVal = !_allSelected;
    setState(() {
      for (final r in _rows) {
        r.selected = newVal;
      }
    });
  }

  List<SubCategory> _subsFor(Category? cat) {
    if (cat == null) return [];
    return cat.subCategories;
  }

  Future<void> _updateSelected() async {
    final selected = _rows.where((r) => r.selected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No transactions selected'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    // Validate all selected have category
    final missing = selected.where((r) => r.selectedCategory == null).toList();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${missing.length} transaction(s) missing category'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final updates = selected.map((r) {
        return {
          'id': r.tx.id,
          'categoryId': r.selectedCategory!.id,
          'subCategoryId': r.selectedSubCategory?.id ?? '',
          'description': r.descController.text.trim(),
        };
      }).toList();

      await _api.updateUnauditedExpenses(updates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${updates.length} transaction(s) updated'),
            backgroundColor: const Color(0xFF22C55E),
          ),
        );
        // Remove updated rows
        setState(() {
          _rows.removeWhere((r) => r.selected && r.selectedCategory != null);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _deleteSelected() async {
    final selected = _rows.where((r) => r.selected).toList();
    if (selected.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transactions'),
        content:
            Text('Delete ${selected.length} selected transaction(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitting = true);
    try {
      final ids = selected.map((r) => r.tx.id).toList();
      await _api.deleteUnauditedExpenses(ids);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${ids.length} transaction(s) deleted'),
            backgroundColor: const Color(0xFF22C55E),
          ),
        );
        setState(() {
          _rows.removeWhere((r) => r.selected);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.descController.dispose();
    }
    super.dispose();
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
          'Unaudited Expense',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? _buildEmpty()
              : Stack(
                  children: [
                    Column(
                      children: [
                        _buildToolbar(),
                        Expanded(child: _buildList()),
                      ],
                    ),
                    if (_submitting)
                      Container(
                        color: Colors.black26,
                        child: const Center(
                            child: CircularProgressIndicator()),
                      ),
                  ],
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'All expenses are audited!',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Expense transactions with no mapped category.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Selected: $_selectedCount / ${_rows.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _updateSelected,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Update',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _rows.length + 1, // +1 for header
      itemBuilder: (context, i) {
        if (i == 0) return _buildHeader();
        return _buildRowCard(_rows[i - 1]);
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggleAll,
            child: Icon(
              _allSelected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          const SizedBox(
              width: 50,
              child: Text('ID',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          const SizedBox(
              width: 80,
              child: Text('Date',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          const SizedBox(
              width: 70,
              child: Text('Amount',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          const Expanded(
              child: Text('Account',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildRowCard(_UnauditedRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100),
        ),
      ),
      child: Column(
        children: [
          // Top row: checkbox, ID, date, amount, account
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => row.selected = !row.selected),
                child: Icon(
                  row.selected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 20,
                  color: row.selected
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 50,
                child: Text(
                  row.tx.id,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500),
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  row.tx.date,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF1E293B)),
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  formatINR(row.tx.amount, decimals: 0),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  row.tx.accountName ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF1E293B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Bottom row: category, subcategory, description dropdowns
          Row(
            children: [
              const SizedBox(width: 28), // align with content
              Expanded(
                flex: 3,
                child: _buildCategoryDropdown(row),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _buildSubCategoryDropdown(row),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _buildDescField(row),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryDropdown(_UnauditedRow row) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Category>(
          value: row.selectedCategory,
          isExpanded: true,
          isDense: true,
          hint: Text('Category',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
          icon: Icon(Icons.keyboard_arrow_down,
              size: 16, color: Colors.grey.shade400),
          items: _categories
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  ))
              .toList(),
          onChanged: (val) {
            setState(() {
              row.selectedCategory = val;
              row.selectedSubCategory = null;
            });
          },
        ),
      ),
    );
  }

  Widget _buildSubCategoryDropdown(_UnauditedRow row) {
    final subs = _subsFor(row.selectedCategory);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SubCategory>(
          value: row.selectedSubCategory,
          isExpanded: true,
          isDense: true,
          hint: Text('Subcategory',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
          icon: Icon(Icons.keyboard_arrow_down,
              size: 16, color: Colors.grey.shade400),
          items: subs
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  ))
              .toList(),
          onChanged: subs.isEmpty
              ? null
              : (val) => setState(() => row.selectedSubCategory = val),
        ),
      ),
    );
  }

  Widget _buildDescField(_UnauditedRow row) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: row.descController,
        style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
        decoration: InputDecoration(
          hintText: 'Description',
          hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _UnauditedRow {
  final TransactionModel tx;
  bool selected;
  Category? selectedCategory;
  SubCategory? selectedSubCategory;
  final TextEditingController descController;

  _UnauditedRow({
    required this.tx,
    required this.selected,
    required this.selectedCategory,
    required this.selectedSubCategory,
    required this.descController,
  });
}
