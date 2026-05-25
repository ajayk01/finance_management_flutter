import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/currency_formatter.dart';

class AccountCard extends StatefulWidget 
{
  final List<BankAccount> bankAccounts;
  final List<CreditCardAccount> creditCards;
  final List<InvestmentAccount> investmentAccounts;

  const AccountCard({
    super.key,
    this.bankAccounts = const [],
    this.creditCards = const [],
    this.investmentAccounts = const [],
  });

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<Map<String, dynamic>> get _pages {
    debugPrint('Bank Accounts: ${widget.bankAccounts}, Credit Cards: ${widget.creditCards}, Investment Accounts: ${widget.investmentAccounts}');
    final bankList = widget.bankAccounts.isNotEmpty
        ? widget.bankAccounts
            .map((a) => {'name': a.name, 'balance': formatINR(a.balance), 'logo': a.logo ?? ''})
            .toList()
        : <Map<String, String>>[
            {'name': 'Bank of America', 'balance': '₹52,450.26', 'logo': ''},
            {'name': 'Chase Bank', 'balance': '₹78,312.52', 'logo': ''},
          ];
    final ccList = widget.creditCards.isNotEmpty
        ? widget.creditCards
            .map((a) => {'name': a.name, 'balance': formatINR(a.usedAmount.abs()), 'logo': a.logo ?? ''})
            .toList()
        : <Map<String, String>>[
            {'name': 'Visa Platinum', 'balance': '₹3,240.50', 'logo': ''},
            {'name': 'Mastercard Gold', 'balance': '₹1,890.00', 'logo': ''},
          ];
    final invList = widget.investmentAccounts.isNotEmpty
        ? widget.investmentAccounts
            .map((a) => {'name': a.name, 'balance': formatINR(a.totalInvested), 'logo': ''})
            .toList()
        : <Map<String, String>>[
            {'name': 'Vanguard S&P 500', 'balance': '₹45,200.00', 'logo': ''},
            {'name': 'Fidelity Growth', 'balance': '₹32,150.75', 'logo': ''},
          ];

    return [
      {
        'title': 'Main Account',
        'icon': Icons.account_balance,
        'gradient': const [Color(0xFF0D0D3B), Color(0xFF1A1A6C), Color(0xFF2D2DB8), Color(0xFF3B3BF9)],
        'accounts': bankList,
      },
      {
        'title': 'Credit Card',
        'icon': Icons.credit_card,
        'gradient': const [Color(0xFF3B0D0D), Color(0xFF6C1A1A), Color(0xFFB82D2D), Color(0xFFF93B3B)],
        'accounts': ccList,
      },
      {
        'title': 'Investment',
        'icon': Icons.trending_up,
        'gradient': const [Color(0xFF0D3B1A), Color(0xFF1A6C2D), Color(0xFF2DB84A), Color(0xFF3BF96B)],
        'accounts': invList,
      },
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 288,
          child: PageView.builder(
            controller: _pageController,
            clipBehavior: Clip.none,
            itemCount: _pages.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _buildCard(_pages[index]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildPageIndicator(),
      ],
    );
  }

  Widget _buildCard(Map<String, dynamic> page) {
    final accounts = page['accounts'] as List<Map<String, String>>;
    final gradientColors = page['gradient'] as List<Color>;
    final fallbackIcon = page['icon'] as IconData;
    final title = page['title'] as String;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
            stops: const [0.0, 0.3, 0.6, 1.0],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -40,
              left: -20,
              child: Transform.rotate(
                angle: -0.5,
                child: Container(
                  width: 200,
                  height: 350,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.06),
                        Colors.white.withValues(alpha: 0.02),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -60,
              left: 60,
              child: Transform.rotate(
                angle: -0.5,
                child: Container(
                  width: 160,
                  height: 400,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.04),
                        Colors.white.withValues(alpha: 0.01),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -30,
              right: -40,
              child: Transform.rotate(
                angle: -0.6,
                child: Container(
                  width: 180,
                  height: 300,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.15),
                        Colors.white.withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.more_vert,
                          color: Colors.white.withValues(alpha: 0.7),
                          size: 22,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: List.generate(accounts.length, (index) {
                            return Column(
                              children: [
                                _buildAccountRow(
                                  fallbackIcon,
                                  accounts[index]['name']!,
                                  accounts[index]['balance']!,
                                  accounts[index]['logo'] ?? '',
                                ),
                                if (index < accounts.length - 1) _buildDivider(),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pages.length, (index) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentPage == index ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: _currentPage == index
                ? const Color(0xFF3B3BF9)
                : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildAccountRow(IconData icon, String name, String balance, String logo) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: logo.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    logo,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(icon, color: Colors.white, size: 20),
                  ),
                )
              : Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        Text(
          balance,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.white.withValues(alpha: 0.12),
      ),
    );
  }
}
