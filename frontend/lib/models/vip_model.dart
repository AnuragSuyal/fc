class VipBenefit {
  final String id;
  final String category;
  final String title;
  final String description;

  const VipBenefit({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
  });

  factory VipBenefit.fromJson(Map<String, dynamic> json) => VipBenefit(
        id: json['id']?.toString() ?? '',
        category: json['category']?.toString() ?? 'identity',
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
      );
}

class VipPlanOption {
  final String planDuration;
  final String label;
  final int durationDays;
  final int priceCoins;
  final int savingsPercent;
  final String recommendedTag;

  const VipPlanOption({
    required this.planDuration,
    required this.label,
    required this.durationDays,
    required this.priceCoins,
    required this.savingsPercent,
    required this.recommendedTag,
  });

  factory VipPlanOption.fromJson(Map<String, dynamic> json) => VipPlanOption(
        planDuration: json['planDuration']?.toString() ?? 'monthly',
        label: json['label']?.toString() ?? 'Monthly',
        durationDays: _toInt(json['durationDays']) ?? 30,
        priceCoins: _toInt(json['priceCoins']) ?? 0,
        savingsPercent: _toInt(json['savingsPercent']) ?? 0,
        recommendedTag: json['recommendedTag']?.toString() ?? '',
      );
}

class VipTierUiModel {
  final String accent;
  final List<String> gradient;
  final String glow;

  const VipTierUiModel({
    required this.accent,
    required this.gradient,
    required this.glow,
  });

  factory VipTierUiModel.fromJson(Map<String, dynamic>? json) => VipTierUiModel(
        accent: json?['accent']?.toString() ?? '#94A3B8',
        gradient: (json?['gradient'] as List? ?? const [])
            .map((entry) => entry.toString())
            .toList(growable: false),
        glow: json?['glow']?.toString() ?? '#94A3B8',
      );
}

class VipNameColorStyle {
  final String token;
  final String label;
  final List<String> colors;

  const VipNameColorStyle({
    required this.token,
    required this.label,
    required this.colors,
  });

  factory VipNameColorStyle.fromJson(Map<String, dynamic>? json) =>
      VipNameColorStyle(
        token: json?['token']?.toString() ?? 'default',
        label: json?['label']?.toString() ?? 'Default',
        colors: (json?['colors'] as List? ?? const [])
            .map((entry) => entry.toString())
            .toList(growable: false),
      );
}

class VipTierModel {
  final String tierId;
  final int level;
  final int displayOrder;
  final String displayName;
  final String shortLabel;
  final String badgeAsset;
  final VipNameColorStyle nameColorStyle;
  final String frameAsset;
  final int xpBoostPercent;
  final int monthlyCoinReward;
  final int giftingPerkLevel;
  final String roomEntryEffect;
  final List<String> premiumEffects;
  final Map<String, dynamic> featureFlags;
  final List<VipBenefit> newlyUnlockedBenefits;
  final List<VipBenefit> cumulativeBenefits;
  final List<String> includedTierIds;
  final List<VipPlanOption> planOptions;
  final VipTierUiModel ui;
  final bool isCurrent;
  final bool isSelected;
  final String upgradeState;

  const VipTierModel({
    required this.tierId,
    required this.level,
    required this.displayOrder,
    required this.displayName,
    required this.shortLabel,
    required this.badgeAsset,
    required this.nameColorStyle,
    required this.frameAsset,
    required this.xpBoostPercent,
    required this.monthlyCoinReward,
    required this.giftingPerkLevel,
    required this.roomEntryEffect,
    required this.premiumEffects,
    required this.featureFlags,
    required this.newlyUnlockedBenefits,
    required this.cumulativeBenefits,
    required this.includedTierIds,
    required this.planOptions,
    required this.ui,
    this.isCurrent = false,
    this.isSelected = false,
    this.upgradeState = 'unlock',
  });

