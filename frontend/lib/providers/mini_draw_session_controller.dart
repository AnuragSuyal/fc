import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/mini_draw_model.dart';
import '../models/room_model.dart';
import '../services/mini_draw_service.dart';
import '../services/socket_service.dart';

class MiniDrawSessionController extends ChangeNotifier {
  MiniDrawSessionController({
    required RoomModel initialRoom,
    required String? currentUserId,
  })  : _room = initialRoom,
        _currentUserId = currentUserId,
        _summary = const MiniDrawSessionSummary() {
    _applySummary(initialRoom.miniDraw, clearIfSessionChanged: true);
    _drawSubscription = SocketService.roomDrawStream.listen(_handleDrawEvent);
    _resyncSubscription = SocketService.resyncStream.listen((_) {
      if (_summary.isUnlocked &&
          _hasLoadedSnapshot &&
          !_hasInFlightLocalStroke) {
        unawaited(ensureSnapshotLoaded(force: true));
      }
    });
  }

  static final Random _random = Random();

  final ValueNotifier<int> canvasRevision = ValueNotifier<int>(0);

  RoomModel _room;
  final String? _currentUserId;
  StreamSubscription<Map<String, dynamic>>? _drawSubscription;
  StreamSubscription<Map<String, dynamic>>? _resyncSubscription;

  MiniDrawSessionSummary _summary;
  List<MiniDrawStroke> _strokes = const [];
  final Map<String, MiniDrawStroke> _remoteActiveStrokes =
      <String, MiniDrawStroke>{};
  final Map<String, MiniDrawStroke> _pendingLocalStrokes =
      <String, MiniDrawStroke>{};
  MiniDrawStroke? _activeLocalStroke;
  final List<MiniDrawPoint> _queuedChunkPoints = <MiniDrawPoint>[];
  Timer? _chunkFlushTimer;

  bool _hasLoadedSnapshot = false;
  int _loadedSnapshotVersion = 0;
  bool _isLoadingSnapshot = false;
  bool _isUnlocking = false;
  bool _isSavingSettings = false;
  bool _isApplyingAction = false;
  String? _errorMessage;

  MiniDrawToolType _selectedTool = MiniDrawToolType.pen;
  int _selectedColorValue = 0xFFFFFFFF;
  double _selectedBrushSize = 3;

  RoomModel get room => _room;
  MiniDrawSessionSummary get summary => _summary;
  List<MiniDrawStroke> get committedStrokes =>
      List<MiniDrawStroke>.unmodifiable(
        _strokes.where((stroke) => stroke.isVisible),
      );
  Map<String, MiniDrawStroke> get remoteActiveStrokes =>
      Map<String, MiniDrawStroke>.unmodifiable(_remoteActiveStrokes);
  Map<String, MiniDrawStroke> get pendingLocalStrokes =>
      Map<String, MiniDrawStroke>.unmodifiable(_pendingLocalStrokes);
  MiniDrawStroke? get activeLocalStroke => _activeLocalStroke;
  MiniDrawToolType get selectedTool => _selectedTool;
  int get selectedColorValue => _selectedColorValue;
  double get selectedBrushSize => _selectedBrushSize;
  bool get isLoadingSnapshot => _isLoadingSnapshot;
  bool get isUnlocking => _isUnlocking;
  bool get isSavingSettings => _isSavingSettings;
  bool get isApplyingAction => _isApplyingAction;
  String? get errorMessage => _errorMessage;
  bool get hasLoadedSnapshot => _hasLoadedSnapshot;
  int get loadedSnapshotVersion => _loadedSnapshotVersion;

