import 'dart:math';
import 'package:flutter/material.dart';
import 'reaction_artwork.dart';

class FloatingReaction extends StatefulWidget {
  final String emoji;
  final VoidCallback onFinished;

  const FloatingReaction({
    super.key,
    required this.emoji,
    required this.onFinished,
  });

  @override
  State<FloatingReaction> createState() => _FloatingReactionState();
}

class _FloatingReactionState extends State<FloatingReaction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _verticalOffset;
  late final Animation<double> _horizontalOffset;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();

    final random = Random(
      widget.emoji.hashCode ^ DateTime.now().microsecondsSinceEpoch,
    );
    final driftDirection = random.nextBool() ? 1.0 : -1.0;
    final driftDistance = 18 + random.nextDouble() * 22;
    final rotationAmount = 0.12 + random.nextDouble() * 0.12;

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
    );

    final eased = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _verticalOffset = Tween<double>(begin: 0, end: -140).animate(eased);
    _horizontalOffset = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: driftDistance * driftDirection),
        weight: 58,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: driftDistance * driftDirection,
          end: driftDistance * -0.35 * driftDirection,
        ),
        weight: 42,
      ),
    ]).animate(eased);
    _rotation = Tween<double>(
      begin: -rotationAmount * driftDirection,
      end: rotationAmount * driftDirection,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 18),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 32),
    ]).animate(_controller);
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.65, end: 1.16)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 36,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.16, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 64,
      ),
    ]).animate(_controller);

    _controller.forward().whenComplete(widget.onFinished);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasArtwork = reactionArtworkAsset(widget.emoji) != null;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.translate(
          offset: Offset(
            _horizontalOffset.value,
            _verticalOffset.value,
          ),
          child: Transform.rotate(
            angle: _rotation.value,
            child: Transform.scale(
              scale: _scale.value,
              child: Opacity(
                opacity: _opacity.value,
                child: child,
              ),
            ),
          ),
        ),
        child: hasArtwork
            ? SizedBox(
                width: 96,
                height: 96,
                child: Center(
                  child: ReactionArtwork(
                    emoji: widget.emoji,
                    size: 90,
                  ),
                ),
              )
            : Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ReactionArtwork(
                  emoji: widget.emoji,
                  size: 36,
                  fallbackTextStyle: const TextStyle(
                    fontSize: 36,
                    shadows: [
                      Shadow(color: Colors.black45, blurRadius: 12),
                      Shadow(color: Colors.white24, blurRadius: 4),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