  factory VipTierModel.fromJson(Map<String, dynamic> json) => VipTierModel(
        tierId: json['tierId']?.toString() ?? '',
        level: _toInt(json['level']) ?? 0,
        displayOrder: _toInt(json['displayOrder']) ?? 0,
        displayName: json['displayName']?.toString() ?? 'Free',
        shortLabel: json['shortLabel']?.toString() ?? 'Free',
        badgeAsset: json['badgeAsset']?.toString() ?? '',
        nameColorStyle: VipNameColorStyle.fromJson(
          json['nameColorStyle'] is Map
              ? Map<String, dynamic>.from(json['nameColorStyle'] as Map)
              : null,
        ),
        frameAsset: json['frameAsset']?.toString() ?? '',
        xpBoostPercent: _toInt(json['xpBoostPercent']) ?? 0,
        monthlyCoinReward: _toInt(json['monthlyCoinReward']) ?? 0,
        giftingPerkLevel: _toInt(json['giftingPerkLevel']) ?? 0,
        roomEntryEffect: json['roomEntryEffect']?.toString() ?? '',
        premiumEffects: (json['premiumEffects'] as List? ?? const [])
            .map((entry) => entry.toString())
            .toList(growable: false),
        featureFlags: json['featureFlags'] is Map
            ? Map<String, dynamic>.from(json['featureFlags'] as Map)
            : const <String, dynamic>{},
        newlyUnlockedBenefits: (json['newlyUnlockedBenefits'] as List? ??
                const [])
            .whereType<Map>()
            .map((entry) => VipBenefit.fromJson(Map<String, dynamic>.from(entry)))
            .toList(growable: false),
        cumulativeBenefits:
            (json['cumulativeBenefits'] as List? ?? const [])
                .whereType<Map>()
                .map(
                    (entry) => VipBenefit.fromJson(Map<String, dynamic>.from(entry)))
                .toList(growable: false),
        includedTierIds: (json['includedTierIds'] as List? ?? const [])
            .map((entry) => entry.toString())
            .toList(growable: false),
        planOptions: (json['planOptions'] as List? ?? const [])
            .whereType<Map>()
            .map(
                (entry) => VipPlanOption.fromJson(Map<String, dynamic>.from(entry)))
            .toList(growable: false),
        ui: VipTierUiModel.fromJson(json['ui'] is Map
            ? Map<String, dynamic>.from(json['ui'] as Map)
            : null),
        isCurrent: json['isCurrent'] == true,
        isSelected: json['isSelected'] == true,
        upgradeState: json['upgradeState']?.toString() ?? 'unlock',
      );
}

class VipComparisonValue {
  final String tierId;
  final dynamic value;

  const VipComparisonValue({
    required this.tierId,
    required this.value,
  });

  factory VipComparisonValue.fromJson(Map<String, dynamic> json) =>
      VipComparisonValue(
        tierId: json['tierId']?.toString() ?? '',
        value: json['value'],
      );
}

class VipComparisonRow {
  final String key;
  final String label;
  final String type;
  final List<VipComparisonValue> values;

  const VipComparisonRow({
    required this.key,
    required this.label,
    required this.type,
    required this.values,
  });

  factory VipComparisonRow.fromJson(Map<String, dynamic> json) =>
      VipComparisonRow(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        type: json['type']?.toString() ?? 'text',
        values: (json['values'] as List? ?? const [])
            .whereType<Map>()
            .map((entry) =>
                VipComparisonValue.fromJson(Map<String, dynamic>.from(entry)))
            .toList(growable: false),
      );
}

class VipCatalogModel {
  final List<VipTierModel> tiers;
  final List<VipComparisonRow> comparisonRows;
  final List<VipPlanOption> planDefinitions;

  const VipCatalogModel({
    required this.tiers,
    required this.comparisonRows,
    required this.planDefinitions,
  });

  factory VipCatalogModel.fromJson(Map<String, dynamic> json) => VipCatalogModel(
        tiers: (json['tiers'] as List? ?? const [])
            .whereType<Map>()
            .map((entry) => VipTierModel.fromJson(Map<String, dynamic>.from(entry)))
            .toList(growable: false),
        comparisonRows: ((json['comparison']?['rows'] as List?) ?? const [])
            .whereType<Map>()
            .map((entry) =>
                VipComparisonRow.fromJson(Map<String, dynamic>.from(entry)))
            .toList(growable: false),
        planDefinitions: (json['planDefinitions'] as List? ?? const [])
            .whereType<Map>()
            .map(
                (entry) => VipPlanOption.fromJson(Map<String, dynamic>.from(entry)))
            .toList(growable: false),
      );
}

class VipMembershipSnapshot {
  final String activeTierId;
  final String currentTierId;
  final int currentTierLevel;
  final String status;
  final bool isActive;
  final int vipLevel;
  final DateTime? vipStartAt;
  final DateTime? vipExpireAt;
  final bool autoRenew;
  final String planDuration;
  final String purchaseSource;
  final DateTime? monthlyRewardLastClaimedAt;
  final int daysRemaining;
  final int secondsRemaining;
  final VipTierModel currentTier;
  final VipTierModel? activeTier;
  final bool canClaimMonthlyReward;
  final int monthlyRewardAmount;
  final DateTime? nextRewardAt;

