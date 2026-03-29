import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/color_clash_card_model.dart';
import 'package:frontend/models/color_clash_home_model.dart';
import 'package:frontend/models/color_clash_lobby_model.dart';
import 'package:frontend/models/color_clash_match_snapshot.dart';
import 'package:frontend/models/color_clash_season_model.dart';
import 'package:frontend/models/color_clash_settlement_model.dart';
import 'package:frontend/models/color_clash_table_model.dart';
import 'package:frontend/providers/color_clash_session_controller.dart';
import 'package:frontend/screens/games/color_clash_home_screen.dart';
import 'package:frontend/screens/games/color_clash_table_screen.dart';
import 'package:frontend/services/color_clash_service.dart';
import 'package:frontend/services/color_clash_socket_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

void main() {
  group('ColorClashSessionController', () {
    test('loadHome stores home payload and season summary', () async {
      final service = FakeColorClashService(home: buildHomeModel());
      final controller = ColorClashSessionController(
        service: service,
        socketService: FakeColorClashSocketService(),
      );

      await controller.loadHome(force: true);

      expect(controller.home?.gameId, 'color_clash');
      expect(controller.seasonSummary?.season?.name, 'March Clash');
      expect(controller.matchmakingState.queueTicketId, 'ticket-1');
      controller.dispose();
    });

    test('loadHome maps raw syntax errors to a safe retry message', () async {
      final service =
          FakeColorClashService(homeError: Exception('ERR syntax error'));
      final controller = ColorClashSessionController(
        service: service,
        socketService: FakeColorClashSocketService(),
      );

      await controller.loadHome(force: true);

      expect(
        controller.homeError,
        'Color Clash hit a temporary sync issue. Please retry.',
      );
      controller.dispose();
    });

    test('joinMatchmaking maps local range errors to a safe retry message',
        () async {
      final service = FakeColorClashService(
        joinMatchmakingError:
            RangeError.range(0, 1, 4294967296, 'max', 'max must be in range'),
      );
      final controller = ColorClashSessionController(
        service: service,
        socketService: FakeColorClashSocketService(),
      );

      await controller.joinMatchmaking(mode: 'casual_free');

      expect(
        controller.matchmakingState.errorMessage,
        'Color Clash hit a temporary queue issue. Please retry.',
      );
      controller.dispose();
    });

    test('version mismatch triggers snapshot reload path', () async {
      final socket = FakeColorClashSocketService();
      final service = FakeColorClashService(
        home: buildHomeModel(),
        matchSnapshots: <ColorClashMatchSnapshotModel>[
          buildMatchSnapshot(version: 1),
          buildMatchSnapshot(version: 4, currentTurnSeat: 1),
        ],
      );
      final controller = ColorClashSessionController(
        service: service,
        socketService: socket,
      );

      await controller.loadMatchSnapshot('match-1', force: true);
      socket.emitMatchPatch(
        ColorClashMatchPatchEvent(
          matchId: 'match-1',
          roomId: 'room-1',
          version: 3,
          publicState: buildPublicMatchState(currentTurnSeat: 1),
          events: const <Map<String, dynamic>>[],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.matchSnapshot?.version, 4);
      expect(service.matchSnapshotCalls, 2);
      controller.dispose();
    });

    test('reconnectMatch applies snapshot payload safely', () async {
      final service = FakeColorClashService(
        reconnectPayload: ColorClashReconnectPayloadModel(
          mode: 'snapshot',
          viewerRole: 'player',
          replay: const <ColorClashReplayEventModel>[],
          snapshot: buildMatchSnapshot(version: 5),
        ),
      );
      final controller = ColorClashSessionController(
        service: service,
        socketService: FakeColorClashSocketService(),
      );

      await controller.reconnectMatch('match-1');

      expect(controller.reconnectState.status, ColorClashReconnectStatus.ready);
      expect(controller.matchSnapshot?.version, 5);
      controller.dispose();
    });

    test(
        'playCard sends backend-authoritative move and clears pending on patch',
        () async {
      final socket = FakeColorClashSocketService();
      final controller = ColorClashSessionController(
        service: FakeColorClashService(
          matchSnapshots: <ColorClashMatchSnapshotModel>[buildMatchSnapshot()],
        ),
        socketService: socket,
      );

      await controller.loadMatchSnapshot('match-1', force: true);
      controller.selectCard('card-private');

      final ack = await controller.playCard('card-private');
      expect(ack?.accepted, isTrue);
      expect(controller.isSubmittingMove, isTrue);
      expect(socket.sentMoves.single['move']['type'], 'play_card');

      socket.emitMatchPatch(
        ColorClashMatchPatchEvent(
          matchId: 'match-1',
          roomId: 'room-1',
          version: 2,
          publicState: buildPublicMatchState(currentTurnSeat: 1),
          events: const <Map<String, dynamic>>[
            <String, dynamic>{'type': 'card_played'}
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.isSubmittingMove, isFalse);
      expect(controller.lastActionSummary, contains('clash'));
      controller.dispose();
    });

    test('challenge prompt state and finished transition stay synchronized',
        () async {
      final socket = FakeColorClashSocketService();
      final controller = ColorClashSessionController(
        service: FakeColorClashService(
          matchSnapshots: <ColorClashMatchSnapshotModel>[buildMatchSnapshot()],
        ),
        socketService: socket,
      );

      await controller.loadMatchSnapshot('match-1', force: true);
      socket.emitPrivateState(
        ColorClashPrivateStateEvent(
          matchId: 'match-1',
          roomId: 'room-1',
          version: 2,
          seatIndex: 0,
          privateState: const ColorClashPrivateMatchStateModel(
            seatIndex: 0,
            currentTurnSeat: 0,
            hand: <ColorClashCardModel>[
              ColorClashCardModel(
                id: 'card-private',
                kind: 'number',
                hue: 'tide',
                value: 8,
              ),
            ],
            legalMoves: <ColorClashLegalMoveModel>[
              ColorClashLegalMoveModel(type: 'challenge'),
              ColorClashLegalMoveModel(type: 'decline_challenge'),
            ],
            prompt: ColorClashPromptModel(
              kind: 'challenge_response',
              sourceSeat: 1,
              amount: 4,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.hasPendingPrompt, isTrue);
      expect(controller.canChallenge, isTrue);
      expect(controller.canDeclineChallenge, isTrue);

      socket.emitMatchFinished(
        ColorClashMatchFinishedEvent(
          matchId: 'match-1',
          roomId: 'room-1',
          version: 3,
          result: const ColorClashRoundResultModel(
            winnerSeat: 0,
            endReason: 'completed',
            placements: <ColorClashPlacementModel>[
              ColorClashPlacementModel(
                placement: 1,
                seatIndex: 0,
                userId: 'user-1',
                status: 'finished',
                handPoints: 0,
                handCount: 0,
                timeoutStrikes: 0,
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.matchFinished, isTrue);
      expect(controller.lastActionSummary, 'Match finished.');
      controller.dispose();
    });

    test('openMatch with reconnect keeps room shell and match snapshot aligned',
        () async {
      final controller = ColorClashSessionController(
        service: FakeColorClashService(
          lobbySession: buildLobbySession(),
          reconnectPayload: ColorClashReconnectPayloadModel(
            mode: 'snapshot',
            viewerRole: 'player',
            replay: const <ColorClashReplayEventModel>[],
            snapshot: buildMatchSnapshot(version: 6),
          ),
        ),
        socketService: FakeColorClashSocketService(),
      );

      final snapshot = await controller.openMatch(
        'match-1',
        roomId: 'room-1',
        forceReconnect: true,
      );

      expect(snapshot?.version, 6);
      expect(controller.lobbySession?.room.roomId, 'room-1');
      expect(controller.reconnectState.status, ColorClashReconnectStatus.ready);
      controller.dispose();
    });

    test('loadSettlementSummary surfaces pending then settled rank sync states',
        () async {
      final service = FakeColorClashService(
        settlementSummaries: <ColorClashSettlementSummaryModel>[
          buildSettlementSummary(status: 'locked'),
          buildSettlementSummary(
            status: 'settled',
            rankProgression: const ColorClashRankProgressionModel(
              status: 'applied',
              results: <ColorClashRankProgressResultModel>[
                ColorClashRankProgressResultModel(
                  userId: 'user-1',
                  placement: 1,
                  ratingBefore: 1000,
                  ratingAfter: 1032,
                  ratingDelta: 32,
                  tierId: 'spark',
                  division: 2,
                  stars: 4,
                ),
              ],
            ),
          ),
        ],
      );
      final controller = ColorClashSessionController(
        service: service,
        socketService: FakeColorClashSocketService(),
      );

      await controller.loadSettlementSummary('match-1', pollIfPending: true);

      expect(controller.settlementSummary?.isPending, isTrue);
      expect(
          controller.statusNotice?.message, contains('Settlement is syncing'));

      await Future<void>.delayed(const Duration(milliseconds: 2300));

      expect(controller.settlementSummary?.isSettled, isTrue);
      expect(
        controller.statusNotice?.message,
        contains('season rating synced'),
      );
      controller.dispose();
    });
  });

  testWidgets('Color Clash home screen renders primary sections',
      (WidgetTester tester) async {
    final controller = ColorClashSessionController(
      service: FakeColorClashService(
        home: buildHomeModel(),
        tables: buildTablesPayload(),
        seasonSummary: buildSeasonSummary(),
      ),
      socketService: FakeColorClashSocketService(),
    );
    await controller.loadHome(force: true);
    await controller.loadTables(force: true);
    await controller.loadSeasonSummary(force: true);

    await tester.pumpWidget(
      ChangeNotifierProvider<ColorClashSessionController>.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ColorClashHomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Color Clash'), findsWidgets);
    expect(find.text('Original social card nights'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Color Clash table screen renders loading then active state',
      (WidgetTester tester) async {
    final controller = ColorClashSessionController(
      service: FakeColorClashService(
        lobbySession: buildLobbySession(),
        matchSnapshots: <ColorClashMatchSnapshotModel>[buildMatchSnapshot()],
      ),
      socketService: FakeColorClashSocketService(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ColorClashSessionController>.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ColorClashTableScreen(
            matchId: 'match-1',
            roomId: 'room-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your hand'), findsOneWidget);
    expect(find.text('Draw'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('Color Clash table screen renders finished rematch state',
      (WidgetTester tester) async {
    final socket = FakeColorClashSocketService();
    final controller = ColorClashSessionController(
      service: FakeColorClashService(
        lobbySession: buildLobbySession(),
        matchSnapshots: <ColorClashMatchSnapshotModel>[
          buildMatchSnapshot(version: 4),
        ],
      ),
      socketService: socket,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ColorClashSessionController>.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ColorClashTableScreen(
            matchId: 'match-1',
            roomId: 'room-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    socket.emitMatchFinished(
      const ColorClashMatchFinishedEvent(
        matchId: 'match-1',
        roomId: 'room-1',
        version: 5,
        result: ColorClashRoundResultModel(
          winnerSeat: 0,
          endReason: 'completed',
          placements: <ColorClashPlacementModel>[
            ColorClashPlacementModel(
              placement: 1,
              seatIndex: 0,
              userId: 'user-1',
              status: 'finished',
              handPoints: 0,
              handCount: 0,
              timeoutStrikes: 0,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Match finished'), findsOneWidget);
    expect(find.text('Vote rematch'), findsOneWidget);
    expect(find.text('Return to room'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('Color Clash table screen renders social entry points safely',
      (WidgetTester tester) async {
    final controller = ColorClashSessionController(
      service: FakeColorClashService(
        lobbySession: buildLobbySession(),
        matchSnapshots: <ColorClashMatchSnapshotModel>[buildMatchSnapshot()],
      ),
      socketService: FakeColorClashSocketService(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ColorClashSessionController>.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ColorClashTableScreen(
            matchId: 'match-1',
            roomId: 'room-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('React'), findsOneWidget);
    expect(find.text('Gift'), findsOneWidget);
    expect(find.text('Room'), findsOneWidget);

    await tester.tap(find.text('Gift'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a player'), findsOneWidget);
    controller.dispose();
  });
}

class FakeColorClashService extends ColorClashService {
  FakeColorClashService({
    this.home,
    this.homeError,
    this.tables,
    this.seasonSummary,
    this.lobbySession,
    this.joinMatchmakingError,
    List<ColorClashMatchSnapshotModel>? matchSnapshots,
    this.reconnectPayload,
    List<ColorClashSettlementSummaryModel>? settlementSummaries,
  })  : _matchSnapshots = matchSnapshots ?? <ColorClashMatchSnapshotModel>[],
        _settlementSummaries =
            settlementSummaries ?? <ColorClashSettlementSummaryModel>[];

  final ColorClashHomeModel? home;
  final Object? homeError;
  final ColorClashTablesPayload? tables;
  final ColorClashSeasonSummaryModel? seasonSummary;
  final ColorClashLobbySessionModel? lobbySession;
  final Object? joinMatchmakingError;
  final List<ColorClashMatchSnapshotModel> _matchSnapshots;
  final List<ColorClashSettlementSummaryModel> _settlementSummaries;
  final ColorClashReconnectPayloadModel? reconnectPayload;

  int matchSnapshotCalls = 0;

  @override
  Future<ColorClashHomeModel> getHome() async {
    if (homeError != null) {
      throw homeError!;
    }
    return home ?? buildHomeModel();
  }

  @override
  Future<ColorClashTablesPayload> getTables(
      {String? mode, int limit = 20}) async {
    return tables ?? buildTablesPayload();
  }

  @override
  Future<ColorClashMatchmakingJoinResult> joinMatchmaking({
    required String mode,
    int? stakeAmount,
    String? region,
    String? themePackId,
  }) async {
    if (joinMatchmakingError != null) {
      throw joinMatchmakingError!;
    }
    return const ColorClashMatchmakingJoinResult(
      status: 'queued',
      duplicate: false,
      queueTicketId: 'ticket-queued',
      estimatedWaitMs: 3000,
    );
  }

  @override
  Future<ColorClashSeasonSummaryModel> getCurrentSeason() async {
    return seasonSummary ?? buildSeasonSummary();
  }

  @override
  Future<ColorClashMatchSnapshotModel> getMatchSnapshot(String matchId) async {
    matchSnapshotCalls += 1;
    if (_matchSnapshots.isEmpty) {
      return buildMatchSnapshot();
    }
    if (_matchSnapshots.length == 1) {
      return _matchSnapshots.first;
    }
    return _matchSnapshots.removeAt(0);
  }

  @override
  Future<ColorClashLobbySessionModel> getLobby(String roomId) async {
    return lobbySession ?? buildLobbySession();
  }

  @override
  Future<ColorClashReconnectPayloadModel> reconnectMatch(
    String matchId, {
    int lastKnownVersion = 0,
  }) async {
    return reconnectPayload ??
        ColorClashReconnectPayloadModel(
          mode: 'snapshot',
          viewerRole: 'player',
          replay: const <ColorClashReplayEventModel>[],
          snapshot: buildMatchSnapshot(version: lastKnownVersion + 1),
        );
  }

  @override
  Future<ColorClashLeaderboardPayloadModel> getLeaderboard({
    String period = 'alltime',
    int limit = 50,
    int offset = 0,
  }) async {
    return ColorClashLeaderboardPayloadModel(
      gameId: 'color_clash',
      period: period,
      season: buildSeasonSummary().season,
      rankings: const <ColorClashLeaderboardEntryModel>[],
      limit: limit,
      offset: offset,
      userRank: const ColorClashLeaderboardUserRankModel(rank: 4, score: 1024),
    );
  }

  @override
  Future<ColorClashSettlementSummaryModel> getSettlementSummary(
    String matchId,
  ) async {
    if (_settlementSummaries.isEmpty) {
      return buildSettlementSummary();
    }
    if (_settlementSummaries.length == 1) {
      return _settlementSummaries.first;
    }
    return _settlementSummaries.removeAt(0);
  }
}

class FakeColorClashSocketService extends ColorClashSocketService {
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
  final List<Map<String, dynamic>> sentMoves = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> sentChallenges = <Map<String, dynamic>>[];
  int heartbeatCount = 0;

  @override
  Stream<ColorClashLobbyModel> get roomLobbyStream =>
      _roomLobbyController.stream;
  @override
  Stream<ColorClashCountdownEvent> get countdownStartedStream =>
      _countdownStartedController.stream;
  @override
  Stream<ColorClashCountdownCancelledEvent> get countdownCancelledStream =>
      _countdownCancelledController.stream;
  @override
  Stream<ColorClashMatchStartedEvent> get matchStartedStream =>
      _matchStartedController.stream;
  @override
  Stream<ColorClashMatchPatchEvent> get matchPatchStream =>
      _matchPatchController.stream;
  @override
  Stream<ColorClashLastCardAlertEvent> get lastCardAlertStream =>
      _lastCardAlertController.stream;
  @override
  Stream<ColorClashRoundResultEvent> get roundResultStream =>
      _roundResultController.stream;
  @override
  Stream<ColorClashMatchFinishedEvent> get matchFinishedStream =>
      _matchFinishedController.stream;
  @override
  Stream<ColorClashPrivateStateEvent> get handStateStream =>
      _handStateController.stream;
  @override
  Stream<ColorClashPrivateStateEvent> get drawResultStream =>
      _drawResultController.stream;
  @override
  Stream<ColorClashPrivateStateEvent> get challengePromptStream =>
      _challengePromptController.stream;
  @override
  Stream<ColorClashCommandErrorEvent> get commandErrorStream =>
      _commandErrorController.stream;
  @override
  Stream<ColorClashQueueMatchedEvent> get queueMatchedStream =>
      _queueMatchedController.stream;
  @override
  Stream<Map<String, dynamic>> get resyncStream => _resyncController.stream;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<ColorClashRoomSubscribeAck> subscribeRoom(
    String roomId, {
    int? lastLobbyVersion,
  }) async {
    return ColorClashRoomSubscribeAck(
      roomId: roomId,
      viewerRole: 'player',
      lobby: buildLobby(),
    );
  }

  @override
  Future<ColorClashReconnectPayloadModel> subscribeMatch(
    String matchId, {
    int? lastVersion,
  }) async {
    return ColorClashReconnectPayloadModel(
      mode: 'snapshot',
      viewerRole: 'player',
      replay: const <ColorClashReplayEventModel>[],
      snapshot: buildMatchSnapshot(version: lastVersion ?? 1),
    );
  }

  @override
  Future<ColorClashCommandAck> sendMove({
    required String matchId,
    required String clientMoveId,
    required int expectedVersion,
    required Map<String, dynamic> move,
  }) async {
    sentMoves.add(<String, dynamic>{
      'matchId': matchId,
      'clientMoveId': clientMoveId,
      'expectedVersion': expectedVersion,
      'move': move,
    });
    return ColorClashCommandAck(
      ok: true,
      accepted: true,
      duplicate: false,
      matchId: matchId,
      version: expectedVersion + 1,
      snapshotRequired: false,
    );
  }

  @override
  Future<ColorClashCommandAck> sendChallenge({
    required String matchId,
    required String clientMoveId,
    required int expectedVersion,
    required String decision,
  }) async {
    sentChallenges.add(<String, dynamic>{
      'matchId': matchId,
      'clientMoveId': clientMoveId,
      'expectedVersion': expectedVersion,
      'decision': decision,
    });
    return ColorClashCommandAck(
      ok: true,
      accepted: true,
      duplicate: false,
      matchId: matchId,
      version: expectedVersion + 1,
      snapshotRequired: false,
    );
  }

  @override
  Future<void> sendHeartbeat({
    String? roomId,
    String? matchId,
    String viewerRole = 'player',
  }) async {
    heartbeatCount += 1;
  }

  void emitMatchPatch(ColorClashMatchPatchEvent event) {
    _matchPatchController.add(event);
  }

  void emitPrivateState(ColorClashPrivateStateEvent event) {
    _challengePromptController.add(event);
  }

  void emitMatchFinished(ColorClashMatchFinishedEvent event) {
    _matchFinishedController.add(event);
  }

  @override
  Future<void> dispose() async {
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
}

ColorClashHomeModel buildHomeModel() {
  return ColorClashHomeModel(
    gameId: 'color_clash',
    season: buildSeasonSummary().season,
    userProgress: ColorClashHomeUserProgressModel(
      stats: const <String, dynamic>{'rankedPlayed': 4},
      activeQueueTicketId: 'ticket-1',
      currentSeason: buildSeasonProgress(),
      currentUserRank: const ColorClashLeaderboardUserRankModel(
        rank: 4,
        score: 1024,
      ),
      eligibility: const ColorClashEligibilityModel(
        rankedEligible: true,
        stakeEligible: true,
        rankedLockReason: '',
        stakeLockReason: '',
        riskState: <String, dynamic>{},
      ),
    ),
    queuePresets: const <ColorClashQueuePresetModel>[
      ColorClashQueuePresetModel(
        queueId: 'casual-global',
        mode: 'casual_free',
        stakeAmount: 0,
        region: 'Global',
        playerCount: 2,
        enabled: true,
        themePackId: 'forest_picnic',
      ),
      ColorClashQueuePresetModel(
        queueId: 'ranked-global',
        mode: 'ranked',
        stakeAmount: 0,
        region: 'Global',
        playerCount: 2,
        enabled: true,
        themePackId: 'neon_orbit',
      ),
    ],
    rooms: <ColorClashRoomSummaryModel>[
      buildRoomSummary(),
    ],
    activeMatch: const ColorClashHomeActiveMatchModel(
      matchId: 'match-1',
      roomId: 'room-1',
      status: 'active',
      tableMode: 'ranked',
      version: 2,
      players: <ColorClashHomeActivePlayerModel>[
        ColorClashHomeActivePlayerModel(
          userId: 'user-1',
          seatIndex: 0,
          username: 'Asha',
          avatar: '',
          status: 'active',
        ),
      ],
      publicState: ColorClashPublicMatchStateModel(
        gameId: 'color_clash',
        roundNumber: 1,
        phase: 'active',
        currentTurnSeat: 0,
        direction: 1,
        currentHue: 'ember',
        drawPileCount: 85,
        discardCount: 1,
        discardTop: ColorClashCardModel(
          id: 'card-top',
          kind: 'number',
          hue: 'ember',
          value: 4,
        ),
        players: <ColorClashPublicPlayerStateModel>[
          ColorClashPublicPlayerStateModel(
            seatIndex: 0,
            userId: 'user-1',
            status: 'active',
            handCount: 7,
            timeoutStrikes: 0,
            hasShield: false,
            pendingLastCardCall: false,
            declaredLastCard: false,
          ),
        ],
      ),
    ),
    themes: const ColorClashHomeThemeSummaryModel(
      equippedThemePackId: 'forest_picnic',
      ownedThemePackIds: <String>['forest_picnic', 'neon_orbit'],
    ),
    tutorial: const ColorClashHomeTutorialModel(
      completedVersions: <String>[],
    ),
    leaderboardPreview: const <ColorClashLeaderboardEntryModel>[],
    rewardPreview: const <Map<String, dynamic>>[],
  );
}

ColorClashTablesPayload buildTablesPayload() {
  return ColorClashTablesPayload(
    gameId: 'color_clash',
    queuePresets: buildHomeModel().queuePresets,
    rooms: <ColorClashRoomSummaryModel>[buildRoomSummary()],
  );
}

ColorClashSeasonSummaryModel buildSeasonSummary() {
  return ColorClashSeasonSummaryModel(
    season: ColorClashSeasonModel(
      id: 'season-1',
      key: '2026-03',
      name: 'March Clash',
      status: 'active',
      startsAt: DateTime.utc(2026, 3, 1),
      endsAt: DateTime.utc(2026, 3, 31),
      finalizeAt: DateTime.utc(2026, 4, 1),
      placementMatches: 5,
      rankedEnabled: true,
      tiers: const <ColorClashTierModel>[
        ColorClashTierModel(
          id: 'spark',
          name: 'Spark',
          order: 1,
          minRating: 0,
          maxRating: 1099,
          divisions: 3,
          starsPerDivision: 4,
        ),
      ],
      ratingConfig: const ColorClashRatingConfigModel(
        baseRating: 1000,
        kFactor: 32,
        streakBonus: 4,
        placementMultiplier: 1.5,
        inactivityDecay: 0,
      ),
      rewardPreview: const <Map<String, dynamic>>[],
      themeRotation: const <String>['forest_picnic'],
    ),
    leaderboardPreview: const <ColorClashLeaderboardEntryModel>[
      ColorClashLeaderboardEntryModel(
        rank: 1,
        userId: 'user-top',
        username: 'Nova',
        avatar: '',
        level: 7,
        vipLevel: 2,
        rating: 1120,
        tierId: 'spark',
        division: 1,
        stars: 4,
      ),
    ],
    rewardPreview: const <Map<String, dynamic>>[],
    userProgress: buildSeasonProgress(),
    userRank: const ColorClashLeaderboardUserRankModel(rank: 4, score: 1024),
    eligibility: const ColorClashEligibilityModel(
      rankedEligible: true,
      stakeEligible: true,
      rankedLockReason: '',
      stakeLockReason: '',
      riskState: <String, dynamic>{},
    ),
  );
}

ColorClashSeasonProgressModel buildSeasonProgress() {
  return const ColorClashSeasonProgressModel(
    seasonId: 'season-1',
    userId: 'user-1',
    rating: 1024,
    peakRating: 1024,
    tierId: 'spark',
    tierName: 'Spark',
    division: 2,
    stars: 3,
    placementMatchesRemaining: 1,
    wins: 3,
    losses: 1,
    currentStreak: 2,
    bestStreak: 2,
    timeoutLosses: 0,
    forfeitLosses: 0,
    opponentDiversityScore: 85,
    smurfWatch: false,
    leaderboardScore: 1024,
    rewardStatus: 'pending',
  );
}

ColorClashRoomSummaryModel buildRoomSummary() {
  return ColorClashRoomSummaryModel(
    roomId: 'room-1',
    displayId: 'R-101',
    name: 'Friday Circle',
    description: 'Warm-up room',
    host: const ColorClashHostModel(
      userId: 'host-1',
      username: 'Host',
      avatar: '',
    ),
    visibility: 'invite_only',
    tableMode: 'friend_room',
    allowSpectators: true,
    themePackId: 'forest_picnic',
    maxPlayers: 4,
    participantCount: 2,
    lobbyStatus: 'open',
    stake: const ColorClashStakeModel(
      currency: 'none',
      entryFee: 0,
      houseFeeBps: 0,
      sinkFeeBps: 0,
      payouts: <ColorClashPayoutRuleModel>[],
    ),
    createdAt: DateTime.utc(2026, 3, 29),
    updatedAt: DateTime.utc(2026, 3, 29),
  );
}

ColorClashLobbySessionModel buildLobbySession() {
  return ColorClashLobbySessionModel(
    room: buildRoomSummary(),
    lobby: buildLobby(),
    viewerRole: 'player',
  );
}

ColorClashLobbyModel buildLobby() {
  return const ColorClashLobbyModel(
    roomId: 'room-1',
    gameId: 'color_clash',
    lobbyVersion: 1,
    status: 'open',
    minPlayersToStart: 2,
    maxPlayers: 4,
    countdownSec: 6,
    allowSpectators: true,
    seats: <int, String>{0: 'user-1'},
    playersByUserId: <String, ColorClashLobbyPlayerModel>{
      'user-1': ColorClashLobbyPlayerModel(
        userId: 'user-1',
        username: 'Asha',
        avatar: '',
        seatIndex: 0,
        ready: true,
        role: 'player',
        joinedAtMs: 1,
        lastSeenAtMs: 2,
      ),
    },
    updatedAtMs: 10,
  );
}

ColorClashMatchSnapshotModel buildMatchSnapshot({
  int version = 1,
  int currentTurnSeat = 0,
  String phase = 'active',
  ColorClashRoundResultModel? result,
}) {
  return ColorClashMatchSnapshotModel(
    matchId: 'match-1',
    roomId: 'room-1',
    version: version,
    viewerRole: 'player',
    publicState: buildPublicMatchState(
      currentTurnSeat: currentTurnSeat,
      phase: phase,
      result: result,
    ),
    privateState: const ColorClashPrivateMatchStateModel(
      seatIndex: 0,
      currentTurnSeat: 0,
      hand: <ColorClashCardModel>[
        ColorClashCardModel(
          id: 'card-private',
          kind: 'number',
          hue: 'tidal',
          value: 8,
        ),
      ],
      legalMoves: <ColorClashLegalMoveModel>[
        ColorClashLegalMoveModel(type: 'play_card', cardId: 'card-private'),
      ],
    ),
    presence: const ColorClashMatchPresenceModel(players: 2, spectators: 1),
    replayAvailable: true,
  );
}

ColorClashSettlementSummaryModel buildSettlementSummary({
  String status = 'settled',
  ColorClashRankProgressionModel? rankProgression,
}) {
  return ColorClashSettlementSummaryModel(
    matchId: 'match-1',
    paidTable: false,
    status: status,
    currency: 'none',
    entryFee: 0,
    totalEscrowed: 0,
    grossPool: 0,
    houseFee: 0,
    sinkAmount: 0,
    totalPaidOut: 0,
    refundedAmount: 0,
    escrowCount: 0,
    payouts: const <ColorClashSettlementPayoutModel>[],
    rankProgression: rankProgression,
  );
}

ColorClashPublicMatchStateModel buildPublicMatchState({
  int currentTurnSeat = 0,
  String phase = 'active',
  ColorClashRoundResultModel? result,
}) {
  return ColorClashPublicMatchStateModel(
    gameId: 'color_clash',
    roundNumber: 1,
    phase: phase,
    currentTurnSeat: currentTurnSeat,
    direction: 1,
    currentHue: 'ember',
    discardTop: const ColorClashCardModel(
      id: 'card-top',
      kind: 'number',
      hue: 'ember',
      value: 4,
    ),
    drawPileCount: 84,
    discardCount: 2,
    players: const <ColorClashPublicPlayerStateModel>[
      ColorClashPublicPlayerStateModel(
        seatIndex: 0,
        userId: 'user-1',
        status: 'active',
        handCount: 6,
        timeoutStrikes: 0,
        hasShield: false,
        pendingLastCardCall: false,
        declaredLastCard: false,
      ),
      ColorClashPublicPlayerStateModel(
        seatIndex: 1,
        userId: 'user-2',
        status: 'active',
        handCount: 7,
        timeoutStrikes: 0,
        hasShield: false,
        pendingLastCardCall: false,
        declaredLastCard: false,
      ),
    ],
    roundResult: result,
  );
}