  bool get canUnlock => _summary.permissions.canUnlock;
  bool get canManage => _summary.permissions.canManage;
  bool get canView => _summary.permissions.canView;
  bool get canDraw => _summary.permissions.canDraw;
  bool get canClear => _summary.permissions.canClear;
  bool get canUndoRedo => _summary.permissions.canUndoRedo;
  bool get hasInteractiveSurface =>
      canView || canManage || canUnlock || canClear;
  bool get isReadOnly =>
      _summary.isUnlocked && _summary.enabled && !canDraw && canView;
  bool get isDisabledForRoom =>
      _summary.isUnlocked && !_summary.enabled && !canManage && !canClear;
  bool get _hasInFlightLocalStroke =>
      _activeLocalStroke != null || _pendingLocalStrokes.isNotEmpty;

  List<MiniDrawStroke> get renderedStrokes {
    final strokes = <MiniDrawStroke>[
      ..._strokes.where((stroke) => stroke.isVisible),
      ..._pendingLocalStrokes.values,
      ..._remoteActiveStrokes.values,
    ];
    if (_activeLocalStroke != null) {
      strokes.add(_activeLocalStroke!);
    }
    return strokes;
  }

  void applyRoomSnapshot(RoomModel room) {
    final previousSessionId = _summary.sessionId;
    _room = room;
    _applySummary(
      room.miniDraw,
      clearIfSessionChanged: previousSessionId.isNotEmpty &&
          previousSessionId != room.miniDraw.sessionId,
    );
    notifyListeners();
  }

  Future<void> ensureSnapshotLoaded({bool force = false}) async {
    if (!_summary.isUnlocked) {
      _strokes = const [];
      _remoteActiveStrokes.clear();
      _pendingLocalStrokes.clear();
      _activeLocalStroke = null;
      _hasLoadedSnapshot = false;
      _notifyCanvasChanged();
      return;
    }
    if (_isLoadingSnapshot) return;
    if (!force &&
        _hasLoadedSnapshot &&
        _summary.version == _loadedSnapshotVersion) {
      return;
    }

    _isLoadingSnapshot = true;
    _clearError(notify: false);
    notifyListeners();
    try {
      final snapshot = await MiniDrawService.getSnapshot(_room.id);
      _applySummary(snapshot.summary, clearIfSessionChanged: true);
      _strokes = snapshot.strokes;
      _remoteActiveStrokes.clear();
      _pendingLocalStrokes.clear();
      _activeLocalStroke = null;
      _queuedChunkPoints.clear();
      _hasLoadedSnapshot = true;
      _loadedSnapshotVersion = _summary.version;
      _notifyCanvasChanged();
    } catch (error) {
      _setError(
          _normalizeError(error, fallback: 'Could not load the draw board'));
    } finally {
      _isLoadingSnapshot = false;
      notifyListeners();
    }
  }

  Future<void> unlockFeature() async {
    if (_isUnlocking) return;
    _isUnlocking = true;
    _clearError(notify: false);
    notifyListeners();
    try {
      final result = await MiniDrawService.unlock(_room.id);
      _applySummary(result.summary, clearIfSessionChanged: true);
      await ensureSnapshotLoaded(force: true);
    } catch (error) {
      _setError(
        _normalizeError(error, fallback: 'Mini Draw could not be unlocked'),
      );
    } finally {
      _isUnlocking = false;
      notifyListeners();
    }
  }

  Future<void> setFeatureEnabled(bool enabled) async {
    if (_isSavingSettings) return;
    _isSavingSettings = true;
    _clearError(notify: false);
    notifyListeners();
    try {
      final nextSummary = await MiniDrawService.updateSettings(
        _room.id,
        enabled: enabled,
      );
      _applySummary(nextSummary);
    } catch (error) {
      _setError(
        _normalizeError(error, fallback: 'Could not update draw availability'),
      );
    } finally {
      _isSavingSettings = false;
      notifyListeners();
    }
  }