  const VipMembershipSnapshot({
    required this.activeTierId,
    required this.currentTierId,
    required this.currentTierLevel,
    required this.status,
    required this.isActive,
    required this.vipLevel,
    required this.vipStartAt,
    required this.vipExpireAt,
    required this.autoRenew,
    required this.planDuration,
    required this.purchaseSource,
    required this.monthlyRewardLastClaimedAt,
    required this.daysRemaining,
    required this.secondsRemaining,
    required this.currentTier,
    required this.activeTier,
    required this.canClaimMonthlyReward,
    required this.monthlyRewardAmount,
    required this.nextRewardAt,
  });

  factory VipMembershipSnapshot.fromJson(Map<String, dynamic>? json) {
    final currentTierJson = json?['currentTier'] is Map
        ? Map<String, dynamic>.from(json!['currentTier'] as Map)
        : const <String, dynamic>{
            'tierId': 'free',
            'level': 0,
            'displayOrder': 0,
            'displayName': 'Free',
            'shortLabel': 'Free',
            'badgeAsset': '',
            'nameColorStyle': {
              'token': 'default',
              'label': 'Default',
              'colors': ['#CBD5E1', '#64748B']
            },
            'frameAsset': '',
            'xpBoostPercent': 0,
            'monthlyCoinReward': 0,
            'giftingPerkLevel': 0,
            'roomEntryEffect': '',
            'premiumEffects': [],
            'featureFlags': {},
            'newlyUnlockedBenefits': [],
            'cumulativeBenefits': [],
            'includedTierIds': [],
            'planOptions': [],
            'ui': {
              'accent': '#94A3B8',
              'gradient': ['#111827', '#334155'],
              'glow': '#94A3B8'
            },
          };
    return VipMembershipSnapshot(
      activeTierId: json?['activeTierId']?.toString() ?? '',
      currentTierId: json?['currentTierId']?.toString() ?? 'free',
      currentTierLevel: _toInt(json?['currentTierLevel']) ?? 0,
      status: json?['status']?.toString() ?? 'inactive',
      isActive: json?['isActive'] == true,
      vipLevel: _toInt(json?['vipLevel']) ?? 0,
      vipStartAt: _parseDate(json?['vipStartAt']),
      vipExpireAt: _parseDate(json?['vipExpireAt']),
      autoRenew: json?['autoRenew'] == true,
      planDuration: json?['planDuration']?.toString() ?? 'monthly',
      purchaseSource: json?['purchaseSource']?.toString() ?? '',
      monthlyRewardLastClaimedAt:
          _parseDate(json?['monthlyRewardLastClaimedAt']),
      daysRemaining: _toInt(json?['daysRemaining']) ?? 0,
      secondsRemaining: _toInt(json?['secondsRemaining']) ?? 0,
      currentTier: VipTierModel.fromJson(currentTierJson),
      activeTier: json?['activeTier'] is Map
          ? VipTierModel.fromJson(
              Map<String, dynamic>.from(json!['activeTier'] as Map),
            )
          : null,
      canClaimMonthlyReward: json?['canClaimMonthlyReward'] == true,
      monthlyRewardAmount: _toInt(json?['monthlyRewardAmount']) ?? 0,
      nextRewardAt: _parseDate(json?['nextRewardAt']),
    );
  }

  bool get isExpired => status == 'expired';
}

class VipStatusModel {
  final VipMembershipSnapshot membership;
  final VipTierModel currentLevel;
  final VipTierModel? nextLevel;
  final List<VipComparisonRow> comparisonRows;
  final int totalSpent;

  const VipStatusModel({
    required this.membership,
    required this.currentLevel,
    required this.nextLevel,
    required this.comparisonRows,
    required this.totalSpent,
  });

  factory VipStatusModel.fromJson(Map<String, dynamic> json) => VipStatusModel(
        membership: VipMembershipSnapshot.fromJson(
          json['membership'] is Map
              ? Map<String, dynamic>.from(json['membership'] as Map)
              : null,
        ),
        currentLevel: VipTierModel.fromJson(
          json['currentLevel'] is Map
              ? Map<String, dynamic>.from(json['currentLevel'] as Map)
              : const <String, dynamic>{},
        ),
        nextLevel: json['nextLevel'] is Map
            ? VipTierModel.fromJson(
                Map<String, dynamic>.from(json['nextLevel'] as Map),
              )
            : null,
        comparisonRows: ((json['comparison']?['rows'] as List?) ?? const [])
            .whereType<Map>()
            .map((entry) =>
                VipComparisonRow.fromJson(Map<String, dynamic>.from(entry)))
            .toList(growable: false),
        totalSpent: _toInt(json['totalSpent']) ?? 0,
      );
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
