import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/bank_statement_parser.dart';
import '../utils/currency_formatter.dart';
import 'add_transaction_screen.dart';

class BankStatementScreen extends StatefulWidget {
  final String? localPdfPath;

  const BankStatementScreen.fromFile({
    super.key,
    required String this.localPdfPath,
  });

  @override
  State<BankStatementScreen> createState() => _BankStatementScreenState();
}

class _BankStatementScreenState extends State<BankStatementScreen> with SingleTickerProviderStateMixin {
  bool _loading = false;
  String? _error;
  String? _pdfPath;
  bool _needsPassword = false;
  String? _pdfPassword;

  late TabController _tabController;
  BankStatementResult? _parsedResult;
  bool _parsing = false;
  String? _parseError;

  List<MergedBankTransaction>? _mergedTransactions;
  bool _fetchingDb = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pdfPath = widget.localPdfPath;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
            const Text('This PDF is password protected. Please enter the password.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'PDF Password',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text('Open')),
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
      _mergedTransactions = null;
    });
    try {
      final result = await BankStatementParser.parse(_pdfPath!, password: _pdfPassword);
      if (mounted) {
        setState(() {
          _parsedResult = result;
          _parsing = false;
        });
        if (result.transactions.isNotEmpty) {
          _tabController.animateTo(1);
          _fetchAndMergeDbTransactions(result);
        }
      }
    } catch (e) {
      debugPrint('[BankStatement] Parse error: $e');
      if (mounted) {
        setState(() {
          _parseError = e.toString();
          _parsing = false;
        });
      }
    }
  }

  Future<void> _fetchAndMergeDbTransactions(BankStatementResult result) async {
    setState(() => _fetchingDb = true);
    try {
      final startDate = result.effectiveStartDate;
      final endDate = result.effectiveEndDate;

      if (startDate == null || endDate == null) {
        // Determine from transactions
        DateTime? earliest;
        DateTime? latest;
        for (final t in result.transactions) {
          final parts = t.date.split('/');
          if (parts.length == 3) {
            final d = DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}');
            if (d != null) {
              if (earliest == null || d.isBefore(earliest)) earliest = d;
              if (latest == null || d.isAfter(latest)) latest = d;
            }
          }
        }
        if (earliest == null || latest == null) {
          setState(() {
            _mergedTransactions = result.transactions
                .map((t) => MergedBankTransaction(statementTxn: t))
                .toList();
            _fetchingDb = false;
          });
          return;
        }
        await _mergeWithDb(result, earliest, latest);
        return;
      }

      await _mergeWithDb(result, startDate, endDate);
    } catch (e) {
      debugPrint('[BankStatement] DB fetch error: $e');
      if (mounted) {
        setState(() {
          _mergedTransactions = result.transactions
              .map((t) => MergedBankTransaction(statementTxn: t))
              .toList();
          _fetchingDb = false;
        });
      }
    }
  }

  Future<void> _mergeWithDb(BankStatementResult result, DateTime startDate, DateTime endDate) async {
    final api = ApiService();
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final months = <String>{};
    var cursor = DateTime(startDate.year, startDate.month);
    final endMonth = DateTime(endDate.year, endDate.month);
    while (!cursor.isAfter(endMonth)) {
      months.add('${monthNames[cursor.month]}-${cursor.year}');
      cursor = DateTime(cursor.year, cursor.month + 1);
    }

    final allDbTxns = <TransactionModel>[];
    final futures = months.map((my) {
      final parts = my.split('-');
      return api.getAllTransactions(month: parts[0], year: parts[1]);
    }).toList();

    final results = await Future.wait(futures);
    for (final data in results) {
      final txList = (data['transactions'] as List? ?? [])
          .map((j) => TransactionModel.fromJson(j))
          .toList();
      allDbTxns.addAll(txList);
    }

    debugPrint('[BankStatement] Fetched ${allDbTxns.length} DB transactions');

    // Filter to matching bank account
    final bank = result.detectedBank;
    final bankAccountId = bank.accountId;
    final bankDbTxns = bankAccountId.isNotEmpty
        ? allDbTxns.where((t) => t.accountId == bankAccountId).toList()
        : allDbTxns;
    debugPrint('[BankStatement] Bank: ${bank.bankLabel} (accountId=$bankAccountId)');
    debugPrint('[BankStatement] Filtered to ${bankDbTxns.length} bank account transactions');

    // Match by date + amount
    final usedDbIds = <String>{};
    final merged = <MergedBankTransaction>[];

    for (final stmtTxn in result.transactions) {
      final stmtDate = stmtTxn.normalizedDate;
      TransactionModel? match;
      for (final dbTxn in bankDbTxns) {
        if (usedDbIds.contains(dbTxn.id)) continue;
        final dbDate = dbTxn.date.split(' ').first.split('T').first;
        if (dbDate == stmtDate && (dbTxn.amount - stmtTxn.amount).abs() < 0.01) {
          match = dbTxn;
          usedDbIds.add(dbTxn.id);
          break;
        }
      }
      merged.add(MergedBankTransaction(statementTxn: stmtTxn, dbTxn: match));
    }

    if (mounted) {
      setState(() {
        _mergedTransactions = merged;
        _fetchingDb = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bank Statement'),
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
                  physics: const NeverScrollableScrollPhysics(),
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
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
    if (_parsing || _fetchingDb) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_parsing ? 'Parsing statement...' : 'Fetching DB transactions...'),
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
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text('Parse Error:\n$_parseError', textAlign: TextAlign.center),
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

    if (_parsedResult == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.touch_app, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Tap the button below to parse the statement'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _parseStatement,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Parse Statement'),
            ),
          ],
        ),
      );
    }

    final result = _parsedResult!;
    final cs = Theme.of(context).colorScheme;
    final txns = _mergedTransactions ?? [];
    final totalCount = txns.length;
    final matchedCount = txns.where((t) => t.isMatched).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCard(result, totalCount, matchedCount, cs),
        const SizedBox(height: 16),
        _buildTableHeader(cs),
        ...txns.asMap().entries.map((e) => _buildMergedRow(e.value, e.key, cs)),
      ],
    );
  }

  Widget _buildSummaryCard(BankStatementResult result, int totalCount, int matchedCount, ColorScheme cs) {
    return Container(
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
                '$totalCount Transactions',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onPrimaryContainer),
              ),
              if (result.detectedBank.bankLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    result.detectedBank.bankLabel,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _summaryItem('Matched', '$matchedCount / $totalCount', Colors.green, cs),
              _summaryItem('Unmatched', '${totalCount - matchedCount}', Colors.orange, cs),
            ],
          ),
          if (result.statementPeriod != null) ...[
            const SizedBox(height: 8),
            Text(
              result.statementPeriod!,
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
            child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: valueColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurface))),
          Expanded(flex: 3, child: Text('Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurface))),
          SizedBox(width: 72, child: Text('DB Amt', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurface))),
          SizedBox(width: 72, child: Text('Stmt Amt', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurface))),
        ],
      ),
    );
  }

  Widget _buildMergedRow(MergedBankTransaction txn, int index, ColorScheme cs) {
    final hasCategory = txn.category != null && txn.category!.isNotEmpty;

    final Color bgColor;
    if (txn.isMatched && hasCategory) {
      bgColor = Colors.green.withValues(alpha: 0.05);
    } else {
      bgColor = Colors.orange.withValues(alpha: 0.06);
    }

    final bool isTappable = !txn.isMatched || (txn.isMatched && !hasCategory);

    return GestureDetector(
      onTap: isTappable ? () => _onTransactionTap(txn) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: index.isEven ? bgColor : bgColor.withValues(alpha: 0.02),
          border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 70,
              child: Text(txn.date, style: TextStyle(fontSize: 11, color: cs.onSurface)),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          txn.description,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (txn.isMatched)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
                        ),
                    ],
                  ),
                  if (txn.isMatched && hasCategory)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [txn.category, txn.subCategory].whereType<String>().where((s) => s.isNotEmpty).join(' › '),
                        style: TextStyle(fontSize: 10, color: cs.primary),
                      ),
                    ),
                  if (txn.isMatched && !hasCategory)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        txn.statementTxn.description,
                        style: TextStyle(fontSize: 10, color: Colors.orange.shade700, fontStyle: FontStyle.italic),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (!txn.isMatched)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Not in DB',
                        style: TextStyle(fontSize: 9, color: Colors.orange.shade700, fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                txn.dbAmount != null ? formatINR(txn.dbAmount!) : '-',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: txn.dbAmount != null ? cs.onSurface : cs.outline),
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                '${txn.isCredit ? '+' : ''}${formatINR(txn.statementAmount)}',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: txn.isCredit ? Colors.green : cs.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onTransactionTap(MergedBankTransaction txn) async {
    if (!txn.isMatched) {
      final bank = _parsedResult?.detectedBank;
      final prefill = TransactionModel(
        id: '',
        date: txn.statementTxn.normalizedDate,
        description: txn.statementTxn.description,
        amount: txn.statementAmount,
        type: txn.isCredit ? 'income' : 'expense',
        accountName: bank?.accountName ?? '',
        accountId: bank?.accountId ?? '',
      );
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AddTransactionScreen(prefill: prefill)),
      );
    } else {
      // In DB but missing category → edit with locked fields
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddTransactionScreen(
            prefill: txn.dbTxn,
            isEdit: true,
            lockFields: const {'account', 'amount'},
          ),
        ),
      );
    }
    if (_parsedResult != null && mounted) {
      _fetchAndMergeDbTransactions(_parsedResult!);
    }
  }
}
