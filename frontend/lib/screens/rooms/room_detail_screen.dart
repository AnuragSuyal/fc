import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../services/room_service.dart';
import '../../models/room_model.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../../utils/haptics_util.dart';
import '../../utils/room_permissions.dart';
import '../../utils/room_presets.dart';
import '../../services/socket_service.dart';
import '../../widgets/gifting/gift_bottom_sheet.dart';
import '../../widgets/gifting/gift_animation_overlay.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/rooms/room_info_bottom_sheet.dart';
import '../../widgets/rooms/room_members_bottom_sheet.dart';
import 'room_settings_screen.dart';
import '../../widgets/rooms/room_control_bottom_sheet.dart';
import '../../widgets/rooms/user_profile_bottom_sheet.dart';
import 'package:flutter/services.dart';
import '../../widgets/rooms/reaction_quick_panel.dart';
import '../../widgets/rooms/reaction_animation_overlay.dart';
// import '../../widgets/rooms/seat_reaction_overlay.dart'; // No longer needed locally
import '../../widgets/rooms/invite_friends_bottom_sheet.dart';
import '../../widgets/rooms/gift_sound_bottom_sheet.dart';
import '../../services/voice_service.dart';
import '../../services/message_service.dart';
import '../../services/upload_service.dart';
import '../profile/enhanced_profile_screen.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as ep;
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

class RoomDetailScreen extends StatefulWidget {
  final RoomModel room;

  const RoomDetailScreen({super.key, required this.room});

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  late RoomModel _room;
  final bool _isLoading = false;
  bool _isJoining = false;
  bool _isExiting = false;
  bool _hasJoinedSocketRoom = false;
  bool _isVoiceConnected = false;
  String? _errorMessage;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _chatMessages = [];
  final ValueNotifier<int> _chatRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _stageRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _headerRevision = ValueNotifier<int>(0);
  StreamSubscription? _messageSubscription;
  StreamSubscription? _updateSubscription;
  StreamSubscription? _voiceSubscription;
  StreamSubscription? _resyncSubscription;
  bool _isMuted = true;
  bool _isSpeakerOn = true;
  final VoiceService _voiceService = VoiceService();
  Timer? _heartbeatTimer;
  Timer? _roomRefreshTimer;
  DateTime? _lastReactionTime;
  YoutubePlayerController? _youtubeController;
  final AudioPlayer _roomAudioPlayer = AudioPlayer();
  final yt.YoutubeExplode _youtubeExplode = yt.YoutubeExplode();
  final Set<YoutubePlayerController> _pendingYoutubeDisposals = {};
  String? _activeYoutubeId;
  String? _activeAudioUrl;
  bool _showQuickReactions = false;
  bool _isRefreshingRoom = false;
  bool _hasPendingRoomRefresh = false;
  bool _hasAttemptedAutoJoin = false;
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
  bool get _canBypassChatRestrictions => _permissions.canManageSafety;
  bool get _canSendTextMessages =>
      !_room.banTextChat || _canBypassChatRestrictions;
  bool get _canShareRoomImages =>
      !_room.banPhotoChat || _canBypassChatRestrictions;
  bool get _canOpenChatComposer => _canSendTextMessages || _canShareRoomImages;
  bool get _canUseRoomGifts => _permissions.canUseRoomGifts;

  // Global Keys for mapping seat positions to global overlay
  final Map<int, GlobalKey> _seatKeyMap = {
    for (int i = 0; i <= 8; i++) i: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _syncMediaController(_room);

    _messageSubscription =
        SocketService.roomMessageStream.listen(_handleIncomingRoomMessage);
    _updateSubscription =
        SocketService.roomUpdateStream.listen(_handleRoomUpdate);
    _voiceSubscription = SocketService.voiceStream.listen(_handleVoiceEvent);
    _resyncSubscription = SocketService.resyncStream.listen((_) {
      if (!mounted) return;
      _scheduleRoomRefresh(delay: const Duration(milliseconds: 220));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeRoom();
      _startHeartbeat();
      _loadInitialMessages();
    });
  }

