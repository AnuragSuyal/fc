import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../utils/haptics_util.dart';
import '../gift_image.dart';

class GiftAnimationOverlay extends StatefulWidget {
  final Stream<Map<String, dynamic>> giftStream;

  const GiftAnimationOverlay({
    super.key,
    required this.giftStream,
  });

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
    _subscription = widget.giftStream.listen(_addGift);
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
    final giftName = data['giftName']?.toString() ?? 'Gift';
    String? animationPath;

    final normalized = giftName.toLowerCase();
    if (normalized.contains('flame')) {
      animationPath = 'assets/animations/fire.json';
    } else if (normalized.contains('diamond')) {
      animationPath = 'assets/animations/diamond.json';
    } else if (normalized.contains('rocket')) {
      animationPath = 'assets/animations/rocket.json';
    }

    final gift = _ActiveGift(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderName: data['fromUsername']?.toString() ??
          data['sender']?['username']?.toString() ??
          'Someone',
      giftIcon: data['giftIcon']?.toString() ?? '',
      giftName: giftName,
      animationPath: animationPath,
    );

    if (!mounted) return;

    final isPremium = normalized.contains('diamond') ||
        normalized.contains('rocket') ||
        normalized.contains('royal') ||
        normalized.contains('celebration');

    if (isPremium) {
      final hapticTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) {
          HapticsUtil.giftReceived();
        }
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

    final removeTimer = Timer(
      Duration(milliseconds: animationPath != null ? 5000 : 3000),
      () {
        if (mounted) {
          setState(() {
            _activeGifts.removeWhere((entry) => entry.id == gift.id);
          });
        }
      },
    );
    _timers.add(removeTimer);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          children: _activeGifts
              .map((gift) => _FloatingGiftWidget(
                    key: ValueKey(gift.id),
                    gift: gift,
                  ))
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

  const _FloatingGiftWidget({
    super.key,
    required this.gift,
  });

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

    _slideAnimation = Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
      ),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.2), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
    ]).animate(_controller);

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
                    GiftImage(
                      source: widget.gift.giftIcon,
                      width: 36,
                      height: 36,
                      fallback: const Icon(
                        Icons.card_giftcard_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
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
