// Helper to safely parse numbers that may come as strings
double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

// ─── Bank Account ────────────────────────────────────────────
class BankAccount {
  final String id;
  final String name;
  final double balance;
  final double initialBalance;
  final bool isActive;
  final String? logo;

  BankAccount({
    required this.id,
    required this.name,
    required this.balance,
    this.initialBalance = 0,
    this.isActive = true,
    this.logo,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) => BankAccount(
        id: json['id'].toString(),
        name: json['name'] ?? '',
        balance: _toDouble(json['balance'] ?? json['currentBalance']),
        initialBalance: _toDouble(json['initialBalance']),
        isActive: json['isActive'] ?? true,
        logo: json['logo'],
      );
}

// ─── Credit Card Account ─────────────────────────────────────
class CreditCardAccount {
  final String id;
  final String name;
  final double usedAmount;
  final double totalLimit;
  final double availableCredit;
  final double rewardPoints;
  final bool isActive;
  final String? logo;

  CreditCardAccount({
    required this.id,
    required this.name,
    required this.usedAmount,
    required this.totalLimit,
    this.availableCredit = 0,
    this.rewardPoints = 0,
    this.isActive = true,
    this.logo,
  });

  factory CreditCardAccount.fromJson(Map<String, dynamic> json) =>
      CreditCardAccount(
        id: json['id'].toString(),
        name: json['name'] ?? '',
        usedAmount: _toDouble(json['usedAmount']),
        totalLimit: _toDouble(json['totalLimit']),
        availableCredit: _toDouble(json['availableCredit']),
        rewardPoints: _toDouble(json['rewardPoints']),
        isActive: json['isActive'] ?? true,
        logo: json['logo'],
      );
}

// ─── Investment Account ──────────────────────────────────────
class InvestmentAccount {
  final String id;
  final String name;
  final double totalInvested;
  final double totalWithdraw;
  final double currentValue;
  final double xirr;
  final bool isActive;

  InvestmentAccount({
    required this.id,
    required this.name,
    this.totalInvested = 0,
    this.totalWithdraw = 0,
    this.currentValue = 0,
    this.xirr = 0,
    this.isActive = true,
  });

  factory InvestmentAccount.fromJson(Map<String, dynamic> json) =>
      InvestmentAccount(
        id: json['id'].toString(),
        name: json['name'] ?? '',
        totalInvested: _toDouble(json['totalInvested']),
        totalWithdraw: _toDouble(json['totalWithdraw']),
        currentValue: _toDouble(json['currentValue']),
        xirr: _toDouble(json['xirr']),
        isActive: json['isActive'] ?? true,
      );
}

// ─── Transaction ─────────────────────────────────────────────
class TransactionModel {
  final String id;
  final String date;
  final String? time;
  final String description;
  final double amount;
  final String type;
  final String? category;
  final String? subCategory;
  final String? accountId;
  final String? accountName;
  final String? categoryId;
  final String? subCategoryId;
  final String? investmentAccountId;
  final String? investmentAccountName;
  final List<dynamic>? splitwiseDetails;
  final String? splitwiseGroupId;
  final List<dynamic>? splitwiseUserIds;
  final bool includeSplitwise;
  final String? splitType;

