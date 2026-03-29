import 'color_clash_match_snapshot.dart';
import 'color_clash_model_utils.dart';
import 'color_clash_season_model.dart';
import 'color_clash_table_model.dart';

class ColorClashHomeModel {
  const ColorClashHomeModel({
    required this.gameId,
    required this.queuePresets,
    required this.rooms,
    required this.themes,
    required this.tutorial,
    required this.userProgress,
    required this.leaderboardPreview,
    required this.rewardPreview,
    this.season,
    this.activeMatch,
  });

  final String gameId;
  final ColorClashSeasonModel? season;
  final ColorClashHomeUserProgressModel userProgress;
  final List<ColorClashQueuePresetModel> queuePresets;
  final List<ColorClashRoomSummaryModel> rooms;
  final ColorClashHomeActiveMatchModel? activeMatch;
  final ColorClashHomeThemeSummaryModel themes;
  final ColorClashHomeTutorialModel tutorial;
  final List<ColorClashLeaderboardEntryModel> leaderboardPreview;
  final List<Map<String, dynamic>> rewardPreview;

  factory ColorClashHomeModel.fromJson(Map<String, dynamic> json) {
    return ColorClashHomeModel(
      gameId: json['gameId']?.toString() ?? 'color_clash',
      season: json['season'] == null
          ? null
          : ColorClashSeasonModel.fromJson(asMap(json['season'])),
      userProgress: ColorClashHomeUserProgressModel.fromJson(
        asMap(json['userProgress']),
      ),
      queuePresets: asMapList(json['queuePresets'])
          .map(ColorClashQueuePresetModel.fromJson)
          .toList(growable: false),
      rooms: asMapList(json['rooms'])
          .map(ColorClashRoomSummaryModel.fromJson)
          .toList(growable: false),
      activeMatch: json['activeMatch'] == null
          ? null
          : ColorClashHomeActiveMatchModel.fromJson(asMap(json['activeMatch'])),
      themes: ColorClashHomeThemeSummaryModel.fromJson(asMap(json['themes'])),
      tutorial: ColorClashHomeTutorialModel.fromJson(asMap(json['tutorial'])),
      leaderboardPreview: asMapList(json['leaderboardPreview'])
          .map(ColorClashLeaderboardEntryModel.fromJson)
          .toList(growable: false),
      rewardPreview: asMapList(json['rewardPreview']),
    );
  }

  bool get hasActiveMatch => activeMatch != null;
}

class ColorClashHomeUserProgressModel {
  const ColorClashHomeUserProgressModel({
    required this.stats,
    required this.activeQueueTicketId,
    this.currentSeason,
    this.currentUserRank,
    this.eligibility,
  });

  final Map<String, dynamic> stats;
  final String? activeQueueTicketId;
  final ColorClashSeasonProgressModel? currentSeason;
  final ColorClashLeaderboardUserRankModel? currentUserRank;
  final ColorClashEligibilityModel? eligibility;

  factory ColorClashHomeUserProgressModel.fromJson(Map<String, dynamic> json) {
    return ColorClashHomeUserProgressModel(
      stats: asMap(json['stats']),
      activeQueueTicketId: json['activeQueueTicketId']?.toString(),
      currentSeason: json['currentSeason'] == null
          ? null
          : ColorClashSeasonProgressModel.fromJson(
              asMap(json['currentSeason']),
            ),
      currentUserRank: json['currentUserRank'] == null
          ? null
          : ColorClashLeaderboardUserRankModel.fromJson(
              asMap(json['currentUserRank']),
            ),
      eligibility: json['eligibility'] == null
          ? null
          : ColorClashEligibilityModel.fromJson(asMap(json['eligibility'])),
    );
  }
}

class ColorClashHomeActiveMatchModel {
  const ColorClashHomeActiveMatchModel({
    required this.matchId,
    required this.roomId,
    required this.status,
    required this.tableMode,
    required this.version,
    required this.players,
    this.seasonId,
    this.publicState,
    this.updatedAt,
    this.startedAt,
  });

  final String matchId;
  final String roomId;
  final String? seasonId;
  final String status;
  final String tableMode;
  final int version;
  final ColorClashPublicMatchStateModel? publicState;
  final List<ColorClashHomeActivePlayerModel> players;
  final DateTime? updatedAt;
  final DateTime? startedAt;

  factory ColorClashHomeActiveMatchModel.fromJson(Map<String, dynamic> json) {
    final seasonId = asId(json['seasonId']);
    return ColorClashHomeActiveMatchModel(
      matchId: asId(json['matchId']),
      roomId: asId(json['roomId']),
      seasonId: seasonId.isEmpty ? null : seasonId,
      status: json['status']?.toString() ?? 'active',
      tableMode: json['tableMode']?.toString() ?? 'friend_room',
      version: asInt(json['version'], fallback: 1),
      publicState: json['publicState'] == null
          ? null
          : ColorClashPublicMatchStateModel.fromJson(
              asMap(json['publicState']),
            ),
      players: asMapList(json['players'])
          .map(ColorClashHomeActivePlayerModel.fromJson)
          .toList(growable: false),
      updatedAt: asDateTime(json['updatedAt']),
      startedAt: asDateTime(json['startedAt']),
    );
  }
}

class ColorClashHomeActivePlayerModel {
  const ColorClashHomeActivePlayerModel({
    required this.userId,
    required this.seatIndex,
    required this.username,
    required this.avatar,
    required this.status,
  });

  final String userId;
  final int seatIndex;
  final String username;
  final String avatar;
  final String status;

  factory ColorClashHomeActivePlayerModel.fromJson(Map<String, dynamic> json) {
    return ColorClashHomeActivePlayerModel(
      userId: asId(json['userId']),
      seatIndex: asInt(json['seatIndex']),
      username: json['username']?.toString() ?? 'Guest',
      avatar: json['avatar']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
    );
  }
}

class ColorClashHomeThemeSummaryModel {
  const ColorClashHomeThemeSummaryModel({
    required this.equippedThemePackId,
    required this.ownedThemePackIds,
  });

  final String equippedThemePackId;
  final List<String> ownedThemePackIds;

  factory ColorClashHomeThemeSummaryModel.fromJson(Map<String, dynamic> json) {
    return ColorClashHomeThemeSummaryModel(
      equippedThemePackId:
          json['equippedThemePackId']?.toString() ?? 'forest_picnic',
      ownedThemePackIds: asStringList(json['ownedThemePackIds']),
    );
  }
}

class ColorClashHomeTutorialModel {
  const ColorClashHomeTutorialModel({
    required this.completedVersions,
  });

  final List<String> completedVersions;

  factory ColorClashHomeTutorialModel.fromJson(Map<String, dynamic> json) {
    return ColorClashHomeTutorialModel(
      completedVersions: asStringList(json['completedVersions']),
    );
  }

  bool get isV1Complete => completedVersions.contains('v1');
}
