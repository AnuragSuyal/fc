import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/active_room_session_controller.dart';
import '../../providers/golden_dragon_session_controller.dart';
import '../../providers/mini_draw_session_controller.dart';
import '../../services/room_service.dart';
import '../../models/golden_dragon_model.dart';
import '../../models/room_model.dart';
import '../../models/shop_models.dart';
import '../../models/user_model.dart';
import '../../models/level_progress_model.dart';
import '../../models/vip_model.dart';
import '../../utils/constants.dart';
import '../../utils/haptics_util.dart';
import '../../utils/room_permissions.dart';
import '../../utils/room_presets.dart';
import '../../utils/shop_appearance_resolver.dart';
import '../../services/socket_service.dart';
import '../../widgets/app_search_icon.dart';
import '../../widgets/currency_icon.dart';
import '../../widgets/gifting/gift_bottom_sheet.dart';
import '../../widgets/gifting/gift_animation_overlay.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/level_badge.dart';
import '../../widgets/vip/vip_badge.dart';
import '../../widgets/vip/vip_name_text.dart';
import '../../widgets/rooms/room_info_bottom_sheet.dart';
import '../../widgets/rooms/room_members_bottom_sheet.dart';
import 'room_settings_screen.dart';
import '../../widgets/rooms/room_control_bottom_sheet.dart';
import '../../widgets/rooms/room_feature_bottom_sheet.dart';
import '../../widgets/rooms/room_feature_overlay.dart';
import '../../widgets/rooms/invite_friends_bottom_sheet.dart';
import '../../widgets/rooms/golden_dragon_activation_sheet.dart';
import '../../widgets/rooms/golden_dragon_overlay.dart';
import '../../widgets/rooms/mini_draw_overlay.dart';
import '../../widgets/rooms/room_seat_tile.dart';
import '../../widgets/rooms/user_profile_bottom_sheet.dart';
import 'package:flutter/services.dart';
import '../../widgets/rooms/reaction_quick_panel.dart';
import '../../widgets/rooms/reaction_animation_overlay.dart';
// import '../../widgets/rooms/seat_reaction_overlay.dart'; // No longer needed locally
import '../../widgets/rooms/gift_sound_bottom_sheet.dart';
import '../../services/voice_service.dart';
import '../../services/message_service.dart';
import '../../services/upload_service.dart';
import '../messages/chat_screen.dart';
import '../profile/enhanced_profile_screen.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as ep;
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as ypi;

class RoomDetailScreen extends StatefulWidget {
  final RoomModel room;

  const RoomDetailScreen({super.key, required this.room});

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

enum _RoomExitDecision { leave, background, closeOnly }

class _RoomDetailScreenState extends State<RoomDetailScreen>
    with WidgetsBindingObserver {
  late final ActiveRoomSessionController _activeRoomSessionController;
  late final GoldenDragonSessionController _goldenDragonController;
  late final MiniDrawSessionController _miniDrawController;
  late RoomModel _room;
  final bool _isLoading = false;
  bool _isJoining = false;
  bool _isExiting = false;
  bool _keepRoomSessionAliveOnDispose = false;
  bool _hasJoinedSocketRoom = false;
  bool _isVoiceConnected = false;
  bool _isConnectingVoice = false;
  String? _roomErrorMessage;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _chatMessages = [];
  final ValueNotifier<int> _chatRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _stageRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _headerRevision = ValueNotifier<int>(0);
  StreamSubscription? _messageSubscription;
  StreamSubscription? _updateSubscription;
  StreamSubscription? _voiceSubscription;
  StreamSubscription? _roomFeatureSubscription;
  StreamSubscription? _resyncSubscription;
  bool _isMuted = true;
  bool _isSpeakerOn = true;
  final VoiceService _voiceService = VoiceService();
  Timer? _heartbeatTimer;
  Timer? _roomRefreshTimer;
  DateTime? _lastReactionTime;
  ypi.YoutubePlayerController? _youtubeController;
  StreamSubscription<ypi.YoutubePlayerValue>? _youtubeValueSubscription;
  StreamSubscription<ypi.YoutubeVideoState>? _youtubeVideoStateSubscription;
  final AudioPlayer _roomAudioPlayer = AudioPlayer();
  final yt.YoutubeExplode _youtubeExplode = yt.YoutubeExplode();
  final Set<ypi.YoutubePlayerController> _pendingYoutubeDisposals = {};
  ypi.YoutubePlayerValue _youtubePlayerValue = ypi.YoutubePlayerValue();
  ypi.YoutubeVideoState _youtubeVideoState = const ypi.YoutubeVideoState();
  String? _activeYoutubeId;
  int _activeYoutubeSessionVersion = 0;
  String? _activeAudioUrl;
  Timer? _youtubeSyncDebounceTimer;
  Timer? _youtubePlaybackRecoveryTimer;
  String? _lastObservedYoutubePlaybackState;
  int? _lastObservedYoutubePositionMs;
  DateTime? _lastObservedYoutubeAt;
  bool _isApplyingYoutubeRemoteSync = false;
  bool _isSendingYoutubeSync = false;
  Map<String, dynamic>? _pendingYoutubeSyncPayload;
  DateTime? _pauseYoutubeLocalSyncUntil;
  bool _isYoutubePickerOpen = false;
  bool _showQuickReactions = false;
  bool _isRefreshingRoom = false;
  bool _hasPendingRoomRefresh = false;
  bool _hasAttemptedAutoJoin = false;
  bool _showYoutubePlaybackRecovery = false;
  bool _isRecoveringYoutubeError = false;
  bool _showMiniDrawPanel = false;
  int _youtubeErrorRecoveryAttempts = 0;
  String? _youtubeErrorRecoveryVideoId;
  Timer? _youtubeErrorRecoveryTimer;
  bool _isAdvancingYoutubeQueue = false;
  bool _isUpdatingYoutubeQueue = false;
  final double _youtubeLocalVolume = 1.0;
  final bool _youtubeMutedLocally = false;
  Timer? _quickReactionTrayTimer;
  final List<String> _gamePrompts = const [
    'Two truths and a lie',
    'Rapid-fire trivia round',
    'Guess the song intro',
    'Would you rather challenge',
    'Story chain in 20 seconds',
    'Emoji-only storytelling',
  ];
  int _gamePromptIndex = 0;
  int _diceValue = 4;

  String? get _currentUserId =>
      Provider.of<AuthProvider>(context, listen: false).user?.id;
  RoomPermissions get _permissions =>
      RoomPermissions(room: _room, userId: _currentUserId);
  bool get _canSendTextMessages => _permissions.canSendRoomMessages;
  bool get _canShareRoomImages => _permissions.canSendRoomImages;
  bool get _canOpenChatComposer => _canSendTextMessages || _canShareRoomImages;
  bool get _canUseRoomGifts => _permissions.canUseRoomGifts;
  bool get _canControlRoomStream => _permissions.canManageRoomMedia;
  bool get _isRoomInactive => !_room.roomActive;

  // Global Keys for mapping seat positions to global overlay
  final Map<int, GlobalKey> _seatKeyMap = {
    for (int i = 0; i <= 8; i++) i: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeRoomSessionController = Provider.of<ActiveRoomSessionController>(
      context,
      listen: false,
    );
    _room = _activeRoomSessionController.activeRoom?.id == widget.room.id
        ? _activeRoomSessionController.activeRoom!
        : widget.room;
    _goldenDragonController = GoldenDragonSessionController(
      roomId: _room.id,
      currentUserId: _currentUserId,
    );
    _miniDrawController = MiniDrawSessionController(
      initialRoom: _room,
      currentUserId: _currentUserId,
    );
    _syncMediaController(_room);

    _messageSubscription =
        SocketService.roomMessageStream.listen(_handleIncomingRoomMessage);
    _updateSubscription =
        SocketService.roomUpdateStream.listen(_handleRoomUpdate);
    _voiceSubscription = SocketService.voiceStream.listen(_handleVoiceEvent);
    _roomFeatureSubscription =
        SocketService.roomFeatureStream.listen(_handleRoomFeatureEvent);
    _resyncSubscription = SocketService.resyncStream.listen((_) {
      if (!mounted) return;
      _scheduleRoomRefresh(delay: const Duration(milliseconds: 220));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapRoomSession());
    });
  }

  Future<void> _bootstrapRoomSession() async {
    await _activeRoomSessionController.prepareForForegroundRoom(_room);
    if (!mounted) return;

    final attachedRoom = _activeRoomSessionController.attachRoomScreen(_room);
    if (!mounted) return;

    setState(() {
      _room = attachedRoom;
    });
    _miniDrawController.applyRoomSnapshot(_room);
    _syncMediaController(_room);
    _initializeRoom();
    unawaited(_goldenDragonController.ensureEventState(force: true));
    _startHeartbeat();
    await _loadInitialMessages(reset: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      _scheduleRoomRefresh(delay: const Duration(milliseconds: 160));
      if (_room.type == 'video' && (_room.youtubeUrl?.isNotEmpty == true)) {
        _applySharedYoutubeSync(_room, force: true);
      }
    }
  }

  Future<void> _loadInitialMessages({bool reset = false}) async {
    final result = await MessageService.getRoomMessages(_room.id, limit: 40);
    final messages = result['messages'] as List<dynamic>? ?? const [];
    if (!mounted) return;

    if (reset) {
      _chatMessages.clear();
    }
    if (messages.isEmpty) {
      if (reset) {
        _notifyChatChanged();
      }
      return;
    }

    for (final message in messages) {
      _appendChatMessage({
        '_id': message.id,
        'roomId': message.roomId,
        'userId': message.senderId,
        'username': message.senderName,
        'avatar': message.senderAvatar,
        'content': message.content,
        'type': message.type,
        'timestamp': message.createdAt.toIso8601String(),
      }, notify: false);
    }
    _notifyChatChanged();
  }

  void _syncMediaController(RoomModel room) {
    final videoId = _sharedYoutubeVideoId(room);
    final sessionVersion = _sharedYoutubeSessionVersion(room);
    final normalizedAudioUrl =
        _normalizeRoomMediaUrl(room.type == 'music' ? room.musicUrl : null);

    if (videoId == null || videoId.isEmpty) {
      _youtubeValueSubscription?.cancel();
      _youtubeVideoStateSubscription?.cancel();
      _queueYoutubeControllerDispose(_youtubeController);
      _youtubeController = null;
      _youtubePlayerValue = ypi.YoutubePlayerValue();
      _youtubeVideoState = const ypi.YoutubeVideoState();
      _activeYoutubeId = null;
      _activeYoutubeSessionVersion = 0;
      _resetYoutubeErrorRecoveryState();
      _setYoutubePlaybackRecoveryVisible(false);
    } else if (_youtubeController == null ||
        _activeYoutubeId != videoId ||
        _activeYoutubeSessionVersion != sessionVersion) {
      _replaceYoutubeController(
        videoId,
        sessionVersion: sessionVersion,
      );
      return;
    } else if (room.type == 'video') {
      _applySharedYoutubeSync(room, force: true);
      _applyYoutubeLocalAudioPreference();
      _scheduleYoutubePlaybackRecoveryCheck();
    }

    final isLocalAudio = _isDirectAudioUrl(normalizedAudioUrl);

    if (!isLocalAudio) {
      _activeAudioUrl = null;
      unawaited(_roomAudioPlayer.stop());
      return;
    }

    if (_activeAudioUrl != normalizedAudioUrl) {
      _activeAudioUrl = normalizedAudioUrl;
      unawaited(_configureRoomAudio(room));
      return;
    }

    unawaited(_roomAudioPlayer.setLoopMode(
      room.musicLoop ? LoopMode.all : LoopMode.off,
    ));
    if (!_roomAudioPlayer.playing) {
      unawaited(_roomAudioPlayer.play());
    }
  }

