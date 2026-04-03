enum LevelBadgeTier {
  defaultTier,
  parrotGreen,
  blue,
  yellow,
  darkRed;

  static LevelBadgeTier fromKey(String? key) {
    switch ((key ?? '').trim().toLowerCase()) {
      case 'parrot_green':
        return LevelBadgeTier.parrotGreen;
      case 'blue':
        return LevelBadgeTier.blue;
      case 'yellow':
        return LevelBadgeTier.yellow;
      case 'dark_red':
        return LevelBadgeTier.darkRed;
      default:
        return LevelBadgeTier.defaultTier;
    }
  }

  String get key {
    switch (this) {
      case LevelBadgeTier.parrotGreen:
        return 'parrot_green';
      case LevelBadgeTier.blue:
        return 'blue';
      case LevelBadgeTier.yellow:
        return 'yellow';
      case LevelBadgeTier.darkRed:
        return 'dark_red';
      case LevelBadgeTier.defaultTier:
        return 'default';
    }
  }
}

class LevelProgressSnapshot {
  static const int _fallbackXpScale = 60;

  final int level;
  final int xp;
  final int currentLevelXp;
  final int? nextLevelXp;
  final int xpIntoLevel;
  final int xpToNextLevel;
  final double progress;
  final double progressPercent;
  final LevelBadgeTier milestoneTier;
  final int milestoneStartLevel;
  final int? nextMilestoneLevel;
  final DateTime? lastLevelUpdatedAt;

  const LevelProgressSnapshot({
    required this.level,
    required this.xp,
    required this.currentLevelXp,
    required this.nextLevelXp,
    required this.xpIntoLevel,
    required this.xpToNextLevel,
    required this.progress,
    required this.progressPercent,
    required this.milestoneTier,
    required this.milestoneStartLevel,
    required this.nextMilestoneLevel,
    this.lastLevelUpdatedAt,
  });

  factory LevelProgressSnapshot.fromJson(Map<String, dynamic> json) {
    final level = _asInt(json['level']) ?? 1;
    final xp = _asInt(json['xp']) ?? 0;
    final currentLevelXp = _asInt(json['currentLevelXp']) ?? _xpForLevel(level);
    final nextLevelXp = _asInt(json['nextLevelXp']);
    final xpIntoLevel = _asInt(json['xpIntoLevel']) ?? (xp - currentLevelXp);
    final xpToNextLevel = _asInt(json['xpToNextLevel']) ??
        (nextLevelXp == null ? 0 : (nextLevelXp - xp));
    final progress = _asDouble(json['progress']) ??
        _asDouble(json['xpProgress']) ??
        _derivedProgress(
          level: level,
          xp: xp,
          currentLevelXp: currentLevelXp,
          nextLevelXp: nextLevelXp,
        );
    final progressPercent =
        _asDouble(json['progressPercent']) ?? (progress * 100);

    return LevelProgressSnapshot(
      level: level,
      xp: xp,
      currentLevelXp: currentLevelXp,
      nextLevelXp: nextLevelXp,
      xpIntoLevel: _clampInt(xpIntoLevel, 0, 1 << 31),
      xpToNextLevel: _clampInt(xpToNextLevel, 0, 1 << 31),
      progress: _clampDouble(progress, 0.0, 1.0),
      progressPercent: _clampDouble(progressPercent, 0.0, 100.0),
      milestoneTier: LevelBadgeTier.fromKey(
        json['milestoneTier']?.toString() ??
            json['levelMilestoneTier']?.toString(),
      ),
      milestoneStartLevel:
          _asInt(json['milestoneStartLevel']) ?? _resolveMilestoneStart(level),
      nextMilestoneLevel:
          _asInt(json['nextMilestoneLevel']) ?? _resolveNextMilestone(level),
      lastLevelUpdatedAt: json['lastLevelUpdatedAt'] != null
          ? DateTime.tryParse(json['lastLevelUpdatedAt'].toString())
          : null,
    );
  }

