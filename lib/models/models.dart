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
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) =>
      TransactionModel(
        id: json['id'].toString(),
        date: json['date'] ?? '',
        time: json['time'],
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
        splitwiseDetails: json['splitwiseDetails'],
      );
}

// ─── Category ────────────────────────────────────────────────
class Category {
  final String id;
  final String name;
  final double budget;
  final String type;
  final List<SubCategory> subCategories;

  Category({
    required this.id,
    required this.name,
    this.budget = 0,
    this.type = '',
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
