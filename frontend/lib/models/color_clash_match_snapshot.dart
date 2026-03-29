import 'color_clash_card_model.dart';
import 'color_clash_model_utils.dart';

class ColorClashMatchSnapshotModel {
  const ColorClashMatchSnapshotModel({
    required this.matchId,
    required this.roomId,
    required this.version,
    required this.viewerRole,
    required this.publicState,
    this.privateState,
    this.presence,
    this.replayAvailable = false,
  });

  final String matchId;
  final String roomId;
  final int version;
  final String viewerRole;
  final ColorClashPublicMatchStateModel publicState;
  final ColorClashPrivateMatchStateModel? privateState;
  final ColorClashMatchPresenceModel? presence;
  final bool replayAvailable;

  factory ColorClashMatchSnapshotModel.fromJson(Map<String, dynamic> json) {
    return ColorClashMatchSnapshotModel(
      matchId: asId(json['matchId']),
      roomId: asId(json['roomId']),
      version: asInt(json['version'], fallback: 1),
      viewerRole: json['viewerRole']?.toString() ?? 'spectator',
      publicState:
          ColorClashPublicMatchStateModel.fromJson(asMap(json['publicState'])),
      privateState: json['privateState'] == null
          ? null
          : ColorClashPrivateMatchStateModel.fromJson(
              asMap(json['privateState']),
            ),
      presence: json['presence'] == null
          ? null
          : ColorClashMatchPresenceModel.fromJson(asMap(json['presence'])),
      replayAvailable: asBool(json['replayAvailable']),
    );
  }

  bool get isPlayerView => viewerRole == 'player';

  bool get isSpectatorView => viewerRole == 'spectator';

  bool get isCompleted => publicState.phase == 'completed';

  ColorClashPublicPlayerStateModel? playerBySeat(int seatIndex) {
    for (final player in publicState.players) {
      if (player.seatIndex == seatIndex) {
        return player;
      }
    }
    return null;
  }
}

class ColorClashPublicMatchStateModel {
  const ColorClashPublicMatchStateModel({
    required this.gameId,
    required this.roundNumber,
    required this.phase,
    required this.currentTurnSeat,
    required this.direction,
    required this.currentHue,
    required this.drawPileCount,
    required this.discardCount,
    required this.players,
    this.discardTop,
    this.turnContext,
    this.pendingEffect,
    this.roundResult,
  });

  final String gameId;
  final int roundNumber;
  final String phase;
  final int currentTurnSeat;
  final int direction;
  final String? currentHue;
  final ColorClashCardModel? discardTop;
  final int drawPileCount;
  final int discardCount;
  final ColorClashTurnContextModel? turnContext;
  final ColorClashPendingEffectModel? pendingEffect;
  final List<ColorClashPublicPlayerStateModel> players;
  final ColorClashRoundResultModel? roundResult;

  factory ColorClashPublicMatchStateModel.fromJson(Map<String, dynamic> json) {
    return ColorClashPublicMatchStateModel(
      gameId: json['gameId']?.toString() ?? 'color_clash',
      roundNumber: asInt(json['roundNumber'], fallback: 1),
      phase: json['phase']?.toString() ?? 'active',
      currentTurnSeat: asInt(json['currentTurnSeat']),
      direction: asInt(json['direction'], fallback: 1),
      currentHue: json['currentHue']?.toString(),
      discardTop: json['discardTop'] == null
          ? null
          : ColorClashCardModel.fromJson(asMap(json['discardTop'])),
      drawPileCount: asInt(json['drawPileCount']),
      discardCount: asInt(json['discardCount']),
      turnContext: json['turnContext'] == null
          ? null
          : ColorClashTurnContextModel.fromJson(asMap(json['turnContext'])),
      pendingEffect: json['pendingEffect'] == null
          ? null
          : ColorClashPendingEffectModel.fromJson(asMap(json['pendingEffect'])),
      players: asMapList(json['players'])
          .map(ColorClashPublicPlayerStateModel.fromJson)
          .toList(growable: false),
      roundResult: json['roundResult'] == null
          ? null
          : ColorClashRoundResultModel.fromJson(asMap(json['roundResult'])),
    );
  }

  bool get isRoundEnded => phase == 'round_end' || phase == 'completed';
}

