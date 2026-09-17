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
        _mccCodeController.clear();
        _nameController.clear();
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
                  _buildAddForm(),
                  const SizedBox(height: 30),
                  _buildMCCCodesList(),
                ],
              ),
            ),
    );
  }

  Widget _buildAddForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add New MCC Code',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
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
                final code = int.tryParse(value.trim());
                if (code == null || code <= 0) {
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: const Color(0xFF2563EB),
                  disabledBackgroundColor: Colors.grey[300],
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Add MCC Code',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
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
    final id = code['id'];
    final mccCode = code['mcc_code'];
    final name = code['name'];

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
          IconButton(
            icon: const Icon(Icons.delete, color: Color(0xFFEF4444)),
            onPressed: () {
              _showDeleteConfirmation(id, mccCode);
            },
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(int id, int mccCode) {
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
