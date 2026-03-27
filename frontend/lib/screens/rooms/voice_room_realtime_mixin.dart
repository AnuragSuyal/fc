import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/socket_service.dart';

/// Mix into any room screen State to receive all Socket.IO room events.
mixin VoiceRoomRealtimeMixin<T extends StatefulWidget> on State<T> {
  final List<StreamSubscription> _roomSubs = [];

  String? get watchedRoomId;

  void onRoomUpdated(Map<String, dynamic> data)  {}
  void onRoomMessage(Map<String, dynamic> data)  {}
  void onRoomReaction(Map<String, dynamic> data) {}
  void onSoundEffect(Map<String, dynamic> data)  {}
  void onVoiceEvent(Map<String, dynamic> data)   {}
  void onGiftReceived(Map<String, dynamic> data) {}

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribeRoomEvents());
  }

  void _subscribeRoomEvents() {
    _roomSubs.add(SocketService.roomUpdateStream.listen((d) { if (mounted) onRoomUpdated(d); }));
    _roomSubs.add(SocketService.roomMessageStream.listen((d) {
      if (!mounted) return;
      final id = watchedRoomId;
      if (id == null || d['roomId']?.toString() == id || d['roomId'] == null) onRoomMessage(d);
    }));
    _roomSubs.add(SocketService.reactionStream.listen((d) { if (mounted) onRoomReaction(d); }));
    _roomSubs.add(SocketService.soundStream.listen((d)    { if (mounted) onSoundEffect(d);  }));
    _roomSubs.add(SocketService.voiceStream.listen((d)    { if (mounted) onVoiceEvent(d);   }));
    _roomSubs.add(SocketService.giftStream.listen((d) {
      if (!mounted) return;
      final id = watchedRoomId;
      if (id == null || d['roomId']?.toString() == id) onGiftReceived(d);
    }));
  }

  @override
  void dispose() {
    for (final s in _roomSubs) {
      s.cancel();
    }
    _roomSubs.clear();
    super.dispose();
  }
}




