import 'package:flutter/material.dart';

import '../../models/vip_model.dart';
import 'vip_badge.dart';

class VipTierCard extends StatelessWidget {
  final VipTierModel tier;
  final bool selected;
  final VoidCallback? onTap;

  const VipTierCard({
    super.key,
    required this.tier,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _parseColor(tier.ui.accent);
    final gradient = tier.ui.gradient.isNotEmpty
        ? tier.ui.gradient.map(_parseColor).toList(growable: false)
        : <Color>[accent.withValues(alpha: 0.8), const Color(0xFF111827)];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 196,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: gradient.length >= 2 ? gradient : <Color>[gradient.first, accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: selected
              ? Colors.white.withValues(alpha: 0.72)
              : Colors.white.withValues(alpha: 0.12),
        ),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: accent.withValues(alpha: 0.24),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tier.displayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                if (tier.isCurrent)
                  _tag('Current', Colors.white, accent)
                else if (tier.upgradeState == 'upgrade')
                  _tag('Upgrade', accent, Colors.white)
                else if (tier.upgradeState == 'locked_lower')
                  _tag('Past Tier', Colors.white70, Colors.white12),
              ],
            ),
            const SizedBox(height: 14),
            Center(
              child: VipBadge(
                membership: VipMembershipSnapshot.fromJson({
                  'currentTier': {
                    'tierId': tier.tierId,
                    'level': tier.level,
                    'displayOrder': tier.displayOrder,
                    'displayName': tier.displayName,
                    'shortLabel': tier.shortLabel,
                    'badgeAsset': tier.badgeAsset,
                    'nameColorStyle': {
                      'token': tier.nameColorStyle.token,
                      'label': tier.nameColorStyle.label,
                      'colors': tier.nameColorStyle.colors,
                    },
                    'frameAsset': tier.frameAsset,
                    'xpBoostPercent': tier.xpBoostPercent,
                    'monthlyCoinReward': tier.monthlyCoinReward,
                    'giftingPerkLevel': tier.giftingPerkLevel,
                    'roomEntryEffect': tier.roomEntryEffect,
                    'premiumEffects': tier.premiumEffects,
                    'featureFlags': tier.featureFlags,
                    'newlyUnlockedBenefits': [],
                    'cumulativeBenefits': [],
                    'includedTierIds': tier.includedTierIds,
                    'planOptions': [],
                    'ui': {
                      'accent': tier.ui.accent,
                      'gradient': tier.ui.gradient,
                      'glow': tier.ui.glow,
                    },
                  },
                  'currentTierId': tier.tierId,
                  'activeTierId': tier.tierId,
                  'status': 'active',
                  'isActive': true,
                  'vipLevel': tier.level,
                }),
                size: VipBadgeSize.large,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${tier.xpBoostPercent}% XP boost',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${tier.monthlyCoinReward} monthly coins',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              tier.newlyUnlockedBenefits.isNotEmpty
                  ? tier.newlyUnlockedBenefits.first.title
                  : 'Premium identity',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, Color foreground, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  static Color _parseColor(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ??
        0x334155;
    return Color(value + 0xFF000000);
  }
}
