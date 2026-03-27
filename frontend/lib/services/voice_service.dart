import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'socket_service.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  Room? _room;
  LocalParticipant? _localParticipant;
  String? _currentRoomId;
  bool? _lastReportedSpeaking;

  Room? get room => _room;
  LocalParticipant? get localParticipant => _localParticipant;
  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  bool get isMicEnabled => _localParticipant?.isMicrophoneEnabled() ?? false;
  bool get isSpeakerEnabled => _room?.speakerOn ?? true;

  final _speakingCtrl = StreamController<bool>.broadcast();
  Stream<bool> get speakingStream => _speakingCtrl.stream;

  // ── Audio session ──────────────────────────────────────────────────────────
  Future<void> initAudio() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
    await session.setActive(true);
  }

  // ── Connect ────────────────────────────────────────────────────────────────
  Future<void> connectToRoom(String url, String token, {String? roomId}) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) throw Exception('Microphone permission denied');

    await initAudio();

    final room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        stopLocalTrackOnUnpublish: true,
      ),
    );
    room.addListener(_onRoomChanged);
    await room.connect(url, token);

    _room = room;
    _localParticipant = room.localParticipant;
    _currentRoomId = roomId;
    _lastReportedSpeaking = _localParticipant?.isSpeaking ?? false;

    await _localParticipant?.setMicrophoneEnabled(true);

    if (!kIsWeb) await _startBg();
    debugPrint('✅ VoiceService connected to: ${room.name}');
  }

  void _onRoomChanged() {
    final speaking = _localParticipant?.isSpeaking ?? false;
    if (_lastReportedSpeaking == speaking) return;

    _lastReportedSpeaking = speaking;
    _speakingCtrl.add(speaking);
    if (_currentRoomId != null) {
      SocketService.sendVoiceSpeaking(
        roomId: _currentRoomId!,
        speaking: speaking,
      );
    }
  }

  // ── Mic control ────────────────────────────────────────────────────────────
  Future<void> setMicEnabled(bool enabled) async {
    final current = _localParticipant?.isMicrophoneEnabled() ?? false;
    if (current == enabled) return;

    await _localParticipant?.setMicrophoneEnabled(enabled);
    if (_currentRoomId != null) {
      SocketService.sendVoiceMute(roomId: _currentRoomId!, muted: !enabled);
    }
  }

  Future<bool> toggleMic() async {
    final current = _localParticipant?.isMicrophoneEnabled() ?? false;
    await setMicEnabled(!current);
    return !current;
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────
  Future<void> setSpeakerEnabled(bool enabled) async {
    final room = _room;
    if (room == null) return;

    if (!kIsWeb) {
      await room.setSpeakerOn(enabled);
    }
  }

  Future<bool> toggleSpeaker() async {
    final next = !isSpeakerEnabled;
    await setSpeakerEnabled(next);
    return next;
  }

  Future<void> disconnect() async {
    _room?.removeListener(_onRoomChanged);
    await _room?.disconnect();
    _room = null;
    _localParticipant = null;
    _currentRoomId = null;
    _lastReportedSpeaking = null;
    if (!kIsWeb) await _stopBg();
    debugPrint('🔌 VoiceService disconnected');
  }

  // ── Background service ─────────────────────────────────────────────────────
  Future<void> _startBg() async {
    try {
      final svc = FlutterBackgroundService();
      if (!await svc.isRunning()) {
        await svc.configure(
          androidConfiguration: AndroidConfiguration(
            onStart: _bgStart,
            autoStart: false,
            isForegroundMode: true,
            notificationChannelId: 'fc_voice_channel',
            initialNotificationTitle: 'Friend Circle Voice',
            initialNotificationContent: 'Voice chat is active',
          ),
          iosConfiguration: IosConfiguration(
            autoStart: false,
            onForeground: _bgStart,
            onBackground: _bgIos,
          ),
        );
        await svc.startService();
      }
    } catch (e) {
      debugPrint('BG service start error: $e');
    }
  }

  Future<void> _stopBg() async {
    try {
      FlutterBackgroundService().invoke('stopService');
    } catch (_) {}
  }

  @pragma('vm:entry-point')
  static void _bgStart(ServiceInstance s) {
    s.on('stopService').listen((_) => s.stopSelf());
  }

  @pragma('vm:entry-point')
  static Future<bool> _bgIos(ServiceInstance s) async => true;
}
