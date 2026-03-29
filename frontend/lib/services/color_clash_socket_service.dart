import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/color_clash_lobby_model.dart';
import '../models/color_clash_match_snapshot.dart';
import '../models/color_clash_model_utils.dart';
import 'socket_service.dart';

class ColorClashSocketService {
  ColorClashSocketService();

  io.Socket? _boundSocket;
  StreamSubscription<Map<String, dynamic>>? _resyncSubscription;
  bool _coreListenersBound = false;
  bool _disposed = false;

  final Map<String, int> _trackedRoomVersions = <String, int>{};
  final Map<String, int> _trackedMatchVersions = <String, int>{};
  final Map<String, Future<ColorClashRoomSubscribeAck>> _roomSubscriptionsInFlight =
      <String, Future<ColorClashRoomSubscribeAck>>{};
  final Map<String, Future<ColorClashReconnectPayloadModel>>
      _matchSubscriptionsInFlight =
      <String, Future<ColorClashReconnectPayloadModel>>{};

  final StreamController<ColorClashLobbyModel> _roomLobbyController =
      StreamController<ColorClashLobbyModel>.broadcast();
  final StreamController<ColorClashCountdownEvent> _countdownStartedController =
      StreamController<ColorClashCountdownEvent>.broadcast();
  final StreamController<ColorClashCountdownCancelledEvent>
      _countdownCancelledController =
      StreamController<ColorClashCountdownCancelledEvent>.broadcast();
  final StreamController<ColorClashMatchStartedEvent> _matchStartedController =
      StreamController<ColorClashMatchStartedEvent>.broadcast();
  final StreamController<ColorClashMatchPatchEvent> _matchPatchController =
      StreamController<ColorClashMatchPatchEvent>.broadcast();
  final StreamController<ColorClashLastCardAlertEvent>
      _lastCardAlertController =
      StreamController<ColorClashLastCardAlertEvent>.broadcast();
  final StreamController<ColorClashRoundResultEvent> _roundResultController =
      StreamController<ColorClashRoundResultEvent>.broadcast();
  final StreamController<ColorClashMatchFinishedEvent>
      _matchFinishedController =
      StreamController<ColorClashMatchFinishedEvent>.broadcast();
  final StreamController<ColorClashPrivateStateEvent> _handStateController =
      StreamController<ColorClashPrivateStateEvent>.broadcast();
  final StreamController<ColorClashPrivateStateEvent> _drawResultController =
      StreamController<ColorClashPrivateStateEvent>.broadcast();
  final StreamController<ColorClashPrivateStateEvent>
      _challengePromptController =
      StreamController<ColorClashPrivateStateEvent>.broadcast();
  final StreamController<ColorClashCommandErrorEvent> _commandErrorController =
      StreamController<ColorClashCommandErrorEvent>.broadcast();
  final StreamController<ColorClashQueueMatchedEvent> _queueMatchedController =
      StreamController<ColorClashQueueMatchedEvent>.broadcast();
  final StreamController<Map<String, dynamic>> _resyncController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<ColorClashLobbyModel> get roomLobbyStream =>
      _roomLobbyController.stream;
  Stream<ColorClashCountdownEvent> get countdownStartedStream =>
      _countdownStartedController.stream;
  Stream<ColorClashCountdownCancelledEvent> get countdownCancelledStream =>
      _countdownCancelledController.stream;
  Stream<ColorClashMatchStartedEvent> get matchStartedStream =>
      _matchStartedController.stream;
  Stream<ColorClashMatchPatchEvent> get matchPatchStream =>
      _matchPatchController.stream;
  Stream<ColorClashLastCardAlertEvent> get lastCardAlertStream =>
      _lastCardAlertController.stream;
  Stream<ColorClashRoundResultEvent> get roundResultStream =>
      _roundResultController.stream;
  Stream<ColorClashMatchFinishedEvent> get matchFinishedStream =>
      _matchFinishedController.stream;
  Stream<ColorClashPrivateStateEvent> get handStateStream =>
      _handStateController.stream;
  Stream<ColorClashPrivateStateEvent> get drawResultStream =>
      _drawResultController.stream;
  Stream<ColorClashPrivateStateEvent> get challengePromptStream =>
      _challengePromptController.stream;
  Stream<ColorClashCommandErrorEvent> get commandErrorStream =>
      _commandErrorController.stream;
  Stream<ColorClashQueueMatchedEvent> get queueMatchedStream =>
      _queueMatchedController.stream;
  Stream<Map<String, dynamic>> get resyncStream => _resyncController.stream;

