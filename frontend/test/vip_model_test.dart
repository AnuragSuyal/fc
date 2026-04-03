import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/vip_model.dart';
import 'package:frontend/utils/vip_tier_style.dart';

void main() {
  test('vip catalog and membership snapshot parse backend payloads', () {
    final catalog = VipCatalogModel.fromJson({
      'tiers': [
        {
          'tierId': 'vip1',
          'level': 1,
          'displayOrder': 1,
          'displayName': 'VIP 1',
          'shortLabel': 'VIP 1',
          'badgeAsset': 'badge_vip1',
          'nameColorStyle': {
            'token': 'green',
            'label': 'Green',
            'colors': ['#B9FF60', '#4FD53B'],
          },
          'frameAsset': 'vip_frame_basic_green',
          'xpBoostPercent': 5,
          'monthlyCoinReward': 400,
          'giftingPerkLevel': 0,
          'roomEntryEffect': 'premium_status_glow',
          'premiumEffects': ['basic_identity_glow'],
          'featureFlags': {'vipChatBubble': true},
          'newlyUnlockedBenefits': [
            {
              'id': 'vip1_badge',
              'category': 'identity',
              'title': 'Unique VIP 1 badge',
              'description': 'Show your premium identity.',
            },
          ],
          'cumulativeBenefits': [],
          'includedTierIds': ['vip1'],
          'planOptions': [
            {
              'planDuration': 'monthly',
              'label': 'Monthly',
              'durationDays': 30,
              'priceCoins': 499,
              'savingsPercent': 0,
              'recommendedTag': 'Flexible',
            },
          ],
          'ui': {
            'accent': '#7EF24B',
            'gradient': ['#123B23', '#1E7A40', '#9BE15D'],
            'glow': '#A3FF5A',
          },
        },
      ],
      'comparison': {
        'rows': [
          {
            'key': 'xpBoostPercent',
            'label': 'XP Boost',
            'type': 'number',
            'values': [
              {'tierId': 'vip1', 'value': 5},
            ],
          },
        ],
      },
      'planDefinitions': [
        {
          'planDuration': 'monthly',
          'label': 'Monthly',
          'durationDays': 30,
          'priceCoins': 499,
          'savingsPercent': 0,
          'recommendedTag': 'Flexible',
        },
      ],
    });

    final membership = VipMembershipSnapshot.fromJson({
      'activeTierId': 'vip1',
      'currentTierId': 'vip1',
      'currentTierLevel': 1,
      'status': 'active',
      'isActive': true,
      'vipLevel': 1,
      'vipStartAt': '2026-03-01T00:00:00.000Z',
      'vipExpireAt': '2026-04-01T00:00:00.000Z',
      'autoRenew': true,
      'planDuration': 'monthly',
      'purchaseSource': 'coins',
      'monthlyRewardLastClaimedAt': null,
      'daysRemaining': 2,
      'secondsRemaining': 172800,
      'currentTier': catalog.tiers.first.toMembershipJson,
      'activeTier': catalog.tiers.first.toMembershipJson,
      'canClaimMonthlyReward': true,
      'monthlyRewardAmount': 400,
      'nextRewardAt': null,
    });

    expect(catalog.tiers.single.displayName, 'VIP 1');
    expect(catalog.comparisonRows.single.label, 'XP Boost');
    expect(membership.isActive, isTrue);
    expect(membership.currentTier.displayName, 'VIP 1');
    expect(membership.monthlyRewardAmount, 400);
  });

  test('vip tier style resolver maps asset and prestige colors correctly', () {
    final diamond = VipTierStyles.fromTierId('diamond');
    final supreme = VipTierStyles.fromTierId('supreme');
    final fallback = VipTierStyles.fromLevel(0);

    expect(diamond.badgeAssetPath, 'assets/vip_badges/badge_diamond.png');
    expect(diamond.displayName, 'Diamond');
    expect(supreme.badgeAssetPath, 'assets/vip_badges/badge_supreme.png');
    expect(supreme.rainbow, isTrue);
    expect(fallback.isFree, isTrue);
  });
}

extension on VipTierModel {
  Map<String, dynamic> get toMembershipJson => {
        'tierId': tierId,
        'level': level,
        'displayOrder': displayOrder,
        'displayName': displayName,
        'shortLabel': shortLabel,
        'badgeAsset': badgeAsset,
        'nameColorStyle': {
          'token': nameColorStyle.token,
          'label': nameColorStyle.label,
          'colors': nameColorStyle.colors,
        },
        'frameAsset': frameAsset,
        'xpBoostPercent': xpBoostPercent,
        'monthlyCoinReward': monthlyCoinReward,
        'giftingPerkLevel': giftingPerkLevel,
        'roomEntryEffect': roomEntryEffect,
        'premiumEffects': premiumEffects,
        'featureFlags': featureFlags,
        'newlyUnlockedBenefits': newlyUnlockedBenefits
            .map(
              (benefit) => {
                'id': benefit.id,
                'category': benefit.category,
                'title': benefit.title,
                'description': benefit.description,
              },
            )
            .toList(growable: false),
        'cumulativeBenefits': cumulativeBenefits
            .map(
              (benefit) => {
                'id': benefit.id,
                'category': benefit.category,
                'title': benefit.title,
                'description': benefit.description,
              },
            )
            .toList(growable: false),
        'includedTierIds': includedTierIds,
        'planOptions': planOptions
            .map(
              (plan) => {
                'planDuration': plan.planDuration,
                'label': plan.label,
                'durationDays': plan.durationDays,
                'priceCoins': plan.priceCoins,
                'savingsPercent': plan.savingsPercent,
                'recommendedTag': plan.recommendedTag,
              },
            )
            .toList(growable: false),
        'ui': {
          'accent': ui.accent,
          'gradient': ui.gradient,
          'glow': ui.glow,
        },
      };
}
