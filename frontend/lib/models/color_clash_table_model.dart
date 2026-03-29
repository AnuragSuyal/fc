import 'color_clash_model_utils.dart';

class ColorClashTablesPayload {
  const ColorClashTablesPayload({
    required this.gameId,
    required this.queuePresets,
    required this.rooms,
  });

  final String gameId;
  final List<ColorClashQueuePresetModel> queuePresets;
  final List<ColorClashRoomSummaryModel> rooms;

  factory ColorClashTablesPayload.fromJson(Map<String, dynamic> json) {
    return ColorClashTablesPayload(
      gameId: json['gameId']?.toString() ?? 'color_clash',
      queuePresets: asMapList(json['queuePresets'])
          .map(ColorClashQueuePresetModel.fromJson)
          .toList(growable: false),
      rooms: asMapList(json['rooms'])
          .map(ColorClashRoomSummaryModel.fromJson)
          .toList(growable: false),
    );
  }
}

class ColorClashQueuePresetModel {
  const ColorClashQueuePresetModel({
    required this.queueId,
    required this.mode,
    required this.stakeAmount,
    required this.region,
    required this.playerCount,
    required this.enabled,
    required this.themePackId,
    this.disabledReason,
  });

  final String queueId;
  final String mode;
  final int stakeAmount;
  final String region;
  final int playerCount;
  final bool enabled;
  final String themePackId;
  final String? disabledReason;

  factory ColorClashQueuePresetModel.fromJson(Map<String, dynamic> json) {
    return ColorClashQueuePresetModel(
      queueId: json['queueId']?.toString() ?? '',
      mode: json['mode']?.toString() ?? 'casual_free',
      stakeAmount: asInt(json['stakeAmount']),
      region: json['region']?.toString() ?? 'Global',
      playerCount: asInt(json['playerCount'], fallback: 2),
      enabled: asBool(json['enabled'], fallback: true),
      themePackId: json['themePackId']?.toString() ?? 'forest_picnic',
      disabledReason: json['disabledReason']?.toString(),
    );
  }

  bool get isStakeTable => mode == 'gold_stake' || stakeAmount > 0;
  bool get isRanked => mode == 'ranked';

  String get modeLabel {
    switch (mode) {
      case 'casual_free':
        return 'Casual Free';
      case 'gold_stake':
        return 'Gold Stake';
      case 'ranked':
        return 'Ranked Season';
      case 'friend_room':
        return 'Friend Room';
      case 'custom_chaos':
        return 'Custom Chaos';
      default:
        return mode;
    }
  }
}

class ColorClashStakeModel {
  const ColorClashStakeModel({
    required this.currency,
    required this.entryFee,
    required this.houseFeeBps,
    required this.sinkFeeBps,
    required this.payouts,
  });

  final String currency;
  final int entryFee;
  final int houseFeeBps;
  final int sinkFeeBps;
  final List<ColorClashPayoutRuleModel> payouts;

  factory ColorClashStakeModel.fromJson(Map<String, dynamic> json) {
    return ColorClashStakeModel(
      currency: json['currency']?.toString() ?? 'none',
      entryFee: asInt(json['entryFee']),
      houseFeeBps: asInt(json['houseFeeBps']),
      sinkFeeBps: asInt(json['sinkFeeBps']),
      payouts: asMapList(json['payouts'])
          .map(ColorClashPayoutRuleModel.fromJson)
          .toList(growable: false),
    );
  }

  bool get isPaidTable => currency != 'none' && entryFee > 0;
}

class ColorClashPayoutRuleModel {
  const ColorClashPayoutRuleModel({
    required this.place,
    required this.bps,
  });

  final int place;
  final int bps;

  factory ColorClashPayoutRuleModel.fromJson(Map<String, dynamic> json) {
    return ColorClashPayoutRuleModel(
      place: asInt(json['place'], fallback: 1),
      bps: asInt(json['bps']),
    );
  }
}

class ColorClashHostModel {
  const ColorClashHostModel({
    required this.userId,
    required this.username,
    required this.avatar,
  });

  final String userId;
  final String username;
  final String avatar;

  factory ColorClashHostModel.fromJson(Map<String, dynamic> json) {
    return ColorClashHostModel(
      userId: asId(json['userId']),
      username: json['username']?.toString() ?? 'Host',
      avatar: json['avatar']?.toString() ?? '',
    );
  }
}

class ColorClashRoomSummaryModel {
  const ColorClashRoomSummaryModel({
    required this.roomId,
    required this.displayId,
    required this.name,
    required this.description,
    required this.visibility,
    required this.tableMode,
    required this.allowSpectators,
    required this.themePackId,
    required this.maxPlayers,
    required this.participantCount,
    required this.lobbyStatus,
    required this.stake,
    required this.createdAt,
    required this.updatedAt,
    this.host,
    this.seasonId,
    this.activeMatchId,
  });

  final String roomId;
  final String displayId;
  final String name;
  final String description;
  final ColorClashHostModel? host;
  final String visibility;
  final String tableMode;
  final String? seasonId;
  final bool allowSpectators;
  final String themePackId;
  final int maxPlayers;
  final int participantCount;
  final String lobbyStatus;
  final String? activeMatchId;
  final ColorClashStakeModel stake;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ColorClashRoomSummaryModel.fromJson(Map<String, dynamic> json) {
    final seasonId = asId(json['seasonId']);
    final activeMatchId = asId(json['activeMatchId']);
    return ColorClashRoomSummaryModel(
      roomId: asId(json['roomId']),
      displayId: json['displayId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Color Clash Room',
      description: json['description']?.toString() ?? '',
      host: json['host'] == null
          ? null
          : ColorClashHostModel.fromJson(asMap(json['host'])),
      visibility: json['visibility']?.toString() ?? 'private',
      tableMode: json['tableMode']?.toString() ?? 'friend_room',
      seasonId: seasonId.isEmpty ? null : seasonId,
      allowSpectators: asBool(json['allowSpectators'], fallback: true),
      themePackId: json['themePackId']?.toString() ?? 'forest_picnic',
      maxPlayers: asInt(json['maxPlayers'], fallback: 4),
      participantCount: asInt(json['participantCount']),
      lobbyStatus: json['lobbyStatus']?.toString() ?? 'open',
      activeMatchId: activeMatchId.isEmpty ? null : activeMatchId,
      stake: ColorClashStakeModel.fromJson(asMap(json['stake'])),
      createdAt: asDateTime(json['createdAt']),
      updatedAt: asDateTime(json['updatedAt']),
    );
  }

  bool get isPaidTable => stake.isPaidTable;
  bool get hasActiveMatch => (activeMatchId ?? '').isNotEmpty;

  String get tableModeLabel {
    switch (tableMode) {
      case 'casual_free':
        return 'Casual Free';
      case 'gold_stake':
        return 'Gold Stake';
      case 'ranked':
        return 'Ranked';
      case 'friend_room':
        return 'Friend Room';
      case 'custom_chaos':
        return 'Custom Chaos';
      default:
        return tableMode.replaceAll('_', ' ');
    }
  }
}

extension ColorClashThemePackLabel on String {
  String get colorClashThemeLabel {
    switch (this) {
      case 'forest_picnic':
        return 'Forest Picnic';
      case 'neon_orbit':
        return 'Neon Orbit';
      case 'candy_carnival':
        return 'Candy Carnival';
      default:
        return replaceAll('_', ' ');
    }
  }
}
