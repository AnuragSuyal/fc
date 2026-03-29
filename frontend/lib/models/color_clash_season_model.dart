import 'color_clash_model_utils.dart';

class ColorClashSeasonSummaryModel {
  const ColorClashSeasonSummaryModel({
    required this.season,
    required this.leaderboardPreview,
    required this.rewardPreview,
    this.userProgress,
    this.userRank,
    this.eligibility,
  });

  final ColorClashSeasonModel? season;
  final List<ColorClashLeaderboardEntryModel> leaderboardPreview;
  final List<Map<String, dynamic>> rewardPreview;
  final ColorClashSeasonProgressModel? userProgress;
  final ColorClashLeaderboardUserRankModel? userRank;
  final ColorClashEligibilityModel? eligibility;

  factory ColorClashSeasonSummaryModel.fromJson(Map<String, dynamic> json) {
    return ColorClashSeasonSummaryModel(
      season: json['season'] == null
          ? null
          : ColorClashSeasonModel.fromJson(asMap(json['season'])),
      leaderboardPreview: asMapList(json['leaderboardPreview'])
          .map(ColorClashLeaderboardEntryModel.fromJson)
          .toList(growable: false),
      rewardPreview: asMapList(json['rewardPreview']),
      userProgress: json['userProgress'] == null
          ? null
          : ColorClashSeasonProgressModel.fromJson(asMap(json['userProgress'])),
      userRank: json['userRank'] == null
          ? null
          : ColorClashLeaderboardUserRankModel.fromJson(
              asMap(json['userRank'])),
      eligibility: json['eligibility'] == null
          ? null
          : ColorClashEligibilityModel.fromJson(asMap(json['eligibility'])),
    );
  }
}

class ColorClashSeasonModel {
  const ColorClashSeasonModel({
    required this.id,
    required this.key,
    required this.name,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.finalizeAt,
    required this.placementMatches,
    required this.rankedEnabled,
    required this.tiers,
    required this.ratingConfig,
    required this.rewardPreview,
    required this.themeRotation,
  });

  final String id;
  final String key;
  final String name;
  final String status;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? finalizeAt;
  final int placementMatches;
  final bool rankedEnabled;
  final List<ColorClashTierModel> tiers;
  final ColorClashRatingConfigModel ratingConfig;
  final List<Map<String, dynamic>> rewardPreview;
  final List<String> themeRotation;

  factory ColorClashSeasonModel.fromJson(Map<String, dynamic> json) {
    final rawId =
        asId(json['id']).isNotEmpty ? asId(json['id']) : asId(json['_id']);
    return ColorClashSeasonModel(
      id: rawId,
      key: json['key']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Color Clash Season',
      status: json['status']?.toString() ?? 'upcoming',
      startsAt: asDateTime(json['startsAt']),
      endsAt: asDateTime(json['endsAt']),
      finalizeAt: asDateTime(json['finalizeAt']),
      placementMatches: asInt(json['placementMatches'], fallback: 0),
      rankedEnabled: asBool(json['rankedEnabled'], fallback: true),
      tiers: asMapList(json['tiers'])
          .map(ColorClashTierModel.fromJson)
          .toList(growable: false),
      ratingConfig:
          ColorClashRatingConfigModel.fromJson(asMap(json['ratingConfig'])),
      rewardPreview: asMapList(json['rewardPreview']),
      themeRotation: asStringList(json['themeRotation']),
    );
  }
}

class ColorClashTierModel {
  const ColorClashTierModel({
    required this.id,
    required this.name,
    required this.order,
    required this.minRating,
    required this.maxRating,
    required this.divisions,
    required this.starsPerDivision,
  });

  final String id;
  final String name;
  final int order;
  final int minRating;
  final int maxRating;
  final int divisions;
  final int starsPerDivision;

