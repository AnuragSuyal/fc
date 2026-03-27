class GroupModel {
  final String id;
  final String name;
  final String tag;
  final String description;
  final String motto;
  final String leaderId;
  final String leaderName;
  final String leaderAvatar;
  final List<dynamic> admins;
  final int memberCount;
  final int maxMembers;
  final String type; // small, large, epic
  final Map<String, dynamic> stats;
  final int coins;
  final bool hasTreasure;
  final List<dynamic> store;
  final String avatar;
  final bool isPublic;
  final List<dynamic> members;
  final DateTime createdAt;

  GroupModel({
    required this.id,
    required this.name,
    required this.tag,
    required this.description,
    required this.motto,
    required this.leaderId,
    required this.leaderName,
    required this.leaderAvatar,
    required this.admins,
    required this.members,
    required this.memberCount,
    required this.maxMembers,
    required this.type,
    required this.stats,
    required this.coins,
    required this.hasTreasure,
    required this.store,
    required this.avatar,
    required this.isPublic,
    required this.createdAt,
  });

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    final leader = json['leaderId'] is Map
        ? json['leaderId'] as Map<String, dynamic>
        : null;

    return GroupModel(
      id: json['_id'] ?? '',
      name: json['name'] ?? '',
      tag: json['tag'] ?? '',
      description: json['description'] ?? '',
      motto: json['motto'] ?? '',
      leaderId: leader?['_id'] ?? json['leaderId'] ?? '',
      leaderName: leader?['username'] ?? 'Unknown',
      leaderAvatar: leader?['avatar'] ?? '',
      admins: json['admins'] ?? [],
      members: json['members'] ?? [],
      memberCount: json['memberCount'] ?? 0,
      maxMembers: json['maxMembers'] ?? 50,
      type: json['type'] ?? 'small',
      stats: json['stats'] ?? {},
      coins: json['coins'] ?? 0,
      hasTreasure: json['treasureChest']?['available'] ?? false,
      store: json['store'] ?? [],
      avatar: json['avatar'] ?? '',
      isPublic: json['isPublic'] ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}






