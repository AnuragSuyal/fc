import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/wallet_service.dart';
import '../../widgets/rounded_scaffold.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  Map<String, dynamic> _transactions = {};
  bool _isLoading = true;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isDisposed = false;

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    _safeSetState(() => _isLoading = true);

    final data = await WalletService.getTransactions(page: _currentPage);

    if (!mounted) return;

    _safeSetState(() {
      if (_currentPage == 1) {
        _transactions = data['transactions'] ?? {};
      } else {
        final newTransactions = data['transactions'] ?? {};
        // Merge by date
        newTransactions.forEach((date, txs) {
          if (_transactions.containsKey(date)) {
            _transactions[date] = [..._transactions[date], ...txs];
          } else {
            _transactions[date] = txs;
          }
        });
      }
      _hasMore = (data['pagination']?['pages'] ?? 1) > _currentPage;
      _isLoading = false;
    });
  }

  void _loadMore() {
    if (_hasMore && !_isLoading) {
      _currentPage++;
      _loadTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoundedScaffold(
      title: 'Transaction History',
      body: _isLoading && _currentPage == 1
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No transactions yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your transaction history will appear here',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollEndNotification &&
                        notification.metrics.extentAfter == 0 &&
                        _hasMore) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _transactions.keys.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _transactions.keys.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final dates = _transactions.keys.toList()
                        ..sort((a, b) => b.compareTo(a));
                      final date = dates[index];
                      final txs = _transactions[date] as List;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              _formatDateHeader(date),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          ...txs.map((t) => _buildTransactionTile(t)),
                        ],
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> t) {
    if (t['amount'] == null) return const SizedBox.shrink();

    final amountCoins = t['amount']['coins'] as num? ?? 0;
    final amountGems = t['amount']['gems'] as num? ?? 0;
    final isPositive = amountCoins > 0 || amountGems > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isPositive ? Colors.green.shade50 : Colors.red.shade50,
          child: Icon(
            _getTransactionIcon(t['type']),
            color: isPositive ? Colors.green : Colors.red,
          ),
        ),
        title: Text(t['description'] ?? 'Transaction'),
        subtitle: Text(_formatTime(t['createdAt'].toString())),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (amountCoins != 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.monetization_on,
                      size: 12,
                      color: Colors.amber.shade700,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '$amountCoins',
                      style: TextStyle(
                        color: Colors.amber.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (amountGems != 0)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.diamond,
                        size: 12,
                        color: Colors.purple.shade700,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '$amountGems',
                        style: TextStyle(
                          color: Colors.purple.shade700,
                          fontWeight: FontWeight.bold,
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

  IconData _getTransactionIcon(String? type) {
    switch (type) {
      case 'purchase_coins':
      case 'purchase_gems':
        return Icons.shopping_cart;
      case 'gift_sent':
        return Icons.card_giftcard;
      case 'gift_received':
        return Icons.card_giftcard;
      case 'daily_bonus':
        return Icons.calendar_today;
      case 'quest_reward':
        return Icons.assignment_turned_in;
      case 'vip_purchase':
        return Icons.workspace_premium;
      case 'entry_fee':
        return Icons.meeting_room;
      case 'tip':
        return Icons.volunteer_activism;
      case 'withdrawal':
        return Icons.account_balance;
      default:
        return Icons.swap_horiz;
    }
  }

  String _formatDateHeader(String dateStr) {
    try {
      final date = DateTime.tryParse(dateStr) ??
          DateFormat('EEE MMM dd yyyy').parseLoose(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));

      if (date.year == today.year &&
          date.month == today.month &&
          date.day == today.day) {
        return 'Today';
      } else if (date.year == yesterday.year &&
          date.month == yesterday.month &&
          date.day == yesterday.day) {
        return 'Yesterday';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return dateStr;
    }
  }

  String _formatTime(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }
}





