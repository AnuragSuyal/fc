class PostModel {
  final String id;
  final String userId;
  final String username;
  final String userAvatar;
  final int userLevel;

  final String content;
  final List<Map<String, dynamic>> images;
  final String type;

  final List<dynamic> likes;
  final int likeCount;
  final bool isLikedByUser;

  final List<dynamic> comments;
  final int commentCount;

  final List<dynamic> mentions;

  final int views;
  final bool isEdited;

  final DateTime createdAt;
  final DateTime updatedAt;

  PostModel({
    required this.id,
    required this.userId,
    required this.username,
    required this.userAvatar,
    required this.userLevel,
    required this.content,
    required this.images,
    required this.type,
    required this.likes,
    required this.likeCount,
    required this.isLikedByUser,
    required this.comments,
    required this.commentCount,
    required this.mentions,
    required this.views,
    required this.isEdited,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) {
    final user =
        json['userId'] is Map ? json['userId'] as Map<String, dynamic> : null;

    return PostModel(
      id: json['_id'] ?? '',
      userId: user?['_id']?.toString() ?? json['userId']?.toString() ?? '',
      username: user?['username'] ?? 'Unknown',
      userAvatar: user?['avatar'] ?? '',
      userLevel: user?['level'] ?? 1,
      content: json['content'] ?? '',
      images: List<Map<String, dynamic>>.from(json['images'] ?? []),
      type: json['type'] ?? 'normal',
      likes: json['likes'] ?? [],
      likeCount: json['likeCount'] ?? 0,
      isLikedByUser: json['isLikedByUser'] ?? false,
      comments: json['comments'] ?? [],
      commentCount: json['commentCount'] ?? 0,
      mentions: json['mentions'] ?? [],
      views: json['views'] ?? 0,
      isEdited: json['isEdited'] ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
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

class CommentModel {
  final String id;
  final String userId;
  final String username;
  final String userAvatar;
  final String content;
  final DateTime createdAt;

  CommentModel({
    required this.id,
    required this.userId,
    required this.username,
    required this.userAvatar,
    required this.content,
    required this.createdAt,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    final user =
        json['userId'] is Map ? json['userId'] as Map<String, dynamic> : null;

    return CommentModel(
      id: json['_id'] ?? '',
      userId: user?['_id']?.toString() ?? '',
      username: user?['username'] ?? 'Unknown',
      userAvatar: user?['avatar'] ?? '',
      content: json['content'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}






