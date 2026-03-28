import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'reaction_artwork.dart';

class FloatingReaction extends StatefulWidget {
  final String emoji;
  final int seed;
  final int launchDelayMs;
  final VoidCallback onFinished;

  const FloatingReaction({
    super.key,
    required this.emoji,
    required this.seed,
    this.launchDelayMs = 0,
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
  late final Animation<double> _haloScale;
  late final Animation<double> _haloOpacity;
  late final List<_SparkleSpec> _sparkles;
  late final double _driftDirection;
  late final double _waveAmplitude;
  late final double _waveCycles;
  late final Color _accentColor;
  Timer? _launchTimer;

  @override
  void initState() {
    super.initState();

    final random = math.Random(widget.seed);
    _driftDirection = random.nextBool() ? 1.0 : -1.0;
    _waveAmplitude = 8 + random.nextDouble() * 8;
    _waveCycles = 1.6 + random.nextDouble() * 0.8;
    _accentColor = _reactionAccent(widget.emoji);
    final driftDistance = 18 + random.nextDouble() * 22;
    final rotationAmount = 0.12 + random.nextDouble() * 0.12;
    _sparkles = List<_SparkleSpec>.generate(5, (index) {
      final angle = (-math.pi / 1.8) + random.nextDouble() * (math.pi * 0.95);
      return _SparkleSpec(
        angle: angle,
        distance: 18 + random.nextDouble() * 24 + index * 2,
        size: 4 + random.nextDouble() * 4,
      );
    });

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1850 + random.nextInt(280)),
    );

    final eased = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _verticalOffset =
        Tween<double>(begin: 0, end: -170 - random.nextDouble() * 26)
            .animate(eased);
    _horizontalOffset = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: driftDistance * _driftDirection),
        weight: 58,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: driftDistance * _driftDirection,
          end: driftDistance * -0.28 * _driftDirection,
        ),
        weight: 42,
      ),
    ]).animate(eased);
    _rotation = Tween<double>(
      begin: -rotationAmount * _driftDirection,
      end: rotationAmount * _driftDirection,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 12),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 54),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 34),
    ]).animate(_controller);
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.48, end: 1.18)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 34,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.18, end: 0.98)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 64,
      ),
    ]).animate(_controller);
    _haloScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.5, end: 1.08)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 44,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.08, end: 1.34)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 56,
      ),
    ]).animate(_controller);
    _haloOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.82), weight: 16),
      TweenSequenceItem(tween: Tween(begin: 0.82, end: 0.18), weight: 56),
      TweenSequenceItem(tween: Tween(begin: 0.18, end: 0.0), weight: 28),
    ]).animate(_controller);

    if (widget.launchDelayMs > 0) {
      _launchTimer =
          Timer(Duration(milliseconds: widget.launchDelayMs), _start);
    } else {
      _start();
    }
  }

  @override
  void dispose() {
    _launchTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasArtwork = reactionArtworkAsset(widget.emoji) != null;
    final coreSize = hasArtwork ? 92.0 : 54.0;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = _controller.value;
          final waveOffset = math.sin(progress * math.pi * 2 * _waveCycles) *
              _waveAmplitude *
              (1 - progress);

          return Transform.translate(
            offset: Offset(
              _horizontalOffset.value + waveOffset,
              _verticalOffset.value,
            ),
            child: Transform.rotate(
              angle: _rotation.value +
                  (math.sin(progress * math.pi * 2.6) *
                      0.025 *
                      _driftDirection),
              child: Transform.scale(
                scale: _scale.value,
                child: Opacity(
                  opacity: _opacity.value,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      _buildHalo(coreSize),
                      for (final sparkle in _sparkles)
                        _buildSparkle(sparkle: sparkle, progress: progress),
                      child!,
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        child: hasArtwork
            ? Container(
                width: coreSize,
                height: coreSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.98),
                      _accentColor.withValues(alpha: 0.22),
                    ],
                    stops: const [0.18, 1],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.78),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _accentColor.withValues(alpha: 0.32),
                      blurRadius: 28,
                      spreadRadius: 3,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Center(
                  child: ReactionArtwork(
                    emoji: widget.emoji,
                    size: 84,
                  ),
                ),
              )
            : Container(
                width: coreSize,
                height: coreSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.98),
                      _accentColor.withValues(alpha: 0.24),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.72),
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _accentColor.withValues(alpha: 0.28),
                      blurRadius: 24,
                      spreadRadius: 3,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ReactionArtwork(
                  emoji: widget.emoji,
                  size: 34,
                  fallbackTextStyle: const TextStyle(
                    fontSize: 34,
                    shadows: [
                      Shadow(color: Colors.black38, blurRadius: 12),
                      Shadow(color: Colors.white24, blurRadius: 4),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  void _start() {
    if (!mounted) return;
    _controller.forward().whenComplete(widget.onFinished);
  }

  Widget _buildHalo(double coreSize) {
    final ringSize = coreSize + 18;
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.scale(
          scale: _haloScale.value,
          child: Opacity(
            opacity: _haloOpacity.value,
            child: Container(
              width: ringSize,
              height: ringSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _accentColor.withValues(alpha: 0.28),
                    _accentColor.withValues(alpha: 0.02),
                  ],
                  stops: const [0.2, 1],
                ),
              ),
            ),
          ),
        ),
        Transform.scale(
          scale: 0.86 + (_haloScale.value - 0.5) * 0.55,
          child: Opacity(
            opacity: _haloOpacity.value * 0.72,
            child: Container(
              width: ringSize + 8,
              height: ringSize + 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _accentColor.withValues(alpha: 0.48),
                  width: 1.4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSparkle({
    required _SparkleSpec sparkle,
    required double progress,
  }) {
    final travel = Curves.easeOut.transform(progress);
    final dx = math.cos(sparkle.angle) * sparkle.distance * travel;
    final dy =
        math.sin(sparkle.angle) * sparkle.distance * travel - (10 * progress);

    return Transform.translate(
      offset: Offset(dx, dy),
      child: Opacity(
        opacity: (1 - progress) * 0.95,
        child: Transform.rotate(
          angle: sparkle.angle + progress * math.pi,
          child: Container(
            width: sparkle.size,
            height: sparkle.size * 1.8,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(sparkle.size),
              boxShadow: [
                BoxShadow(
                  color: _accentColor.withValues(alpha: 0.42),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _reactionAccent(String emoji) {
    const palette = <Color>[
      Color(0xFFFF6B6B),
      Color(0xFFFFB347),
      Color(0xFF63DDFF),
      Color(0xFF7CF29A),
      Color(0xFFFF8CC6),
      Color(0xFFB69CFF),
      Color(0xFFFFE27A),
    ];

    var hash = 0;
    for (final rune in emoji.runes) {
      hash = (hash * 31 + rune) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }
}

class _SparkleSpec {
  final double angle;
  final double distance;
  final double size;

  const _SparkleSpec({
    required this.angle,
    required this.distance,
    required this.size,
  });
}
