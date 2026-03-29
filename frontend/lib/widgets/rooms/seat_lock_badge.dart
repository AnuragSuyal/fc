import 'package:flutter/material.dart';

class SeatLockBadge extends StatelessWidget {
  const SeatLockBadge({
    super.key,
    this.size = 26,
    this.backgroundColor = const Color(0xFF131A33),
    this.showGlow = true,
  });

  final double size;
  final Color backgroundColor;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor.withValues(alpha: 0.92),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: const Color(0xFFFFD451).withValues(alpha: 0.28),
                  blurRadius: size * 0.55,
                  spreadRadius: size * 0.04,
                ),
              ]
            : const [],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.16),
        child: Image.asset(
          'assets/images/room_seat_lock.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.lock_rounded,
            size: size * 0.78,
            color: const Color(0xFFFFD451),
          ),
        ),
      ),
    );
  }
}