class ColorClashTurnContextModel {
  const ColorClashTurnContextModel({
    required this.phase,
    this.turnEndsAt,
    this.graceEndsAt,
  });

  final String phase;
  final int? turnEndsAt;
  final int? graceEndsAt;

  factory ColorClashTurnContextModel.fromJson(Map<String, dynamic> json) {
    return ColorClashTurnContextModel(
      phase: json['phase']?.toString() ?? 'main',
      turnEndsAt: json['turnEndsAt'] == null ? null : asInt(json['turnEndsAt']),
      graceEndsAt:
          json['graceEndsAt'] == null ? null : asInt(json['graceEndsAt']),
    );
  }

  bool get isAfterDraw => phase == 'after_draw';
}

class ColorClashPendingEffectModel {
  const ColorClashPendingEffectModel({
    required this.kind,
    this.targetSeat,
    this.sourceSeat,
    this.amount,
    this.chosenHue,
  });

  final String kind;
  final int? targetSeat;
  final int? sourceSeat;
  final int? amount;
  final String? chosenHue;

  factory ColorClashPendingEffectModel.fromJson(Map<String, dynamic> json) {
    return ColorClashPendingEffectModel(
      kind: json['kind']?.toString() ?? '',
      targetSeat: json['targetSeat'] == null ? null : asInt(json['targetSeat']),
      sourceSeat: json['sourceSeat'] == null ? null : asInt(json['sourceSeat']),
      amount: json['amount'] == null ? null : asInt(json['amount']),
      chosenHue: json['chosenHue']?.toString(),
    );
  }

  String get summaryLabel {
    switch (kind) {
      case 'freeze':
        return 'Freeze the next seat';
      case 'pulse_stack':
        return 'Pulse stack ${amount ?? 0}';
      case 'prism_surge_challenge':
        return 'Prism Surge challenge';
      default:
        return kind.replaceAll('_', ' ');
    }
  }
}

class ColorClashPublicPlayerStateModel {
  const ColorClashPublicPlayerStateModel({
    required this.seatIndex,
    required this.status,
    required this.handCount,
    required this.timeoutStrikes,
    required this.hasShield,
    required this.pendingLastCardCall,
    required this.declaredLastCard,
    this.userId,
    this.username,
    this.avatar,
  });

  final int seatIndex;
  final String? userId;
  final String? username;
  final String? avatar;
  final String status;
  final int handCount;
  final int timeoutStrikes;
  final bool hasShield;
  final bool pendingLastCardCall;
  final bool declaredLastCard;

  factory ColorClashPublicPlayerStateModel.fromJson(Map<String, dynamic> json) {
    return ColorClashPublicPlayerStateModel(
      seatIndex: asInt(json['seatIndex']),
      userId: asId(json['userId']).isEmpty ? null : asId(json['userId']),
      username: json['username']?.toString(),
      avatar: json['avatar']?.toString(),
      status: json['status']?.toString() ?? 'active',
      handCount: asInt(json['handCount']),
      timeoutStrikes: asInt(json['timeoutStrikes']),
      hasShield: asBool(json['hasShield']),
      pendingLastCardCall: asBool(json['pendingLastCardCall']),
      declaredLastCard: asBool(json['declaredLastCard']),
    );
  }
}

class ColorClashPrivateMatchStateModel {
  const ColorClashPrivateMatchStateModel({
    required this.seatIndex,
    required this.currentTurnSeat,
    required this.hand,
    required this.legalMoves,
    this.prompt,
  });

  final int seatIndex;
  final int currentTurnSeat;
  final List<ColorClashCardModel> hand;
  final List<ColorClashLegalMoveModel> legalMoves;
  final ColorClashPromptModel? prompt;

  factory ColorClashPrivateMatchStateModel.fromJson(Map<String, dynamic> json) {
    return ColorClashPrivateMatchStateModel(
      seatIndex: asInt(json['seatIndex']),
      currentTurnSeat: asInt(json['currentTurnSeat']),
      hand: asMapList(json['hand'])
          .map(ColorClashCardModel.fromJson)
          .toList(growable: false),
      legalMoves: asMapList(json['legalMoves'])
          .map(ColorClashLegalMoveModel.fromJson)
          .toList(growable: false),
      prompt: json['prompt'] == null
          ? null
          : ColorClashPromptModel.fromJson(asMap(json['prompt'])),
    );
  }

