import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/color_clash_card_model.dart';
import '../../models/color_clash_home_model.dart';
import '../../models/color_clash_match_snapshot.dart';
import '../../models/color_clash_table_model.dart';
import '../../providers/color_clash_session_controller.dart';
import '../../screens/profile/enhanced_profile_screen.dart';
import '../../screens/rooms/room_detail_screen.dart';
import '../../services/room_service.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/color_clash/color_clash_board_widget.dart';
import '../../widgets/color_clash/color_clash_card_widget.dart';
import '../../widgets/color_clash/color_clash_profile_actions_sheet.dart';
import '../../widgets/color_clash/color_clash_prompt_sheet.dart';
import '../../widgets/color_clash/color_clash_seat_widget.dart';
import '../../widgets/color_clash/color_clash_social_bar.dart';
import '../../widgets/color_clash/color_clash_status_banner.dart';
import '../../widgets/gift_animation_overlay.dart';
import '../../widgets/gifting/gift_bottom_sheet.dart';
import '../../widgets/rounded_scaffold.dart';
import '../../widgets/rooms/reaction_animation_overlay.dart';
import '../../widgets/rooms/reaction_quick_panel.dart';

class ColorClashTableScreen extends StatefulWidget {
  const ColorClashTableScreen({
    super.key,
    this.matchId,
    this.roomId,
  });

  static const String routeName = '/games/color-clash/table';

  final String? matchId;
  final String? roomId;

  @override
  State<ColorClashTableScreen> createState() => _ColorClashTableScreenState();
}

