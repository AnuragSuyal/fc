import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/socket_service.dart';
import 'floating_reaction.dart';

class ReactionAnimationOverlay extends StatefulWidget {
  final Map<int, GlobalKey> seatKeys;
  final String? filterRoomId;

  const ReactionAnimationOverlay({
    super.key,
    required this.seatKeys,
    this.filterRoomId,
  });

  @override
  State<ReactionAnimationOverlay> createState() =>
      _ReactionAnimationOverlayState();
}

class _ReactionAnimationOverlayState extends State<ReactionAnimationOverlay> {
  static const int _maxVisibleReactions = 24;
  static const int _seedChunkMax = 1 << 16;

  final List<_PendingReaction> _reactions = [];
  StreamSubscription? _subscription;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _soundSubscription;

  static const Map<String, String> _soundToEmoji = {
    'clap': '👏',
    'laugh': '😂',
    'cheer': '🎉',
    'wow': '😮',
    'kick': '🥊',
    'bell': '🔔',
    'whistle': '😗',
    'airhorn': '📣',
  };

  @override
  void initState() {
    super.initState();
    _subscription = SocketService.reactionStream.listen((data) {
      if (!_matchesRoom(data)) return;
      final seatIndex = data['seatIndex'] as int? ?? -1;
      final emojis = _extractEmojis(data);
      _triggerReactionBurst(seatIndex: seatIndex, emojis: emojis);
    });

    _messageSubscription = SocketService.roomMessageStream.listen((data) {
      if (!_matchesRoom(data)) return;
      if (data['type'] != 'emoji' || data['emojis'] == null) return;

      final seatIndex = data['seatIndex'] as int? ?? -1;
      final emojis = (data['emojis'] as List).map((e) => '$e').toList();
      _triggerReactionBurst(seatIndex: seatIndex, emojis: emojis);
    });

    _soundSubscription = SocketService.soundStream.listen((data) {
      if (!_matchesRoom(data)) return;
      final seatIndex = data['seatIndex'] as int? ?? -1;
      final soundId = data['soundId']?.toString();
      final emoji = _soundToEmoji[soundId] ?? '🎵';
      _triggerReactionBurst(seatIndex: seatIndex, emojis: [emoji]);
    });
  }

  bool _matchesRoom(Map<String, dynamic> data) {
    final filterRoomId = widget.filterRoomId;
    if (filterRoomId == null || filterRoomId.isEmpty) {
      return true;
    }
    return data['roomId']?.toString() == filterRoomId;
  }

  List<String> _extractEmojis(Map<String, dynamic> data) {
    if (data['emojis'] is List) {
      return (data['emojis'] as List).map((emoji) => '$emoji').toList();
    }

    final emoji = data['emoji']?.toString();
    if (emoji == null || emoji.isEmpty) {
      return const [];
    }
    return [emoji];
  }

  void _triggerReactionBurst({
    required int seatIndex,
    required List<String> emojis,
  }) {
    if (!mounted || seatIndex == -1 || emojis.isEmpty) return;

    final key = widget.seatKeys[seatIndex];
    if (key == null || key.currentContext == null) return;

    final seatBox = key.currentContext!.findRenderObject() as RenderBox?;
    final overlayBox = context.findRenderObject() as RenderBox?;
    if (seatBox == null || overlayBox == null) return;

    final center = seatBox.localToGlobal(
      Offset(seatBox.size.width / 2, seatBox.size.height / 2),
      ancestor: overlayBox,
    );
    final random = Random();
    final nextReactions = <_PendingReaction>[
      ..._reactions,
      for (var i = 0; i < emojis.length; i++)
        _PendingReaction(
          id: '${DateTime.now().microsecondsSinceEpoch}-${emojis[i]}-${random.nextInt(1000)}',
          emoji: emojis[i],
          position: center +
              Offset(
                random.nextDouble() * 42 - 21,
                -6 - random.nextDouble() * 14,
              ),
          seed: _nextSafeSeed(random),
          delayMs: i * 55 + random.nextInt(45),
        ),
    ];

    if (nextReactions.length > _maxVisibleReactions) {
      nextReactions.removeRange(0, nextReactions.length - _maxVisibleReactions);
    }

    setState(() {
      _reactions
        ..clear()
        ..addAll(nextReactions);
    });
  }

  void _removeReaction(String id) {
    if (!mounted || _reactions.isEmpty) return;
    setState(() {
      _reactions.removeWhere((reaction) => reaction.id == id);
    });
  }

  int _nextSafeSeed(Random random) {
    final left = random.nextInt(_seedChunkMax);
    final right = random.nextInt(_seedChunkMax);
    return (left << 16) ^ right;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _messageSubscription?.cancel();
    _soundSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final reaction in _reactions)
              Positioned(
                left: reaction.position.dx - 24,
                top: reaction.position.dy - 24,
                child: FloatingReaction(
                  key: ValueKey(reaction.id),
                  emoji: reaction.emoji,
                  seed: reaction.seed,
                  launchDelayMs: reaction.delayMs,
                  onFinished: () => _removeReaction(reaction.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PendingReaction {
  final String id;
  final String emoji;
  final Offset position;
  final int seed;
  final int delayMs;

  const _PendingReaction({
    required this.id,
    required this.emoji,
    required this.position,
    required this.seed,
    required this.delayMs,
  });
}
