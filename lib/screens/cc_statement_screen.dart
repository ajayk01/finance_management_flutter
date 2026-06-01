import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/cc_statement_parser.dart';
import '../services/zoho_mail_service.dart';
import '../utils/currency_formatter.dart';
import 'add_transaction_screen.dart';

class CCStatementScreen extends StatefulWidget {
  final String? userId;
  final String? folderId;
  final String? messageId;
  final String? localPdfPath;

  const CCStatementScreen({
    super.key,
    this.userId,
    this.folderId,
    this.messageId,
    this.localPdfPath,
  });

  /// Constructor for Zoho mail fetched PDFs
  const CCStatementScreen.fromMail({
    super.key,
    required String this.userId,
    required String this.folderId,
    required String this.messageId,
  }) : localPdfPath = null;

  /// Constructor for locally uploaded PDFs
  const CCStatementScreen.fromFile({
    super.key,
    required String this.localPdfPath,
  })  : userId = null,
        folderId = null,
        messageId = null;

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

  // Merged transactions
  List<MergedCCTransaction>? _mergedTransactions;
  bool _fetchingDb = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.localPdfPath != null) {
      _pdfPath = widget.localPdfPath;
      _loading = false;
    } else {
      _fetchStatement();
    }
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
          userId: widget.userId!,
          folderId: widget.folderId!,
          messageId: widget.messageId!,
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
            userId: widget.userId!,
            folderId: widget.folderId!,
            messageId: widget.messageId!,
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
      _mergedTransactions = null;
    });
    try {
      final result = await CCStatementParser.parse(_pdfPath!, password: _pdfPassword);
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
      debugPrint('[CCParser] Error: $e');
      if (mounted) {
        setState(() {
          _parseError = e.toString();
          _parsing = false;
        });
      }
    }
  }

  /// Fetch DB transactions for the billing period months, then match with statement.
  Future<void> _fetchAndMergeDbTransactions(CCStatementResult result) async {
    setState(() => _fetchingDb = true);
    try {
      final api = ApiService();
      final startDate = result.effectiveStartDate;
      final endDate = result.effectiveEndDate;

      if (startDate == null || endDate == null) {
        // Can't determine billing period; show statement-only data
        setState(() {
          _mergedTransactions = result.transactions
              .map((t) => MergedCCTransaction(statementTxn: t))
              .toList();
          _fetchingDb = false;
        });
        return;
      }

      debugPrint('[CCStatement] Billing period: $startDate - $endDate');

      // Collect all month/year combos in the billing range
      final monthNames = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final months = <String>{};
      var cursor = DateTime(startDate.year, startDate.month);
      final endMonth = DateTime(endDate.year, endDate.month);
      while (!cursor.isAfter(endMonth)) {
        months.add('${monthNames[cursor.month]}-${cursor.year}');
        cursor = DateTime(cursor.year, cursor.month + 1);
      }

      // Fetch all DB transactions for those months in parallel
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

      debugPrint('[CCStatement] Fetched ${allDbTxns.length} DB transactions');

      // Filter to only transactions from the matching CC account
      final card = result.detectedCard;
      final ccAccountId = card.accountId;
      final ccDbTxns = ccAccountId.isNotEmpty
          ? allDbTxns.where((t) => t.accountId == ccAccountId).toList()
          : allDbTxns;
      debugPrint('[CCStatement] Card: ${card.cardLabel} (accountId=$ccAccountId)');
      debugPrint('[CCStatement] Filtered to ${ccDbTxns.length} CC account transactions');

      // Debug: print sample DB dates to verify format
      for (final dbTxn in ccDbTxns.take(5)) {
        debugPrint('[CCStatement] DB txn: date="${dbTxn.date}" amount=${dbTxn.amount} desc="${dbTxn.description}"');
      }
      // Debug: print statement dates
      for (final stmtTxn in result.transactions.take(5)) {
        debugPrint('[CCStatement] Stmt txn: date="${stmtTxn.date}" normalized="${stmtTxn.normalizedDate}" amount=${stmtTxn.amount}');
      }

      // Build merged list: match by date + amount
      final usedDbIds = <String>{};
      final merged = <MergedCCTransaction>[];

      for (final stmtTxn in result.transactions) {
        final stmtDate = stmtTxn.normalizedDate; // YYYY-MM-DD

        // Find matching DB transaction: same date + same amount
        TransactionModel? match;
        for (final dbTxn in ccDbTxns) {
          if (usedDbIds.contains(dbTxn.id)) continue;
          // Compare dates: normalize DB date too (strip time, handle different formats)
          final dbDate = dbTxn.date.split(' ').first.split('T').first;
          if (dbDate == stmtDate && (dbTxn.amount - stmtTxn.amount).abs() < 0.01) {
            match = dbTxn;
            usedDbIds.add(dbTxn.id);
            break;
          }
        }

        merged.add(MergedCCTransaction(
          statementTxn: stmtTxn,
          dbTxn: match,
        ));
      }

      if (mounted) {
        setState(() {
          _mergedTransactions = merged;
          _fetchingDb = false;
        });
      }
    } catch (e) {
      debugPrint('[CCStatement] DB fetch error: $e');
      if (mounted) {
        // Fall back to statement-only
        setState(() {
          _mergedTransactions = result.transactions
              .map((t) => MergedCCTransaction(statementTxn: t))
              .toList();
          _fetchingDb = false;
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

    final merged = _mergedTransactions ?? [];
    final cs = Theme.of(context).colorScheme;
    final matchedCount = merged.where((m) => m.isMatched).length;

    return Column(
      children: [
        _buildSummaryCard(result, cs, matchedCount, merged.length),
        // Transaction table
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            itemCount: merged.length + 1, // +1 for header
            itemBuilder: (context, index) {
              if (index == 0) return _buildTableHeader(cs);
              final txn = merged[index - 1];
              return _buildMergedRow(txn, index, cs);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(CCStatementResult result, ColorScheme cs, int matchedCount, int totalCount) {
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
                '$totalCount Transactions',
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
          const SizedBox(height: 8),
          Row(
            children: [
              _summaryItem('Total Due',
                  result.totalAmountDue != null ? formatINR(result.totalAmountDue!) : '-',
                  cs.error, cs),
              _summaryItem('Min Due',
                  result.minimumDue != null ? formatINR(result.minimumDue!) : '-',
                  cs.tertiary, cs),
              _summaryItem('Matched', '$matchedCount / $totalCount',
                  Colors.green, cs),
              _summaryItem('Unmatched', '${totalCount - matchedCount}',
                  Colors.orange, cs),
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

  Widget _buildTableHeader(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurface)),
          ),
          Expanded(
            flex: 3,
            child: Text('Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurface)),
          ),
          SizedBox(
            width: 72,
            child: Text('DB Amt', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurface)),
          ),
          SizedBox(
            width: 72,
            child: Text('Stmt Amt', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurface)),
          ),
        ],
      ),
    );
  }

  Widget _buildMergedRow(MergedCCTransaction txn, int index, ColorScheme cs) {
    final isCCPayment = txn.isCredit; // Credit transactions = CC payments, skip highlighting
    final hasCategory = txn.category != null && txn.category!.isNotEmpty;

    // Background color logic:
    // - CC payment (credit): neutral, no highlight
    // - Matched with category: green
    // - Matched without category: orange highlight (needs attention)
    // - Not matched (not CC payment): orange highlight
    final Color bgColor;
    if (isCCPayment) {
      bgColor = cs.surface;
    } else if (txn.isMatched && hasCategory) {
      bgColor = Colors.green.withValues(alpha: 0.05);
    } else {
      bgColor = Colors.orange.withValues(alpha: 0.06);
    }

    // Tappable if:
    // 1. Not in DB and not a CC payment → tap to add expense
    // 2. In DB but missing category/subcategory → tap to edit
    final bool isTappable = (!txn.isMatched && !isCCPayment) ||
        (txn.isMatched && !hasCategory);

    return GestureDetector(
      onTap: isTappable ? () => _onTransactionTap(txn) : null,
      child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: index.isEven ? bgColor : bgColor.withValues(alpha: 0.02),
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date
              SizedBox(
                width: 70,
                child: Text(
                  txn.date,
                  style: TextStyle(fontSize: 11, color: cs.onSurface),
                ),
              ),
              // Description + category
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
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (txn.isEmi)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text('EMI', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.orange)),
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
                    if (!txn.isMatched && !isCCPayment)
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
              // DB Amount
              SizedBox(
                width: 72,
                child: Text(
                  txn.dbAmount != null ? formatINR(txn.dbAmount!) : '-',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: txn.dbAmount != null ? cs.onSurface : cs.outline,
                  ),
                ),
              ),
              // Statement Amount
              SizedBox(
                width: 72,
                child: Text(
                  '${txn.isCredit ? '+' : ''}${formatINR(txn.statementAmount)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: txn.isCredit ? Colors.green : cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  void _onTransactionTap(MergedCCTransaction txn) async {
    if (!txn.isMatched) {
      // Not in DB → open Add Expense with prefilled date, account, amount, description
      final card = _parsedResult?.detectedCard;
      final prefill = TransactionModel(
        id: '',
        date: txn.statementTxn.normalizedDate,
        description: txn.statementTxn.description,
        amount: txn.statementAmount,
        type: 'expense',
        accountName: card?.accountName ?? '',
        accountId: card?.accountId ?? '',
      );
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddTransactionScreen(prefill: prefill),
        ),
      );
    } else {
      // In DB but missing category → open Edit with account & amount locked
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
    // After returning, re-fetch DB transactions and re-merge
    if (_parsedResult != null && mounted) {
      _fetchAndMergeDbTransactions(_parsedResult!);
    }
  }
}
