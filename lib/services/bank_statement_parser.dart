import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/models.dart';

/// Detected bank info for DB matching
class DetectedBank {
  final String accountId;
  final String accountName;
  final String bankLabel;

  const DetectedBank(this.accountId, this.accountName, this.bankLabel);

  static const icici = DetectedBank('1', 'ICICI Bank', 'ICICI');
  static const hdfc = DetectedBank('3', 'HDFC Bank', 'HDFC');
  static const sbi = DetectedBank('', 'SBI', 'SBI');
  static const unknown = DetectedBank('', '', 'Unknown Bank');
}

class BankStatementParser {
  static Future<BankStatementResult> parse(String pdfPath, {String? password}) async {
    return compute(_parseInIsolate, _ParseArgs(pdfPath, password));
  }

  static BankStatementResult _parseInIsolate(_ParseArgs args) {
    final bytes = File(args.pdfPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes, password: args.password ?? '');

    final pageCount = doc.pages.count;
    final allLines = <String>[];

    for (int i = 0; i < pageCount; i++) {
      final extractor = PdfTextExtractor(doc);
      final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
      allLines.addAll(text.split('\n'));

      final textLines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
      for (final tl in textLines) {
        final lineText = tl.text.trim();
        if (lineText.isNotEmpty && !allLines.contains(lineText)) {
          allLines.add(lineText);
        }
      }
    }
    doc.dispose();

    debugPrint('[BankParser] ===== EXTRACTED TEXT (${allLines.length} lines) =====');
    for (int i = 0; i < allLines.length; i++) {
      debugPrint('[BankParser] L$i: ${allLines[i]}');
    }
    debugPrint('[BankParser] ===== END EXTRACTED TEXT =====');

    return _parseStatement(allLines);
  }

  static DetectedBank _detectBank(String fullText) {
    final upper = fullText.toUpperCase();
    if (upper.contains('HDFC BANK')) return DetectedBank.hdfc;
    if (upper.contains('ICICI BANK')) return DetectedBank.icici;
    if (upper.contains('STATE BANK') || upper.contains('SBI')) return DetectedBank.sbi;
    return DetectedBank.unknown;
  }