  Future<void> setAccessPolicy(MiniDrawAccessPolicy accessPolicy) async {
    if (_isSavingSettings) return;
    _isSavingSettings = true;
    _clearError(notify: false);
    notifyListeners();
    try {
      final nextSummary = await MiniDrawService.updateSettings(
        _room.id,
        accessPolicy: accessPolicy,
      );
      _applySummary(nextSummary);
    } catch (error) {
      _setError(
        _normalizeError(error, fallback: 'Could not update draw permissions'),
      );
    } finally {
      _isSavingSettings = false;
      notifyListeners();
    }
  }

  Future<void> clearCanvas() async {
    if (_isApplyingAction) return;
    _isApplyingAction = true;
    _clearError(notify: false);
    notifyListeners();
    try {
      final nextSummary = await MiniDrawService.clear(_room.id);
      _applySummary(nextSummary);
      _strokes = const [];
      _remoteActiveStrokes.clear();
      _pendingLocalStrokes.clear();
      _activeLocalStroke = null;
      _queuedChunkPoints.clear();
      _hasLoadedSnapshot = true;
      _loadedSnapshotVersion = _summary.version;
      _notifyCanvasChanged();
    } catch (error) {
      _setError(_normalizeError(error, fallback: 'Could not clear the canvas'));
    } finally {
      _isApplyingAction = false;
      notifyListeners();
    }
  }

  Future<void> undo() async {
    if (_isApplyingAction) return;
    _isApplyingAction = true;
    _clearError(notify: false);
    notifyListeners();
    try {
      final nextSummary = await MiniDrawService.undo(_room.id);
      _applySummary(nextSummary);
      await ensureSnapshotLoaded(force: true);
    } catch (error) {
      _setError(_normalizeError(error, fallback: 'Could not undo that stroke'));
    } finally {
      _isApplyingAction = false;
      notifyListeners();
    }
  }

  Future<void> redo() async {
    if (_isApplyingAction) return;
    _isApplyingAction = true;
    _clearError(notify: false);
    notifyListeners();
    try {
      final nextSummary = await MiniDrawService.redo(_room.id);
      _applySummary(nextSummary);
      await ensureSnapshotLoaded(force: true);
    } catch (error) {
      _setError(_normalizeError(error, fallback: 'Could not redo that stroke'));
    } finally {
      _isApplyingAction = false;
      notifyListeners();
    }
  }

  void selectTool(MiniDrawToolType tool) {
    if (_selectedTool == tool) return;
    _selectedTool = tool;
    notifyListeners();
  }

  void selectColorValue(int colorValue) {
    if (_selectedColorValue == colorValue) return;
    _selectedColorValue = colorValue;
    if (_selectedTool == MiniDrawToolType.eraser) {
      _selectedTool = MiniDrawToolType.pen;
    }
    notifyListeners();
  }

  void selectBrushSize(double size) {
    final nextSize = size.clamp(1.0, 24.0);
    if ((_selectedBrushSize - nextSize).abs() < 0.001) return;
    _selectedBrushSize = nextSize;
    notifyListeners();
  }

  void beginStroke(MiniDrawPoint point) {
    if (!canDraw || _summary.sessionId.isEmpty) return;
    _clearError();
    final strokeId = _buildStrokeId();
    final stroke = MiniDrawStroke(
      strokeId: strokeId,
      toolType: _selectedTool,
      colorValue: _selectedTool == MiniDrawToolType.eraser
          ? 0x00FFFFFF
          : _selectedColorValue,
      thickness: _selectedBrushSize,
      points: <MiniDrawPoint>[point],
      createdBy: _currentUserId ?? '',
      createdAt: DateTime.now(),
      version: _summary.version,
    );
    _activeLocalStroke = stroke;
    _queuedChunkPoints
      ..clear()
      ..add(point);
    _flushStrokeQueue(forceBegin: true);
    _notifyCanvasChanged();
  }