  Future<void> _loadInitialMessages() async {
    final result = await MessageService.getRoomMessages(_room.id, limit: 40);
    final messages = result['messages'] as List<dynamic>? ?? const [];
    if (!mounted || messages.isEmpty) return;

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
    final videoUrl = room.type == 'video' ? room.youtubeUrl : null;
    final videoId =
        videoUrl == null ? null : YoutubePlayer.convertUrlToId(videoUrl);
    final normalizedAudioUrl =
        _normalizeRoomMediaUrl(room.type == 'music' ? room.musicUrl : null);

    if (videoId == null || videoId.isEmpty) {
      _activeYoutubeId = null;
      _runYoutubeControllerAction((controller) => controller.pause());
    } else if (_youtubeController == null || _activeYoutubeId != videoId) {
      _replaceYoutubeController(videoId);
      return;
    } else if (room.type == 'video') {
      _runYoutubeControllerAction((controller) => controller.play());
      _applyYoutubeAudioDefaults();
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

  void _replaceYoutubeController(String videoId) {
    final previous = _youtubeController;
    final controller = YoutubePlayerController(
      initialVideoId: videoId,
      flags: YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        disableDragSeek: false,
        loop: false,
        isLive: false,
        forceHD: false,
        enableCaption: false,
      ),
    );

    _youtubeController = controller;
    _activeYoutubeId = videoId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeYoutubeId != videoId) return;
      _applyYoutubeAudioDefaults();
    });
    _queueYoutubeControllerDispose(previous);
  }

  void _applyYoutubeAudioDefaults() {
    final controller = _youtubeController;
    if (controller == null) return;

    try {
      controller.unMute();
      controller.setVolume(100);
    } catch (error) {
      debugPrint('YouTube audio defaults skipped: $error');
    }
  }

  bool _isDirectAudioUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return YoutubePlayer.convertUrlToId(url) == null;
  }

  String? _normalizeRoomMediaUrl(String? url) {
    if (url == null || url.isEmpty || kIsWeb) return url;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return url;
    return AppConfig.normalizeBackendUrl(url);
  }

  void _runYoutubeControllerAction(
    void Function(YoutubePlayerController controller) action,
  ) {
    final controller = _youtubeController;
    if (controller == null) return;

    try {
      action(controller);
    } catch (error) {
      debugPrint('YouTube controller action skipped: $error');
    }
  }

  void _queueYoutubeControllerDispose(YoutubePlayerController? controller) {
    if (controller == null || _pendingYoutubeDisposals.contains(controller)) {
      return;
    }

    _pendingYoutubeDisposals.add(controller);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (!_pendingYoutubeDisposals.remove(controller)) return;

        try {
          controller.dispose();
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
          _isSpeakerOn = true;
          _isVoiceConnected = true;
        });
      }
    } catch (e) {
      debugPrint('Voice connection failed: $e');
      if (!mounted) return;
      setState(() {
        _isVoiceConnected = false;
      });
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
        onExit: () {
          Navigator.pop(sheetContext);
          _leaveRoomAndExit();
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

  Future<void> _toggleSpeakerOutput() async {
    if (!_isVoiceConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice is offline')),
      );
      return;
    }

    try {
      final nextSpeakerOn = !_isSpeakerOn;
      await _voiceService.setSpeakerEnabled(nextSpeakerOn);
      if (!mounted) return;
      setState(() => _isSpeakerOn = nextSpeakerOn);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _showInviteFriends() {
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

  void _onModeChanged(String newType) async {
    final updated = await RoomService.updateRoom(_room.id, {'type': newType});
    if (!mounted) return;
    if (updated != null) {
      _syncMediaController(updated);
      setState(() {
        _room = updated;
      });
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
    SocketService.joinRoom(_room.id);
    _hasJoinedSocketRoom = true;
  }

  void _leaveSocketRoom() {
    if (!_hasJoinedSocketRoom) return;
    SocketService.leaveRoom(_room.id);
    _hasJoinedSocketRoom = false;
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _roomRefreshTimer?.cancel();
    _quickReactionTrayTimer?.cancel();
    _messageSubscription?.cancel();
    _updateSubscription?.cancel();
    _voiceSubscription?.cancel();
    _resyncSubscription?.cancel();
    _passwordController.dispose();
    _messageController.dispose();
    _queueYoutubeControllerDispose(_youtubeController);
    _youtubeController = null;
    _youtubeExplode.close();
    unawaited(_roomAudioPlayer.dispose());
    unawaited(_voiceService.disconnect());
    _leaveSocketRoom();
    super.dispose();
  }

  Future<void> _joinRoom({bool showFeedback = true}) async {
    if (_isJoining) return;

    setState(() {
      _isJoining = true;
      _errorMessage = null;
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

        _joinSocketRoom();
        unawaited(_connectToVoice());

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
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
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

  Future<List<_YoutubeVideoOption>> _searchYoutubeVideos(String query) async {
    final results = await _youtubeExplode.search.search(query);
    return results
        .take(12)
        .map(
          (video) => _YoutubeVideoOption(
            id: video.id.value,
            title: video.title,
            author: video.author,
            duration: video.duration,
            thumbnailUrl: video.thumbnails.highResUrl,
          ),
        )
        .toList();
  }

  Future<void> _showYouTubePicker() async {
    final searchController = TextEditingController(
      text: _room.youtubeTitle?.trim().isNotEmpty == true
          ? _room.youtubeTitle!
          : _room.name,
    );
    final initialQuery = searchController.text.trim();
    var results = <_YoutubeVideoOption>[];
    _YoutubeVideoOption? selectedVideo;
    var isSearching = false;
    var didInitialSearch = false;
    String? searchError;
    BuildContext? activeSheetContext;
    late void Function(VoidCallback fn) updateSheetState;

    void safeUpdateSheet(VoidCallback fn) {
      final sheetContext = activeSheetContext;
      if (sheetContext == null || !sheetContext.mounted) return;
      updateSheetState(fn);
    }

    Future<void> runSearch([String? queryOverride]) async {
      final query = (queryOverride ?? searchController.text).trim();
      if (query.isEmpty) return;

      safeUpdateSheet(() {
        isSearching = true;
        searchError = null;
      });

      try {
        final items = await _searchYoutubeVideos(query);
        safeUpdateSheet(() {
          results = items;
          selectedVideo = items.isNotEmpty ? items.first : null;
          isSearching = false;
        });
      } catch (e) {
        safeUpdateSheet(() {
          isSearching = false;
          searchError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }

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
              if (sheetContext.mounted) {
                runSearch(initialQuery);
              }
            });
          }

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
                            onPressed: isSearching ? null : () => runSearch(),
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
                            const Icon(Icons.search_rounded,
                                color: Colors.black54),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: searchController,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) => runSearch(),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'Search YouTube',
                                ),
                              ),
                            ),
                          ],
                        ),
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
                            padding: const EdgeInsets.symmetric(horizontal: 24),
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
                                    '${results.isEmpty ? 0 : 1}/${results.length}',
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
                                      onTap: () => runSearch(initialQuery),
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
                                                      BorderRadius.circular(14),
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
                                                      Text(
                                                        video.title,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color:
                                                              Color(0xFF161827),
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        video.author,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.black45,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                      if (video.durationLabel !=
                                                          null) ...[
                                                        const SizedBox(
                                                            height: 4),
                                                        Text(
                                                          video.durationLabel!,
                                                          style:
                                                              const TextStyle(
                                                            color:
                                                                Colors.black38,
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
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: selectedVideo == null
                              ? null
                              : () {
                                  final video = selectedVideo!;
                                  Navigator.pop(sheetContext);
                                  _applyMediaRoomUpdate(
                                    type: 'video',
                                    theme: {
                                      'youtubeUrl':
                                          'https://www.youtube.com/watch?v=${video.id}',
                                      'youtubeTitle': video.title,
                                      'youtubeThumbnail': video.thumbnailUrl,
                                    },
                                    successMessage: 'YouTube room updated.',
                                  );
                                },
                          icon: const Icon(Icons.playlist_add_rounded),
                          label: const Text('Add video'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF31C8F5),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFBDECF8),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
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

    searchController.dispose();
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
              icon: const Icon(Icons.search_rounded),
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
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    final isInRoom = user != null && _isUserInRoom(user.id);

    try {
      if (isInRoom) {
        await RoomService.leaveRoom(_room.id);
      }
    } finally {
      _leaveSocketRoom();
      await _voiceService.disconnect();
      await _roomAudioPlayer.stop();
      _isVoiceConnected = false;
    }

    if (!mounted) return;
    if (reason != null && reason.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason)),
      );
    }
    Navigator.pop(context);
  }

  Future<bool> _handleBackNavigation() async {
    await _leaveRoomAndExit();
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
    final shouldRebuildShell =
        rebuildPage || previous.background != room.background;
    _syncMediaController(room);
    if (shouldRebuildShell && mounted) {
      setState(() {
        _room = room;
      });
    } else {
      _room = room;
    }
    _announceRoomSettingChanges(previous, room);
    _notifyHeaderChanged();
    _notifyStageChanged();
  }

  void _announceRoomSettingChanges(RoomModel previous, RoomModel next) {
    if (previous.id != next.id) return;

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
    _notifyStageChanged();
    return true;
  }

  bool _updateSeatLockState(int seatIndex, bool locked) {
    final nextLockedSeats = [..._room.lockedSeats];
    final changed = locked
        ? (!nextLockedSeats.contains(seatIndex) &&
            (nextLockedSeats..add(seatIndex)).isNotEmpty)
        : nextLockedSeats.remove(seatIndex);

    if (!changed) return false;
    nextLockedSeats.sort();
    _room = _room.copyWith(lockedSeats: nextLockedSeats);
    _notifyStageChanged();
    return true;
  }

  bool _applyPresenceDelta(int delta) {
    final nextOnlineCount = (_room.onlineCount + delta).clamp(0, 99999).toInt();
    if (nextOnlineCount == _room.onlineCount) return false;

    _room = _room.copyWith(onlineCount: nextOnlineCount);
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
    final currentUserId =
        Provider.of<AuthProvider>(context, listen: false).user?.id;
    if (userId != currentUserId) {
      _appendPresenceMessage(participant.username);
    }
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
      case 'participant_muted':
        if (_updateParticipantState(
          data['userId']?.toString() ?? '',
          muted: data['muted'] == true,
        )) {
          return;
        }
        break;
      case 'seat_locked':
        final seatIndex = int.tryParse('${data['seatIndex']}');
        if (seatIndex != null && _updateSeatLockState(seatIndex, true)) {
          return;
        }
        break;
      case 'seat_unlocked':
        final seatIndex = int.tryParse('${data['seatIndex']}');
        if (seatIndex != null && _updateSeatLockState(seatIndex, false)) {
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
        return;
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

  void _appendPresenceMessage(String username, {bool notify = true}) {
    if (username.trim().isEmpty) return;
    _appendChatMessage({
      '_id': 'presence-${DateTime.now().microsecondsSinceEpoch}',
      'type': 'presence',
      'username': username.trim(),
      'content': 'entered the room',
      'timestamp': DateTime.now().toIso8601String(),
    }, notify: notify && mounted);
  }

  bool _canManageRoom(String? userId) {
    return RoomPermissions(room: _room, userId: userId).canManageRoom;
  }

  bool _isUserInRoom(String userId) {
    return _room.participants.any((p) {
      if (p.user != null) {
        return p.user!.id == userId;
      }
      return p.userId == userId;
    });
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

            if (_errorMessage != null)
              Positioned(
                top: 50,
                left: 20,
                right: 20,
                child: GestureDetector(
                  onTap: () => setState(() => _errorMessage = null),
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
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
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
                    builder: (_, __, ___) => Column(
                      children: [
                        SafeArea(
                          bottom: false,
                          child: _buildMinimalHeader(),
                        ),
                        if (_room.announcement.isNotEmpty)
                          _buildAnnouncementBar(),
                      ],
                    ),
                  ),

                  Expanded(
                    child: Column(
                      children: [
                        ValueListenableBuilder<int>(
                          valueListenable: _chatRevision,
                          builder: (_, __, ___) => AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _buildChatDock(),
                          ),
                        ),
                        Expanded(
                          child: ValueListenableBuilder<int>(
                            valueListenable: _stageRevision,
                            builder: (_, __, ___) => _buildMainArea(),
                          ),
                        ),
                      ],
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

  Widget _buildAnnouncementBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
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
                  () => unawaited(_leaveRoomAndExit()),
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
                    const Icon(Icons.monetization_on,
                        size: 12, color: Colors.amber),
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
                    const Icon(Icons.diamond,
                        size: 12, color: Colors.purpleAccent),
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
            onPressed: () => unawaited(_leaveRoomAndExit()),
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
            () => unawaited(_leaveRoomAndExit()),
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
                    const Icon(
                      Icons.monetization_on_rounded,
                      size: 12,
                      color: Colors.amber,
                    ),
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
                    const Icon(
                      Icons.diamond_rounded,
                      size: 12,
                      color: Colors.purpleAccent,
                    ),
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

  Widget _buildAuctionView() {
    return Column(
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
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.monetization_on,
                            color: Colors.amber, size: 20),
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
                        child:
                            Icon(Icons.person, color: Colors.white, size: 28)),
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
      ],
    );
  }

  Widget _buildVideoView() {
    final hasVideo = _room.youtubeUrl?.isNotEmpty == true &&
        YoutubePlayer.convertUrlToId(_room.youtubeUrl!) != null &&
        _youtubeController != null;
    final videoId = _activeYoutubeId ??
        YoutubePlayer.convertUrlToId(_room.youtubeUrl ?? '');

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 228),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF2B2B33),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _room.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Video ID: ${videoId ?? 'Not selected'}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                if (!hasVideo)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 28,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(22),
                    ),
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
                                color: Colors.red.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
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
                        const SizedBox(height: 28),
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
                        const SizedBox(height: 26),
                        ElevatedButton(
                          onPressed: _showYouTubePicker,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0C2C36),
                            foregroundColor: const Color(0xFF3CD5FF),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          child: const Text(
                            'Add video',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      color: Colors.black,
                      child: Stack(
                        children: [
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: YoutubePlayer(
                              controller: _youtubeController!,
                              showVideoProgressIndicator: true,
                              progressIndicatorColor: Colors.white,
                              topActions: <Widget>[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _room.youtubeTitle ?? _room.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _showYouTubePicker,
                                  icon: const Icon(
                                    Icons.playlist_play_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                              bottomActions: const [
                                CurrentPosition(),
                                SizedBox(width: 8),
                                ProgressBar(isExpanded: true),
                                SizedBox(width: 8),
                                RemainingDuration(),
                                FullScreenButton(),
                              ],
                              onReady: _applyYoutubeAudioDefaults,
                            ),
                          ),
                          Positioned(
                            left: 12,
                            top: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
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
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _buildSeatGrid(compact: true),
        ],
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
    return Column(
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
                              ((DateTime.now().microsecondsSinceEpoch % 6) + 1)
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
      ],
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

    return _activeYoutubeId != null ||
        YoutubePlayer.convertUrlToId(videoUrl) != null;
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
            Center(child: _buildMainSpeaker()),
            const SizedBox(height: 20),
            seatGrid,
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: _buildAudienceStrip(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactVideoSeatWrap() {
    final entries = <Widget>[];
    final host = _getHostParticipant();

    if (host != null) {
      entries.add(
        SizedBox(
          width: 64,
          child: _buildParticipantSeatAvatar(
            host,
            seatKeyIndex: 0,
            size: 56,
          ),
        ),
      );
    }

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

    return RepaintBoundary(
      key: _seatKeyMap[seatKeyIndex],
      child: RoomAvatar(
        username: participant.username,
        avatarUrl: participant.avatar,
        role: role,
        isSpeaking: participant.isSpeaking,
        isMuting: participant.isMuted,
        isVIP: participant.vipLevel > 0,
        size: size,
        onTap: () => _onParticipantTap(participant),
      ),
    );
  }

  Widget _buildMainSpeaker() {
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
      if (participant.userId == _room.hostId) continue;
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
    final isLocked = _room.isLockedSeat(index) || isClosedByLimit;
    final canManageRoom = _canManageRoom(
      Provider.of<AuthProvider>(context, listen: false).user?.id,
    );

    return Container(
      key: _seatKeyMap[index],
      child: Column(
        children: [
          GestureDetector(
            onTap: isLocked ? null : () => _takeSeat(index),
            onLongPress: canManageRoom && !isClosedByLimit
                ? () async {
                    try {
                      if (isLocked) {
                        await RoomService.unlockSeat(_room.id, index);
                        _appendSystemMessage('Seat $index was unlocked.');
                      } else {
                        await RoomService.lockSeat(_room.id, index);
                        _appendSystemMessage('Seat $index was locked.');
                      }
                      if (!mounted) return;
                      await _refreshRoom();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            e.toString().replaceFirst('Exception: ', ''),
                          ),
                        ),
                      );
                    }
                  }
                : null,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isLocked
                    ? const Color(0xFFFF3B30).withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.03),
                border: Border.all(
                  color: isLocked
                      ? const Color(0xFFFF3B30).withValues(alpha: 0.3)
                      : Colors.white10,
                  width: 1.5,
                  style: isLocked ? BorderStyle.solid : BorderStyle.none,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (!isLocked)
                    CustomPaint(
                      size: const Size(56, 56),
                      painter: _DottedCirclePainter(color: Colors.white24),
                    ),
                  Icon(
                    isLocked ? Icons.lock_outline_rounded : Icons.add_rounded,
                    color: isLocked ? const Color(0xFFFF3B30) : Colors.white24,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (showLabel) ...[
            const SizedBox(height: 8),
            Text(
              isClosedByLimit
                  ? 'Closed'
                  : isLocked
                      ? 'Locked'
                      : 'Seat $index',
              style: TextStyle(
                color: isLocked ? Colors.redAccent : Colors.white24,
                fontSize: 10,
              ),
            ),
          ],
        ],
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

  Future<void> _takeSeat(int seatIndex) async {
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
          content: Text('This seat is locked right now.'),
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
        onSendGift: () {
          Navigator.pop(sheetContext);
          _showGiftPanelForUser(participant.userId, participant.username);
        },
        onLeaveSeat: () {
          Navigator.pop(sheetContext);
          _leaveSeat();
        },
        onRefreshRoom: () async {
          await _refreshRoom();
        },
      ),
    );
  }

  Widget _buildChatDock() {
    if (_chatMessages.isEmpty) {
      return const SizedBox(
        key: ValueKey('chat-dock-hidden'),
        height: 6,
      );
    }

    return Padding(
      key: const ValueKey('chat-dock-visible'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.84,
            maxHeight: 176,
          ),
          child: RepaintBoundary(
            child: _buildChatOverlay(),
          ),
        ),
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
                        _errorMessage != null
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
              Icons.graphic_eq_rounded,
              _isSpeakerOn ? Colors.white70 : Colors.white38,
              _toggleSpeakerOutput,
              backgroundColor: _isSpeakerOn
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.12),
            ),
            const SizedBox(width: 6),
            _buildBottomDockActionButton(
              _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              _isMuted ? const Color(0xFFFF6B6B) : Colors.white70,
              () async {
                if (!_isVoiceConnected) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Voice is offline')),
                  );
                  return;
                }
                setState(() => _isMuted = !_isMuted);
                await _voiceService.setMicEnabled(!_isMuted);
                HapticsUtil.giftReceived();
              },
              backgroundColor: _isMuted
                  ? const Color(0xFFFF3B30).withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.06),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: _canOpenChatComposer
                    ? _showChatInput
                    : _showChatComposerRestriction,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.8)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _canSendTextMessages
                            ? Icons.chat_bubble_outline_rounded
                            : _canShareRoomImages
                                ? Icons.photo_library_outlined
                                : Icons.block_rounded,
                        color: Colors.black54,
                        size: 17,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _canSendTextMessages
                              ? 'Share your energy'
                              : _canShareRoomImages
                                  ? 'Photos only right now'
                                  : 'Chat locked for guests',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _buildBottomDockActionButton(
              Icons.sentiment_satisfied_alt_rounded,
              _showQuickReactions ? const Color(0xFFFFD60A) : Colors.white70,
              _showReactionPanel,
              onLongPress: _toggleQuickReactionTray,
              backgroundColor: _showQuickReactions
                  ? const Color(0xFFFFD60A).withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.05),
            ),
            const SizedBox(width: 6),
            _buildBottomDockActionButton(
              Icons.card_giftcard_rounded,
              _canUseRoomGifts ? Colors.white : Colors.white54,
              _canUseRoomGifts ? _showGiftPanelForHost : _showGiftRestriction,
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
              Icons.person_add_alt_1_rounded,
              Colors.white,
              _showInviteFriends,
            ),
            const SizedBox(width: 6),
            _buildBottomDockActionButton(
              Icons.grid_view_rounded,
              Colors.white,
              _showRoomControl,
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

  Widget _buildBottomDockActionButton(
    IconData icon,
    Color color,
    VoidCallback onTap, {
    VoidCallback? onLongPress,
    Color? backgroundColor,
    Gradient? gradient,
    Color? shadowColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
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
        ),
        child: Icon(icon, color: color, size: 18),
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
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                      ),
                      icon: const Icon(
                        Icons.photo_library_outlined,
                        color: Colors.black87,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        unawaited(_pickAndSendRoomImage());
                      },
                    ),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                      ),
                      icon: Icon(
                        showEmojiPicker
                            ? Icons.keyboard
                            : Icons.emoji_emotions_outlined,
                        color: Colors.black87,
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
                      child: TextField(
                        controller: _messageController,
                        autofocus: _canSendTextMessages,
                        enabled: _canSendTextMessages,
                        cursorColor: Colors.black87,
                        style: const TextStyle(color: Colors.black87),
                        decoration: InputDecoration(
                          hintText: _canSendTextMessages
                              ? 'Type a message...'
                              : 'Text chat is locked right now',
                          hintStyle: const TextStyle(color: Colors.black54),
                          border: InputBorder.none,
                        ),
                        onTap: () {
                          if (showEmojiPicker) {
                            setModalState(() => showEmojiPicker = false);
                          }
                        },
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                      ),
                      icon: const Icon(Icons.send, color: Colors.black87),
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GiftBottomSheet(
        toUserId: userId,
        toUsername: username,
        roomId: _room.id,
      ),
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
                          colors: [
                            Colors.white.withValues(alpha: 0.2),
                            Colors.white.withValues(alpha: 0.05)
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
                        color: const Color(0xFF52A1FF).withValues(alpha: 0.4),
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
                    child: const Icon(Icons.mic_off_rounded,
                        size: 10, color: Colors.white54),
                  ),
                ),
              if (isVIP)
                Positioned(
                  bottom: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF8C52FF), Color(0xFF52A1FF)]),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFF0F0E13), width: 1.5),
                    ),
                    child: const Text(
                      'VIP',
                      style: TextStyle(
                          fontSize: 7,
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
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

class _DottedCirclePainter extends CustomPainter {
  final Color color;
  _DottedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const double dashWidth = 3;
    const double dashSpace = 3;
    final double radius = size.width / 2;
    double startAngle = 0;

    while (startAngle < 2 * 3.141592653589793) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(radius, radius), radius: radius),
        startAngle,
        dashWidth / radius,
        false,
        paint,
      );
      startAngle += (dashWidth + dashSpace) / radius;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
