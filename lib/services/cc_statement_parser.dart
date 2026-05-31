import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/models.dart';

class CCStatementParser {
  /// Extract transactions from a credit card statement PDF file.
  /// Supports password-protected PDFs.
  static Future<CCStatementResult> parse(String pdfPath, {String? password}) async {
    return compute(_parseInIsolate, _ParseArgs(pdfPath, password));
  }

  static CCStatementResult _parseInIsolate(_ParseArgs args) {
    final bytes = File(args.pdfPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes, password: args.password ?? '');

    final pageCount = doc.pages.count;
    final allLines = <String>[];

    for (int i = 0; i < pageCount; i++) {
      // Extract text with layout to preserve table structure
      final extractor = PdfTextExtractor(doc);
      final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
      allLines.addAll(text.split('\n'));

      // Also try extracting individual text lines for better structure
      final textLines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
      for (final tl in textLines) {
        final lineText = tl.text.trim();
        if (lineText.isNotEmpty && !allLines.contains(lineText)) {
          allLines.add(lineText);
        }
      }
    }
    doc.dispose();

    // Debug: print all extracted lines
    debugPrint('[CCParser] ===== EXTRACTED TEXT (${allLines.length} lines) =====');
    for (int i = 0; i < allLines.length; i++) {
      debugPrint('[CCParser] L$i: ${allLines[i]}');
    }
    debugPrint('[CCParser] ===== END EXTRACTED TEXT =====');

    return _parseTransactions(allLines);
  }

  static CCStatementResult _parseTransactions(List<String> allLines) {
    final transactions = <CCStatementTransaction>[];

    // Summary fields
    double? totalAmountDue;
    double? minimumDue;
    String? dueDate;
    String? billingPeriod;

    // Collect all text for summary extraction
    final fullText = allLines.join('\n');

    // ── Extract summary info ──
    // Total amount due
    final totalDueMatch = RegExp(r'(?:TOTAL\s+AMOUNT\s+DUE|Total\s+Amount\s+Due)[^\d]*[₹Rs.\s]*([\d,]+\.?\d*)', caseSensitive: false).firstMatch(fullText);
    if (totalDueMatch != null) totalAmountDue = _parseAmount(totalDueMatch.group(1)!);

    // Minimum due
    final minDueMatch = RegExp(r'(?:MINIMUM\s+DUE|Minimum\s+Due)[^\d]*[₹Rs.\s]*([\d,]+\.?\d*)', caseSensitive: false).firstMatch(fullText);
    if (minDueMatch != null) minimumDue = _parseAmount(minDueMatch.group(1)!);

    // Due date
    final dueDateMatch = RegExp(r'(?:DUE\s+DATE|Due\s+Date)[^\d]*(\d{1,2}\s+\w+,?\s+\d{4})', caseSensitive: false).firstMatch(fullText);
    if (dueDateMatch != null) dueDate = dueDateMatch.group(1);

    // Billing period
    final billingMatch = RegExp(r'(?:Billing\s+Period)[^\d]*(\d{1,2}\s+\w+,?\s+\d{4}\s*-\s*\d{1,2}\s+\w+,?\s+\d{4})', caseSensitive: false).firstMatch(fullText);
    if (billingMatch != null) billingPeriod = billingMatch.group(1);

    // ── Extract transactions ──
    // Multiple regex strategies to handle different Syncfusion extraction formats

    // Pattern 1: "DD/MM/YYYY| HH:MM" or "DD/MM/YYYY HH:MM" followed by description and amount
    final p1 = RegExp(
      r'(\d{2}/\d{2}/\d{4})\s*\|?\s*(\d{2}:\d{2})',
    );

    // Amount pattern: ₹ or Rs followed by digits with commas
    final amountPattern = RegExp(r'[₹`]\s*([\d,]+\.\d{2})');
    // Standalone amount: just digits with comma formatting and .XX
    final standaloneAmount = RegExp(r'(\d{1,3}(?:,\d{2,3})*\.\d{2})');

    for (int i = 0; i < allLines.length; i++) {
      final line = allLines[i].trim();
      if (line.isEmpty) continue;

      // Skip header lines
      if (line.contains('DATE & TIME') || line.contains('TRANSACTION DESCRIPTION') ||
          line.contains('Domestic Transactions') || line.contains('K AJAY') ||
          line.contains('International Transaction')) continue;

      final dateMatch = p1.firstMatch(line);
      if (dateMatch == null) continue;

      final date = dateMatch.group(1)!;
      final time = dateMatch.group(2)!;

      // Get everything after the date/time
      var rest = line.substring(dateMatch.end).trim();

      // Check if the amount is on this line
      var amountMatch = amountPattern.firstMatch(rest);
      String desc;
      double amount;
      bool isCredit = false;
      bool isEmi = false;

      if (amountMatch != null) {
        // Amount found on same line
        desc = rest.substring(0, amountMatch.start).trim();
        amount = _parseAmount(amountMatch.group(1)!);
        // Check for credit indicator before amount
        final beforeAmount = rest.substring(0, amountMatch.start);
        isCredit = beforeAmount.contains('+') && beforeAmount.contains('₹');
      } else {
        // Try standalone amount pattern
        final saMatch = standaloneAmount.firstMatch(rest);
        if (saMatch != null) {
          desc = rest.substring(0, saMatch.start).trim();
          amount = _parseAmount(saMatch.group(1)!);
          final beforeAmount = rest.substring(0, saMatch.start);
          isCredit = beforeAmount.trimRight().endsWith('+');
        } else {
          // Amount might be on the next line or description spans the whole line
          desc = rest;
          // Look ahead for amount in next lines
          double? foundAmount;
          bool foundCredit = false;
          for (int j = i + 1; j < allLines.length && j <= i + 3; j++) {
            final nextLine = allLines[j].trim();
            if (p1.hasMatch(nextLine)) break; // Hit another date, stop
            
            final nextAmountMatch = amountPattern.firstMatch(nextLine);
            if (nextAmountMatch != null) {
              foundAmount = _parseAmount(nextAmountMatch.group(1)!);
              foundCredit = nextLine.contains('+');
              // Prepend any description from this line
              final extraDesc = nextLine.substring(0, nextAmountMatch.start).trim();
              if (extraDesc.isNotEmpty && !RegExp(r'^[\+\-\d\s]+$').hasMatch(extraDesc)) {
                desc = '$desc $extraDesc'.trim();
              }
              break;
            }
            final nextSaMatch = standaloneAmount.firstMatch(nextLine);
            if (nextSaMatch != null) {
              foundAmount = _parseAmount(nextSaMatch.group(1)!);
              foundCredit = nextLine.trimRight().endsWith('+') || nextLine.contains('+ ');
              final extraDesc = nextLine.substring(0, nextSaMatch.start).trim();
              if (extraDesc.isNotEmpty && !RegExp(r'^[\+\-\d\s]+$').hasMatch(extraDesc)) {
                desc = '$desc $extraDesc'.trim();
              }
              break;
            }
            // This line might be continued description
            if (nextLine.isNotEmpty && !RegExp(r'^[\d₹\+\-]+$').hasMatch(nextLine)) {
              desc = '$desc $nextLine'.trim();
            }
          }
          if (foundAmount == null) continue; // Skip if no amount found
          amount = foundAmount;
          isCredit = foundCredit;
        }
      }

      // Clean description
      isEmi = desc.toUpperCase().contains('EMI');
      desc = _cleanDescription(desc);

      if (desc.isEmpty) continue;

      // Check for credit: "+₹" or "+ ₹" pattern in the original line
      if (!isCredit) {
        isCredit = line.contains('+ ₹') || line.contains('+₹');
      }

      transactions.add(CCStatementTransaction(
        date: date,
        time: time,
        description: desc,
        amount: amount,
        isCredit: isCredit,
        isEmi: isEmi,
      ));
    }

    debugPrint('[CCParser] Found ${transactions.length} transactions');
    for (final t in transactions) {
      debugPrint('[CCParser] ${t.date} ${t.time} | ${t.description} | ${t.isCredit ? "+" : "-"}${t.amount} | EMI=${t.isEmi}');
    }

    return CCStatementResult(
      transactions: transactions,
      totalAmountDue: totalAmountDue,
      minimumDue: minimumDue,
      dueDate: dueDate,
      billingPeriod: billingPeriod,
    );
  }

