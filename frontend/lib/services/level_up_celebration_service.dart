import 'dart:async';

import '../models/level_progress_model.dart';

class LevelUpCelebration {
  final int previousLevel;
  final int newLevel;
  final int xpGained;
  final String source;
  final LevelBadgeTier previousTier;
  final LevelBadgeTier newTier;
  final bool milestoneTierChanged;
  final LevelProgressSnapshot levelInfo;
  final String id;

  const LevelUpCelebration({
    required this.previousLevel,
    required this.newLevel,
    required this.xpGained,
    required this.source,
    required this.previousTier,
    required this.newTier,
    required this.milestoneTierChanged,
    required this.levelInfo,
    required this.id,
  });

  factory LevelUpCelebration.fromJson(Map<String, dynamic> json) {
    final levelInfo = LevelProgressSnapshot.maybeFrom(json['levelInfo']) ??
        LevelProgressSnapshot.fromLevel(
          level: _toInt(json['newLevel']) ?? 1,
          xp: _toInt(json['xp']) ?? 0,
          levelMilestoneTier: json['newTier']?.toString(),
        );

    return LevelUpCelebration(
      previousLevel: _toInt(json['previousLevel']) ?? 1,
      newLevel: _toInt(json['newLevel']) ?? levelInfo.level,
      xpGained: _toInt(json['xpGained']) ?? 0,
      source: json['source']?.toString() ?? 'progress',
      previousTier: LevelBadgeTier.fromKey(json['previousTier']?.toString()),
      newTier: LevelBadgeTier.fromKey(json['newTier']?.toString()),
      milestoneTierChanged: json['milestoneTierChanged'] == true,
      levelInfo: levelInfo,
      id: [
        _toInt(json['newLevel']) ?? levelInfo.level,
        _toInt(json['xp']) ?? levelInfo.xp,
        DateTime.now().microsecondsSinceEpoch,
      ].join('-'),
    );
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

class LevelUpCelebrationService {
  LevelUpCelebrationService._();

  static final StreamController<LevelUpCelebration?> _controller =
      StreamController<LevelUpCelebration?>.broadcast();

  static Stream<LevelUpCelebration?> get stream => _controller.stream;

  static Timer? _dismissTimer;
  static LevelUpCelebration? _current;

  static void showFromPayload(Map<String, dynamic> payload) {
    final celebration = LevelUpCelebration.fromJson(payload);
    _current = celebration;
    _controller.add(celebration);
    _dismissTimer?.cancel();
    _dismissTimer = Timer(
      Duration(seconds: celebration.milestoneTierChanged ? 5 : 4),
      () => dismiss(celebration.id),
    );
  }

  static void dismiss([String? id]) {
    if (id != null && _current?.id != id) {
      return;
    }
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _current = null;
    _controller.add(null);
  }
}
