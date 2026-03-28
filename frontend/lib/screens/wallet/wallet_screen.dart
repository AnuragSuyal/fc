import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/socket_service.dart';
import '../../services/wallet_service.dart';
import '../../utils/constants.dart';
import '../../widgets/currency_icon.dart';
import '../../widgets/rounded_scaffold.dart';
import '../../widgets/transaction_history_icon.dart';
import 'shop_screen.dart';
import 'transactions_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _isLoading = true;
  bool _disposed = false;
  Map<String, dynamic> _meta = const {'tickets': 0, 'stars': 0, 'vipLevel': 0};
  List<Map<String, dynamic>> _recent = const [];
  StreamSubscription<Map<String, dynamic>>? _walletUpdateSubscription;
  StreamSubscription<Map<String, dynamic>>? _walletResyncSubscription;
  Timer? _realtimeDebounce;

  @override
  void initState() {
    super.initState();
    _subscribeToRealtime();
    unawaited(_loadWallet());
  }

  @override
  void dispose() {
    _disposed = true;
    _realtimeDebounce?.cancel();
    _walletUpdateSubscription?.cancel();
    _walletResyncSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToRealtime() {
    _walletUpdateSubscription = SocketService.balanceStream.listen((_) {
      _scheduleRealtimeRefresh();
    });
    _walletResyncSubscription = SocketService.resyncStream.listen((_) {
      _scheduleRealtimeRefresh();
    });
  }

  void _scheduleRealtimeRefresh() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 350), () {
      if (_disposed || !mounted) return;
      unawaited(_loadWallet(showLoader: false));
    });
  }

  Future<void> _loadWallet({bool showLoader = true}) async {
    if (_disposed) return;
    if (showLoader && mounted) setState(() => _isLoading = true);

    try {
      final results = await Future.wait<dynamic>([
        WalletService.getBalance(),
        WalletService.getTransactions(limit: 8),
      ]);
      if (!mounted || _disposed) return;

      final balance = Map<String, dynamic>.from(results[0] as Map);
      final history = Map<String, dynamic>.from(results[1] as Map);

      context.read<AuthProvider>().updateProfile(
            coins: _toInt(balance['coins']),
            gems: _toInt(balance['gems']),
            vipLevel: _toInt(balance['vipLevel']),
          );

      final recent = <Map<String, dynamic>>[];
      final grouped = history['transactions'];
      if (grouped is Map) {
        for (final value in grouped.values) {
          if (value is List) {
            for (final item in value) {
              if (item is Map) recent.add(Map<String, dynamic>.from(item));
            }
          }
        }
      }
      recent.sort(
          (a, b) => _dateOf(b['createdAt']).compareTo(_dateOf(a['createdAt'])));

      setState(() {
        _meta = {
          'tickets': _toInt(balance['tickets']) ?? 0,
          'stars': _toInt(balance['stars']) ?? 0,
          'vipLevel': _toInt(balance['vipLevel']) ?? 0,
        };
        _recent = recent.take(5).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Wallet load error: $e');
      if (!mounted || _disposed) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openShop(int tab) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoundedScaffold(
          title: 'Wallet Shop',
          body: ShopScreen(initialTab: tab),
        ),
      ),
    );
    if (mounted) _loadWallet(showLoader: false);
  }

  Future<void> _showConvertDialog() async {
    final controller = TextEditingController();
    final ok = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert coins'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Coins',
            hintText: '100 coins = 1 gem',
            prefixIcon: CurrencyIcon.coins(size: 20),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('Convert'),
          ),
        ],
      ),
    );

    if (ok == null || ok < 100 || !mounted) return;
    final result = await WalletService.convertCoinsToGems(ok);
    if (!mounted) return;

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversion failed.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    final balance = result['newBalance'] is Map
        ? Map<String, dynamic>.from(result['newBalance'] as Map)
        : <String, dynamic>{};
    context.read<AuthProvider>().updateBalance(
          coins: _toInt(balance['coins']),
          gems: _toInt(balance['gems']),
        );
    await _loadWallet(showLoader: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Converted $ok coins into ${ok ~/ 100} gems.'),
        backgroundColor: AppColors.successGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = context.watch<AuthProvider>().user;
    final coins = user?.coins ?? 0;
    final gems = user?.gems ?? 0;
    final vip = user?.vipLevel ?? (_toInt(_meta['vipLevel']) ?? 0);
    final tickets = _toInt(_meta['tickets']) ?? 0;
    final stars = _toInt(_meta['stars']) ?? 0;

    return RoundedScaffold(
      title: 'Wallet',
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: colorScheme.outline.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CurrencyIcon.coins(size: 16),
              const SizedBox(width: 4),
              Text('$coins', style: theme.textTheme.labelLarge),
              const SizedBox(width: 10),
              const CurrencyIcon.gems(size: 16),
              const SizedBox(width: 4),
              Text('$gems', style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadWallet(showLoader: false),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.primaryBlue,
                          AppColors.accentBerry,
                          AppColors.secondaryBlue,
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live wallet connected',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Coins, gems, room purchases, and VIP flows now share the same wallet state.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            _metric('Coins', '$coins'),
                            const SizedBox(width: 10),
                            _metric('Gems', '$gems'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _metric('Tickets', '$tickets'),
                            const SizedBox(width: 10),
                            _metric('VIP', vip > 0 ? 'VIP $vip' : 'Free'),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () => _openShop(0),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.textPrimary,
                                ),
                                child: const Text('Top up'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _showConvertDialog,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.30),
                                  ),
                                ),
                                child: const Text('Convert'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Quick actions',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: _actionCard(
                              context,
                              const CurrencyIcon.coins(size: 24),
                              'Buy coins',
                              'Top up',
                              () => _openShop(0))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _actionCard(
                              context,
                              const CurrencyIcon.gems(size: 24),
                              'Buy gems',
                              'Premium items',
                              () => _openShop(1))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _actionCard(
                              context,
                              const TransactionHistoryIcon(size: 30),
                              'History',
                              'Transactions', () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const TransactionsScreen()));
                      }, iconBoxSize: 30)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text('Recent activity',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const TransactionsScreen()));
                        },
                        child: const Text('View all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _recent.isEmpty
                          ? ListTile(
                              leading: Icon(Icons.receipt_long_outlined,
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.45)),
                              title: const Text('No wallet activity yet'),
                              subtitle: const Text(
                                  'Purchases, gifts, and bonuses will show up here.'),
                            )
                          : Column(
                              children: [
                                for (var i = 0; i < _recent.length; i++) ...[
                                  _transactionTile(context, _recent[i]),
                                  if (i != _recent.length - 1)
                                    Divider(
                                        color: colorScheme.outline
                                            .withValues(alpha: 0.10)),
                                ],
                              ],
                            ),
                    ),
                  ),
                  if (stars > 0) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.auto_awesome_rounded,
                            color: Color(0xFFF59E0B)),
                        title: Text('Star balance: $stars'),
                        subtitle: const Text(
                            'Stars are synced and ready for future rewards and campaigns.'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.78))),
          ],
        ),
      ),
    );
  }

  Widget _actionCard(
    BuildContext context,
    Widget icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    double iconBoxSize = 24,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border:
              Border.all(color: colorScheme.outline.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: iconBoxSize,
              height: iconBoxSize,
              child: Center(
                child: IconTheme(
                  data: IconThemeData(color: colorScheme.primary, size: 24),
                  child: icon,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _transactionTile(
      BuildContext context, Map<String, dynamic> transaction) {
    final amount = transaction['amount'] is Map
        ? Map<String, dynamic>.from(transaction['amount'] as Map)
        : <String, dynamic>{};
    final coins = _toInt(amount['coins']) ?? 0;
    final gems = _toInt(amount['gems']) ?? 0;
    final positive = coins > 0 || gems > 0;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            (positive ? AppColors.successGreen : AppColors.errorRed)
                .withValues(alpha: 0.12),
        child: Icon(_iconFor(transaction['type']?.toString()),
            color: positive ? AppColors.successGreen : AppColors.errorRed),
      ),
      title: Text(transaction['description']?.toString() ?? 'Transaction'),
      subtitle: Text(_formatRelative(transaction['createdAt']?.toString())),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (coins != 0)
            Text('${coins > 0 ? '+' : ''}$coins coins',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          if (gems != 0)
            Text('${gems > 0 ? '+' : ''}$gems gems',
                style: const TextStyle(
                    color: Color(0xFF7C3AED), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'purchase_coins':
      case 'purchase_gems':
        return Icons.shopping_bag_outlined;
      case 'gift_sent':
      case 'gift_received':
        return Icons.card_giftcard_rounded;
      case 'vip_purchase':
        return Icons.workspace_premium_rounded;
      case 'daily_bonus':
      case 'vip_daily_bonus':
        return Icons.calendar_today_outlined;
      default:
        return Icons.swap_horiz_rounded;
    }
  }

  String _formatRelative(String? value) {
    final parsed = DateTime.tryParse(value ?? '');
    if (parsed == null) return 'Recently';
    final diff = DateTime.now().difference(parsed);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  DateTime _dateOf(dynamic value) {
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
