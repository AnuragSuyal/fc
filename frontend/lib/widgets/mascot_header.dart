import 'package:flutter/material.dart';

class MascotHeader extends StatelessWidget {
  const MascotHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFF8B72),
                  Color(0xFFFFC963),
                  Color(0xFF7AD5FF),
                ],
              ),
            ),
          ),
          Positioned(
            top: 24,
            left: 28,
            child: _badge('chat', const Color(0xFFFFFFFF)),
          ),
          Positioned(
            top: 40,
            right: 24,
            child: _badge('play', const Color(0xFFFFF2B0)),
          ),
          Positioned(
            bottom: 24,
            left: 36,
            child: _badge('laugh', const Color(0xFFDDF8F0)),
          ),
          Align(
            alignment: const Alignment(0, 0.18),
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.28),
              ),
              padding: const EdgeInsets.all(14),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFF6EF), Color(0xFFFFFFFF)],
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 46,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _eye(),
                          const SizedBox(width: 28),
                          _eye(),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 38,
                      child: Container(
                        width: 62,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2D2147),
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(32),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Original Friend Circle party vibe',
                style: TextStyle(
                  color: Color(0xCC2D2147),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF2D2147),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _eye() {
    return Container(
      width: 20,
      height: 24,
      decoration: const BoxDecoration(
        color: Color(0xFF2D2147),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
    );
  }
}