  factory LevelProgressSnapshot.fromLevel({
    required int level,
    required int xp,
    String? levelMilestoneTier,
    DateTime? lastLevelUpdatedAt,
  }) {
    final safeLevel = level < 1 ? 1 : level;
    final safeXp = xp < 0 ? 0 : xp;
    final currentLevelXp = _xpForLevel(safeLevel);
    final nextLevelXp = _xpForLevel(safeLevel + 1);
    final xpIntoLevel = _clampInt(safeXp - currentLevelXp, 0, 1 << 31);
    final xpToNextLevel = _clampInt(nextLevelXp - safeXp, 0, 1 << 31);
    final denominator = _clampInt(nextLevelXp - currentLevelXp, 1, 1 << 31);
    final progress = _clampDouble(xpIntoLevel / denominator, 0.0, 1.0);

    return LevelProgressSnapshot(
      level: safeLevel,
      xp: safeXp,
      currentLevelXp: currentLevelXp,
      nextLevelXp: nextLevelXp,
      xpIntoLevel: xpIntoLevel,
      xpToNextLevel: xpToNextLevel,
      progress: progress,
      progressPercent: progress * 100,
      milestoneTier:
          levelMilestoneTier == null || levelMilestoneTier.trim().isEmpty
              ? _resolveTier(safeLevel)
              : LevelBadgeTier.fromKey(levelMilestoneTier),
      milestoneStartLevel: _resolveMilestoneStart(safeLevel),
      nextMilestoneLevel: _resolveNextMilestone(safeLevel),
      lastLevelUpdatedAt: lastLevelUpdatedAt,
    );
  }

  static LevelProgressSnapshot? maybeFrom(dynamic value) {
    if (value is Map<String, dynamic>) {
      return LevelProgressSnapshot.fromJson(value);
    }
    if (value is Map) {
      return LevelProgressSnapshot.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  static LevelProgressSnapshot fromRoot(Map<String, dynamic> json) {
    final nested = maybeFrom(json['levelInfo']);
    if (nested != null) return nested;

    return LevelProgressSnapshot.fromLevel(
      level: _asInt(json['level']) ?? 1,
      xp: _asInt(json['xp']) ?? 0,
      levelMilestoneTier: json['levelMilestoneTier']?.toString(),
      lastLevelUpdatedAt: json['lastLevelUpdatedAt'] != null
          ? DateTime.tryParse(json['lastLevelUpdatedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'level': level,
        'xp': xp,
        'currentLevelXp': currentLevelXp,
        'nextLevelXp': nextLevelXp,
        'xpIntoLevel': xpIntoLevel,
        'xpToNextLevel': xpToNextLevel,
        'progress': progress,
        'progressPercent': progressPercent,
        'milestoneTier': milestoneTier.key,
        'milestoneStartLevel': milestoneStartLevel,
        'nextMilestoneLevel': nextMilestoneLevel,
        'lastLevelUpdatedAt': lastLevelUpdatedAt?.toIso8601String(),
      };

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int _xpForLevel(int level) {
    final safeLevel = level < 1 ? 1 : level;
    return (safeLevel - 1) * (safeLevel - 1) * _fallbackXpScale;
  }

  static int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static double _clampDouble(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static double _derivedProgress({
    required int level,
    required int xp,
    int? currentLevelXp,
    int? nextLevelXp,
  }) {
    final floorXp = currentLevelXp ?? _xpForLevel(level);
    final ceilingXp = nextLevelXp ?? _xpForLevel(level + 1);
    final span = _clampInt(ceilingXp - floorXp, 1, 1 << 31);
    return _clampDouble((xp - floorXp) / span, 0.0, 1.0);
  }

  static LevelBadgeTier _resolveTier(int level) {
    if (level >= 100) return LevelBadgeTier.darkRed;
    if (level >= 80) return LevelBadgeTier.yellow;
    if (level >= 40) return LevelBadgeTier.blue;
    if (level >= 20) return LevelBadgeTier.parrotGreen;
    return LevelBadgeTier.defaultTier;
  }

  static int _resolveMilestoneStart(int level) {
    if (level >= 100) return 100;
    if (level >= 80) return 80;
    if (level >= 40) return 40;
    if (level >= 20) return 20;
    return 1;
  }

  static int? _resolveNextMilestone(int level) {
    if (level >= 100) return null;
    if (level >= 80) return 100;
    if (level >= 40) return 80;
    if (level >= 20) return 40;
    return 20;
  }
}
