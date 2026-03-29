import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/color_clash_home_model.dart';
import '../models/color_clash_lobby_model.dart';
import '../models/color_clash_match_snapshot.dart';
import '../models/color_clash_season_model.dart';
import '../models/color_clash_settlement_model.dart';
import '../models/color_clash_table_model.dart';
import '../models/color_clash_model_utils.dart';
import 'api_service.dart';

class ColorClashService {
  static const String _basePath = '/color-clash';
  static final Random _random = Random();

  Future<ColorClashHomeModel> getHome() async {
    final response = await ApiService.get('$_basePath/home');
    return ColorClashHomeModel.fromJson(asMap(response));
  }

  Future<ColorClashTablesPayload> getTables({
    String? mode,
    int limit = 20,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      if (mode != null && mode.isNotEmpty) 'mode': mode,
    };
    final response = await ApiService.get(
        '$_basePath/tables?${Uri(queryParameters: query).query}');
    return ColorClashTablesPayload.fromJson(asMap(response));
  }

  Future<ColorClashLobbySessionModel> createFriendRoom({
    String? name,
    String? description,
    String visibility = 'invite_only',
    bool allowSpectators = true,
    int maxPlayers = 4,
    int? minPlayersToStart,
    int? countdownSec,
    int? turnTimeoutSec,
    String themePackId = 'forest_picnic',
    String tableMode = 'friend_room',
    int stakeEntryFee = 0,
    List<Map<String, dynamic>>? stakePayouts,
    int? houseFeeBps,
    int? sinkFeeBps,
    List<String> invitedUserIds = const <String>[],
    Map<String, dynamic> customCards = const <String, dynamic>{},
  }) async {
    final response = await ApiService.post(
      '$_basePath/rooms',
      <String, dynamic>{
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        'visibility': visibility,
        'allowSpectators': allowSpectators,
        'maxPlayers': maxPlayers,
        if (minPlayersToStart != null) 'minPlayersToStart': minPlayersToStart,
        if (countdownSec != null) 'countdownSec': countdownSec,
        if (turnTimeoutSec != null) 'turnTimeoutSec': turnTimeoutSec,
        'themePackId': themePackId,
        'tableMode': tableMode,
        'stakeEntryFee': stakeEntryFee,
        if (stakePayouts != null) 'stakePayouts': stakePayouts,
        if (houseFeeBps != null) 'houseFeeBps': houseFeeBps,
        if (sinkFeeBps != null) 'sinkFeeBps': sinkFeeBps,
        'invitedUserIds': invitedUserIds,
        'customCards': customCards,
      },
      headers: _idempotencyHeaders('room-create'),
    );
    return ColorClashLobbySessionModel.fromJson(asMap(response));
  }

  Future<ColorClashLobbySessionModel> joinRoom(
    String roomId, {
    bool spectator = false,
  }) async {
    final response = await ApiService.post(
      '$_basePath/rooms/$roomId/join',
      <String, dynamic>{'spectator': spectator},
      headers: _idempotencyHeaders('room-join-$roomId'),
    );
    return ColorClashLobbySessionModel.fromJson(asMap(response));
  }

  Future<ColorClashMatchmakingJoinResult> joinMatchmaking({
    required String mode,
    int? stakeAmount,
    String? region,
    String? themePackId,
  }) async {
    final response = await ApiService.post(
      '$_basePath/matchmaking/join',
      <String, dynamic>{
        'mode': mode,
        if (stakeAmount != null) 'stakeAmount': stakeAmount,
        if (region != null && region.isNotEmpty) 'region': region,
        if (themePackId != null && themePackId.isNotEmpty)
          'themePackId': themePackId,
      },
      headers: _idempotencyHeaders('queue-join-$mode-${stakeAmount ?? 0}'),
    );
    return ColorClashMatchmakingJoinResult.fromJson(asMap(response));
  }

  Future<ColorClashMatchmakingLeaveResult> leaveMatchmaking({
    String? queueTicketId,
  }) async {
    final response = await ApiService.post(
      '$_basePath/matchmaking/leave',
      <String, dynamic>{
        if (queueTicketId != null && queueTicketId.isNotEmpty)
          'queueTicketId': queueTicketId,
      },
      headers: _idempotencyHeaders('queue-leave-${queueTicketId ?? 'active'}'),
    );
    return ColorClashMatchmakingLeaveResult.fromJson(asMap(response));
  }

