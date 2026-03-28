class GroupUserModel {
  final String id;
  final String username;
  final String avatar;
  final int level;
  final int vipLevel;
  final String uid;
  final bool isOnline;

  const GroupUserModel({
    required this.id,
    required this.username,
    required this.avatar,
    required this.level,
    required this.vipLevel,
    required this.uid,
    required this.isOnline,
  });

  factory GroupUserModel.fromJson(dynamic raw) {
    if (raw is! Map) {
      return const GroupUserModel(
        id: '',
        username: 'Unknown',
        avatar: '',
        level: 1,
        vipLevel: 0,
        uid: '',
        isOnline: false,
      );
    }

    final json = Map<String, dynamic>.from(raw);
    final status = json['status'];
    return GroupUserModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? 'Unknown',
      avatar: json['avatar']?.toString() ?? '',
      level: (json['level'] as num?)?.toInt() ?? 1,
      vipLevel: (json['vipLevel'] as num?)?.toInt() ?? 0,
      uid: json['uid']?.toString() ?? '',
      isOnline: status is Map ? status['isOnline'] == true : false,
    );
  }
}

class GroupMemberModel {
  final GroupUserModel user;
  final String role;
  final DateTime? joinedAt;

  const GroupMemberModel({
    required this.user,
    required this.role,
    required this.joinedAt,
  });

  factory GroupMemberModel.fromJson(dynamic raw) {
    if (raw is! Map) {
      return GroupMemberModel(
        user: GroupUserModel.fromJson(null),
        role: 'member',
        joinedAt: null,
      );
    }

    final json = Map<String, dynamic>.from(raw);
    return GroupMemberModel(
      user: GroupUserModel.fromJson(json['userId']),
      role: json['role']?.toString() ?? 'member',
      joinedAt: json['joinedAt'] is String
          ? DateTime.tryParse(json['joinedAt'].toString())
          : null,
    );
  }
}

class GroupInviteModel {
  final GroupUserModel user;
  final GroupUserModel? invitedBy;
  final String status;
  final DateTime? invitedAt;

  const GroupInviteModel({
    required this.user,
    required this.invitedBy,
    required this.status,
    required this.invitedAt,
  });

  factory GroupInviteModel.fromJson(dynamic raw) {
    if (raw is! Map) {
      return GroupInviteModel(
        user: GroupUserModel.fromJson(null),
        invitedBy: null,
        status: 'pending',
        invitedAt: null,
      );
    }

    final json = Map<String, dynamic>.from(raw);
    return GroupInviteModel(
      user: GroupUserModel.fromJson(json['userId']),
      invitedBy: json['invitedBy'] != null
          ? GroupUserModel.fromJson(json['invitedBy'])
          : null,
      status: json['status']?.toString() ?? 'pending',
      invitedAt: json['invitedAt'] is String
          ? DateTime.tryParse(json['invitedAt'].toString())
          : null,
    );
  }
}

class GroupJoinRequestModel {
  final GroupUserModel user;
  final String message;
  final DateTime? requestedAt;

  const GroupJoinRequestModel({
    required this.user,
    required this.message,
    required this.requestedAt,
  });

  factory GroupJoinRequestModel.fromJson(dynamic raw) {
    if (raw is! Map) {
      return GroupJoinRequestModel(
        user: GroupUserModel.fromJson(null),
        message: '',
        requestedAt: null,
      );
    }

    final json = Map<String, dynamic>.from(raw);
    return GroupJoinRequestModel(
      user: GroupUserModel.fromJson(json['userId']),
      message: json['message']?.toString() ?? '',
      requestedAt: json['requestedAt'] is String
          ? DateTime.tryParse(json['requestedAt'].toString())
          : null,
    );
  }
}

class GroupVoiceRoomModel {
  final String id;
  final String roomId;
  final String name;
  final String type;
  final int participantCount;
  final int onlineCount;
  final String coverImage;
  final Map<String, dynamic> settings;

  const GroupVoiceRoomModel({
    required this.id,
    required this.roomId,
    required this.name,
    required this.type,
    required this.participantCount,
    required this.onlineCount,
    required this.coverImage,
    required this.settings,
  });

  factory GroupVoiceRoomModel.fromJson(dynamic raw) {
    if (raw is! Map) {
      return const GroupVoiceRoomModel(
        id: '',
        roomId: '',
        name: 'Voice Lounge',
        type: 'voice',
        participantCount: 0,
        onlineCount: 0,
        coverImage: '',
        settings: <String, dynamic>{},
      );
    }

    final json = Map<String, dynamic>.from(raw);
    return GroupVoiceRoomModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      roomId: json['roomId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Voice Lounge',
      type: json['type']?.toString() ?? 'voice',
      participantCount: (json['participantCount'] as num?)?.toInt() ?? 0,
      onlineCount: (json['onlineCount'] as num?)?.toInt() ?? 0,
      coverImage: json['coverImage']?.toString() ?? '',
      settings: json['settings'] is Map
          ? Map<String, dynamic>.from(json['settings'])
          : const <String, dynamic>{},
    );
  }
}