  factory ColorClashTierModel.fromJson(Map<String, dynamic> json) {
    return ColorClashTierModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      order: asInt(json['order'], fallback: 1),
      minRating: asInt(json['minRating']),
      maxRating: asInt(json['maxRating']),
      divisions: asInt(json['divisions'], fallback: 1),
      starsPerDivision: asInt(json['starsPerDivision'], fallback: 4),
    );
  }
}

class ColorClashRatingConfigModel {
  const ColorClashRatingConfigModel({
    required this.baseRating,
    required this.kFactor,
    required this.streakBonus,
    required this.placementMultiplier,
    required this.inactivityDecay,
  });

  final int baseRating;
  final int kFactor;
  final int streakBonus;
  final double placementMultiplier;
  final int inactivityDecay;

  factory ColorClashRatingConfigModel.fromJson(Map<String, dynamic> json) {
    return ColorClashRatingConfigModel(
      baseRating: asInt(json['baseRating'], fallback: 1000),
      kFactor: asInt(json['kFactor'], fallback: 32),
      streakBonus: asInt(json['streakBonus'], fallback: 4),
      placementMultiplier: asDouble(json['placementMultiplier'], fallback: 1.5),
      inactivityDecay: asInt(json['inactivityDecay']),
    );
  }
}

class ColorClashSeasonProgressModel {
  const ColorClashSeasonProgressModel({
    required this.seasonId,
    required this.userId,
    required this.rating,
    required this.peakRating,
    required this.tierId,
    required this.tierName,
    required this.division,
    required this.stars,
    required this.placementMatchesRemaining,
    required this.wins,
    required this.losses,
    required this.currentStreak,
    required this.bestStreak,
    required this.timeoutLosses,
    required this.forfeitLosses,
    required this.opponentDiversityScore,
    required this.smurfWatch,
    required this.leaderboardScore,
    required this.rewardStatus,
    this.finalRank,
    this.lastMatchId,
  });

  final String seasonId;
  final String userId;
  final int rating;
  final int peakRating;
  final String tierId;
  final String tierName;
  final int division;
  final int stars;
  final int placementMatchesRemaining;
  final int wins;
  final int losses;
  final int currentStreak;
  final int bestStreak;
  final int timeoutLosses;
  final int forfeitLosses;
  final int opponentDiversityScore;
  final bool smurfWatch;
  final int leaderboardScore;
  final int? finalRank;
  final String rewardStatus;
  final String? lastMatchId;

  factory ColorClashSeasonProgressModel.fromJson(Map<String, dynamic> json) {
    final lastMatchId = asId(json['lastMatchId']);
    return ColorClashSeasonProgressModel(
      seasonId: asId(json['seasonId']),
      userId: asId(json['userId']),
      rating: asInt(json['rating'], fallback: 1000),
      peakRating: asInt(json['peakRating'], fallback: 1000),
      tierId: json['tierId']?.toString() ?? '',
      tierName: json['tierName']?.toString() ?? '',
      division: asInt(json['division'], fallback: 1),
      stars: asInt(json['stars']),
      placementMatchesRemaining:
          asInt(json['placementMatchesRemaining'], fallback: 0),
      wins: asInt(json['wins']),
      losses: asInt(json['losses']),
      currentStreak: asInt(json['currentStreak']),
      bestStreak: asInt(json['bestStreak']),
      timeoutLosses: asInt(json['timeoutLosses']),
      forfeitLosses: asInt(json['forfeitLosses']),
      opponentDiversityScore: asInt(json['opponentDiversityScore']),
      smurfWatch: asBool(json['smurfWatch']),
      leaderboardScore: asInt(json['leaderboardScore'], fallback: 1000),
      finalRank: json['finalRank'] == null ? null : asInt(json['finalRank']),
      rewardStatus: json['rewardStatus']?.toString() ?? 'pending',
      lastMatchId: lastMatchId.isEmpty ? null : lastMatchId,
    );
  }
}

