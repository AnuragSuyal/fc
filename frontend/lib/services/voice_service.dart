import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import 'socket_service.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();

  factory VoiceService() => _instance;

  VoiceService._internal();

  Room? _room;
  LocalParticipant? _localParticipant;
  String? _currentRoomId;
  bool? _lastReportedSpeaking;
  EventsListener<RoomEvent>? _roomListener;
  final Set<String> _locallyMutedParticipantIds = <String>{};
  bool _speakerEnabled = true;
  double _remotePlaybackVolume = 1.0;
  bool _remotePlaybackMuted = false;

  Room? get room => _room;
  LocalParticipant? get localParticipant => _localParticipant;
  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  bool get isMicEnabled => _localParticipant?.isMicrophoneEnabled() ?? false;
  bool get isSpeakerEnabled => _room?.speakerOn ?? _speakerEnabled;
  double get remotePlaybackVolume => _remotePlaybackVolume;
  bool get isRemotePlaybackMuted => _remotePlaybackMuted;

  bool isParticipantMutedLocally(String participantId) =>
      _locallyMutedParticipantIds.contains(participantId);

  final _speakingCtrl = StreamController<bool>.broadcast();
  Stream<bool> get speakingStream => _speakingCtrl.stream;

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

  Future<void> connectToRoom(String url, String token, {String? roomId}) async {
    if (isConnected) {
      await disconnect(clearLocalMutedParticipants: false);
    }

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      throw Exception('Microphone permission denied');
    }

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
    _bindRoomEvents(room);

    if (!kIsWeb) {
      await room.setSpeakerOn(_speakerEnabled);
    }

    await _applyAllLocalMutePreferences(room);
    await _localParticipant?.setMicrophoneEnabled(true);

    if (!kIsWeb) {
      await _startBg();
    }

    debugPrint('VoiceService connected to: ${room.name}');
  }

  void _onRoomChanged() {
    if (_locallyMutedParticipantIds.isNotEmpty ||
        _remotePlaybackMuted ||
        _remotePlaybackVolume < 0.99) {
      unawaited(_applyAllLocalMutePreferences());
    }

    final speaking = _localParticipant?.isSpeaking ?? false;
    if (_lastReportedSpeaking == speaking) {
      return;
    }

    _lastReportedSpeaking = speaking;
    _speakingCtrl.add(speaking);
    if (_currentRoomId != null) {
      SocketService.sendVoiceSpeaking(
        roomId: _currentRoomId!,
        speaking: speaking,
      );
    }
  }

  Future<void> setMicEnabled(bool enabled) async {
    final current = _localParticipant?.isMicrophoneEnabled() ?? false;
    if (current == enabled) {
      return;
    }

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

  Future<void> setSpeakerEnabled(bool enabled) async {
    _speakerEnabled = enabled;
    final room = _room;
    if (room == null) {
      return;
    }

    if (!kIsWeb) {
      await room.setSpeakerOn(enabled);
    }
  }

  Future<bool> toggleSpeaker() async {
    final next = !isSpeakerEnabled;
    await setSpeakerEnabled(next);
    return isSpeakerEnabled;
  }

  Future<void> setRemotePlaybackVolume(double volume) async {
    final clampedVolume = volume.clamp(0.0, 1.0).toDouble();
    _remotePlaybackVolume = clampedVolume;
    if (clampedVolume > 0) {
      _remotePlaybackMuted = false;
    }
    await _applyAllLocalMutePreferences();
  }

  Future<void> setRemotePlaybackMuted(bool muted) async {
    _remotePlaybackMuted = muted;
    await _applyAllLocalMutePreferences();
  }

  Future<void> setParticipantMutedLocally(
    String participantId,
    bool muted,
  ) async {
    if (participantId.isEmpty) {
      return;
    }

    if (muted) {
      _locallyMutedParticipantIds.add(participantId);
    } else {
      _locallyMutedParticipantIds.remove(participantId);
    }

    await _applyParticipantAudioPreference(participantId);
  }

  Future<void> disconnect({bool clearLocalMutedParticipants = true}) async {
    await _roomListener?.dispose();
    _roomListener = null;

    _room?.removeListener(_onRoomChanged);
    await _room?.disconnect();

    _room = null;
    _localParticipant = null;
    _currentRoomId = null;
    _lastReportedSpeaking = null;

    if (clearLocalMutedParticipants) {
      _locallyMutedParticipantIds.clear();
    }

    if (!kIsWeb) {
      await _stopBg();
    }

    debugPrint('VoiceService disconnected');
  }

  void _bindRoomEvents(Room room) {
    unawaited(_roomListener?.dispose());

    final listener = room.createListener()
      ..on<RoomConnectedEvent>((_) async {
        await _applyAllLocalMutePreferences(room);
      })
      ..on<RoomReconnectedEvent>((_) async {
        await _applyAllLocalMutePreferences(room);
      })
      ..on<ParticipantConnectedEvent>((event) async {
        await _applyParticipantAudioPreference(
          event.participant.identity,
          room: room,
        );
      })
      ..on<TrackSubscribedEvent>((event) async {
        final track = event.track;
        if (track is! RemoteAudioTrack) {
          return;
        }

        await _applyAudioPreferenceForTrack(
          participantId: event.participant.identity,
          track: track,
        );
      });

    _roomListener = listener;
  }

  Future<void> _applyAllLocalMutePreferences([Room? room]) async {
    final activeRoom = room ?? _room;
    if (activeRoom == null) {
      return;
    }

    for (final participantId in activeRoom.remoteParticipants.keys) {
      await _applyParticipantAudioPreference(participantId, room: activeRoom);
    }
  }

  Future<void> _applyParticipantAudioPreference(
    String participantId, {
    Room? room,
  }) async {
    if (participantId.isEmpty) {
      return;
    }

    final activeRoom = room ?? _room;
    final participant = activeRoom?.remoteParticipants[participantId];
    if (participant == null) {
      return;
    }

    for (final publication in participant.audioTrackPublications) {
      final track = publication.track;
      if (track == null) {
        continue;
      }

      await _applyAudioPreferenceForTrack(
        participantId: participantId,
        track: track,
      );
    }
  }

  Future<void> _applyAudioPreferenceForTrack({
    required String participantId,
    required RemoteAudioTrack track,
  }) async {
    final mutedOnDevice = _locallyMutedParticipantIds.contains(participantId);
    if (mutedOnDevice) {
      await track.disable();
    } else {
      await track.enable();
    }

    if (kIsWeb) {
      return;
    }

    final effectiveVolume =
        mutedOnDevice || _remotePlaybackMuted ? 0.0 : _remotePlaybackVolume;
    try {
      await rtc.Helper.setVolume(
        effectiveVolume.clamp(0.0, 1.0).toDouble(),
        track.mediaStreamTrack,
      );
    } catch (e) {
      debugPrint('Remote playback volume update failed: $e');
    }
  }

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
  static void _bgStart(ServiceInstance service) {
    service.on('stopService').listen((_) => service.stopSelf());
  }

  @pragma('vm:entry-point')
  static Future<bool> _bgIos(ServiceInstance service) async => true;
}
