import 'dart:ui';

enum MiniDrawToolType { pen, eraser }

enum MiniDrawAccessPolicy { allParticipants, hostAdmin, viewOnly }

MiniDrawToolType miniDrawToolTypeFromString(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'eraser':
      return MiniDrawToolType.eraser;
    case 'pen':
    default:
      return MiniDrawToolType.pen;
  }
}

String miniDrawToolTypeToJson(MiniDrawToolType value) {
  switch (value) {
    case MiniDrawToolType.eraser:
      return 'eraser';
    case MiniDrawToolType.pen:
      return 'pen';
  }
}

MiniDrawAccessPolicy miniDrawAccessPolicyFromString(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'host_admin':
      return MiniDrawAccessPolicy.hostAdmin;
    case 'view_only':
      return MiniDrawAccessPolicy.viewOnly;
    case 'all_participants':
    default:
      return MiniDrawAccessPolicy.allParticipants;
  }
}

String miniDrawAccessPolicyToJson(MiniDrawAccessPolicy value) {
  switch (value) {
    case MiniDrawAccessPolicy.hostAdmin:
      return 'host_admin';
    case MiniDrawAccessPolicy.viewOnly:
      return 'view_only';
    case MiniDrawAccessPolicy.allParticipants:
      return 'all_participants';
  }
}

class MiniDrawPermissions {
  const MiniDrawPermissions({
    this.canUnlock = false,
    this.canManage = false,
    this.canView = false,
    this.canDraw = false,
    this.canClear = false,
    this.canUndoRedo = false,
  });

  final bool canUnlock;
  final bool canManage;
  final bool canView;
  final bool canDraw;
  final bool canClear;
  final bool canUndoRedo;

  factory MiniDrawPermissions.fromJson(Map<String, dynamic>? json) {
    return MiniDrawPermissions(
      canUnlock: json?['canUnlock'] == true,
      canManage: json?['canManage'] == true,
      canView: json?['canView'] == true,
      canDraw: json?['canDraw'] == true,
      canClear: json?['canClear'] == true,
      canUndoRedo: json?['canUndoRedo'] == true,
    );
  }

  MiniDrawPermissions copyWith({
    bool? canUnlock,
    bool? canManage,
    bool? canView,
    bool? canDraw,
    bool? canClear,
    bool? canUndoRedo,
  }) {
    return MiniDrawPermissions(
      canUnlock: canUnlock ?? this.canUnlock,
      canManage: canManage ?? this.canManage,
      canView: canView ?? this.canView,
      canDraw: canDraw ?? this.canDraw,
      canClear: canClear ?? this.canClear,
      canUndoRedo: canUndoRedo ?? this.canUndoRedo,
    );
  }
}

class MiniDrawPoint {
  const MiniDrawPoint({
    required this.x,
    required this.y,
  });

  final double x;
  final double y;

  factory MiniDrawPoint.fromJson(Map<String, dynamic> json) {
    return MiniDrawPoint(
      x: _clampUnit(_asDouble(json['x'])),
      y: _clampUnit(_asDouble(json['y'])),
    );
  }

  Map<String, dynamic> toJson() => {
        'x': double.parse(x.toStringAsFixed(4)),
        'y': double.parse(y.toStringAsFixed(4)),
      };

  Offset toOffset(Size size) => Offset(x * size.width, y * size.height);

  static double _clampUnit(double value) {
    if (value.isNaN || value.isInfinite) return 0;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }
}

class MiniDrawStroke {
  const MiniDrawStroke({
    required this.strokeId,
    required this.toolType,
    required this.colorValue,
    required this.thickness,
    required this.points,
    required this.createdBy,
    required this.createdAt,
    required this.version,
    this.updatedAt,
    this.isVisible = true,
  });

  final String strokeId;
  final MiniDrawToolType toolType;
  final int colorValue;
  final double thickness;
  final List<MiniDrawPoint> points;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int version;
  final bool isVisible;

  factory MiniDrawStroke.fromJson(Map<String, dynamic> json) {
    return MiniDrawStroke(
      strokeId: json['strokeId']?.toString() ?? '',
      toolType: miniDrawToolTypeFromString(json['toolType']?.toString()),
      colorValue: _asInt(json['colorValue'], fallback: 0xFFFFFFFF),
      thickness: _asDouble(json['thickness'], fallback: 3),
      points: (json['points'] is List)
          ? (json['points'] as List)
              .whereType<Map>()
              .map((point) => MiniDrawPoint.fromJson(
                    Map<String, dynamic>.from(point),
                  ))
              .toList(growable: false)
          : const <MiniDrawPoint>[],
      createdBy: json['createdBy']?.toString() ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
      version: _asInt(json['version']),
      isVisible: json['isVisible'] != false,
    );
  }