  Future<void> ensureInitialized() async {
    await SocketService.init();
    _bindCoreListeners();
    _bindSocket(SocketService.socket);
  }

  Future<ColorClashRoomSubscribeAck> subscribeRoom(
    String roomId, {
    int? lastLobbyVersion,
  }) async {
    final requestKey = '$roomId:${lastLobbyVersion ?? -1}';
    final existing = _roomSubscriptionsInFlight[requestKey];
    if (existing != null) {
      return existing;
    }

    final future = _subscribeRoomInternal(
      roomId,
      lastLobbyVersion: lastLobbyVersion,
    );
    _roomSubscriptionsInFlight[requestKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_roomSubscriptionsInFlight[requestKey], future)) {
        _roomSubscriptionsInFlight.remove(requestKey);
      }
    }
  }

  Future<ColorClashRoomSubscribeAck> _subscribeRoomInternal(
    String roomId, {
    int? lastLobbyVersion,
  }) async {
    await ensureInitialized();
    final payload = <String, dynamic>{
      'roomId': roomId,
      if (lastLobbyVersion != null) 'lastLobbyVersion': lastLobbyVersion,
    };
    final response = await _emitWithAck('cc:room:subscribe', payload);
    final ack = ColorClashRoomSubscribeAck.fromJson(response);
    _trackedRoomVersions[roomId] = ack.lobby.lobbyVersion;
    return ack;
  }

  Future<ColorClashReconnectPayloadModel> subscribeMatch(
    String matchId, {
    int? lastVersion,
  }) async {
    final requestKey = '$matchId:${lastVersion ?? -1}';
    final existing = _matchSubscriptionsInFlight[requestKey];
    if (existing != null) {
      return existing;
    }

    final future = _subscribeMatchInternal(
      matchId,
      lastVersion: lastVersion,
    );
    _matchSubscriptionsInFlight[requestKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_matchSubscriptionsInFlight[requestKey], future)) {
        _matchSubscriptionsInFlight.remove(requestKey);
      }
    }
  }

  Future<ColorClashReconnectPayloadModel> _subscribeMatchInternal(
    String matchId, {
    int? lastVersion,
  }) async {
    await ensureInitialized();
    final response = await _emitWithAck(
      'cc:match:subscribe',
      <String, dynamic>{
        'matchId': matchId,
        if (lastVersion != null) 'lastVersion': lastVersion,
      },
    );
    final reconnect = ColorClashReconnectPayloadModel.fromJson(response);
    if (reconnect.snapshot != null) {
      _trackedMatchVersions[matchId] = reconnect.snapshot!.version;
    } else if (lastVersion != null) {
      _trackedMatchVersions[matchId] = lastVersion;
    }
    return reconnect;
  }

  Future<ColorClashCommandAck> sendMove({
    required String matchId,
    required String clientMoveId,
    required int expectedVersion,
    required Map<String, dynamic> move,
  }) async {
    await ensureInitialized();
    final response = await _emitWithAck(
      'cc:command:move',
      <String, dynamic>{
        'matchId': matchId,
        'clientMoveId': clientMoveId,
        'expectedVersion': expectedVersion,
        'move': move,
      },
    );
    return ColorClashCommandAck.fromJson(response);
  }

  Future<ColorClashCommandAck> sendChallenge({
    required String matchId,
    required String clientMoveId,
    required int expectedVersion,
    required String decision,
  }) async {
    await ensureInitialized();
    final response = await _emitWithAck(
      'cc:command:challenge',
      <String, dynamic>{
        'matchId': matchId,
        'clientMoveId': clientMoveId,
        'expectedVersion': expectedVersion,
        'decision': decision,
      },
    );
    return ColorClashCommandAck.fromJson(response);
  }

  Future<void> sendHeartbeat({
    String? roomId,
    String? matchId,
    String viewerRole = 'player',
  }) async {
    await ensureInitialized();
    await _emitWithAck(
      'cc:heartbeat',
      <String, dynamic>{
        if (roomId != null) 'roomId': roomId,
        if (matchId != null) 'matchId': matchId,
        'viewerRole': viewerRole,
      },
    );
  }

  Future<List<ColorClashRoomSubscribeAck>> resubscribeRooms() async {
    final results = <ColorClashRoomSubscribeAck>[];
    for (final entry in _trackedRoomVersions.entries) {
      results.add(
        await subscribeRoom(
          entry.key,
          lastLobbyVersion: entry.value,
        ),
      );
    }
    return results;
  }

  Future<List<ColorClashReconnectPayloadModel>> resubscribeMatches() async {
    final results = <ColorClashReconnectPayloadModel>[];
    for (final entry in _trackedMatchVersions.entries) {
      results.add(
        await subscribeMatch(
          entry.key,
          lastVersion: entry.value,
        ),
      );
    }
    return results;
  }

  void updateTrackedLobbyVersion(String roomId, int version) {
    _trackedRoomVersions[roomId] = version;
  }

  void updateTrackedMatchVersion(String matchId, int version) {
    _trackedMatchVersions[matchId] = version;
  }

  void forgetRoom(String roomId) {
    _trackedRoomVersions.remove(roomId);
  }

  void forgetMatch(String matchId) {
    _trackedMatchVersions.remove(matchId);
  }

  Future<void> dispose() async {
    _disposed = true;
    _roomSubscriptionsInFlight.clear();
    _matchSubscriptionsInFlight.clear();
    _unbindSocket();
    await _resyncSubscription?.cancel();
    _resyncSubscription = null;
    await _roomLobbyController.close();
    await _countdownStartedController.close();
    await _countdownCancelledController.close();
    await _matchStartedController.close();
    await _matchPatchController.close();
    await _lastCardAlertController.close();
    await _roundResultController.close();
    await _matchFinishedController.close();
    await _handStateController.close();
    await _drawResultController.close();
    await _challengePromptController.close();
    await _commandErrorController.close();
    await _queueMatchedController.close();
    await _resyncController.close();
  }

  void _bindCoreListeners() {
    if (_coreListenersBound || _disposed) return;
    _coreListenersBound = true;
    _resyncSubscription = SocketService.resyncStream.listen((event) {
      if (!_resyncController.isClosed) {
        _resyncController.add(event);
      }
      _bindSocket(SocketService.socket);
    });
  }

  void _bindSocket(io.Socket? socket) {
    if (socket == null || _disposed) return;
    if (identical(_boundSocket, socket)) return;
    _unbindSocket();
    _boundSocket = socket;

    socket.on('cc:room:lobby_state', (payload) {
      final lobby = ColorClashLobbyModel.fromJson(asMap(payload));
      _trackedRoomVersions[lobby.roomId] = lobby.lobbyVersion;
      _roomLobbyController.add(lobby);
    });
    socket.on('cc:room:countdown_started', (payload) {
      _countdownStartedController.add(
        ColorClashCountdownEvent.fromJson(asMap(payload)),
      );
    });
    socket.on('cc:room:countdown_cancelled', (payload) {
      _countdownCancelledController.add(
        ColorClashCountdownCancelledEvent.fromJson(asMap(payload)),
      );
    });
    socket.on('cc:room:match_started', (payload) {
      _matchStartedController.add(
        ColorClashMatchStartedEvent.fromJson(asMap(payload)),
      );
    });
    socket.on('cc:match:state_patch', (payload) {
      final event = ColorClashMatchPatchEvent.fromJson(asMap(payload));
      _trackedMatchVersions[event.matchId] = event.version;
      _matchPatchController.add(event);
    });
    socket.on('cc:match:last_card_alert', (payload) {
      _lastCardAlertController.add(
        ColorClashLastCardAlertEvent.fromJson(asMap(payload)),
      );
    });
    socket.on('cc:match:round_result', (payload) {
      _roundResultController.add(
        ColorClashRoundResultEvent.fromJson(asMap(payload)),
      );
    });
    socket.on('cc:match:finished', (payload) {
      _matchFinishedController.add(
        ColorClashMatchFinishedEvent.fromJson(asMap(payload)),
      );
    });
    socket.on('cc:player:hand_state', (payload) {
      final event = ColorClashPrivateStateEvent.fromJson(asMap(payload));
      _trackedMatchVersions[event.matchId] = event.version;
      _handStateController.add(event);
    });
    socket.on('cc:player:draw_result', (payload) {
      final event = ColorClashPrivateStateEvent.fromJson(asMap(payload));
      _trackedMatchVersions[event.matchId] = event.version;
      _drawResultController.add(event);
    });
    socket.on('cc:player:challenge_prompt', (payload) {
      final event = ColorClashPrivateStateEvent.fromJson(asMap(payload));
      _trackedMatchVersions[event.matchId] = event.version;
      _challengePromptController.add(event);
    });
    socket.on('cc:player:command_error', (payload) {
      _commandErrorController.add(
        ColorClashCommandErrorEvent.fromJson(asMap(payload)),
      );
    });
    socket.on('cc:queue:matched', (payload) {
      _queueMatchedController.add(
        ColorClashQueueMatchedEvent.fromJson(asMap(payload)),
      );
    });
  }

  void _unbindSocket() {
    if (_boundSocket == null) return;
    _boundSocket!
      ..off('cc:room:lobby_state')
      ..off('cc:room:countdown_started')
      ..off('cc:room:countdown_cancelled')
      ..off('cc:room:match_started')
      ..off('cc:match:state_patch')
      ..off('cc:match:last_card_alert')
      ..off('cc:match:round_result')
      ..off('cc:match:finished')
      ..off('cc:player:hand_state')
      ..off('cc:player:draw_result')
      ..off('cc:player:challenge_prompt')
      ..off('cc:player:command_error')
      ..off('cc:queue:matched');
    _boundSocket = null;
  }

  Future<Map<String, dynamic>> _emitWithAck(
    String event,
    Map<String, dynamic> payload,
  ) async {
    final socket = SocketService.socket;
    if (socket == null) {
      throw Exception('Color Clash socket is not connected.');
    }
    final response = await socket.emitWithAckAsync(event, payload);
    final map = asMap(response);
    if (map['ok'] == false) {
      final error = asMap(map['error']);
      throw Exception(
        error['message']?.toString() ?? 'Color Clash realtime request failed.',
      );
    }
    return map;
  }
}

