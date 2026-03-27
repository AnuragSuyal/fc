class StatsModel {
  final int level;
  final int xp;
  final int nextLevelXp;
  final double xpProgress;
  final int coins;
  final int gems;
  final int tickets;
  final int vipLevel;
  final int loginStreak;
  final int longestStreak;
  final Map<String, dynamic>? gameStats;

  StatsModel({
    required this.level,
    required this.xp,
    required this.nextLevelXp,
    required this.xpProgress,
    required this.coins,
    required this.gems,
    required this.tickets,
    required this.vipLevel,
    required this.loginStreak,
    required this.longestStreak,
    this.gameStats,
  });

  factory StatsModel.fromJson(Map<String, dynamic> json) {
    return StatsModel(
      level: json['level'] ?? 1,
      xp: json['xp'] ?? 0,
      nextLevelXp: json['nextLevelXp'] ?? 1000,
      xpProgress: (json['xpProgress'] ?? 0).toDouble(),
      coins: json['coins'] ?? 0,
      gems: json['gems'] ?? 0,
      tickets: json['tickets'] ?? 0,
      vipLevel: json['vipLevel'] ?? 0,
      loginStreak: json['loginStreak'] ?? 0,
      longestStreak: json['longestStreak'] ?? 0,
      gameStats: json['stats'],
    );
  }
}






