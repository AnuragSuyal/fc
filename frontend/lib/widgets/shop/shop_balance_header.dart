import 'package:flutter/material.dart';

import '../../models/shop_models.dart';
import '../../theme/app_theme.dart';
import '../currency_icon.dart';
import 'shop_item_artwork.dart';

class ShopBalanceHeader extends StatelessWidget {
  final Map<String, dynamic> balance;
  final ShopInventorySummary inventorySummary;
  final UserShopProfile shopProfile;
  final ShopCatalogItem? firstPurchaseReward;

  const ShopBalanceHeader({
    super.key,
    required this.balance,
    required this.inventorySummary,
    required this.shopProfile,
    required this.firstPurchaseReward,
  });

  @override
  Widget build(BuildContext context) {
    final mood = context.mood;
    final coins = _toInt(balance['coins']);
    final level = _toInt(balance['level']);
    final xp = _toInt(balance['xp']);
    final boosts = _activeBoostLabels();
    final unlockedReward = shopProfile.firstShopPurchaseAt != null;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF191B2A),
            Color(0xFF0B0F18),
            Color(0xFF261A3A),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: mood.shadow,
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Style Shop',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Account-bound cosmetics, boosts, collectibles, and limited finds.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CurrencyIcon.coins(size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '$coins',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MetricPill(
                  label: 'Owned',
                  value: '${inventorySummary.ownedEntries}',
                  accent: const Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricPill(
                  label: 'Equipped',
                  value: '${inventorySummary.equippedEntries}',
                  accent: const Color(0xFF8B5CF6),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricPill(
                  label: 'Level',
                  value: 'Lv $level',
                  accent: const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricPill(
                  label: 'XP',
                  value: '$xp',
                  accent: const Color(0xFF22C55E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (boosts.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: boosts
                  .map(
                    (label) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.86),
                                ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 16),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 56,
                  child: ShopItemArtwork(
                    itemId: firstPurchaseReward?.itemId ?? '',
                    previewStyle: firstPurchaseReward?.previewStyle ?? const {},
                    rarity: firstPurchaseReward?.rarity ?? 'rare',
                    width: 72,
                    height: 56,
                    borderRadius: BorderRadius.circular(18),
                    iconSize: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        unlockedReward
                            ? 'First purchase bonus unlocked'
                            : 'First purchase bonus ready',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        unlockedReward
                            ? '${firstPurchaseReward?.itemName ?? 'Bonus reward'} is already in your vault.'
                            : 'Buy any shop item to claim ${firstPurchaseReward?.itemName ?? 'a bonus collectible'} instantly.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _activeBoostLabels() {
    final boosts = <String>[];
    final activeBoosts = shopProfile.activeBoosts;
    final xpBoostItemId = activeBoosts['xpBoostItemId']?.toString() ?? '';
    final profileHighlightItemId =
        activeBoosts['profileHighlightItemId']?.toString() ?? '';
    final discoverBoostItemId =
        activeBoosts['discoverBoostItemId']?.toString() ?? '';
    final voiceAuraBoostItemId =
        activeBoosts['voiceAuraBoostItemId']?.toString() ?? '';

    if (xpBoostItemId.isNotEmpty) {
      final multiplier = _toDouble(activeBoosts['xpBoostMultiplier']);
      boosts.add('XP ${multiplier.toStringAsFixed(multiplier == 2 ? 0 : 1)}x');
    }
    if (profileHighlightItemId.isNotEmpty) {
      boosts.add('Profile highlight');
    }
    if (discoverBoostItemId.isNotEmpty) {
      boosts.add('Discover boost');
    }
    if (voiceAuraBoostItemId.isNotEmpty) {
      boosts.add('Voice aura');
    }

    return boosts;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 1;
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _MetricPill({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: accent.withValues(alpha: 0.96),
                ),
          ),
        ],
      ),
    );
  }
}