  void _replaceYoutubeController(
    String videoId, {
    int? sessionVersion,
  }) {
    final previous = _youtubeController;
    _youtubeValueSubscription?.cancel();
    _youtubeVideoStateSubscription?.cancel();
    final nextSessionVersion = sessionVersion ?? _sharedYoutubeSessionVersion();

    final controller = ypi.YoutubePlayerController(
      params: ypi.YoutubePlayerParams(
        mute: false,
        showControls: true,
        showFullscreenButton: true,
        enableCaption: false,
        strictRelatedVideos: true,
        pointerEvents: ypi.PointerEvents.auto,
      ),
      onWebResourceError: (error) {
        debugPrint('YouTube web resource error: ${error.description}');
        _scheduleYoutubeErrorRecovery();
        _setYoutubePlaybackRecoveryVisible(true);
      },
    );

    if (_activeYoutubeId != videoId) {
      _resetYoutubeErrorRecoveryState();
    }
    _youtubePlayerValue = ypi.YoutubePlayerValue();
    _youtubeVideoState = const ypi.YoutubeVideoState();
    _youtubeValueSubscription = controller.listen(
      _handleYoutubeValueChanged,
      onError: (error) => debugPrint('YouTube value listen error: $error'),
    );
    _youtubeVideoStateSubscription = controller.videoStateStream.listen(
      _handleYoutubeVideoStateChanged,
      onError: (error) =>
          debugPrint('YouTube video state listen error: $error'),
    );

    final startSeconds = _effectiveYoutubePositionMs(_room) / 1000;
    if (_room.youtubePlaybackState == 'paused' && !_canControlRoomStream) {
      unawaited(
        controller.cueVideoById(videoId: videoId, startSeconds: startSeconds),
      );
    } else {
      unawaited(
        controller.loadVideoById(videoId: videoId, startSeconds: startSeconds),
      );
    }

    _youtubeController = controller;
    _activeYoutubeId = videoId;
    _activeYoutubeSessionVersion = nextSessionVersion;
    _showYoutubePlaybackRecovery = false;
    _pauseYoutubeLocalSyncFor(const Duration(milliseconds: 1400));
    _syncYoutubePlayerOverlayInteractivity();
    _lastObservedYoutubePlaybackState = null;
    _lastObservedYoutubePositionMs = null;
    _lastObservedYoutubeAt = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _activeYoutubeId != videoId ||
          _activeYoutubeSessionVersion != nextSessionVersion) {
        return;
      }
      _applyYoutubeLocalAudioPreference();
      _applySharedYoutubeSync(_room, force: true);
      _scheduleYoutubePlaybackRecoveryCheck();
    });
    if (mounted) {
      setState(() {});
    }
    _queueYoutubeControllerDispose(previous);
  }

  void _applyYoutubeLocalAudioPreference() {
    final controller = _youtubeController;
    if (controller == null) return;

    unawaited(_setYoutubeLocalAudioPreference(controller));
  }

  void _handleYoutubePlayerReady() {
    _resetYoutubeErrorRecoveryState();
    _syncYoutubePlayerOverlayInteractivity();
    _applyYoutubeLocalAudioPreference();
    _applySharedYoutubeSync(_room, force: true);
    _scheduleYoutubePlaybackRecoveryCheck();
  }

  void _pauseYoutubeLocalSyncFor(Duration duration) {
    _pauseYoutubeLocalSyncUntil = DateTime.now().add(duration);
  }

  Future<void> _setYoutubePointerEventsEnabled(bool enabled) async {
    final controller = _youtubeController;
    if (controller == null) return;

    final pointerEventsValue = enabled ? 'auto' : 'none';
    try {
      // ignore: invalid_use_of_internal_member
      await controller.webViewController.runJavaScript('''
        document.documentElement.style.pointerEvents = '$pointerEventsValue';
        document.body.style.pointerEvents = '$pointerEventsValue';
      ''');
    } catch (error) {
      debugPrint('YouTube pointer events update skipped: $error');
    }
  }

  void _syncYoutubePlayerOverlayInteractivity() {
    unawaited(_setYoutubePointerEventsEnabled(!_isYoutubePickerOpen));
  }

  String? _mapYoutubePlaybackState(ypi.PlayerState state) {
    switch (state) {
      case ypi.PlayerState.playing:
        return 'playing';
      case ypi.PlayerState.paused:
      case ypi.PlayerState.cued:
      case ypi.PlayerState.ended:
        return 'paused';
      case ypi.PlayerState.unStarted:
      case ypi.PlayerState.buffering:
      case ypi.PlayerState.unknown:
        return null;
    }
  }

  String? _extractYoutubeVideoId(String? url) {
    if (url == null || url.isEmpty) return null;
    return ypi.YoutubePlayerController.convertUrlToId(url);
  }

  String? _sharedYoutubeVideoId([RoomModel? room]) {
    final source = room ?? _room;
    final activeVideoId = source.youtubeActiveVideoId?.trim();
    if (activeVideoId != null && activeVideoId.isNotEmpty) {
      return activeVideoId;
    }
    return _extractYoutubeVideoId(source.youtubeUrl);
  }

  int _sharedYoutubeSessionVersion([RoomModel? room]) {
    final source = room ?? _room;
    return source.youtubeSessionVersion < 0 ? 0 : source.youtubeSessionVersion;
  }

  String _sharedYoutubeSessionKey([RoomModel? room]) {
    final source = room ?? _room;
    return '${_sharedYoutubeVideoId(source) ?? ''}:${_sharedYoutubeSessionVersion(source)}';
  }

  String get _youtubeDisplayTitle {
    final liveTitle = _youtubePlayerValue.metaData.title.trim();
    if (liveTitle.isNotEmpty) {
      return liveTitle;
    }

    final roomTitle = _room.youtubeTitle?.trim();
    if (roomTitle != null && roomTitle.isNotEmpty) {
      return roomTitle;
    }

    return _room.name;
  }

  String _normalizeUiErrorMessage(
    Object error, {
    bool forVoice = false,
  }) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    if (raw.isEmpty) {
      return forVoice
          ? 'Voice is unavailable right now. Please try again.'
          : 'Something went wrong. Please try again.';
    }

    final normalized = raw.toLowerCase();
    if (normalized.contains('microphone permission denied')) {
      return 'Microphone permission is needed to use voice.';
    }
    if (normalized.contains('/rtc/validate') ||
        normalized.contains('failed to fetch') ||
        normalized.contains('clientfailed')) {
      return forVoice
          ? 'Voice server is not reachable on this device right now.'
          : 'The room could not connect right now. Please try again.';
    }
    if (normalized.contains('timeout') || normalized.contains('timed out')) {
      return 'The connection timed out. Please try again.';
    }
    if (normalized.contains('socketexception') ||
        normalized.contains('network error')) {
      return 'Network connection failed. Please try again.';
    }

    final lines = raw
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final singleLine = lines.isNotEmpty ? lines.first : raw;
    if (singleLine.length > 140) {
      return '${singleLine.substring(0, 137)}...';
    }
    return singleLine;
  }

  int _effectiveYoutubePositionMs(RoomModel room) {
    var positionMs = room.youtubePositionMs;
    if (room.isYoutubePlaying && room.youtubeSyncedAt != null) {
      positionMs +=
          DateTime.now().difference(room.youtubeSyncedAt!).inMilliseconds;
    }

    return positionMs < 0 ? 0 : positionMs;
  }

  void _applySharedYoutubeSync(RoomModel room, {bool force = false}) {
    if (_canControlRoomStream && !force) {
      return;
    }

    final targetVideoId = _sharedYoutubeVideoId(room);
    final targetSessionVersion = _sharedYoutubeSessionVersion(room);
    if (room.type != 'video' ||
        targetVideoId == null ||
        targetVideoId.isEmpty ||
        room.youtubeUrl?.isNotEmpty != true) {
      return;
    }

    final controller = _youtubeController;
    if (controller == null) return;

    final currentMetaVideoId = _youtubePlayerValue.metaData.videoId.trim();
    final needsControllerRebind = _activeYoutubeId != targetVideoId ||
        _activeYoutubeSessionVersion != targetSessionVersion ||
        (currentMetaVideoId.isNotEmpty && currentMetaVideoId != targetVideoId);
    if (needsControllerRebind) {
      _replaceYoutubeController(
        targetVideoId,
        sessionVersion: targetSessionVersion,
      );
      return;
    }

    if (_youtubePlayerValue.hasError) {
      unawaited(_recoverYoutubePlayback(forceRebind: true));
      return;
    }

    final targetPlaybackState = room.youtubePlaybackState;
    final targetPositionMs = _effectiveYoutubePositionMs(room);
    final currentPositionMs = _youtubeVideoState.position.inMilliseconds;
    final localPlaybackState =
        _mapYoutubePlaybackState(_youtubePlayerValue.playerState);
    final needsSeek =
        force || (currentPositionMs - targetPositionMs).abs() > 1400;
    final needsPause =
        targetPlaybackState == 'paused' && localPlaybackState == 'playing';
    final needsPlay =
        targetPlaybackState == 'playing' && localPlaybackState != 'playing';

    if (!needsSeek && !needsPause && !needsPlay) {
      return;
    }

    _isApplyingYoutubeRemoteSync = true;
    _pauseYoutubeLocalSyncFor(const Duration(milliseconds: 1400));

    unawaited(() async {
      try {
        if (needsSeek) {
          await controller.seekTo(
            seconds: targetPositionMs / 1000,
            allowSeekAhead: true,
          );
        }

        if (targetPlaybackState == 'playing') {
          await controller.playVideo();
        } else {
          await controller.pauseVideo();
        }

        await _setYoutubeLocalAudioPreference(controller);
        _lastObservedYoutubePlaybackState = targetPlaybackState;
        _lastObservedYoutubePositionMs = targetPositionMs;
        _lastObservedYoutubeAt = DateTime.now();
        _scheduleYoutubePlaybackRecoveryCheck();
      } catch (error) {
        debugPrint('YouTube sync apply skipped: $error');
      } finally {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        _isApplyingYoutubeRemoteSync = false;
      }
    }());
  }

  void _handleYoutubeValueChanged(ypi.YoutubePlayerValue value) {
    final previousValue = _youtubePlayerValue;
    _youtubePlayerValue = value;

    final becameReady = previousValue.playerState == ypi.PlayerState.unknown &&
        value.playerState != ypi.PlayerState.unknown;
    if (becameReady) {
      _handleYoutubePlayerReady();
    }

    if (value.playerState == ypi.PlayerState.playing) {
      _resetYoutubeErrorRecoveryState();
      _setYoutubePlaybackRecoveryVisible(false);
    } else if (value.playerState == ypi.PlayerState.ended) {
      unawaited(_handleYoutubeVideoEnded());
    } else if (!value.hasError) {
      _scheduleYoutubePlaybackRecoveryCheck();
    }

    if (value.hasError) {
      _scheduleYoutubeErrorRecovery();
    }

    if (_canControlRoomStream &&
        previousValue.playerState != value.playerState) {
      _handleYoutubeControllerChanged();
    }

    final shouldRebuild = previousValue.playerState != value.playerState ||
        previousValue.error != value.error ||
        previousValue.metaData.title != value.metaData.title ||
        previousValue.metaData.videoId != value.metaData.videoId;
    if (shouldRebuild && mounted) {
      setState(() {});
    }
  }

  void _handleYoutubeVideoStateChanged(ypi.YoutubeVideoState videoState) {
    _youtubeVideoState = videoState;
    if (_canControlRoomStream) {
      _handleYoutubeControllerChanged();
    }
  }

  void _setYoutubePlaybackRecoveryVisible(bool visible) {
    _youtubePlaybackRecoveryTimer?.cancel();
    if (_showYoutubePlaybackRecovery == visible) {
      return;
    }

    if (!mounted) {
      _showYoutubePlaybackRecovery = visible;
      return;
    }

    setState(() {
      _showYoutubePlaybackRecovery = visible;
    });
  }

  void _scheduleYoutubePlaybackRecoveryCheck() {
    _youtubePlaybackRecoveryTimer?.cancel();

    final shouldCheck = _room.type == 'video' &&
        _activeYoutubeId != null &&
        !_youtubePlayerValue.hasError &&
        _room.youtubePlaybackState == 'playing' &&
        _youtubePlayerValue.playerState != ypi.PlayerState.playing;
    if (!shouldCheck) {
      _setYoutubePlaybackRecoveryVisible(false);
      return;
    }

    _youtubePlaybackRecoveryTimer = Timer(
      const Duration(seconds: 2),
      () => _setYoutubePlaybackRecoveryVisible(
        _room.type == 'video' &&
            _activeYoutubeId != null &&
            !_youtubePlayerValue.hasError &&
            _room.youtubePlaybackState == 'playing' &&
            _youtubePlayerValue.playerState != ypi.PlayerState.playing,
      ),
    );
  }

  void _resetYoutubeErrorRecoveryState() {
    _youtubeErrorRecoveryTimer?.cancel();
    _youtubeErrorRecoveryAttempts = 0;
    _youtubeErrorRecoveryVideoId = null;
    _isRecoveringYoutubeError = false;
  }

  void _scheduleYoutubeErrorRecovery() {
    final videoId = _activeYoutubeId;
    if (videoId == null || _isRecoveringYoutubeError) {
      return;
    }

    if (_youtubeErrorRecoveryVideoId != videoId) {
      _youtubeErrorRecoveryVideoId = videoId;
      _youtubeErrorRecoveryAttempts = 0;
    }

    if (_youtubeErrorRecoveryAttempts >= 2) {
      _setYoutubePlaybackRecoveryVisible(true);
      return;
    }

    if (_youtubeErrorRecoveryTimer?.isActive == true) {
      return;
    }

    _youtubeErrorRecoveryAttempts += 1;
    _isRecoveringYoutubeError = true;
    _youtubeErrorRecoveryTimer = Timer(
      Duration(milliseconds: 500 + (_youtubeErrorRecoveryAttempts * 350)),
      () async {
        await _recoverYoutubePlayback();
        _isRecoveringYoutubeError = false;
      },
    );
  }

  Future<void> _setYoutubeLocalAudioPreference(
    ypi.YoutubePlayerController controller,
  ) async {
    try {
      final volume = (_youtubeLocalVolume * 100).round().clamp(0, 100).toInt();
      await controller.setVolume(volume);
      if (_youtubeMutedLocally || volume == 0) {
        await controller.mute();
      } else {
        await controller.unMute();
      }
    } catch (error) {
      debugPrint('YouTube audio preference skipped: $error');
    }
  }

  Future<void> _recoverYoutubePlayback({bool forceRebind = false}) async {
    final videoId = _sharedYoutubeVideoId();
    if (videoId == null) return;
    final sessionVersion = _sharedYoutubeSessionVersion();
    final currentMetaVideoId = _youtubePlayerValue.metaData.videoId.trim();
    final shouldRebind = forceRebind ||
        _youtubeController == null ||
        _youtubePlayerValue.hasError ||
        _activeYoutubeId != videoId ||
        _activeYoutubeSessionVersion != sessionVersion ||
        (currentMetaVideoId.isNotEmpty && currentMetaVideoId != videoId);

    if (shouldRebind) {
      _replaceYoutubeController(
        videoId,
        sessionVersion: sessionVersion,
      );
      _isRecoveringYoutubeError = false;
      return;
    }

    final controller = _youtubeController;
    if (controller == null) return;

    _pauseYoutubeLocalSyncFor(const Duration(milliseconds: 1200));
    try {
      await controller.seekTo(
        seconds: _effectiveYoutubePositionMs(_room) / 1000,
        allowSeekAhead: true,
      );
      if (_room.youtubePlaybackState == 'playing') {
        await controller.playVideo();
      } else {
        await controller.pauseVideo();
      }
      await _setYoutubeLocalAudioPreference(controller);
      _resetYoutubeErrorRecoveryState();
      _scheduleYoutubePlaybackRecoveryCheck();
    } catch (error) {
      debugPrint('YouTube playback recovery skipped: $error');
    } finally {
      _isRecoveringYoutubeError = false;
    }
  }

  bool _didYoutubePositionJump({
    required int positionMs,
    required String playbackState,
    required DateTime observedAt,
  }) {
    final previousPositionMs = _lastObservedYoutubePositionMs;
    final previousObservedAt = _lastObservedYoutubeAt;
    if (previousPositionMs == null || previousObservedAt == null) {
      return false;
    }

    final previousState = _lastObservedYoutubePlaybackState;
    final elapsedMs = observedAt.difference(previousObservedAt).inMilliseconds;
    final expectedPositionMs = previousState == 'playing'
        ? previousPositionMs + elapsedMs
        : previousPositionMs;
    final thresholdMs = playbackState == 'playing' ? 1800 : 900;
    return (positionMs - expectedPositionMs).abs() > thresholdMs;
  }

  void _handleYoutubeControllerChanged() {
    if (!_canControlRoomStream || _room.type != 'video') {
      return;
    }

    if (_isYoutubePickerOpen) {
      return;
    }

    if (_isApplyingYoutubeRemoteSync) {
      return;
    }

    final pauseUntil = _pauseYoutubeLocalSyncUntil;
    if (pauseUntil != null && DateTime.now().isBefore(pauseUntil)) {
      return;
    }

    if (_youtubePlayerValue.hasError) {
      return;
    }

    if (_youtubePlayerValue.playerState == ypi.PlayerState.ended) {
      return;
    }

    final playbackState =
        _mapYoutubePlaybackState(_youtubePlayerValue.playerState);
    if (playbackState == null) {
      return;
    }

    final observedAt = DateTime.now();
    final positionMs = _youtubeVideoState.position.inMilliseconds;
    final stateChanged = playbackState != _lastObservedYoutubePlaybackState;
    final positionJumped = _didYoutubePositionJump(
      positionMs: positionMs,
      playbackState: playbackState,
      observedAt: observedAt,
    );

    _lastObservedYoutubePlaybackState = playbackState;
    _lastObservedYoutubePositionMs = positionMs;
    _lastObservedYoutubeAt = observedAt;

    if (!stateChanged && !positionJumped) {
      return;
    }

    _queueYoutubePlaybackSync(
      positionMs: positionMs,
      playbackState: playbackState,
    );
  }

  void _queueYoutubePlaybackSync({
    required int positionMs,
    required String playbackState,
  }) {
    _pendingYoutubeSyncPayload = {
      'positionMs': positionMs,
      'playbackState': playbackState,
    };

    _youtubeSyncDebounceTimer?.cancel();
    _youtubeSyncDebounceTimer = Timer(
      const Duration(milliseconds: 420),
      () => unawaited(_flushYoutubePlaybackSync()),
    );
  }

  Future<void> _flushYoutubePlaybackSync() async {
    if (_isSendingYoutubeSync || !_canControlRoomStream || !mounted) {
      return;
    }

    final pendingPayload = _pendingYoutubeSyncPayload;
    if (pendingPayload == null) {
      return;
    }

    final playbackState =
        pendingPayload['playbackState']?.toString() ?? 'paused';
    final positionMs = pendingPayload['positionMs'] is int
        ? pendingPayload['positionMs'] as int
        : int.tryParse('${pendingPayload['positionMs']}') ?? 0;

    if (_room.youtubePlaybackState == playbackState &&
        (_room.youtubePositionMs - positionMs).abs() < 900) {
      _pendingYoutubeSyncPayload = null;
      return;
    }

    _pendingYoutubeSyncPayload = null;
    _isSendingYoutubeSync = true;

    try {
      final updated = await RoomService.updateRoom(_room.id, {
        'theme': {
          'youtubePlaybackState': playbackState,
          'youtubePositionMs': positionMs,
        },
      });
      if (!mounted || updated == null) return;
      _applyRoomSnapshot(updated);
    } finally {
      _isSendingYoutubeSync = false;
      if (_pendingYoutubeSyncPayload != null) {
        final nextPositionMs = _pendingYoutubeSyncPayload!['positionMs'] is int
            ? _pendingYoutubeSyncPayload!['positionMs'] as int
            : int.tryParse('${_pendingYoutubeSyncPayload!['positionMs']}') ?? 0;
        _queueYoutubePlaybackSync(
          positionMs: nextPositionMs,
          playbackState:
              _pendingYoutubeSyncPayload!['playbackState']?.toString() ??
                  'paused',
        );
      }
    }
  }

  List<RoomYoutubeQueueItem> _currentYoutubeQueueItems() {
    if (_room.youtubeQueue.isNotEmpty) {
      return List<RoomYoutubeQueueItem>.from(_room.youtubeQueue);
    }

    final currentUrl = _room.youtubeUrl;
    if (currentUrl == null || currentUrl.isEmpty) {
      return const <RoomYoutubeQueueItem>[];
    }

    return [
      RoomYoutubeQueueItem(
        videoId: _extractYoutubeVideoId(currentUrl) ?? '',
        url: currentUrl,
        title: _room.youtubeTitle ?? '',
        thumbnailUrl: _room.youtubeThumbnail ?? '',
      ),
    ];
  }

  String _youtubeQueueIdentity({
    required String url,
    String? videoId,
  }) {
    if (videoId != null && videoId.isNotEmpty) {
      return 'id:$videoId';
    }
    return 'url:$url';
  }

  List<Map<String, dynamic>> _youtubeQueuePayload(
    List<RoomYoutubeQueueItem> items,
  ) {
    return items.map((item) => item.toThemeJson()).toList(growable: false);
  }

  Future<void> _updateYoutubeQueue(
    List<RoomYoutubeQueueItem> items, {
    String? playbackState,
    int? positionMs,
    String? successMessage,
  }) async {
    if (_isUpdatingYoutubeQueue) {
      return;
    }

    if (mounted) {
      setState(() {
        _isUpdatingYoutubeQueue = true;
      });
    } else {
      _isUpdatingYoutubeQueue = true;
    }

    try {
      final themePatch = <String, dynamic>{
        'youtubeQueue': _youtubeQueuePayload(items),
      };
      if (playbackState != null) {
        themePatch['youtubePlaybackState'] = playbackState;
      }
      if (positionMs != null) {
        themePatch['youtubePositionMs'] = positionMs;
      }

      final updated = await RoomService.updateRoom(_room.id, {
        'theme': themePatch,
      });
      if (!mounted) return;

      if (updated != null) {
        _applyRoomSnapshot(updated, rebuildPage: true);
        if (successMessage != null && successMessage.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(successMessage)),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update the room playlist.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingYoutubeQueue = false;
        });
      } else {
        _isUpdatingYoutubeQueue = false;
      }
    }
  }

  Future<void> _queueYoutubeOption(
    _YoutubeVideoOption video, {
    required bool playNow,
  }) async {
    final item = RoomYoutubeQueueItem(
      videoId: video.id,
      url: 'https://www.youtube.com/watch?v=${video.id}',
      title: video.title,
      thumbnailUrl: video.thumbnailUrl,
      durationMs: video.duration?.inMilliseconds ?? 0,
      addedBy: _currentUserId ?? '',
      addedAt: DateTime.now(),
    );
    final itemIdentity =
        _youtubeQueueIdentity(url: item.url, videoId: item.videoId);
    final queue = _currentYoutubeQueueItems()
        .where(
          (entry) =>
              _youtubeQueueIdentity(url: entry.url, videoId: entry.videoId) !=
              itemIdentity,
        )
        .toList(growable: true);

    if (playNow) {
      queue.insert(0, item);
    } else {
      queue.add(item);
    }

    await _updateYoutubeQueue(
      queue,
      playbackState: playNow || queue.length == 1 ? 'playing' : null,
      positionMs: playNow || queue.length == 1 ? 0 : null,
      successMessage:
          playNow ? 'Shared video updated.' : 'Video added to the playlist.',
    );
  }

  Future<void> _playQueuedYoutubeItem(RoomYoutubeQueueItem item) async {
    final queue = _currentYoutubeQueueItems().toList(growable: true);
    final itemIdentity =
        _youtubeQueueIdentity(url: item.url, videoId: item.videoId);
    final selectedIndex = queue.indexWhere(
      (entry) =>
          _youtubeQueueIdentity(url: entry.url, videoId: entry.videoId) ==
          itemIdentity,
    );
    if (selectedIndex <= 0) {
      return;
    }

    final selected = queue.removeAt(selectedIndex);
    queue.insert(0, selected);
    await _updateYoutubeQueue(
      queue,
      playbackState: 'playing',
      positionMs: 0,
    );
  }

  Future<void> _removeQueuedYoutubeItem(RoomYoutubeQueueItem item) async {
    final queue = _currentYoutubeQueueItems().toList(growable: true);
    final itemIdentity =
        _youtubeQueueIdentity(url: item.url, videoId: item.videoId);
    final removedCurrent = queue.isNotEmpty &&
        _youtubeQueueIdentity(
              url: queue.first.url,
              videoId: queue.first.videoId,
            ) ==
            itemIdentity;

    queue.removeWhere(
      (entry) =>
          _youtubeQueueIdentity(url: entry.url, videoId: entry.videoId) ==
          itemIdentity,
    );

    await _updateYoutubeQueue(
      queue,
      playbackState:
          removedCurrent ? (queue.isNotEmpty ? 'playing' : 'paused') : null,
      positionMs: removedCurrent ? 0 : null,
      successMessage: 'Video removed from the playlist.',
    );
  }

  Future<void> _handleYoutubeVideoEnded() async {
    if (!_canControlRoomStream || _isAdvancingYoutubeQueue) {
      return;
    }

    _isAdvancingYoutubeQueue = true;
    _pendingYoutubeSyncPayload = null;
    _youtubeSyncDebounceTimer?.cancel();

    try {
      final queue = _currentYoutubeQueueItems();
      if (queue.length > 1) {
        await _updateYoutubeQueue(
          queue.sublist(1),
          playbackState: 'playing',
          positionMs: 0,
        );
        return;
      }

      final controller = _youtubeController;
      if (controller != null) {
        try {
          await controller.seekTo(seconds: 0, allowSeekAhead: true);
          await controller.pauseVideo();
          await _setYoutubeLocalAudioPreference(controller);
        } catch (error) {
          debugPrint('YouTube end reset skipped: $error');
        }
      }

      final updated = await RoomService.updateRoom(_room.id, {
        'theme': {
          'youtubePlaybackState': 'paused',
          'youtubePositionMs': 0,
        },
      });
      if (!mounted || updated == null) return;
      _applyRoomSnapshot(updated, rebuildPage: true);
    } finally {
      _isAdvancingYoutubeQueue = false;
    }
  }

  bool _isDirectAudioUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return _extractYoutubeVideoId(url) == null;
  }

  String? _normalizeRoomMediaUrl(String? url) {
    if (url == null || url.isEmpty || kIsWeb) return url;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return url;
    return AppConfig.normalizeBackendUrl(url);
  }

  void _queueYoutubeControllerDispose(ypi.YoutubePlayerController? controller) {
    if (controller == null || _pendingYoutubeDisposals.contains(controller)) {
      return;
    }

    _pendingYoutubeDisposals.add(controller);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (!_pendingYoutubeDisposals.remove(controller)) return;

        try {
          unawaited(controller.close());
        } catch (error) {
          debugPrint('YouTube controller dispose skipped: $error');
        }
      }),
    );
  }

  Future<void> _configureRoomAudio(RoomModel room) async {
    final audioUrl = _normalizeRoomMediaUrl(room.musicUrl);
    if (!_isDirectAudioUrl(audioUrl)) {
      await _roomAudioPlayer.stop();
      return;
    }

    try {
      await _roomAudioPlayer.setLoopMode(
        room.musicLoop ? LoopMode.all : LoopMode.off,
      );
      await _roomAudioPlayer.setUrl(audioUrl!);
      await _roomAudioPlayer.play();
    } catch (e) {
      debugPrint('Room audio playback failed: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_hasJoinedSocketRoom && SocketService.socket?.connected == true) {
        SocketService.socket?.emit('room:heartbeat', {'roomId': _room.id});
      }
    });
  }

  void _initializeRoom() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?.id ?? '';
    if (userId.isEmpty) return;

    if (_isUserInRoom(userId)) {
      _joinSocketRoom();
      unawaited(_connectToVoice());
      return;
    }

    if (_hasAttemptedAutoJoin) return;
    _hasAttemptedAutoJoin = true;
    unawaited(_attemptAutoJoinOnOpen());
  }

  Future<void> _attemptAutoJoinOnOpen() async {
    await _enterRoom(showFeedback: false, popOnPasswordCancel: true);
  }

  Future<void> _enterRoom({
    bool showFeedback = true,
    bool popOnPasswordCancel = false,
  }) async {
    if (_room.isPrivate) {
      final password = await _promptForRoomPassword();
      if (!mounted) return;
      if (password == null) {
        if (popOnPasswordCancel) {
          Navigator.maybePop(context);
        }
        return;
      }
      _passwordController.text = password;
    }

    await _joinRoom(showFeedback: showFeedback);
  }

  Future<String?> _promptForRoomPassword() async {
    final controller = TextEditingController(text: _passwordController.text);
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('Enter Room Password'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Password',
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (password == null || password.trim().isEmpty) {
      return null;
    }
    return password.trim();
  }

  Future<void> _connectToVoice() async {
    if (_isConnectingVoice) {
      return;
    }

    if (_voiceService.isConnected) {
      if (mounted) {
        setState(() {
          _isMuted = !_voiceService.isMicEnabled;
          _isSpeakerOn = _voiceService.isSpeakerEnabled;
          _isVoiceConnected = true;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isConnectingVoice = true;
      });
    }

    try {
      final tokenResponse = await RoomService.getRoomToken(_room.id);
      final token = tokenResponse['token']?.toString();
      final serverUrl = tokenResponse['serverUrl']?.toString();
      if (token == null || token.isEmpty || serverUrl == null) {
        throw Exception('Voice room token is unavailable');
      }

      final effectiveUrl = AppConfig.normalizeBackendUrl(serverUrl);
      await _voiceService.connectToRoom(
        effectiveUrl,
        token,
        roomId: _room.id,
      );

      if (mounted) {
        setState(() {
          _isMuted = !_voiceService.isMicEnabled;
          _isSpeakerOn = _voiceService.isSpeakerEnabled;
          _isVoiceConnected = true;
          _isConnectingVoice = false;
        });
      }
    } catch (e) {
      debugPrint('Voice connection failed: $e');
      if (!mounted) return;
      final errorMessage = _normalizeUiErrorMessage(e, forVoice: true);
      setState(() {
        _isVoiceConnected = false;
        _isConnectingVoice = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  Future<void> _refreshRoom() async {
    if (_isRefreshingRoom) {
      _hasPendingRoomRefresh = true;
      return;
    }

    _isRefreshingRoom = true;
    try {
      final updated = await RoomService.getRoomById(_room.id);
      if (!mounted || updated == null) return;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?.id ?? '';
      final isInRoom = userId.isNotEmpty && updated.isUserInRoom(userId);

      if (!_hasJoinedSocketRoom && isInRoom) {
        _joinSocketRoom();
      } else if (_hasJoinedSocketRoom && !isInRoom) {
        _leaveSocketRoom();
        unawaited(_voiceService.disconnect());
        _isVoiceConnected = false;
      }

      _applyRoomSnapshot(updated);
    } finally {
      _isRefreshingRoom = false;
      if (_hasPendingRoomRefresh && mounted) {
        _hasPendingRoomRefresh = false;
        _scheduleRoomRefresh(delay: const Duration(milliseconds: 320));
      }
    }
  }

  void _showRoomInfo() {
    final roomInfoListenable = Listenable.merge([
      _headerRevision,
      _stageRevision,
    ]);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AnimatedBuilder(
        animation: roomInfoListenable,
        builder: (context, _) {
          final user = Provider.of<AuthProvider>(context, listen: false).user;
          final isJoined = user != null && _isUserInRoom(user.id);
          final isFollowing = user != null && _room.isFollowedBy(user.id);
          final isRoomOwner = user != null && user.id == _room.hostId;

          return RoomInfoBottomSheet(
            room: _room,
            isJoined: isJoined,
            isFollowing: isFollowing,
            showFollowButton: !isRoomOwner,
            onShare: () {
              Navigator.pop(sheetContext);
              _onShareRoom();
            },
            onPrimaryAction: () {
              Navigator.pop(sheetContext);
              if (!isJoined) {
                _enterRoom();
              }
            },
            onFollowToggle: user == null ? null : _toggleFollowRoom,
            onViewAll: () {
              Navigator.pop(sheetContext);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _showMembers();
                }
              });
            },
          );
        },
      ),
    );
  }

  void _showMembers() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RoomMemberListBottomSheet(
        room: _room,
        onParticipantTap: _onParticipantTap,
      ),
    );
  }

  Future<void> _showSettings() async {
    if (!_permissions.canOpenRoomSettings) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Only the owner and admins can open room settings.')),
      );
      return;
    }

    final updatedRoom = await Navigator.push<RoomModel?>(
      context,
      MaterialPageRoute(builder: (context) => RoomSettingsScreen(room: _room)),
    );

    if (!mounted || updatedRoom == null) return;
    _applyRoomSnapshot(updatedRoom, rebuildPage: true);
  }

  void _showRoomControl() {
    _hideQuickReactionTray();
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    final userPermissions = RoomPermissions(room: _room, userId: user?.id);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => RoomControlBottomSheet(
        room: _room,
        canOpenRoomSettings: userPermissions.canOpenRoomSettings,
        canChangeRoomMode: userPermissions.canManageRoomIdentity,
        canEditAnnouncement: userPermissions.canEditAnnouncement,
        canInviteUsers: userPermissions.canInviteUsers,
        canRallyFans: userPermissions.canRallyFans,
        onExit: () {
          Navigator.pop(sheetContext);
          unawaited(_confirmRoomExit());
        },
        onSettings: () {
          Navigator.pop(sheetContext);
          _showSettings();
        },
        onInvite: () {
          Navigator.pop(sheetContext);
          _showInviteFriends();
        },
        onGiftSound: () {
          Navigator.pop(sheetContext);
          _showGiftSounds();
        },
        onRallyFans: () {
          Navigator.pop(sheetContext);
          _rallyFans();
        },
        onShare: () {
          Navigator.pop(sheetContext);
          _onShareRoom();
        },
        onReport: () {
          Navigator.pop(sheetContext);
          _showReportRoomDialog();
        },
        onAnnouncement: () {
          Navigator.pop(sheetContext);
          _showAnnouncementComposer();
        },
        onVideoSetup: () {
          Navigator.pop(sheetContext);
          _showYouTubePicker();
        },
        onMusicSetup: () {
          Navigator.pop(sheetContext);
          _showMusicSetupSheet();
        },
        onModeChanged: (newType) {
          Navigator.pop(sheetContext);
          _onModeChanged(newType);
        },
      ),
    );
  }

  void _onShareRoom() {
    final roomUrl = 'https://friendcircle.app/room/${_room.id}';
    Clipboard.setData(ClipboardData(text: roomUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Room link copied to clipboard!'),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  void _rallyFans() {
    if (!_permissions.canRallyFans) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only hosts and admins can rally the room.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    SocketService.rallyFans(roomId: _room.id, roomName: _room.name);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rallying fans... followers have been notified!'),
        backgroundColor: Colors.pinkAccent,
      ),
    );
  }

  void _showGiftSounds() {
    _hideQuickReactionTray();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GiftSoundBottomSheet(
        roomId: _room.id,
        seatIndex: _getMySeatIndex(),
      ),
    );
  }

  void _showInviteFriends() {
    if (!_permissions.canInviteUsers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only hosts and admins can invite users right now.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    _hideQuickReactionTray();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => InviteFriendsBottomSheet(
        roomId: _room.id,
        roomName: _room.name,
      ),
    );
  }

  void _showVoiceFeatureLab() {
    _hideQuickReactionTray();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RoomFeatureBottomSheet(
        roomId: _room.id,
        canActivateGoldenDragon:
            _permissions.canActivateDragonPacket && !_room.banRedPacket,
        goldenDragonDisabledReason: _room.banRedPacket
            ? 'Golden Dragon is disabled in this room.'
            : 'Only hosts and room admins can launch Golden Dragon here.',
        onOpenGoldenDragon: _openGoldenDragonActivationSheet,
      ),
    );
  }

  Future<void> _openGoldenDragonActivationSheet() async {
    final userId = _currentUserId;
    if (!_canUseMiniDrawInRoom(_room, userId, requireVoiceRoom: false)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Join this room before launching Golden Dragon.'),
        ),
      );
      return;
    }

    final event = await showModalBottomSheet<GoldenDragonLiveEvent>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GoldenDragonActivationSheet(
        roomId: _room.id,
        roomName: _room.name,
        onActivated: _goldenDragonController.attachActivatedEvent,
      ),
    );

    if (event != null) {
      _goldenDragonController.attachActivatedEvent(event);
    }
  }

  void _toggleMiniDrawPanel() {
    final userId = _currentUserId;
    if (!_canUseMiniDrawInRoom(_room, userId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Join this voice room to use Mini Draw.'),
          ),
        );
      }
      return;
    }

    _hideQuickReactionTray();
    setState(() {
      _showMiniDrawPanel = !_showMiniDrawPanel;
    });
  }

  void _closeMiniDrawPanel() {
    if (!_showMiniDrawPanel || !mounted) return;
    setState(() {
      _showMiniDrawPanel = false;
    });
  }

  Future<void> _toggleSpeakerOutput() async {
    if (!_isVoiceConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice is offline')),
      );
      return;
    }

    try {
      final nextSpeakerOn = !_voiceService.isSpeakerEnabled;
      await _voiceService.setSpeakerEnabled(nextSpeakerOn);
      if (!mounted) return;
      setState(() => _isSpeakerOn = _voiceService.isSpeakerEnabled);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _showVoiceAudioSheet() {
    if (!_isVoiceConnected) {
      unawaited(_connectToVoice());
      return;
    }

    _hideQuickReactionTray();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final muted = _voiceService.isRemotePlaybackMuted;
          final volume =
              muted ? 0.0 : _voiceService.remotePlaybackVolume.clamp(0.0, 1.0);

          Future<void> refreshSheet() async {
            if (!mounted) return;
            setState(() {});
            setSheetState(() {});
          }

          return Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
            decoration: const BoxDecoration(
              color: Color(0xFF17161F),
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Voice audio',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'These controls only change what you hear on this device.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            _isSpeakerOn
                                ? Icons.speaker_rounded
                                : Icons.hearing_disabled_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Speaker output',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Switch between loud speaker output and quieter audio routing.',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isSpeakerOn,
                          activeThumbColor: const Color(0xFF69DFFF),
                          activeTrackColor:
                              const Color(0xFF69DFFF).withValues(alpha: 0.4),
                          onChanged: (_) async {
                            await _toggleSpeakerOutput();
                            await refreshSheet();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.multitrack_audio_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Room volume',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${(volume * 100).round()}%',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () async {
                                await _voiceService.setRemotePlaybackMuted(
                                  !_voiceService.isRemotePlaybackMuted,
                                );
                                await refreshSheet();
                              },
                              icon: Icon(
                                muted || volume == 0
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                color: Colors.white,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7,
                                  ),
                                ),
                                child: Slider(
                                  value: volume,
                                  min: 0,
                                  max: 1,
                                  activeColor: const Color(0xFF69DFFF),
                                  inactiveColor: Colors.white24,
                                  onChanged: (value) async {
                                    await _voiceService.setRemotePlaybackVolume(
                                      value,
                                    );
                                    await refreshSheet();
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleParticipantAudioOnDevice(Participant participant) async {
    if (participant.userId.isEmpty || participant.userId == _currentUserId) {
      return;
    }

    final nextMuted =
        !_voiceService.isParticipantMutedLocally(participant.userId);

    try {
      await _voiceService.setParticipantMutedLocally(
        participant.userId,
        nextMuted,
      );
      if (!mounted) return;

      HapticFeedback.selectionClick();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextMuted
                ? '${participant.username} muted on this device'
                : '${participant.username} unmuted on this device',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _onModeChanged(String newType) async {
    final updated = await RoomService.updateRoom(_room.id, {'type': newType});
    if (!mounted) return;
    if (updated != null) {
      _applyRoomSnapshot(updated, rebuildPage: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Room mode changed to ${newType.toUpperCase()}')),
      );
    }
  }

  void _showReactionPanel() {
    _hideQuickReactionTray();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReactionQuickPanel(
        onSelectEmoji: (emoji) {
          final now = DateTime.now();
          if (_lastReactionTime != null &&
              now.difference(_lastReactionTime!) <
                  const Duration(milliseconds: 500)) {
            // Cooldown active
            return;
          }
          _lastReactionTime = now;

          final user = Provider.of<AuthProvider>(context, listen: false).user;
          if (user != null) {
            HapticFeedback.lightImpact();
            debugPrint(
                'Ã°Å¸â€œÂ¤ Emitting reaction: $emoji for seat ${_getUserSeatIndex(user.id)}');
            SocketService.sendReaction(
              roomId: _room.id,
              emoji: emoji,
              seatIndex: _getUserSeatIndex(user.id),
            );
          }
        },
      ),
    );
  }

  void _toggleQuickReactionTray() {
    final nextValue = !_showQuickReactions;
    setState(() {
      _showQuickReactions = nextValue;
    });

    if (nextValue) {
      _armQuickReactionTrayDismiss();
    } else {
      _quickReactionTrayTimer?.cancel();
    }
  }

  void _hideQuickReactionTray() {
    _quickReactionTrayTimer?.cancel();
    if (!_showQuickReactions || !mounted) return;

    setState(() {
      _showQuickReactions = false;
    });
  }

  void _armQuickReactionTrayDismiss() {
    _quickReactionTrayTimer?.cancel();
    _quickReactionTrayTimer = Timer(
      const Duration(seconds: 4),
      _hideQuickReactionTray,
    );
  }

  void _sendQuickReaction(String emoji) {
    final now = DateTime.now();
    if (_lastReactionTime != null &&
        now.difference(_lastReactionTime!) <
            const Duration(milliseconds: 450)) {
      return;
    }

    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) return;

    _lastReactionTime = now;
    HapticFeedback.lightImpact();
    SocketService.sendReaction(
      roomId: _room.id,
      emoji: emoji,
      seatIndex: _getUserSeatIndex(user.id),
    );
    _hideQuickReactionTray();
  }

  int _getUserSeatIndex(String userId) {
    if (userId == _room.hostId) return 0;
    try {
      return _room.participants
          .firstWhere((participant) => participant.userId == userId)
          .seatIndex;
    } catch (_) {
      return -1;
    }
  }

  void _joinSocketRoom() {
    if (_hasJoinedSocketRoom) return;
    if (!_activeRoomSessionController.claimForegroundSocketMembership(
      _room.id,
    )) {
      SocketService.joinRoom(_room.id);
    }
    _hasJoinedSocketRoom = true;
  }

  void _leaveSocketRoom() {
    if (!_hasJoinedSocketRoom) return;
    SocketService.leaveRoom(_room.id);
    _hasJoinedSocketRoom = false;
  }

  @override
  void dispose() {
    _activeRoomSessionController.detachRoomScreen(
      _room.id,
      backgrounded: _keepRoomSessionAliveOnDispose,
    );
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _roomRefreshTimer?.cancel();
    _quickReactionTrayTimer?.cancel();
    _youtubeSyncDebounceTimer?.cancel();
    _youtubePlaybackRecoveryTimer?.cancel();
    _youtubeErrorRecoveryTimer?.cancel();
    _messageSubscription?.cancel();
    _updateSubscription?.cancel();
    _voiceSubscription?.cancel();
    _roomFeatureSubscription?.cancel();
    _resyncSubscription?.cancel();
    _youtubeValueSubscription?.cancel();
    _youtubeVideoStateSubscription?.cancel();
    _goldenDragonController.dispose();
    _miniDrawController.dispose();
    _passwordController.dispose();
    _messageController.dispose();
    _queueYoutubeControllerDispose(_youtubeController);
    _youtubeController = null;
    _youtubeExplode.close();
    unawaited(_roomAudioPlayer.dispose());
    if (!_keepRoomSessionAliveOnDispose) {
      unawaited(_voiceService.disconnect());
      _leaveSocketRoom();
    }
    super.dispose();
  }

  Future<void> _joinRoom({bool showFeedback = true}) async {
    if (_isJoining) return;

    setState(() {
      _isJoining = true;
      _roomErrorMessage = null;
    });

    try {
      final updatedRoom = await RoomService.joinRoom(
        _room.id,
        password: _room.isPrivate ? _passwordController.text : null,
      );

      if (!mounted) return;

      if (updatedRoom != null) {
        setState(() {
          _room = updatedRoom;
          _isJoining = false;
        });

        _activeRoomSessionController.updateRoom(updatedRoom);
        _joinSocketRoom();
        unawaited(_connectToVoice());
        unawaited(_loadInitialMessages(reset: true));
        unawaited(_goldenDragonController.ensureEventState(force: true));

        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Joined room successfully!'),
              backgroundColor: AppColors.successGreen,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _roomErrorMessage = _normalizeUiErrorMessage(e);
        _isJoining = false;
      });
    }
  }

  Future<void> _toggleFollowRoom() async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) return;

    try {
      final isFollowing = _room.isFollowedBy(user.id);
      final followers = isFollowing
          ? await RoomService.unfollowRoom(_room.id)
          : await RoomService.followRoom(_room.id);
      final nextFollowerIds = isFollowing
          ? _room.followerIds
              .where((followerId) => followerId != user.id)
              .toList(growable: false)
          : <String>{..._room.followerIds, user.id}.toList(growable: false);
      final nextFollowerCount = followers ??
          (isFollowing
              ? (_room.followers - 1).clamp(0, 99999).toInt()
              : _room.followers + 1);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFollowing ? 'Unfollowed room' : 'Following room now',
          ),
        ),
      );
      setState(() {
        _room = _room.copyWith(
          followerIds: nextFollowerIds,
          followers: nextFollowerCount,
          fans: nextFollowerCount,
        );
      });
      _notifyHeaderChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _showReportRoomDialog() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        const reasons = ['spam', 'abuse', 'inappropriate', 'harassment'];
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: const BoxDecoration(
            color: Color(0xFF17161F),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Report Room',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose the reason that best describes the problem.',
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 16),
              ...reasons.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    item[0].toUpperCase() + item.substring(1),
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white38,
                  ),
                  onTap: () => Navigator.pop(context, item),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (reason == null || !mounted) return;
    try {
      final message = await RoomService.reportRoom(_room.id, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message ?? 'Room reported successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _showAnnouncementComposer() async {
    if (!_permissions.canEditAnnouncement) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Only the room owner can update the announcement.')),
      );
      return;
    }

    final controller = TextEditingController(text: _room.announcement);
    final announcement = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: const BoxDecoration(
            color: Color(0xFF17161F),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Update Room Notice',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                maxLength: 180,
                minLines: 3,
                maxLines: 5,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Share today\'s vibe, agenda, or reminder',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(context, controller.text.trim()),
                  child: const Text('Save Notice'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();

    if (announcement == null || !mounted) return;

    try {
      await RoomService.setAnnouncement(_room.id, announcement);
      if (!mounted) return;
      await _refreshRoom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _applyMediaRoomUpdate({
    String? type,
    required Map<String, dynamic> theme,
    String? successMessage,
  }) async {
    try {
      final updated = await RoomService.updateRoom(_room.id, {
        if (type != null) 'type': type,
        'theme': theme,
      });
      if (!mounted) return;

      if (updated != null) {
        _applyRoomSnapshot(updated, rebuildPage: true);
        if (successMessage != null && successMessage.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(successMessage)),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update room media.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _showMusicSetupSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Room Audio',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _room.musicTitle?.isNotEmpty == true
                    ? _room.musicTitle!
                    : 'Select an audio file from your device for everyone in the room.',
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.library_music_rounded,
                  color: Color(0xFF63E6BE),
                ),
                title: const Text(
                  'Choose from device',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Upload an MP3, M4A, AAC, WAV or OGG file',
                  style: TextStyle(color: Colors.white54),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickRoomAudioFromDevice();
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.tune_rounded,
                  color: Colors.amberAccent,
                ),
                title: const Text(
                  'Audio settings',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _room.musicLoop ? 'Loop is on' : 'Loop is off',
                  style: const TextStyle(color: Colors.white54),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showMusicSettingsSheet();
                },
              ),
              if (_room.musicUrl?.isNotEmpty == true)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Remove current track',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _clearRoomAudio();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickRoomAudioFromDevice() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Device audio picking is not supported here.')),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'webm'],
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null || path.isEmpty) {
        throw Exception('Could not access the selected audio file.');
      }

      final upload = await UploadService.uploadAudio(path);
      if (upload['url'] == null) {
        throw Exception('Audio upload failed.');
      }

      final title =
          upload['originalName']?.toString() ?? result.files.single.name;
      await _applyMediaRoomUpdate(
        type: 'music',
        theme: {
          'music': upload['url'],
          'musicTitle': title,
          'musicLoop': _room.musicLoop,
        },
        successMessage: 'Room audio updated.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _showMusicSettingsSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var loopEnabled = _room.musicLoop;
        return StatefulBuilder(
          builder: (context, setSheetState) => Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: const BoxDecoration(
              color: Color(0xFF111111),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Loop track',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Keep playing the uploaded track continuously',
                      style: TextStyle(color: Colors.white54),
                    ),
                    value: loopEnabled,
                    activeThumbColor: const Color(0xFF63E6BE),
                    onChanged: (value) {
                      setSheetState(() => loopEnabled = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(
                        sheetContext,
                        {'action': 'save', 'loop': loopEnabled},
                      ),
                      child: const Text('Save audio settings'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (result == null || !mounted) return;
    await _applyMediaRoomUpdate(
      type: 'music',
      theme: {
        'musicLoop': result['loop'] == true,
      },
      successMessage: 'Music settings updated.',
    );
  }

  Future<void> _clearRoomAudio() async {
    await _applyMediaRoomUpdate(
      type: 'music',
      theme: {
        'music': '',
        'musicTitle': '',
        'musicLoop': false,
      },
      successMessage: 'Room audio removed.',
    );
  }

  List<_YoutubeVideoOption> _dedupeYoutubeOptions(
    Iterable<_YoutubeVideoOption> items,
  ) {
    final seenIds = <String>{};
    final results = <_YoutubeVideoOption>[];
    for (final item in items) {
      final normalizedId = item.id.trim();
      if (normalizedId.isEmpty || seenIds.contains(normalizedId)) {
        continue;
      }
      seenIds.add(normalizedId);
      results.add(item);
    }
    return results;
  }

  Future<List<_YoutubeVideoOption>> _searchYoutubeVideos(String query) async {
    try {
      final remoteResults =
          await RoomService.searchYoutubeVideos(_room.id, query);
      if (remoteResults.isNotEmpty || kIsWeb) {
        return _dedupeYoutubeOptions(
          remoteResults.map(
            (video) => _YoutubeVideoOption(
              id: video['id']?.toString() ?? '',
              title: video['title']?.toString() ?? 'Untitled video',
              author: video['author']?.toString() ?? '',
              duration: video['durationMs'] == null
                  ? null
                  : Duration(
                      milliseconds: int.tryParse('${video['durationMs']}') ?? 0,
                    ),
              thumbnailUrl: video['thumbnailUrl']?.toString() ?? '',
            ),
          ),
        );
      }
    } catch (error) {
      if (kIsWeb) {
        throw Exception('Could not load YouTube results right now.');
      }
      debugPrint('Backend YouTube search failed, falling back locally: $error');
    }

    final results = await _youtubeExplode.search.search(query);
    return _dedupeYoutubeOptions(
      results.take(12).map(
            (video) => _YoutubeVideoOption(
              id: video.id.value,
              title: video.title,
              author: video.author,
              duration: video.duration,
              thumbnailUrl: video.thumbnails.highResUrl,
            ),
          ),
    );
  }

  Future<void> _showYouTubePicker() async {
    if (!_canControlRoomStream) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Only the owner and admins can control the shared stream.'),
        ),
      );
      return;
    }

    final searchController = TextEditingController(
      text: _room.youtubeTitle?.trim().isNotEmpty == true
          ? _room.youtubeTitle!.trim()
          : '',
    );
    final initialQuery = searchController.text.trim();
    var results = <_YoutubeVideoOption>[];
    _YoutubeVideoOption? selectedVideo;
    var isSearching = false;
    var isSubmitting = false;
    var didInitialSearch = false;
    String? searchError;
    Timer? searchDebounce;
    var latestSearchRequest = 0;
    BuildContext? activeSheetContext;
    late void Function(VoidCallback fn) updateSheetState;

    void safeUpdateSheet(VoidCallback fn) {
      final sheetContext = activeSheetContext;
      if (sheetContext == null || !sheetContext.mounted) return;
      updateSheetState(fn);
    }

    bool isAlreadyInPlaylist(_YoutubeVideoOption video) {
      final itemIdentity = _youtubeQueueIdentity(
        url: 'https://www.youtube.com/watch?v=${video.id}',
        videoId: video.id,
      );
      return _currentYoutubeQueueItems().any(
        (entry) =>
            _youtubeQueueIdentity(url: entry.url, videoId: entry.videoId) ==
            itemIdentity,
      );
    }

    Future<void> runSearch([
      String? queryOverride,
      bool immediate = false,
    ]) async {
      final query = (queryOverride ?? searchController.text).trim();
      searchDebounce?.cancel();
      if (query.isEmpty) {
        safeUpdateSheet(() {
          results = const <_YoutubeVideoOption>[];
          selectedVideo = null;
          isSearching = false;
          searchError = null;
        });
        return;
      }

      Future<void> performSearch() async {
        final requestId = ++latestSearchRequest;
        safeUpdateSheet(() {
          isSearching = true;
          searchError = null;
        });

        try {
          final items = await _searchYoutubeVideos(query);
          if (requestId != latestSearchRequest) return;
          safeUpdateSheet(() {
            results = items;
            isSearching = false;
            if (items.isEmpty) {
              selectedVideo = null;
              return;
            }
            final existingSelectionId = selectedVideo?.id;
            selectedVideo = items.firstWhere(
              (item) => item.id == existingSelectionId,
              orElse: () => items.first,
            );
          });
        } catch (e) {
          if (requestId != latestSearchRequest) return;
          safeUpdateSheet(() {
            isSearching = false;
            searchError = e.toString().replaceFirst('Exception: ', '');
          });
        }
      }

      if (immediate) {
        await performSearch();
        return;
      }

      safeUpdateSheet(() {
        isSearching = true;
      });
      searchDebounce = Timer(
        const Duration(milliseconds: 340),
        () => unawaited(performSearch()),
      );
    }

    Future<void> submitSelection(
      BuildContext sheetContext, {
      required bool playNow,
    }) async {
      final video = selectedVideo;
      if (video == null || isSubmitting) {
        return;
      }

      safeUpdateSheet(() {
        isSubmitting = true;
      });
      Navigator.pop(sheetContext);
      await _queueYoutubeOption(video, playNow: playNow);
    }

    _isYoutubePickerOpen = true;
    _pauseYoutubeLocalSyncFor(const Duration(milliseconds: 1400));
    _syncYoutubePlayerOverlayInteractivity();

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            activeSheetContext = sheetContext;
            updateSheetState = setSheetState;

            if (!didInitialSearch) {
              didInitialSearch = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (sheetContext.mounted && initialQuery.isNotEmpty) {
                  unawaited(runSearch(initialQuery, true));
                }
              });
            }

            final queueCount = _currentYoutubeQueueItems().length;

            return FractionallySizedBox(
              heightFactor: 0.9,
              child: Container(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close_rounded),
                            ),
                            const Expanded(
                              child: Text(
                                'Playlist',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF161827),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: isSearching
                                  ? null
                                  : () => unawaited(
                                        runSearch(
                                          searchController.text,
                                          true,
                                        ),
                                      ),
                              child: const Text(
                                'Search',
                                style: TextStyle(
                                  color: Color(0xFF31C8F5),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F4F8),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.search_rounded,
                                size: 20,
                                color: Color(0xFF161827),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: searchController,
                                  textInputAction: TextInputAction.search,
                                  cursorColor: const Color(0xFF161827),
                                  style: const TextStyle(
                                    color: Color(0xFF161827),
                                  ),
                                  onChanged: (value) =>
                                      unawaited(runSearch(value)),
                                  onSubmitted: (_) => unawaited(
                                    runSearch(
                                      searchController.text,
                                      true,
                                    ),
                                  ),
                                  decoration: const InputDecoration(
                                    filled: false,
                                    fillColor: Colors.transparent,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    hintText: 'Search YouTube videos',
                                    hintStyle: TextStyle(
                                      color: Colors.black45,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.queue_music_rounded,
                              size: 16,
                              color: Colors.black.withValues(alpha: 0.45),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              queueCount == 0
                                  ? 'Pick a video to start the shared playlist'
                                  : '$queueCount video${queueCount == 1 ? '' : 's'} currently in the room playlist',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (isSearching)
                        const Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (searchError != null)
                        Expanded(
                          child: Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                searchError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: Column(
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: Row(
                                  children: [
                                    Text(
                                      '${results.length} result${results.length == 1 ? '' : 's'}',
                                      style: const TextStyle(
                                        color: Colors.black38,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: results.isEmpty
                                    ? _buildEmptyYouTubePickerState(
                                        onTap: () => unawaited(
                                          runSearch(
                                            searchController.text.isNotEmpty
                                                ? searchController.text
                                                : initialQuery,
                                            true,
                                          ),
                                        ),
                                      )
                                    : ListView.separated(
                                        padding: const EdgeInsets.fromLTRB(
                                            20, 0, 20, 12),
                                        itemCount: results.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 12),
                                        itemBuilder: (context, index) {
                                          final video = results[index];
                                          final isSelected =
                                              selectedVideo?.id == video.id;
                                          final alreadyQueued =
                                              isAlreadyInPlaylist(video);

                                          return InkWell(
                                            borderRadius:
                                                BorderRadius.circular(22),
                                            onTap: () {
                                              updateSheetState(() {
                                                selectedVideo = video;
                                              });
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? const Color(0xFFE8FBFF)
                                                    : Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(22),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? const Color(0xFF31C8F5)
                                                      : const Color(0xFFE8EAF1),
                                                ),
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            14),
                                                    child: Image.network(
                                                      video.thumbnailUrl,
                                                      width: 122,
                                                      height: 72,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (_, __, ___) =>
                                                              Container(
                                                        width: 122,
                                                        height: 72,
                                                        color: const Color(
                                                            0xFFF1F3F8),
                                                        alignment:
                                                            Alignment.center,
                                                        child: const Icon(
                                                          Icons
                                                              .smart_display_rounded,
                                                          color: Colors.black38,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 14),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            Expanded(
                                                              child: Text(
                                                                video.title,
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style:
                                                                    const TextStyle(
                                                                  color: Color(
                                                                      0xFF161827),
                                                                  fontSize: 15,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ),
                                                            if (alreadyQueued)
                                                              Container(
                                                                margin:
                                                                    const EdgeInsets
                                                                        .only(
                                                                  left: 8,
                                                                ),
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 4,
                                                                ),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: const Color(
                                                                          0xFF161827)
                                                                      .withValues(
                                                                    alpha: 0.06,
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                    999,
                                                                  ),
                                                                ),
                                                                child:
                                                                    const Text(
                                                                  'In playlist',
                                                                  style:
                                                                      TextStyle(
                                                                    color: Color(
                                                                        0xFF161827),
                                                                    fontSize:
                                                                        10,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                  ),
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                            height: 8),
                                                        Text(
                                                          video.author,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            color:
                                                                Colors.black45,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                        if (video
                                                                .durationLabel !=
                                                            null) ...[
                                                          const SizedBox(
                                                              height: 4),
                                                          Text(
                                                            video
                                                                .durationLabel!,
                                                            style:
                                                                const TextStyle(
                                                              color: Colors
                                                                  .black38,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: selectedVideo == null || isSubmitting
                                    ? null
                                    : () => unawaited(
                                          submitSelection(
                                            sheetContext,
                                            playNow: false,
                                          ),
                                        ),
                                icon: const Icon(Icons.queue_rounded),
                                label: const Text('Add to queue'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF161827),
                                  side: const BorderSide(
                                    color: Color(0xFFCED7E3),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: selectedVideo == null || isSubmitting
                                    ? null
                                    : () => unawaited(
                                          submitSelection(
                                            sheetContext,
                                            playNow: true,
                                          ),
                                        ),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: Text(
                                  queueCount == 0 ? 'Start now' : 'Play now',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF31C8F5),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      const Color(0xFFBDECF8),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    } finally {
      searchDebounce?.cancel();
      _isYoutubePickerOpen = false;
      _pauseYoutubeLocalSyncFor(const Duration(milliseconds: 900));
      _syncYoutubePlayerOverlayInteractivity();
      searchController.dispose();

      if (mounted &&
          _room.type == 'video' &&
          _room.youtubePlaybackState == 'playing' &&
          _youtubeController != null &&
          !_youtubePlayerValue.hasError) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _isYoutubePickerOpen) return;
          _applySharedYoutubeSync(_room, force: true);
        });
      }
    }
  }

  Widget _buildEmptyYouTubePickerState({
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.smart_display_rounded,
              size: 56,
              color: Color(0xFFFF3D3D),
            ),
            const SizedBox(height: 18),
            const Text(
              'Search YouTube to get started',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF161827),
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Pick a video inside the app and add it to the room playlist.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black54,
                fontSize: 15,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: onTap,
              icon: const AppSearchIcon(size: 18),
              label: const Text('Search now'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF161827),
                side: const BorderSide(color: Color(0xFFD8DDE8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _leaveRoomAndExit({String? reason}) async {
    if (_isExiting) return;
    _isExiting = true;
    _keepRoomSessionAliveOnDispose = false;
    final user = Provider.of<AuthProvider>(context, listen: false).user;

    try {
      if (user != null) {
        await RoomService.leaveRoom(_room.id);
      }
    } finally {
      _leaveSocketRoom();
      await _voiceService.disconnect();
      await _roomAudioPlayer.stop();
      _isVoiceConnected = false;
      _activeRoomSessionController.clearTrackedRoom(_room.id);
    }

    if (!mounted) return;
    if (reason != null && reason.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason)),
      );
    }
    Navigator.pop(context);
  }

  Future<void> _backgroundRoomAndExit() async {
    if (_keepRoomSessionAliveOnDispose || _isExiting) return;

    _keepRoomSessionAliveOnDispose = true;
    _activeRoomSessionController.backgroundRoom(_room);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<_RoomExitDecision?> _showRoomExitSheet() {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    final isInRoom = user != null && _isUserInRoom(user.id);
    final roleLabel = _permissions.isOwner
        ? 'host'
        : _permissions.isAdmin
            ? 'admin'
            : 'listener';

    return showModalBottomSheet<_RoomExitDecision>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: const Color(0xF010121B),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 28,
              offset: const Offset(0, -12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 46,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Leave the room?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isInRoom
                  ? _permissions.isOwner
                      ? 'You are in the room as $roleLabel. Keep it running in the background and come back anytime, or leave fully to hand off or close the live session based on room policy.'
                      : 'Keep the room active in the background with a floating return button, or leave the live session completely.'
                  : 'You have not joined this room yet. Leaving now will just close this screen.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            if (isInRoom)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      onTap: () => Navigator.pop(
                        sheetContext,
                        _RoomExitDecision.background,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 4,
                      ),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF1B7CFF).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.picture_in_picture_alt_rounded,
                          color: Colors.white,
                        ),
                      ),
                      title: const Text(
                        'Keep room in background',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Voice stays connected and a floating room shortcut will appear.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.62),
                          height: 1.35,
                        ),
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    ListTile(
                      onTap: () =>
                          Navigator.pop(sheetContext, _RoomExitDecision.leave),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 4,
                      ),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFFF5D6C).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          color: Colors.white,
                        ),
                      ),
                      title: const Text(
                        'Leave room completely',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Disconnect voice, remove the floating shortcut, and clean up this room session.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.62),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(sheetContext, _RoomExitDecision.closeOnly),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B7CFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Close room screen'),
                ),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Stay here'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRoomExit() async {
    final decision = await _showRoomExitSheet();
    if (!mounted || decision == null) return;

    switch (decision) {
      case _RoomExitDecision.background:
        await _backgroundRoomAndExit();
        return;
      case _RoomExitDecision.leave:
        await _leaveRoomAndExit();
        return;
      case _RoomExitDecision.closeOnly:
        _activeRoomSessionController.clearTrackedRoom(_room.id);
        if (mounted) {
          Navigator.pop(context);
        }
        return;
    }
  }

  Future<bool> _handleBackNavigation() async {
    await _confirmRoomExit();
    return false;
  }

  void _notifyChatChanged() {
    _chatRevision.value++;
  }

  void _notifyStageChanged() {
    _stageRevision.value++;
  }

  void _notifyHeaderChanged() {
    _headerRevision.value++;
  }

  void _applyRoomSnapshot(RoomModel room, {bool rebuildPage = false}) {
    final previous = _room;
    final previousQueueSignature = previous.youtubeQueue
        .map((item) => item.videoId.isNotEmpty ? item.videoId : item.url)
        .join('|');
    final nextQueueSignature = room.youtubeQueue
        .map((item) => item.videoId.isNotEmpty ? item.videoId : item.url)
        .join('|');
    final mediaChanged = previous.type != room.type ||
        previous.youtubeUrl != room.youtubeUrl ||
        previous.youtubeActiveVideoId != room.youtubeActiveVideoId ||
        previous.youtubeSessionVersion != room.youtubeSessionVersion ||
        previous.youtubeTitle != room.youtubeTitle ||
        previous.youtubeThumbnail != room.youtubeThumbnail ||
        previous.youtubePlaybackState != room.youtubePlaybackState ||
        previous.youtubeSyncedAt != room.youtubeSyncedAt ||
        previousQueueSignature != nextQueueSignature ||
        previous.musicUrl != room.musicUrl ||
        previous.musicTitle != room.musicTitle;
    final shouldKeepMiniDrawPanel =
        _showMiniDrawPanel && _canUseMiniDrawInRoom(room, _currentUserId);
    final shouldRebuildShell =
        rebuildPage || previous.background != room.background || mediaChanged;
    if (shouldRebuildShell && mounted) {
      setState(() {
        _room = room;
        _showMiniDrawPanel = shouldKeepMiniDrawPanel;
      });
    } else {
      _room = room;
      _showMiniDrawPanel = shouldKeepMiniDrawPanel;
    }
    _syncMediaController(room);
    _miniDrawController.applyRoomSnapshot(room);
    _applySharedYoutubeSync(room);
    _announceRoomSettingChanges(previous, room);
    _activeRoomSessionController.updateRoom(_room);
    _notifyHeaderChanged();
    _notifyStageChanged();
  }

  void _announceRoomSettingChanges(RoomModel previous, RoomModel next) {
    if (previous.id != next.id) return;

    if (previous.roomActive != next.roomActive) {
      _appendSystemMessage(
        next.roomActive
            ? 'Room is active again. Host/admin controls are back.'
            : 'Room inactive - waiting for host/admin.',
      );
    }
    if (previous.type != next.type) {
      final mode = roomModePresetFor(next.type);
      _appendSystemMessage('Room mode switched to ${mode.label}.');
    }
    if (previous.background != next.background) {
      final background = roomBackgroundPresetFor(next.background);
      _appendSystemMessage('Room atmosphere changed to ${background.label}.');
    }
    if (previous.banTextChat != next.banTextChat) {
      _appendSystemMessage(
        next.banTextChat
            ? 'Text chat is now limited to hosts and admins.'
            : 'Text chat is open for everyone again.',
      );
    }
    if (previous.banPhotoChat != next.banPhotoChat) {
      _appendSystemMessage(
        next.banPhotoChat
            ? 'Photo sharing is now turned off for guests.'
            : 'Photo sharing is available again.',
      );
    }
    if (previous.hdVoice != next.hdVoice) {
      _appendSystemMessage(
        next.hdVoice
            ? 'High quality voice mode is now on.'
            : 'High quality voice mode is now off.',
      );
    }
    if (previous.allowGifts != next.allowGifts) {
      _appendSystemMessage(
        next.allowGifts
            ? 'Room gifting is now enabled.'
            : 'Room gifting has been turned off.',
      );
    }
    if (previous.stageJoinsLocked != next.stageJoinsLocked) {
      _appendSystemMessage(
        next.stageJoinsLocked
            ? 'Stage joins are locked. Only the owner and admins can move people onto the stage.'
            : 'Stage joins are open again.',
      );
    }
    if (previous.requireApproval != next.requireApproval) {
      _appendSystemMessage(
        next.requireApproval
            ? 'Mic approval is now required before joining the stage.'
            : 'Guests can join open speaker seats again.',
      );
    }
    if (previous.maxActiveSpeakers != next.maxActiveSpeakers) {
      _appendSystemMessage(
        'Active speaker seats changed to ${next.maxActiveSpeakers}.',
      );
    }
    if (previous.isPrivate != next.isPrivate) {
      _appendSystemMessage(
        next.isPrivate
            ? 'Room privacy is now enabled.'
            : 'Room is public again.',
      );
    }
  }

  Widget _buildInactiveRoomBanner() {
    return Padding(
      key: const ValueKey('room-inactive-banner'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF201A12).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFFFFC857).withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFFC857).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.pause_circle_filled_rounded,
                color: Color(0xFFFFC857),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Room inactive',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Waiting for host/admin. Stage actions are paused until a controller returns.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scheduleRoomRefresh({
    Duration delay = const Duration(milliseconds: 480),
  }) {
    _roomRefreshTimer?.cancel();
    _roomRefreshTimer = Timer(delay, () {
      if (!mounted) return;
      unawaited(_refreshRoom());
    });
  }

  bool _updateParticipantState(
    String userId, {
    bool? muted,
    bool? speaking,
  }) {
    if (userId.isEmpty) return false;

    var changed = false;
    final updatedParticipants = _room.participants.map((participant) {
      if (participant.userId != userId) {
        return participant;
      }

      final nextMuted = muted ?? participant.isMuted;
      final nextSpeaking = speaking ?? participant.isSpeaking;
      if (nextMuted == participant.isMuted &&
          nextSpeaking == participant.isSpeaking) {
        return participant;
      }

      changed = true;
      return participant.copyWith(
        isMuted: nextMuted,
        isSpeaking: nextSpeaking,
      );
    }).toList();

    if (!changed) return false;
    _room = _room.copyWith(participants: updatedParticipants);
    _activeRoomSessionController.updateRoom(_room);
    _notifyStageChanged();
    return true;
  }

  bool _applySeatStatesSnapshot(dynamic rawSeatStates) {
    if (rawSeatStates is! List) return false;

    final nextSeatStates = <RoomSeatState>[];
    for (final entry in rawSeatStates) {
      if (entry is Map<String, dynamic>) {
        nextSeatStates.add(RoomSeatState.fromJson(entry));
      } else if (entry is Map) {
        nextSeatStates
            .add(RoomSeatState.fromJson(Map<String, dynamic>.from(entry)));
      }
    }

    if (nextSeatStates.isEmpty) return false;
    nextSeatStates
        .sort((left, right) => left.seatIndex.compareTo(right.seatIndex));
    _room = _room.copyWith(seatStates: nextSeatStates);
    _activeRoomSessionController.updateRoom(_room);
    _notifyStageChanged();
    return true;
  }

  bool _updateSeatLockState(
    int seatIndex,
    bool locked, {
    RoomSeatState? seatState,
  }) {
    final nextSeatStates = [..._room.seatStates];
    final existingIndex = nextSeatStates.indexWhere(
      (entry) => entry.seatIndex == seatIndex,
    );
    final nextSeatState = seatState ??
        (existingIndex >= 0
            ? nextSeatStates[existingIndex].copyWith(
                isLocked: locked,
                lockedByUserId: locked
                    ? nextSeatStates[existingIndex].lockedByUserId
                    : null,
                lockedAt:
                    locked ? nextSeatStates[existingIndex].lockedAt : null,
                lockReason:
                    locked ? nextSeatStates[existingIndex].lockReason : '',
                updatedAt: DateTime.now(),
              )
            : RoomSeatState(
                seatIndex: seatIndex,
                occupiedByUserId: _getParticipantAtSeat(seatIndex)?.userId,
                isLocked: locked,
                updatedAt: DateTime.now(),
              ));

    if (existingIndex >= 0) {
      nextSeatStates[existingIndex] = nextSeatState;
    } else {
      nextSeatStates.add(nextSeatState);
    }

    nextSeatStates
        .sort((left, right) => left.seatIndex.compareTo(right.seatIndex));
    _room = _room.copyWith(seatStates: nextSeatStates);
    _activeRoomSessionController.updateRoom(_room);
    _notifyStageChanged();
    return true;
  }

  bool _applyPresenceDelta(int delta) {
    final nextOnlineCount = (_room.onlineCount + delta).clamp(0, 99999).toInt();
    if (nextOnlineCount == _room.onlineCount) return false;

    _room = _room.copyWith(onlineCount: nextOnlineCount);
    _activeRoomSessionController.updateRoom(_room);
    _notifyHeaderChanged();
    return true;
  }

  bool _applyParticipantJoined(Map<String, dynamic> data) {
    final userId = data['userId']?.toString();
    if (userId == null ||
        userId.isEmpty ||
        _room.participants.any((participant) => participant.userId == userId)) {
      return false;
    }

    final participant = Participant(
      userId: userId,
      username: data['username']?.toString() ?? 'User',
      avatar: data['avatar']?.toString() ?? '',
      level: 1,
      vipLevel: 0,
      role: 'listener',
      seatIndex: -1,
      isMuted: false,
      isSpeaking: false,
      isOnline: true,
      contribution: 0,
      raisedHand: false,
    );

    _room = _room.copyWith(
      participants: [..._room.participants, participant],
      participantCount: _room.participantCount + 1,
      onlineCount: _room.onlineCount + 1,
    );
    _activeRoomSessionController.updateRoom(_room);
    _notifyHeaderChanged();
    _notifyStageChanged();
    return true;
  }

  bool _applyParticipantLeft(Map<String, dynamic> data) {
    final userId = data['userId']?.toString();
    if (userId == null || userId.isEmpty || userId == _room.hostId) {
      return false;
    }

    final updatedParticipants = _room.participants
        .where((participant) => participant.userId != userId)
        .toList();
    if (updatedParticipants.length == _room.participants.length) {
      return false;
    }

    _room = _room.copyWith(
      participants: updatedParticipants,
      participantCount: updatedParticipants.length,
      onlineCount: (_room.onlineCount - 1).clamp(0, 99999).toInt(),
    );
    _activeRoomSessionController.updateRoom(_room);
    _notifyHeaderChanged();
    _notifyStageChanged();
    return true;
  }

  bool _canApplyRoomPayloadDirectly(Map<String, dynamic> data) {
    final payloadRoomId =
        data['_id']?.toString() ?? data['id']?.toString() ?? data['roomId'];
    if (payloadRoomId?.toString() != _room.id) return false;

    final participants = data['participants'];
    if (participants is List && participants.isNotEmpty) {
      return participants.any(
        (participant) =>
            participant is Map<String, dynamic> &&
            (participant['userId'] is Map<String, dynamic> ||
                participant['user'] is Map<String, dynamic>),
      );
    }

    return data['hostId'] is Map<String, dynamic>;
  }

  void _handleIncomingRoomMessage(Map<String, dynamic> data) {
    if (data['roomId'] != _room.id || !mounted) return;
    _appendChatMessage(data);
  }

  void _handleRoomUpdate(Map<String, dynamic> data) {
    final matchesRoom = data['_id'] == _room.id ||
        data['id'] == _room.id ||
        data['roomId'] == _room.id;
    if (!matchesRoom) return;

    final eventType = data['_eventType']?.toString();
    if (eventType == 'room_deleted') {
      unawaited(_leaveRoomAndExit(reason: 'This room has ended.'));
      return;
    }
    if (eventType == 'user_kicked') {
      unawaited(_leaveRoomAndExit(reason: 'You were removed from the room.'));
      return;
    }
    if (eventType == 'user_banned') {
      unawaited(_leaveRoomAndExit(reason: 'You were banned from this room.'));
      return;
    }

    switch (eventType) {
      case 'room_update_identity':
      case 'room_update_settings':
      case 'room_update_permissions':
      case 'room_update_seats':
      case 'room_seats_updated':
      case 'room_update_roles':
      case 'room_update_mode':
      case 'room_update_theme':
        final roomPayload = data['room'];
        if (roomPayload is Map<String, dynamic>) {
          _applyRoomSnapshot(RoomModel.fromJson(roomPayload));
          return;
        }
        if (_applySeatStatesSnapshot(data['updatedSeats'])) {
          return;
        }
        break;
      case 'participant_muted':
        if (_updateParticipantState(
          data['userId']?.toString() ?? '',
          muted: data['muted'] == true,
        )) {
          return;
        }
        break;
      case 'seat_locked':
        if (_applySeatStatesSnapshot(data['updatedSeats'])) {
          return;
        }
        final seatIndex = int.tryParse('${data['seatIndex']}');
        final updatedSeat = data['updatedSeat'];
        final seatState = updatedSeat is Map<String, dynamic>
            ? RoomSeatState.fromJson(updatedSeat)
            : updatedSeat is Map
                ? RoomSeatState.fromJson(Map<String, dynamic>.from(updatedSeat))
                : null;
        if (seatIndex != null &&
            _updateSeatLockState(seatIndex, true, seatState: seatState)) {
          return;
        }
        break;
      case 'seat_unlocked':
        if (_applySeatStatesSnapshot(data['updatedSeats'])) {
          return;
        }
        final seatIndex = int.tryParse('${data['seatIndex']}');
        final updatedSeat = data['updatedSeat'];
        final seatState = updatedSeat is Map<String, dynamic>
            ? RoomSeatState.fromJson(updatedSeat)
            : updatedSeat is Map
                ? RoomSeatState.fromJson(Map<String, dynamic>.from(updatedSeat))
                : null;
        if (seatIndex != null &&
            _updateSeatLockState(seatIndex, false, seatState: seatState)) {
          return;
        }
        break;
      case 'participant_joined':
        if (_applyParticipantJoined(data)) {
          return;
        }
        break;
      case 'participant_left':
        if (_applyParticipantLeft(data)) {
          return;
        }
        break;
      case 'user_joined':
        if (_applyPresenceDelta(1)) {
          return;
        }
        break;
      case 'user_left':
        if (_applyPresenceDelta(-1)) {
          return;
        }
        break;
      case 'room_updated':
        if (_canApplyRoomPayloadDirectly(data)) {
          _applyRoomSnapshot(RoomModel.fromJson(data));
          return;
        }
        break;
      case 'rally_fans':
        break;
    }

    _scheduleRoomRefresh();
  }

  void _handleVoiceEvent(Map<String, dynamic> data) {
    final userId = data['userId']?.toString();
    if (userId == null || userId.isEmpty || !mounted) return;

    final eventType = data['_eventType']?.toString();
    if (eventType == 'mute') {
      _updateParticipantState(userId, muted: data['muted'] == true);
      return;
    }
    if (eventType == 'speaking') {
      _updateParticipantState(userId, speaking: data['speaking'] == true);
    }
  }

  void _handleRoomFeatureEvent(Map<String, dynamic> data) {
    if (data['roomId']?.toString() != _room.id || !mounted) return;

    final summary = data['summary']?.toString();
    if (summary == null) return;

    final trimmedSummary = summary.trim();
    if (trimmedSummary.isEmpty) return;
    _appendSystemMessage(trimmedSummary);
  }

  void _appendChatMessage(
    Map<String, dynamic> data, {
    bool notify = true,
  }) {
    final messageId = data['_id']?.toString();
    final alreadyExists = messageId != null &&
        _chatMessages.any((message) => message['_id']?.toString() == messageId);
    if (alreadyExists) return;

    _chatMessages.add(Map<String, dynamic>.from(data));
    if (_chatMessages.length > 120) {
      _chatMessages.removeAt(0);
    }
    if (notify) {
      _notifyChatChanged();
    }
  }

  void _appendSystemMessage(String content, {bool notify = true}) {
    final previous = _chatMessages.isNotEmpty
        ? _chatMessages.last['content']?.toString()
        : null;
    if (previous == content) return;
    _appendChatMessage({
      '_id': 'system-${DateTime.now().microsecondsSinceEpoch}',
      'type': 'system',
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    }, notify: notify && mounted);
  }

  bool _canManageRoom(String? userId) {
    return RoomPermissions(room: _room, userId: userId).canManageRoom;
  }

  bool _canManageSeatLocks(String? userId) {
    return RoomPermissions(room: _room, userId: userId).canManageSeatLocks;
  }

  bool _isUserInRoom(String userId) {
    return _canUseMiniDrawInRoom(_room, userId, requireVoiceRoom: false);
  }

  bool _canUseMiniDrawInRoom(
    RoomModel room,
    String? userId, {
    bool requireVoiceRoom = true,
  }) {
    if (userId == null || userId.isEmpty) return false;
    if (requireVoiceRoom && room.type != 'voice') return false;

    return room.participants.any((p) {
      if (p.user != null) {
        return p.user!.id == userId && p.isPresent;
      }
      return p.userId == userId && p.isPresent;
    });
  }

  Widget _buildMiniDrawToggleButton() {
    final isOpen = _showMiniDrawPanel;
    final isUnlocked = _miniDrawController.summary.isUnlocked;
    final accent = isOpen
        ? const Color(0xFF64D2FF)
        : isUnlocked
            ? const Color(0xFF7B61FF)
            : const Color(0xFF4A4F66);
    final background = isOpen
        ? const [Color(0xFF64D2FF), Color(0xFF367CFF)]
        : isUnlocked
            ? const [Color(0xFF7B61FF), Color(0xFF3E3C94)]
            : const [Color(0xFF252A36), Color(0xFF171B24)];

    return Tooltip(
      message: isOpen
          ? 'Hide Mini Draw'
          : isUnlocked
              ? 'Open Mini Draw'
              : 'Unlock Mini Draw for 300 coins',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleMiniDrawPanel,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: background,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: isOpen ? 0.24 : 0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.34),
                  blurRadius: 20,
                  spreadRadius: -6,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Image.asset(
                      'assets/images/mini_draw_board.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: isUnlocked
                          ? const Color(0xFF111827)
                          : const Color(0xFFFFD43B),
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFF090B11), width: 2),
                    ),
                    child: Icon(
                      isUnlocked
                          ? Icons.wifi_tethering_rounded
                          : Icons.workspace_premium_rounded,
                      color: isUnlocked
                          ? const Color(0xFF63E6BE)
                          : const Color(0xFF121212),
                      size: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only rebuild if the User ID changes (which shouldn't happen during a session)
    final userId = context.select<AuthProvider, String?>((p) => p.user?.id);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Background Layer (Parallax/Dynamic Gradients)
            RepaintBoundary(
              child: _buildBackground(),
            ),

            if (_roomErrorMessage != null)
              Positioned(
                top: 50,
                left: 20,
                right: 20,
                child: GestureDetector(
                  onTap: () => setState(() => _roomErrorMessage = null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _roomErrorMessage!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                        const Icon(Icons.close,
                            color: Colors.white70, size: 18),
                      ],
                    ),
                  ),
                ),
              ),

            // 2. Main Content Layer
            SafeArea(
              child: Column(
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: _headerRevision,
                    builder: (_, __, ___) => SafeArea(
                      bottom: false,
                      child: _buildMinimalHeader(),
                    ),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: _headerRevision,
                    builder: (_, __, ___) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _isRoomInactive
                          ? _buildInactiveRoomBanner()
                          : const SizedBox.shrink(),
                    ),
                  ),

                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _stageRevision,
                      builder: (_, __, ___) => _buildMainArea(),
                    ),
                  ),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        sizeFactor: animation,
                        axisAlignment: -1,
                        child: child,
                      ),
                    ),
                    child: userId != null &&
                            _isUserInRoom(userId) &&
                            _showQuickReactions
                        ? Padding(
                            key: const ValueKey('quick-reaction-tray'),
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                            child: ReactionQuickPanel(
                              compact: true,
                              onSelectEmoji: _sendQuickReaction,
                              onOpenFullPicker: _showReactionPanel,
                            ),
                          )
                        : const SizedBox(
                            key: ValueKey('quick-reaction-tray-hidden'),
                          ),
                  ),

                  // Bottom Toolbar
                  ValueListenableBuilder<int>(
                    valueListenable: _stageRevision,
                    builder: (_, __, ___) => _buildBottomToolbar(
                      userId != null && _isUserInRoom(userId),
                    ),
                  ),
                ],
              ),
            ),

            // 3. Real-time Animation Layer (Stack-level overlay - Ensure absolute top Z-index)
            Positioned.fill(
              child: IgnorePointer(
                child:
                    GiftAnimationOverlay(giftStream: SocketService.giftStream),
              ),
            ),
            Positioned.fill(
              child: ReactionAnimationOverlay(seatKeys: _seatKeyMap),
            ),
            Positioned.fill(
              child: RoomFeatureOverlay(roomId: _room.id),
            ),
            Positioned.fill(
              child: GoldenDragonOverlay(
                controller: _goldenDragonController,
                visible: _goldenDragonController.hasVisibleEvent,
                onClose: _goldenDragonController.result != null
                    ? _goldenDragonController.dismissResult
                    : null,
              ),
            ),
            if (_canUseMiniDrawInRoom(_room, userId))
              Positioned(
                right: 14,
                bottom: MediaQuery.of(context).padding.bottom +
                    (_showQuickReactions ? 144 : 88),
                child: _buildMiniDrawToggleButton(),
              ),
            Positioned.fill(
              child: MiniDrawOverlay(
                controller: _miniDrawController,
                visible:
                    _showMiniDrawPanel && _canUseMiniDrawInRoom(_room, userId),
                onClose: _closeMiniDrawPanel,
              ),
            ),

            // 4. Floating Reactions (Secondary Overlay for additional visibility)
            // Positioned.fill(child: FloatingReactionOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    final preset = roomBackgroundPresetFor(_room.background);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: preset.colors,
        ),
      ),
      child: Stack(
        children: [
          ..._buildBackgroundLayers(preset),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.02),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.14),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientOrb(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  List<Widget> _buildBackgroundLayers(RoomBackgroundPreset preset) {
    switch (preset.id) {
      case 'space':
        return [
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.025),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
                Expanded(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.09),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 84,
            right: -88,
            child: _buildAmbientOrb(
              preset.colors.last.withValues(alpha: 0.18),
              220,
            ),
          ),
          Positioned(
            bottom: -70,
            left: -50,
            child: _buildAmbientOrb(
              preset.colors[1].withValues(alpha: 0.18),
              180,
            ),
          ),
        ];
      case 'ocean':
        return [
          Positioned(
            top: -76,
            right: -56,
            child: _buildAmbientOrb(
              preset.colors.last.withValues(alpha: 0.22),
              180,
            ),
          ),
          Positioned(
            bottom: 70,
            left: -62,
            child: _buildAmbientOrb(
              Colors.white.withValues(alpha: 0.06),
              150,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.04),
                    Colors.transparent,
                    preset.colors.last.withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ),
        ];
      case 'galaxy':
        return [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 0.95,
                  colors: [
                    Colors.white.withValues(alpha: 0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          _buildSparkleField(),
          Positioned(
            top: 110,
            right: -80,
            child: _buildAmbientOrb(
              preset.colors.last.withValues(alpha: 0.14),
              180,
            ),
          ),
        ];
      case 'sunrise':
        return [
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                Expanded(
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                ),
                Expanded(
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ];
      case 'default':
      default:
        return [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, 0.08),
                  radius: 0.72,
                  colors: [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          _buildSparkleField(),
          Positioned(
            top: -128,
            left: -52,
            child: _buildAmbientOrb(
              preset.colors.last.withValues(alpha: 0.16),
              220,
            ),
          ),
          Positioned(
            bottom: -88,
            right: -46,
            child: _buildAmbientOrb(
              Colors.white.withValues(alpha: 0.06),
              170,
            ),
          ),
        ];
    }
  }

  Widget _buildSparkleField() {
    return IgnorePointer(
      child: Stack(
        children: const [
          _Sparkle(alignment: Alignment(-0.62, 0.06), size: 5),
          _Sparkle(alignment: Alignment(-0.38, 0.18), size: 4),
          _Sparkle(alignment: Alignment(-0.12, 0.02), size: 3),
          _Sparkle(alignment: Alignment(0.12, 0.1), size: 4),
          _Sparkle(alignment: Alignment(0.36, -0.02), size: 3),
          _Sparkle(alignment: Alignment(0.58, 0.16), size: 5),
          _Sparkle(alignment: Alignment(0.02, 0.34), size: 4),
          _Sparkle(alignment: Alignment(-0.26, 0.42), size: 3),
          _Sparkle(alignment: Alignment(0.28, 0.44), size: 3),
        ],
      ),
    );
  }

  Widget _buildAnnouncementBar({
    EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(16, 4, 16, 10),
  }) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.campaign_rounded,
              color: Colors.amberAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _room.announcement,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  overflow: TextOverflow.ellipsis),
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_ios,
              color: Colors.white.withValues(alpha: 0.3), size: 10),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildHeader(UserModel? user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: MediaQuery.of(context).size.width - 32, // Accommodate padding
          child: Row(
            children: [
              _buildToolbarIcon(Icons.arrow_back_ios_new, Colors.white,
                  () => unawaited(_confirmRoomExit()),
                  size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _showRoomInfo,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getTypeColor(_room.type),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(_room.type.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34C759),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('Lv.${_room.level}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _room.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios,
                              color: Colors.white54, size: 10),
                        ],
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Text(
                                '${_room.onlineCount}/${_room.participantCount}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 10)),
                            const SizedBox(width: 8),
                            const Text('Ã¢â‚¬Â¢',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 10)),
                            const SizedBox(width: 8),
                            Text(_room.region,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 10)),
                            const SizedBox(width: 8),
                            const Text('Ã¢â‚¬Â¢',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 10)),
                            const SizedBox(width: 8),
                            Icon(
                              _isVoiceConnected
                                  ? Icons.multitrack_audio_rounded
                                  : Icons.chat_bubble_outline_rounded,
                              color: _isVoiceConnected
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                              size: 10,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isVoiceConnected ? 'Voice live' : 'Chat live',
                              style: TextStyle(
                                color: _isVoiceConnected
                                    ? Colors.greenAccent
                                    : Colors.orangeAccent,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.favorite,
                                color: Colors.pink, size: 10),
                            const SizedBox(width: 2),
                            Text('${_room.fans}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Wallet Display (Reactive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const CurrencyIcon.coins(size: 12),
                    const SizedBox(width: 4),
                    Selector<AuthProvider, int>(
                      selector: (_, provider) => provider.user?.coins ?? 0,
                      builder: (_, coins, __) => Text(
                        '$coins',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const CurrencyIcon.gems(size: 12),
                    const SizedBox(width: 4),
                    Selector<AuthProvider, int>(
                      selector: (_, provider) => provider.user?.gems ?? 0,
                      builder: (_, gems, __) => Text(
                        '$gems',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Participant count / Online list
              GestureDetector(
                onTap: _showMembers,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.group, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('${_room.onlineCount}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),
              _buildToolbarIcon(
                  Icons.more_horiz, Colors.white, _showRoomControl,
                  size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => unawaited(_confirmRoomExit()),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              padding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: _showRoomInfo,
              child: Row(
                children: [
                  _buildHeaderArtwork(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _room.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.verified_rounded,
                                color: Color(0xFF52A1FF), size: 16),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'ID: ${_room.roomId}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildHeaderAudienceCount(),
          const SizedBox(width: 8),
          _buildEqualizerIcon(),
          const SizedBox(width: 12),
          IconButton(
            onPressed: _showRoomControl,
            icon: const Icon(Icons.more_horiz_rounded,
                color: Colors.white, size: 24),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              padding: const EdgeInsets.all(10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderArtwork() {
    final roomImageUrl = _normalizeRoomHeaderImage(_room.coverImage);

    return Container(
      width: 46,
      height: 46,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: roomImageUrl != null
            ? Image.network(
                roomImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildHeaderArtworkFallback(),
              )
            : _buildHeaderArtworkFallback(),
      ),
    );
  }

  Widget _buildHeaderArtworkFallback() {
    return Container(
      color: const Color(0xFF141519),
      alignment: Alignment.center,
      child: UserAvatar(
        imageUrl: _resolveHostAvatarForHeader(),
        username: _room.hostName.isNotEmpty ? _room.hostName : _room.name,
        radius: 15,
        fontSize: 12,
      ),
    );
  }

  String? _resolveHostAvatarForHeader() {
    for (final participant in _room.participants) {
      if (participant.userId != _room.hostId) {
        continue;
      }

      final avatar = participant.avatar.trim();
      if (avatar.isNotEmpty && avatar != 'null') {
        return avatar;
      }
    }

    final hostAvatar = _room.hostAvatar.trim();
    if (hostAvatar.isNotEmpty && hostAvatar != 'null') {
      return hostAvatar;
    }

    return null;
  }

  String? _normalizeRoomHeaderImage(String? imageUrl) {
    return _normalizeRoomAssetUrl(imageUrl);
  }

  String? _normalizeRoomAssetUrl(String? imageUrl) {
    final rawUrl = imageUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty || rawUrl == 'null') {
      return null;
    }

    final normalized = AppConfig.normalizeBackendUrl(rawUrl);
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasAuthority) {
      return null;
    }

    return normalized;
  }

  Widget _buildEqualizerIcon() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFFF7A45).withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border:
            Border.all(color: const Color(0xFFFF7A45).withValues(alpha: 0.2)),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildEqualizerBar(8, const Duration(milliseconds: 400)),
            const SizedBox(width: 2),
            _buildEqualizerBar(14, const Duration(milliseconds: 600)),
            const SizedBox(width: 2),
            _buildEqualizerBar(10, const Duration(milliseconds: 500)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderAudienceCount() {
    return GestureDetector(
      onTap: _showMembers,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.groups_rounded,
              size: 16,
              color: Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              '${_room.participantCount}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEqualizerBar(double height, Duration duration) {
    return _EqualizerBar(maxHeight: height, duration: duration);
  }

  // ignore: unused_element
  Widget _buildRoomHeader(UserModel? user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToolbarIcon(
            Icons.arrow_back_ios_new,
            Colors.white,
            () => unawaited(_confirmRoomExit()),
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: _showRoomInfo,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildHeaderBadge(
                          _room.type.toUpperCase(),
                          background: _getTypeColor(_room.type),
                        ),
                        _buildHeaderBadge(
                          'Lv.${_room.level}',
                          background: const Color(0xFF34C759),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _room.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white54,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildHeaderInfoPill(
                          Icons.group_rounded,
                          '${_room.onlineCount}/${_room.participantCount}',
                        ),
                        _buildHeaderInfoPill(
                          Icons.public_rounded,
                          _room.region,
                        ),
                        _buildHeaderInfoPill(
                          _isVoiceConnected
                              ? Icons.multitrack_audio_rounded
                              : Icons.chat_bubble_outline_rounded,
                          _isVoiceConnected ? 'Voice live' : 'Chat live',
                          iconColor: _isVoiceConnected
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                          textColor: _isVoiceConnected
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                        ),
                        _buildHeaderInfoPill(
                          Icons.favorite_rounded,
                          '${_room.fans}',
                          iconColor: Colors.pinkAccent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              _buildHeaderStatChip(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CurrencyIcon.coins(size: 12),
                    const SizedBox(width: 4),
                    Selector<AuthProvider, int>(
                      selector: (_, provider) => provider.user?.coins ?? 0,
                      builder: (_, coins, __) => Text(
                        '$coins',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const CurrencyIcon.gems(size: 12),
                    const SizedBox(width: 4),
                    Selector<AuthProvider, int>(
                      selector: (_, provider) => provider.user?.gems ?? 0,
                      builder: (_, gems, __) => Text(
                        '$gems',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildHeaderStatChip(
                onTap: _showMembers,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.group_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_room.onlineCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildToolbarIcon(
                Icons.more_horiz,
                Colors.white,
                _showRoomControl,
                size: 22,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBadge(
    String label, {
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildHeaderInfoPill(
    IconData icon,
    String label, {
    Color iconColor = Colors.white70,
    Color textColor = Colors.white70,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStatChip({
    required Widget child,
    VoidCallback? onTap,
  }) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );

    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }

  Widget _buildMainArea() {
    switch (_room.type) {
      case 'voice':
        return _buildVoiceView();
      case 'auction':
        return _buildAuctionView();
      case 'video':
        return _buildVideoView();
      case 'music':
        return _buildMusicView();
      case 'game':
        return _buildGameView();
      default:
        return _buildSeatGrid();
    }
  }

  Widget _buildVoiceView() {
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: constraints.maxHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              Center(child: _buildMainSpeaker()),
              const SizedBox(height: 20),
              _buildVoiceSeatWrap(),
              const SizedBox(height: 16),
              Expanded(
                child: _buildRoomActivitySection(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuctionView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 228),
      child: Column(
        children: [
          Container(
            height: 120,
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8E24AA), Color(0xFFD81B60)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.pink.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.gavel_rounded, color: Colors.white, size: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Current Bid',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const CurrencyIcon.coins(size: 20),
                          const SizedBox(width: 4),
                          const Text('12,000',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2)),
                      child: const CircleAvatar(
                          backgroundColor: Colors.white24,
                          child: Icon(Icons.person,
                              color: Colors.white, size: 28)),
                    ),
                    const SizedBox(height: 4),
                    const Text('Top Bidder',
                        style: TextStyle(color: Colors.white70, fontSize: 9)),
                  ],
                ),
              ],
            ),
          ),
          _buildSeatGrid(compact: true),
          const SizedBox(height: 18),
          _buildRoomActivitySection(compact: true),
        ],
      ),
    );
  }

  Widget _buildVideoView() {
    final hasVideo = _room.youtubeUrl?.isNotEmpty == true &&
        _extractYoutubeVideoId(_room.youtubeUrl!) != null &&
        _youtubeController != null;
    final videoId = _sharedYoutubeVideoId();
    final canControlStream = _canControlRoomStream;
    final youtubeQueue = _currentYoutubeQueueItems();
    final playbackLabel =
        _room.youtubePlaybackState == 'playing' ? 'Live sync' : 'Paused';
    final isVideoLoading = hasVideo &&
        _youtubePlayerValue.playerState == ypi.PlayerState.unknown &&
        !_youtubePlayerValue.hasError;

    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: constraints.maxHeight,
        width: constraints.maxWidth,
        child: Align(
          alignment: Alignment.topCenter,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _room.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _youtubeDisplayTitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (canControlStream)
                              Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: TextButton.icon(
                                  onPressed: _isUpdatingYoutubeQueue
                                      ? null
                                      : _showYouTubePicker,
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF31C8F5),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    backgroundColor: const Color(0xFF31C8F5)
                                        .withValues(alpha: 0.1),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                  icon: _isUpdatingYoutubeQueue
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.add_rounded,
                                          size: 16,
                                        ),
                                  label: Text(
                                    _isUpdatingYoutubeQueue
                                        ? 'Updating'
                                        : 'Add video',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildHeaderInfoPill(
                              Icons.play_circle_outline_rounded,
                              playbackLabel,
                              iconColor: const Color(0xFF7AE6FF),
                              textColor: Colors.white,
                            ),
                            _buildHeaderInfoPill(
                              Icons.queue_music_rounded,
                              '${youtubeQueue.length} in playlist',
                            ),
                            _buildHeaderInfoPill(
                              Icons.smart_display_rounded,
                              videoId == null
                                  ? 'No active video'
                                  : 'ID $videoId',
                              iconColor: const Color(0xFFFF6B6B),
                              textColor: Colors.white70,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (!hasVideo)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 28,
                            ),
                            color: Colors.black.withValues(alpha: 0.78),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.red.withValues(alpha: 0.14),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.smart_display_rounded,
                                            color: Color(0xFFFF3D3D),
                                            size: 18,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'YouTube',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'Choose a YouTube video to watch\nand chat with friends in the whole room',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                if (canControlStream)
                                  ElevatedButton(
                                    onPressed: _isUpdatingYoutubeQueue
                                        ? null
                                        : _showYouTubePicker,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0C2C36),
                                      foregroundColor: const Color(0xFF3CD5FF),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 28,
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                    ),
                                    child: const Text(
                                      'Add video',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                else
                                  const Text(
                                    'The owner or admins will start the shared stream here.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 14,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.22),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              children: [
                                AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: ypi.YoutubePlayer(
                                    key: ValueKey(
                                      'shared-youtube-${_sharedYoutubeSessionKey()}',
                                    ),
                                    controller: _youtubeController!,
                                    aspectRatio: 16 / 9,
                                  ),
                                ),
                                if (isVideoLoading)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Container(
                                        color: Colors.black
                                            .withValues(alpha: 0.18),
                                        alignment: Alignment.center,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.56),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                                color: Colors.white10),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              SizedBox(width: 10),
                                              Text(
                                                'Loading shared video',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  top: 12,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 9,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.42,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: Text(
                                            _youtubeDisplayTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (canControlStream) ...[
                                        const SizedBox(width: 10),
                                        Material(
                                          color: Colors.black
                                              .withValues(alpha: 0.42),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          child: InkWell(
                                            onTap: _showYouTubePicker,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            child: const Padding(
                                              padding: EdgeInsets.all(10),
                                              child: Icon(
                                                Icons.playlist_play_rounded,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Positioned(
                                  left: 12,
                                  top: 58,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.smart_display_rounded,
                                          size: 16,
                                          color: Color(0xFFFF3D3D),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'ID: ${videoId ?? '-'}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_youtubePlayerValue.hasError ||
                                    _showYoutubePlaybackRecovery)
                                  Positioned.fill(
                                    child: Container(
                                      color:
                                          Colors.black.withValues(alpha: 0.48),
                                      padding: const EdgeInsets.all(24),
                                      child: Center(
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 280,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                _youtubePlayerValue.hasError
                                                    ? Icons
                                                        .error_outline_rounded
                                                    : Icons
                                                        .play_circle_fill_rounded,
                                                size: 42,
                                                color: Colors.white,
                                              ),
                                              const SizedBox(height: 14),
                                              Text(
                                                _youtubePlayerValue.hasError
                                                    ? 'This shared video needs a fresh reload on this device.'
                                                    : 'Tap once to start the current shared video on this device.',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                _youtubePlayerValue.hasError
                                                    ? 'We will rebind the player to the latest room video session.'
                                                    : 'Autoplay can be blocked until you interact with the embedded player.',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              ElevatedButton.icon(
                                                onPressed: () => unawaited(
                                                  _recoverYoutubePlayback(
                                                    forceRebind:
                                                        _youtubePlayerValue
                                                            .hasError,
                                                  ),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.white,
                                                  foregroundColor:
                                                      const Color(0xFF10151D),
                                                  elevation: 0,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 18,
                                                    vertical: 12,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            999),
                                                  ),
                                                ),
                                                icon: Icon(
                                                  _youtubePlayerValue.hasError
                                                      ? Icons.refresh_rounded
                                                      : Icons
                                                          .play_arrow_rounded,
                                                ),
                                                label: Text(
                                                  _youtubePlayerValue.hasError
                                                      ? 'Reload shared video'
                                                      : 'Start shared video',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (!canControlStream)
                                  Positioned(
                                    right: 12,
                                    top: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F3140)
                                            .withValues(alpha: 0.78),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: const Text(
                                        'Synced with host',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 10),
                        _buildVideoSectionDivider(),
                        const SizedBox(height: 10),
                        _buildYoutubeQueuePanel(
                          queue: youtubeQueue,
                          canControlStream: canControlStream,
                        ),
                      ],
                    ),
                  ),
                  _buildSeatGrid(compact: true),
                  const SizedBox(height: 12),
                  _buildRoomActivitySection(compact: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoSectionDivider() {
    return Container(
      width: double.infinity,
      height: 0.7,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildYoutubeQueuePanel({
    required List<RoomYoutubeQueueItem> queue,
    required bool canControlStream,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.queue_music_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Playlist',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (canControlStream) ...[
                TextButton.icon(
                  onPressed:
                      _isUpdatingYoutubeQueue ? null : _showYouTubePicker,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF31C8F5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor:
                        const Color(0xFF31C8F5).withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  icon: _isUpdatingYoutubeQueue
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.add_rounded,
                          size: 16,
                        ),
                  label: Text(
                    _isUpdatingYoutubeQueue ? 'Updating' : 'Add video',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                '${queue.length} video${queue.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildVideoSectionDivider(),
          const SizedBox(height: 12),
          if (queue.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                canControlStream
                    ? 'Added videos will appear here. Use Add video to build the shared playlist.'
                    : 'The room playlist will appear here once the host or an admin adds videos.',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            )
          else
            _buildYoutubeQueueList(
              queue: queue,
              canControlStream: canControlStream,
            ),
        ],
      ),
    );
  }

  Widget _buildYoutubeQueueList({
    required List<RoomYoutubeQueueItem> queue,
    required bool canControlStream,
  }) {
    final queueListHeight = (queue.length * 96.0).clamp(96.0, 304.0).toDouble();

    return SizedBox(
      height: queueListHeight,
      child: Scrollbar(
        thumbVisibility: queue.length > 3,
        child: ListView.separated(
          primary: false,
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          itemCount: queue.length,
          separatorBuilder: (_, __) => Column(
            children: [
              const SizedBox(height: 10),
              _buildVideoSectionDivider(),
              const SizedBox(height: 10),
            ],
          ),
          itemBuilder: (context, index) => _buildYoutubeQueueTile(
            item: queue[index],
            index: index,
            canControlStream: canControlStream,
          ),
        ),
      ),
    );
  }

  Widget _buildYoutubeQueueTile({
    required RoomYoutubeQueueItem item,
    required int index,
    required bool canControlStream,
  }) {
    final isCurrent = index == 0;
    final title = item.title.isNotEmpty
        ? item.title
        : 'Video ${item.videoId.isNotEmpty ? item.videoId : index + 1}';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isCurrent
            ? const Color(0xFF31C8F5).withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: item.thumbnailUrl.isNotEmpty
                ? Image.network(
                    item.thumbnailUrl,
                    width: 74,
                    height: 46,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 74,
                      height: 46,
                      color: Colors.white10,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.smart_display_rounded,
                        color: Colors.white38,
                      ),
                    ),
                  )
                : Container(
                    width: 74,
                    height: 46,
                    color: Colors.white10,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.smart_display_rounded,
                      color: Colors.white38,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF31C8F5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Now',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      Text(
                        'Up next $index',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (canControlStream) ...[
            if (!isCurrent)
              _buildYoutubeQueueActionButton(
                onPressed: _isUpdatingYoutubeQueue
                    ? null
                    : () => unawaited(_playQueuedYoutubeItem(item)),
                icon: Icons.play_arrow_rounded,
                tooltip: 'Play now',
              ),
            _buildYoutubeQueueActionButton(
              onPressed: _isUpdatingYoutubeQueue
                  ? null
                  : () => unawaited(_removeQueuedYoutubeItem(item)),
              icon: Icons.delete_outline_rounded,
              tooltip: 'Remove',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildYoutubeQueueActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.96),
          foregroundColor: const Color(0xFF10151D),
          padding: EdgeInsets.zero,
          minimumSize: const Size(36, 36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(
          icon,
          size: 20,
          color: const Color(0xFF10151D),
        ),
      ),
    );
  }

  Widget _buildMusicView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 228),
      child: Column(
        children: [
          _buildMediaRoomCard(
            title: 'Room Audio',
            subtitle:
                'Use the normal room layout and play a local track for everyone.',
            icon: Icons.queue_music_rounded,
            mediaTitle: _room.musicTitle,
            hasMedia: _isDirectAudioUrl(_room.musicUrl),
            actionLabel: _room.musicUrl?.isNotEmpty == true
                ? 'Replace track'
                : 'Select track',
            onConfigure: _showMusicSetupSheet,
            secondaryActionLabel:
                _room.musicUrl?.isNotEmpty == true ? 'Settings' : null,
            onSecondaryAction: _room.musicUrl?.isNotEmpty == true
                ? _showMusicSettingsSheet
                : null,
            mediaChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF63E6BE).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      color: Color(0xFF63E6BE),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _room.musicTitle?.isNotEmpty == true
                              ? _room.musicTitle!
                              : 'No track selected yet',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _room.musicUrl?.isNotEmpty == true
                              ? (_roomAudioPlayer.playing
                                  ? 'Playing for everyone in the room'
                                  : 'Ready for everyone in the room')
                              : 'Choose a local audio file to sync this room',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      _room.musicLoop ? 'Loop on' : 'Loop off',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildSeatGrid(),
        ],
      ),
    );
  }

  Widget _buildGameView() {
    final prompt = _gamePrompts[_gamePromptIndex % _gamePrompts.length];
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 228),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.sports_esports_rounded,
                        color: Colors.greenAccent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Party Game Room',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Switch prompts and mini challenges while everyone stays in voice.',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Prompt',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        prompt,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _gamePromptIndex =
                                (_gamePromptIndex + 1) % _gamePrompts.length;
                          });
                        },
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('New Prompt'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _diceValue =
                                ((DateTime.now().microsecondsSinceEpoch % 6) +
                                        1)
                                    .toInt();
                          });
                        },
                        icon: const Icon(Icons.casino_rounded),
                        label: Text('Roll d$_diceValue'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildSeatGrid(compact: true),
          const SizedBox(height: 18),
          _buildRoomActivitySection(compact: true),
        ],
      ),
    );
  }

  Widget _buildMediaRoomCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool hasMedia,
    required String actionLabel,
    required VoidCallback onConfigure,
    String? mediaTitle,
    String? artworkUrl,
    Widget? mediaChild,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
  }) {
    final canManageRoom = _canManageRoom(
      Provider.of<AuthProvider>(context, listen: false).user?.id,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (canManageRoom)
                _buildMediaActionButton(
                  actionLabel,
                  onConfigure,
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (hasMedia && mediaChild != null)
            mediaChild
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  if (artworkUrl?.isNotEmpty == true) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        artworkUrl!,
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Icon(icon, color: Colors.white30, size: 38),
                  const SizedBox(height: 10),
                  Text(
                    mediaTitle?.isNotEmpty == true
                        ? mediaTitle!
                        : canManageRoom
                            ? 'Set this room up directly here without leaving the app.'
                            : 'The host has not set this room up yet.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                  if (canManageRoom) ...[
                    const SizedBox(height: 14),
                    _buildMediaActionButton(
                      actionLabel,
                      onConfigure,
                      filled: true,
                    ),
                  ],
                ],
              ),
            ),
          if (hasMedia && mediaTitle?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(
              mediaTitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (hasMedia &&
              onSecondaryAction != null &&
              secondaryActionLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                children: [
                  Expanded(
                    child: _buildMediaActionButton(
                      secondaryActionLabel,
                      onSecondaryAction,
                      filled: true,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaActionButton(
    String label,
    VoidCallback onTap, {
    bool filled = false,
  }) {
    final child = Text(
      label,
      style: TextStyle(
        color: filled ? Colors.black : Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );

    if (filled) {
      return ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: child,
      );
    }

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: child,
    );
  }

  bool get _hasActiveVideoStage {
    if (_room.type != 'video') return false;

    final videoUrl = _room.youtubeUrl;
    if (videoUrl == null || videoUrl.isEmpty) return false;

    return _activeYoutubeId != null || _extractYoutubeVideoId(videoUrl) != null;
  }

  Widget _buildSeatGrid({bool compact = false}) {
    if (compact && _hasActiveVideoStage) {
      return Column(
        children: [
          _buildCompactVideoSeatWrap(),
        ],
      );
    }

    final seatGrid = Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 32.0 : 24.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: compact ? 20 : 16,
          mainAxisSpacing: compact ? 12 : 20,
          childAspectRatio: 0.8,
        ),
        clipBehavior: Clip.none,
        itemCount: 8,
        itemBuilder: (context, index) {
          final participant = _getParticipantAtSeat(index + 1);
          if (participant == null) return _buildEmptySeat(index + 1);

          return _buildParticipantSeatAvatar(
            participant,
            seatKeyIndex: index + 1,
          );
        },
      ),
    );

    if (compact) {
      return Column(
        children: [
          seatGrid,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: constraints.maxHeight,
        child: Column(
          children: [
            if (_room.type != 'video') ...[
              Center(child: _buildMainSpeaker()),
              const SizedBox(height: 20),
            ],
            seatGrid,
            const Spacer(),
            if (_room.type != 'voice')
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 12),
                child: _buildAudienceStrip(),
              ),
            _buildRoomActivitySection(compact: _room.type != 'voice'),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomActivitySection({bool compact = false}) {
    return ValueListenableBuilder<int>(
      valueListenable: _headerRevision,
      builder: (_, __, ___) => ValueListenableBuilder<int>(
        valueListenable: _chatRevision,
        builder: (_, __, ___) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axisAlignment: 1,
              child: child,
            ),
          ),
          child: _buildRoomActivityPanel(compact: compact),
        ),
      ),
    );
  }

  Widget _buildRoomActivityPanel({bool compact = false}) {
    final hasAnnouncement = _room.announcement.trim().isNotEmpty;
    final hasMessages = _chatMessages.isNotEmpty;
    final showVoiceChatPlaceholder =
        _room.type == 'voice' && !compact && !hasAnnouncement && !hasMessages;
    final useOpenVoiceFeed = _room.type == 'voice' && !compact;

    if (!hasAnnouncement && !hasMessages && !showVoiceChatPlaceholder) {
      return SizedBox(
        key: ValueKey('room-activity-hidden-${compact ? 'compact' : 'full'}'),
        height: compact ? 8 : 12,
      );
    }

    final feedHeight = compact
        ? (hasAnnouncement ? 104.0 : 132.0)
        : (hasAnnouncement ? 118.0 : 156.0);

    if (useOpenVoiceFeed) {
      return Padding(
        key: ValueKey(
          'room-activity-${compact ? 'compact' : 'full'}-${hasAnnouncement ? 1 : 0}-${_chatMessages.length}',
        ),
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox.expand(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasAnnouncement)
                _buildAnnouncementBar(
                    margin: const EdgeInsets.only(bottom: 10)),
              if (hasMessages)
                Expanded(
                  child: RepaintBoundary(
                    child: _buildChatOverlay(),
                  ),
                )
              else if (showVoiceChatPlaceholder)
                _buildVoiceChatEmptyState(),
            ],
          ),
        ),
      );
    }

    return Padding(
      key: ValueKey(
        'room-activity-${compact ? 'compact' : 'full'}-${hasAnnouncement ? 1 : 0}-${_chatMessages.length}',
      ),
      padding: EdgeInsets.fromLTRB(16, 0, 16, compact ? 16 : 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1015).withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.dynamic_feed_rounded,
                    color: Colors.white70,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Room feed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  hasMessages ? '${_chatMessages.length}' : 'Live',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (hasAnnouncement) ...[
              const SizedBox(height: 10),
              _buildAnnouncementBar(margin: EdgeInsets.zero),
            ],
            if (hasMessages) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: feedHeight,
                child: RepaintBoundary(
                  child: _buildChatOverlay(),
                ),
              ),
            ] else if (showVoiceChatPlaceholder) ...[
              const SizedBox(height: 10),
              _buildVoiceChatEmptyState(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceChatEmptyState() {
    if (_isRoomInactive) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.pause_circle_outline_rounded,
                color: Colors.white70,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Room feed paused',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'The room is waiting for a host or admin to return before stage activity can continue.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _canOpenChatComposer
            ? _showChatInput
            : _showChatComposerRestriction,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Room chat space',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _canOpenChatComposer
                          ? 'Messages and photos from the room will appear here. Tap to send the first one.'
                          : 'Messages from the room will appear here once chat is opened for guests.',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _canOpenChatComposer ? 'Open' : 'Locked',
                style: TextStyle(
                  color: _canOpenChatComposer
                      ? const Color(0xFF69DFFF)
                      : Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactVideoSeatWrap() {
    final entries = <Widget>[];

    for (var seatIndex = 1; seatIndex <= 8; seatIndex++) {
      final participant = _getParticipantAtSeat(seatIndex);
      entries.add(
        SizedBox(
          width: 64,
          child: participant == null
              ? _buildEmptySeat(
                  seatIndex,
                  showLabel: false,
                )
              : _buildParticipantSeatAvatar(
                  participant,
                  seatKeyIndex: seatIndex,
                  size: 56,
                ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 14,
        children: entries,
      ),
    );
  }

  Widget _buildVoiceSeatWrap() {
    final entries = <Widget>[];

    for (var seatIndex = 1; seatIndex <= 8; seatIndex++) {
      final participant = _getParticipantAtSeat(seatIndex);
      entries.add(
        SizedBox(
          width: 78,
          child: participant == null
              ? _buildEmptySeat(seatIndex)
              : _buildParticipantSeatAvatar(
                  participant,
                  seatKeyIndex: seatIndex,
                  size: 58,
                ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Speaker seats',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isRoomInactive
                ? 'Room inactive - waiting for host/admin before anyone can join the stage.'
                : 'Tap any open seat to join the stage. The host stays pinned at the top.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 18,
            children: entries,
          ),
        ],
      ),
    );
  }

  Participant? _getHostParticipant() {
    try {
      return _room.participants.firstWhere(
        (participant) => participant.userId == _room.hostId,
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildParticipantSeatAvatar(
    Participant participant, {
    required int seatKeyIndex,
    double size = 60,
  }) {
    final role = participant.userId == _room.hostId ? 'host' : participant.role;
    final currentUserId =
        Provider.of<AuthProvider>(context, listen: false).user?.id;
    final canManageSeatLocks =
        seatKeyIndex > 0 && _canManageSeatLocks(currentUserId);
    final seatState =
        seatKeyIndex > 0 ? _room.seatStateFor(seatKeyIndex) : null;

    return RoomSeatTile(
      seatIndex: seatKeyIndex,
      isLocked: seatState?.isLocked ?? false,
      isInactive: _isRoomInactive,
      hasOccupant: true,
      canManageLock: canManageSeatLocks,
      showLabel: false,
      onToggleLock: seatKeyIndex > 0
          ? () => _toggleSeatLock(
                seatKeyIndex,
                isLocked: seatState?.isLocked == true,
                hasOccupant: true,
              )
          : null,
      child: RepaintBoundary(
        key: _seatKeyMap[seatKeyIndex],
        child: RoomAvatar(
          username: participant.username,
          avatarUrl: participant.avatar,
          level: participant.level,
          levelInfo: participant.user?.levelInfo,
          shopProfile: participant.user?.shopProfile,
          vipMembership: participant.user?.vipMembership,
          vipLevel: participant.vipLevel,
          role: role,
          isSpeaking: participant.isSpeaking,
          isMuting: participant.isMuted,
          isVIP: participant.vipLevel > 0,
          size: size,
          onTap: () => _onParticipantTap(participant),
        ),
      ),
    );
  }

  Widget _buildMainSpeaker() {
    if (_isRoomInactive) {
      return Column(
        children: [
          _buildEmptySeat(
            0,
            showLabel: false,
          ),
        ],
      );
    }

    final host = _getHostParticipant();
    if (host == null) return _buildEmptySeat(0);

    return Column(
      children: [
        _buildParticipantSeatAvatar(
          host,
          seatKeyIndex: 0,
          size: 80,
        ),
      ],
    );
  }

  Participant? _getParticipantAtSeat(int seatIndex) {
    for (final participant in _room.participants) {
      if (_room.type != 'video' && participant.userId == _room.hostId) {
        continue;
      }
      if (participant.seatIndex == seatIndex) {
        return participant;
      }
    }
    return null;
  }

  int _getMySeatIndex() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?.id;
    if (userId == null) return -1;

    return _getUserSeatIndex(userId);
  }

  Widget _buildEmptySeat(
    int index, {
    bool showLabel = true,
  }) {
    final isClosedByLimit = index > _room.maxActiveSpeakers;
    final seatState = _room.seatStateFor(index);
    final isLocked = seatState?.isLocked == true;
    final canManageSeatLocks = index > 0 &&
        _canManageSeatLocks(
          Provider.of<AuthProvider>(context, listen: false).user?.id,
        );

    return Container(
      key: _seatKeyMap[index],
      child: RoomSeatTile(
        seatIndex: index,
        isLocked: isLocked,
        isClosedByLimit: isClosedByLimit,
        isInactive: _isRoomInactive,
        canManageLock: canManageSeatLocks,
        showLabel: showLabel,
        onTapSeat: index > 0 ? () => _takeSeat(index) : null,
        onToggleLock: () => _toggleSeatLock(
          index,
          isLocked: isLocked,
          hasOccupant: false,
        ),
      ),
    );
  }

  Widget _buildAudienceStrip() {
    if (_room.type == 'voice') {
      return const SizedBox.shrink();
    }

    final audience = _room.participants
        .where((participant) => participant.userId != _room.hostId)
        .where((participant) => participant.seatIndex < 0)
        .toList();

    if (audience.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 34,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: audience.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final participant = audience[index];
          return GestureDetector(
            onTap: () => _onParticipantTap(participant),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    participant.username,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (participant.raisedHand) ...[
                    const SizedBox(width: 6),
                    const Text('âœ‹', style: TextStyle(fontSize: 12)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleSeatLock(
    int seatIndex, {
    required bool isLocked,
    required bool hasOccupant,
  }) async {
    if (hasOccupant && !isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only empty seats can be locked.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final updatedRoom = isLocked
          ? await RoomService.unlockSeat(_room.id, seatIndex)
          : await RoomService.lockSeat(_room.id, seatIndex);
      if (!mounted) return;
      if (updatedRoom != null) {
        setState(() => _room = updatedRoom);
      } else {
        await _refreshRoom();
        if (!mounted) return;
      }
      _appendSystemMessage(
        isLocked
            ? 'This seat has been unlocked.'
            : 'Seat $seatIndex was locked by room management.',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _takeSeat(int seatIndex) async {
    if (_isRoomInactive) {
      _showRoomInactiveSnackBar();
      return;
    }

    if (seatIndex > _room.maxActiveSpeakers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Only ${_room.maxActiveSpeakers} speaker seats are open right now.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_room.isLockedSeat(seatIndex)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This seat is locked by room management.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_getParticipantAtSeat(seatIndex) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This seat is already occupied.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final currentSeatIndex = _getMySeatIndex();
    if (currentSeatIndex == seatIndex) {
      return;
    }

    if (currentSeatIndex > 0) {
      final shouldMove = await _confirmSeatChange(
        fromSeat: currentSeatIndex,
        toSeat: seatIndex,
      );
      if (!shouldMove) {
        return;
      }
    }

    try {
      final updatedRoom = await RoomService.takeSeat(_room.id, seatIndex);
      if (updatedRoom != null) {
        Participant? myParticipant;
        for (final participant in updatedRoom.participants) {
          if (participant.userId == _currentUserId) {
            myParticipant = participant;
            break;
          }
        }
        setState(() {
          _room = updatedRoom;
        });
        HapticFeedback.mediumImpact();

        if (myParticipant != null &&
            myParticipant.seatIndex < 0 &&
            myParticipant.raisedHand) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mic request sent to the room owner and admins.'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error taking seat: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _showRoomInactiveSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Room inactive - waiting for host/admin'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<bool> _confirmSeatChange({
    required int fromSeat,
    required int toSeat,
  }) async {
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1921),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
        contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF11B9E8).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.swap_horiz_rounded,
                color: Color(0xFF69DFFF),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Change seat?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'You are already in seat $fromSeat. Move to seat $toSeat now?',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white60,
            ),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF11B9E8),
              foregroundColor: const Color(0xFF07151A),
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: const Text(
              'Yes, move',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> _leaveSeat() async {
    try {
      final updatedRoom = await RoomService.leaveSeat(_room.id);
      if (updatedRoom != null) {
        setState(() {
          _room = updatedRoom;
        });
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      debugPrint('Error leaving seat: $e');
    }
  }

  void _onParticipantTap(Participant participant) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.user;
    final isMe = participant.userId == currentUser?.id;
    final userPermissions =
        RoomPermissions(room: _room, userId: currentUser?.id);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => UserProfileBottomSheet(
        participant: participant,
        room: _room,
        isMe: isMe,
        canModerate: userPermissions.canModerateParticipant(participant),
        isHost: userPermissions.isOwner,
        canManageRoles: userPermissions.canManageAdminRole(participant),
        canManageSpeakerState:
            userPermissions.canManageSpeakerState(participant),
        canSendGifts: userPermissions.canUseRoomGifts,
        isLocallyMuted: !isMe &&
            _voiceService.isParticipantMutedLocally(participant.userId),
        onViewProfile: () {
          Navigator.pop(sheetContext);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => isMe
                  ? const EnhancedProfileScreen()
                  : EnhancedProfileScreen(userId: participant.userId),
            ),
          );
        },
        onOpenChat: () {
          Navigator.pop(sheetContext);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                userId: participant.userId,
                username: participant.username,
                avatar: participant.avatar,
              ),
            ),
          );
        },
        onSendGift: () {
          Navigator.pop(sheetContext);
          _showGiftPanelForUser(participant.userId, participant.username);
        },
        onLeaveSeat: () {
          Navigator.pop(sheetContext);
          _leaveSeat();
        },
        onToggleLocalAudio: isMe
            ? null
            : () async {
                Navigator.pop(sheetContext);
                await _toggleParticipantAudioOnDevice(participant);
              },
        onRefreshRoom: () async {
          await _refreshRoom();
        },
      ),
    );
  }

  Widget _buildChatOverlay() {
    final startIndex = _chatMessages.length > 6 ? _chatMessages.length - 6 : 0;
    final visibleMessages = _chatMessages.sublist(startIndex);

    return Container(
      padding: const EdgeInsets.only(right: 8),
      child: ListView.builder(
        reverse: true,
        itemCount: visibleMessages.length,
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        itemBuilder: (context, index) {
          final msg = visibleMessages[visibleMessages.length - 1 - index];

          if (msg['type'] == 'presence') {
            final username = msg['username']?.toString() ?? 'Someone';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121318).withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.successGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: username,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: ' entered the room',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.68),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (msg['type'] == 'system') {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF8C52FF).withValues(alpha: 0.15),
                      const Color(0xFF52A1FF).withValues(alpha: 0.05),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8C52FF), Color(0xFF52A1FF)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 4),
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Aura Guardian: ',
                                  style: TextStyle(
                                    color: const Color(0xFF52A1FF)
                                        .withValues(alpha: 0.9),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                TextSpan(
                                  text: msg['content'] ?? '',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final sender = msg['senderId'];
          final username = msg['username']?.toString() ??
              (sender is Map ? (sender['username'] ?? 'User') : 'User');
          final isImageMessage = msg['type'] == 'image';
          final imageUrl = _normalizeRoomAssetUrl(msg['content']?.toString());

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16151B).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.03)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$username:',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (isImageMessage && imageUrl != null)
                        GestureDetector(
                          onTap: () =>
                              _showRoomImagePreview(imageUrl, username),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              imageUrl,
                              width: 92,
                              height: 92,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 92,
                                height: 92,
                                color: Colors.white10,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Text(
                          msg['content'] ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showRoomImagePreview(String imageUrl, String username) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF111115),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$username shared a photo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),
            AspectRatio(
              aspectRatio: 1,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 42,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomToolbar(bool isInRoom) {
    final preset = roomBackgroundPresetFor(_room.background);
    final footerDecoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          preset.colors[1].withValues(alpha: 0.28),
          preset.colors.last.withValues(alpha: 0.94),
        ],
      ),
      border: Border(
        top: BorderSide(
          color: Colors.white.withValues(alpha: 0.04),
          width: 0.5,
        ),
      ),
    );

    if (!isInRoom) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: footerDecoration,
        child: SafeArea(
          child: Row(
            children: [
              _buildToolbarIcon(
                _isSpeakerOn
                    ? Icons.volume_up_outlined
                    : Icons.volume_off_outlined,
                Colors.white,
                () {
                  setState(() => _isSpeakerOn = !_isSpeakerOn);
                },
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF15161A),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isJoining) ...[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        _roomErrorMessage != null
                            ? 'Unable to enter room'
                            : _room.isPrivate
                                ? 'Checking room access...'
                                : 'Entering room...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: footerDecoration,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _buildBottomDockActionButton(
              !_isVoiceConnected
                  ? null
                  : (_voiceService.isRemotePlaybackMuted ||
                          _voiceService.remotePlaybackVolume == 0)
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
              !_isVoiceConnected
                  ? const Color(0xFF69DFFF)
                  : (_isSpeakerOn ? Colors.white : Colors.white54),
              _isVoiceConnected
                  ? _showVoiceAudioSheet
                  : () => unawaited(_connectToVoice()),
              assetPath: !_isVoiceConnected
                  ? 'assets/images/room_action_play.png'
                  : null,
              assetSize: 32,
              backgroundColor: !_isVoiceConnected
                  ? const Color(0xFF0C2C36).withValues(alpha: 0.9)
                  : _isSpeakerOn
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.12),
            ),
            const SizedBox(width: 6),
            _buildBottomDockActionButton(
              _isMuted ? null : Icons.mic_rounded,
              _isRoomInactive
                  ? Colors.white38
                  : (_isMuted ? const Color(0xFFFF6B6B) : Colors.white),
              () async {
                if (_isRoomInactive) {
                  _showRoomInactiveSnackBar();
                  return;
                }
                if (!_isVoiceConnected) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Voice is offline')),
                  );
                  return;
                }

                final nextMicEnabled = !_voiceService.isMicEnabled;
                try {
                  await _voiceService.setMicEnabled(nextMicEnabled);
                  if (!mounted) return;
                  setState(() => _isMuted = !_voiceService.isMicEnabled);
                  HapticsUtil.giftReceived();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text(e.toString().replaceFirst('Exception: ', '')),
                    ),
                  );
                }
              },
              assetPath:
                  _isMuted ? 'assets/images/room_action_mic_off.png' : null,
              assetSize: 31,
              backgroundColor: _isRoomInactive
                  ? Colors.white.withValues(alpha: 0.03)
                  : _isMuted
                      ? const Color(0xFFFF3B30).withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.06),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildVoiceRoomComposerAction(),
            ),
            const SizedBox(width: 8),
            _buildBottomDockActionButton(
              null,
              _showQuickReactions ? const Color(0xFFFFD60A) : Colors.white70,
              _showReactionPanel,
              onLongPress: _toggleQuickReactionTray,
              assetPath: 'assets/images/room_action_reaction.png',
              assetSize: 28,
              backgroundColor: _showQuickReactions
                  ? const Color(0xFFFFD60A).withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.05),
            ),
            const SizedBox(width: 6),
            _buildBottomDockActionButton(
              null,
              _canUseRoomGifts ? Colors.white : Colors.white54,
              _canUseRoomGifts ? _showGiftPanelForHost : _showGiftRestriction,
              assetPath: 'assets/images/room_action_gift.png',
              assetSize: 28,
              backgroundColor: _canUseRoomGifts
                  ? null
                  : Colors.white.withValues(alpha: 0.05),
              gradient: _canUseRoomGifts
                  ? const LinearGradient(
                      colors: [Color(0xFFFF3E8E), Color(0xFFFE8B1D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              shadowColor: _canUseRoomGifts ? const Color(0xFFFF3E8E) : null,
            ),
            const SizedBox(width: 6),
            _buildBottomDockActionButton(
              _room.type == 'voice' ? null : Icons.grid_view_rounded,
              Colors.white,
              _room.type == 'voice' ? _showVoiceFeatureLab : _showRoomControl,
              assetPath: _room.type == 'voice'
                  ? 'assets/images/room_action_feature.png'
                  : null,
              assetSize: 28,
              gradient: _room.type == 'voice'
                  ? const LinearGradient(
                      colors: [Color(0xFFFF7A45), Color(0xFF8C52FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              shadowColor:
                  _room.type == 'voice' ? const Color(0xFF8C52FF) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarIcon(
    IconData icon,
    Color color,
    VoidCallback onTap, {
    double size = 22,
    VoidCallback? onLongPress,
    Color? bgColor,
  }) {
    return IconButton(
      onPressed: onTap,
      onLongPress: onLongPress,
      icon: Icon(icon, color: color, size: size),
      style: IconButton.styleFrom(
        backgroundColor: bgColor ?? Colors.white.withValues(alpha: 0.05),
        padding: const EdgeInsets.all(10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildVoiceRoomComposerAction() {
    if (_isRoomInactive) {
      return Material(
        color: Colors.transparent,
        child: Ink(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.pause_circle_outline_rounded,
                  color: Colors.white54,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Room inactive - waiting for host/admin',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isPhotoOnly = !_canSendTextMessages && _canShareRoomImages;
    final isLocked = !_canOpenChatComposer;
    final accent = isLocked
        ? Colors.white54
        : isPhotoOnly
            ? const Color(0xFFFFB703)
            : Colors.white;

    final title = _canSendTextMessages
        ? 'Share your energy'
        : isPhotoOnly
            ? 'Share a room photo'
            : 'Stage chat locked';
    final icon = _canSendTextMessages
        ? Icons.chat_bubble_outline_rounded
        : isPhotoOnly
            ? Icons.photo_library_outlined
            : Icons.shield_moon_rounded;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _canOpenChatComposer
            ? _showChatInput
            : _showChatComposerRestriction,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: accent.withValues(alpha: isLocked ? 0.76 : 0.9),
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        Colors.white.withValues(alpha: isLocked ? 0.7 : 0.92),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isLocked || isPhotoOnly)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isLocked ? 'Locked' : 'Photo',
                    style: TextStyle(
                      color: accent.withValues(alpha: 0.9),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.36),
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomDockActionButton(
    IconData? icon,
    Color color,
    VoidCallback onTap, {
    VoidCallback? onLongPress,
    Color? backgroundColor,
    Gradient? gradient,
    Color? shadowColor,
    String? assetPath,
    double assetSize = 28,
    bool showBoundary = false,
  }) {
    assert(icon != null || assetPath != null);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 44,
        height: 44,
        decoration: showBoundary
            ? BoxDecoration(
                color: gradient == null
                    ? (backgroundColor ?? Colors.white.withValues(alpha: 0.05))
                    : null,
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: gradient == null
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.transparent,
                ),
                boxShadow: shadowColor == null
                    ? null
                    : [
                        BoxShadow(
                          color: shadowColor.withValues(alpha: 0.45),
                          blurRadius: 12,
                          spreadRadius: -4,
                        ),
                      ],
              )
            : null,
        child: Center(
          child: assetPath != null
              ? Image.asset(
                  assetPath,
                  width: assetSize,
                  height: assetSize,
                  fit: BoxFit.contain,
                )
              : Icon(icon, color: color, size: assetSize),
        ),
      ),
    );
  }

  void _showGiftPanelForHost() {
    final hostId = _room.hostId;
    Participant? hostParticipant;
    try {
      hostParticipant = _room.participants.firstWhere(
        (participant) => participant.userId == hostId,
      );
    } catch (_) {
      hostParticipant = null;
    }

    final hostUsername =
        hostParticipant?.user?.username ?? hostParticipant?.username ?? 'Host';
    _showGiftPanelForUser(hostId, hostUsername);
  }

  void _showGiftRestriction() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Gifting is disabled in this room right now.')),
    );
  }

  void _showChatInput() {
    if (!_canOpenChatComposer) {
      _showChatComposerRestriction();
      return;
    }

    _hideQuickReactionTray();
    bool showEmojiPicker = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF0E0E12),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      icon: const Icon(
                        Icons.photo_library_outlined,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        unawaited(_pickAndSendRoomImage());
                      },
                    ),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF0E0E12),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      icon: Icon(
                        showEmojiPicker
                            ? Icons.keyboard
                            : Icons.emoji_emotions_outlined,
                        color: Colors.white,
                      ),
                      onPressed: !_canSendTextMessages
                          ? _showTextChatRestriction
                          : () {
                              setModalState(() {
                                showEmojiPicker = !showEmojiPicker;
                              });
                              if (showEmojiPicker) {
                                FocusScope.of(context).unfocus();
                              }
                            },
                    ),
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF090A0D),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: TextField(
                          controller: _messageController,
                          autofocus: _canSendTextMessages,
                          enabled: _canSendTextMessages,
                          cursorColor: Colors.white,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: _canSendTextMessages
                                ? 'Type a message...'
                                : 'Text chat is locked right now',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            border: InputBorder.none,
                            filled: true,
                            fillColor: Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onTap: () {
                            if (showEmojiPicker) {
                              setModalState(() => showEmojiPicker = false);
                            }
                          },
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF0E0E12),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _canSendTextMessages
                          ? _sendMessage
                          : _showTextChatRestriction,
                    ),
                  ],
                ),
                if (showEmojiPicker)
                  SizedBox(
                    height: 250,
                    child: ep.EmojiPicker(
                      onEmojiSelected: (category, emoji) {
                        HapticsUtil.lightImpact(); // Audit: Added Haptic Sync
                        _messageController.text += emoji.emoji;
                      },
                      config: const ep.Config(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    if (!_canSendTextMessages) {
      _showTextChatRestriction();
      return;
    }
    if (_messageController.text.trim().isEmpty) return;

    final content = _messageController.text.trim();
    _messageController.clear();
    Navigator.pop(context);

    try {
      final sentMessage = await MessageService.sendRoomMessage(
        roomId: _room.id,
        content: content,
      );

      if (!mounted) return;
      if (sentMessage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send that message.')),
        );
        return;
      }

      _appendChatMessage({
        '_id': sentMessage.id,
        'roomId': sentMessage.roomId,
        'userId': sentMessage.senderId,
        'username': sentMessage.senderName,
        'avatar': sentMessage.senderAvatar,
        'content': sentMessage.content,
        'type': sentMessage.type,
        'timestamp': sentMessage.createdAt.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _pickAndSendRoomImage() async {
    if (!_canShareRoomImages) {
      _showPhotoChatRestriction();
      return;
    }

    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (image == null) return;

      final upload = await UploadService.uploadImage(image);
      final imageUrl = upload['url']?.toString();
      if (imageUrl == null || imageUrl.trim().isEmpty) {
        throw Exception('Photo upload failed.');
      }

      final sentMessage = await MessageService.sendRoomMessage(
        roomId: _room.id,
        content: imageUrl,
        type: 'image',
      );
      if (!mounted) return;

      if (sentMessage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share that photo.')),
        );
        return;
      }

      _appendChatMessage({
        '_id': sentMessage.id,
        'roomId': sentMessage.roomId,
        'userId': sentMessage.senderId,
        'username': sentMessage.senderName,
        'avatar': sentMessage.senderAvatar,
        'content': sentMessage.content,
        'type': sentMessage.type,
        'timestamp': sentMessage.createdAt.toIso8601String(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _showTextChatRestriction() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Text chat is currently limited to hosts and admins.'),
      ),
    );
  }

  void _showPhotoChatRestriction() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Photo sharing is currently turned off in this room.'),
      ),
    );
  }

  void _showChatComposerRestriction() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Text and photo sharing are currently locked for guests.'),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'voice':
        return Colors.blueAccent;
      case 'music':
        return Colors.purpleAccent;
      case 'video':
        return Colors.redAccent;
      case 'auction':
        return Colors.orangeAccent;
      case 'game':
        return Colors.greenAccent;
      case 'chat':
        return Colors.tealAccent;
      default:
        return Colors.blueAccent;
    }
  }

  void _showGiftPanelForUser(String userId, String username) {
    if (!_canUseRoomGifts) {
      _showGiftRestriction();
      return;
    }
    showGiftBottomSheet(
      context: context,
      toUserId: userId,
      toUsername: username,
      roomId: _room.id,
    );
  }
}

class _YoutubeVideoOption {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;

  const _YoutubeVideoOption({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
  });

  String? get durationLabel {
    final value = duration;
    if (value == null) return null;

    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class RoomAvatar extends StatelessWidget {
  final String username;
  final String? avatarUrl;
  final int level;
  final LevelProgressSnapshot? levelInfo;
  final UserShopProfile? shopProfile;
  final VipMembershipSnapshot? vipMembership;
  final int vipLevel;
  final String role;
  final bool isSpeaking;
  final bool isMuting;
  final bool isVIP;
  final double size;
  final VoidCallback? onTap;

  const RoomAvatar({
    super.key,
    required this.username,
    this.avatarUrl,
    required this.level,
    this.levelInfo,
    this.shopProfile,
    this.vipMembership,
    this.vipLevel = 0,
    required this.role,
    this.isSpeaking = false,
    this.isMuting = false,
    this.isVIP = false,
    this.size = 60,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isHost = role == 'host';
    final speakingGlow = resolveSpeakingGlowColor(shopProfile);
    final entryColors = resolveEntryEffectColors(shopProfile);
    final displayNameColor = resolveDisplayNameColor(
      shopProfile,
      fallback: Colors.white.withValues(alpha: 0.9),
    );

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (isSpeaking) const _SpeakingPulseEffect(),
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isHost
                      ? const LinearGradient(
                          colors: [Color(0xFFFF7A45), Color(0xFFFFCC00)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: entryColors ??
                              [
                                Colors.white.withValues(alpha: 0.2),
                                Colors.white.withValues(alpha: 0.05),
                              ],
                        ),
                  boxShadow: [
                    if (isHost)
                      BoxShadow(
                        color: const Color(0xFFFF7A45).withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    if (isSpeaking && !isHost)
                      BoxShadow(
                        color: (speakingGlow ?? const Color(0xFF52A1FF))
                            .withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F0E13),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: UserAvatar(
                        username: username,
                        imageUrl: avatarUrl,
                        radius: size / 2,
                        shopProfile: shopProfile,
                        vipMembership: vipMembership,
                        vipLevel: vipLevel,
                      ),
                    ),
                  ),
                ),
              ),
              if (isHost)
                Positioned(
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFCC00),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                    child: const Icon(Icons.workspace_premium,
                        size: 10, color: Colors.black),
                  ),
                ),
              if (isMuting)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16151B),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white10, width: 1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(1),
                      child: Image.asset(
                        'assets/images/room_action_mic_off.png',
                        width: 10,
                        height: 10,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              if (isVIP)
                Positioned(
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0E13),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: VipBadge(
                      membership: vipMembership,
                      fallbackVipLevel: vipLevel,
                      size:
                          size >= 76 ? VipBadgeSize.medium : VipBadgeSize.small,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          VipNameText(
            username,
            membership: vipMembership,
            fallbackVipLevel: vipLevel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            fallbackColor: displayNameColor,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          LevelBadge(
            level: level,
            levelInfo: levelInfo,
            size: size >= 76 ? LevelBadgeSize.medium : LevelBadgeSize.small,
            includePrefix: true,
          ),
        ],
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  final Alignment alignment;
  final double size;

  const _Sparkle({
    required this.alignment,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.7),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.28),
              blurRadius: size * 3,
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeakingPulseEffect extends StatefulWidget {
  const _SpeakingPulseEffect();
  @override
  State<_SpeakingPulseEffect> createState() => _SpeakingPulseEffectState();
}

class _SpeakingPulseEffectState extends State<_SpeakingPulseEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 70 + (30 * _controller.value),
              height: 70 + (30 * _controller.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFF7A45)
                      .withValues(alpha: 0.4 * (1 - _controller.value)),
                  width: 2,
                ),
              ),
            ),
            Container(
              width: 65 + (20 * _controller.value),
              height: 65 + (20 * _controller.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF7A45)
                    .withValues(alpha: 0.15 * (1 - _controller.value)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EqualizerBar extends StatefulWidget {
  final double maxHeight;
  final Duration duration;
  const _EqualizerBar({required this.maxHeight, required this.duration});
  @override
  State<_EqualizerBar> createState() => _EqualizerBarState();
}

class _EqualizerBarState extends State<_EqualizerBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _animation = Tween<double>(begin: 2.0, end: widget.maxHeight)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Container(
        width: 3,
        height: _animation.value,
        decoration: BoxDecoration(
            color: const Color(0xFFFF7A45),
            borderRadius: BorderRadius.circular(1.5)),
      ),
    );
  }
}
