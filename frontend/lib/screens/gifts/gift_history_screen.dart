import 'package:flutter/material.dart';
import '../../models/gift_transaction_model.dart';
import '../../services/gift_service.dart';
import '../../widgets/currency_icon.dart';

class GiftHistoryScreen extends StatefulWidget {
  const GiftHistoryScreen({super.key});

  @override
  State<GiftHistoryScreen> createState() => _GiftHistoryScreenState();
}

class _GiftHistoryScreenState extends State<GiftHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<GiftTransactionModel> _sent = [];
  List<GiftTransactionModel> _received = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final sentData = await GiftService.getGiftHistory(type: 'sent');
      final receivedData = await GiftService.getGiftHistory(type: 'received');

      if (!mounted) return;
      setState(() {
        _sent = sentData['transactions'];
        _received = receivedData['transactions'];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gift History'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Sent'),
            Tab(text: 'Received'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildHistoryList(_sent),
                    _buildHistoryList(_received),
                  ],
                ),
    );
  }

  Widget _buildHistoryList(List<GiftTransactionModel> transactions) {
    if (transactions.isEmpty) {
      return const Center(child: Text('No gift history found'));
    }

    return ListView.builder(
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final tx = transactions[index];
        final isSent = tx.type == 'gift_sent';

        // Determine person name based on transaction type
        String personName = 'Unknown';
        if (isSent) {
          personName = tx.recipientName ?? 'Unknown';
        } else {
          personName = tx.senderName ?? 'Unknown';
        }

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey.shade300,
            child: Text(
              personName.isNotEmpty ? personName[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(
            isSent ? 'To: $personName' : 'From: $personName',
          ),
          subtitle: Text(tx.description),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(tx.formattedDate),
              if (tx.coinsAmount != 0 || tx.gemsAmount != 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tx.coinsAmount != 0) ...[
                      const CurrencyIcon.coins(size: 14),
                      const SizedBox(width: 2),
                      Text('${tx.coinsAmount.abs()}'),
                    ],
                    if (tx.gemsAmount != 0) ...[
                      const SizedBox(width: 4),
                      const CurrencyIcon.gems(size: 14),
                      const SizedBox(width: 2),
                      Text('${tx.gemsAmount.abs()}'),
                    ],
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
