import 'user_model.dart';

class RoomSettings {
  final bool isPrivate;
  final int maxParticipants;
  final int entryFee;
  final bool hdVoice;
  final bool banTextChat;
  final bool banPhotoChat;
  final bool banRedPacket;
  final bool allowGifts;
  final bool stageJoinsLocked;
  final int maxActiveSpeakers;
  final bool requireApproval;

  RoomSettings({
    required this.isPrivate,
    required this.maxParticipants,
    required this.entryFee,
    required this.hdVoice,
    required this.banTextChat,
    required this.banPhotoChat,
    required this.banRedPacket,
    required this.allowGifts,
    required this.stageJoinsLocked,
    required this.maxActiveSpeakers,
    required this.requireApproval,
  });

  factory RoomSettings.fromJson(Map<String, dynamic> json) {
    return RoomSettings(
      isPrivate: json['isPrivate'] ?? false,
      maxParticipants: json['maxParticipants'] ?? 20,
      entryFee: json['entryFee'] ?? 0,
      hdVoice: json['hdVoice'] ?? false,
      banTextChat: json['banTextChat'] ?? false,
      banPhotoChat: json['banPhotoChat'] ?? false,
      banRedPacket: json['banRedPacket'] ?? false,
      allowGifts: json['allowGifts'] ?? true,
      stageJoinsLocked: json['stageJoinsLocked'] ?? false,
      maxActiveSpeakers: json['maxActiveSpeakers'] ?? 8,
      requireApproval: json['requireApproval'] ?? false,
    );
  }

  RoomSettings copyWith({
    bool? isPrivate,
    int? maxParticipants,
    int? entryFee,
    bool? hdVoice,
    bool? banTextChat,
    bool? banPhotoChat,
    bool? banRedPacket,
    bool? allowGifts,
    bool? stageJoinsLocked,
    int? maxActiveSpeakers,
    bool? requireApproval,
  }) {
    return RoomSettings(
      isPrivate: isPrivate ?? this.isPrivate,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      entryFee: entryFee ?? this.entryFee,
      hdVoice: hdVoice ?? this.hdVoice,
      banTextChat: banTextChat ?? this.banTextChat,
      banPhotoChat: banPhotoChat ?? this.banPhotoChat,
      banRedPacket: banRedPacket ?? this.banRedPacket,
      allowGifts: allowGifts ?? this.allowGifts,
      stageJoinsLocked: stageJoinsLocked ?? this.stageJoinsLocked,
      maxActiveSpeakers: maxActiveSpeakers ?? this.maxActiveSpeakers,
      requireApproval: requireApproval ?? this.requireApproval,
    );
  }
}

class Participant {
  final UserModel? user;
  final String userId;
  final String username;
  final String avatar;
  final int level;
  final int vipLevel;
  final String role;
  final int seatIndex;
  final bool isMuted;
  final bool isSpeaking;
  final bool isOnline;
  final int contribution;
  final bool raisedHand;

  Participant({
    this.user,
    required this.userId,
    required this.username,
    required this.avatar,
    required this.level,
    required this.vipLevel,
    required this.role,
    this.seatIndex = -1,
    this.isMuted = false,
    this.isSpeaking = false,
    this.isOnline = false,
    this.contribution = 0,
    this.raisedHand = false,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    final userJson = json['userId'] ?? json['user'];
    UserModel? user;
    if (userJson is Map<String, dynamic>) {
      user = UserModel.fromJson(userJson);
    }

    return Participant(
      user: user,
      userId: user?.id ?? (json['userId'] is String ? json['userId'] : ''),
      username: user?.username ?? json['username'] ?? 'User',
      avatar: user?.avatar ?? json['avatar'] ?? '',
      level: user?.level ?? json['level'] ?? 1,
      vipLevel: user?.vipLevel ?? json['vipLevel'] ?? 0,
      role: json['role'] ?? 'listener',
      seatIndex: json['seatIndex'] ?? -1,
      isMuted: json['isMuted'] ?? false,
      isSpeaking: json['isSpeaking'] ?? false,
      isOnline: user?.isOnline ?? json['isOnline'] == true,
      contribution: json['contribution'] ?? 0,
      raisedHand: json['raisedHand'] ?? false,
    );
  }

  Participant copyWith({
    UserModel? user,
    String? userId,
    String? username,
    String? avatar,
    int? level,
    int? vipLevel,
    String? role,
    int? seatIndex,
    bool? isMuted,
    bool? isSpeaking,
    bool? isOnline,
    int? contribution,
    bool? raisedHand,
  }) {
    return Participant(
      user: user ?? this.user,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      avatar: avatar ?? this.avatar,
      level: level ?? this.level,
      vipLevel: vipLevel ?? this.vipLevel,
      role: role ?? this.role,
      seatIndex: seatIndex ?? this.seatIndex,
      isMuted: isMuted ?? this.isMuted,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isOnline: isOnline ?? this.isOnline,
      contribution: contribution ?? this.contribution,
      raisedHand: raisedHand ?? this.raisedHand,
    );
  }
}

class RoomYoutubeQueueItem {
  final String videoId;
  final String url;
  final String title;
  final String thumbnailUrl;
  final int durationMs;
  final String addedBy;
  final DateTime? addedAt;

