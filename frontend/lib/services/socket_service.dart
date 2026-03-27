import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../utils/constants.dart';
import 'auth_service.dart';

/// Central real-time hub for the entire app.
/// All streams are broadcast, so multiple widgets can listen safely.
class SocketService {
  SocketService._();

  static io.Socket? _socket;
  static io.Socket? get socket => _socket;
  static bool get isConnected => _socket?.connected ?? false;

  static final Set<String> _joinedRoomIds = <String>{};
  static final Set<String> _joinedGroupIds = <String>{};

  static bool _hasConnectedOnce = false;
  static bool _isRefreshingAuth = false;
  static _SocketLifecycleObserver? _lifecycleObserver;

  static final _gift = _make<Map<String, dynamic>>();
  static final _balance = _make<Map<String, dynamic>>();
  static final _levelUp = _make<Map<String, dynamic>>();
  static final _roomMsg = _make<Map<String, dynamic>>();
  static final _groupMsg = _make<Map<String, dynamic>>();
  static final _dm = _make<Map<String, dynamic>>();
  static final _messageReaction = _make<Map<String, dynamic>>();
  static final _messageRead = _make<Map<String, dynamic>>();
  static final _reaction = _make<Map<String, dynamic>>();
  static final _sound = _make<Map<String, dynamic>>();
  static final _roomUpdate = _make<Map<String, dynamic>>();
  static final _voice = _make<Map<String, dynamic>>();
  static final _typing = _make<Map<String, dynamic>>();
  static final _friend = _make<Map<String, dynamic>>();
  static final _roomInvite = _make<Map<String, dynamic>>();
  static final _wedding = _make<Map<String, dynamic>>();
  static final _resync = _make<Map<String, dynamic>>();

  static Stream<Map<String, dynamic>> get giftStream => _gift.stream;
  static Stream<Map<String, dynamic>> get balanceStream => _balance.stream;
  static Stream<Map<String, dynamic>> get levelUpStream => _levelUp.stream;
  static Stream<Map<String, dynamic>> get roomMessageStream => _roomMsg.stream;
  static Stream<Map<String, dynamic>> get groupMessageStream =>
      _groupMsg.stream;
  static Stream<Map<String, dynamic>> get dmStream => _dm.stream;
  static Stream<Map<String, dynamic>> get messageReactionStream =>
      _messageReaction.stream;
  static Stream<Map<String, dynamic>> get messageReadStream =>
      _messageRead.stream;
  static Stream<Map<String, dynamic>> get reactionStream => _reaction.stream;
  static Stream<Map<String, dynamic>> get soundStream => _sound.stream;
  static Stream<Map<String, dynamic>> get roomUpdateStream =>
      _roomUpdate.stream;
  static Stream<Map<String, dynamic>> get voiceStream => _voice.stream;
  static Stream<Map<String, dynamic>> get typingStream => _typing.stream;
  static Stream<Map<String, dynamic>> get friendStream => _friend.stream;
  static Stream<Map<String, dynamic>> get roomInviteStream =>
      _roomInvite.stream;
  static Stream<Map<String, dynamic>> get weddingStream => _wedding.stream;
  static Stream<Map<String, dynamic>> get resyncStream => _resync.stream;

