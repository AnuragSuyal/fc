import 'package:flutter/material.dart';

class GiftSheetTokens {
  static const Color overlay = Color(0x66000000);
  static const Color backdropTint = Color(0x40070910);
  static const Color sheetBackground = Color(0xE60A0A0E);
  static const Color sheetHighlight = Color(0xCC161924);
  static const Color panel = Color(0x66161A24);
  static const Color panelStrong = Color(0x8C171B26);
  static const Color border = Color(0x26FFFFFF);
  static const Color borderStrong = Color(0x40FFFFFF);
  static const Color primaryText = Color(0xFFF7F7FA);
  static const Color secondaryText = Color(0xFF9CA3B4);
  static const Color mutedText = Color(0xFF6C7284);
  static const Color gold = Color(0xFFFFD56A);
  static const Color goldDeep = Color(0xFFF0A826);
  static const Color cyan = Color(0xFF8FE3FF);
  static const Color cyanDeep = Color(0xFF3AA8FF);
  static const Color accent = Color(0xFFFF7CCB);
  static const Color success = Color(0xFF6BFFB3);
  static const Color danger = Color(0xFFFF8E88);

  static const LinearGradient sheetGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xF210121A),
      Color(0xF00A0A0E),
    ],
  );

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFE58B),
      Color(0xFFFFC341),
      Color(0xFFE49A1B),
    ],
  );

  static const LinearGradient cyanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFB7F0FF),
      Color(0xFF6CD9FF),
      Color(0xFF3B9BFF),
    ],
  );

  static const LinearGradient actionGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFFFFD772),
      Color(0xFFFF8A52),
      Color(0xFFFF5DA2),
    ],
  );

  static BoxDecoration glassPanel({
    double radius = 28,
    bool elevated = true,
    bool emphasized = false,
  }) {
    return BoxDecoration(
      gradient: emphasized ? null : sheetGradient,
      color: emphasized ? panelStrong : null,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: emphasized ? borderStrong : border,
        width: 1,
      ),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.34),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, -1),
              ),
            ]
          : const [],
    );
  }

  static BoxDecoration innerGlass({
    double radius = 22,
    bool selected = false,
    Color? tint,
  }) {
    final Color glow = tint ?? (selected ? gold : Colors.white);
    return BoxDecoration(
      color: selected ? panelStrong : panel,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: selected
            ? glow.withValues(alpha: 0.46)
            : border,
      ),
      boxShadow: selected
          ? [
              BoxShadow(
                color: glow.withValues(alpha: 0.22),
                blurRadius: 26,
                spreadRadius: 1,
              ),
            ]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
    );
  }
}