class ColorClashRoomSubscribeAck {
  const ColorClashRoomSubscribeAck({
    required this.roomId,
    required this.viewerRole,
    required this.lobby,
  });

  final String roomId;
  final String viewerRole;
  final ColorClashLobbyModel lobby;

  factory ColorClashRoomSubscribeAck.fromJson(Map<String, dynamic> json) {
    return ColorClashRoomSubscribeAck(
      roomId: asId(json['roomId']),
      viewerRole: json['viewerRole']?.toString() ?? 'spectator',
      lobby: ColorClashLobbyModel.fromJson(asMap(json['lobby'])),
    );
  }
}

class ColorClashCountdownEvent {
  const ColorClashCountdownEvent({
    required this.roomId,
    required this.lobbyVersion,
    required this.countdownEndsAt,
  });

  final String roomId;
  final int lobbyVersion;
  final int countdownEndsAt;

  factory ColorClashCountdownEvent.fromJson(Map<String, dynamic> json) {
    return ColorClashCountdownEvent(
      roomId: asId(json['roomId']),
      lobbyVersion: asInt(json['lobbyVersion']),
      countdownEndsAt: asInt(json['countdownEndsAt']),
    );
  }
}

class ColorClashCountdownCancelledEvent {
  const ColorClashCountdownCancelledEvent({
    required this.roomId,
    required this.lobbyVersion,
    required this.reason,
  });

