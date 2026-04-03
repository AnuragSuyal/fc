import 'package:flutter/material.dart';

import '../models/level_progress_model.dart';

class LevelBadgeStyle {
  final String assetPath;
  final Color textColor;
  final Color glowColor;
  final Color accentColor;

  const LevelBadgeStyle({
    required this.assetPath,
    required this.textColor,
    required this.glowColor,
    required this.accentColor,
  });
}

LevelBadgeStyle resolveLevelBadgeStyle(LevelBadgeTier tier) {
  switch (tier) {
    case LevelBadgeTier.parrotGreen:
      return const LevelBadgeStyle(
        assetPath: 'assets/images/level_badge_parrot_green.png',
        textColor: Color(0xFF173106),
        glowColor: Color(0xFFCBFF48),
        accentColor: Color(0xFFCBFF48),
      );
    case LevelBadgeTier.blue:
      return const LevelBadgeStyle(
        assetPath: 'assets/images/level_badge_blue.png',
        textColor: Colors.white,
        glowColor: Color(0xFF275CFF),
        accentColor: Color(0xFF6DA8FF),
      );
    case LevelBadgeTier.yellow:
      return const LevelBadgeStyle(
        assetPath: 'assets/images/level_badge_yellow.png',
        textColor: Color(0xFF261300),
        glowColor: Color(0xFFFFD155),
        accentColor: Color(0xFFFFD155),
      );
    case LevelBadgeTier.darkRed:
      return const LevelBadgeStyle(
        assetPath: 'assets/images/level_badge_dark_red.png',
        textColor: Colors.white,
        glowColor: Color(0xFFB3111D),
        accentColor: Color(0xFFFF7368),
      );
    case LevelBadgeTier.defaultTier:
      return const LevelBadgeStyle(
        assetPath: 'assets/images/level_badge_default.png',
        textColor: Colors.white,
        glowColor: Color(0xFF9DA7B5),
        accentColor: Color(0xFFFFD27A),
      );
  }
}
