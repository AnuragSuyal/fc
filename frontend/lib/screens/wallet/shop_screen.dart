import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/wallet_service.dart';
import '../../utils/constants.dart';

class ShopScreen extends StatefulWidget {
  final int initialTab;

  const ShopScreen({
    super.key,
    this.initialTab = 0,
  });

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  List<dynamic> _coins = [];
  List<dynamic> _gems = [];
  bool _loading = true;
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab < 0
        ? 0
        : widget.initialTab > 1
            ? 1
            : widget.initialTab;
    _load();
  }

  Future<void> _load() async {
    final result = await Future.wait<dynamic>([
      WalletService.getCoinPacks(),
      WalletService.getGemPacks(),
    ]);

    if (!mounted) return;
    setState(() {
      _coins = result[0] as List<dynamic>;
      _gems = result[1] as List<dynamic>;
      _loading = false;
    });
  }

  Future<void> _purchase(Map<String, dynamic> pack, bool isGem) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm purchase'),
        content: Text(
          'Buy ${pack['name']} for \$${(pack['price'] as num).toStringAsFixed(2)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Buy'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final response = isGem
        ? await WalletService.purchaseGems(pack['id'].toString())
        : await WalletService.purchaseCoins(pack['id'].toString());
    if (!mounted) return;

    if (response == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Purchase failed.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    await context.read<AuthProvider>().refreshBalance();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${pack['name']} added successfully.'),
        backgroundColor: AppColors.successGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final data = _tab == 0 ? _coins : _gems;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(child: _tabButton(context, 0, 'Coins')),
              const SizedBox(width: 8),
              Expanded(child: _tabButton(context, 1, 'Gems')),
            ],
          ),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: data.length,
              itemBuilder: (context, index) {
                final pack = Map<String, dynamic>.from(data[index] as Map);
                final isGem = _tab == 1;
                final amount = isGem ? pack['gems'] : pack['coins'];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor:
                              (isGem ? const Color(0xFF8B5CF6) : Colors.amber)
                                  .withValues(alpha: 0.14),
                          child: Icon(
                            isGem
                                ? Icons.diamond_rounded
                                : Icons.monetization_on_rounded,
                            color: isGem
                                ? const Color(0xFF8B5CF6)
                                : Colors.amber.shade800,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pack['name'].toString(),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('$amount ${isGem ? 'gems' : 'coins'}'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 86),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '\$${(pack['price'] as num).toStringAsFixed(2)}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 32,
                                child: FilledButton(
                                  onPressed: () => _purchase(pack, isGem),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    minimumSize: const Size(74, 32),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: const Text('Buy'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _tabButton(BuildContext context, int value, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _tab == value;
    return InkWell(
      onTap: () => setState(() => _tab = value),
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
