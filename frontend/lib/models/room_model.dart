import 'mini_draw_model.dart';
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
  final bool allowAdminSeatControl;
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
    required this.allowAdminSeatControl,
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
      allowAdminSeatControl: json['allowAdminSeatControl'] ?? true,
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
    bool? allowAdminSeatControl,
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
      allowAdminSeatControl:
          allowAdminSeatControl ?? this.allowAdminSeatControl,
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
  final bool isPresent;
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
    this.isPresent = true,
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
      isPresent: json['isPresent'] is bool ? json['isPresent'] as bool : true,
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
    bool? isPresent,
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
      isPresent: isPresent ?? this.isPresent,
      isOnline: isOnline ?? this.isOnline,
      contribution: contribution ?? this.contribution,
      raisedHand: raisedHand ?? this.raisedHand,
    );
  }
}

class RoomSeatState {
  final int seatIndex;
  final String? occupiedByUserId;
  final bool isLocked;
  final String? lockedByUserId;
  final DateTime? lockedAt;
  final String lockReason;
  final String seatType;
  final DateTime? updatedAt;

  const RoomSeatState({
    required this.seatIndex,
    this.occupiedByUserId,
    this.isLocked = false,
    this.lockedByUserId,
    this.lockedAt,
    this.lockReason = '',
    this.seatType = 'speaker',
    this.updatedAt,
  });

