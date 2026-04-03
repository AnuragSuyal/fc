import 'level_progress_model.dart';
import 'vip_model.dart';

class StatsModel {
  final int level;
  final int xp;
  final int nextLevelXp;
  final double xpProgress;
  final int coins;
  final int gems;
  final int tickets;
  final int vipLevel;
  final VipMembershipSnapshot vipMembership;
  final int loginStreak;
  final int longestStreak;
  final Map<String, dynamic>? gameStats;
  final LevelProgressSnapshot levelInfo;

  StatsModel({
    required this.level,
    required this.xp,
    required this.nextLevelXp,
    required this.xpProgress,
    required this.coins,
    required this.gems,
    required this.tickets,
    required this.vipLevel,
    required this.vipMembership,
    required this.loginStreak,
    required this.longestStreak,
    required this.levelInfo,
    this.gameStats,
  });

  factory StatsModel.fromJson(Map<String, dynamic> json) {
    final levelInfo = LevelProgressSnapshot.fromRoot(json);
    return StatsModel(
      level: levelInfo.level,
      xp: levelInfo.xp,
      nextLevelXp: levelInfo.nextLevelXp ?? 0,
      xpProgress: levelInfo.progress,
      coins: json['coins'] ?? 0,
      gems: json['gems'] ?? 0,
      tickets: json['tickets'] ?? 0,
      vipLevel: json['vipLevel'] ?? 0,
      vipMembership: VipMembershipSnapshot.fromJson(
        json['vipMembership'] is Map
            ? Map<String, dynamic>.from(json['vipMembership'] as Map)
            : null,
      ),
      loginStreak: json['loginStreak'] ?? 0,
      longestStreak: json['longestStreak'] ?? 0,
      levelInfo: levelInfo,
      gameStats: json['stats'],
    );
  }
}