class _ColorClashTableScreenState extends State<ColorClashTableScreen>
    with WidgetsBindingObserver {
  String? _matchId;
  String? _roomId;
  bool _requestedSync = false;
  String? _lastPendingKey;
  Timer? _heartbeatTimer;
  Timer? _tickerTimer;
  StreamSubscription<Map<String, dynamic>>? _voiceSubscription;
  final Map<int, GlobalKey> _seatKeys = <int, GlobalKey>{};
  final Map<String, bool> _speakingByUserId = <String, bool>{};
  final Map<String, bool> _mutedByUserId = <String, bool>{};
  DateTime? _lastReactionAt;
  bool _joinedSocketRoom = false;
  bool _isReturningToRoom = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voiceSubscription = SocketService.voiceStream.listen(_handleVoiceEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _matchId ??= widget.matchId ?? args?['matchId']?.toString();
    _roomId ??= widget.roomId ?? args?['roomId']?.toString();
    if (!_requestedSync && (_matchId ?? '').isNotEmpty) {
      _requestedSync = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final controller = context.read<ColorClashSessionController>();
        controller.trackUiEvent(
          'table_screen_opened',
          payload: <String, Object?>{
            'matchId': _matchId,
            'roomId': _roomId,
          },
        );
        await controller.openMatch(
              _matchId!,
              roomId: _roomId,
            );
        _joinSocialRoomSocket();
        _startHeartbeat();
        _startTicker();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && (_matchId ?? '').isNotEmpty) {
      unawaited(
        context.read<ColorClashSessionController>().openMatch(
              _matchId!,
              roomId: _roomId,
              forceReconnect: true,
            ),
      );
      _joinSocialRoomSocket();
      _startHeartbeat();
      _startTicker();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _tickerTimer?.cancel();
    _voiceSubscription?.cancel();
    if (_joinedSocketRoom && (_roomId ?? '').isNotEmpty) {
      SocketService.leaveRoom(_roomId!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ColorClashSessionController>();
    _followPendingTarget(controller);
    final snapshot = controller.matchSnapshot;
    final match =
        snapshot != null && snapshot.matchId == _matchId ? snapshot : null;
    final room = controller.currentRoomSummary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _confirmLeaveView();
      },
      child: RoundedScaffold(
        showBackButton: false,
        titleWidget: _HeaderTitle(
          title: room?.name ?? 'Color Clash Table',
          subtitle:
              '${room?.tableModeLabel ?? 'Live table'}${match?.isSpectatorView == true ? ' - Spectator' : ''}',
        ),
        actions: [
          _StatusBadge(
            label: _connectionLabel(controller),
            tone: _connectionTone(controller),
          ),
          const SizedBox(width: 8),
          if ((_roomId ?? '').isNotEmpty)
            IconButton(
              tooltip: 'Return to room',
              onPressed: _isReturningToRoom ? null : _returnToRoom,
              icon: _isReturningToRoom
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.voice_chat_rounded),
            ),
        ],
        body: _buildBody(context, controller, match, room),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ColorClashSessionController controller,
    ColorClashMatchSnapshotModel? match,
    ColorClashRoomSummaryModel? room,
  ) {
    if ((_matchId ?? '').isEmpty) {
      return const _MessageState(
        title: 'No active match',
        message:
            'A Color Clash match id is required before the gameplay table can open.',
      );
    }
    if (controller.isMatchLoading && match == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.matchError != null && match == null) {
      return _MessageState(
        title: 'Table unavailable',
        message: controller.matchError!,
        actionLabel: 'Reconnect',
        onPressed: () async {
          await controller.openMatch(
            _matchId!,
            roomId: _roomId,
            forceReconnect: true,
          );
        },
      );
    }
    if (match == null) {
      return _MessageState(
        title: 'Waiting for sync',
        message: 'The backend has not returned a playable snapshot yet.',
        actionLabel: 'Retry',
        onPressed: () async {
          await controller.openMatch(
            _matchId!,
            roomId: _roomId,
            forceReconnect: true,
          );
        },
      );
    }

    final seats = _seatViews(controller, match);
    final localSeat = seats
        .where((entry) => entry.seatIndex == controller.mySeatIndex)
        .cast<_SeatViewData?>()
        .firstWhere((entry) => entry != null, orElse: () => null);
    final otherSeats = seats
        .where((entry) => entry.seatIndex != controller.mySeatIndex)
        .toList(growable: false);

    final tableColumn = Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            children: [
              if (controller.statusNotice != null)
                ColorClashStatusBanner(
                  notice: controller.statusNotice!,
                  onDismiss: controller.clearStatusNotice,
                ),
              _MetaStrip(
                modeLabel: room?.tableModeLabel ?? 'Live table',
                stakeText: room?.isPaidTable == true
                    ? '${room!.stake.entryFee} gold'
                    : 'Free table',
                spectators: match.presence?.spectators ?? 0,
              ),
              if ((controller.lastRealtimeError ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                _InlineNotice(
                  tone: AppColors.errorRed,
                  icon: Icons.error_outline_rounded,
                  text: controller.lastRealtimeError!,
                  actionLabel: 'Sync',
                  onPressed: () async {
                    controller.clearRealtimeError();
                    await controller.openMatch(
                      _matchId!,
                      roomId: _roomId,
                      forceReconnect: true,
                    );
                  },
                ),
              ],
              if (controller.reconnectState.status ==
                  ColorClashReconnectStatus.reconnecting) ...[
                const SizedBox(height: 12),
                const _InlineNotice(
                  tone: AppColors.warningOrange,
                  icon: Icons.sync_rounded,
                  text: 'Recovering the authoritative match session.',
                ),
              ],
              if (controller.settlementSummary != null) ...[
                const SizedBox(height: 12),
                _InlineNotice(
                  tone: controller.settlementSummary!.isFailed
                      ? AppColors.errorRed
                      : controller.settlementSummary!.isSettled
                          ? AppColors.successGreen
                          : AppColors.warningOrange,
                  icon: controller.settlementSummary!.isSettled
                      ? Icons.account_balance_wallet_rounded
                      : Icons.hourglass_top_rounded,
                  text: controller.settlementSummary!.statusLabel,
                ),
              ],
              const SizedBox(height: 16),
              ColorClashSocialBar(
                reactionsEnabled: (_roomId ?? '').isNotEmpty,
                giftsEnabled: (_roomId ?? '').isNotEmpty &&
                    !match.isSpectatorView &&
                    seats.any((seat) => (seat.userId ?? '').isNotEmpty),
                returnEnabled: (_roomId ?? '').isNotEmpty,
                onOpenReactions: () => _openReactions(controller),
                onOpenGifts: () => _openGiftPicker(
                  controller: controller,
                  seats: seats,
                ),
                onReturnToRoom: _returnToRoom,
              ),
              const SizedBox(height: 16),
              if (otherSeats.isNotEmpty)
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: otherSeats
                      .map(
                        (seat) => SizedBox(
                          width: MediaQuery.of(context).size.width > 560
                              ? (MediaQuery.of(context).size.width - 64) / 2
                              : double.infinity,
                          child: KeyedSubtree(
                            key: _seatKeyFor(seat.seatIndex),
                            child: ColorClashSeatWidget(
                              name: seat.name,
                              avatarUrl: seat.avatarUrl,
                              cardCount: seat.cardCount,
                              seatIndex: seat.seatIndex,
                              isCurrentTurn: seat.isCurrentTurn,
                              isFinalCard: seat.isFinalCard,
                              isWinner: seat.isWinner,
                              isDisconnected: seat.isDisconnected,
                              isSpeaking: _speakingByUserId[seat.userId] == true,
                              isMuted: _mutedByUserId[seat.userId] == true,
                              hasShield: seat.hasShield,
                              timeoutStrikes: seat.timeoutStrikes,
                              placement: seat.placement,
                              onTap: seat.userId == null
                                  ? null
                                  : () => _openSeatActions(
                                        seat,
                                        canGift: !match.isSpectatorView,
                                      ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              const SizedBox(height: 16),
              ColorClashBoardWidget(
                discardTop: match.publicState.discardTop,
                drawPileCount: match.publicState.drawPileCount,
                discardCount: match.publicState.discardCount,
                currentHue: match.publicState.currentHue,
                direction: match.publicState.direction,
                pendingEffect: match.publicState.pendingEffect,
                lastActionSummary: controller.lastActionSummary,
                roundResult: match.publicState.roundResult,
                turnEndsAt: controller.turnEndsAt,
                isSubmitting: controller.isSubmittingMove,
                isSpectator: match.isSpectatorView,
              ),
              if (localSeat != null) ...[
                const SizedBox(height: 16),
                KeyedSubtree(
                  key: _seatKeyFor(localSeat.seatIndex),
                  child: ColorClashSeatWidget(
                    name: localSeat.name,
                    avatarUrl: localSeat.avatarUrl,
                    cardCount: localSeat.cardCount,
                    seatIndex: localSeat.seatIndex,
                    isCurrentTurn: localSeat.isCurrentTurn,
                    isFinalCard: localSeat.isFinalCard,
                    isWinner: localSeat.isWinner,
                    isDisconnected: localSeat.isDisconnected,
                    isSpeaking: _speakingByUserId[localSeat.userId] == true,
                    isMuted: _mutedByUserId[localSeat.userId] == true,
                    hasShield: localSeat.hasShield,
                    timeoutStrikes: localSeat.timeoutStrikes,
                    placement: localSeat.placement,
                    isLocalSeat: true,
                    onTap: localSeat.userId == null
                        ? null
                        : () => _openSeatActions(
                              localSeat,
                              canGift: false,
                            ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!match.isSpectatorView &&
            match.privateState != null &&
            !match.isCompleted)
          _HandZone(
            hand: match.privateState!.hand,
            selectedCardId: controller.selectedCardId,
            playableCardIds: controller.playableCardIds,
            isSubmitting: controller.isSubmittingMove,
            onCardTap: (card) => _onCardTap(controller, card),
          ),
        _ActionZone(
          controller: controller,
          snapshot: match,
          onPlayPressed: () => _playSelected(controller),
          onReturnToRoom: (_roomId ?? '').isNotEmpty ? _returnToRoom : null,
        ),
      ],
    );

    return GiftAnimationOverlay(
      filterRoomId: _roomId,
      child: Stack(
        children: [
          tableColumn,
          Positioned.fill(
            child: ReactionAnimationOverlay(
              seatKeys: _seatKeys,
              filterRoomId: _roomId,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onCardTap(
    ColorClashSessionController controller,
    ColorClashCardModel card,
  ) async {
    final wasSelected = controller.selectedCardId == card.id;
    controller.selectCard(card.id);
    if (wasSelected &&
        controller.canPlaySelectedCard &&
        !controller.cardNeedsHueChoice(card.id) &&
        !controller.cardNeedsTargetChoice(card.id)) {
      await _playSelected(controller);
    }
  }

  Future<void> _playSelected(ColorClashSessionController controller) async {
    final card = controller.selectedCard;
    if (card == null) return;

    int? targetSeat;
    final targets = controller.availableTargetsForCard(card.id);
    if (targets.length > 1) {
      targetSeat = await showColorClashSeatPrompt(
        context,
        seats: targets,
        title: 'Choose a target seat',
      );
      if (!mounted || targetSeat == null) return;
    } else if (targets.length == 1) {
      targetSeat = targets.single;
    }

    String? chosenHue;
    final hues = controller.availableHuesForCard(card.id);
    if (hues.length > 1) {
      chosenHue = await showColorClashHuePrompt(
        context,
        hues: hues,
        title: 'Choose a clash hue',
      );
      if (!mounted || chosenHue == null) return;
    } else if (hues.length == 1) {
      chosenHue = hues.single;
    }

    await controller.playCard(
      card.id,
      chosenHue: chosenHue,
      targetSeat: targetSeat,
    );
  }

  GlobalKey _seatKeyFor(int seatIndex) {
    return _seatKeys.putIfAbsent(
      seatIndex,
      () => GlobalKey(debugLabel: 'cc-seat-$seatIndex'),
    );
  }

  void _joinSocialRoomSocket() {
    final roomId = _roomId;
    if (_joinedSocketRoom || (roomId ?? '').isEmpty) {
      return;
    }
    SocketService.joinRoom(roomId!);
    _joinedSocketRoom = true;
  }

  void _handleVoiceEvent(Map<String, dynamic> data) {
    if (!mounted) {
      return;
    }
    if ((_roomId ?? '').isNotEmpty && data['roomId']?.toString() != _roomId) {
      return;
    }
    final userId = data['userId']?.toString();
    if ((userId ?? '').isEmpty) {
      return;
    }
    final eventType = data['_eventType']?.toString();
    if (eventType == 'speaking') {
      setState(() {
        _speakingByUserId[userId!] = data['speaking'] == true;
      });
      return;
    }
    if (eventType == 'mute') {
      setState(() {
        _mutedByUserId[userId!] = data['muted'] == true;
      });
    }
  }

  Future<void> _openReactions(
    ColorClashSessionController controller,
  ) async {
    final roomId = _roomId;
    if ((roomId ?? '').isEmpty) {
      return;
    }
    final now = DateTime.now();
    if (_lastReactionAt != null &&
        now.difference(_lastReactionAt!) < const Duration(milliseconds: 700)) {
      return;
    }
    _lastReactionAt = now;

    controller.trackUiEvent(
      'reaction_panel_opened',
      payload: <String, Object?>{
        'matchId': _matchId,
        'roomId': roomId,
      },
    );

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ReactionQuickPanel(
        onSelectEmoji: (emoji) {
          SocketService.sendReaction(roomId: roomId!, emoji: emoji);
          controller.trackUiEvent(
            'reaction_sent',
            payload: <String, Object?>{
              'matchId': _matchId,
              'roomId': roomId,
              'emoji': emoji,
            },
          );
          controller.showStatusNotice(
            'Reaction sent to the room.',
            tone: ColorClashNoticeTone.success,
          );
        },
      ),
    );
  }

  Future<void> _openGiftPicker({
    required ColorClashSessionController controller,
    required List<_SeatViewData> seats,
  }) async {
    controller.trackUiEvent(
      'gift_picker_opened',
      payload: <String, Object?>{
        'matchId': _matchId,
        'roomId': _roomId,
      },
    );
    final giftableSeats = seats
        .where((seat) => (seat.userId ?? '').isNotEmpty)
        .toList(growable: false);
    if (giftableSeats.isEmpty) {
      controller.showStatusNotice(
        'No live seat is ready for gifting yet.',
        tone: ColorClashNoticeTone.warning,
      );
      return;
    }

    final chosenSeat = await showModalBottomSheet<_SeatViewData>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose a player',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pick the Color Clash seat you want to celebrate.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 16),
              for (final seat in giftableSeats) ...[
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  tileColor: AppColors.backgroundWhite,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.1),
                    backgroundImage: (seat.avatarUrl ?? '').isNotEmpty
                        ? NetworkImage(_fullAvatarUrl(seat.avatarUrl))
                        : null,
                    child: (seat.avatarUrl ?? '').isEmpty
                        ? Text(
                            seat.name.isNotEmpty
                                ? seat.name.substring(0, 1).toUpperCase()
                                : '?',
                          )
                        : null,
                  ),
                  title: Text(seat.name),
                  subtitle: Text('Seat ${seat.seatIndex + 1}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).pop(seat),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );

    if (!mounted || chosenSeat == null) {
      return;
    }
    await _showGiftBottomSheetForSeat(chosenSeat, controller: controller);
  }

  Future<void> _showGiftBottomSheetForSeat(
    _SeatViewData seat, {
    required ColorClashSessionController controller,
  }) async {
    final userId = seat.userId;
    if ((userId ?? '').isEmpty) {
      return;
    }
    final sent = await showGiftBottomSheet(
      context: context,
      toUserId: userId!,
      toUsername: seat.name,
      roomId: _roomId,
    );
    if (!mounted || sent != true) {
      return;
    }
    controller.trackUiEvent(
      'gift_sent_from_match',
      payload: <String, Object?>{
        'matchId': _matchId,
        'roomId': _roomId,
        'targetUserId': userId,
      },
    );
    controller.showStatusNotice(
      'Gift sent to ${seat.name}.',
      tone: ColorClashNoticeTone.success,
    );
  }

  Future<void> _openSeatActions(
    _SeatViewData seat, {
    required bool canGift,
  }) async {
    final userId = seat.userId;
    if ((userId ?? '').isEmpty) {
      return;
    }
    context.read<ColorClashSessionController>().trackUiEvent(
          'seat_profile_opened',
          payload: <String, Object?>{
            'matchId': _matchId,
            'roomId': _roomId,
            'targetUserId': userId,
            'seatIndex': seat.seatIndex,
          },
        );
    final action = await showColorClashProfileActionsSheet(
      context,
      userId: userId!,
      username: seat.name,
      avatarUrl: seat.avatarUrl,
      canGift: canGift,
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == ColorClashProfileAction.viewProfile) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EnhancedProfileScreen(userId: userId),
        ),
      );
      return;
    }
    await _showGiftBottomSheetForSeat(
      seat,
      controller: context.read<ColorClashSessionController>(),
    );
  }

  Future<void> _returnToRoom() async {
    final roomId = _roomId;
    if (_isReturningToRoom || (roomId ?? '').isEmpty) {
      return;
    }
    setState(() {
      _isReturningToRoom = true;
    });
    try {
      final room = await RoomService.getRoomById(roomId!);
      if (!mounted) {
        return;
      }
      if (room == null) {
        context.read<ColorClashSessionController>().showStatusNotice(
              'We could not load the linked room right now.',
              tone: ColorClashNoticeTone.warning,
            );
        return;
      }
      context.read<ColorClashSessionController>().trackUiEvent(
            'return_to_room_opened',
            payload: <String, Object?>{
              'matchId': _matchId,
              'roomId': roomId,
            },
          );
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RoomDetailScreen(room: room),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isReturningToRoom = false;
        });
      }
    }
  }

  String _fullAvatarUrl(String? value) {
    if ((value ?? '').isEmpty) {
      return '';
    }
    if (value!.startsWith('http')) {
      return value;
    }
    return '${AppConfig.baseUrl}$value';
  }

  List<_SeatViewData> _seatViews(
    ColorClashSessionController controller,
    ColorClashMatchSnapshotModel snapshot,
  ) {
    final placements = <int, int>{};
    for (final placement
        in snapshot.publicState.roundResult?.placements ?? const []) {
      placements[placement.seatIndex] = placement.placement;
    }
    final homePlayers = controller.home?.activeMatch?.players ??
        const <ColorClashHomeActivePlayerModel>[];

    return snapshot.publicState.players.map((player) {
      final lobbyPlayer = controller.lobbyPlayerForUser(player.userId);
      ColorClashHomeActivePlayerModel? homePlayer;
      for (final entry in homePlayers) {
        if (entry.userId == player.userId) {
          homePlayer = entry;
          break;
        }
      }
      return _SeatViewData(
        seatIndex: player.seatIndex,
        userId: player.userId,
        name: lobbyPlayer?.username ??
            homePlayer?.username ??
            'Seat ${player.seatIndex + 1}',
        avatarUrl: lobbyPlayer?.avatar ?? homePlayer?.avatar,
        cardCount: player.handCount,
        isCurrentTurn:
            snapshot.publicState.currentTurnSeat == player.seatIndex &&
                !snapshot.isCompleted,
        isFinalCard: player.handCount == 1 ||
            player.pendingLastCardCall ||
            player.declaredLastCard,
        isWinner:
            snapshot.publicState.roundResult?.winnerSeat == player.seatIndex,
        isDisconnected: player.status == 'disconnected',
        hasShield: player.hasShield,
        timeoutStrikes: player.timeoutStrikes,
        placement: placements[player.seatIndex],
      );
    }).toList(growable: false)
      ..sort((a, b) => a.seatIndex.compareTo(b.seatIndex));
  }

  void _followPendingTarget(ColorClashSessionController controller) {
    final target = controller.pendingMatchTarget;
    if (target == null || target.matchId == _matchId) return;
    final key = '${target.roomId}:${target.matchId}:${target.source}';
    if (_lastPendingKey == key) return;
    _lastPendingKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.consumePendingMatchTarget();
      Navigator.of(context).pushReplacementNamed(
        ColorClashTableScreen.routeName,
        arguments: <String, dynamic>{
          'matchId': target.matchId,
          'roomId': target.roomId,
        },
      );
    });
  }

  Future<void> _confirmLeaveView() async {
    final action = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave table view?'),
            content: const Text(
              'The match keeps running on the server. You can reconnect from Games at any time.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('stay'),
                child: const Text('Stay'),
              ),
              if ((_roomId ?? '').isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.of(context).pop('room'),
                  child: const Text('Return to room'),
                ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop('leave'),
                child: const Text('Leave view'),
              ),
            ],
          ),
        ) ??
        'stay';
    if (!mounted) {
      return;
    }
    if (action == 'room') {
      await _returnToRoom();
      return;
    }
    if (action == 'leave') {
      Navigator.of(context).pop();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 18), (_) {
      unawaited(context.read<ColorClashSessionController>().sendHeartbeat());
    });
  }

  void _startTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Color _connectionTone(ColorClashSessionController controller) {
    if (controller.reconnectState.status ==
        ColorClashReconnectStatus.reconnecting) {
      return AppColors.warningOrange;
    }
    if ((controller.lastRealtimeError ?? '').isNotEmpty) {
      return AppColors.errorRed;
    }
    return AppColors.successGreen;
  }

  String _connectionLabel(ColorClashSessionController controller) {
    if (controller.reconnectState.status ==
        ColorClashReconnectStatus.reconnecting) {
      return 'Syncing';
    }
    if ((controller.lastRealtimeError ?? '').isNotEmpty) {
      return 'Recover';
    }
    return 'Live';
  }
}

class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tone,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _MetaStrip extends StatelessWidget {
  const _MetaStrip({
    required this.modeLabel,
    required this.stakeText,
    required this.spectators,
  });

  final String modeLabel;
  final String stakeText;
  final int spectators;

  @override
  Widget build(BuildContext context) {
    Widget buildPill(IconData icon, String label) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.mood.outlineSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.primaryBlue),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        buildPill(Icons.grid_goldenratio_rounded, modeLabel),
        buildPill(Icons.stars_rounded, stakeText),
        buildPill(Icons.visibility_rounded, '$spectators watching'),
      ],
    );
  }
}

