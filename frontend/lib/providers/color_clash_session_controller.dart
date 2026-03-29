import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/color_clash_card_model.dart';
import '../models/color_clash_home_model.dart';
import '../models/color_clash_lobby_model.dart';
import '../models/color_clash_match_snapshot.dart';
import '../models/color_clash_season_model.dart';
import '../models/color_clash_settlement_model.dart';
import '../models/color_clash_table_model.dart';
import '../services/color_clash_service.dart';
import '../services/color_clash_socket_service.dart';
import '../services/color_clash_telemetry_service.dart';

class ColorClashSessionController extends ChangeNotifier {
  ColorClashSessionController({
    ColorClashService? service,
    ColorClashSocketService? socketService,
    ColorClashTelemetryService? telemetry,
  })  : _service = service ?? ColorClashService(),
        _socketService = socketService ?? ColorClashSocketService(),
        _telemetry = telemetry ?? const ColorClashTelemetryService() {
    _bindSocketStreams();
  }

  final ColorClashService _service;
  final ColorClashSocketService _socketService;
  final ColorClashTelemetryService _telemetry;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  final Set<String> _matchReloadsInFlight = <String>{};
  Timer? _settlementPollTimer;
  Timer? _statusNoticeTimer;

  ColorClashHomeModel? _home;
  ColorClashTablesPayload? _tables;
  ColorClashSeasonSummaryModel? _seasonSummary;
  ColorClashLobbySessionModel? _lobbySession;
  ColorClashMatchSnapshotModel? _matchSnapshot;
  ColorClashSettlementSummaryModel? _settlementSummary;
  ColorClashMatchmakingState _matchmakingState =
      const ColorClashMatchmakingState();
  ColorClashReconnectState _reconnectState = const ColorClashReconnectState();
  ColorClashStatusNotice? _statusNotice;
  ColorClashPendingMatchTarget? _pendingMatchTarget;
  String? _selectedCardId;
  bool _isSubmittingMove = false;
  int? _pendingCommandVersion;
  String? _lastActionSummary;

  bool _isHomeLoading = false;
  bool _isTablesLoading = false;
  bool _isLobbyLoading = false;
  bool _isMatchLoading = false;
  bool _isSeasonLoading = false;
  bool _isSettlementLoading = false;

  String? _homeError;
  String? _tablesError;
  String? _lobbyError;
  String? _matchError;
  String? _seasonError;
  String? _settlementError;
  String? _lastRealtimeError;

  ColorClashHomeModel? get home => _home;
  ColorClashTablesPayload? get tables => _tables;
  ColorClashSeasonSummaryModel? get seasonSummary => _seasonSummary;
  ColorClashLobbySessionModel? get lobbySession => _lobbySession;
  ColorClashMatchSnapshotModel? get matchSnapshot => _matchSnapshot;
  ColorClashSettlementSummaryModel? get settlementSummary => _settlementSummary;
  ColorClashMatchmakingState get matchmakingState => _matchmakingState;
  ColorClashReconnectState get reconnectState => _reconnectState;
  ColorClashStatusNotice? get statusNotice => _statusNotice;
  ColorClashPendingMatchTarget? get pendingMatchTarget => _pendingMatchTarget;
  String? get selectedCardId => _selectedCardId;
  bool get isSubmittingMove => _isSubmittingMove;
  String? get lastActionSummary => _lastActionSummary;

  bool get isHomeLoading => _isHomeLoading;
  bool get isTablesLoading => _isTablesLoading;
  bool get isLobbyLoading => _isLobbyLoading;
  bool get isMatchLoading => _isMatchLoading;
  bool get isSeasonLoading => _isSeasonLoading;
  bool get isSettlementLoading => _isSettlementLoading;

  String? get homeError => _homeError;
  String? get tablesError => _tablesError;
  String? get lobbyError => _lobbyError;
  String? get matchError => _matchError;
  String? get seasonError => _seasonError;
  String? get settlementError => _settlementError;
  String? get lastRealtimeError => _lastRealtimeError;

  String? get activeMatchId =>
      _matchSnapshot?.matchId ??
      _pendingMatchTarget?.matchId ??
      _home?.activeMatch?.matchId;

  String? get activeRoomId =>
      _lobbySession?.room.roomId ??
      _matchSnapshot?.roomId ??
      _pendingMatchTarget?.roomId ??
      _home?.activeMatch?.roomId;

  bool get hasActiveMatch =>
      (activeMatchId ?? '').isNotEmpty || _home?.hasActiveMatch == true;

  bool get canResumeActiveMatch =>
      (home?.activeMatch?.matchId ?? '').isNotEmpty;

  ColorClashRoomSummaryModel? get currentRoomSummary {
    if (_lobbySession != null) {
      return _lobbySession!.room;
    }

    final roomId = activeRoomId;
    if ((roomId ?? '').isEmpty) {
      return null;
    }

    for (final room in _home?.rooms ?? const <ColorClashRoomSummaryModel>[]) {
      if (room.roomId == roomId) {
        return room;
      }
    }

    return null;
  }

  ColorClashPublicMatchStateModel? get publicMatchState =>
      _matchSnapshot?.publicState;

  ColorClashPrivateMatchStateModel? get privateMatchState =>
      _matchSnapshot?.privateState;

  String get currentViewerRole =>
      _matchSnapshot?.viewerRole ?? _lobbySession?.viewerRole ?? 'spectator';

  bool get isSpectatorView =>
      _matchSnapshot?.isSpectatorView ??
      (_lobbySession?.viewerRole == 'spectator');

  bool get isPlayerView => _matchSnapshot?.isPlayerView == true;

  int? get mySeatIndex => _matchSnapshot?.privateState?.seatIndex;

  ColorClashCardModel? get selectedCard {
    final cardId = _selectedCardId;
    if (cardId == null || cardId.isEmpty) {
      return null;
    }
    for (final card in _matchSnapshot?.privateState?.hand ??
        const <ColorClashCardModel>[]) {
      if (card.id == cardId) {
        return card;
      }
    }
    return null;
  }

  bool get isMyTurn {
    final privateState = _matchSnapshot?.privateState;
    return privateState != null &&
        privateState.currentTurnSeat == privateState.seatIndex &&
        !matchFinished;
  }

  bool get canDraw =>
      !_isSubmittingMove && isPlayerView && privateMatchState?.canDraw == true;

  bool get canKeepDrawn =>
      !_isSubmittingMove &&
      isPlayerView &&
      privateMatchState?.canKeepDrawn == true;

  bool get canChallenge =>
      !_isSubmittingMove &&
      isPlayerView &&
      privateMatchState?.canChallenge == true;

  bool get canDeclineChallenge =>
      !_isSubmittingMove &&
      isPlayerView &&
      privateMatchState?.canDeclineChallenge == true;

  bool get hasPendingPrompt => privateMatchState?.hasPrompt == true;

  bool get matchFinished => _matchSnapshot?.isCompleted == true;

