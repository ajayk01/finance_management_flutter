import 'package:finance_app/services/direct_sql_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/account_card.dart';
import '../widgets/expense_pie_chart.dart';
import '../widgets/monthly_budget.dart';
import '../widgets/money_flow.dart';
import '../widgets/bottom_nav_bar.dart';
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
  final _api = ApiService();

  // Data state
  bool _loading = true;
  List<BankAccount> _bankAccounts = [];
  List<CreditCardAccount> _creditCards = [];
  List<InvestmentAccount> _investmentAccounts = [];
  // ignore: unused_field
  List<Category> _categories = [];
  double _totalIncome = 0;
  double _totalExpense = 0;
  double _totalInvestment = 0;
  double _budgetSpent = 0;
  double _budgetTotal = 0;
  // ignore: unused_field
  List<MonthlySummary> _yearlySummary = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<ActiveAccountsResult> _safeFetchAccounts(String month, String year) async {
    try {
      return await DirectSqlService.getAllActiveAccounts();
    } catch (e) {
      debugPrint('[HomeScreen] getAccounts failed: $e');
      return const ActiveAccountsResult();
    }
  }

  Future<Map<String, dynamic>> _safeFetch(
    String label,
    Future<Map<String, dynamic>> Function() fetcher,
  ) async {
    try {
      return await fetcher();
    } catch (e) {
      debugPrint('[HomeScreen] $label failed: $e');
      return {};
    }
  }

  double _parseAmount(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[^0-9.\-]'), '');
      return double.tryParse(cleaned) ?? 0;
    }
    return 0;
  }

  Future<void> _loadData() async {
    final now = DateTime.now();
    final month = DateFormat('MMM').format(now).toLowerCase();
    final year = now.year.toString();

    final accountsFuture = _safeFetchAccounts(month, year);
    final typesSumFuture = DirectSqlService.getTransactionTypesSum(month, year).catchError((e) {
      debugPrint('[HomeScreen] getTransactionTypesSum failed: $e');
      return <String, double>{'total_income': 0, 'total_expense': 0, 'total_investment': 0};
    });

    final results = await Future.wait([
      _safeFetch('getCategories', () => _api.getCategories(type: 'expense')),
      _safeFetch('getYearlySummary', () => _api.getYearlySummary(year)),
    ]);

    final accountsData = await accountsFuture;
    final typeSums = await typesSumFuture;
    final categoriesData = results[0];
    final yearlyData = results[1];

    final banks = accountsData.bankAccounts;
    final cards = accountsData.creditCardAccounts;
    final investments = accountsData.investmentAccounts;

    final double income = typeSums['total_income'] ?? 0;
    final double expense = typeSums['total_expense'] ?? 0;
    final double investment = typeSums['total_investment'] ?? 0;

    final List<Category> cats = (categoriesData['categories'] as List? ?? [])
      .map((j) => Category.fromJson(j))
        .where((c) => c.type == 'expense')
        .toList();
    final totalBudget =
        cats.fold<double>(0, (sum, c) => sum + c.budget);

    final summary = (yearlyData['summaryData'] as List? ?? [])
        .map((j) => MonthlySummary.fromJson(j))
        .toList();

    if (mounted) {
      setState(() {
        _bankAccounts = banks;
        _creditCards = cards;
        _investmentAccounts = investments;
        _totalIncome = income;
        _totalExpense = expense;
        _totalInvestment = investment;
        _categories = cats;
        _budgetSpent = expense;
        _budgetTotal = totalBudget;
        _yearlySummary = summary;
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
                  const ExpensePieChart(),
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
