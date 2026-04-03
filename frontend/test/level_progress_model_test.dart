import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/level_progress_model.dart';

void main() {
  test('level snapshot resolves milestone colors from backend payload', () {
    final snapshot = LevelProgressSnapshot.fromRoot({
      'level': 45,
      'xp': 117000,
      'levelInfo': {
        'level': 45,
        'xp': 117000,
        'currentLevelXp': 116160,
        'nextLevelXp': 121500,
        'xpIntoLevel': 840,
        'xpToNextLevel': 4500,
        'progress': 0.1573,
        'progressPercent': 15.73,
        'milestoneTier': 'blue',
        'milestoneStartLevel': 40,
        'nextMilestoneLevel': 80,
      },
    });

    expect(snapshot.level, 45);
    expect(snapshot.milestoneTier, LevelBadgeTier.blue);
    expect(snapshot.milestoneStartLevel, 40);
    expect(snapshot.nextMilestoneLevel, 80);
    expect(snapshot.progress, closeTo(0.1573, 0.0001));
  });

  test('fallback level snapshot maps milestone thresholds correctly', () {
    final green = LevelProgressSnapshot.fromRoot({'level': 20, 'xp': 21660});
    final yellow = LevelProgressSnapshot.fromRoot({'level': 85, 'xp': 433500});
    final red = LevelProgressSnapshot.fromRoot({'level': 120, 'xp': 849660});

    expect(green.milestoneTier, LevelBadgeTier.parrotGreen);
    expect(yellow.milestoneTier, LevelBadgeTier.yellow);
    expect(red.milestoneTier, LevelBadgeTier.darkRed);
  });
}