  MiniDrawStroke copyWith({
    List<MiniDrawPoint>? points,
    DateTime? updatedAt,
    int? version,
    bool? isVisible,
  }) {
    return MiniDrawStroke(
      strokeId: strokeId,
      toolType: toolType,
      colorValue: colorValue,
      thickness: thickness,
      points: points ?? this.points,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  Map<String, dynamic> toJson() => {
        'strokeId': strokeId,
        'toolType': miniDrawToolTypeToJson(toolType),
        'colorValue': colorValue,
        'thickness': thickness,
        'points': points.map((point) => point.toJson()).toList(growable: false),
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'version': version,
        'isVisible': isVisible,
      };

  Color get color => Color(colorValue);
}

class MiniDrawSessionSummary {
  const MiniDrawSessionSummary({
    this.sessionId = '',
    this.roomId = '',
    this.isUnlocked = false,
    this.unlockCostCoins = 300,
    this.enabled = false,
    this.accessPolicy = MiniDrawAccessPolicy.allParticipants,
    this.unlockedBy = '',
    this.unlockedAt,
    this.version = 0,
    this.strokeCount = 0,
    this.lastClearedAt,
    this.lastClearedBy = '',
    this.updatedAt,
    this.roomActive = true,
    this.permissions = const MiniDrawPermissions(),
  });

  final String sessionId;
  final String roomId;
  final bool isUnlocked;
  final int unlockCostCoins;
  final bool enabled;
  final MiniDrawAccessPolicy accessPolicy;
  final String unlockedBy;
  final DateTime? unlockedAt;
  final int version;
  final int strokeCount;
  final DateTime? lastClearedAt;
  final String lastClearedBy;
  final DateTime? updatedAt;
  final bool roomActive;
  final MiniDrawPermissions permissions;

  factory MiniDrawSessionSummary.fromJson(Map<String, dynamic>? json) {
    return MiniDrawSessionSummary(
      sessionId: json?['sessionId']?.toString() ?? '',
      roomId: json?['roomId']?.toString() ?? '',
      isUnlocked: json?['isUnlocked'] == true,
      unlockCostCoins: _asInt(json?['unlockCostCoins'], fallback: 300),
      enabled: json?['enabled'] == true,
      accessPolicy:
          miniDrawAccessPolicyFromString(json?['accessPolicy']?.toString()),
      unlockedBy: json?['unlockedBy']?.toString() ?? '',
      unlockedAt: json?['unlockedAt'] != null
          ? DateTime.tryParse(json!['unlockedAt'].toString())
          : null,
      version: _asInt(json?['version']),
      strokeCount: _asInt(json?['strokeCount']),
      lastClearedAt: json?['lastClearedAt'] != null
          ? DateTime.tryParse(json!['lastClearedAt'].toString())
          : null,
      lastClearedBy: json?['lastClearedBy']?.toString() ?? '',
      updatedAt: json?['updatedAt'] != null
          ? DateTime.tryParse(json!['updatedAt'].toString())
          : null,
      roomActive: json?['roomActive'] != false,
      permissions: MiniDrawPermissions.fromJson(
        json?['permissions'] is Map<String, dynamic>
            ? json!['permissions'] as Map<String, dynamic>
            : json?['permissions'] is Map
                ? Map<String, dynamic>.from(json!['permissions'] as Map)
                : null,
      ),
    );
  }

  MiniDrawSessionSummary copyWith({
    String? sessionId,
    String? roomId,
    bool? isUnlocked,
    int? unlockCostCoins,
    bool? enabled,
    MiniDrawAccessPolicy? accessPolicy,
    String? unlockedBy,
    DateTime? unlockedAt,
    int? version,
    int? strokeCount,
    DateTime? lastClearedAt,
    String? lastClearedBy,
    DateTime? updatedAt,
    bool? roomActive,
    MiniDrawPermissions? permissions,
  }) {
    return MiniDrawSessionSummary(
      sessionId: sessionId ?? this.sessionId,
      roomId: roomId ?? this.roomId,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      unlockCostCoins: unlockCostCoins ?? this.unlockCostCoins,
      enabled: enabled ?? this.enabled,
      accessPolicy: accessPolicy ?? this.accessPolicy,
      unlockedBy: unlockedBy ?? this.unlockedBy,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      version: version ?? this.version,
      strokeCount: strokeCount ?? this.strokeCount,
      lastClearedAt: lastClearedAt ?? this.lastClearedAt,
      lastClearedBy: lastClearedBy ?? this.lastClearedBy,
      updatedAt: updatedAt ?? this.updatedAt,
      roomActive: roomActive ?? this.roomActive,
      permissions: permissions ?? this.permissions,
    );
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'roomId': roomId,
        'isUnlocked': isUnlocked,
        'unlockCostCoins': unlockCostCoins,
        'enabled': enabled,
        'accessPolicy': miniDrawAccessPolicyToJson(accessPolicy),
        'unlockedBy': unlockedBy,
        'unlockedAt': unlockedAt?.toIso8601String(),
        'version': version,
        'strokeCount': strokeCount,
        'lastClearedAt': lastClearedAt?.toIso8601String(),
        'lastClearedBy': lastClearedBy,
        'updatedAt': updatedAt?.toIso8601String(),
        'roomActive': roomActive,
        'permissions': {
          'canUnlock': permissions.canUnlock,
          'canManage': permissions.canManage,
          'canView': permissions.canView,
          'canDraw': permissions.canDraw,
          'canClear': permissions.canClear,
          'canUndoRedo': permissions.canUndoRedo,
        },
      };
}

class MiniDrawSnapshot {
  const MiniDrawSnapshot({
    required this.summary,
    required this.strokes,
  });

  final MiniDrawSessionSummary summary;
  final List<MiniDrawStroke> strokes;

  factory MiniDrawSnapshot.fromJson(Map<String, dynamic> json) {
    return MiniDrawSnapshot(
      summary: MiniDrawSessionSummary.fromJson(
        json['summary'] is Map<String, dynamic>
            ? json['summary'] as Map<String, dynamic>
            : json['summary'] is Map
                ? Map<String, dynamic>.from(json['summary'] as Map)
                : null,
      ),
      strokes: (json['strokes'] is List)
          ? (json['strokes'] as List)
              .whereType<Map>()
              .map((stroke) => MiniDrawStroke.fromJson(
                    Map<String, dynamic>.from(stroke),
                  ))
              .toList(growable: false)
          : const <MiniDrawStroke>[],
    );
  }
}

double _asDouble(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? fallback;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}
