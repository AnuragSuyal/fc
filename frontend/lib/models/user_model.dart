import 'package:flutter/material.dart';

class UserModel {
  final String id;
  final String uid;
  final String username;
  final String? email;
  final String avatar;
  final String? coverPhoto;
  final String? bio;
  final String region;
  final int level;
  final int xp;
  final int coins;
  final int gems;
  final int vipLevel;
  final bool isOnline;
  final bool isGuest;
  final DateTime? lastActive;
  final Map<String, dynamic>? gameStats;
  final List<dynamic> badges;
  final Map<String, dynamic> stats;

  const UserModel({
    required this.id,
    required this.uid,
    required this.username,
    this.email,
    required this.avatar,
    this.coverPhoto,
    this.bio,
    required this.region,
    required this.level,
    required this.xp,
    required this.coins,
    required this.gems,
    required this.vipLevel,
    required this.isOnline,
    required this.isGuest,
    this.lastActive,
    this.gameStats,
    required this.badges,
    required this.stats,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
        uid: json['uid']?.toString() ?? '',
        username: json['username'] ?? 'User',
        email: json['email'],
        avatar: json['avatar'] ?? '',
        coverPhoto: json['coverPhoto'],
        bio: json['bio'],
        region: json['region']?.toString() ?? 'Global',
        level: _toInt(json['level']) ?? 1,
        xp: _toInt(json['xp']) ?? 0,
        coins: _toInt(json['coins']) ?? 0,
        gems: _toInt(json['gems']) ?? 0,
        vipLevel: _toInt(json['vipLevel']) ?? 0,
        isOnline:
            json['status']?['isOnline'] == true || json['isOnline'] == true,
        isGuest: json['isGuest'] == true,
        lastActive: json['status']?['lastActive'] != null
            ? DateTime.tryParse(json['status']['lastActive'].toString())
            : null,
        gameStats: json['gameStats'] is Map
            ? Map<String, dynamic>.from(json['gameStats'])
            : null,
        badges: json['badges'] is List ? List.from(json['badges']) : [],
        stats: json['stats'] is Map
            ? Map<String, dynamic>.from(json['stats'])
            : {},
      );

  UserModel copyWith({
    String? id,
    String? uid,
    String? username,
    String? email,
    String? avatar,
    String? coverPhoto,
    String? bio,
    String? region,
    int? level,
    int? xp,
    int? coins,
    int? gems,
    int? vipLevel,
    bool? isOnline,
    bool? isGuest,
    DateTime? lastActive,
    Map<String, dynamic>? gameStats,
    List<dynamic>? badges,
    Map<String, dynamic>? stats,
  }) =>
      UserModel(
        id: id ?? this.id,
        uid: uid ?? this.uid,
        username: username ?? this.username,
        email: email ?? this.email,
        avatar: avatar ?? this.avatar,
        coverPhoto: coverPhoto ?? this.coverPhoto,
        bio: bio ?? this.bio,
        region: region ?? this.region,
        level: level ?? this.level,
        xp: xp ?? this.xp,
        coins: coins ?? this.coins,
        gems: gems ?? this.gems,
        vipLevel: vipLevel ?? this.vipLevel,
        isOnline: isOnline ?? this.isOnline,
        isGuest: isGuest ?? this.isGuest,
        lastActive: lastActive ?? this.lastActive,
        gameStats: gameStats ?? this.gameStats,
        badges: badges ?? this.badges,
        stats: stats ?? this.stats,
      );

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  Color get vipColor {
    if (vipLevel <= 0) return Colors.grey;
    if (vipLevel <= 2) return Colors.blue;
    if (vipLevel <= 4) return Colors.purple;
    if (vipLevel <= 6) return Colors.orange;
    return Colors.amber;
  }
}
