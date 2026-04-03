import 'package:flutter/material.dart';

import 'level_progress_model.dart';
import 'shop_models.dart';
import 'vip_model.dart';
import '../utils/vip_tier_style.dart';

class UserModel {
  final String id;
  final String uid;
  final String username;
  final String? email;
  final String avatar;
  final String? coverPhoto;
  final String? bio;
  final String region;
  final int level;
  final int xp;
  final int coins;
  final int gems;
  final int vipLevel;
  final VipMembershipSnapshot vipMembership;
  final LevelProgressSnapshot levelInfo;
  final UserShopProfile shopProfile;
  final bool isOnline;
  final bool isGuest;
  final String permanentRoomId;
  final bool hasPermanentRoom;
  final DateTime? lastActive;
  final Map<String, dynamic>? gameStats;
  final List<dynamic> badges;
  final Map<String, dynamic> stats;

  const UserModel({
    required this.id,
    required this.uid,
    required this.username,
    this.email,
    required this.avatar,
    this.coverPhoto,
    this.bio,
    required this.region,
    required this.level,
    required this.xp,
    required this.coins,
    required this.gems,
    required this.vipLevel,
    required this.vipMembership,
    required this.levelInfo,
    required this.shopProfile,
    required this.isOnline,
    required this.isGuest,
    this.permanentRoomId = '',
    this.hasPermanentRoom = false,
    this.lastActive,
    this.gameStats,
    required this.badges,
    required this.stats,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
        uid: json['uid']?.toString() ?? '',
        username: json['username'] ?? 'User',
        email: json['email'],
        avatar: json['avatar'] ?? '',
        coverPhoto: json['coverPhoto'],
        bio: json['bio'],
        region: json['region']?.toString() ?? 'Global',
        level: _toInt(json['level']) ?? 1,
        xp: _toInt(json['xp']) ?? 0,
        coins: _toInt(json['coins']) ?? 0,
        gems: _toInt(json['gems']) ?? 0,
        vipLevel: _toInt(json['vipLevel']) ?? 0,
        vipMembership: VipMembershipSnapshot.fromJson(
          json['vipMembership'] is Map
              ? Map<String, dynamic>.from(json['vipMembership'] as Map)
              : null,
        ),
        levelInfo: LevelProgressSnapshot.fromRoot(json),
        shopProfile: UserShopProfile.fromJson(json['shopProfile']),
        isOnline:
            json['status']?['isOnline'] == true || json['isOnline'] == true,
        isGuest: json['isGuest'] == true,
        permanentRoomId: json['permanentRoomId']?.toString() ?? '',
        hasPermanentRoom: json['hasPermanentRoom'] == true ||
            ((json['permanentRoomId']?.toString() ?? '').isNotEmpty),
        lastActive: json['status']?['lastActive'] != null
            ? DateTime.tryParse(json['status']['lastActive'].toString())
            : null,
        gameStats: json['gameStats'] is Map
            ? Map<String, dynamic>.from(json['gameStats'])
            : null,
        badges: json['badges'] is List ? List.from(json['badges']) : [],
        stats: json['stats'] is Map
            ? Map<String, dynamic>.from(json['stats'])
            : {},
      );

  UserModel copyWith({
    String? id,
    String? uid,
    String? username,
    String? email,
    String? avatar,
    String? coverPhoto,
    String? bio,
    String? region,
    int? level,
    int? xp,
    int? coins,
    int? gems,
    int? vipLevel,
    VipMembershipSnapshot? vipMembership,
    LevelProgressSnapshot? levelInfo,
    UserShopProfile? shopProfile,
    bool? isOnline,
    bool? isGuest,
    String? permanentRoomId,
    bool? hasPermanentRoom,
    DateTime? lastActive,
    Map<String, dynamic>? gameStats,
    List<dynamic>? badges,
    Map<String, dynamic>? stats,
  }) =>
      UserModel(
        id: id ?? this.id,
        uid: uid ?? this.uid,
        username: username ?? this.username,
        email: email ?? this.email,
        avatar: avatar ?? this.avatar,
        coverPhoto: coverPhoto ?? this.coverPhoto,
        bio: bio ?? this.bio,
        region: region ?? this.region,
        level: level ?? this.level,
        xp: xp ?? this.xp,
        coins: coins ?? this.coins,
        gems: gems ?? this.gems,
        vipLevel: vipLevel ?? this.vipLevel,
        vipMembership: vipMembership ?? this.vipMembership,
        levelInfo: levelInfo ??
            LevelProgressSnapshot.fromLevel(
              level: level ?? this.level,
              xp: xp ?? this.xp,
              levelMilestoneTier: (level ?? this.level) == this.level &&
                      (xp ?? this.xp) == this.xp
                  ? this.levelInfo.milestoneTier.key
                  : null,
              lastLevelUpdatedAt: this.levelInfo.lastLevelUpdatedAt,
            ),
        shopProfile: shopProfile ?? this.shopProfile,
        isOnline: isOnline ?? this.isOnline,
        isGuest: isGuest ?? this.isGuest,
        permanentRoomId: permanentRoomId ?? this.permanentRoomId,
        hasPermanentRoom: hasPermanentRoom ?? this.hasPermanentRoom,
        lastActive: lastActive ?? this.lastActive,
        gameStats: gameStats ?? this.gameStats,
        badges: badges ?? this.badges,
        stats: stats ?? this.stats,
      );

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'id': id,
        'uid': uid,
        'username': username,
        'email': email,
        'avatar': avatar,
        'coverPhoto': coverPhoto,
        'bio': bio,
        'region': region,
        'level': level,
        'xp': xp,
        'coins': coins,
        'gems': gems,
        'vipLevel': vipLevel,
        'vipMembership': {
          'activeTierId': vipMembership.activeTierId,
          'currentTierId': vipMembership.currentTierId,
          'currentTierLevel': vipMembership.currentTierLevel,
          'status': vipMembership.status,
          'isActive': vipMembership.isActive,
          'vipLevel': vipMembership.vipLevel,
          'vipStartAt': vipMembership.vipStartAt?.toIso8601String(),
          'vipExpireAt': vipMembership.vipExpireAt?.toIso8601String(),
          'autoRenew': vipMembership.autoRenew,
          'planDuration': vipMembership.planDuration,
          'purchaseSource': vipMembership.purchaseSource,
          'monthlyRewardLastClaimedAt':
              vipMembership.monthlyRewardLastClaimedAt?.toIso8601String(),
          'daysRemaining': vipMembership.daysRemaining,
          'secondsRemaining': vipMembership.secondsRemaining,
          'currentTier': {
            'tierId': vipMembership.currentTier.tierId,
            'level': vipMembership.currentTier.level,
            'displayOrder': vipMembership.currentTier.displayOrder,
            'displayName': vipMembership.currentTier.displayName,
            'shortLabel': vipMembership.currentTier.shortLabel,
            'badgeAsset': vipMembership.currentTier.badgeAsset,
            'nameColorStyle': {
              'token': vipMembership.currentTier.nameColorStyle.token,
              'label': vipMembership.currentTier.nameColorStyle.label,
              'colors': vipMembership.currentTier.nameColorStyle.colors,
            },
            'frameAsset': vipMembership.currentTier.frameAsset,
            'xpBoostPercent': vipMembership.currentTier.xpBoostPercent,
            'monthlyCoinReward': vipMembership.currentTier.monthlyCoinReward,
            'giftingPerkLevel': vipMembership.currentTier.giftingPerkLevel,
            'roomEntryEffect': vipMembership.currentTier.roomEntryEffect,
            'premiumEffects': vipMembership.currentTier.premiumEffects,
            'featureFlags': vipMembership.currentTier.featureFlags,
            'newlyUnlockedBenefits': vipMembership.currentTier
                .newlyUnlockedBenefits
                .map((benefit) => {
                      'id': benefit.id,
                      'category': benefit.category,
                      'title': benefit.title,
                      'description': benefit.description,
                    })
                .toList(growable: false),
            'cumulativeBenefits': vipMembership.currentTier.cumulativeBenefits
                .map((benefit) => {
                      'id': benefit.id,
                      'category': benefit.category,
                      'title': benefit.title,
                      'description': benefit.description,
                    })
                .toList(growable: false),
            'includedTierIds': vipMembership.currentTier.includedTierIds,
            'planOptions': vipMembership.currentTier.planOptions
                .map((plan) => {
                      'planDuration': plan.planDuration,
                      'label': plan.label,
                      'durationDays': plan.durationDays,
                      'priceCoins': plan.priceCoins,
                      'savingsPercent': plan.savingsPercent,
                      'recommendedTag': plan.recommendedTag,
                    })
                .toList(growable: false),
            'ui': {
              'accent': vipMembership.currentTier.ui.accent,
              'gradient': vipMembership.currentTier.ui.gradient,
              'glow': vipMembership.currentTier.ui.glow,
            },
          },
          'activeTier': vipMembership.activeTier == null
              ? null
              : {
                  'tierId': vipMembership.activeTier!.tierId,
                  'level': vipMembership.activeTier!.level,
                  'displayOrder': vipMembership.activeTier!.displayOrder,
                  'displayName': vipMembership.activeTier!.displayName,
                  'shortLabel': vipMembership.activeTier!.shortLabel,
                  'badgeAsset': vipMembership.activeTier!.badgeAsset,
                  'nameColorStyle': {
                    'token': vipMembership.activeTier!.nameColorStyle.token,
                    'label': vipMembership.activeTier!.nameColorStyle.label,
                    'colors': vipMembership.activeTier!.nameColorStyle.colors,
                  },
                  'frameAsset': vipMembership.activeTier!.frameAsset,
                  'xpBoostPercent': vipMembership.activeTier!.xpBoostPercent,
                  'monthlyCoinReward':
                      vipMembership.activeTier!.monthlyCoinReward,
                  'giftingPerkLevel':
                      vipMembership.activeTier!.giftingPerkLevel,
                  'roomEntryEffect': vipMembership.activeTier!.roomEntryEffect,
                  'premiumEffects': vipMembership.activeTier!.premiumEffects,
                  'featureFlags': vipMembership.activeTier!.featureFlags,
                  'newlyUnlockedBenefits': vipMembership
                      .activeTier!.newlyUnlockedBenefits
                      .map((benefit) => {
                            'id': benefit.id,
                            'category': benefit.category,
                            'title': benefit.title,
                            'description': benefit.description,
                          })
                      .toList(growable: false),
                  'cumulativeBenefits': vipMembership.activeTier!.cumulativeBenefits
                      .map((benefit) => {
                            'id': benefit.id,
                            'category': benefit.category,
                            'title': benefit.title,
                            'description': benefit.description,
                          })
                      .toList(growable: false),
                  'includedTierIds': vipMembership.activeTier!.includedTierIds,
                  'planOptions': vipMembership.activeTier!.planOptions
                      .map((plan) => {
                            'planDuration': plan.planDuration,
                            'label': plan.label,
                            'durationDays': plan.durationDays,
                            'priceCoins': plan.priceCoins,
                            'savingsPercent': plan.savingsPercent,
                            'recommendedTag': plan.recommendedTag,
                          })
                      .toList(growable: false),
                  'ui': {
                    'accent': vipMembership.activeTier!.ui.accent,
                    'gradient': vipMembership.activeTier!.ui.gradient,
                    'glow': vipMembership.activeTier!.ui.glow,
                  },
                },
          'canClaimMonthlyReward': vipMembership.canClaimMonthlyReward,
          'monthlyRewardAmount': vipMembership.monthlyRewardAmount,
          'nextRewardAt': vipMembership.nextRewardAt?.toIso8601String(),
        },
        'levelMilestoneTier': levelInfo.milestoneTier.key,
        'lastLevelUpdatedAt': levelInfo.lastLevelUpdatedAt?.toIso8601String(),
        'levelInfo': levelInfo.toJson(),
        'shopProfile': shopProfile.toJson(),
        'status': {
          'isOnline': isOnline,
          'lastActive': lastActive?.toIso8601String(),
        },
        'isGuest': isGuest,
        'permanentRoomId': permanentRoomId,
        'hasPermanentRoom': hasPermanentRoom,
        if (gameStats != null) 'gameStats': gameStats,
        'badges': badges,
        'stats': stats,
      };

  Color get vipColor {
    return VipTierStyles.fromMembership(vipMembership, fallbackLevel: vipLevel)
        .accent;
  }
}
