import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/level_progress_model.dart';
import '../utils/level_badge_style.dart';

enum LevelBadgeSize { small, medium, large }

class LevelBadge extends StatelessWidget {
  final int level;
  final LevelProgressSnapshot? levelInfo;
  final LevelBadgeSize size;
  final bool showGlow;
  final bool includePrefix;

  const LevelBadge({
    super.key,
    required this.level,
    this.levelInfo,
    this.size = LevelBadgeSize.small,
    this.showGlow = true,
    this.includePrefix = true,
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = levelInfo ??
        LevelProgressSnapshot.fromLevel(
          level: level,
          xp: 0,
        );
    final style = resolveLevelBadgeStyle(snapshot.milestoneTier);
    final metrics = _metricsFor(size);

    return Semantics(
      label: 'Level $level badge',
      child: Container(
        constraints: BoxConstraints(
          minWidth: metrics.width,
          minHeight: metrics.height,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: metrics.horizontalPadding,
          vertical: metrics.verticalPadding,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(metrics.radius),
          image: DecorationImage(
            image: AssetImage(style.assetPath),
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          boxShadow: [
            if (showGlow)
              BoxShadow(
                color: style.glowColor.withValues(alpha: 0.34),
                blurRadius: metrics.glowBlur,
                spreadRadius: 0.6,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (size != LevelBadgeSize.small &&
                snapshot.milestoneTier != LevelBadgeTier.defaultTier) ...[
              Icon(
                Icons.auto_awesome_rounded,
                size: metrics.iconSize,
                color: style.accentColor,
              ),
              SizedBox(width: metrics.iconSpacing),
            ],
            Text(
              includePrefix ? 'LV $level' : '$level',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: GoogleFonts.orbitron(
                color: style.textColor,
                fontSize: metrics.fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: metrics.letterSpacing,
                shadows: const [
                  Shadow(
                    color: Color(0x7A000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _LevelBadgeMetrics _metricsFor(LevelBadgeSize size) {
    switch (size) {
      case LevelBadgeSize.large:
        return const _LevelBadgeMetrics(
          width: 130,
          height: 42,
          horizontalPadding: 16,
          verticalPadding: 8,
          radius: 20,
          fontSize: 15,
          letterSpacing: 1.0,
          glowBlur: 24,
          iconSize: 14,
          iconSpacing: 6,
        );
      case LevelBadgeSize.medium:
        return const _LevelBadgeMetrics(
          width: 92,
          height: 32,
          horizontalPadding: 12,
          verticalPadding: 6,
          radius: 16,
          fontSize: 11.5,
          letterSpacing: 0.8,
          glowBlur: 18,
          iconSize: 11,
          iconSpacing: 4,
        );
      case LevelBadgeSize.small:
        return const _LevelBadgeMetrics(
          width: 68,
          height: 24,
          horizontalPadding: 10,
          verticalPadding: 4,
          radius: 14,
          fontSize: 9.6,
          letterSpacing: 0.7,
          glowBlur: 12,
          iconSize: 0,
          iconSpacing: 0,
        );
    }
  }
}

class _LevelBadgeMetrics {
  final double width;
  final double height;
  final double horizontalPadding;
  final double verticalPadding;
  final double radius;
  final double fontSize;
  final double letterSpacing;
  final double glowBlur;
  final double iconSize;
  final double iconSpacing;

  const _LevelBadgeMetrics({
    required this.width,
    required this.height,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.radius,
    required this.fontSize,
    required this.letterSpacing,
    required this.glowBlur,
    required this.iconSize,
    required this.iconSpacing,
  });
}
