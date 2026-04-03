import 'package:flutter/material.dart';

import '../../models/vip_model.dart';
import '../../widgets/level_badge.dart';
import '../../widgets/user_avatar.dart';
import 'vip_badge.dart';
import 'vip_name_text.dart';

class VipIdentityPreview extends StatelessWidget {
  final VipTierModel tier;
  final String username;
  final int level;

  const VipIdentityPreview({
    super.key,
    required this.tier,
    required this.username,
    this.level = 27,
  });

  @override
  Widget build(BuildContext context) {
    final membership = VipMembershipSnapshot.fromJson({
      'activeTierId': tier.tierId,
      'currentTierId': tier.tierId,
      'currentTierLevel': tier.level,
      'status': 'active',
      'isActive': true,
      'vipLevel': tier.level,
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
        'newlyUnlockedBenefits': const [],
        'cumulativeBenefits': const [],
        'includedTierIds': tier.includedTierIds,
        'planOptions': const [],
        'ui': {
          'accent': tier.ui.accent,
          'gradient': tier.ui.gradient,
          'glow': tier.ui.glow,
        },
      },
      'activeTier': {
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
        'newlyUnlockedBenefits': const [],
        'cumulativeBenefits': const [],
        'includedTierIds': tier.includedTierIds,
        'planOptions': const [],
        'ui': {
          'accent': tier.ui.accent,
          'gradient': tier.ui.gradient,
          'glow': tier.ui.glow,
        },
      },
    });

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live Identity Preview',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: tier.ui.gradient.map(_parseColor).toList(growable: false),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                UserAvatar(
                  username: username,
                  radius: 28,
                  vipMembership: membership,
                  vipLevel: tier.level,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VipNameText(
                        username,
                        membership: membership,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tier.displayName} room card preview',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                VipBadge(
                  membership: membership,
                  size: VipBadgeSize.medium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              LevelBadge(
                level: level,
                size: LevelBadgeSize.small,
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: _parseColor(tier.ui.accent).withValues(alpha: 0.16),
                ),
                child: Text(
                  tier.nameColorStyle.label,
                  style: TextStyle(
                    color: _parseColor(tier.ui.accent),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _parseColor(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ??
        0x8B5CF6;
    return Color(value + 0xFF000000);
  }
}
