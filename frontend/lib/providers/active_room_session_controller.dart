import 'dart:async';

import 'package:flutter/material.dart';

import '../models/room_model.dart';
import '../services/app_navigation_service.dart';
import '../services/room_service.dart';
import '../services/socket_service.dart';
import '../services/voice_service.dart';

class ActiveRoomSessionController extends ChangeNotifier {
  ActiveRoomSessionController() {
    _roomUpdateSubscription =
        SocketService.roomUpdateStream.listen(_handleRoomUpdate);
  }

  final VoiceService _voiceService = VoiceService();
  StreamSubscription<Map<String, dynamic>>? _roomUpdateSubscription;
  Timer? _backgroundHeartbeatTimer;

  RoomModel? _activeRoom;
  bool _isBackgrounded = false;
  bool _isRoomScreenAttached = false;
  bool _backgroundOwnsSocketMembership = false;
  bool _isResumingRoom = false;
  bool _isLeavingRoom = false;

  RoomModel? get activeRoom => _activeRoom;
  bool get hasActiveRoom => _activeRoom != null;
  bool get isBackgrounded => _isBackgrounded;
  bool get isRoomScreenAttached => _isRoomScreenAttached;
  bool get isResumingRoom => _isResumingRoom;
  bool get showFloatingEntry =>
      _activeRoom != null &&
      _isBackgrounded &&
      !_isRoomScreenAttached &&
      !_isResumingRoom;

  Future<void> prepareForForegroundRoom(RoomModel room) async {
    final existingRoom = _activeRoom;
    if (existingRoom == null || existingRoom.id == room.id) {
      return;
    }

    if (_isRoomScreenAttached) {
      return;
    }

    await _leaveTrackedRoom(
      existingRoom,
      notifyServer: true,
      showFeedback: false,
      clearTracking: true,
    );
  }

  RoomModel attachRoomScreen(RoomModel room) {
    final shouldReuseTrackedRoom =
        _activeRoom?.id == room.id && (_isBackgrounded || _isRoomScreenAttached);
    _activeRoom = shouldReuseTrackedRoom ? _activeRoom : room;
    _isBackgrounded = false;
    _isRoomScreenAttached = true;
    _isResumingRoom = false;
    _stopBackgroundHeartbeat();
    notifyListeners();
    return _activeRoom!;
  }

  void detachRoomScreen(
    String roomId, {
    required bool backgrounded,
  }) {
    if (_activeRoom?.id != roomId) return;

    _isRoomScreenAttached = false;
    _isBackgrounded = backgrounded;
    if (backgrounded) {
      _backgroundOwnsSocketMembership = true;
      _startBackgroundHeartbeat();
    } else {
      _backgroundOwnsSocketMembership = false;
      _stopBackgroundHeartbeat();
    }
    notifyListeners();
  }

  void updateRoom(RoomModel room) {
    if (_activeRoom?.id != room.id) return;
    _activeRoom = room;
    notifyListeners();
  }

  void backgroundRoom(RoomModel room) {
    _activeRoom = room;
    _isBackgrounded = true;
    _isRoomScreenAttached = false;
    _isResumingRoom = false;
    _backgroundOwnsSocketMembership = true;
    _startBackgroundHeartbeat();
    notifyListeners();
  }

  bool claimForegroundSocketMembership(String roomId) {
    if (_activeRoom?.id != roomId || !_backgroundOwnsSocketMembership) {
      return false;
    }

    _backgroundOwnsSocketMembership = false;
    _isBackgrounded = false;
    _isRoomScreenAttached = true;
    _stopBackgroundHeartbeat();
    notifyListeners();
    return true;
  }

  bool beginRoomResume() {
    if (!showFloatingEntry) return false;
    _isResumingRoom = true;
    notifyListeners();
    return true;
  }

  void finishRoomResumeAttempt() {
    if (!_isResumingRoom) return;
    _isResumingRoom = false;
    notifyListeners();
  }

  Future<void> leaveBackgroundRoom({String? reason}) async {
    final room = _activeRoom;
    if (room == null) return;

    await _leaveTrackedRoom(
      room,
      notifyServer: true,
      showFeedback: reason != null && reason.trim().isNotEmpty,
      feedbackMessage: reason,
      clearTracking: true,
    );
  }