class GroupModel {
  final String id;
  final String name;
  final String tag;
  final String description;
  final String motto;
  final String vibe;
  final String announcement;
  final String leaderId;
  final String leaderName;
  final String leaderAvatar;
  final List<GroupUserModel> admins;
  final List<GroupMemberModel> members;
  final List<GroupInviteModel> invitations;
  final List<GroupJoinRequestModel> joinRequests;
  final int memberCount;
  final int maxMembers;
  final String type;
  final Map<String, dynamic> stats;
  final int coins;
  final bool hasTreasure;
  final List<dynamic> store;
  final String avatar;
  final String coverImage;
  final bool isPublic;
  final bool approvalRequired;
  final bool isMember;
  final bool isInvited;
  final bool hasPendingJoinRequest;
  final String viewerRole;
  final Map<String, dynamic> permissions;
  final int onlineMembers;
  final GroupVoiceRoomModel? linkedVoiceRoom;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastActivityAt;

  const GroupModel({
    required this.id,
    required this.name,
    required this.tag,
    required this.description,
    required this.motto,
    required this.vibe,
    required this.announcement,
    required this.leaderId,
    required this.leaderName,
    required this.leaderAvatar,
    required this.admins,
    required this.members,
    required this.invitations,
    required this.joinRequests,
    required this.memberCount,
    required this.maxMembers,
    required this.type,
    required this.stats,
    required this.coins,
    required this.hasTreasure,
    required this.store,
    required this.avatar,
    required this.coverImage,
    required this.isPublic,
    required this.approvalRequired,
    required this.isMember,
    required this.isInvited,
    required this.hasPendingJoinRequest,
    required this.viewerRole,
    required this.permissions,
    required this.onlineMembers,
    required this.linkedVoiceRoom,
    required this.createdAt,
    required this.updatedAt,
    required this.lastActivityAt,
  });

  bool get isLeader => viewerRole == 'leader';
  bool get isAdmin => isLeader || viewerRole == 'admin';

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    final leader = GroupUserModel.fromJson(json['leaderId']);
    final members = (json['members'] as List? ?? const [])
        .map(GroupMemberModel.fromJson)
        .toList(growable: false);

    return GroupModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      tag: json['tag']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      motto: json['motto']?.toString() ?? '',
      vibe: json['vibe']?.toString() ?? 'Orbit',
      announcement: json['announcement']?.toString() ?? '',
      leaderId: leader.id,
      leaderName: leader.username,
      leaderAvatar: leader.avatar,
      admins: (json['admins'] as List? ?? const [])
          .map(GroupUserModel.fromJson)
          .toList(growable: false),
      members: members,
      invitations: (json['invitations'] as List? ?? const [])
          .map(GroupInviteModel.fromJson)
          .toList(growable: false),
      joinRequests: (json['joinRequests'] as List? ?? const [])
          .map(GroupJoinRequestModel.fromJson)
          .toList(growable: false),
      memberCount: (json['memberCount'] as num?)?.toInt() ?? members.length,
      maxMembers: (json['maxMembers'] as num?)?.toInt() ?? 50,
      type: json['type']?.toString() ?? 'small',
      stats: json['stats'] is Map
          ? Map<String, dynamic>.from(json['stats'])
          : <String, dynamic>{},
      coins: (json['coins'] as num?)?.toInt() ?? 0,
      hasTreasure: json['hasTreasure'] == true ||
          (json['treasureChest'] is Map &&
              json['treasureChest']['available'] == true),
      store:
          json['store'] is List ? List<dynamic>.from(json['store']) : const [],
      avatar: json['avatar']?.toString() ?? '',
      coverImage: json['coverImage']?.toString() ?? '',
      isPublic: json['isPublic'] != false,
      approvalRequired: json['approvalRequired'] == true,
      isMember: json['isMember'] == true,
      isInvited: json['isInvited'] == true,
      hasPendingJoinRequest: json['hasPendingJoinRequest'] == true,
      viewerRole: json['viewerRole']?.toString() ?? 'guest',
      permissions: json['permissions'] is Map
          ? Map<String, dynamic>.from(json['permissions'])
          : const <String, dynamic>{},
      onlineMembers: (json['onlineMembers'] as num?)?.toInt() ??
          members.where((member) => member.user.isOnline).length,
      linkedVoiceRoom: json['linkedVoiceRoom'] != null
          ? GroupVoiceRoomModel.fromJson(json['linkedVoiceRoom'])
          : (json['linkedRoomId'] is Map
              ? GroupVoiceRoomModel.fromJson(json['linkedRoomId'])
              : null),
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] is String
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      lastActivityAt: json['lastActivityAt'] is String
          ? DateTime.tryParse(json['lastActivityAt'].toString())
          : null,
    );
  }
}