  static String _cleanDescription(String desc) {
    // Remove EMI tag
    desc = desc.replaceAll(RegExp(r'\bEMI\b', caseSensitive: false), '').trim();
    // Remove pipe chars
    desc = desc.replaceAll('|', '').trim();
    // Remove reward points like "+ 44", "+ 100" at the end
    desc = desc.replaceFirst(RegExp(r'[\+\-]\s*\d{1,4}\s*$'), '').trim();
    // Remove leading/trailing + or -
    desc = desc.replaceFirst(RegExp(r'^[\+\-]\s*'), '').trim();
    desc = desc.replaceFirst(RegExp(r'[\+\-]\s*$'), '').trim();
    // Remove stray ₹ symbols
    desc = desc.replaceAll('₹', '').trim();
    // Collapse multiple spaces
    desc = desc.replaceAll(RegExp(r'\s{2,}'), ' ');
    return desc;
  }

  static double _parseAmount(String amountStr) {
    // Remove everything except digits, commas, and dots
    final cleaned = amountStr.replaceAll(RegExp(r'[^0-9.,]'), '');
    // Remove commas for parsing
    final forParse = cleaned.replaceAll(',', '');
    return double.tryParse(forParse) ?? 0;
  }
}

class CCStatementResult {
  final List<CCStatementTransaction> transactions;
  final double? totalAmountDue;
  final double? minimumDue;
  final String? dueDate;
  final String? billingPeriod;

  CCStatementResult({
    required this.transactions,
    this.totalAmountDue,
    this.minimumDue,
    this.dueDate,
    this.billingPeriod,
  });

  double get totalDebits =>
      transactions.where((t) => !t.isCredit).fold(0, (sum, t) => sum + t.amount);

  double get totalCredits =>
      transactions.where((t) => t.isCredit).fold(0, (sum, t) => sum + t.amount);
}

class _ParseArgs {
  final String pdfPath;
  final String? password;
  _ParseArgs(this.pdfPath, this.password);
}
