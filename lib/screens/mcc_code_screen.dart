import 'package:flutter/material.dart';
import '../services/direct_sql_service.dart';

class MCCCodeScreen extends StatefulWidget {
  const MCCCodeScreen({super.key});

  @override
  State<MCCCodeScreen> createState() => _MCCCodeScreenState();
}

class _MCCCodeScreenState extends State<MCCCodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mccCodeController = TextEditingController();
  final _nameController = TextEditingController();
  
  bool _loading = true;
  bool _submitting = false;
  int? _editingId;
  List<Map<String, dynamic>> _mccCodes = [];

  @override
  void initState() {
    super.initState();
    _loadMCCCodes();
  }

  @override
  void dispose() {
    _mccCodeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadMCCCodes() async {
    try {
      final codes = await DirectSqlService.getAllMCCCodes();
      if (mounted) {
        setState(() {
          _mccCodes = codes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading MCC codes: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _submitting = true);
    try {
      final mccCode = int.tryParse(_mccCodeController.text.trim()) ?? 0;
      final name = _nameController.text.trim();

      if (_editingId != null) {
        await DirectSqlService.updateMCCCode(
          id: _editingId!,
          mccCode: mccCode,
          name: name,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('MCC code updated successfully'),
              backgroundColor: Color(0xFF22C55E),
            ),
          );
        }
      } else {
        await DirectSqlService.createMCCCode(
          mccCode: mccCode,
          name: name,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('MCC code added successfully'),
              backgroundColor: Color(0xFF22C55E),
            ),
          );
        }
      }

      if (mounted) {
        _mccCodeController.clear();
        _nameController.clear();
        _editingId = null;
        _loadMCCCodes();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _mccCodeController.clear();
      _nameController.clear();
    });
  }

  Future<void> _deleteMCCCode(int id) async {
    try {
      await DirectSqlService.deleteMCCCode(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('MCC code deleted successfully'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
        _loadMCCCodes();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting MCC code: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCC Codes'),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMCCCodes,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildMCCCodesList(),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showMCCForm(),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }

  void _showMCCForm([Map<String, dynamic>? code]) {
    final isEdit = code != null;
    final id = isEdit ? int.tryParse(code['id']?.toString() ?? '') : null;

    if (isEdit && id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to edit this MCC code. Invalid ID.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    _editingId = id;
    _mccCodeController.text = isEdit ? (code['mcc_code']?.toString() ?? '') : '';
    _nameController.text = isEdit ? (code['name']?.toString() ?? '') : '';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEdit ? 'Edit MCC Code' : 'Add New MCC Code'),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _mccCodeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'MCC Code',
                      hintText: 'e.g., 5411',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'MCC code is required';
                      }
                      final codeValue = int.tryParse(value.trim());
                      if (codeValue == null || codeValue <= 0) {
                        return 'Enter a valid MCC code';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      hintText: 'e.g., Grocery Stores',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Description is required';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _cancelEdit();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _submitting ? null : () async {
              Navigator.pop(dialogContext);
              await _submitForm();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    isEdit ? 'Update' : 'Add',
                    style: const TextStyle(color: Colors.white),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMCCCodesList() {
    if (_mccCodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Text(
            'No MCC codes added yet',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MCC Codes (${_mccCodes.length})',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _mccCodes.length,
          itemBuilder: (context, index) {
            final code = _mccCodes[index];
            return _buildMCCCodeItem(code);
          },
        ),
      ],
    );
  }

  Widget _buildMCCCodeItem(Map<String, dynamic> code) {
    final id = int.tryParse(code['id']?.toString() ?? '') ?? 0;
    final mccCode = int.tryParse(code['mcc_code']?.toString() ?? '') ?? 0;
    final name = code['name']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mccCode.toString(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name.toString(),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Color(0xFF2563EB)),
                onPressed: () {
                  _showMCCForm(code);
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Color(0xFFEF4444)),
                onPressed: () {
                  _showDeleteConfirmation(id, mccCode);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(int id, int mccCode) {
    if (id <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to delete this MCC code. Invalid ID.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete MCC Code'),
        content: Text('Are you sure you want to delete MCC code $mccCode?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMCCCode(id);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
  }
}
