import 'package:finance_app/services/direct_sql_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../widgets/account_card.dart';
import '../widgets/expense_pie_chart.dart';
import '../widgets/monthly_budget.dart';
import '../widgets/money_flow.dart';
import '../widgets/bottom_nav_bar.dart';
import '../services/app_data_cache.dart';
import 'investment_screen.dart';
import 'profile_screen.dart';
import 'transaction_screen.dart';
import 'add_transaction_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedNavIndex = 0;
  String? _filterAccount;

  // Data state
  bool _loading = true;
  List<BankAccount> _bankAccounts = [];
  List<CreditCardAccount> _creditCards = [];
  List<InvestmentAccount> _investmentAccounts = [];
  // ignore: unused_field
  List<Category> _categories = [];
  List<Category> _allCategories = [];
  double _totalIncome = 0;
  double _totalExpense = 0;
  double _totalInvestment = 0;
  double _budgetSpent = 0;
  double _budgetTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<ActiveAccountsResult> _safeFetchAccounts(String month, String year) async 
  {
    try 
    {
      return await DirectSqlService.getAllActiveAccounts();
    } 
    catch (e) 
    {
      debugPrint('[HomeScreen] getAccounts failed: $e');
      return const ActiveAccountsResult();
    }
  }

  Future<void> _loadData() async {
    final now = DateTime.now();
    final month = DateFormat('MMM').format(now).toLowerCase();
    final year = now.year.toString();

    // Load accounts and categories in PARALLEL instead of sequentially
    final accountsFuture = _safeFetchAccounts(month, year);
    final expenseCategoriesFuture = DirectSqlService.getExpenseCategories(month, year).catchError((e) {
      debugPrint('[HomeScreen] getExpenseCategories failed: $e');
      return (
        categories: <Category>[],
        totalIncome: 0.0,
        totalExpense: 0.0,
        totalInvestment: 0.0,
      );
    });

    // Wait for both in parallel
    final results = await Future.wait([accountsFuture, expenseCategoriesFuture]);
    
    final accountsData = results[0] as ActiveAccountsResult;
    final categoriesResult = results[1] as ({
      List<Category> categories,
      double totalIncome,
      double totalExpense,
      double totalInvestment
    });

    final expenseCategories = categoriesResult.categories;

    final banks = accountsData.bankAccounts;
    final cards = accountsData.creditCardAccounts;
    final investments = accountsData.investmentAccounts;

    final double income = categoriesResult.totalIncome;
    final double expense = categoriesResult.totalExpense;
    final double investment = categoriesResult.totalInvestment;

    final List<Category> cats = (expenseCategories as List<Category>? ?? [])
        .where((c) => c.type == 'expense')
        .toList();
    final totalBudget =
        cats.fold<double>(0, (sum, c) => sum + c.budget);

    final expenseByCategory = <String, double>{};
    final incomeByCategory = <String, double>{};
    for (final c in expenseCategories) {
      final amount = c.amount;
      if (amount <= 0) continue;
      if (c.type == 'expense') {
        expenseByCategory[c.name] = (expenseByCategory[c.name] ?? 0) + amount;
      } else if (c.type == 'income') {
        incomeByCategory[c.name] = (incomeByCategory[c.name] ?? 0) + amount;
      }
    }

    final cache = AppDataCache();
    cache.updateAccountsFromModels(
      bankAccounts: banks,
      creditCardAccounts: cards,
      investmentAccounts: investments,
    );
    cache.updateMonthlySummaryCache(
      month: month,
      year: year,
      expenseByCategory: expenseByCategory,
      incomeByCategory: incomeByCategory,
      totalIncome: income,
      totalExpense: expense,
      totalInvestment: investment,
    );

    if (mounted) {
      setState(() {
        _bankAccounts = banks;
        _creditCards = cards;
        _investmentAccounts = investments;
        _totalIncome = income;
        _totalExpense = expense;
        _totalInvestment = investment;
        _categories = cats;
        _allCategories = expenseCategories;
        _budgetSpent = expense;
        _budgetTotal = totalBudget;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) 
  {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F8),
      body: _buildBody(),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _selectedNavIndex,
        onTap: (index) => setState(() => _selectedNavIndex = index),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddTransactionScreen(),
            ),
          );
          if (result == true) {
            _loadData();
          }
        },
        backgroundColor: const Color(0xFF3B3BF9),
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildBody() {
    switch (_selectedNavIndex) {
      case 1:
        final account = _filterAccount;
        _filterAccount = null;
        return TransactionScreen(initialAccount: account);
      case 2:
        return const InvestmentScreen();
      case 3:
        return const ProfileScreen();
      default:
        if (_loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  AccountCard(
                    bankAccounts: _bankAccounts,
                    creditCards: _creditCards,
                    investmentAccounts: _investmentAccounts,
                    onAccountTap: (accountName) {
                      setState(() {
                        _filterAccount = accountName;
                        _selectedNavIndex = 1;
                      });
                    },
                  ),
                  const SizedBox(height: 28),
                  MonthlyBudget(
                    spent: _budgetSpent,
                    total: _budgetTotal > 0 ? _budgetTotal : 2500,
                  ),
                  const SizedBox(height: 28),
                  ExpensePieChart(categories: _allCategories),
                  const SizedBox(height: 28),
                  MoneyFlow(
                    income: _totalIncome,
                    expense: _totalExpense,
                    investment: _totalInvestment,
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        );
    }
  }

  Widget _buildHeader() {
    final now = DateTime.now();
    final timeStr = DateFormat('hh:mm a').format(now);
    final dateStr = DateFormat('EEE, dd MMMM yyyy').format(now);
    return Row(
      children: [
        const CircleAvatar(
          radius: 24,
          backgroundColor: Color(0xFFE0E7FF),
          child: Icon(Icons.person, size: 28, color: Color(0xFF3B3BF9)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hi, K Ajay!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade900,
                ),
              ),
              Text(
                '$timeStr • $dateStr',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        _buildIconButton(Icons.notifications_outlined, badge: true),
      ],
    );
  }

  Widget _buildIconButton(IconData icon, {bool badge = false}) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, color: Colors.grey.shade700, size: 22),
          if (badge)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