  final String roomId;
  final int lobbyVersion;
  final String reason;

  factory ColorClashCountdownCancelledEvent.fromJson(
    Map<String, dynamic> json,
  ) {
    return ColorClashCountdownCancelledEvent(
      roomId: asId(json['roomId']),
      lobbyVersion: asInt(json['lobbyVersion']),
      reason: json['reason']?.toString() ?? '',
    );
  }
}

class ColorClashMatchStartedEvent {
  const ColorClashMatchStartedEvent({
    required this.roomId,
    required this.matchId,
    required this.version,
    required this.players,
  });

  final String roomId;
  final String matchId;
  final int version;
  final List<ColorClashMatchStartedPlayer> players;

  factory ColorClashMatchStartedEvent.fromJson(Map<String, dynamic> json) {
    return ColorClashMatchStartedEvent(
      roomId: asId(json['roomId']),
      matchId: asId(json['matchId']),
      version: asInt(json['version'], fallback: 1),
      players: asMapList(json['players'])
          .map(ColorClashMatchStartedPlayer.fromJson)
          .toList(growable: false),
    );
  }
}

class ColorClashMatchStartedPlayer {
  const ColorClashMatchStartedPlayer({
    required this.userId,
    required this.seatIndex,
    required this.username,
    required this.avatar,
  });