  Future<ColorClashReadyResult> setReady({
    required String roomId,
    required bool ready,
    int? seatIndex,
  }) async {
    final response = await ApiService.post(
      '$_basePath/rooms/$roomId/ready',
      <String, dynamic>{
        'ready': ready,
        if (seatIndex != null) 'seatIndex': seatIndex,
      },
      headers: _idempotencyHeaders(
        'ready-$roomId-$ready-${seatIndex ?? 'seat'}',
      ),
    );
    return ColorClashReadyResult.fromJson(asMap(response));
  }

  Future<ColorClashCancelRoomResult> cancelRoom(
    String roomId, {
    String? reason,
  }) async {
    final response = await ApiService.post(
      '$_basePath/rooms/$roomId/cancel',
      <String, dynamic>{
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
      headers: _idempotencyHeaders('room-cancel-$roomId'),
    );
    return ColorClashCancelRoomResult.fromJson(asMap(response));
  }

  Future<ColorClashLobbySessionModel> getLobby(String roomId) async {
    final response = await ApiService.get('$_basePath/rooms/$roomId/lobby');
    return ColorClashLobbySessionModel.fromJson(asMap(response));
  }

  Future<ColorClashMatchSnapshotModel> getMatchSnapshot(String matchId) async {
    final response =
        await ApiService.get('$_basePath/matches/$matchId/snapshot');
    return ColorClashMatchSnapshotModel.fromJson(asMap(response));
  }

  Future<ColorClashSettlementSummaryModel> getSettlementSummary(
    String matchId,
  ) async {
    final response =
        await ApiService.get('$_basePath/matches/$matchId/settlement');
    return ColorClashSettlementSummaryModel.fromJson(asMap(response));
  }

  Future<ColorClashReconnectPayloadModel> reconnectMatch(
    String matchId, {
    int lastKnownVersion = 0,
  }) async {
    final response = await ApiService.post(
      '$_basePath/matches/$matchId/reconnect',
      <String, dynamic>{'lastKnownVersion': lastKnownVersion},
      headers:
          _idempotencyHeaders('match-reconnect-$matchId-$lastKnownVersion'),
    );
    return ColorClashReconnectPayloadModel.fromJson(asMap(response));
  }

  Future<ColorClashRematchResult> voteRematch({
    required String matchId,
    required bool vote,
  }) async {
    final response = await ApiService.post(
      '$_basePath/matches/$matchId/rematch',
      <String, dynamic>{'vote': vote},
      headers: _idempotencyHeaders('rematch-$matchId-$vote'),
    );
    return ColorClashRematchResult.fromJson(asMap(response));
  }

  Future<ColorClashSeasonSummaryModel> getCurrentSeason() async {
    final response = await ApiService.get('$_basePath/seasons/current');
    return ColorClashSeasonSummaryModel.fromJson(asMap(response));
  }

  Future<ColorClashLeaderboardPayloadModel> getLeaderboard({
    String period = 'alltime',
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await ApiService.get(
      '$_basePath/leaderboards?${Uri(queryParameters: <String, String>{
            'period': period,
            'limit': '$limit',
            'offset': '$offset',
          }).query}',
    );
    return ColorClashLeaderboardPayloadModel.fromJson(asMap(response));
  }

  Future<String> equipTheme(String themeId) async {
    final response = await ApiService.post(
      '$_basePath/themes/$themeId/equip',
      const <String, dynamic>{'slot': 'table'},
      headers: _idempotencyHeaders('theme-equip-$themeId'),
    );
    return asMap(response)['equippedThemePackId']?.toString() ?? themeId;
  }

  Future<bool> completeTutorial({String version = 'v1'}) async {
    final response = await ApiService.post(
      '$_basePath/tutorial/complete',
      <String, dynamic>{'version': version},
      headers: _idempotencyHeaders('tutorial-$version'),
    );
    return asBool(asMap(response)['completed']);
  }

  Map<String, String> _idempotencyHeaders(String prefix) {
    final key = createIdempotencyKey(prefix);
    return <String, String>{
      'Idempotency-Key': key,
    };
  }

  @visibleForTesting
  static String createIdempotencyKey(
    String prefix, {
    Random? random,
    DateTime? timestamp,
  }) {
    final clock = timestamp ?? DateTime.now();
    final source = random ?? _random;
    final entropy = List<String>.generate(
      4,
      (_) => source.nextInt(1 << 16).toRadixString(16).padLeft(4, '0'),
      growable: false,
    ).join();
    return '$prefix-${clock.microsecondsSinceEpoch}-$entropy';
  }
}

class ColorClashMatchmakingJoinResult {
  const ColorClashMatchmakingJoinResult({
    required this.status,
    required this.duplicate,
    this.queueTicketId,
    this.estimatedWaitMs,
    this.room,
    this.match,
  });