  TransactionModel({
    required this.id,
    required this.date,
    this.time,
    required this.description,
    required this.amount,
    required this.type,
    this.category,
    this.subCategory,
    this.accountId,
    this.accountName,
    this.categoryId,
    this.subCategoryId,
    this.investmentAccountId,
    this.investmentAccountName,
    this.splitwiseDetails,
    this.splitwiseGroupId,
    this.splitwiseUserIds,
    this.includeSplitwise = false,
    this.splitType,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    String date = (json['date'] ?? '').toString();
    String? time = json['time']?.toString();

    final normalized = _normalizeDateAndTime(date, time);
    date = normalized.date;
    time = normalized.time;

    return TransactionModel(
        id: json['id'].toString(),
        date: date,
        time: time,
        description: json['description'] ?? '',
        amount: _toDouble(json['amount']),
        type: json['type'] ?? '',
        category: json['category'],
        subCategory: json['subCategory'],
        accountId: json['accountId']?.toString(),
        accountName: json['accountName'],
        categoryId: json['categoryId']?.toString(),
        subCategoryId: json['subCategoryId']?.toString(),
        investmentAccountId: json['investmentAccountId']?.toString(),
        investmentAccountName: json['investmentAccountName'],
        splitwiseDetails: json['splitwiseDetails'] is List ? json['splitwiseDetails'] : null,
        splitwiseGroupId: json['splitwiseGroupId']?.toString(),
        splitwiseUserIds: json['splitwiseUserIds'] is List ? json['splitwiseUserIds'] : null,
        includeSplitwise: json['includeSplitwise'] == true,
        splitType: json['splitType']?.toString(),
      );
  }

  static ({String date, String? time}) _normalizeDateAndTime(
    String date,
    String? time,
  ) {
    // Accept epoch timestamps from backend (seconds or milliseconds).
    final epochDate = int.tryParse(date);
    if (epochDate != null) {
      final dt = _epochToLocalDateTime(epochDate);
      return (date: _formatDate(dt), time: _formatTime(dt));
    }

    // If date already contains full date-time, parse and normalize to local.
    if (date.contains('T') || date.contains(' ')) {
      final parsed = DateTime.tryParse(date);
      if (parsed != null) {
        final local = parsed.toLocal();
        return (date: _formatDate(local), time: _formatTime(local));
      }

      // Fallback for non-ISO forms like "yyyy-MM-dd HH:mm:ss".
      if (time == null && date.contains(' ')) {
        final parts = date.split(' ');
        date = parts.first;
        time = parts.sublist(1).join(' ');
      }
    }

    if (time == null || time.trim().isEmpty) {
      return (date: date, time: null);
    }

    final normalizedTime = _normalizeTimeWithDate(date, time);
    if (normalizedTime != null) {
      return (date: normalizedTime.date, time: normalizedTime.time);
    }

    // Keep human-entered plain times ("HH:mm", "hh:mm a") as-is.
    return (date: date, time: time.trim());
  }

  static DateTime _epochToLocalDateTime(int epoch) {
    final isMilliseconds = epoch.abs() > 9999999999;
    return DateTime.fromMillisecondsSinceEpoch(
      isMilliseconds ? epoch : epoch * 1000,
      isUtc: true,
    ).toLocal();
  }

  static ({String date, String time})? _normalizeTimeWithDate(
    String date,
    String time,
  ) {
    final trimmed = time.trim();

    // If time already carries timezone/ISO markers, parse with date and convert.
    if (trimmed.contains('Z') || trimmed.contains('+') || trimmed.contains('-') || trimmed.contains('T')) {
      final attempt = DateTime.tryParse('${date}T$trimmed');
      if (attempt != null) {
        final local = attempt.toLocal();
        return (date: _formatDate(local), time: _formatTime(local));
      }
      final direct = DateTime.tryParse(trimmed);
      if (direct != null) {
        final local = direct.toLocal();
        return (date: _formatDate(local), time: _formatTime(local));
      }
    }

    // Trim seconds/millis for standard HH:mm(:ss[.sss]) inputs.
    final timeOnlyMatch = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$').firstMatch(trimmed);
    if (timeOnlyMatch != null) {
      final h = (int.tryParse(timeOnlyMatch.group(1)!) ?? 0)
          .toString()
          .padLeft(2, '0');
      final m = timeOnlyMatch.group(2)!;
      return (date: date, time: '$h:$m');
    }

    return null;
  }

  static String _formatDate(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d';
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ─── Category ────────────────────────────────────────────────
class Category {
  final String id;
  final String name;
  final double budget;
  final String type;
  final double amount;
  final List<SubCategory> subCategories;

  Category({
    required this.id,
    required this.name,
    this.budget = 0,
    this.type = '',
    this.amount = 0,
    this.subCategories = const [],
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'].toString(),
        name: json['name'] ?? '',
        budget: _toDouble(json['budget']),
        type: json['type'] ?? '',
        subCategories: (json['subCategories'] as List?)
                ?.map((s) => SubCategory.fromJson(s))
                .toList() ??
            [],
      );
}

// ─── SubCategory ─────────────────────────────────────────────
class SubCategory {
  final String id;
  final String categoryId;
  final String name;
  final double budget;

  SubCategory({
    required this.id,
    this.categoryId = '',
    required this.name,
    this.budget = 0,
  });

  factory SubCategory.fromJson(Map<String, dynamic> json) => SubCategory(
        id: json['id'].toString(),
        categoryId: json['categoryId'].toString(),
        name: json['name'] ?? '',
        budget: _toDouble(json['budget']),
      );
}

// ─── Credit Card Cap ─────────────────────────────────────────
class CreditCardCap {
  final String id;
  final String creditCardId;
  final String capName;
  final double capTotalAmount;
  final double capPercentage;
  final double capCurrentAmount;
  final double remainingAmount;
  final double totalRewards;
  final double rewardPerAmount;

  CreditCardCap({
    required this.id,
    required this.creditCardId,
    required this.capName,
    required this.capTotalAmount,
    required this.capPercentage,
    this.capCurrentAmount = 0,
    this.remainingAmount = 0,
    this.totalRewards = 0,
    this.rewardPerAmount = 100,
  });

  factory CreditCardCap.fromJson(Map<String, dynamic> json) => CreditCardCap(
        id: json['id'].toString(),
        creditCardId: json['creditCardId'].toString(),
        capName: json['capName'] ?? '',
        capTotalAmount: _toDouble(json['capTotalAmount']),
        capPercentage: _toDouble(json['capPercentage']),
        capCurrentAmount: _toDouble(json['capCurrentAmount']),
        remainingAmount: _toDouble(json['remainingAmount']),
        totalRewards: _toDouble(json['totalRewards']),
        rewardPerAmount: _toDouble(json['rewardPerAmount'] ?? 100),
      );
}

// ─── Splitwise Group ─────────────────────────────────────────
class SplitwiseGroup {
  final String id;
  final String name;
  final List<SplitwiseMember> members;

  SplitwiseGroup({
    required this.id,
    required this.name,
    required this.members,
  });

  factory SplitwiseGroup.fromJson(Map<String, dynamic> json) =>
      SplitwiseGroup(
        id: json['id'].toString(),
        name: json['name'] ?? '',
        members: (json['members'] as List? ?? [])
            .map((m) => SplitwiseMember.fromJson(m))
            .toList(),
      );
}

class SplitwiseMember {
  final String id;
  final String friendId;
  final String name;

  SplitwiseMember({
    required this.id,
    required this.friendId,
    required this.name,
  });

  factory SplitwiseMember.fromJson(Map<String, dynamic> json) =>
      SplitwiseMember(
        id: json['id'].toString(),
        friendId: json['friendId'].toString(),
        name: json['name'] ?? '',
      );
}

// ─── Yearly Summary ──────────────────────────────────────────
class MonthlySummary {
  final String month;
  final double expense;
  final double income;
  final double investment;

  MonthlySummary({
    required this.month,
    required this.expense,
    required this.income,
    required this.investment,
  });

  factory MonthlySummary.fromJson(Map<String, dynamic> json) =>
      MonthlySummary(
        month: (json['month'] ?? '').toString(),
        expense: _toDouble(json['expense']),
        income: _toDouble(json['income']),
        investment: _toDouble(json['investment']),
      );
}

// ─── Friend Balance ──────────────────────────────────────────
class FriendBalance {
  final String name;
  final double splitwiseAmount;
  final double notionAmount;
  final String friendId;

  FriendBalance({
    required this.name,
    required this.splitwiseAmount,
    required this.notionAmount,
    required this.friendId,
  });

  factory FriendBalance.fromJson(Map<String, dynamic> json) => FriendBalance(
        name: json['name'] ?? '',
        splitwiseAmount: _toDouble(json['splitwiseAmount']),
        notionAmount: _toDouble(json['notionAmount']),
        friendId: json['friendId'].toString(),
      );
}

// ─── CC Statement Transaction ────────────────────────────────
class CCStatementTransaction {
  final String date;
  final String time;
  final String description;
  final double amount;
  final bool isCredit;
  final bool isEmi;

  CCStatementTransaction({
    required this.date,
    required this.time,
    required this.description,
    required this.amount,
    this.isCredit = false,
    this.isEmi = false,
  });

  /// Convert statement date (DD/MM/YYYY) to YYYY-MM-DD for matching
  String get normalizedDate {
    final parts = date.split('/');
    if (parts.length == 3) return '${parts[2]}-${parts[1]}-${parts[0]}';
    return date;
  }
}

// ─── Merged CC Transaction ───────────────────────────────────
/// Holds a statement transaction merged with DB transaction (if matched).
class MergedCCTransaction {
  final CCStatementTransaction statementTxn;
  final TransactionModel? dbTxn; // null if not found in DB

  MergedCCTransaction({
    required this.statementTxn,
    this.dbTxn,
  });

  bool get isMatched => dbTxn != null;
  String get date => statementTxn.date;
  String get description => dbTxn?.description ?? statementTxn.description;
  String? get category => dbTxn?.category;
  String? get subCategory => dbTxn?.subCategory;
  double get statementAmount => statementTxn.amount;
  double? get dbAmount => dbTxn?.amount;
  bool get isCredit => statementTxn.isCredit;
  bool get isEmi => statementTxn.isEmi;
}

// ─── Bank Statement Transaction ──────────────────────────────
class BankStatementTransaction {
  final String date;
  final String description;
  final double amount;
  final bool isCredit; // true = credit, false = debit
  final double? balance; // running balance

  BankStatementTransaction({
    required this.date,
    required this.description,
    required this.amount,
    required this.isCredit,
    this.balance,
  });

  /// Convert statement date (DD/MM/YYYY) to YYYY-MM-DD for matching
  String get normalizedDate {
    final parts = date.split('/');
    if (parts.length == 3) return '${parts[2]}-${parts[1]}-${parts[0]}';
    return date;
  }
}

// ─── Merged Bank Transaction ─────────────────────────────────
class MergedBankTransaction {
  final BankStatementTransaction statementTxn;
  final TransactionModel? dbTxn;

  MergedBankTransaction({
    required this.statementTxn,
    this.dbTxn,
  });

  bool get isMatched => dbTxn != null;
  String get date => statementTxn.date;
  String get description => dbTxn?.description ?? statementTxn.description;
  String? get category => dbTxn?.category;
  String? get subCategory => dbTxn?.subCategory;
  double get statementAmount => statementTxn.amount;
  double? get dbAmount => dbTxn?.amount;
  bool get isCredit => statementTxn.isCredit;
  double? get balance => statementTxn.balance;
}
