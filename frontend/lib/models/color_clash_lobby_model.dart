import 'color_clash_model_utils.dart';
import 'color_clash_table_model.dart';

class ColorClashLobbySessionModel {
  const ColorClashLobbySessionModel({
    required this.room,
    required this.lobby,
    required this.viewerRole,
  });

  final ColorClashRoomSummaryModel room;
  final ColorClashLobbyModel lobby;
  final String viewerRole;

  factory ColorClashLobbySessionModel.fromJson(Map<String, dynamic> json) {
    return ColorClashLobbySessionModel(
      room: ColorClashRoomSummaryModel.fromJson(asMap(json['room'])),
      lobby: ColorClashLobbyModel.fromJson(asMap(json['lobby'])),
      viewerRole: json['viewerRole']?.toString() ?? 'spectator',
    );
  }
}

class ColorClashLobbyModel {
  const ColorClashLobbyModel({
    required this.roomId,
    required this.gameId,
    required this.lobbyVersion,
    required this.status,
    required this.minPlayersToStart,
    required this.maxPlayers,
    required this.countdownSec,
    required this.allowSpectators,
    required this.seats,
    required this.playersByUserId,
    required this.updatedAtMs,
    this.activeMatchId,
    this.countdownEndsAt,
    this.rematchWindowEndsAt,
    this.rematchVotesByUserId = const {},
  });

  final String roomId;
  final String gameId;
  final int lobbyVersion;
  final String status;
  final String? activeMatchId;
  final int minPlayersToStart;
  final int maxPlayers;
  final int countdownSec;
  final bool allowSpectators;
  final Map<int, String> seats;
  final Map<String, ColorClashLobbyPlayerModel> playersByUserId;
  final int updatedAtMs;
  final int? countdownEndsAt;
  final int? rematchWindowEndsAt;
  final Map<String, bool> rematchVotesByUserId;

  factory ColorClashLobbyModel.fromJson(Map<String, dynamic> json) {
    final rawSeats = asMap(json['seats']);
    final parsedSeats = <int, String>{};
    for (final entry in rawSeats.entries) {
      final key = int.tryParse(entry.key);
      if (key == null) continue;
      final userId = entry.value?.toString() ?? '';
      if (userId.isNotEmpty) {
        parsedSeats[key] = userId;
      }
    }

    final rawPlayers = asMap(json['playersByUserId']);
    final parsedPlayers = <String, ColorClashLobbyPlayerModel>{};
    for (final entry in rawPlayers.entries) {
      parsedPlayers[entry.key] =
          ColorClashLobbyPlayerModel.fromJson(asMap(entry.value));
    }

    final rawVotes = asMap(json['rematchVotesByUserId']);
    return ColorClashLobbyModel(
      roomId: json['roomId']?.toString() ?? '',
      gameId: json['gameId']?.toString() ?? 'color_clash',
      lobbyVersion: asInt(json['lobbyVersion'], fallback: 1),
      status: json['status']?.toString() ?? 'open',
      activeMatchId: asId(json['activeMatchId']).isEmpty
          ? null
          : asId(json['activeMatchId']),
      minPlayersToStart: asInt(json['minPlayersToStart'], fallback: 2),
      maxPlayers: asInt(json['maxPlayers'], fallback: 4),
      countdownSec: asInt(json['countdownSec'], fallback: 6),
      allowSpectators: asBool(json['allowSpectators'], fallback: true),
      seats: parsedSeats,
      playersByUserId: parsedPlayers,
      updatedAtMs: asInt(json['updatedAtMs']),
      countdownEndsAt: json['countdownEndsAt'] == null
          ? null
          : asInt(json['countdownEndsAt']),
      rematchWindowEndsAt: json['rematchWindowEndsAt'] == null
          ? null
          : asInt(json['rematchWindowEndsAt']),
      rematchVotesByUserId: rawVotes.map(
        (key, value) => MapEntry(key, asBool(value)),
      ),
    );
  }

  List<ColorClashLobbyPlayerModel> get orderedPlayers {
    final entries = playersByUserId.values.toList(growable: false);
    entries.sort((left, right) {
      final leftSeat = left.seatIndex ?? 999;
      final rightSeat = right.seatIndex ?? 999;
      if (leftSeat != rightSeat) return leftSeat.compareTo(rightSeat);
      return left.username.compareTo(right.username);
    });
    return entries;
  }

  List<ColorClashLobbyPlayerModel> get readyPlayers => orderedPlayers
      .where((entry) => entry.role == 'player' && entry.ready)
      .toList(growable: false);

  int get spectatorCount =>
      playersByUserId.values.where((entry) => entry.role == 'spectator').length;
}

class ColorClashLobbyPlayerModel {
  const ColorClashLobbyPlayerModel({
    required this.userId,
    required this.username,
    required this.avatar,
    required this.ready,
    required this.role,
    required this.joinedAtMs,
    required this.lastSeenAtMs,
    this.seatIndex,
  });

  final String userId;
  final String username;
  final String avatar;
  final int? seatIndex;
  final bool ready;
  final String role;
  final int joinedAtMs;
  final int lastSeenAtMs;

  factory ColorClashLobbyPlayerModel.fromJson(Map<String, dynamic> json) {
    return ColorClashLobbyPlayerModel(
      userId: json['userId']?.toString() ?? '',
      username: json['username']?.toString() ?? 'Guest',
      avatar: json['avatar']?.toString() ?? '',
      seatIndex: json['seatIndex'] == null ? null : asInt(json['seatIndex']),
      ready: asBool(json['ready']),
      role: json['role']?.toString() ?? 'spectator',
      joinedAtMs: asInt(json['joinedAtMs']),
      lastSeenAtMs: asInt(json['lastSeenAtMs']),
    );
  }

  bool get isSpectator => role == 'spectator';
  bool get hasSeat => seatIndex != null;
}