  static Future<void> init() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('SocketService.init skipped: no auth token');
      return;
    }

    _ensureLifecycleObserver();

    if (_socket != null) {
      _applyAuthToken(token);
      if (_socket?.connected != true) {
        _socket?.connect();
      }
      return;
    }

    final socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(15)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .setTimeout(15000)
          .build(),
    );

    _socket = socket;
    _wireLifecycleHooks(socket);
    _wireEvents(socket);
  }

  static Future<void> dispose() async {
    await _tearDown(clearMemberships: true);
  }

  static void disconnect() {
    _socket?.disconnect();
  }

  static void joinRoom(String roomId) {
    if (roomId.isEmpty) return;
    _joinedRoomIds.add(roomId);
    _socket?.emit('join_room', roomId);
  }

  static void leaveRoom(String roomId) {
    if (roomId.isEmpty) return;
    _joinedRoomIds.remove(roomId);
    _socket?.emit('leave_room', roomId);
  }

  static void joinGroup(String groupId) {
    if (groupId.isEmpty) return;
    _joinedGroupIds.add(groupId);
    _socket?.emit('group:join', {'groupId': groupId});
  }

  static void leaveGroup(String groupId) {
    if (groupId.isEmpty) return;
    _joinedGroupIds.remove(groupId);
    _socket?.emit('group:leave', {'groupId': groupId});
  }

  static void sendRoomMessage({
    required String roomId,
    required String content,
    String type = 'text',
  }) {
    _socket?.emit(
      'room:message',
      {'roomId': roomId, 'content': content, 'type': type},
    );
  }

  static void sendReaction({
    required String roomId,
    required String emoji,
    int? seatIndex,
  }) {
    _socket?.emit('room:reaction', {
      'roomId': roomId,
      'emoji': emoji,
      if (seatIndex != null) 'seatIndex': seatIndex,
    });
  }

  static void sendSoundEffect({
    required String roomId,
    required String soundId,
    int? seatIndex,
  }) {
    _socket?.emit('room:sound_effect', {
      'roomId': roomId,
      'soundId': soundId,
      if (seatIndex != null) 'seatIndex': seatIndex,
    });
  }

  static void sendVoiceMute({required String roomId, required bool muted}) {
    _socket?.emit('voice:mute', {'roomId': roomId, 'muted': muted});
  }

  static void sendVoiceSpeaking({
    required String roomId,
    required bool speaking,
  }) {
    _socket?.emit('voice:speaking', {'roomId': roomId, 'speaking': speaking});
  }

  static void sendTyping({
    String? roomId,
    String? groupId,
    String? recipientId,
    required bool isTyping,
  }) {
    _socket?.emit('typing', {
      if (roomId != null) 'roomId': roomId,
      if (groupId != null) 'groupId': groupId,
      if (recipientId != null) 'recipientId': recipientId,
      'isTyping': isTyping,
    });
  }

  static void sendHeartbeat({required String roomId}) {
    _socket?.emit('room:heartbeat', {'roomId': roomId});
  }

  static void sendRoomInvite({
    required String roomId,
    required String targetUserId,
    String? roomName,
  }) {
    _socket?.emit('room:invite', {
      'roomId': roomId,
      'targetUserId': targetUserId,
      'roomName': roomName ?? '',
    });
  }

  static void sendGiftViaSocket({
    required String toUserId,
    required String giftId,
    String? roomId,
  }) {
    _socket?.emit('send_gift', {
      'toUserId': toUserId,
      'giftId': giftId,
      if (roomId != null) 'roomId': roomId,
    });
  }

  static void rallyFans({required String roomId, String? roomName}) {
    _socket?.emit(
      'room:rally_fans',
      {'roomId': roomId, 'roomName': roomName ?? ''},
    );
  }

  static void _wireLifecycleHooks(io.Socket socket) {
    socket
      ..onConnect((_) => _handleConnected())
      ..onDisconnect((reason) {
        debugPrint('Socket disconnected: $reason');
      })
      ..onReconnectAttempt((count) {
        debugPrint('Socket reconnect attempt #$count');
      })
      ..onReconnect((_) {
        debugPrint('Socket reconnected');
      })
      ..onConnectError((details) {
        debugPrint('Socket connect error: $details');
        if (_needsAuthRefresh(details)) {
          unawaited(
            _refreshSocketAuthAndReconnect(reason: 'connect_error'),
          );
        }
      })
      ..onError((details) {
        debugPrint('Socket error: $details');
      });
  }

  static void _wireEvents(io.Socket socket) {
    socket.on('receive_gift', (data) => _add(_gift, data));
    socket.on('balance_update', (data) => _add(_balance, data));
    socket.on('level_up', (data) => _add(_levelUp, data));
    socket.on('room:message', (data) => _add(_roomMsg, data));
    socket.on('group:message', (data) => _add(_groupMsg, data));
    socket.on('dm:received', (data) => _add(_dm, data));
    socket.on('message:reaction', (data) => _add(_messageReaction, data));
    socket.on('message:read', (data) => _add(_messageRead, data));
    socket.on('room:reaction', (data) => _add(_reaction, data));
    socket.on('room:sound_effect', (data) => _add(_sound, data));
    socket.on(
      'room:created',
      (data) => _add(_roomUpdate, _typed(data, 'room_created')),
    );
    socket.on(
      'room:deleted',
      (data) => _add(_roomUpdate, _typed(data, 'room_deleted')),
    );
    socket.on(
      'room:lobby:update',
      (data) => _add(_roomUpdate, _typed(data, 'lobby_update')),
    );
    socket.on(
      'room:updated',
      (data) => _add(_roomUpdate, _typed(data, 'room_updated')),
    );
    socket.on(
      'room:participant:joined',
      (data) => _add(_roomUpdate, _typed(data, 'participant_joined')),
    );
    socket.on(
      'room:participant:left',
      (data) => _add(_roomUpdate, _typed(data, 'participant_left')),
    );
    socket.on(
      'room:participant:muted',
      (data) => _add(_roomUpdate, _typed(data, 'participant_muted')),
    );
    socket.on(
      'room:seat_locked',
      (data) => _add(_roomUpdate, _typed(data, 'seat_locked')),
    );
    socket.on(
      'room:seat_unlocked',
      (data) => _add(_roomUpdate, _typed(data, 'seat_unlocked')),
    );
    socket.on(
      'room:rally_fans',
      (data) => _add(_roomUpdate, _typed(data, 'rally_fans')),
    );
    socket.on(
      'user_joined',
      (data) => _add(_roomUpdate, _typed(data, 'user_joined')),
    );
    socket.on(
      'user_left',
      (data) => _add(_roomUpdate, _typed(data, 'user_left')),
    );
    socket.on(
      'user:kicked',
      (data) => _add(_roomUpdate, _typed(data, 'user_kicked')),
    );
    socket.on(
      'user:banned',
      (data) => _add(_roomUpdate, _typed(data, 'user_banned')),
    );
    socket.on('voice:mute', (data) => _add(_voice, _typed(data, 'mute')));
    socket.on(
      'voice:speaking',
      (data) => _add(_voice, _typed(data, 'speaking')),
    );
    socket.on('typing', (data) => _add(_typing, data));
    socket.on(
      'friend_request_received',
      (data) => _add(_friend, _typed(data, 'friend_request_received')),
    );
    socket.on(
      'friend_request_accepted',
      (data) => _add(_friend, _typed(data, 'friend_request_accepted')),
    );
    socket.on(
      'friend_request_rejected',
      (data) => _add(_friend, _typed(data, 'friend_request_rejected')),
    );
    socket.on(
      'friend_removed',
      (data) => _add(_friend, _typed(data, 'friend_removed')),
    );
    socket.on(
      'friend:online',
      (data) => _add(_friend, _typed(data, 'friend_online')),
    );
    socket.on(
      'friend:offline',
      (data) => _add(_friend, _typed(data, 'friend_offline')),
    );
    socket.on('room:invite', (data) => _add(_roomInvite, data));
    socket.on(
      'wedding:proposal',
      (data) => _add(_wedding, _typed(data, 'proposal')),
    );
    socket.on(
      'wedding:proposal_sent',
      (data) => _add(_wedding, _typed(data, 'proposal_sent')),
    );
    socket.on(
      'wedding:accepted',
      (data) => _add(_wedding, _typed(data, 'accepted')),
    );
    socket.on(
      'wedding:rejected',
      (data) => _add(_wedding, _typed(data, 'rejected')),
    );
    socket.on(
      'wedding:divorced',
      (data) => _add(_wedding, _typed(data, 'divorced')),
    );
    socket.on(
      'wedding:blessing',
      (data) => _add(_wedding, _typed(data, 'blessing')),
    );
    socket.on('vip_activated', (data) => _add(_balance, data));
  }

  static void _handleConnected() {
    final isReconnect = _hasConnectedOnce;
    _hasConnectedOnce = true;
    debugPrint(
      isReconnect
          ? 'Socket connected after reconnect (${_socket?.id})'
          : 'Socket connected (${_socket?.id})',
    );
    _rejoinTrackedMemberships();
    _emitResync(isReconnect ? 'reconnected' : 'connected');
  }

  static void _rejoinTrackedMemberships() {
    for (final roomId in _joinedRoomIds) {
      _socket?.emit('join_room', roomId);
    }
    for (final groupId in _joinedGroupIds) {
      _socket?.emit('group:join', {'groupId': groupId});
    }
  }

  static void _emitResync(String reason) {
    _add(_resync, {
      'type': 'socket_resync',
      'reason': reason,
      'rooms': _joinedRoomIds.toList(growable: false),
      'groups': _joinedGroupIds.toList(growable: false),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> _refreshSocketAuthAndReconnect({
    required String reason,
  }) async {
    if (_isRefreshingAuth) return;
    _isRefreshingAuth = true;

    try {
      final refreshed = await AuthService.refreshSession();
      if (!refreshed) {
        debugPrint('Socket auth refresh failed after $reason');
        await _tearDown(clearMemberships: true);
        return;
      }

      final token = await AuthService.getToken();
      if (token == null || token.isEmpty || _socket == null) {
        return;
      }

      _applyAuthToken(token);
      _socket!
        ..disconnect()
        ..connect();
    } finally {
      _isRefreshingAuth = false;
    }
  }

  static void _applyAuthToken(String token) {
    final options = _socket?.io.options;
    if (options == null) return;

    options['auth'] = {'token': token};
    options['extraHeaders'] = {
      'Authorization': 'Bearer $token',
    };
  }

  static bool _needsAuthRefresh(dynamic details) {
    final text = details?.toString().toLowerCase() ?? '';
    return text.contains('invalid token') ||
        text.contains('authentication required') ||
        text.contains('jwt') ||
        text.contains('unauthorized');
  }

  static void _ensureLifecycleObserver() {
    if (_lifecycleObserver != null) return;
    _lifecycleObserver = _SocketLifecycleObserver();
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
  }

  static void _handleAppLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _socket != null) {
      if (_socket?.connected != true) {
        _socket?.connect();
      } else {
        _emitResync('app_resumed');
      }
    }
  }

  static Future<void> _tearDown({bool clearMemberships = false}) async {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _hasConnectedOnce = false;
    _isRefreshingAuth = false;

    if (clearMemberships) {
      _joinedRoomIds.clear();
      _joinedGroupIds.clear();
    }

    if (clearMemberships && _lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
  }

  static StreamController<T> _make<T>() => StreamController<T>.broadcast();

  static void _add<T>(StreamController<T> controller, dynamic raw) {
    if (controller.isClosed) return;
    try {
      controller
          .add(raw is Map ? Map<String, dynamic>.from(raw) as T : raw as T);
    } catch (error) {
      debugPrint('SocketService stream add error: $error');
    }
  }

  static Map<String, dynamic> _typed(dynamic raw, String type) {
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    data['_eventType'] = type;
    return data;
  }
}

class _SocketLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    SocketService._handleAppLifecycle(state);
  }
}