  static BankStatementResult _parseStatement(List<String> allLines) {
    final fullText = allLines.join('\n');
    final detectedBank = _detectBank(fullText);
    debugPrint('[BankParser] Detected bank: ${detectedBank.bankLabel}');

    // ── Statement period: "From : DD/MM/YYYY To : DD/MM/YYYY" ──
    String? statementPeriod;
    final periodMatch = RegExp(
      r'From\s*:\s*(\d{1,2}/\d{1,2}/\d{2,4})\s+To\s*:\s*(\d{1,2}/\d{1,2}/\d{2,4})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (periodMatch != null) {
      statementPeriod = '${_normalizeDate(periodMatch.group(1)!)} - ${_normalizeDate(periodMatch.group(2)!)}';
    }

    // ── Account number ──
    String? accountNumber;
    final accMatch = RegExp(
      r'Account\s*No\s*:\s*(\d[\d\s]+\d)',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (accMatch != null) accountNumber = accMatch.group(1)?.trim();

    // ── Opening balance from STATEMENT SUMMARY ──
    double? openingBalance;
    final amountPattern = RegExp(r'(\d{1,3}(?:,\d{2,3})*\.\d{2})');
    for (int i = 0; i < allLines.length; i++) {
      if (allLines[i].contains('STATEMENT SUMMARY')) {
        // Look for the opening balance value in nearby lines
        for (int j = i + 1; j < allLines.length && j <= i + 5; j++) {
          final amts = amountPattern.allMatches(allLines[j]).toList();
          if (amts.isNotEmpty) {
            openingBalance = _parseAmount(amts.first.group(1)!);
            debugPrint('[BankParser] Opening balance: $openingBalance');
            break;
          }
        }
        break;
      }
    }

    // ── Parse transactions using block-based approach ──
    final transactions = <BankStatementTransaction>[];
    if (detectedBank == DetectedBank.hdfc) {
      _parseHDFCTransactions(allLines, transactions, openingBalance);
    } else {
      _parseGenericTransactions(allLines, transactions);
    }

    debugPrint('[BankParser] Found ${transactions.length} transactions');
    for (final t in transactions) {
      debugPrint('[BankParser] ${t.date} | ${t.description} | ${t.isCredit ? "CR" : "DR"} ${t.amount} | Bal: ${t.balance}');
    }

    return BankStatementResult(
      transactions: transactions,
      detectedBank: detectedBank,
      statementPeriod: statementPeriod,
      accountNumber: accountNumber,
    );
  }

  // ── HDFC Bank Statement ──
  // Columns: Date | Narration | Chq./Ref.No. | Value Dt | Withdrawal Amt. | Deposit Amt. | Closing Balance
  // Date: DD/MM/YY, multi-line narrations, amounts at end of block
  static void _parseHDFCTransactions(
    List<String> allLines,
    List<BankStatementTransaction> transactions,
    double? openingBalance,
  ) {
    final dateStart = RegExp(r'^(\d{2}/\d{2}/\d{2,4})\s');
    final amountPattern = RegExp(r'(\d{1,3}(?:,\d{2,3})*\.\d{2})');
    final refPattern = RegExp(r'\b\d{16}\b');

    // Skip patterns for page headers/footers
    bool isSkipLine(String line) {
      if (line.startsWith('Page No')) return true;
      if (line.contains('HDFC BANK')) return true;
      if (line.contains('Statement of account')) return true;
      if (line.contains('STATEMENT SUMMARY')) return true;
      if (line.contains('Opening Balance') && line.contains('Dr Count')) return true;
      if (line.contains('Generated On')) return true;
      if (line.contains('computer generated')) return true;
      if (line.contains('Closing balance includes')) return true;
      if (line.contains('Contents of this statement')) return true;
      if (line.contains('GSTN') || line.contains('GSTIN')) return true;
      if (line.contains('Registered Office')) return true;
      if (line.contains('From :') && line.contains('To :')) return true;
      if (RegExp(r'^(Date|Narration|Chq|Value Dt|Withdrawal|Deposit|Closing Balance)')
          .hasMatch(line)) return true;
      if (line.contains('Narration') && line.contains('Chq')) return true;
      // Account info lines
      if (RegExp(r'^(Account\s|A/C Open|RTGS|Branch Code|OD Limit|Currency|Cust ID|Phone|Email|City|State|Address|Nomination|JOINT|MR\.|TAMIL|ERODE|SINN|CHENN|AMMAN)',
          caseSensitive: false).hasMatch(line)) return true;
      return false;
    }

    // Group lines into transaction blocks
    final blocks = <_TxnBlock>[];
    bool pastSummary = false;

    for (int i = 0; i < allLines.length; i++) {
      final line = allLines[i].trim();
      if (line.isEmpty) continue;
      if (line.contains('STATEMENT SUMMARY')) {
        pastSummary = true;
        continue;
      }
      if (pastSummary) continue; // Skip everything after summary
      if (isSkipLine(line)) continue;

      final dateMatch = dateStart.firstMatch(line);
      if (dateMatch != null) {
        blocks.add(_TxnBlock(dateMatch.group(1)!, [line.substring(dateMatch.end).trim()]));
      } else if (blocks.isNotEmpty) {
        blocks.last.lines.add(line);
      }
    }

    debugPrint('[BankParser] Found ${blocks.length} transaction blocks');

    // Parse each block
    double? prevClosing = openingBalance;

    for (final block in blocks) {
      final fullText = block.lines.join(' ');

      // Find all amounts in the full block text
      final amounts = amountPattern.allMatches(fullText).toList();
      if (amounts.length < 2) continue; // Need at least txn amount + closing balance

      // Last amount is always the closing balance
      final closingBalance = _parseAmount(amounts.last.group(1)!);
      // Second-to-last is the transaction amount
      final txnAmount = _parseAmount(amounts[amounts.length - 2].group(1)!);

      if (txnAmount <= 0) continue;

      // Determine credit/debit by comparing closing balances
      bool isCredit;
      if (prevClosing != null) {
        isCredit = closingBalance > prevClosing;
      } else {
        // Heuristic: if narration contains salary/deposit keywords, it's credit
        final upper = fullText.toUpperCase();
        isCredit = upper.contains('SALARY') || upper.contains('ACH C-') ||
            upper.contains('DEPOSIT') || upper.contains('TPT-CC RETURN') ||
            upper.contains('TPT-BRO');
      }
      prevClosing = closingBalance;

      // Build description: take narration text, remove ref numbers/amounts/value dates
      var desc = fullText;
      // Remove 16-digit ref numbers
      desc = desc.replaceAll(refPattern, '').trim();
      // Remove value dates (DD/MM/YY or DD/MM/YYYY embedded in text)
      desc = desc.replaceAll(RegExp(r'\b\d{2}/\d{2}/\d{2,4}\b'), '').trim();
      // Remove all amount values
      for (final amt in amounts) {
        desc = desc.replaceFirst(amt.group(0)!, '').trim();
      }
      // Clean up
      desc = desc.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
      desc = desc.replaceAll(RegExp(r'^[-\s]+'), '').trim();
      desc = desc.replaceAll(RegExp(r'[-\s]+$'), '').trim();

      if (desc.isEmpty || desc.length < 3) continue;

      final date = _normalizeDate(block.date);

      transactions.add(BankStatementTransaction(
        date: date,
        description: desc,
        amount: txnAmount,
        isCredit: isCredit,
        balance: closingBalance,
      ));
    }
  }

  // ── Generic bank statement parser (fallback) ──
  static void _parseGenericTransactions(
    List<String> allLines,
    List<BankStatementTransaction> transactions,
  ) {
    final datePattern = RegExp(r'^(\d{2}[/\-]\d{2}[/\-]\d{2,4})');
    final amountPattern = RegExp(r'(\d{1,3}(?:,\d{2,3})*\.\d{2})');

    for (int i = 0; i < allLines.length; i++) {
      final line = allLines[i].trim();
      if (line.isEmpty) continue;

      if (line.contains('Date') && (line.contains('Debit') || line.contains('Credit') || line.contains('Withdrawal')) ||
          line.contains('Opening Balance') || line.contains('Closing Balance') ||
          line.contains('Page ') && line.contains(' of ')) continue;

      final dateMatch = datePattern.firstMatch(line);
      if (dateMatch == null) continue;

      final date = _normalizeDate(dateMatch.group(1)!);
      var rest = line.substring(dateMatch.end).trim();
      final amounts = amountPattern.allMatches(rest).toList();

      if (amounts.isEmpty) continue;

      String desc;
      double amount;
      bool isCredit = false;
      double? balance;

      final firstAmt = amounts.first;
      desc = rest.substring(0, firstAmt.start).trim();

      if (amounts.length >= 3) {
        final debitAmt = _parseAmount(amounts[0].group(1)!);
        final creditAmt = _parseAmount(amounts[1].group(1)!);
        balance = _parseAmount(amounts[2].group(1)!);
        if (creditAmt > 0 && debitAmt == 0) {
          amount = creditAmt;
          isCredit = true;
        } else {
          amount = debitAmt > 0 ? debitAmt : creditAmt;
          isCredit = debitAmt == 0;
        }
      } else if (amounts.length == 2) {
        amount = _parseAmount(amounts[0].group(1)!);
        balance = _parseAmount(amounts[1].group(1)!);
        isCredit = rest.toUpperCase().contains('CR');
      } else {
        amount = _parseAmount(amounts[0].group(1)!);
        isCredit = rest.toUpperCase().contains('CR');
      }

      desc = desc.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
      if (desc.isEmpty || desc.length < 3 || amount <= 0) continue;

      transactions.add(BankStatementTransaction(
        date: date,
        description: desc,
        amount: amount,
        isCredit: isCredit,
        balance: balance,
      ));
    }
  }

  static String _normalizeDate(String raw) {
    final parts = raw.split(RegExp(r'[/\-]'));
    if (parts.length != 3) return raw;
    final day = parts[0].padLeft(2, '0');
    final month = parts[1].padLeft(2, '0');
    var year = parts[2];
    if (year.length == 2) {
      final y = int.tryParse(year) ?? 0;
      year = y > 50 ? '19$year' : '20$year';
    }
    return '$day/$month/$year';
  }

  static double _parseAmount(String amountStr) {
    final cleaned = amountStr.replaceAll(RegExp(r'[^0-9.,]'), '');
    final forParse = cleaned.replaceAll(',', '');
    return double.tryParse(forParse) ?? 0;
  }
}

/// Helper to hold transaction block data during parsing
class _TxnBlock {
  final String date;
  final List<String> lines;
  _TxnBlock(this.date, this.lines);
}

class BankStatementResult {
  final List<BankStatementTransaction> transactions;
  final DetectedBank detectedBank;
  final String? statementPeriod;
  final String? accountNumber;

  BankStatementResult({
    required this.transactions,
    required this.detectedBank,
    this.statementPeriod,
    this.accountNumber,
  });

  DateTime? get effectiveStartDate {
    if (statementPeriod == null) return null;
    final parts = statementPeriod!.split(' - ');
    if (parts.isEmpty) return null;
    return _parseDateStr(parts[0].trim());
  }

  DateTime? get effectiveEndDate {
    if (statementPeriod == null) return null;
    final parts = statementPeriod!.split(' - ');
    if (parts.length < 2) return null;
    return _parseDateStr(parts[1].trim());
  }

  static DateTime? _parseDateStr(String s) {
    final parts = s.split(RegExp(r'[/\-]'));
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]) ?? 1;
    final month = int.tryParse(parts[1]) ?? 1;
    var year = int.tryParse(parts[2]) ?? 2026;
    if (year < 100) year = year > 50 ? 1900 + year : 2000 + year;
    return DateTime(year, month, day);
  }
}

class _ParseArgs {
  final String pdfPath;
  final String? password;
  _ParseArgs(this.pdfPath, this.password);
}
