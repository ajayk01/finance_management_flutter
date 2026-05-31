import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../models/models.dart';
import '../services/cc_statement_parser.dart';
import '../services/zoho_mail_service.dart';
import '../utils/currency_formatter.dart';

class CCStatementScreen extends StatefulWidget {
  final String userId;
  final String folderId;
  final String messageId;

  const CCStatementScreen({
    super.key,
    required this.userId,
    required this.folderId,
    required this.messageId,
  });

  @override
  State<CCStatementScreen> createState() => _CCStatementScreenState();
}

class _CCStatementScreenState extends State<CCStatementScreen> with SingleTickerProviderStateMixin {
  final _zoho = ZohoMailService();
  bool _loading = true;
  String? _error;
  String? _pdfPath;
  bool _needsPassword = false;
  String? _pdfPassword;

  // Transactions tab
  late TabController _tabController;
  CCStatementResult? _parsedResult;
  bool _parsing = false;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchStatement();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchStatement() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _zoho.loadTokens();

      // If no refresh token, trigger OAuth flow
      if (!_zoho.isAuthenticated) {
        if (!mounted) return;
        final success = await _zoho.authenticate(context);
        if (!success) {
          setState(() {
            _error = 'Zoho authorization required';
            _loading = false;
          });
          return;
        }
      }

      try {
        final path = await _zoho.fetchPdfAttachment(
          userId: widget.userId,
          folderId: widget.folderId,
          messageId: widget.messageId,
        );
        setState(() {
          _pdfPath = path;
          _loading = false;
        });
      } on ZohoException catch (e) {
        // If refresh token was invalid, clear and re-authenticate
        if (e.message.contains('Refresh token invalid') ||
            e.message.contains('Failed to obtain access token')) {
          debugPrint('[CCStatement] Re-authenticating due to: ${e.message}');
          if (!mounted) return;
          final success = await _zoho.authenticate(context);
          if (!success) {
            setState(() {
              _error = 'Zoho authorization required';
              _loading = false;
            });
            return;
          }
          // Retry after re-authentication
          final path = await _zoho.fetchPdfAttachment(
            userId: widget.userId,
            folderId: widget.folderId,
            messageId: widget.messageId,
          );
          setState(() {
            _pdfPath = path;
            _loading = false;
          });
        } else {
          rethrow;
        }
      }
    } on ZohoException catch (e) {
      debugPrint('[CCStatement] ZohoException: $e');
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('[CCStatement] Error: $e');
      debugPrint('[CCStatement] Stack: $st');
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onPdfError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('password') || errorStr.contains('encrypted')) {
      setState(() => _needsPassword = true);
      _promptPassword();
    }
  }

  Future<void> _promptPassword() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Password Required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This PDF is password protected. Please enter the password to open it.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'PDF Password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Open'),
          ),
        ],
      ),
    );

    if (password != null && password.isNotEmpty) {
      setState(() {
        _pdfPassword = password;
        _needsPassword = false;
      });
      _parseStatement();
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _parseStatement() async {
    if (_pdfPath == null) return;
    setState(() {
      _parsing = true;
      _parseError = null;
    });
    try {
      final result = await CCStatementParser.parse(_pdfPath!, password: _pdfPassword);
      if (mounted) {
        setState(() {
          _parsedResult = result;
          _parsing = false;
        });
        // Auto-switch to transactions tab if transactions found
        if (result.transactions.isNotEmpty) {
          _tabController.animateTo(1);
        }
      }
    } catch (e) {
      debugPrint('[CCParser] Error: $e');
      if (mounted) {
        setState(() {
          _parseError = e.toString();
          _parsing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CC Statement'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.picture_as_pdf), text: 'PDF'),
            Tab(icon: Icon(Icons.receipt_long), text: 'Transactions'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _needsPassword
                        ? const Center(child: CircularProgressIndicator())
                        : _buildPdfView(),
                    _buildTransactionsView(),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _fetchStatement,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfView() {
    if (_pdfPath == null || !File(_pdfPath!).existsSync()) {
      return const Center(child: Text('PDF file not found'));
    }

    return PDFView(
      key: ValueKey('$_pdfPath-$_pdfPassword'),
      filePath: _pdfPath!,
      password: _pdfPassword,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: true,
      pageFling: false,
      onError: (error) {
        debugPrint('[PDF] Error: $error');
        _onPdfError(error);
      },
      onPageError: (page, error) {
        debugPrint('[PDF] Page $page error: $error');
        _onPdfError(error);
      },
    );
  }

  Widget _buildTransactionsView() {
    if (_parsing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Parsing statement...'),
          ],
        ),
      );
    }

    if (_parseError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(
                'Failed to parse transactions:\n$_parseError',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _parseStatement,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final result = _parsedResult;
    if (result == null || result.transactions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No transactions found', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final txns = result.transactions;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Summary card
        _buildSummaryCard(result, cs),
        // Transaction list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: txns.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final txn = txns[index];
              return _buildTransactionTile(txn, index + 1, cs);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(CCStatementResult result, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${result.transactions.length} Transactions',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: cs.onPrimaryContainer,
                ),
              ),
              if (result.dueDate != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Due: ${result.dueDate}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.error,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _summaryItem('Total Due',
                  result.totalAmountDue != null ? formatINR(result.totalAmountDue!) : '-',
                  cs.error, cs),
              _summaryItem('Min Due',
                  result.minimumDue != null ? formatINR(result.minimumDue!) : '-',
                  cs.tertiary, cs),
              _summaryItem('Debits', formatINR(result.totalDebits),
                  cs.onPrimaryContainer, cs),
              _summaryItem('Credits', formatINR(result.totalCredits),
                  Colors.green, cs),
            ],
          ),
          if (result.billingPeriod != null) ...[
            const SizedBox(height: 8),
            Text(
              result.billingPeriod!,
              style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer.withValues(alpha: 0.7)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color valueColor, ColorScheme cs) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: cs.onPrimaryContainer.withValues(alpha: 0.7))),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(CCStatementTransaction txn, int index, ColorScheme cs) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: txn.isCredit
            ? Colors.green.withValues(alpha: 0.15)
            : cs.primaryContainer,
        child: Text(
          '$index',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: txn.isCredit ? Colors.green : cs.onPrimaryContainer,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              txn.description,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (txn.isEmi)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('EMI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
            ),
        ],
      ),
      subtitle: Text(
        '${txn.date}  ${txn.time}',
        style: TextStyle(fontSize: 12, color: cs.outline),
      ),
      trailing: Text(
        '${txn.isCredit ? '+' : ''}${formatINR(txn.amount)}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: txn.isCredit ? Colors.green : cs.onSurface,
        ),
      ),
    );
  }
}