  factory RoomSeatState.fromJson(Map<String, dynamic> json) {
    return RoomSeatState(
      seatIndex: json['seatIndex'] is int
          ? json['seatIndex'] as int
          : int.tryParse('${json['seatIndex']}') ?? 0,
      occupiedByUserId: json['occupiedByUserId']?.toString(),
      isLocked: json['isLocked'] == true,
      lockedByUserId: json['lockedByUserId']?.toString(),
      lockedAt: json['lockedAt'] != null
          ? DateTime.tryParse(json['lockedAt'].toString())
          : null,
      lockReason: json['lockReason']?.toString() ?? '',
      seatType: json['seatType']?.toString() ?? 'speaker',
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }

  RoomSeatState copyWith({
    String? occupiedByUserId,
    bool? isLocked,
    String? lockedByUserId,
    DateTime? lockedAt,
    String? lockReason,
    String? seatType,
    DateTime? updatedAt,
  }) {
    return RoomSeatState(
      seatIndex: seatIndex,
      occupiedByUserId: occupiedByUserId ?? this.occupiedByUserId,
      isLocked: isLocked ?? this.isLocked,
      lockedByUserId: lockedByUserId ?? this.lockedByUserId,
      lockedAt: lockedAt ?? this.lockedAt,
      lockReason: lockReason ?? this.lockReason,
      seatType: seatType ?? this.seatType,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isOccupied =>
      occupiedByUserId != null && occupiedByUserId!.isNotEmpty;
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
  final String topic;
  final String language;
  final String roomRules;
  final String type;
  final String mode;
  final String category;
  final List<String> tags;

  final String ownerId;
  final String hostId;
  final String hostName;
  final String hostAvatar;
  final int hostLevel;
  final bool isPermanent;

  final RoomSettings settings;

  final int participantCount;
  final int onlineCount;
  final List<Participant> participants;
  final List<RoomSeatState> seatStates;
  final List<int> lockedSeats;
  final List<String> followerIds;
  final List<String> coHostIds;
  final List<String> moderatorIds;
  final bool hostPresent;
  final int adminCount;
  final int activeControllersCount;
  final bool roomActive;
  final DateTime? inactiveSince;

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
  final String? youtubeActiveVideoId;
  final int youtubeSessionVersion;
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
  final Map<String, bool> capabilities;
  final Map<String, dynamic> roomSettingsSnapshot;
  final MiniDrawSessionSummary miniDraw;

  RoomModel({
    required this.id,
    required this.roomId,
    required this.name,
    required this.description,
    this.topic = '',
    this.language = 'en',
    this.roomRules = '',
    required this.type,
    this.mode = 'normal',
    required this.category,
    required this.tags,
    this.ownerId = '',
    required this.hostId,
    required this.hostName,
    required this.hostAvatar,
    required this.hostLevel,
    this.isPermanent = false,
    required this.settings,
    required this.participantCount,
    required this.onlineCount,
    required this.participants,
    this.seatStates = const [],
    required this.lockedSeats,
    required this.followerIds,
    required this.coHostIds,
    required this.moderatorIds,
    this.hostPresent = false,
    this.adminCount = 0,
    this.activeControllersCount = 0,
    this.roomActive = true,
    this.inactiveSince,
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
    this.youtubeActiveVideoId,
    this.youtubeSessionVersion = 0,
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
    this.capabilities = const {},
    this.roomSettingsSnapshot = const {},
    this.miniDraw = const MiniDrawSessionSummary(),
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
    final capabilitiesMap = json['capabilities'] is Map<String, dynamic>
        ? (json['capabilities'] as Map<String, dynamic>)
            .map((key, value) => MapEntry(key, value == true))
        : <String, bool>{};
    final roomSettingsSnapshot = json['roomSettings'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(
            json['roomSettings'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final miniDrawSummary = json['miniDraw'] is Map<String, dynamic>
        ? MiniDrawSessionSummary.fromJson(
            json['miniDraw'] as Map<String, dynamic>,
          )
        : json['miniDraw'] is Map
            ? MiniDrawSessionSummary.fromJson(
                Map<String, dynamic>.from(json['miniDraw'] as Map),
              )
            : roomSettingsSnapshot['miniDraw'] is Map<String, dynamic>
                ? MiniDrawSessionSummary.fromJson(
                    roomSettingsSnapshot['miniDraw'] as Map<String, dynamic>,
                  )
                : roomSettingsSnapshot['miniDraw'] is Map
                    ? MiniDrawSessionSummary.fromJson(
                        Map<String, dynamic>.from(
                          roomSettingsSnapshot['miniDraw'] as Map,
                        ),
                      )
                    : const MiniDrawSessionSummary();
    final rawLockedSeats = json['lockedSeats'] is List
        ? (json['lockedSeats'] as List)
            .map((seat) => seat is int ? seat : int.tryParse('$seat'))
            .whereType<int>()
            .toList()
        : const <int>[];
    final roomSettingsSeatItems =
        roomSettingsSnapshot['seats'] is Map<String, dynamic>
            ? (roomSettingsSnapshot['seats'] as Map<String, dynamic>)['items']
            : null;
    final seatStates = _parseSeatStates(
      json['seatStates'] ?? roomSettingsSeatItems,
      participantsList,
      rawLockedSeats,
    );
    final lockedSeats = seatStates.isNotEmpty
        ? seatStates
            .where((seatState) => seatState.isLocked)
            .map((seatState) => seatState.seatIndex)
            .toList()
        : rawLockedSeats;
    final rallyExpiresAt = json['rallyExpiresAt'] != null
        ? DateTime.tryParse(json['rallyExpiresAt'].toString())
        : null;
    final isRallyActive = json['rallyActive'] == true ||
        (rallyExpiresAt != null && rallyExpiresAt.isAfter(DateTime.now()));
    final controllerState =
        roomSettingsSnapshot['controllerState'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(
                roomSettingsSnapshot['controllerState'] as Map<String, dynamic>,
              )
            : <String, dynamic>{};

    return RoomModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      roomId: json['roomId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed Room',
      description: json['description']?.toString() ?? '',
      topic: json['topic']?.toString() ?? '',
      language: json['language']?.toString() ??
          roomSettingsSnapshot['roomConfig']?['language']?.toString() ??
          'en',
      roomRules: json['roomRules']?.toString() ??
          roomSettingsSnapshot['roomConfig']?['roomRules']?.toString() ??
          '',
      type: json['type']?.toString() ?? 'voice',
      mode: json['mode']?.toString() ??
          (json['type']?.toString() == 'auction'
              ? 'auction'
              : json['type']?.toString() == 'chat'
                  ? 'acquaint'
                  : 'normal'),
      category: json['category']?.toString() ?? 'all',
      tags: json['tags'] is List ? List<String>.from(json['tags']) : [],
      ownerId: json['ownerId'] is Map<String, dynamic>
          ? (json['ownerId']['_id']?.toString() ??
              json['ownerId']['id']?.toString() ??
              '')
          : json['ownerId']?.toString() ?? '',
      hostId: hostUser?.id ?? (hostJson is String ? hostJson : ''),
      hostName: hostUser?.username ?? json['hostName']?.toString() ?? 'Unknown',
      hostAvatar: hostUser?.avatar ?? json['hostAvatar']?.toString() ?? '',
      hostLevel: hostUser?.level ?? json['hostLevel'] ?? 1,
      isPermanent: json['isPermanent'] == true ||
          roomSettingsSnapshot['roomConfig']?['isPermanent'] == true,
      settings: RoomSettings.fromJson(settingsMap),
      participantCount: json['participantCount'] ?? participantsList.length,
      onlineCount: json['onlineCount'] ?? 0,
      participants: participantsList,
      seatStates: seatStates,
      lockedSeats: lockedSeats,
      followerIds: _parseIdList(json['followers']),
      coHostIds: _parseIdList(json['coHosts']),
      moderatorIds: _parseIdList(json['moderators']),
      hostPresent:
          json['hostPresent'] == true || controllerState['hostPresent'] == true,
      adminCount: json['adminCount'] is int
          ? json['adminCount'] as int
          : int.tryParse('${json['adminCount']}') ??
              (controllerState['adminCount'] is int
                  ? controllerState['adminCount'] as int
                  : int.tryParse('${controllerState['adminCount']}') ?? 0),
      activeControllersCount: json['activeControllersCount'] is int
          ? json['activeControllersCount'] as int
          : int.tryParse('${json['activeControllersCount']}') ??
              (controllerState['activeControllersCount'] is int
                  ? controllerState['activeControllersCount'] as int
                  : int.tryParse(
                          '${controllerState['activeControllersCount']}') ??
                      0),
      roomActive: json['roomActive'] is bool
          ? json['roomActive'] as bool
          : controllerState['roomActive'] is bool
              ? controllerState['roomActive'] as bool
              : true,
      inactiveSince: json['inactiveSince'] != null
          ? DateTime.tryParse(json['inactiveSince'].toString())
          : controllerState['inactiveSince'] != null
              ? DateTime.tryParse(controllerState['inactiveSince'].toString())
              : null,
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
      youtubeActiveVideoId: themeMap['youtubeActiveVideoId']?.toString(),
      youtubeSessionVersion: themeMap['youtubeSessionVersion'] is int
          ? themeMap['youtubeSessionVersion'] as int
          : int.tryParse('${themeMap['youtubeSessionVersion']}') ?? 0,
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
      capabilities: capabilitiesMap,
      roomSettingsSnapshot: roomSettingsSnapshot,
      miniDraw: miniDrawSummary,
    );
  }

  RoomModel copyWith({
    String? name,
    String? description,
    String? topic,
    String? language,
    String? roomRules,
    String? type,
    String? mode,
    String? category,
    List<String>? tags,
    String? ownerId,
    String? hostId,
    String? hostName,
    String? hostAvatar,
    int? hostLevel,
    bool? isPermanent,
    int? onlineCount,
    int? participantCount,
    List<Participant>? participants,
    List<RoomSeatState>? seatStates,
    List<int>? lockedSeats,
    List<String>? followerIds,
    List<String>? coHostIds,
    List<String>? moderatorIds,
    bool? hostPresent,
    int? adminCount,
    int? activeControllersCount,
    bool? roomActive,
    DateTime? inactiveSince,
    int? level,
    int? exp,
    int? expToday,
    String? region,
    int? followers,
    int? totalEarned,
    int? fans,
    String? announcement,
    RoomSettings? settings,
    String? background,
    String? coverImage,
    String? youtubeUrl,
    String? youtubeTitle,
    String? youtubeThumbnail,
    List<RoomYoutubeQueueItem>? youtubeQueue,
    String? youtubeActiveVideoId,
    int? youtubeSessionVersion,
    int? youtubePositionMs,
    String? youtubePlaybackState,
    DateTime? youtubeSyncedAt,
    String? musicUrl,
    String? musicTitle,
    bool? musicLoop,
    bool? isVipRoom,
    bool? isRallyActive,
    DateTime? rallyExpiresAt,
    DateTime? createdAt,
    DateTime? endedAt,
    Map<String, bool>? capabilities,
    Map<String, dynamic>? roomSettingsSnapshot,
    MiniDrawSessionSummary? miniDraw,
  }) {
    final nextSeatStates = seatStates ?? this.seatStates;
    final nextLockedSeats = lockedSeats ??
        (seatStates != null
            ? nextSeatStates
                .where((seatState) => seatState.isLocked)
                .map((seatState) => seatState.seatIndex)
                .toList()
            : this.lockedSeats);
    return RoomModel(
      id: id,
      roomId: roomId,
      name: name ?? this.name,
      description: description ?? this.description,
      topic: topic ?? this.topic,
      language: language ?? this.language,
      roomRules: roomRules ?? this.roomRules,
      type: type ?? this.type,
      mode: mode ?? this.mode,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      ownerId: ownerId ?? this.ownerId,
      hostId: hostId ?? this.hostId,
      hostName: hostName ?? this.hostName,
      hostAvatar: hostAvatar ?? this.hostAvatar,
      hostLevel: hostLevel ?? this.hostLevel,
      isPermanent: isPermanent ?? this.isPermanent,
      settings: settings ?? this.settings,
      participantCount: participantCount ?? this.participantCount,
      onlineCount: onlineCount ?? this.onlineCount,
      participants: participants ?? this.participants,
      seatStates: nextSeatStates,
      lockedSeats: nextLockedSeats,
      followerIds: followerIds ?? this.followerIds,
      coHostIds: coHostIds ?? this.coHostIds,
      moderatorIds: moderatorIds ?? this.moderatorIds,
      hostPresent: hostPresent ?? this.hostPresent,
      adminCount: adminCount ?? this.adminCount,
      activeControllersCount:
          activeControllersCount ?? this.activeControllersCount,
      roomActive: roomActive ?? this.roomActive,
      inactiveSince: inactiveSince ?? this.inactiveSince,
      level: level ?? this.level,
      exp: exp ?? this.exp,
      expToday: expToday ?? this.expToday,
      region: region ?? this.region,
      followers: followers ?? this.followers,
      totalEarned: totalEarned ?? this.totalEarned,
      background: background ?? this.background,
      coverImage: coverImage ?? this.coverImage,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      youtubeTitle: youtubeTitle ?? this.youtubeTitle,
      youtubeThumbnail: youtubeThumbnail ?? this.youtubeThumbnail,
      youtubeQueue: youtubeQueue ?? this.youtubeQueue,
      youtubeActiveVideoId: youtubeActiveVideoId ?? this.youtubeActiveVideoId,
      youtubeSessionVersion:
          youtubeSessionVersion ?? this.youtubeSessionVersion,
      youtubePositionMs: youtubePositionMs ?? this.youtubePositionMs,
      youtubePlaybackState: youtubePlaybackState ?? this.youtubePlaybackState,
      youtubeSyncedAt: youtubeSyncedAt ?? this.youtubeSyncedAt,
      musicUrl: musicUrl ?? this.musicUrl,
      musicTitle: musicTitle ?? this.musicTitle,
      musicLoop: musicLoop ?? this.musicLoop,
      announcement: announcement ?? this.announcement,
      fans: fans ?? this.fans,
      isVipRoom: isVipRoom ?? this.isVipRoom,
      isRallyActive: isRallyActive ?? this.isRallyActive,
      rallyExpiresAt: rallyExpiresAt ?? this.rallyExpiresAt,
      createdAt: createdAt ?? this.createdAt,
      endedAt: endedAt ?? this.endedAt,
      capabilities: capabilities ?? this.capabilities,
      roomSettingsSnapshot: roomSettingsSnapshot ?? this.roomSettingsSnapshot,
      miniDraw: miniDraw ?? this.miniDraw,
    );
  }

  bool isUserInRoom(String userId) {
    return participants.any((p) => p.userId == userId && p.isPresent);
  }

  bool hasParticipantRecord(String userId) {
    return participants.any((p) => p.userId == userId);
  }

  bool isOwnedBy(String userId) {
    final effectiveOwnerId = ownerId.isNotEmpty ? ownerId : hostId;
    return effectiveOwnerId == userId;
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

  RoomSeatState? seatStateFor(int seatIndex) {
    for (final seatState in seatStates) {
      if (seatState.seatIndex == seatIndex) {
        return seatState;
      }
    }
    if (seatIndex < 1) return null;
    String? occupiedByUserId;
    for (final participant in participants) {
      if (participant.seatIndex == seatIndex) {
        occupiedByUserId = participant.userId;
        break;
      }
    }
    return RoomSeatState(
      seatIndex: seatIndex,
      occupiedByUserId: occupiedByUserId,
      isLocked: lockedSeats.contains(seatIndex),
      seatType: 'speaker',
    );
  }

  bool isLockedSeat(int seatIndex) {
    return seatStateFor(seatIndex)?.isLocked == true;
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
  bool get allowAdminSeatControl => settings.allowAdminSeatControl;
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

  static List<RoomSeatState> _parseSeatStates(
    dynamic value,
    List<Participant> participants,
    List<int> fallbackLockedSeats,
  ) {
    final parsed = <RoomSeatState>[];
    if (value is List) {
      for (final entry in value) {
        if (entry is Map<String, dynamic>) {
          parsed.add(RoomSeatState.fromJson(entry));
        } else if (entry is Map) {
          parsed.add(RoomSeatState.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }
    if (parsed.isNotEmpty) {
      parsed.sort((left, right) => left.seatIndex.compareTo(right.seatIndex));
      return parsed;
    }

    return List<RoomSeatState>.generate(8, (index) {
      final seatIndex = index + 1;
      String? occupiedByUserId;
      for (final participant in participants) {
        if (participant.seatIndex == seatIndex) {
          occupiedByUserId = participant.userId;
          break;
        }
      }
      return RoomSeatState(
        seatIndex: seatIndex,
        occupiedByUserId: occupiedByUserId,
        isLocked: fallbackLockedSeats.contains(seatIndex),
        seatType: 'speaker',
      );
    });
  }
}