class ColorClashLeaderboardPayloadModel {
  const ColorClashLeaderboardPayloadModel({
    required this.gameId,
    required this.period,
    required this.season,
    required this.rankings,
    required this.limit,
    required this.offset,
    this.userRank,
  });

  final String gameId;
  final String period;
  final ColorClashSeasonModel? season;
  final List<ColorClashLeaderboardEntryModel> rankings;
  final ColorClashLeaderboardUserRankModel? userRank;
  final int limit;
  final int offset;

  factory ColorClashLeaderboardPayloadModel.fromJson(
      Map<String, dynamic> json) {
    return ColorClashLeaderboardPayloadModel(
      gameId: json['gameId']?.toString() ?? 'color_clash',
      period: json['period']?.toString() ?? 'alltime',
      season: json['season'] == null
          ? null
          : ColorClashSeasonModel.fromJson(asMap(json['season'])),
      rankings: asMapList(json['rankings'])
          .map(ColorClashLeaderboardEntryModel.fromJson)
          .toList(growable: false),
      userRank: json['userRank'] == null
          ? null
          : ColorClashLeaderboardUserRankModel.fromJson(
              asMap(json['userRank'])),
      limit: asInt(json['limit'], fallback: 50),
      offset: asInt(json['offset']),
    );
  }
}

class ColorClashLeaderboardEntryModel {
  const ColorClashLeaderboardEntryModel({
    required this.rank,
    required this.userId,
    required this.username,
    required this.avatar,
    required this.level,
    required this.vipLevel,
    required this.rating,
    required this.tierId,
    required this.division,
    required this.stars,
  });

  final int rank;
  final String userId;
  final String username;
  final String avatar;
  final int level;
  final int vipLevel;
  final int rating;
  final String tierId;
  final int division;
  final int stars;

  factory ColorClashLeaderboardEntryModel.fromJson(Map<String, dynamic> json) {
    return ColorClashLeaderboardEntryModel(
      rank: asInt(json['rank'], fallback: 0),
      userId: asId(json['userId']),
      username: json['username']?.toString() ?? 'Unknown',
      avatar: json['avatar']?.toString() ?? '',
      level: asInt(json['level'], fallback: 1),
      vipLevel: asInt(json['vipLevel']),
      rating: asInt(json['rating'], fallback: 0),
      tierId: json['tierId']?.toString() ?? '',
      division: asInt(json['division'], fallback: 1),
      stars: asInt(json['stars']),
    );
  }
}

class ColorClashLeaderboardUserRankModel {
  const ColorClashLeaderboardUserRankModel({
    required this.rank,
    required this.score,
  });

  final int rank;
  final int score;

  factory ColorClashLeaderboardUserRankModel.fromJson(
    Map<String, dynamic> json,
  ) {
    return ColorClashLeaderboardUserRankModel(
      rank: asInt(json['rank'], fallback: 0),
      score: asInt(json['score'], fallback: 0),
    );
  }
}

class ColorClashEligibilityModel {
  const ColorClashEligibilityModel({
    required this.rankedEligible,
    required this.stakeEligible,
    required this.rankedLockReason,
    required this.stakeLockReason,
    required this.riskState,
  });

  final bool rankedEligible;
  final bool stakeEligible;
  final String rankedLockReason;
  final String stakeLockReason;
  final Map<String, dynamic> riskState;

  factory ColorClashEligibilityModel.fromJson(Map<String, dynamic> json) {
    return ColorClashEligibilityModel(
      rankedEligible: asBool(json['rankedEligible']),
      stakeEligible: asBool(json['stakeEligible']),
      rankedLockReason: json['rankedLockReason']?.toString() ?? '',
      stakeLockReason: json['stakeLockReason']?.toString() ?? '',
      riskState: asMap(json['riskState']),
    );
  }

  bool get hasAnyLock =>
      rankedLockReason.isNotEmpty || stakeLockReason.isNotEmpty;
}