  const RoomYoutubeQueueItem({
    required this.videoId,
    required this.url,
    required this.title,
    required this.thumbnailUrl,
    this.durationMs = 0,
    this.addedBy = '',
    this.addedAt,
  });

  factory RoomYoutubeQueueItem.fromJson(Map<String, dynamic> json) {
    return RoomYoutubeQueueItem(
      videoId: json['videoId']?.toString() ?? '',
      url: json['url']?.toString() ?? json['youtubeUrl']?.toString() ?? '',
      title:
          json['title']?.toString() ?? json['youtubeTitle']?.toString() ?? '',
      thumbnailUrl: json['thumbnailUrl']?.toString() ??
          json['youtubeThumbnail']?.toString() ??
          '',
      durationMs: json['durationMs'] is int
          ? json['durationMs'] as int
          : int.tryParse('${json['durationMs']}') ?? 0,
      addedBy: json['addedBy']?.toString() ?? '',
      addedAt: json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toThemeJson() {
    return {
      'videoId': videoId,
      'url': url,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
      'durationMs': durationMs,
      'addedBy': addedBy,
      if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
    };
  }
}

class RoomModel {
  final String id;
  final String roomId;
  final String name;
  final String description;
  final String type;
  final String category;
  final List<String> tags;

  final String hostId;
  final String hostName;
  final String hostAvatar;
  final int hostLevel;

  final RoomSettings settings;

  final int participantCount;
  final int onlineCount;
  final List<Participant> participants;
  final List<int> lockedSeats;
  final List<String> followerIds;
  final List<String> coHostIds;
  final List<String> moderatorIds;

  final int level;
  final int exp;
  final int expToday;
  final String region;
  final int followers;

  final int totalEarned;

  final String background;
  final String? coverImage;
  final String? youtubeUrl;
  final String? youtubeTitle;
  final String? youtubeThumbnail;
  final List<RoomYoutubeQueueItem> youtubeQueue;
  final int youtubePositionMs;
  final String youtubePlaybackState;
  final DateTime? youtubeSyncedAt;
  final String? musicUrl;
  final String? musicTitle;
  final bool musicLoop;
  final String announcement;
  final int fans;
  final bool isVipRoom;
  final bool isRallyActive;
  final DateTime? rallyExpiresAt;

  final DateTime createdAt;
  final DateTime? endedAt;

  RoomModel({
    required this.id,
    required this.roomId,
    required this.name,
    required this.description,
    required this.type,
    required this.category,
    required this.tags,
    required this.hostId,
    required this.hostName,
    required this.hostAvatar,
    required this.hostLevel,
    required this.settings,
    required this.participantCount,
    required this.onlineCount,
    required this.participants,
    required this.lockedSeats,
    required this.followerIds,
    required this.coHostIds,
    required this.moderatorIds,
    required this.level,
    required this.exp,
    required this.expToday,
    required this.region,
    required this.followers,
    required this.totalEarned,
    required this.background,
    this.coverImage,
    this.youtubeUrl,
    this.youtubeTitle,
    this.youtubeThumbnail,
    this.youtubeQueue = const [],
    this.youtubePositionMs = 0,
    this.youtubePlaybackState = 'paused',
    this.youtubeSyncedAt,
    this.musicUrl,
    this.musicTitle,
    this.musicLoop = false,
    required this.announcement,
    required this.fans,
    this.isVipRoom = false,
    this.isRallyActive = false,
    this.rallyExpiresAt,
    required this.createdAt,
    this.endedAt,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    final hostJson = json['hostId'];
    UserModel? hostUser;
    if (hostJson is Map<String, dynamic>) {
      hostUser = UserModel.fromJson(hostJson);
    }

    final participantsList = <Participant>[];
    if (json['participants'] is List) {
      for (final participant in (json['participants'] as List)) {
        if (participant is Map<String, dynamic>) {
          participantsList.add(Participant.fromJson(participant));
        }
      }
    }

    final settingsMap = json['settings'] is Map<String, dynamic>
        ? json['settings'] as Map<String, dynamic>
        : <String, dynamic>{};
    final themeMap = json['theme'] is Map<String, dynamic>
        ? json['theme'] as Map<String, dynamic>
        : <String, dynamic>{};

    final announcementValue = json['announcement'];
    final rallyExpiresAt = json['rallyExpiresAt'] != null
        ? DateTime.tryParse(json['rallyExpiresAt'].toString())
        : null;
    final isRallyActive = json['rallyActive'] == true ||
        (rallyExpiresAt != null && rallyExpiresAt.isAfter(DateTime.now()));

    return RoomModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      roomId: json['roomId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed Room',
      description: json['description']?.toString() ?? '',
      type: json['type']?.toString() ?? 'voice',
      category: json['category']?.toString() ?? 'all',
      tags: json['tags'] is List ? List<String>.from(json['tags']) : [],
      hostId: hostUser?.id ?? (hostJson is String ? hostJson : ''),
      hostName: hostUser?.username ?? json['hostName']?.toString() ?? 'Unknown',
      hostAvatar: hostUser?.avatar ?? json['hostAvatar']?.toString() ?? '',
      hostLevel: hostUser?.level ?? json['hostLevel'] ?? 1,
      settings: RoomSettings.fromJson(settingsMap),
      participantCount: json['participantCount'] ?? participantsList.length,
      onlineCount: json['onlineCount'] ?? 0,
      participants: participantsList,
      lockedSeats: json['lockedSeats'] is List
          ? (json['lockedSeats'] as List)
              .map((seat) => seat is int ? seat : int.tryParse('$seat'))
              .whereType<int>()
              .toList()
          : const [],
      followerIds: _parseIdList(json['followers']),
      coHostIds: _parseIdList(json['coHosts']),
      moderatorIds: _parseIdList(json['moderators']),
      level: json['level'] ?? 1,
      exp: json['exp'] ?? 0,
      expToday: json['expToday'] ?? 0,
      region: json['region']?.toString() ?? 'Global',
      followers: json['metrics']?['followers'] ?? 0,
      totalEarned: json['economy']?['totalEarned'] ?? 0,
      background: themeMap['background']?.toString() ?? 'default',
      coverImage: themeMap['coverImage']?.toString(),
      youtubeUrl: themeMap['youtubeUrl']?.toString(),
      youtubeTitle: themeMap['youtubeTitle']?.toString(),
      youtubeThumbnail: themeMap['youtubeThumbnail']?.toString(),
      youtubeQueue: themeMap['youtubeQueue'] is List
          ? (themeMap['youtubeQueue'] as List)
              .whereType<Map>()
              .map(
                (entry) => RoomYoutubeQueueItem.fromJson(
                  Map<String, dynamic>.from(entry),
                ),
              )
              .where((entry) => entry.url.isNotEmpty)
              .toList()
          : const [],
      youtubePositionMs: themeMap['youtubePositionMs'] is int
          ? themeMap['youtubePositionMs'] as int
          : int.tryParse('${themeMap['youtubePositionMs']}') ?? 0,
      youtubePlaybackState:
          themeMap['youtubePlaybackState']?.toString() ?? 'paused',
      youtubeSyncedAt: themeMap['youtubeSyncedAt'] != null
          ? DateTime.tryParse(themeMap['youtubeSyncedAt'].toString())
          : null,
      musicUrl: themeMap['music']?.toString(),
      musicTitle: themeMap['musicTitle']?.toString(),
      musicLoop: themeMap['musicLoop'] == true,
      announcement: announcementValue is Map
          ? (announcementValue['text']?.toString() ?? '')
          : (announcementValue?.toString() ?? ''),
      fans: json['metrics']?['followers'] ?? 0,
      isVipRoom: json['featured'] ?? false,
      isRallyActive: isRallyActive,
      rallyExpiresAt: rallyExpiresAt,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now(),
      endedAt: json['endedAt'] != null
          ? DateTime.parse(json['endedAt'].toString())
          : null,
    );
  }

  RoomModel copyWith({
    String? name,
    String? category,
    int? onlineCount,
    int? participantCount,
    List<Participant>? participants,
    List<int>? lockedSeats,
    List<String>? followerIds,
    int? followers,
    int? fans,
    String? announcement,
    RoomSettings? settings,
    String? background,
    String? coverImage,
    String? youtubeUrl,
    String? youtubeTitle,
    String? youtubeThumbnail,
    List<RoomYoutubeQueueItem>? youtubeQueue,
    int? youtubePositionMs,
    String? youtubePlaybackState,
    DateTime? youtubeSyncedAt,
    String? musicUrl,
    String? musicTitle,
    bool? musicLoop,
    bool? isRallyActive,
    DateTime? rallyExpiresAt,
  }) {
    return RoomModel(
      id: id,
      roomId: roomId,
      name: name ?? this.name,
      description: description,
      type: type,
      category: category ?? this.category,
      tags: tags,
      hostId: hostId,
      hostName: hostName,
      hostAvatar: hostAvatar,
      hostLevel: hostLevel,
      settings: settings ?? this.settings,
      participantCount: participantCount ?? this.participantCount,
      onlineCount: onlineCount ?? this.onlineCount,
      participants: participants ?? this.participants,
      lockedSeats: lockedSeats ?? this.lockedSeats,
      followerIds: followerIds ?? this.followerIds,
      coHostIds: coHostIds,
      moderatorIds: moderatorIds,
      level: level,
      exp: exp,
      expToday: expToday,
      region: region,
      followers: followers ?? this.followers,
      totalEarned: totalEarned,
      background: background ?? this.background,
      coverImage: coverImage ?? this.coverImage,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      youtubeTitle: youtubeTitle ?? this.youtubeTitle,
      youtubeThumbnail: youtubeThumbnail ?? this.youtubeThumbnail,
      youtubeQueue: youtubeQueue ?? this.youtubeQueue,
      youtubePositionMs: youtubePositionMs ?? this.youtubePositionMs,
      youtubePlaybackState: youtubePlaybackState ?? this.youtubePlaybackState,
      youtubeSyncedAt: youtubeSyncedAt ?? this.youtubeSyncedAt,
      musicUrl: musicUrl ?? this.musicUrl,
      musicTitle: musicTitle ?? this.musicTitle,
      musicLoop: musicLoop ?? this.musicLoop,
      announcement: announcement ?? this.announcement,
      fans: fans ?? this.fans,
      isVipRoom: isVipRoom,
      isRallyActive: isRallyActive ?? this.isRallyActive,
      rallyExpiresAt: rallyExpiresAt ?? this.rallyExpiresAt,
      createdAt: createdAt,
      endedAt: endedAt,
    );
  }

  bool isUserInRoom(String userId) {
    return participants.any((p) => p.userId == userId);
  }

  String? getUserRole(String userId) {
    try {
      return participants.firstWhere((p) => p.userId == userId).role;
    } catch (_) {
      return null;
    }
  }

  bool isFollowedBy(String userId) {
    return followerIds.contains(userId);
  }

  bool isLockedSeat(int seatIndex) {
    return lockedSeats.contains(seatIndex);
  }

  bool get isPrivate => settings.isPrivate;
  int get maxParticipants => settings.maxParticipants;
  int get entryFee => settings.entryFee;
  bool get hdVoice => settings.hdVoice;
  bool get banTextChat => settings.banTextChat;
  bool get banPhotoChat => settings.banPhotoChat;
  bool get banRedPacket => settings.banRedPacket;
  bool get allowGifts => settings.allowGifts;
  bool get stageJoinsLocked => settings.stageJoinsLocked;
  int get maxActiveSpeakers => settings.maxActiveSpeakers;
  bool get requireApproval => settings.requireApproval;
  bool get isYoutubePlaying => youtubePlaybackState == 'playing';
  RoomYoutubeQueueItem? get currentYoutubeQueueItem =>
      youtubeQueue.isEmpty ? null : youtubeQueue.first;
  int get maxAdminSlots => level >= 4 ? 5 : 4;
  int? get nextAdminUnlockLevel => level >= 4 ? null : 4;

  static List<String> _parseIdList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((entry) {
          if (entry is Map<String, dynamic>) {
            return entry['_id']?.toString() ?? entry['id']?.toString() ?? '';
          }
          return entry?.toString() ?? '';
        })
        .where((id) => id.isNotEmpty)
        .toList();
  }
}
