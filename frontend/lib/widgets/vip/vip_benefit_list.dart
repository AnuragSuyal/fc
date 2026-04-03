import 'package:flutter/material.dart';

import '../../models/vip_model.dart';

class VipBenefitList extends StatelessWidget {
  final VipTierModel tier;
  final String title;

  const VipBenefitList({
    super.key,
    required this.tier,
    this.title = 'What You Unlock Instantly',
  });

  @override
  Widget build(BuildContext context) {
    final accent = _parseColor(tier.ui.accent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 12),
        ...tier.newlyUnlockedBenefits.map(
          (benefit) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: accent.withValues(alpha: 0.08),
              border: Border.all(
                color: accent.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconForCategory(benefit.category),
                    size: 18,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        benefit.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        benefit.description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'identity':
        return Icons.workspace_premium_rounded;
      case 'profile':
        return Icons.person_rounded;
      case 'progression':
        return Icons.trending_up_rounded;
      case 'room':
        return Icons.graphic_eq_rounded;
      case 'gifting':
        return Icons.card_giftcard_rounded;
      case 'access':
        return Icons.lock_open_rounded;
      case 'cosmetics':
        return Icons.auto_awesome_rounded;
      case 'rewards':
        return Icons.wallet_giftcard_rounded;
      default:
        return Icons.star_rounded;
    }
  }

  static Color _parseColor(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ??
        0x8B5CF6;
    return Color(value + 0xFF000000);
  }
}