  final String userId;
  final int seatIndex;
  final String username;
  final String avatar;

  factory ColorClashMatchStartedPlayer.fromJson(Map<String, dynamic> json) {
    return ColorClashMatchStartedPlayer(
      userId: asId(json['userId']),
      seatIndex: asInt(json['seatIndex']),
      username: json['username']?.toString() ?? 'Guest',
      avatar: json['avatar']?.toString() ?? '',
    );
  }
}

class ColorClashMatchPatchEvent {
  const ColorClashMatchPatchEvent({
    required this.matchId,
    required this.roomId,
    required this.version,
    required this.publicState,
    required this.events,
    this.actorSeat,
  });

  final String matchId;
  final String roomId;
  final int version;
  final int? actorSeat;
  final ColorClashPublicMatchStateModel publicState;
  final List<Map<String, dynamic>> events;

  factory ColorClashMatchPatchEvent.fromJson(Map<String, dynamic> json) {
    return ColorClashMatchPatchEvent(
      matchId: asId(json['matchId']),
      roomId: asId(json['roomId']),
      version: asInt(json['version'], fallback: 1),
      actorSeat: json['actorSeat'] == null ? null : asInt(json['actorSeat']),
      publicState:
          ColorClashPublicMatchStateModel.fromJson(asMap(json['publicState'])),
      events: asMapList(json['events']),
    );
  }
}

class ColorClashLastCardAlertEvent {
  const ColorClashLastCardAlertEvent({
    required this.matchId,
    required this.roomId,
    required this.version,
    required this.seatIndex,
  });

  final String matchId;
  final String roomId;
  final int version;
  final int seatIndex;

  factory ColorClashLastCardAlertEvent.fromJson(Map<String, dynamic> json) {
    return ColorClashLastCardAlertEvent(
      matchId: asId(json['matchId']),
      roomId: asId(json['roomId']),
      version: asInt(json['version'], fallback: 1),
      seatIndex: asInt(json['seatIndex']),
    );
  }
}

class ColorClashRoundResultEvent {
  const ColorClashRoundResultEvent({
    required this.matchId,
    required this.roomId,
    required this.version,
    required this.result,
  });

  final String matchId;
  final String roomId;
  final int version;
  final ColorClashRoundResultModel result;

  factory ColorClashRoundResultEvent.fromJson(Map<String, dynamic> json) {
    return ColorClashRoundResultEvent(
      matchId: asId(json['matchId']),
      roomId: asId(json['roomId']),
      version: asInt(json['version'], fallback: 1),
      result: ColorClashRoundResultModel.fromJson(asMap(json['result'])),
    );
  }
}

