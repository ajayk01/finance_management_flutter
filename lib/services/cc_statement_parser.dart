import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/models.dart';

/// Detected credit card info for DB matching
class DetectedCard {
  final String accountId;
  final String accountName;
  final String cardLabel;

  const DetectedCard(this.accountId, this.accountName, this.cardLabel);

  static const hdfc = DetectedCard('20', 'HDFC Diners Black', 'HDFC Diners');
  static const iciciAmazon = DetectedCard('7', 'Amazon Pay ICICI CC', 'ICICI Amazon Pay');
  static const iciciCoral = DetectedCard('9', 'ICICI Coral CC', 'ICICI Coral');
  static const unknown = DetectedCard('', '', 'Unknown Card');
}

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

    // Debug: print all extracted lines
    debugPrint('[CCParser] ===== EXTRACTED TEXT (${allLines.length} lines) =====');
    for (int i = 0; i < allLines.length; i++) {
      debugPrint('[CCParser] L$i: ${allLines[i]}');
    }
    debugPrint('[CCParser] ===== END EXTRACTED TEXT =====');

    return _parseTransactions(allLines);
  }

  /// Detect which credit card this statement belongs to
  static DetectedCard _detectCard(String fullText) {
    final upper = fullText.toUpperCase();
    if (upper.contains('AMAZON PAY') && upper.contains('ICICI')) {
      return DetectedCard.iciciAmazon;
    }
    if (upper.contains('CORAL') && upper.contains('ICICI')) {
      return DetectedCard.iciciCoral;
    }
    if (upper.contains('ICICI')) {
      return DetectedCard.iciciCoral; // Default ICICI card
    }
    if (upper.contains('DINERS') || upper.contains('HDFC BANK')) {
      return DetectedCard.hdfc;
    }
    return DetectedCard.unknown;
  }

  static CCStatementResult _parseTransactions(List<String> allLines) {
    final transactions = <CCStatementTransaction>[];
    final fullText = allLines.join('\n');

    // ── Detect card type ──
    final detectedCard = _detectCard(fullText);
    debugPrint('[CCParser] Detected card: ${detectedCard.cardLabel}');

    // ── Summary fields ──
    double? totalAmountDue;
    double? minimumDue;
    String? dueDate;
    String? billingPeriod;

    // Total amount due
    final totalDueMatch = RegExp(r'(?:TOTAL\s+AMOUNT\s+DUE|Total\s+Amount\s+[Dd]ue)[^\d]*[₹Rs.\s]*([\d,]+\.?\d*)', caseSensitive: false).firstMatch(fullText);
    if (totalDueMatch != null) totalAmountDue = _parseAmount(totalDueMatch.group(1)!);

    // Minimum due
    final minDueMatch = RegExp(r'(?:MINIMUM\s+AMOUNT\s+DUE|Minimum\s+Amount\s+[Dd]ue|MINIMUM\s+DUE|Minimum\s+Due)[^\d]*[₹Rs.\s]*([\d,]+\.?\d*)', caseSensitive: false).firstMatch(fullText);
    if (minDueMatch != null) minimumDue = _parseAmount(minDueMatch.group(1)!);

    // Due date — handles "June 15, 2026", "17 Jun, 2026", "PAYMENT DUE DATE June 15, 2026"
    final dueDateMatch = RegExp(
      r'(?:DUE\s+DATE|Due\s+Date|PAYMENT\s+DUE\s+DATE)\s*[:\s]*(\w+\s+\d{1,2},?\s+\d{4}|\d{1,2}\s+\w+,?\s+\d{4})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (dueDateMatch != null) dueDate = dueDateMatch.group(1);

    // Billing period — "Billing Period ... DD Mon, YYYY - DD Mon, YYYY"
    // or "Statement period : April 29, 2026 to May 28, 2026"
    final billingMatch = RegExp(
      r'(?:Billing\s+Period|Statement\s+period)\s*[:\s]*(\w+\s+\d{1,2},?\s+\d{4}|\d{1,2}\s+\w+,?\s+\d{4})\s*(?:-|to)\s*(\w+\s+\d{1,2},?\s+\d{4}|\d{1,2}\s+\w+,?\s+\d{4})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (billingMatch != null) {
      billingPeriod = '${billingMatch.group(1)} - ${billingMatch.group(2)}';
    }

    // ── Parse transactions based on card type ──
    if (detectedCard == DetectedCard.iciciAmazon || detectedCard == DetectedCard.iciciCoral) {
      _parseICICITransactions(allLines, transactions);
    } else {
      _parseHDFCTransactions(allLines, transactions);
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
      detectedCard: detectedCard,
    );
  }

  // ── ICICI format (Amazon Pay / Coral / etc.) ──
  // Table: Date | SerNo. | Transaction Details | Reward Points | Intl.* amount | Amount (in₹)
  // Date: DD/MM/YYYY (no time), Amount may have "CR" suffix for credit
  static void _parseICICITransactions(List<String> allLines, List<CCStatementTransaction> transactions) {
    final dateOnly = RegExp(r'^(\d{2}/\d{2}/\d{4})\b');
    final standaloneAmount = RegExp(r'(\d{1,3}(?:,\d{2,3})*\.\d{2})\s*(CR)?', caseSensitive: false);
    // Masked card number line like "4315XXXXXXXX1004"
    final cardNumberLine = RegExp(r'^\d{4}X{4,}');

    for (int i = 0; i < allLines.length; i++) {
      final line = allLines[i].trim();
      if (line.isEmpty) continue;

      // Skip headers and non-transaction lines
      if (cardNumberLine.hasMatch(line)) continue;
      if (line.contains('Date') && (line.contains('SerNo') || line.contains('Transaction')) ||
          line.contains('International Spends') ||
          line.contains('STATEMENT SUMMARY') ||
          line.contains('CREDIT SUMMARY') ||
          line.contains('EARNINGS') ||
          line.contains('SPENDS OVERVIEW') ||
          line.contains('Page ') && line.contains(' of ')) continue;

      final dateMatch = dateOnly.firstMatch(line);
      if (dateMatch == null) continue;

      final date = dateMatch.group(1)!;
      var rest = line.substring(dateMatch.end).trim();

      // Remove serial number (8+ digit number at the start)
      rest = rest.replaceFirst(RegExp(r'^\d{8,}\s*'), '').trim();

      // Find amounts on this line
      var amounts = standaloneAmount.allMatches(rest).toList();
      String desc;
      double amount;
      bool isCredit = false;

      if (amounts.isNotEmpty) {
        // Amount found on same line as date
        final lastAmount = amounts.last;
        amount = _parseAmount(lastAmount.group(1)!);
        isCredit = lastAmount.group(2) != null; // "CR" suffix

        // Description is text before the first amount
        final firstInRest = standaloneAmount.firstMatch(rest);
        if (firstInRest != null) {
          desc = rest.substring(0, firstInRest.start).trim();
        } else {
          desc = rest;
        }
      } else {
        // Amount NOT on this line — look ahead for it
        desc = rest;
        double? foundAmount;
        bool foundCredit = false;

        for (int j = i + 1; j < allLines.length && j <= i + 3; j++) {
          final nextLine = allLines[j].trim();
          if (nextLine.isEmpty) continue;
          if (dateOnly.hasMatch(nextLine)) break; // Hit another date, stop

          final nextAmounts = standaloneAmount.allMatches(nextLine).toList();
          if (nextAmounts.isNotEmpty) {
            final lastAmt = nextAmounts.last;
            foundAmount = _parseAmount(lastAmt.group(1)!);
            foundCredit = lastAmt.group(2) != null;
            // Any text before the amount on this line is part of description
            final firstNext = standaloneAmount.firstMatch(nextLine);
            if (firstNext != null) {
              final extraDesc = nextLine.substring(0, firstNext.start).trim();
              if (extraDesc.isNotEmpty && !RegExp(r'^\d+$').hasMatch(extraDesc)) {
                desc = '$desc $extraDesc'.trim();
              }
            }
            break;
          }
          // This line might be continued description or serial number
          final cleaned = nextLine.replaceFirst(RegExp(r'^\d{8,}\s*'), '').trim();
          if (cleaned.isNotEmpty && !RegExp(r'^\d+$').hasMatch(cleaned)) {
            desc = '$desc $cleaned'.trim();
          }
        }

        if (foundAmount == null) continue; // No amount found, skip
        amount = foundAmount;
        isCredit = foundCredit;
      }

      // Remove reward points (small numbers at end of desc)
      desc = desc.replaceFirst(RegExp(r'\s+\d{1,4}\s*$'), '').trim();
      desc = _cleanDescription(desc);

      if (desc.isEmpty || desc.length < 3) continue;

      transactions.add(CCStatementTransaction(
        date: date,
        time: '',
        description: desc,
        amount: amount,
        isCredit: isCredit,
        isEmi: false,
      ));
    }
  }

  // ── HDFC Diners format ──
  // Table: DD/MM/YYYY| HH:MM | Description | Rewards | Amount
  static void _parseHDFCTransactions(List<String> allLines, List<CCStatementTransaction> transactions) {
    final p1 = RegExp(r'(\d{2}/\d{2}/\d{4})\s*\|?\s*(\d{2}:\d{2})');
    final amountPattern = RegExp(r'[₹`]\s*([\d,]+\.\d{2})');
    final standaloneAmount = RegExp(r'(\d{1,3}(?:,\d{2,3})*\.\d{2})');

    for (int i = 0; i < allLines.length; i++) {
      final line = allLines[i].trim();
      if (line.isEmpty) continue;

      if (line.contains('DATE & TIME') || line.contains('TRANSACTION DESCRIPTION') ||
          line.contains('Domestic Transactions') || line.contains('K AJAY') ||
          line.contains('International Transaction')) continue;

      final dateMatch = p1.firstMatch(line);
      if (dateMatch == null) continue;

      final date = dateMatch.group(1)!;
      final time = dateMatch.group(2)!;
      var rest = line.substring(dateMatch.end).trim();

      var amountMatch = amountPattern.firstMatch(rest);
      String desc;
      double amount;
      bool isCredit = false;
      bool isEmi = false;

      if (amountMatch != null) {
        desc = rest.substring(0, amountMatch.start).trim();
        amount = _parseAmount(amountMatch.group(1)!);
        final beforeAmount = rest.substring(0, amountMatch.start);
        isCredit = beforeAmount.contains('+') && beforeAmount.contains('₹');
      } else {
        final saMatch = standaloneAmount.firstMatch(rest);
        if (saMatch != null) {
          desc = rest.substring(0, saMatch.start).trim();
          amount = _parseAmount(saMatch.group(1)!);
          final beforeAmount = rest.substring(0, saMatch.start);
          isCredit = beforeAmount.trimRight().endsWith('+');
        } else {
          desc = rest;
          double? foundAmount;
          bool foundCredit = false;
          for (int j = i + 1; j < allLines.length && j <= i + 3; j++) {
            final nextLine = allLines[j].trim();
            if (p1.hasMatch(nextLine)) break;
            final nextAmountMatch = amountPattern.firstMatch(nextLine);
            if (nextAmountMatch != null) {
              foundAmount = _parseAmount(nextAmountMatch.group(1)!);
              foundCredit = nextLine.contains('+');
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
            if (nextLine.isNotEmpty && !RegExp(r'^[\d₹\+\-]+$').hasMatch(nextLine)) {
              desc = '$desc $nextLine'.trim();
            }
          }
          if (foundAmount == null) continue;
          amount = foundAmount;
          isCredit = foundCredit;
        }
      }

      isEmi = desc.toUpperCase().contains('EMI');
      desc = _cleanDescription(desc);
      if (desc.isEmpty) continue;

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
  }

  static String _cleanDescription(String desc) {
    desc = desc.replaceAll(RegExp(r'\bEMI\b', caseSensitive: false), '').trim();
    desc = desc.replaceAll('|', '').trim();
    desc = desc.replaceFirst(RegExp(r'[\+\-]\s*\d{1,4}\s*$'), '').trim();
    desc = desc.replaceFirst(RegExp(r'^[\+\-]\s*'), '').trim();
    desc = desc.replaceFirst(RegExp(r'[\+\-]\s*$'), '').trim();
    desc = desc.replaceAll('₹', '').trim();
    desc = desc.replaceAll(RegExp(r'\s{2,}'), ' ');
    return desc;
  }

  static double _parseAmount(String amountStr) {
    final cleaned = amountStr.replaceAll(RegExp(r'[^0-9.,]'), '');
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
  final DetectedCard detectedCard;

  CCStatementResult({
    required this.transactions,
    this.totalAmountDue,
    this.minimumDue,
    this.dueDate,
    this.billingPeriod,
    this.detectedCard = const DetectedCard('', '', 'Unknown'),
  });

  double get totalDebits =>
      transactions.where((t) => !t.isCredit).fold(0, (sum, t) => sum + t.amount);

  double get totalCredits =>
      transactions.where((t) => t.isCredit).fold(0, (sum, t) => sum + t.amount);

  /// Parse billing period start date "DD Mon, YYYY - DD Mon, YYYY" → DateTime
  DateTime? get billingStartDate => _parseBillingDate(0);
  DateTime? get billingEndDate => _parseBillingDate(1);

  DateTime? _parseBillingDate(int index) {
    if (billingPeriod == null) return null;
    final parts = billingPeriod!.split('-');
    if (parts.length < 2) return null;
    return _parseDateStr(parts[index].trim());
  }

  /// Also derive start/end from transaction dates if billing period not found
  DateTime? get effectiveStartDate {
    if (billingStartDate != null) return billingStartDate;
    if (transactions.isEmpty) return null;
    final dates = transactions.map((t) {
      final p = t.date.split('/');
      if (p.length == 3) return DateTime.tryParse('${p[2]}-${p[1]}-${p[0]}');
      return null;
    }).whereType<DateTime>().toList();
    if (dates.isEmpty) return null;
    dates.sort();
    return dates.first;
  }

  DateTime? get effectiveEndDate {
    if (billingEndDate != null) return billingEndDate;
    if (transactions.isEmpty) return null;
    final dates = transactions.map((t) {
      final p = t.date.split('/');
      if (p.length == 3) return DateTime.tryParse('${p[2]}-${p[1]}-${p[0]}');
      return null;
    }).whereType<DateTime>().toList();
    if (dates.isEmpty) return null;
    dates.sort();
    return dates.last;
  }

  static DateTime? _parseDateStr(String s) {
    // Handles: "29 Apr, 2026", "28 May 2026", "April 29, 2026", "May 28, 2026"
    final cleaned = s.replaceAll(',', '').trim();
    final months = {
      'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
      'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6,
      'jul': 7, 'july': 7, 'aug': 8, 'august': 8, 'sep': 9, 'september': 9,
      'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
    };
    // Try "DD Month YYYY"
    var m = RegExp(r'(\d{1,2})\s+(\w+)\s+(\d{4})').firstMatch(cleaned);
    if (m != null) {
      final day = int.tryParse(m.group(1)!) ?? 1;
      final month = months[m.group(2)!.toLowerCase()] ?? 1;
      final year = int.tryParse(m.group(3)!) ?? 2026;
      return DateTime(year, month, day);
    }
    // Try "Month DD YYYY" (e.g. "April 29 2026")
    m = RegExp(r'(\w+)\s+(\d{1,2})\s+(\d{4})').firstMatch(cleaned);
    if (m != null) {
      final month = months[m.group(1)!.toLowerCase()] ?? 1;
      final day = int.tryParse(m.group(2)!) ?? 1;
      final year = int.tryParse(m.group(3)!) ?? 2026;
      return DateTime(year, month, day);
    }
    return null;
  }
}

class _ParseArgs {
  final String pdfPath;
  final String? password;
  _ParseArgs(this.pdfPath, this.password);
}