  final String status;
  final bool duplicate;
  final String? queueTicketId;
  final int? estimatedWaitMs;
  final ColorClashRoomSummaryModel? room;
  final ColorClashMatchedMatchInfo? match;

  factory ColorClashMatchmakingJoinResult.fromJson(Map<String, dynamic> json) {
    final queueTicketId = json['queueTicketId']?.toString();
    return ColorClashMatchmakingJoinResult(
      status: json['status']?.toString() ?? 'queued',
      duplicate: asBool(json['duplicate']),
      queueTicketId: queueTicketId,
      estimatedWaitMs: json['estimatedWaitMs'] == null
          ? null
          : asInt(json['estimatedWaitMs']),
      room: json['room'] == null
          ? null
          : ColorClashRoomSummaryModel.fromJson(asMap(json['room'])),
      match: json['match'] == null
          ? null
          : ColorClashMatchedMatchInfo.fromJson(asMap(json['match'])),
    );
  }
}

class ColorClashMatchedMatchInfo {
  const ColorClashMatchedMatchInfo({
    required this.matchId,
    required this.roomId,
    required this.roundId,
    required this.version,
  });

  final String matchId;
  final String roomId;
  final String roundId;
  final int version;

  factory ColorClashMatchedMatchInfo.fromJson(Map<String, dynamic> json) {
    return ColorClashMatchedMatchInfo(
      matchId: asId(json['matchId']),
      roomId: asId(json['roomId']),
      roundId: asId(json['roundId']),
      version: asInt(json['version'], fallback: 1),
    );
  }
}

class ColorClashMatchmakingLeaveResult {
  const ColorClashMatchmakingLeaveResult({
    required this.success,
    required this.removed,
    this.queueTicketId,
  });

  final bool success;
  final bool removed;
  final String? queueTicketId;

  factory ColorClashMatchmakingLeaveResult.fromJson(Map<String, dynamic> json) {
    return ColorClashMatchmakingLeaveResult(
      success: asBool(json['success']),
      removed: asBool(json['removed']),
      queueTicketId: json['queueTicketId']?.toString(),
    );
  }
}

class ColorClashReadyResult {
  const ColorClashReadyResult({
    required this.roomId,
    required this.lobby,
    required this.viewerRole,
  });

  final String roomId;
  final ColorClashLobbyModel lobby;
  final String viewerRole;

  factory ColorClashReadyResult.fromJson(Map<String, dynamic> json) {
    return ColorClashReadyResult(
      roomId: asId(json['roomId']),
      lobby: ColorClashLobbyModel.fromJson(asMap(json['lobby'])),
      viewerRole: json['viewerRole']?.toString() ?? 'player',
    );
  }
}

class ColorClashCancelRoomResult {
  const ColorClashCancelRoomResult({
    required this.success,
    required this.roomId,
    required this.lobby,
  });

  final bool success;
  final String roomId;
  final ColorClashLobbyModel lobby;

  factory ColorClashCancelRoomResult.fromJson(Map<String, dynamic> json) {
    return ColorClashCancelRoomResult(
      success: asBool(json['success']),
      roomId: asId(json['roomId']),
      lobby: ColorClashLobbyModel.fromJson(asMap(json['lobby'])),
    );
  }
}

class ColorClashRematchResult {
  const ColorClashRematchResult({
    required this.status,
    required this.roomId,
    required this.votes,
    this.rematchWindowEndsAt,
    this.lobbyVersion,
    this.match,
    this.roundId,
    this.version,
  });

  final String status;
  final String roomId;
  final Map<String, bool> votes;
  final int? rematchWindowEndsAt;
  final int? lobbyVersion;
  final String? match;
  final String? roundId;
  final int? version;

  factory ColorClashRematchResult.fromJson(Map<String, dynamic> json) {
    final rawVotes = asMap(json['votes']);
    final matchId = asId(json['matchId']);
    final roundId = asId(json['roundId']);
    return ColorClashRematchResult(
      status: json['status']?.toString() ?? 'waiting',
      roomId: asId(json['roomId']),
      votes: rawVotes.map(
        (key, value) => MapEntry(key, asBool(value)),
      ),
      rematchWindowEndsAt: json['rematchWindowEndsAt'] == null
          ? null
          : asInt(json['rematchWindowEndsAt']),
      lobbyVersion:
          json['lobbyVersion'] == null ? null : asInt(json['lobbyVersion']),
      match: matchId.isEmpty ? null : matchId,
      roundId: roundId.isEmpty ? null : roundId,
      version: json['version'] == null ? null : asInt(json['version']),
    );
  }

  bool get isMatched => status == 'matched' && (match ?? '').isNotEmpty;
}