  DateTime? get turnEndsAt {
    final endsAt = _matchSnapshot?.publicState.turnContext?.turnEndsAt;
    if (endsAt == null || endsAt <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(endsAt);
  }

  Set<String> get playableCardIds {
    final privateState = privateMatchState;
    if (privateState == null) {
      return const <String>{};
    }
    return privateState.legalMoves
        .where((entry) => entry.isCardPlay)
        .map((entry) => entry.cardId!)
        .toSet();
  }

  bool get canPlaySelectedCard =>
      !_isSubmittingMove &&
      selectedCard != null &&
      legalMovesForCard(selectedCard!.id).isNotEmpty;

  List<ColorClashLegalMoveModel> legalMovesForCard(String cardId) =>
      privateMatchState?.legalMovesForCard(cardId) ??
      const <ColorClashLegalMoveModel>[];

  List<String> availableHuesForCard(String cardId) {
    final values = <String>{};
    for (final move in legalMovesForCard(cardId)) {
      if ((move.chosenHue ?? '').isNotEmpty) {
        values.add(move.chosenHue!);
      }
    }
    return values.toList(growable: false);
  }

  List<int> availableTargetsForCard(String cardId) {
    final values = <int>{};
    for (final move in legalMovesForCard(cardId)) {
      if (move.targetSeat != null) {
        values.add(move.targetSeat!);
      }
    }
    final targets = values.toList(growable: false);
    targets.sort();
    return targets;
  }

  bool cardNeedsHueChoice(String cardId) =>
      availableHuesForCard(cardId).length > 1;

  bool cardNeedsTargetChoice(String cardId) =>
      availableTargetsForCard(cardId).isNotEmpty;

  ColorClashLobbyPlayerModel? lobbyPlayerForUser(String? userId) {
    if ((userId ?? '').isEmpty) {
      return null;
    }
    return _lobbySession?.lobby.playersByUserId[userId!];
  }

  Future<void> loadHome({bool force = false}) async {
    if (_isHomeLoading) return;
    if (!force && _home != null) return;

    _isHomeLoading = true;
    _homeError = null;
    notifyListeners();

    try {
      _home = await _service.getHome();
      final eligibility = _home?.userProgress.eligibility;
      _telemetry.track(
        'home_viewed',
        payload: <String, Object?>{
          'activeMatchId': _home?.activeMatch?.matchId,
          'queueTicketId': _home?.userProgress.activeQueueTicketId,
          'rankedEligible': eligibility?.rankedEligible,
          'stakeEligible': eligibility?.stakeEligible,
        },
      );
      if (_home?.season != null) {
        _seasonSummary ??= ColorClashSeasonSummaryModel(
          season: _home!.season,
          leaderboardPreview: _home!.leaderboardPreview,
          rewardPreview: _home!.rewardPreview,
          userProgress: _home!.userProgress.currentSeason,
          userRank: _home!.userProgress.currentUserRank,
          eligibility: _home!.userProgress.eligibility,
        );
      }
      if (_matchmakingState.queueTicketId == null &&
          (_home?.userProgress.activeQueueTicketId ?? '').isNotEmpty) {
        _matchmakingState = _matchmakingState.copyWith(
          stage: ColorClashQueueStage.queued,
          queueTicketId: _home!.userProgress.activeQueueTicketId,
        );
      }
    } catch (error) {
      _homeError = _cleanError(error);
    } finally {
      _isHomeLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadTables({
    String? mode,
    bool force = false,
  }) async {
    if (_isTablesLoading) return;
    if (!force && _tables != null && (mode == null || mode.isEmpty)) return;

    _isTablesLoading = true;
    _tablesError = null;
    notifyListeners();

    try {
      _tables = await _service.getTables(mode: mode);
      _telemetry.track(
        'tables_loaded',
        payload: <String, Object?>{
          'mode': mode ?? 'all',
          'roomCount': _tables?.rooms.length ?? 0,
          'presetCount': _tables?.queuePresets.length ?? 0,
        },
      );
    } catch (error) {
      _tablesError = _cleanError(error);
    } finally {
      _isTablesLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSeasonSummary({bool force = false}) async {
    if (_isSeasonLoading) return;
    if (!force && _seasonSummary != null) return;

    _isSeasonLoading = true;
    _seasonError = null;
    notifyListeners();

    try {
      _seasonSummary = await _service.getCurrentSeason();
      _telemetry.track(
        'season_summary_loaded',
        payload: <String, Object?>{
          'seasonKey': _seasonSummary?.season?.key,
          'tierId': _seasonSummary?.userProgress?.tierId,
          'rankedEligible': _seasonSummary?.eligibility?.rankedEligible,
        },
      );
    } catch (error) {
      _seasonError = _cleanError(error);
    } finally {
      _isSeasonLoading = false;
      notifyListeners();
    }
  }

  Future<ColorClashLobbySessionModel?> createFriendRoom({
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
    _lobbyError = null;
    notifyListeners();

    try {
      final session = await _service.createFriendRoom(
        name: name,
        description: description,
        visibility: visibility,
        allowSpectators: allowSpectators,
        maxPlayers: maxPlayers,
        minPlayersToStart: minPlayersToStart,
        countdownSec: countdownSec,
        turnTimeoutSec: turnTimeoutSec,
        themePackId: themePackId,
        tableMode: tableMode,
        stakeEntryFee: stakeEntryFee,
        stakePayouts: stakePayouts,
        houseFeeBps: houseFeeBps,
        sinkFeeBps: sinkFeeBps,
        invitedUserIds: invitedUserIds,
        customCards: customCards,
      );
      _lobbySession = session;
      _telemetry.track(
        'room_created',
        payload: <String, Object?>{
          'roomId': session.room.roomId,
          'tableMode': session.room.tableMode,
          'visibility': session.room.visibility,
          'stakeEntryFee': session.room.stake.entryFee,
        },
      );
      _socketService.updateTrackedLobbyVersion(
        session.room.roomId,
        session.lobby.lobbyVersion,
      );
      await subscribeLobby(session.room.roomId);
      notifyListeners();
      return session;
    } catch (error) {
      _lobbyError = _cleanError(error);
      notifyListeners();
      return null;
    }
  }

  Future<ColorClashLobbySessionModel?> joinRoom(
    String roomId, {
    bool spectator = false,
  }) async {
    _isLobbyLoading = true;
    _lobbyError = null;
    notifyListeners();

    try {
      final session = await _service.joinRoom(roomId, spectator: spectator);
      _lobbySession = session;
      _telemetry.track(
        spectator ? 'spectator_joined' : 'room_joined',
        payload: <String, Object?>{
          'roomId': roomId,
          'viewerRole': session.viewerRole,
        },
      );
      _socketService.updateTrackedLobbyVersion(
        roomId,
        session.lobby.lobbyVersion,
      );
      await subscribeLobby(roomId);
      return session;
    } catch (error) {
      _lobbyError = _cleanError(error);
      return null;
    } finally {
      _isLobbyLoading = false;
      notifyListeners();
    }
  }

  Future<ColorClashMatchmakingJoinResult?> joinMatchmaking({
    required String mode,
    int? stakeAmount,
    String? region,
    String? themePackId,
  }) async {
    _matchmakingState = _matchmakingState.copyWith(
      stage: ColorClashQueueStage.joining,
      mode: mode,
      stakeAmount: stakeAmount ?? 0,
      errorMessage: null,
    );
    notifyListeners();

    try {
      final result = await _service.joinMatchmaking(
        mode: mode,
        stakeAmount: stakeAmount,
        region: region,
        themePackId: themePackId,
      );

      _matchmakingState = _matchmakingState.copyWith(
        stage: result.status == 'matched'
            ? ColorClashQueueStage.matched
            : ColorClashQueueStage.queued,
        queueTicketId: result.queueTicketId,
        estimatedWaitMs: result.estimatedWaitMs,
        matchedRoomId: result.room?.roomId,
        matchedMatchId: result.match?.matchId,
        errorMessage: null,
      );

      if (result.room != null && result.match != null) {
        _pendingMatchTarget = ColorClashPendingMatchTarget(
          roomId: result.room!.roomId,
          matchId: result.match!.matchId,
          source: 'queue_join',
        );
      }

      _telemetry.track(
        'queue_joined',
        payload: <String, Object?>{
          'mode': mode,
          'stakeAmount': stakeAmount ?? 0,
          'status': result.status,
          'queueTicketId': result.queueTicketId,
          'matchedMatchId': result.match?.matchId,
        },
      );

      notifyListeners();
      return result;
    } catch (error) {
      _matchmakingState = _matchmakingState.copyWith(
        stage: ColorClashQueueStage.error,
        errorMessage: _cleanError(error),
      );
      notifyListeners();
      return null;
    }
  }

  Future<bool> leaveMatchmaking() async {
    if (_matchmakingState.stage == ColorClashQueueStage.leaving) return false;

    _matchmakingState = _matchmakingState.copyWith(
      stage: ColorClashQueueStage.leaving,
      errorMessage: null,
    );
    notifyListeners();

    try {
      final queueTicketId = _matchmakingState.queueTicketId;
      await _service.leaveMatchmaking(
        queueTicketId: queueTicketId,
      );
      _telemetry.track(
        'queue_left',
        payload: <String, Object?>{
          'queueTicketId': queueTicketId,
          'mode': _matchmakingState.mode,
        },
      );
      _matchmakingState = const ColorClashMatchmakingState();
      notifyListeners();
      return true;
    } catch (error) {
      _matchmakingState = _matchmakingState.copyWith(
        stage: ColorClashQueueStage.error,
        errorMessage: _cleanError(error),
      );
      notifyListeners();
      return false;
    }
  }

  Future<ColorClashReadyResult?> setReady({
    required bool ready,
    int? seatIndex,
  }) async {
    final roomId = _lobbySession?.room.roomId;
    if (roomId == null || roomId.isEmpty) {
      _lobbyError = 'No active Color Clash lobby is open.';
      notifyListeners();
      return null;
    }

    try {
      final result = await _service.setReady(
        roomId: roomId,
        ready: ready,
        seatIndex: seatIndex,
      );
      _lobbySession = ColorClashLobbySessionModel(
        room: _lobbySession!.room,
        lobby: result.lobby,
        viewerRole: result.viewerRole,
      );
      _socketService.updateTrackedLobbyVersion(
          roomId, result.lobby.lobbyVersion);
      _telemetry.track(
        'ready_toggled',
        payload: <String, Object?>{
          'roomId': roomId,
          'ready': ready,
          'seatIndex': seatIndex,
          'lobbyVersion': result.lobby.lobbyVersion,
        },
      );
      notifyListeners();
      return result;
    } catch (error) {
      _lobbyError = _cleanError(error);
      notifyListeners();
      return null;
    }
  }

  Future<ColorClashLobbySessionModel?> loadLobby(
    String roomId, {
    bool force = false,
  }) async {
    if (_isLobbyLoading) return _lobbySession;
    if (!force && _lobbySession?.room.roomId == roomId) return _lobbySession;

    _isLobbyLoading = true;
    _lobbyError = null;
    notifyListeners();

    try {
      _lobbySession = await _service.getLobby(roomId);
      _socketService.updateTrackedLobbyVersion(
        roomId,
        _lobbySession!.lobby.lobbyVersion,
      );
      return _lobbySession;
    } catch (error) {
      _lobbyError = _cleanError(error);
      return null;
    } finally {
      _isLobbyLoading = false;
      notifyListeners();
    }
  }

  Future<void> subscribeLobby(String roomId) async {
    final lastVersion = _lobbySession?.room.roomId == roomId
        ? _lobbySession?.lobby.lobbyVersion
        : null;
    final ack = await _socketService.subscribeRoom(
      roomId,
      lastLobbyVersion: lastVersion,
    );
    if (_lobbySession == null || _lobbySession!.room.roomId == roomId) {
      final room = _lobbySession?.room;
      if (room != null) {
        _lobbySession = ColorClashLobbySessionModel(
          room: room,
          lobby: ack.lobby,
          viewerRole: ack.viewerRole,
        );
      }
      notifyListeners();
    }
  }

  Future<ColorClashMatchSnapshotModel?> loadMatchSnapshot(
    String matchId, {
    bool force = false,
  }) async {
    if (_isMatchLoading) return _matchSnapshot;
    if (!force && _matchSnapshot?.matchId == matchId) return _matchSnapshot;

    _isMatchLoading = true;
    _matchError = null;
    notifyListeners();

    try {
      _matchSnapshot = await _service.getMatchSnapshot(matchId);
      _socketService.updateTrackedMatchVersion(
          matchId, _matchSnapshot!.version);
      _syncPendingCommandState();
      if (_matchSnapshot!.isCompleted) {
        unawaited(loadSettlementSummary(matchId, pollIfPending: true));
      }
      return _matchSnapshot;
    } catch (error) {
      _matchError = _cleanError(error);
      return null;
    } finally {
      _isMatchLoading = false;
      notifyListeners();
    }
  }

  Future<void> subscribeMatch(String matchId) async {
    final reconnectPayload = await _socketService.subscribeMatch(
      matchId,
      lastVersion:
          _matchSnapshot?.matchId == matchId ? _matchSnapshot?.version : null,
    );
    await _applyReconnectPayload(matchId, reconnectPayload);
  }

  Future<ColorClashMatchSnapshotModel?> reconnectMatch(
    String matchId, {
    int? lastKnownVersion,
  }) async {
    _reconnectState = _reconnectState.copyWith(
      status: ColorClashReconnectStatus.reconnecting,
      message: null,
      failedMatchId: null,
    );
    showStatusNotice(
      'Reconnecting to the live Color Clash session.',
      tone: ColorClashNoticeTone.info,
    );
    _telemetry.track(
      'reconnect_attempted',
      payload: <String, Object?>{
        'matchId': matchId,
        'lastKnownVersion': lastKnownVersion ?? _matchSnapshot?.version ?? 0,
      },
    );
    notifyListeners();

    try {
      final reconnectPayload = await _service.reconnectMatch(
        matchId,
        lastKnownVersion: lastKnownVersion ?? _matchSnapshot?.version ?? 0,
      );
      final snapshot = await _applyReconnectPayload(matchId, reconnectPayload);
      await _socketService.subscribeMatch(
        matchId,
        lastVersion: snapshot?.version,
      );
      _reconnectState = _reconnectState.copyWith(
        status: ColorClashReconnectStatus.ready,
        message: 'Match synced',
        failedMatchId: null,
      );
      _pendingMatchTarget = null;
      _syncPendingCommandState();
      showStatusNotice(
        'Color Clash is back in sync.',
        tone: ColorClashNoticeTone.success,
      );
      _telemetry.track(
        'reconnect_succeeded',
        payload: <String, Object?>{
          'matchId': matchId,
          'version': snapshot?.version ?? 0,
        },
      );
      notifyListeners();
      return snapshot;
    } catch (error) {
      _matchError = _cleanError(error);
      _reconnectState = _reconnectState.copyWith(
        status: ColorClashReconnectStatus.failed,
        message: _matchError,
        failedMatchId: matchId,
      );
      showStatusNotice(
        _matchError ?? 'We could not restore the match yet.',
        tone: ColorClashNoticeTone.error,
      );
      _telemetry.track(
        'reconnect_failed',
        payload: <String, Object?>{
          'matchId': matchId,
          'error': _matchError,
        },
      );
      notifyListeners();
      return null;
    }
  }

  Future<ColorClashRematchResult?> voteRematch(bool vote) async {
    final matchId = activeMatchId;
    if (matchId == null || matchId.isEmpty) return null;

    try {
      final result = await _service.voteRematch(matchId: matchId, vote: vote);
      _telemetry.track(
        'rematch_vote_sent',
        payload: <String, Object?>{
          'matchId': matchId,
          'vote': vote,
          'matched': result.isMatched,
        },
      );
      if (_lobbySession != null &&
          _lobbySession!.room.roomId == result.roomId &&
          result.lobbyVersion != null) {
        _lobbySession = ColorClashLobbySessionModel(
          room: _lobbySession!.room,
          lobby: ColorClashLobbyModel(
            roomId: _lobbySession!.lobby.roomId,
            gameId: _lobbySession!.lobby.gameId,
            lobbyVersion: result.lobbyVersion!,
            status: _lobbySession!.lobby.status,
            activeMatchId: result.match,
            minPlayersToStart: _lobbySession!.lobby.minPlayersToStart,
            maxPlayers: _lobbySession!.lobby.maxPlayers,
            countdownSec: _lobbySession!.lobby.countdownSec,
            allowSpectators: _lobbySession!.lobby.allowSpectators,
            seats: _lobbySession!.lobby.seats,
            playersByUserId: _lobbySession!.lobby.playersByUserId,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
            countdownEndsAt: _lobbySession!.lobby.countdownEndsAt,
            rematchWindowEndsAt: result.rematchWindowEndsAt,
            rematchVotesByUserId: result.votes,
          ),
          viewerRole: _lobbySession!.viewerRole,
        );
      }
      if (result.isMatched && result.match != null) {
        _pendingMatchTarget = ColorClashPendingMatchTarget(
          roomId: result.roomId,
          matchId: result.match!,
          source: 'rematch',
        );
      }
      notifyListeners();
      return result;
    } catch (error) {
      _matchError = _cleanError(error);
      notifyListeners();
      return null;
    }
  }

  Future<bool> cancelRoom({String? reason}) async {
    final roomId = _lobbySession?.room.roomId;
    if (roomId == null || roomId.isEmpty) return false;

    try {
      final result = await _service.cancelRoom(roomId, reason: reason);
      _lobbySession = ColorClashLobbySessionModel(
        room: _lobbySession!.room,
        lobby: result.lobby,
        viewerRole: _lobbySession!.viewerRole,
      );
      showStatusNotice(
        'The room was cancelled before the next round started.',
        tone: ColorClashNoticeTone.warning,
      );
      _telemetry.track(
        'room_cancelled',
        payload: <String, Object?>{
          'roomId': roomId,
          'reason': reason,
        },
      );
      notifyListeners();
      return true;
    } catch (error) {
      _lobbyError = _cleanError(error);
      notifyListeners();
      return false;
    }
  }

  Future<void> resubscribeAfterReconnect() async {
    try {
      if (_lobbySession != null) {
        await subscribeLobby(_lobbySession!.room.roomId);
      }
      if (_matchSnapshot != null) {
        await reconnectMatch(
          _matchSnapshot!.matchId,
          lastKnownVersion: _matchSnapshot!.version,
        );
      }
    } catch (error) {
      _lastRealtimeError = _cleanError(error);
      showStatusNotice(
        _lastRealtimeError ?? 'Color Clash sync needs attention.',
        tone: ColorClashNoticeTone.warning,
      );
      notifyListeners();
    }
  }

  Future<ColorClashMatchSnapshotModel?> openMatch(
    String matchId, {
    String? roomId,
    bool forceReconnect = false,
  }) async {
    final resolvedRoomId =
        roomId ?? _lobbySession?.room.roomId ?? _matchSnapshot?.roomId;

    if ((resolvedRoomId ?? '').isNotEmpty) {
      try {
        await loadLobby(resolvedRoomId!, force: true);
        await subscribeLobby(resolvedRoomId);
      } catch (_) {
        // The match screen can still recover from match snapshots even if the
        // surrounding lobby shell is temporarily unavailable.
      }
    }

    _pendingMatchTarget = null;
    _telemetry.track(
      'match_open_requested',
      payload: <String, Object?>{
        'matchId': matchId,
        'roomId': resolvedRoomId,
        'forceReconnect': forceReconnect,
      },
    );

    if (forceReconnect) {
      return reconnectMatch(
        matchId,
        lastKnownVersion:
            _matchSnapshot?.matchId == matchId ? _matchSnapshot?.version : 0,
      );
    }

    final snapshot = await loadMatchSnapshot(matchId, force: true);
    if (snapshot == null) {
      return null;
    }
    await subscribeMatch(matchId);
    await sendHeartbeat();
    _telemetry.track(
      'match_opened',
      payload: <String, Object?>{
        'matchId': matchId,
        'roomId': resolvedRoomId,
        'viewerRole': _matchSnapshot?.viewerRole,
      },
    );
    return _matchSnapshot;
  }

  Future<ColorClashSettlementSummaryModel?> loadSettlementSummary(
    String matchId, {
    bool pollIfPending = false,
  }) async {
    if (_isSettlementLoading && _settlementSummary?.matchId == matchId) {
      return _settlementSummary;
    }

    _settlementPollTimer?.cancel();
    _isSettlementLoading = true;
    _settlementError = null;
    notifyListeners();

    try {
      _settlementSummary = await _service.getSettlementSummary(matchId);
      _telemetry.track(
        'settlement_summary_loaded',
        payload: <String, Object?>{
          'matchId': matchId,
          'status': _settlementSummary?.status,
          'rankStatus': _settlementSummary?.rankProgression?.status,
        },
      );
      await _applySettlementSummaryEffects(_settlementSummary!);
      if (pollIfPending && _settlementSummary!.isPending) {
        _scheduleSettlementPoll(matchId);
      }
      return _settlementSummary;
    } catch (error) {
      _settlementError = _cleanError(error);
      showStatusNotice(
        _settlementError ?? 'Settlement status is still loading.',
        tone: ColorClashNoticeTone.warning,
      );
      return null;
    } finally {
      _isSettlementLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendHeartbeat() async {
    final matchId = _matchSnapshot?.matchId;
    if (matchId == null || matchId.isEmpty) {
      return;
    }
    try {
      await _socketService.sendHeartbeat(
        roomId: _matchSnapshot?.roomId ?? _lobbySession?.room.roomId,
        matchId: matchId,
        viewerRole: currentViewerRole,
      );
    } catch (error) {
      _lastRealtimeError = _cleanError(error);
      showStatusNotice(
        _lastRealtimeError ?? 'Heartbeat sync needs a refresh.',
        tone: ColorClashNoticeTone.warning,
      );
      notifyListeners();
    }
  }

  void clearRealtimeError() {
    if (_lastRealtimeError == null) {
      return;
    }
    _lastRealtimeError = null;
    notifyListeners();
  }

  void trackUiEvent(
    String event, {
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    _telemetry.track(event, payload: payload);
  }

  void showStatusNotice(
    String message, {
    ColorClashNoticeTone tone = ColorClashNoticeTone.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (message.trim().isEmpty) {
      return;
    }
    _statusNoticeTimer?.cancel();
    _statusNotice = ColorClashStatusNotice(
      message: message.trim(),
      tone: tone,
      nonce: DateTime.now().microsecondsSinceEpoch.toString(),
    );
    notifyListeners();
    _statusNoticeTimer = Timer(duration, clearStatusNotice);
  }

  void clearStatusNotice() {
    _statusNoticeTimer?.cancel();
    _statusNoticeTimer = null;
    if (_statusNotice == null) {
      return;
    }
    _statusNotice = null;
    notifyListeners();
  }

  void selectCard(String? cardId) {
    if (_isSubmittingMove) {
      return;
    }

    if (cardId == null || cardId.isEmpty) {
      if (_selectedCardId != null) {
        _selectedCardId = null;
        notifyListeners();
      }
      return;
    }

    final exists =
        privateMatchState?.hand.any((entry) => entry.id == cardId) == true;
    if (!exists) {
      return;
    }

    _selectedCardId = _selectedCardId == cardId ? null : cardId;
    notifyListeners();
  }

  Future<ColorClashCommandAck?> drawCard() async {
    if (!canDraw) {
      return null;
    }
    return _submitMoveCommand(
      move: const <String, dynamic>{'type': 'draw_card'},
      commandKind: 'draw_card',
    );
  }

  Future<ColorClashCommandAck?> keepDrawnCard() async {
    if (!canKeepDrawn) {
      return null;
    }
    return _submitMoveCommand(
      move: const <String, dynamic>{'type': 'keep_drawn'},
      commandKind: 'keep_drawn',
    );
  }

  Future<ColorClashCommandAck?> playCard(
    String cardId, {
    String? chosenHue,
    int? targetSeat,
  }) async {
    if (_isSubmittingMove) {
      return null;
    }

    final matchingMove = _resolvePlayableMove(
      cardId,
      chosenHue: chosenHue,
      targetSeat: targetSeat,
    );
    if (matchingMove == null) {
      _lastRealtimeError = 'That card cannot be played right now.';
      notifyListeners();
      return null;
    }

    final payload = <String, dynamic>{
      'type': 'play_card',
      'cardId': cardId,
      if ((matchingMove.chosenHue ?? '').isNotEmpty)
        'chosenHue': matchingMove.chosenHue,
      if (matchingMove.targetSeat != null)
        'targetSeat': matchingMove.targetSeat,
    };
    return _submitMoveCommand(
      move: payload,
      commandKind: 'play_card',
      selectedCardId: cardId,
    );
  }

  Future<ColorClashCommandAck?> chooseHue(
    String hue, {
    String? cardId,
    int? targetSeat,
  }) {
    final resolvedCardId = cardId ?? _selectedCardId;
    if ((resolvedCardId ?? '').isEmpty) {
      return Future<ColorClashCommandAck?>.value(null);
    }
    return playCard(
      resolvedCardId!,
      chosenHue: hue,
      targetSeat: targetSeat,
    );
  }

  Future<ColorClashCommandAck?> respondToChallenge(String decision) async {
    if (_isSubmittingMove || (!canChallenge && !canDeclineChallenge)) {
      return null;
    }
    return _submitChallengeCommand(
      decision: decision,
      commandKind: decision == 'decline' ? 'decline_challenge' : 'challenge',
    );
  }

  Future<ColorClashRematchResult?> enterRematchVote(bool vote) {
    return voteRematch(vote);
  }

  void consumePendingMatchTarget() {
    if (_pendingMatchTarget == null) return;
    _pendingMatchTarget = null;
    notifyListeners();
  }

  void clearSession() {
    if (_lobbySession != null) {
      _socketService.forgetRoom(_lobbySession!.room.roomId);
    }
    if (_matchSnapshot != null) {
      _socketService.forgetMatch(_matchSnapshot!.matchId);
    }
    _lobbySession = null;
    _matchSnapshot = null;
    _matchmakingState = const ColorClashMatchmakingState();
    _reconnectState = const ColorClashReconnectState();
    _pendingMatchTarget = null;
    _selectedCardId = null;
    _clearPendingCommand();
    _lastActionSummary = null;
    _settlementSummary = null;
    _settlementError = null;
    _lobbyError = null;
    _matchError = null;
    _lastRealtimeError = null;
    _settlementPollTimer?.cancel();
    _settlementPollTimer = null;
    clearStatusNotice();
    notifyListeners();
  }

  Future<ColorClashCommandAck?> sendMove({
    required String clientMoveId,
    required Map<String, dynamic> move,
  }) async {
    final matchId = _matchSnapshot?.matchId;
    final version = _matchSnapshot?.version;
    if (matchId == null || version == null) return null;

    try {
      final ack = await _socketService.sendMove(
        matchId: matchId,
        clientMoveId: clientMoveId,
        expectedVersion: version,
        move: move,
      );
      if (ack.snapshotRequired) {
        unawaited(loadMatchSnapshot(matchId, force: true));
      }
      _telemetry.track(
        ack.accepted ? 'move_submitted' : 'move_rejected',
        payload: <String, Object?>{
          'matchId': matchId,
          'type': move['type']?.toString() ?? 'unknown',
          'accepted': ack.accepted,
          'snapshotRequired': ack.snapshotRequired,
          'version': ack.version,
        },
      );
      return ack;
    } catch (error) {
      _lastRealtimeError = _cleanError(error);
      showStatusNotice(
        _lastRealtimeError ?? 'That move could not be sent.',
        tone: ColorClashNoticeTone.warning,
      );
      notifyListeners();
      return null;
    }
  }

  Future<ColorClashCommandAck?> sendChallenge({
    required String clientMoveId,
    required String decision,
  }) async {
    final matchId = _matchSnapshot?.matchId;
    final version = _matchSnapshot?.version;
    if (matchId == null || version == null) return null;

    try {
      final ack = await _socketService.sendChallenge(
        matchId: matchId,
        clientMoveId: clientMoveId,
        expectedVersion: version,
        decision: decision,
      );
      if (ack.snapshotRequired) {
        unawaited(loadMatchSnapshot(matchId, force: true));
      }
      _telemetry.track(
        ack.accepted ? 'challenge_submitted' : 'challenge_rejected',
        payload: <String, Object?>{
          'matchId': matchId,
          'decision': decision,
          'accepted': ack.accepted,
          'snapshotRequired': ack.snapshotRequired,
          'version': ack.version,
        },
      );
      return ack;
    } catch (error) {
      _lastRealtimeError = _cleanError(error);
      showStatusNotice(
        _lastRealtimeError ?? 'That challenge response could not be sent.',
        tone: ColorClashNoticeTone.warning,
      );
      notifyListeners();
      return null;
    }
  }

  Future<String?> equipTheme(String themePackId) async {
    try {
      final equippedThemeId = await _service.equipTheme(themePackId);
      _telemetry.track(
        'theme_equipped',
        payload: <String, Object?>{'themePackId': themePackId},
      );
      if (_home != null) {
        _home = ColorClashHomeModel(
          gameId: _home!.gameId,
          season: _home!.season,
          userProgress: _home!.userProgress,
          queuePresets: _home!.queuePresets,
          rooms: _home!.rooms,
          activeMatch: _home!.activeMatch,
          themes: ColorClashHomeThemeSummaryModel(
            equippedThemePackId: equippedThemeId,
            ownedThemePackIds: _home!.themes.ownedThemePackIds,
          ),
          tutorial: _home!.tutorial,
          leaderboardPreview: _home!.leaderboardPreview,
          rewardPreview: _home!.rewardPreview,
        );
      }
      notifyListeners();
      return equippedThemeId;
    } catch (error) {
      _homeError = _cleanError(error);
      notifyListeners();
      return null;
    }
  }

  Future<bool> completeTutorial({String version = 'v1'}) async {
    try {
      final completed = await _service.completeTutorial(version: version);
      _telemetry.track(
        'tutorial_completed',
        payload: <String, Object?>{
          'version': version,
          'completed': completed,
        },
      );
      if (completed && _home != null) {
        final versions = <String>{
          ..._home!.tutorial.completedVersions,
          version,
        }.toList(growable: false);
        _home = ColorClashHomeModel(
          gameId: _home!.gameId,
          season: _home!.season,
          userProgress: _home!.userProgress,
          queuePresets: _home!.queuePresets,
          rooms: _home!.rooms,
          activeMatch: _home!.activeMatch,
          themes: _home!.themes,
          tutorial: ColorClashHomeTutorialModel(completedVersions: versions),
          leaderboardPreview: _home!.leaderboardPreview,
          rewardPreview: _home!.rewardPreview,
        );
        notifyListeners();
      }
      return completed;
    } catch (error) {
      _homeError = _cleanError(error);
      notifyListeners();
      return false;
    }
  }

  Future<ColorClashLeaderboardPayloadModel?> loadLeaderboard({
    String period = 'alltime',
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      return await _service.getLeaderboard(
        period: period,
        limit: limit,
        offset: offset,
      );
    } catch (error) {
      _seasonError = _cleanError(error);
      notifyListeners();
      return null;
    }
  }

  Future<ColorClashCommandAck?> _submitMoveCommand({
    required Map<String, dynamic> move,
    required String commandKind,
    String? selectedCardId,
  }) async {
    final matchId = _matchSnapshot?.matchId;
    final version = _matchSnapshot?.version;
    if (matchId == null || version == null) {
      return null;
    }

    final clientMoveId = _createClientMoveId(commandKind);
    _beginPendingCommand(
      selectedCardId: selectedCardId,
    );

    try {
      final ack = await _socketService.sendMove(
        matchId: matchId,
        clientMoveId: clientMoveId,
        expectedVersion: version,
        move: move,
      );
      _handleCommandAck(ack, matchId: matchId);
      _telemetry.track(
        ack.accepted ? 'move_submitted' : 'move_rejected',
        payload: <String, Object?>{
          'matchId': matchId,
          'commandKind': commandKind,
          'accepted': ack.accepted,
          'snapshotRequired': ack.snapshotRequired,
          'version': ack.version,
        },
      );
      return ack;
    } catch (error) {
      _clearPendingCommand();
      _lastRealtimeError = _cleanError(error);
      showStatusNotice(
        _lastRealtimeError ?? 'Color Clash needs to re-sync that move.',
        tone: ColorClashNoticeTone.warning,
      );
      notifyListeners();
      return null;
    }
  }

  Future<ColorClashCommandAck?> _submitChallengeCommand({
    required String decision,
    required String commandKind,
  }) async {
    final matchId = _matchSnapshot?.matchId;
    final version = _matchSnapshot?.version;
    if (matchId == null || version == null) {
      return null;
    }

    final clientMoveId = _createClientMoveId(commandKind);
    _beginPendingCommand();

    try {
      final ack = await _socketService.sendChallenge(
        matchId: matchId,
        clientMoveId: clientMoveId,
        expectedVersion: version,
        decision: decision,
      );
      _handleCommandAck(ack, matchId: matchId);
      _telemetry.track(
        ack.accepted ? 'challenge_submitted' : 'challenge_rejected',
        payload: <String, Object?>{
          'matchId': matchId,
          'commandKind': commandKind,
          'decision': decision,
          'accepted': ack.accepted,
          'snapshotRequired': ack.snapshotRequired,
          'version': ack.version,
        },
      );
      return ack;
    } catch (error) {
      _clearPendingCommand();
      _lastRealtimeError = _cleanError(error);
      showStatusNotice(
        _lastRealtimeError ?? 'Color Clash needs to re-sync that response.',
        tone: ColorClashNoticeTone.warning,
      );
      notifyListeners();
      return null;
    }
  }

  void _beginPendingCommand({String? selectedCardId}) {
    _isSubmittingMove = true;
    _pendingCommandVersion = null;
    _lastRealtimeError = null;
    if (selectedCardId != null) {
      _selectedCardId = selectedCardId;
    }
    notifyListeners();
  }

  void _handleCommandAck(
    ColorClashCommandAck ack, {
    required String matchId,
  }) {
    if (!ack.accepted) {
      _clearPendingCommand();
      if (ack.snapshotRequired) {
        showStatusNotice(
          'Command failed. Refreshing the authoritative match snapshot.',
          tone: ColorClashNoticeTone.warning,
        );
        unawaited(_reloadMatchSnapshotIfNeeded(matchId));
      } else {
        notifyListeners();
      }
      return;
    }

    _pendingCommandVersion = ack.version;
    if (ack.snapshotRequired) {
      showStatusNotice(
        'Refreshing the live match state before the next move.',
        tone: ColorClashNoticeTone.info,
      );
      unawaited(_reloadMatchSnapshotIfNeeded(matchId));
    }
    if (ack.version != null && (_matchSnapshot?.version ?? 0) >= ack.version!) {
      _clearPendingCommand();
    } else {
      notifyListeners();
    }
  }

  void _clearPendingCommand() {
    _isSubmittingMove = false;
    _pendingCommandVersion = null;
  }

  void _syncPendingCommandState() {
    final pendingVersion = _pendingCommandVersion;
    final snapshotVersion = _matchSnapshot?.version ?? 0;
    if (pendingVersion != null && snapshotVersion >= pendingVersion) {
      _clearPendingCommand();
    }
    _syncSelectedCardWithHand();
  }

  void _syncSelectedCardWithHand() {
    final selectedId = _selectedCardId;
    if (selectedId == null) {
      return;
    }
    final exists =
        privateMatchState?.hand.any((entry) => entry.id == selectedId) == true;
    if (!exists) {
      _selectedCardId = null;
      return;
    }
    if (legalMovesForCard(selectedId).isEmpty && !matchFinished) {
      _selectedCardId = null;
    }
  }

  ColorClashLegalMoveModel? _resolvePlayableMove(
    String cardId, {
    String? chosenHue,
    int? targetSeat,
  }) {
    final moves = legalMovesForCard(cardId);
    if (moves.isEmpty) {
      return null;
    }

    for (final move in moves) {
      final matchesHue = chosenHue == null ||
          chosenHue.isEmpty ||
          (move.chosenHue ?? '') == chosenHue;
      final matchesTarget = targetSeat == null || move.targetSeat == targetSeat;
      if (matchesHue && matchesTarget) {
        return move;
      }
    }

    if ((chosenHue == null || chosenHue.isEmpty) &&
        targetSeat == null &&
        moves.length == 1) {
      return moves.first;
    }

    return null;
  }

  String _createClientMoveId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  String? _summarizeRulesEvents(List<Map<String, dynamic>> events) {
    if (events.isEmpty) {
      return null;
    }
    final last = events.last;
    final type = last['type']?.toString() ?? '';
    switch (type) {
      case 'card_played':
        return 'A card hit the clash line.';
      case 'cards_drawn':
        return 'The draw pile answered back.';
      case 'challenge_window_opened':
        return 'A challenge window is open.';
      case 'challenge_declined':
        return 'The challenge window was declined.';
      case 'challenge_resolved':
        return 'The Prism Surge check resolved.';
      case 'freeze_applied':
        return 'Freeze just redirected the turn.';
      case 'direction_changed':
        return 'Flip Flow reversed the orbit.';
      case 'pulse_stack_pending':
        final amount = last['amount'];
        return 'Pulse stack is now ${amount ?? 0}.';
      case 'shield_granted':
        return 'A shield is up.';
      case 'shield_consumed':
        return 'A shield absorbed the hit.';
      case 'hands_swapped':
        return 'Two seats swapped hands.';
      case 'round_finished':
        return 'The round has wrapped.';
      case 'timeout_draw_pass':
        return 'Timeout forced a draw and pass.';
      case 'forfeit':
        return 'A player forfeited the round.';
      default:
        return type.isEmpty ? null : type.replaceAll('_', ' ');
    }
  }

  void _bindSocketStreams() {
    _subscriptions.addAll(<StreamSubscription<dynamic>>[
      _socketService.roomLobbyStream.listen(_handleLobbyUpdate),
      _socketService.countdownStartedStream.listen(_handleCountdownStarted),
      _socketService.countdownCancelledStream.listen(
        _handleCountdownCancelled,
      ),
      _socketService.matchStartedStream.listen(_handleMatchStarted),
      _socketService.matchPatchStream.listen(_handleMatchPatch),
      _socketService.lastCardAlertStream.listen(_handleLastCardAlert),
      _socketService.roundResultStream.listen(_handleRoundResult),
      _socketService.matchFinishedStream.listen(_handleMatchFinished),
      _socketService.handStateStream.listen(_handlePrivateStateEvent),
      _socketService.drawResultStream.listen(_handlePrivateStateEvent),
      _socketService.challengePromptStream.listen(_handlePrivateStateEvent),
      _socketService.commandErrorStream.listen(_handleCommandError),
      _socketService.queueMatchedStream.listen(_handleQueueMatched),
      _socketService.resyncStream.listen((_) {
        unawaited(resubscribeAfterReconnect());
      }),
    ]);
  }

  void _handleLobbyUpdate(ColorClashLobbyModel lobby) {
    if (_lobbySession == null || _lobbySession!.room.roomId != lobby.roomId) {
      return;
    }
    if (lobby.lobbyVersion < _lobbySession!.lobby.lobbyVersion) {
      return;
    }
    _lobbySession = ColorClashLobbySessionModel(
      room: _lobbySession!.room,
      lobby: lobby,
      viewerRole: _lobbySession!.viewerRole,
    );
    _socketService.updateTrackedLobbyVersion(lobby.roomId, lobby.lobbyVersion);
    notifyListeners();
    if ((lobby.activeMatchId ?? '').isNotEmpty) {
      _pendingMatchTarget = ColorClashPendingMatchTarget(
        roomId: lobby.roomId,
        matchId: lobby.activeMatchId!,
        source: 'lobby_update',
      );
      notifyListeners();
    }
  }

  void _handleCountdownStarted(ColorClashCountdownEvent event) {
    if (_lobbySession == null || _lobbySession!.room.roomId != event.roomId) {
      return;
    }
    if (event.lobbyVersion < _lobbySession!.lobby.lobbyVersion) {
      return;
    }
    final lobby = _lobbySession!.lobby;
    _lobbySession = ColorClashLobbySessionModel(
      room: _lobbySession!.room,
      lobby: ColorClashLobbyModel(
        roomId: lobby.roomId,
        gameId: lobby.gameId,
        lobbyVersion: event.lobbyVersion,
        status: 'countdown',
        activeMatchId: lobby.activeMatchId,
        minPlayersToStart: lobby.minPlayersToStart,
        maxPlayers: lobby.maxPlayers,
        countdownSec: lobby.countdownSec,
        allowSpectators: lobby.allowSpectators,
        seats: lobby.seats,
        playersByUserId: lobby.playersByUserId,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        countdownEndsAt: event.countdownEndsAt,
        rematchWindowEndsAt: lobby.rematchWindowEndsAt,
        rematchVotesByUserId: lobby.rematchVotesByUserId,
      ),
      viewerRole: _lobbySession!.viewerRole,
    );
    showStatusNotice(
      'Countdown started. Seats are locking in.',
      tone: ColorClashNoticeTone.info,
    );
    notifyListeners();
  }

  void _handleCountdownCancelled(ColorClashCountdownCancelledEvent event) {
    if (_lobbySession == null || _lobbySession!.room.roomId != event.roomId) {
      return;
    }
    if (event.lobbyVersion < _lobbySession!.lobby.lobbyVersion) {
      return;
    }
    final lobby = _lobbySession!.lobby;
    _lobbySession = ColorClashLobbySessionModel(
      room: _lobbySession!.room,
      lobby: ColorClashLobbyModel(
        roomId: lobby.roomId,
        gameId: lobby.gameId,
        lobbyVersion: event.lobbyVersion,
        status: 'open',
        activeMatchId: lobby.activeMatchId,
        minPlayersToStart: lobby.minPlayersToStart,
        maxPlayers: lobby.maxPlayers,
        countdownSec: lobby.countdownSec,
        allowSpectators: lobby.allowSpectators,
        seats: lobby.seats,
        playersByUserId: lobby.playersByUserId,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        countdownEndsAt: null,
        rematchWindowEndsAt: lobby.rematchWindowEndsAt,
        rematchVotesByUserId: lobby.rematchVotesByUserId,
      ),
      viewerRole: _lobbySession!.viewerRole,
    );
    _lastRealtimeError = event.reason.isEmpty ? null : event.reason;
    showStatusNotice(
      event.reason.isEmpty
          ? 'Countdown paused until enough ready players return.'
          : event.reason,
      tone: ColorClashNoticeTone.warning,
    );
    notifyListeners();
  }

  void _handleMatchStarted(ColorClashMatchStartedEvent event) {
    _matchmakingState = _matchmakingState.copyWith(
      stage: ColorClashQueueStage.matched,
      matchedRoomId: event.roomId,
      matchedMatchId: event.matchId,
      errorMessage: null,
    );
    _pendingMatchTarget = ColorClashPendingMatchTarget(
      roomId: event.roomId,
      matchId: event.matchId,
      source: 'match_started',
    );
    if (_lobbySession != null && _lobbySession!.room.roomId == event.roomId) {
      final lobby = _lobbySession!.lobby;
      _lobbySession = ColorClashLobbySessionModel(
        room: _lobbySession!.room,
        lobby: ColorClashLobbyModel(
          roomId: lobby.roomId,
          gameId: lobby.gameId,
          lobbyVersion: lobby.lobbyVersion,
          status: 'in_progress',
          activeMatchId: event.matchId,
          minPlayersToStart: lobby.minPlayersToStart,
          maxPlayers: lobby.maxPlayers,
          countdownSec: lobby.countdownSec,
          allowSpectators: lobby.allowSpectators,
          seats: lobby.seats,
          playersByUserId: lobby.playersByUserId,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          countdownEndsAt: null,
          rematchWindowEndsAt: lobby.rematchWindowEndsAt,
          rematchVotesByUserId: lobby.rematchVotesByUserId,
        ),
        viewerRole: _lobbySession!.viewerRole,
      );
    }
    showStatusNotice(
      'Color Clash is live. Entering the active table.',
      tone: ColorClashNoticeTone.success,
    );
    notifyListeners();
  }

  void _handleMatchPatch(ColorClashMatchPatchEvent event) {
    if (_matchSnapshot?.matchId != event.matchId) {
      return;
    }
    final currentVersion = _matchSnapshot?.version ?? 0;
    if (event.version <= currentVersion) {
      return;
    }
    if (currentVersion != 0 && event.version != currentVersion + 1) {
      showStatusNotice(
        'Live state skipped ahead. Refreshing the authoritative snapshot.',
        tone: ColorClashNoticeTone.warning,
      );
      unawaited(_reloadMatchSnapshotIfNeeded(event.matchId));
      return;
    }

    _matchSnapshot = _copyMatchSnapshot(
      _matchSnapshot!,
      version: event.version,
      publicState: event.publicState,
    );
    _lastActionSummary = _summarizeRulesEvents(event.events);
    _lastRealtimeError = null;
    _syncPendingCommandState();
    _socketService.updateTrackedMatchVersion(event.matchId, event.version);
    notifyListeners();
  }

  void _handleLastCardAlert(ColorClashLastCardAlertEvent event) {
    if (_matchSnapshot?.matchId != event.matchId) {
      return;
    }
    _lastActionSummary = 'Seat ${event.seatIndex + 1} is down to a final card.';
    showStatusNotice(
      'Seat ${event.seatIndex + 1} is down to a final card.',
      tone: ColorClashNoticeTone.warning,
    );
    notifyListeners();
  }

  void _handleRoundResult(ColorClashRoundResultEvent event) {
    if (_matchSnapshot?.matchId != event.matchId) {
      return;
    }
    if (event.version < _matchSnapshot!.version) {
      return;
    }
    final publicState = ColorClashPublicMatchStateModel(
      gameId: _matchSnapshot!.publicState.gameId,
      roundNumber: _matchSnapshot!.publicState.roundNumber,
      phase: 'round_end',
      currentTurnSeat: _matchSnapshot!.publicState.currentTurnSeat,
      direction: _matchSnapshot!.publicState.direction,
      currentHue: _matchSnapshot!.publicState.currentHue,
      drawPileCount: _matchSnapshot!.publicState.drawPileCount,
      discardCount: _matchSnapshot!.publicState.discardCount,
      players: _matchSnapshot!.publicState.players,
      discardTop: _matchSnapshot!.publicState.discardTop,
      turnContext: _matchSnapshot!.publicState.turnContext,
      pendingEffect: _matchSnapshot!.publicState.pendingEffect,
      roundResult: event.result,
    );
    _matchSnapshot = _copyMatchSnapshot(
      _matchSnapshot!,
      version: event.version,
      publicState: publicState,
    );
    _lastActionSummary = 'Round result is ready.';
    showStatusNotice(
      'Round wrapped. Results are ready.',
      tone: ColorClashNoticeTone.success,
    );
    _syncPendingCommandState();
    _socketService.updateTrackedMatchVersion(event.matchId, event.version);
    notifyListeners();
  }

  void _handleMatchFinished(ColorClashMatchFinishedEvent event) {
    if (_matchSnapshot?.matchId != event.matchId) {
      return;
    }
    if (event.version < _matchSnapshot!.version) {
      return;
    }
    final publicState = ColorClashPublicMatchStateModel(
      gameId: _matchSnapshot!.publicState.gameId,
      roundNumber: _matchSnapshot!.publicState.roundNumber,
      phase: 'completed',
      currentTurnSeat: _matchSnapshot!.publicState.currentTurnSeat,
      direction: _matchSnapshot!.publicState.direction,
      currentHue: _matchSnapshot!.publicState.currentHue,
      drawPileCount: _matchSnapshot!.publicState.drawPileCount,
      discardCount: _matchSnapshot!.publicState.discardCount,
      players: _matchSnapshot!.publicState.players,
      discardTop: _matchSnapshot!.publicState.discardTop,
      turnContext: _matchSnapshot!.publicState.turnContext,
      pendingEffect: _matchSnapshot!.publicState.pendingEffect,
      roundResult: event.result,
    );
    _matchSnapshot = _copyMatchSnapshot(
      _matchSnapshot!,
      version: event.version,
      publicState: publicState,
    );
    _selectedCardId = null;
    _lastActionSummary = 'Match finished.';
    _syncPendingCommandState();
    _reconnectState = _reconnectState.copyWith(
      status: ColorClashReconnectStatus.ready,
      message: 'Match finished',
      failedMatchId: null,
    );
    showStatusNotice(
      'Match finished. Settlement is syncing now.',
      tone: ColorClashNoticeTone.info,
    );
    _telemetry.track(
      'match_finished',
      payload: <String, Object?>{
        'matchId': event.matchId,
        'version': event.version,
      },
    );
    unawaited(loadSettlementSummary(event.matchId, pollIfPending: true));
    notifyListeners();
  }

  void _handlePrivateStateEvent(ColorClashPrivateStateEvent event) {
    if (_matchSnapshot?.matchId != event.matchId) {
      return;
    }
    final currentVersion = _matchSnapshot?.version ?? 0;
    if (event.version < currentVersion) {
      return;
    }
    if (currentVersion != 0 && event.version > currentVersion + 1) {
      showStatusNotice(
        'A private update arrived out of sequence. Reloading your hand.',
        tone: ColorClashNoticeTone.warning,
      );
      unawaited(_reloadMatchSnapshotIfNeeded(event.matchId));
      return;
    }

    _matchSnapshot = _copyMatchSnapshot(
      _matchSnapshot!,
      version: event.version,
      privateState: event.privateState,
    );
    _syncPendingCommandState();
    _socketService.updateTrackedMatchVersion(event.matchId, event.version);
    notifyListeners();
  }

  void _handleCommandError(ColorClashCommandErrorEvent event) {
    if ((_matchSnapshot?.matchId ?? '') != event.matchId) {
      return;
    }
    _clearPendingCommand();
    _lastRealtimeError = event.message;
    showStatusNotice(
      event.snapshotRequired
          ? 'Command failed. Refreshing the live snapshot.'
          : event.message,
      tone: ColorClashNoticeTone.warning,
    );
    _telemetry.track(
      'move_rejected',
      payload: <String, Object?>{
        'matchId': event.matchId,
        'clientMoveId': event.clientMoveId,
        'errorCode': event.errorCode,
        'snapshotRequired': event.snapshotRequired,
      },
    );
    notifyListeners();
    if (event.snapshotRequired) {
      unawaited(_reloadMatchSnapshotIfNeeded(event.matchId));
    }
  }

  void _handleQueueMatched(ColorClashQueueMatchedEvent event) {
    _matchmakingState = _matchmakingState.copyWith(
      stage: ColorClashQueueStage.matched,
      mode: event.mode,
      stakeAmount: event.stakeAmount,
      matchedRoomId: event.roomId,
      matchedMatchId: event.matchId,
      errorMessage: null,
    );
    _pendingMatchTarget = ColorClashPendingMatchTarget(
      roomId: event.roomId,
      matchId: event.matchId,
      source: 'queue_event',
    );
    showStatusNotice(
      'Match found. Syncing your Color Clash table now.',
      tone: ColorClashNoticeTone.success,
    );
    notifyListeners();
  }

  Future<ColorClashMatchSnapshotModel?> _applyReconnectPayload(
    String matchId,
    ColorClashReconnectPayloadModel reconnectPayload,
  ) async {
    if (reconnectPayload.snapshot != null) {
      _matchSnapshot = reconnectPayload.snapshot;
      _socketService.updateTrackedMatchVersion(
        matchId,
        reconnectPayload.snapshot!.version,
      );
      _syncPendingCommandState();
      notifyListeners();
      return _matchSnapshot;
    }

    final existing = _matchSnapshot;
    final canApplyReplay = reconnectPayload.isReplayMode &&
        existing != null &&
        existing.matchId == matchId &&
        existing.viewerRole == 'spectator';

    if (canApplyReplay) {
      for (final replayEvent in reconnectPayload.replay) {
        if (replayEvent.eventName == 'cc:match:state_patch') {
          final patch = ColorClashMatchPatchEvent.fromJson(replayEvent.payload);
          if (patch.version > (_matchSnapshot?.version ?? 0)) {
            _matchSnapshot = _copyMatchSnapshot(
              _matchSnapshot!,
              version: patch.version,
              publicState: patch.publicState,
            );
            _lastActionSummary = _summarizeRulesEvents(patch.events);
          }
        } else if (replayEvent.eventName == 'cc:match:round_result') {
          final round =
              ColorClashRoundResultEvent.fromJson(replayEvent.payload);
          if (_matchSnapshot != null &&
              round.version > _matchSnapshot!.version) {
            _handleRoundResult(round);
          }
        } else if (replayEvent.eventName == 'cc:match:finished') {
          final finished =
              ColorClashMatchFinishedEvent.fromJson(replayEvent.payload);
          if (_matchSnapshot != null &&
              finished.version > _matchSnapshot!.version) {
            _handleMatchFinished(finished);
          }
        }
      }
      _syncPendingCommandState();
      notifyListeners();
      return _matchSnapshot;
    }

    return loadMatchSnapshot(matchId, force: true);
  }

  Future<void> _reloadMatchSnapshotIfNeeded(String matchId) async {
    if (_matchReloadsInFlight.contains(matchId)) return;
    _matchReloadsInFlight.add(matchId);
    try {
      _telemetry.track(
        'snapshot_reload_triggered',
        payload: <String, Object?>{'matchId': matchId},
      );
      await loadMatchSnapshot(matchId, force: true);
    } finally {
      _matchReloadsInFlight.remove(matchId);
    }
  }

  Future<void> _applySettlementSummaryEffects(
    ColorClashSettlementSummaryModel summary,
  ) async {
    if (summary.isPending) {
      showStatusNotice(
        'Settlement is syncing in the background.',
        tone: ColorClashNoticeTone.info,
      );
      return;
    }

    if (summary.isFailed) {
      showStatusNotice(
        summary.error?.trim().isNotEmpty == true
            ? summary.error!
            : 'Settlement hit an issue, but the match state is preserved.',
        tone: ColorClashNoticeTone.warning,
        duration: const Duration(seconds: 6),
      );
      return;
    }

    if (summary.isRefunded) {
      showStatusNotice(
        'Entries were refunded for this Color Clash match.',
        tone: ColorClashNoticeTone.info,
      );
      await loadHome(force: true);
      return;
    }

    if (summary.isSettled) {
      if (summary.rankProgression?.isApplied == true) {
        showStatusNotice(
          'Settlement complete and season rating synced.',
          tone: ColorClashNoticeTone.success,
          duration: const Duration(seconds: 5),
        );
      } else {
        showStatusNotice(
          'Settlement complete.',
          tone: ColorClashNoticeTone.success,
        );
      }
      await Future.wait(<Future<void>>[
        loadHome(force: true),
        loadSeasonSummary(force: true),
      ]);
    }
  }

  void _scheduleSettlementPoll(String matchId) {
    _settlementPollTimer?.cancel();
    _settlementPollTimer = Timer(const Duration(seconds: 2), () {
      unawaited(loadSettlementSummary(matchId, pollIfPending: true));
    });
  }

  ColorClashMatchSnapshotModel _copyMatchSnapshot(
    ColorClashMatchSnapshotModel source, {
    int? version,
    ColorClashPublicMatchStateModel? publicState,
    ColorClashPrivateMatchStateModel? privateState,
    ColorClashMatchPresenceModel? presence,
    bool? replayAvailable,
  }) {
    return ColorClashMatchSnapshotModel(
      matchId: source.matchId,
      roomId: source.roomId,
      version: version ?? source.version,
      viewerRole: source.viewerRole,
      publicState: publicState ?? source.publicState,
      privateState: privateState ?? source.privateState,
      presence: presence ?? source.presence,
      replayAvailable: replayAvailable ?? source.replayAvailable,
    );
  }

  String _cleanError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    final normalized = text.toLowerCase();
    if (normalized.contains('err syntax error') ||
        normalized == 'syntax error') {
      return 'Color Clash hit a temporary sync issue. Please retry.';
    }
    if (normalized.contains('rangeerror') &&
        normalized.contains('max must be in range')) {
      return 'Color Clash hit a temporary queue issue. Please retry.';
    }
    return text.isEmpty ? 'Something went wrong in Color Clash.' : text;
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _settlementPollTimer?.cancel();
    _statusNoticeTimer?.cancel();
    _socketService.dispose();
    super.dispose();
  }
}

enum ColorClashQueueStage {
  idle,
  joining,
  queued,
  matched,
  leaving,
  error,
}

class ColorClashMatchmakingState {
  const ColorClashMatchmakingState({
    this.stage = ColorClashQueueStage.idle,
    this.mode,
    this.stakeAmount = 0,
    this.queueTicketId,
    this.estimatedWaitMs,
    this.matchedRoomId,
    this.matchedMatchId,
    this.errorMessage,
  });

  final ColorClashQueueStage stage;
  final String? mode;
  final int stakeAmount;
  final String? queueTicketId;
  final int? estimatedWaitMs;
  final String? matchedRoomId;
  final String? matchedMatchId;
  final String? errorMessage;

  ColorClashMatchmakingState copyWith({
    ColorClashQueueStage? stage,
    Object? mode = _sentinel,
    int? stakeAmount,
    Object? queueTicketId = _sentinel,
    Object? estimatedWaitMs = _sentinel,
    Object? matchedRoomId = _sentinel,
    Object? matchedMatchId = _sentinel,
    Object? errorMessage = _sentinel,
  }) {
    return ColorClashMatchmakingState(
      stage: stage ?? this.stage,
      mode: identical(mode, _sentinel) ? this.mode : mode as String?,
      stakeAmount: stakeAmount ?? this.stakeAmount,
      queueTicketId: identical(queueTicketId, _sentinel)
          ? this.queueTicketId
          : queueTicketId as String?,
      estimatedWaitMs: identical(estimatedWaitMs, _sentinel)
          ? this.estimatedWaitMs
          : estimatedWaitMs as int?,
      matchedRoomId: identical(matchedRoomId, _sentinel)
          ? this.matchedRoomId
          : matchedRoomId as String?,
      matchedMatchId: identical(matchedMatchId, _sentinel)
          ? this.matchedMatchId
          : matchedMatchId as String?,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  bool get isQueueing =>
      stage == ColorClashQueueStage.joining ||
      stage == ColorClashQueueStage.queued;
}

enum ColorClashReconnectStatus {
  idle,
  reconnecting,
  ready,
  failed,
}

class ColorClashReconnectState {
  const ColorClashReconnectState({
    this.status = ColorClashReconnectStatus.idle,
    this.message,
    this.failedMatchId,
  });

  final ColorClashReconnectStatus status;
  final String? message;
  final String? failedMatchId;

  ColorClashReconnectState copyWith({
    ColorClashReconnectStatus? status,
    Object? message = _sentinel,
    Object? failedMatchId = _sentinel,
  }) {
    return ColorClashReconnectState(
      status: status ?? this.status,
      message:
          identical(message, _sentinel) ? this.message : message as String?,
      failedMatchId: identical(failedMatchId, _sentinel)
          ? this.failedMatchId
          : failedMatchId as String?,
    );
  }
}

class ColorClashPendingMatchTarget {
  const ColorClashPendingMatchTarget({
    required this.roomId,
    required this.matchId,
    required this.source,
  });

  final String roomId;
  final String matchId;
  final String source;
}

enum ColorClashNoticeTone {
  info,
  success,
  warning,
  error,
}

class ColorClashStatusNotice {
  const ColorClashStatusNotice({
    required this.message,
    required this.tone,
    required this.nonce,
  });

  final String message;
  final ColorClashNoticeTone tone;
  final String nonce;
}

const Object _sentinel = Object();