class _HandZone extends StatelessWidget {
  const _HandZone({
    required this.hand,
    required this.selectedCardId,
    required this.playableCardIds,
    required this.isSubmitting,
    required this.onCardTap,
  });

  final List<ColorClashCardModel> hand;
  final String? selectedCardId;
  final Set<String> playableCardIds;
  final bool isSubmitting;
  final Future<void> Function(ColorClashCardModel card) onCardTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: context.mood.outlineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your hand',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a card to focus it. Tap again or use Play to send the move.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 156,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: hand.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final card = hand[index];
                return ColorClashCardWidget(
                  card: card,
                  isSelected: selectedCardId == card.id,
                  isPlayable: playableCardIds.contains(card.id),
                  isDimmed: isSubmitting ||
                      (!playableCardIds.contains(card.id) &&
                          selectedCardId != card.id),
                  onTap: isSubmitting ? null : () => onCardTap(card),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionZone extends StatelessWidget {
  const _ActionZone({
    required this.controller,
    required this.snapshot,
    required this.onPlayPressed,
    this.onReturnToRoom,
  });

  final ColorClashSessionController controller;
  final ColorClashMatchSnapshotModel snapshot;
  final Future<void> Function() onPlayPressed;
  final Future<void> Function()? onReturnToRoom;

  @override
  Widget build(BuildContext context) {
    final prompt = snapshot.privateState?.prompt;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        border: Border(top: BorderSide(color: context.mood.outlineSoft)),
      ),
      child: snapshot.isSpectatorView
          ? const _InlineNotice(
              tone: AppColors.primaryBlue,
              icon: Icons.visibility_rounded,
              text:
                  'Spectator mode stays public-only while the backend keeps private hands sealed.',
            )
          : snapshot.isCompleted
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Match finished',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Keep the room energy going with a rematch or jump back into the voice room.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (controller.settlementSummary != null) ...[
                      const SizedBox(height: 12),
                      _InlineNotice(
                        tone: controller.settlementSummary!.isSettled
                            ? AppColors.successGreen
                            : controller.settlementSummary!.isFailed
                                ? AppColors.errorRed
                                : AppColors.warningOrange,
                        icon: controller.settlementSummary!.isSettled
                            ? Icons.account_balance_wallet_rounded
                            : Icons.sync_rounded,
                        text: controller.settlementSummary!.statusLabel,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: controller.isSubmittingMove
                                ? null
                                : () async {
                                    await controller.enterRematchVote(true);
                                  },
                            child: const Text('Vote rematch'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: controller.isSubmittingMove
                                ? null
                                : () async {
                                    await controller.enterRematchVote(false);
                                  },
                            child: const Text('Skip'),
                          ),
                        ),
                      ],
                    ),
                    if (onReturnToRoom != null) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            await onReturnToRoom!();
                          },
                          icon: const Icon(Icons.voice_chat_rounded),
                          label: const Text('Return to room'),
                        ),
                      ),
                    ],
                  ],
                )
              : prompt?.isChallengeResponse == true
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prompt!.displayLabel,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'The backend is waiting for your response.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: controller.isSubmittingMove
                                    ? null
                                    : () async {
                                        await controller
                                            .respondToChallenge('challenge');
                                      },
                                child: const Text('Challenge'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: controller.isSubmittingMove
                                    ? null
                                    : () async {
                                        await controller
                                            .respondToChallenge('decline');
                                      },
                                child: const Text('Decline'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (controller.canKeepDrawn)
                          const _InlineNotice(
                            tone: AppColors.warningOrange,
                            icon: Icons.layers_clear_rounded,
                            text:
                                'You already drew. Keep the card to pass, or play a legal card now.',
                          ),
                        if (controller.selectedCard != null) ...[
                          Text(
                            controller.selectedCard!.displayName,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            controller.canPlaySelectedCard
                                ? 'Selected for play.'
                                : 'Selected, but not legal right now.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: controller.canDraw
                                    ? () async {
                                        await controller.drawCard();
                                      }
                                    : null,
                                icon: const Icon(Icons.layers_rounded),
                                label: const Text('Draw'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: controller.canPlaySelectedCard
                                    ? onPlayPressed
                                    : null,
                                icon: const Icon(Icons.send_rounded),
                                label: const Text('Play'),
                              ),
                            ),
                          ],
                        ),
                        if (controller.canKeepDrawn) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonal(
                              onPressed: controller.isSubmittingMove
                                  ? null
                                  : () async {
                                      await controller.keepDrawnCard();
                                    },
                              child: const Text('Keep drawn card and pass'),
                            ),
                          ),
                        ],
                      ],
                    ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.tone,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onPressed,
  });

  final Color tone;
  final IconData icon;
  final String text;
  final String? actionLabel;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (actionLabel != null && onPressed != null)
            TextButton(
              onPressed: () => onPressed!(),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onPressed,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: context.mood.outlineSoft),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (actionLabel != null && onPressed != null) ...[
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => onPressed!(),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SeatViewData {
  const _SeatViewData({
    required this.seatIndex,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.cardCount,
    required this.isCurrentTurn,
    required this.isFinalCard,
    required this.isWinner,
    required this.isDisconnected,
    required this.hasShield,
    required this.timeoutStrikes,
    required this.placement,
  });

  final int seatIndex;
  final String? userId;
  final String name;
  final String? avatarUrl;
  final int cardCount;
  final bool isCurrentTurn;
  final bool isFinalCard;
  final bool isWinner;
  final bool isDisconnected;
  final bool hasShield;
  final int timeoutStrikes;
  final int? placement;
}
