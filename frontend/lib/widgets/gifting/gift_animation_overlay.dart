import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import '../../utils/haptics_util.dart';

class GiftAnimationOverlay extends StatefulWidget {
  final Stream<Map<String, dynamic>> giftStream;

  const GiftAnimationOverlay({super.key, required this.giftStream});

  @override
  State<GiftAnimationOverlay> createState() => _GiftAnimationOverlayState();
}

class _GiftAnimationOverlayState extends State<GiftAnimationOverlay> {
  static const int _maxVisibleGifts = 3;
  final List<_ActiveGift> _activeGifts = [];
  final List<Timer> _timers = [];
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.giftStream.listen((giftData) {
      _addGift(giftData);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  void _addGift(Map<String, dynamic> data) {
    final giftName = data['giftName'] ?? 'Gift';
    String? animationPath;

    // Map gift names to Lottie assets
    if (giftName.toString().toLowerCase().contains('fire')) {
      animationPath = 'assets/animations/fire.json';
    } else if (giftName.toString().toLowerCase().contains('diamond')) {
      animationPath = 'assets/animations/diamond.json';
    } else if (giftName.toString().toLowerCase().contains('rocket')) {
      animationPath = 'assets/animations/rocket.json';
    }

    final gift = _ActiveGift(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderName: data['fromUsername'] ?? 'Someone',
      giftIcon: data['giftIcon'] ?? 'Ã°Å¸Å½Â',
      giftName: giftName,
      animationPath: animationPath,
    );

    if (mounted) {
      // Sync haptics with animation peaks for premium gifts
      final isPremium = giftName.toString().toLowerCase().contains('diamond') ||
          giftName.toString().toLowerCase().contains('rocket');

      if (isPremium) {
        // Delay haptic to match Lottie animation build-up/peak
        final hapticTimer = Timer(const Duration(milliseconds: 800), () {
          if (mounted) HapticsUtil.giftReceived();
        });
        _timers.add(hapticTimer);
      } else {
        HapticsUtil.giftReceived();
      }

      setState(() {
        _activeGifts.add(gift);
        if (_activeGifts.length > _maxVisibleGifts) {
          _activeGifts.removeRange(0, _activeGifts.length - _maxVisibleGifts);
        }
      });
    }

    // Remove after animation finishes (5 seconds for Lottie)
    final removeTimer =
        Timer(Duration(milliseconds: animationPath != null ? 5000 : 3000), () {
      if (mounted) {
        setState(() {
          _activeGifts.removeWhere((g) => g.id == gift.id);
        });
      }
    });
    _timers.add(removeTimer);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          children: _activeGifts
              .map((gift) =>
                  _FloatingGiftWidget(key: ValueKey(gift.id), gift: gift))
              .toList(),
        ),
      ),
    );
  }
}

class _ActiveGift {
  final String id;
  final String senderName;
  final String giftIcon;
  final String giftName;
  final String? animationPath;

  _ActiveGift({
    required this.id,
    required this.senderName,
    required this.giftIcon,
    required this.giftName,
    this.animationPath,
  });
}

class _FloatingGiftWidget extends StatefulWidget {
  final _ActiveGift gift;

  const _FloatingGiftWidget({super.key, required this.gift});

  @override
  State<_FloatingGiftWidget> createState() => _FloatingGiftWidgetState();
}

class _FloatingGiftWidgetState extends State<_FloatingGiftWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // Slide up from bottom to center
    _slideAnimation = Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
      ),
    );

    // Scale up and down
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.2), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
    ]).animate(_controller);

    // Fade in and out
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_controller);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (widget.gift.animationPath != null) {
          return Center(
            child: Opacity(
              opacity: _opacityAnimation.value,
              child: Lottie.asset(
                widget.gift.animationPath!,
                width: 300,
                height: 300,
                fit: BoxFit.contain,
              ),
            ),
          );
        }

        return Align(
          alignment: Alignment(0, _slideAnimation.value * 2 - 1),
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.blue.shade900.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.gift.giftIcon,
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.gift.senderName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'sent ${widget.gift.giftName}',
                          style: TextStyle(
                            color: Colors.blue.shade200,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
