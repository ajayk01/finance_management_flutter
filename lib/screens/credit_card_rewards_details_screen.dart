import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_data_cache.dart';
import '../services/direct_sql_service.dart';
import '../widgets/credit_card_cap_carousel.dart';

class CreditCardRewardsDetailsScreen extends StatefulWidget {
  const CreditCardRewardsDetailsScreen({super.key});

  @override
  State<CreditCardRewardsDetailsScreen> createState() =>
      _CreditCardRewardsDetailsScreenState();
}

class _CreditCardRewardsDetailsScreenState
    extends State<CreditCardRewardsDetailsScreen> {
  bool _loading = true;
  List<CreditCardAccount> _cards = [];
  List<CreditCardCap> _caps = [];

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      final results = await Future.wait([
        DirectSqlService.getAllActiveAccounts(),
        DirectSqlService.getAllCreditCardCaps(),
      ]);
      final accounts = results[0] as ActiveAccountsResult;
      if (!mounted) return;
      setState(() {
        _cards = accounts.creditCardAccounts;
        _caps = results[1] as List<CreditCardCap>;
        _loading = false;
      });
      // Update cache with fresh caps
      AppDataCache().setCreditCardCaps(_caps);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Credit Card Rewards Details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDetails,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: _buildCardTables(),
              ),
            ),
    );
  }

  List<Widget> _buildCardTables() {
    if (_caps.isEmpty) {
      return const [Center(child: Text('No credit card caps found.'))];
    }
    final capsByCard = <String, List<CreditCardCap>>{};
    for (final cap in _caps) {
      capsByCard.putIfAbsent(cap.creditCardId, () => []).add(cap);
    }
    return capsByCard.entries.map((entry) {
      final card = _cards.where((item) => item.id == entry.key).firstOrNull;
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: _buildCapTable(
          title: 'Cap Details - ${card?.name ?? 'Credit card'}',
          caps: entry.value,
        ),
      );
    }).toList();
  }

  Widget _buildCapTable({
    required String title,
    required List<CreditCardCap> caps,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        CreditCardCapCarousel(caps: caps),
      ],
    );
  }
}