class ColorClashMatchFinishedEvent {
  const ColorClashMatchFinishedEvent({
    required this.matchId,
    required this.roomId,
    required this.version,
    required this.result,
  });

  final String matchId;
  final String roomId;
  final int version;
  final ColorClashRoundResultModel result;

  factory ColorClashMatchFinishedEvent.fromJson(Map<String, dynamic> json) {
    return ColorClashMatchFinishedEvent(
      matchId: asId(json['matchId']),
      roomId: asId(json['roomId']),
      version: asInt(json['version'], fallback: 1),
      result: ColorClashRoundResultModel.fromJson(asMap(json['result'])),
    );
  }
}

class ColorClashPrivateStateEvent {
  const ColorClashPrivateStateEvent({
    required this.matchId,
    required this.roomId,
    required this.version,
    required this.seatIndex,
    required this.privateState,
  });

  final String matchId;
  final String roomId;
  final int version;
  final int seatIndex;
  final ColorClashPrivateMatchStateModel privateState;

  factory ColorClashPrivateStateEvent.fromJson(Map<String, dynamic> json) {
    return ColorClashPrivateStateEvent(
      matchId: asId(json['matchId']),
      roomId: asId(json['roomId']),
      version: asInt(json['version'], fallback: 1),
      seatIndex: asInt(json['seatIndex']),
      privateState: ColorClashPrivateMatchStateModel.fromJson(
        asMap(json['privateState']),
      ),
    );
  }
}

class ColorClashCommandErrorEvent {
  const ColorClashCommandErrorEvent({
    required this.matchId,
    required this.clientMoveId,
    required this.errorCode,
    required this.message,
    required this.snapshotRequired,
    this.currentVersion,
  });

  final String matchId;
  final String clientMoveId;
  final String errorCode;
  final String message;
  final bool snapshotRequired;
  final int? currentVersion;

  factory ColorClashCommandErrorEvent.fromJson(Map<String, dynamic> json) {
    return ColorClashCommandErrorEvent(
      matchId: asId(json['matchId']),
      clientMoveId: json['clientMoveId']?.toString() ?? '',
      errorCode: json['errorCode']?.toString() ?? 'COMMAND_ERROR',
      message: json['message']?.toString() ?? 'Move rejected',
      snapshotRequired: asBool(json['snapshotRequired']),
      currentVersion:
          json['currentVersion'] == null ? null : asInt(json['currentVersion']),
    );
  }
}

class ColorClashQueueMatchedEvent {
  const ColorClashQueueMatchedEvent({
    required this.roomId,
    required this.matchId,
    required this.mode,
    required this.stakeAmount,
  });

  final String roomId;
  final String matchId;
  final String mode;
  final int stakeAmount;

  factory ColorClashQueueMatchedEvent.fromJson(Map<String, dynamic> json) {
    return ColorClashQueueMatchedEvent(
      roomId: asId(json['roomId']),
      matchId: asId(json['matchId']),
      mode: json['mode']?.toString() ?? 'casual_free',
      stakeAmount: asInt(json['stakeAmount']),
    );
  }
}

class ColorClashCommandAck {
  const ColorClashCommandAck({
    required this.ok,
    required this.accepted,
    required this.duplicate,
    required this.matchId,
    required this.version,
    required this.snapshotRequired,
    this.errorCode,
  });

  final bool ok;
  final bool accepted;
  final bool duplicate;
  final String matchId;
  final int? version;
  final bool snapshotRequired;
  final String? errorCode;

  factory ColorClashCommandAck.fromJson(Map<String, dynamic> json) {
    return ColorClashCommandAck(
      ok: asBool(json['ok'], fallback: true),
      accepted: asBool(json['accepted']),
      duplicate: asBool(json['duplicate']),
      matchId: asId(json['matchId']),
      version: json['version'] == null ? null : asInt(json['version']),
      snapshotRequired: asBool(json['snapshotRequired']),
      errorCode: json['errorCode']?.toString(),
    );
  }
}