  void appendStrokePoint(MiniDrawPoint point) {
    final activeStroke = _activeLocalStroke;
    if (activeStroke == null) return;

    final nextPoints = <MiniDrawPoint>[...activeStroke.points, point];
    _activeLocalStroke = activeStroke.copyWith(points: nextPoints);
    _queuedChunkPoints.add(point);
    if (_queuedChunkPoints.length >= 8) {
      _flushStrokeQueue();
    } else {
      _chunkFlushTimer ??= Timer(
        const Duration(milliseconds: 30),
        () {
          _chunkFlushTimer = null;
          _flushStrokeQueue();
        },
      );
    }
    _notifyCanvasChanged();
  }

  void endStroke() {
    final activeStroke = _activeLocalStroke;
    if (activeStroke == null) return;

    _chunkFlushTimer?.cancel();
    _chunkFlushTimer = null;

    final finalChunk = _queuedChunkPoints.toList(growable: false);
    _queuedChunkPoints.clear();
    _pendingLocalStrokes[activeStroke.strokeId] = activeStroke;
    _activeLocalStroke = null;

    SocketService.sendRoomDrawStrokeEnd(
      roomId: _room.id,
      sessionId: _summary.sessionId,
      strokeId: activeStroke.strokeId,
      points: finalChunk.map((point) => point.toJson()).toList(growable: false),
    );
    _notifyCanvasChanged();
  }

  void cancelLocalStroke() {
    _chunkFlushTimer?.cancel();
    _chunkFlushTimer = null;
    _queuedChunkPoints.clear();
    _activeLocalStroke = null;
    _notifyCanvasChanged();
  }

  void clearError() => _clearError();

  void _flushStrokeQueue({bool forceBegin = false}) {
    final activeStroke = _activeLocalStroke;
    if (activeStroke == null || _queuedChunkPoints.isEmpty) return;

    final points = _queuedChunkPoints.toList(growable: false);
    _queuedChunkPoints.clear();

    if (forceBegin) {
      SocketService.sendRoomDrawStrokeBegin(
        roomId: _room.id,
        sessionId: _summary.sessionId,
        strokeId: activeStroke.strokeId,
        toolType: miniDrawToolTypeToJson(activeStroke.toolType),
        colorValue: activeStroke.colorValue,
        thickness: activeStroke.thickness,
        points: points.map((point) => point.toJson()).toList(growable: false),
      );
      return;
    }

    SocketService.sendRoomDrawStrokeChunk(
      roomId: _room.id,
      sessionId: _summary.sessionId,
      strokeId: activeStroke.strokeId,
      points: points.map((point) => point.toJson()).toList(growable: false),
    );
  }

  void _handleDrawEvent(Map<String, dynamic> data) {
    final eventRoomId = data['roomId']?.toString();
    if (eventRoomId != _room.id) return;

    switch (data['_eventType']?.toString()) {
      case 'draw_meta':
        _applyPublicSummary(data['summary']);
        break;
      case 'draw_progress':
        _handleDrawProgress(data);
        break;
      case 'draw_commit':
        _handleDrawCommit(data);
        break;
      case 'draw_clear':
        _applyPublicSummary(data['summary']);
        _strokes = const [];
        _remoteActiveStrokes.clear();
        _pendingLocalStrokes.clear();
        _activeLocalStroke = null;
        _queuedChunkPoints.clear();
        _hasLoadedSnapshot = true;
        _loadedSnapshotVersion = _summary.version;
        _notifyCanvasChanged();
        break;
      case 'draw_undo':
        _applyPublicSummary(data['summary']);
        final strokeId = data['strokeId']?.toString() ?? '';
        if (strokeId.isNotEmpty) {
          _strokes = _strokes
              .map(
                (stroke) => stroke.strokeId == strokeId
                    ? stroke.copyWith(isVisible: false)
                    : stroke,
              )
              .toList(growable: false);
          _loadedSnapshotVersion = _summary.version;
          _notifyCanvasChanged();
        }
        break;
      case 'draw_redo':
        _applyPublicSummary(data['summary']);
        final strokeId = data['strokeId']?.toString() ?? '';
        if (strokeId.isNotEmpty) {
          _strokes = _strokes
              .map(
                (stroke) => stroke.strokeId == strokeId
                    ? stroke.copyWith(isVisible: true)
                    : stroke,
              )
              .toList(growable: false);
          _loadedSnapshotVersion = _summary.version;
          _notifyCanvasChanged();
        }
        break;
      case 'draw_error':
        _handleDrawError(data);
        break;
    }
  }

