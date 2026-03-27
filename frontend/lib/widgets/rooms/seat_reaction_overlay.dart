import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/socket_service.dart';
import 'floating_reaction.dart';

class SeatReactionOverlay extends StatefulWidget {
  final String? userId; // For matched participants
  final int? seatIndex; // For empty seats or index-based matching
  final Widget child;

  const SeatReactionOverlay({
    super.key,
    this.userId,
    this.seatIndex,
    required this.child,
  });

  @override
  State<SeatReactionOverlay> createState() => _SeatReactionOverlayState();
}

class _SeatReactionOverlayState extends State<SeatReactionOverlay> {
  final List<OverlayReactionData> _activeReactions = [];
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = SocketService.reactionStream.listen((data) {
      bool isMatch = false;

      // Match by userId or seatIndex
      if (widget.userId != null &&
          widget.userId!.isNotEmpty &&
          data['userId'] == widget.userId) {
        isMatch = true;
      } else if (widget.seatIndex != null &&
          data['seatIndex'] == widget.seatIndex) {
        isMatch = true;
      }

      if (isMatch && mounted) {
        debugPrint(
            'ðŸŽ¬ Triggering reaction ${data['emoji']} on seat ${widget.seatIndex}');
        setState(() {
          _activeReactions.add(OverlayReactionData(
            id: '${DateTime.now().microsecondsSinceEpoch}_${data['userId']}',
            emoji: data['emoji'] ?? 'ðŸ”¥',
          ));
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        widget.child,
        ..._activeReactions.map((reaction) => FloatingReaction(
              key: ValueKey(reaction.id),
              emoji: reaction.emoji,
              onFinished: () {
                if (mounted) {
                  setState(() {
                    _activeReactions.removeWhere((r) => r.id == reaction.id);
                  });
                }
              },
            )),
      ],
    );
  }
}

class OverlayReactionData {
  final String id;
  final String emoji;
  OverlayReactionData({required this.id, required this.emoji});
}