  Future<void> clearRoomSession(
    String roomId, {
    bool showFeedback = false,
    String? feedbackMessage,
  }) async {
    if (_activeRoom?.id != roomId) return;

    await _leaveTrackedRoom(
      _activeRoom!,
      notifyServer: false,
      showFeedback: showFeedback,
      feedbackMessage: feedbackMessage,
      clearTracking: true,
    );
  }

  void clearTrackedRoom(String roomId) {
    if (_activeRoom?.id != roomId) return;
    _clearTracking();
    notifyListeners();
  }

  void _handleRoomUpdate(Map<String, dynamic> data) {
    final trackedRoom = _activeRoom;
    if (trackedRoom == null) return;

    final payloadRoomId = data['roomId']?.toString() ??
        data['_id']?.toString() ??
        data['id']?.toString();
    if (payloadRoomId != trackedRoom.id) {
      return;
    }

    final roomPayload = data['room'];
    if (roomPayload is Map<String, dynamic>) {
      _activeRoom = RoomModel.fromJson(roomPayload);
      notifyListeners();
    } else if (roomPayload is Map) {
      _activeRoom = RoomModel.fromJson(Map<String, dynamic>.from(roomPayload));
      notifyListeners();
    }

    if (_isRoomScreenAttached) {
      return;
    }

    final eventType = data['_eventType']?.toString();
    if (eventType == 'room_deleted') {
      unawaited(
        clearRoomSession(
          trackedRoom.id,
          showFeedback: true,
          feedbackMessage: 'This room has ended.',
        ),
      );
    } else if (eventType == 'user_kicked') {
      unawaited(
        clearRoomSession(
          trackedRoom.id,
          showFeedback: true,
          feedbackMessage: 'You were removed from the room.',
        ),
      );
    } else if (eventType == 'user_banned') {
      unawaited(
        clearRoomSession(
          trackedRoom.id,
          showFeedback: true,
          feedbackMessage: 'You were banned from this room.',
        ),
      );
    }
  }

  Future<void> _leaveTrackedRoom(
    RoomModel room, {
    required bool notifyServer,
    required bool showFeedback,
    String? feedbackMessage,
    required bool clearTracking,
  }) async {
    if (_isLeavingRoom) return;
    _isLeavingRoom = true;

    try {
      if (notifyServer) {
        await RoomService.leaveRoom(room.id);
      }
    } catch (error) {
      debugPrint('ActiveRoomSessionController leave failed: $error');
    } finally {
      if (_backgroundOwnsSocketMembership || _activeRoom?.id == room.id) {
        SocketService.leaveRoom(room.id);
      }
      await _voiceService.disconnect();
      if (clearTracking && _activeRoom?.id == room.id) {
        _clearTracking();
        notifyListeners();
      }
      _isLeavingRoom = false;
    }

    if (showFeedback && feedbackMessage != null && feedbackMessage.isNotEmpty) {
      _showFeedback(feedbackMessage);
    }
  }

  void _startBackgroundHeartbeat() {
    final roomId = _activeRoom?.id;
    if (roomId == null || roomId.isEmpty) return;
    if (_backgroundHeartbeatTimer != null) return;

    _backgroundHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (_activeRoom?.id != roomId || !_isBackgrounded) return;
        SocketService.sendHeartbeat(roomId: roomId);
      },
    );
  }

  void _stopBackgroundHeartbeat() {
    _backgroundHeartbeatTimer?.cancel();
    _backgroundHeartbeatTimer = null;
  }

  void _showFeedback(String message) {
    final context = appNavigatorKey.currentContext;
    if (context == null) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearTracking() {
    _activeRoom = null;
    _isBackgrounded = false;
    _isRoomScreenAttached = false;
    _backgroundOwnsSocketMembership = false;
    _isResumingRoom = false;
    _stopBackgroundHeartbeat();
  }

  @override
  void dispose() {
    _backgroundHeartbeatTimer?.cancel();
    _roomUpdateSubscription?.cancel();
    super.dispose();
  }
}