  void _handleDrawProgress(Map<String, dynamic> data) {
    final strokeId = data['strokeId']?.toString() ?? '';
    final remoteUserId = data['userId']?.toString() ?? '';
    if (strokeId.isEmpty || remoteUserId == _currentUserId) return;

    final chunk = _parsePointList(data['points']);
    if (chunk.isEmpty) return;

    final existing = _remoteActiveStrokes[strokeId];
    if (existing == null) {
      final toolType = miniDrawToolTypeFromString(data['toolType']?.toString());
      final colorValue = _asInt(data['colorValue'], fallback: 0xFFFFFFFF);
      final thickness = _asDouble(data['thickness'], fallback: 3);
      final createdAt = data['createdAt'] != null
          ? DateTime.tryParse(data['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now();
      _remoteActiveStrokes[strokeId] = MiniDrawStroke(
        strokeId: strokeId,
        toolType: toolType,
        colorValue: colorValue,
        thickness: thickness,
        points: chunk,
        createdBy: remoteUserId,
        createdAt: createdAt,
        version: _summary.version,
      );
    } else {
      _remoteActiveStrokes[strokeId] = existing.copyWith(
        points: <MiniDrawPoint>[...existing.points, ...chunk],
        updatedAt: DateTime.now(),
      );
    }
    _notifyCanvasChanged();
  }

  void _handleDrawCommit(Map<String, dynamic> data) {
    _applyPublicSummary(data['summary']);
    final strokeJson = data['stroke'];
    final stroke = strokeJson is Map<String, dynamic>
        ? MiniDrawStroke.fromJson(strokeJson)
        : strokeJson is Map
            ? MiniDrawStroke.fromJson(Map<String, dynamic>.from(strokeJson))
            : null;
    if (stroke == null || stroke.strokeId.isEmpty) {
      unawaited(ensureSnapshotLoaded(force: true));
      return;
    }

    _remoteActiveStrokes.remove(stroke.strokeId);
    _pendingLocalStrokes.remove(stroke.strokeId);
    _strokes = _upsertStroke(_strokes, stroke);
    _hasLoadedSnapshot = true;
    _loadedSnapshotVersion = _summary.version;
    _notifyCanvasChanged();
  }

  void _handleDrawError(Map<String, dynamic> data) {
    final message = data['message']?.toString();
    if (message != null && message.trim().isNotEmpty) {
      _setError(message.trim());
    }
    if (data['code']?.toString() == 'MINI_DRAW_SESSION_STALE') {
      cancelLocalStroke();
      _pendingLocalStrokes.clear();
      unawaited(ensureSnapshotLoaded(force: true));
    }
  }

  void _applyPublicSummary(dynamic rawSummary) {
    if (rawSummary is Map<String, dynamic>) {
      _applySummary(MiniDrawSessionSummary.fromJson(rawSummary));
      notifyListeners();
    } else if (rawSummary is Map) {
      _applySummary(
        MiniDrawSessionSummary.fromJson(Map<String, dynamic>.from(rawSummary)),
      );
      notifyListeners();
    }
  }

  void _applySummary(
    MiniDrawSessionSummary nextSummary, {
    bool clearIfSessionChanged = false,
  }) {
    final previousSessionId = _summary.sessionId;
    final sessionChanged = clearIfSessionChanged &&
        previousSessionId.isNotEmpty &&
        nextSummary.sessionId.isNotEmpty &&
        previousSessionId != nextSummary.sessionId;
    final permissions = _derivePermissions(_room, nextSummary);
    _summary = nextSummary.copyWith(permissions: permissions);
    if (sessionChanged) {
      _strokes = const [];
      _remoteActiveStrokes.clear();
      _pendingLocalStrokes.clear();
      _activeLocalStroke = null;
      _queuedChunkPoints.clear();
      _hasLoadedSnapshot = false;
      _loadedSnapshotVersion = 0;
      _notifyCanvasChanged();
    }
  }

  MiniDrawPermissions _derivePermissions(
    RoomModel room,
    MiniDrawSessionSummary summary,
  ) {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) {
      return const MiniDrawPermissions();
    }

    Participant? selfParticipant;
    for (final participant in room.participants) {
      if (participant.userId == userId) {
        selfParticipant = participant;
        break;
      }
    }

    final effectiveOwnerId =
        room.ownerId.isNotEmpty ? room.ownerId : room.hostId;
    final isParticipant = selfParticipant?.isPresent == true;
    final isOwner = userId == effectiveOwnerId;
    final isAdmin = isOwner ||
        room.hostId == userId ||
        room.coHostIds.contains(userId) ||
        room.moderatorIds.contains(userId) ||
        selfParticipant?.role == 'cohost' ||
        selfParticipant?.role == 'moderator' ||
        selfParticipant?.role == 'host';

    final canManage = summary.isUnlocked && isParticipant && isOwner;
    final canClear = summary.isUnlocked && isParticipant && isAdmin;
    final canUnlock = !summary.isUnlocked && isParticipant && isOwner;
    final canView = summary.isUnlocked &&
        isParticipant &&
        (summary.enabled || canManage || canClear);

    var canDraw = false;
    if (summary.isUnlocked &&
        summary.enabled &&
        isParticipant &&
        room.roomActive) {
      switch (summary.accessPolicy) {
        case MiniDrawAccessPolicy.hostAdmin:
          canDraw = isAdmin;
          break;
        case MiniDrawAccessPolicy.viewOnly:
          canDraw = false;
          break;
        case MiniDrawAccessPolicy.allParticipants:
          canDraw = true;
          break;
      }
    }

    return MiniDrawPermissions(
      canUnlock: canUnlock,
      canManage: canManage,
      canView: canView,
      canDraw: canDraw,
      canClear: canClear,
      canUndoRedo: canDraw,
    );
  }

  List<MiniDrawStroke> _upsertStroke(
    List<MiniDrawStroke> source,
    MiniDrawStroke stroke,
  ) {
    final nextStrokes = List<MiniDrawStroke>.from(source);
    final existingIndex =
        nextStrokes.indexWhere((entry) => entry.strokeId == stroke.strokeId);
    if (existingIndex >= 0) {
      nextStrokes[existingIndex] = stroke;
    } else {
      nextStrokes.add(stroke);
    }
    nextStrokes
        .sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return List<MiniDrawStroke>.unmodifiable(nextStrokes);
  }

  List<MiniDrawPoint> _parsePointList(dynamic value) {
    if (value is! List) return const <MiniDrawPoint>[];
    final points = <MiniDrawPoint>[];
    for (final item in value) {
      if (item is Map<String, dynamic>) {
        points.add(MiniDrawPoint.fromJson(item));
      } else if (item is Map) {
        points.add(MiniDrawPoint.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return points;
  }

  String _buildStrokeId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final entropy = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'stroke-$timestamp-$entropy';
  }

  void _notifyCanvasChanged() {
    canvasRevision.value++;
  }

  void _clearError({bool notify = true}) {
    if (_errorMessage == null) return;
    _errorMessage = null;
    if (notify) notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  String _normalizeError(Object error, {required String fallback}) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    return message.isEmpty ? fallback : message;
  }

  @override
  void dispose() {
    _chunkFlushTimer?.cancel();
    _drawSubscription?.cancel();
    _resyncSubscription?.cancel();
    canvasRevision.dispose();
    super.dispose();
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
