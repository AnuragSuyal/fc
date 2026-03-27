class QuestModel {
  final String questId;
  final String title;
  final String description;
  final String type; // 'daily', 'weekly'
  final int target;
  final int progress;
  final bool completed;
  final bool claimed;
  final Map<String, dynamic> reward;
  final DateTime expiresAt;
  final DateTime startedAt;
  final DateTime? completedAt;

  QuestModel({
    required this.questId,
    required this.title,
    required this.description,
    required this.type,
    required this.target,
    required this.progress,
    required this.completed,
    required this.claimed,
    required this.reward,
    required this.expiresAt,
    required this.startedAt,
    this.completedAt,
  });

  factory QuestModel.fromJson(Map<String, dynamic> json) {
    return QuestModel(
      questId: json['questId'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      type: json['type'] ?? 'daily',
      target: json['target'] ?? 1,
      progress: json['progress'] ?? 0,
      completed: json['completed'] ?? false,
      claimed: json['claimed'] ?? false,
      reward: json['reward'] ?? {},
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt']) ??
              DateTime.now().add(const Duration(days: 1))
          : DateTime.now().add(const Duration(days: 1)),
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt']) ?? DateTime.now()
          : DateTime.now(),
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'])
          : null,
    );
  }

  double get progressPercentage {
    if (target == 0) return 0;
    return (progress / target).clamp(0.0, 1.0);
  }

  bool get isExpired {
    return expiresAt.isBefore(DateTime.now());
  }

  bool get canClaim => completed && !claimed && !isExpired;

  Map<String, dynamic> toJson() {
    return {
      'questId': questId,
      'title': title,
      'description': description,
      'type': type,
      'target': target,
      'progress': progress,
      'completed': completed,
      'claimed': claimed,
      'reward': reward,
      'expiresAt': expiresAt.toIso8601String(),
      'startedAt': startedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }
}






