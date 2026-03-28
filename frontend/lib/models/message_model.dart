class MessageModel {
  final String id;
  final String? roomId;
  final String? groupId;
  final String? recipientId;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String content;
  final String type;
  final Map<String, dynamic> metadata;
  final String? giftId;
  final String? giftAnimation;
  final List<dynamic> mentions;
  final List<Reaction> reactions;
  final MessageModel? replyTo;
  final bool isEdited;
  final bool isDeleted;
  final List<dynamic> readBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  MessageModel({
    required this.id,
    this.roomId,
    this.groupId,
    this.recipientId,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.content,
    required this.type,
    required this.metadata,
    this.giftId,
    this.giftAnimation,
    required this.mentions,
    required this.reactions,
    this.replyTo,
    required this.isEdited,
    required this.isDeleted,
    required this.readBy,
    required this.createdAt,
    required this.updatedAt,
  });

  MessageModel copyWith({
    String? id,
    String? roomId,
    String? groupId,
    String? recipientId,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    String? content,
    String? type,
    Map<String, dynamic>? metadata,
    String? giftId,
    String? giftAnimation,
    List<dynamic>? mentions,
    List<Reaction>? reactions,
    MessageModel? replyTo,
    bool? isEdited,
    bool? isDeleted,
    List<dynamic>? readBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MessageModel(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      groupId: groupId ?? this.groupId,
      recipientId: recipientId ?? this.recipientId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      content: content ?? this.content,
      type: type ?? this.type,
      metadata: metadata ?? this.metadata,
      giftId: giftId ?? this.giftId,
      giftAnimation: giftAnimation ?? this.giftAnimation,
      mentions: mentions ?? this.mentions,
      reactions: reactions ?? this.reactions,
      replyTo: replyTo ?? this.replyTo,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      readBy: readBy ?? this.readBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final sender = json['senderId'] is Map
        ? json['senderId'] as Map<String, dynamic>
        : null;
    final replyToJson =
        json['replyTo'] is Map ? json['replyTo'] as Map<String, dynamic> : null;

    return MessageModel(
      id: json['_id'] ?? '',
      roomId: json['roomId']?.toString(),
      groupId: json['groupId']?.toString(),
      recipientId: json['recipientId']?.toString(),
      senderId: sender?['_id'] ?? json['senderId'] ?? '',
      senderName: sender?['username'] ?? 'Unknown',
      senderAvatar: sender?['avatar'] ?? '',
      content: json['content'] ?? '',
      type: json['type'] ?? 'text',
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'])
          : {},
      giftId: json['giftId'],
      giftAnimation: json['giftAnimation'],
      mentions: json['mentions'] ?? [],
      reactions: (json['reactions'] as List? ?? [])
          .map((r) => Reaction.fromJson(r))
          .toList(),
      replyTo: replyToJson != null ? MessageModel.fromJson(replyToJson) : null,
      isEdited: json['isEdited'] ?? false,
      isDeleted: json['isDeleted'] ?? false,
      readBy: json['readBy'] ?? [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
  }

  bool get isFromMe => false; // Will be set by comparing with current user
  bool get isRead => readBy.isNotEmpty;
  bool get isImage => type == 'image' && !isPrivateImage;
  bool get isVoice => type == 'voice';
  bool get isEmoji => type == 'emoji';
  bool get isGift => type == 'gift';
  bool get isPrivateImage =>
      type == 'private_image' || (type == 'image' && metadata['privateImage'] == true);
  bool get isRoomInvite => metadata['roomInvite'] is Map;
  Map<String, dynamic> get roomInviteData => metadata['roomInvite'] is Map
      ? Map<String, dynamic>.from(metadata['roomInvite'] as Map)
      : const {};
  String? get giftName {
    final raw = metadata['giftName']?.toString().trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  String? get giftIcon {
    final raw = metadata['giftIcon']?.toString().trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  int get giftRecipientXpGained {
    final raw = metadata['recipientXpGained'] ?? metadata['xpGained'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  int get giftRecipientLevel {
    final raw = metadata['recipientLevel'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  bool get giftRecipientLeveledUp => metadata['recipientLeveledUp'] == true;

  String? get giftNote {
    final raw = metadata['giftNote']?.toString().trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  int get voiceDurationMs {
    final raw = metadata['durationMs'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  String? get roomInviteRoomId => roomInviteData['roomId']?.toString();
  String get roomInviteRoomName {
    final roomName = roomInviteData['roomName']?.toString();
    if (roomName != null && roomName.trim().isNotEmpty) {
      return roomName.trim();
    }
    return 'Voice Room';
  }

  String get previewText {
    if (isRoomInvite) return 'Room invite: $roomInviteRoomName';
    if (isGift) return giftName != null ? 'Gift: $giftName' : 'Gift';
    if (isEmoji) return 'Emote';
    if (isVoice) return 'Voice message';
    if (isPrivateImage) return 'Private photo';
    if (isImage) return 'Photo';
    return content;
  }

  int get ephemeralSeconds {
    final raw = metadata['ephemeralSeconds'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 5;
  }

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

class Reaction {
  final String userId;
  final String reaction;
  final DateTime createdAt;

  Reaction({
    required this.userId,
    required this.reaction,
    required this.createdAt,
  });

  factory Reaction.fromJson(Map<String, dynamic> json) {
    return Reaction(
      userId: json['userId'] ?? '',
      reaction: json['reaction'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

class ConversationModel {
  final String id;
  final Map<String, dynamic> user;
  final MessageModel lastMessage;
  final int unreadCount;

  ConversationModel({
    required this.id,
    required this.user,
    required this.lastMessage,
    required this.unreadCount,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['_id'] ?? '',
      user: json['user'] ?? {},
      lastMessage: MessageModel.fromJson(json['lastMessage']),
      unreadCount: json['unreadCount'] ?? 0,
    );
  }
}