  bool get hasPrompt => prompt != null;

  List<ColorClashLegalMoveModel> legalMovesForCard(String cardId) => legalMoves
      .where((entry) => entry.matchesCard(cardId))
      .toList(growable: false);

  bool get canDraw => legalMoves.any((entry) => entry.type == 'draw_card');

  bool get canKeepDrawn =>
      legalMoves.any((entry) => entry.type == 'keep_drawn');

  bool get canChallenge => legalMoves.any((entry) => entry.type == 'challenge');

  bool get canDeclineChallenge =>
      legalMoves.any((entry) => entry.type == 'decline_challenge');
}

class ColorClashMatchPresenceModel {
  const ColorClashMatchPresenceModel({
    required this.players,
    required this.spectators,
  });

  final int players;
  final int spectators;

  factory ColorClashMatchPresenceModel.fromJson(Map<String, dynamic> json) {
    return ColorClashMatchPresenceModel(
      players: asInt(json['players']),
      spectators: asInt(json['spectators']),
    );
  }
}

class ColorClashRoundResultModel {
  const ColorClashRoundResultModel({
    required this.winnerSeat,
    required this.endReason,
    required this.placements,
  });

  final int? winnerSeat;
  final String endReason;
  final List<ColorClashPlacementModel> placements;

  factory ColorClashRoundResultModel.fromJson(Map<String, dynamic> json) {
    return ColorClashRoundResultModel(
      winnerSeat: json['winnerSeat'] == null ? null : asInt(json['winnerSeat']),
      endReason: json['endReason']?.toString() ?? 'completed',
      placements: asMapList(json['placements'])
          .map(ColorClashPlacementModel.fromJson)
          .toList(growable: false),
    );
  }
}

class ColorClashPlacementModel {
  const ColorClashPlacementModel({
    required this.placement,
    required this.seatIndex,
    required this.status,
    required this.handPoints,
    required this.handCount,
    required this.timeoutStrikes,
    this.userId,
  });

  final int placement;
  final int seatIndex;
  final String? userId;
  final String status;
  final int handPoints;
  final int handCount;
  final int timeoutStrikes;

  factory ColorClashPlacementModel.fromJson(Map<String, dynamic> json) {
    return ColorClashPlacementModel(
      placement: asInt(json['placement'], fallback: 1),
      seatIndex: asInt(json['seatIndex']),
      userId: asId(json['userId']).isEmpty ? null : asId(json['userId']),
      status: json['status']?.toString() ?? 'active',
      handPoints: asInt(json['handPoints']),
      handCount: asInt(json['handCount']),
      timeoutStrikes: asInt(json['timeoutStrikes']),
    );
  }
}

class ColorClashReplayEventModel {
  const ColorClashReplayEventModel({
    required this.version,
    required this.eventName,
    required this.payload,
  });

  final int version;
  final String eventName;
  final Map<String, dynamic> payload;

  factory ColorClashReplayEventModel.fromJson(Map<String, dynamic> json) {
    return ColorClashReplayEventModel(
      version: asInt(json['version']),
      eventName: json['eventName']?.toString() ?? '',
      payload: asMap(json['payload']),
    );
  }
}

class ColorClashReconnectPayloadModel {
  const ColorClashReconnectPayloadModel({
    required this.mode,
    required this.viewerRole,
    required this.replay,
    this.snapshot,
  });

  final String mode;
  final String viewerRole;
  final List<ColorClashReplayEventModel> replay;
  final ColorClashMatchSnapshotModel? snapshot;

  factory ColorClashReconnectPayloadModel.fromJson(Map<String, dynamic> json) {
    return ColorClashReconnectPayloadModel(
      mode: json['mode']?.toString() ?? 'snapshot',
      viewerRole: json['viewerRole']?.toString() ?? 'spectator',
      replay: asMapList(json['replay'])
          .map(ColorClashReplayEventModel.fromJson)
          .toList(growable: false),
      snapshot: json['snapshot'] == null
          ? null
          : ColorClashMatchSnapshotModel.fromJson(asMap(json['snapshot'])),
    );
  }

  bool get isReplayMode => mode == 'replay';
}
