import 'package:flutter/material.dart';

import 'seat_lock_badge.dart';

class RoomSeatTile extends StatelessWidget {
  const RoomSeatTile({
    super.key,
    required this.seatIndex,
    this.isLocked = false,
    this.isClosedByLimit = false,
    this.isInactive = false,
    this.hasOccupant = false,
    this.canManageLock = false,
    this.showLabel = true,
    this.onTapSeat,
    this.onToggleLock,
    this.child,
  });

  final int seatIndex;
  final bool isLocked;
  final bool isClosedByLimit;
  final bool isInactive;
  final bool hasOccupant;
  final bool canManageLock;
  final bool showLabel;
  final VoidCallback? onTapSeat;
  final VoidCallback? onToggleLock;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final disabled = isLocked || isClosedByLimit || isInactive;
    final label = isInactive
        ? 'Inactive'
        : isClosedByLimit
        ? 'Closed'
        : isLocked
            ? 'Locked'
            : 'Seat $seatIndex';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: disabled ? null : onTapSeat,
              child: child == null
                  ? _buildEmptySeat(disabled: disabled)
                  : Opacity(
                      opacity: isInactive ? 0.5 : 1,
                      child: child!,
                    ),
            ),
            if (canManageLock && onToggleLock != null)
              Positioned(
                top: -6,
                right: -6,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: Key('room-seat-lock-control-$seatIndex'),
                    onTap: onToggleLock,
                    borderRadius: BorderRadius.circular(999),
                    child: Ink(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF0E1326).withValues(alpha: 0.94),
                        border: Border.all(
                          color: isLocked
                              ? const Color(0xFFFFD451).withValues(alpha: 0.46)
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: isLocked
                          ? const SeatLockBadge(
                              size: 16,
                              backgroundColor: Color(0x00000000),
                              showGlow: false,
                            )
                          : Icon(
                              Icons.lock_outline_rounded,
                              size: 15,
                              color: hasOccupant
                                  ? Colors.white38
                                  : const Color(0xFFFFD451),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (showLabel) ...[
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isLocked
                  ? const Color(0xFFFFD451)
                  : isInactive
                      ? Colors.white30
                  : isClosedByLimit
                      ? Colors.white38
                      : Colors.white24,
              fontSize: 10,
              fontWeight: isLocked ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptySeat({required bool disabled}) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isInactive
            ? Colors.white.withValues(alpha: 0.04)
            : isLocked
            ? const Color(0xFF172241).withValues(alpha: 0.84)
            : Colors.white.withValues(alpha: 0.03),
        border: Border.all(
          color: isInactive
              ? Colors.white12
              : isLocked
              ? const Color(0xFFFFD451).withValues(alpha: 0.36)
              : Colors.white10,
          width: 1.4,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!isLocked && !isInactive)
            CustomPaint(
              size: const Size(56, 56),
              painter: _DottedCirclePainter(color: Colors.white24),
            ),
          if (isLocked)
            SeatLockBadge(
              key: Key('room-seat-locked-badge-$seatIndex'),
              size: 28,
            )
          else if (isInactive)
            Icon(
              Icons.pause_circle_outline_rounded,
              color: Colors.white38,
              size: 22,
            )
          else
            Icon(
              Icons.add_rounded,
              color: disabled ? Colors.white38 : Colors.white24,
              size: 20,
            ),
        ],
      ),
    );
  }
}

class _DottedCirclePainter extends CustomPainter {
  _DottedCirclePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    const dashCount = 18;
    final radius = (size.width / 2) - 4;
    final center = Offset(size.width / 2, size.height / 2);

    for (var index = 0; index < dashCount; index++) {
      final startAngle = (index / dashCount) * 2 * 3.141592653589793;
      const dashSweep = 0.18;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DottedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}
