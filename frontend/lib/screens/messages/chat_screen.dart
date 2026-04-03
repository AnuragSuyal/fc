import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/coin_transfer_model.dart';
import '../../models/message_model.dart';
import '../../models/level_progress_model.dart';
import '../../models/shop_models.dart';
import '../../models/vip_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/app_route_observer.dart';
import '../../services/chat_activity_service.dart';
import '../../services/coin_transfer_service.dart';
import '../../services/chat_voice_note_service.dart';
import '../../services/friend_service.dart';
import '../../services/message_service.dart';
import '../../services/room_service.dart';
import '../../services/profile_service.dart';
import '../../services/socket_service.dart';
import '../../services/upload_service.dart';
import '../../utils/constants.dart';
import '../../utils/media_url.dart';
import '../../utils/shop_appearance_resolver.dart';
import '../../widgets/gifting/gift_bottom_sheet.dart';
import '../../widgets/gift_image.dart';
import '../../widgets/level_badge.dart';
import '../../widgets/rounded_scaffold.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/coin_transfer/coin_transfer_sheet.dart';
import '../../widgets/vip/vip_badge.dart';
import '../../widgets/vip/vip_name_text.dart';
import '../profile/enhanced_profile_screen.dart';
import '../rooms/room_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String username;
  final String? avatar;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.username,
    this.avatar,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with RouteAware, WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<StreamSubscription> _subscriptions = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ChatVoiceNoteRecorder _voiceRecorder = ChatVoiceNoteRecorder();
  final Set<String> _consumedPrivatePhotoIds = <String>{};

  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isPaging = false;
  bool _isSending = false;
  bool _isRecordingVoice = false;
  bool _isPartnerTyping = false;
  bool _hasSentTyping = false;
  bool _showEmojiPicker = false;
  bool _friendBusy = false;
  bool _voicePointerDown = false;
  Timer? _typingTimer;
  Future<void>? _loadMessagesFuture;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _hasLoadedOnce = false;
  String? _currentUserId;
  String? _resolvedPeerUserId;
  String? _activeAudioMessageId;
  Map<String, dynamic> _relationship = const {};
  Map<String, dynamic> _peerProfile = const {};
  CoinTransferEligibility? _coinTransferEligibility;
  Duration _voiceRecordingDuration = Duration.zero;
  bool _routeObserverAttached = false;
  bool _isCoinTransferLoading = false;
  bool _isCoinTransferPurchaseBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = context.read<AuthProvider>().user?.id;
    _resolvedPeerUserId =
        _looksLikeMongoId(widget.userId) ? widget.userId : null;
    _loadRelationship();
    _loadPrivatePhotoState();
    if (_effectivePeerUserId != null) {
      _loadMessages();
      _loadCoinTransferEligibility(silent: true);
    } else {
      _isLoading = true;
    }
    _setupListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_routeObserverAttached) {
      appRouteObserver.unsubscribe(this);
    }
    _setChatActivity(false);
    _clearTypingState();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _audioPlayer.dispose();
    _voiceRecorder.dispose();
    _typingTimer?.cancel();
    _voicePointerDown = false;
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeObserverAttached) return;

    final route = ModalRoute.of(context);
    if (route != null) {
      appRouteObserver.subscribe(this, route);
      _routeObserverAttached = true;
      _setChatActivity(route.isCurrent);
    }
  }

  @override
  void didPush() {
    _setChatActivity(true);
  }

  @override
  void didPopNext() {
    _setChatActivity(true);
  }

  @override
  void didPushNext() {
    _setChatActivity(false);
  }

  @override
  void didPop() {
    _setChatActivity(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setChatActivity(ModalRoute.of(context)?.isCurrent == true);
      return;
    }

    _setChatActivity(false);
  }

  bool get _isFriend => _relationship['isFriend'] == true;
  bool get _hasIncomingRequest => _relationship['hasIncomingRequest'] == true;
  bool get _hasOutgoingRequest => _relationship['hasOutgoingRequest'] == true;
  bool get _canSendFriendRequest =>
      _relationship['canSendFriendRequest'] == true;
  bool get _canMessage => _relationship['canMessage'] == true || _isFriend;
  bool get _canSendGift => _isFriend && !_isBlocked;
  bool get _isBlocked => _relationship['isBlocked'] == true;
  bool get _coinTransferFeatureEnabled =>
      _coinTransferEligibility?.featureEnabled == true;
  bool get _coinTransferUnlocked => _coinTransferEligibility?.unlocked == true;
  bool get _canShowCoinTransferUnlock =>
      _isFriend &&
      !_isBlocked &&
      _coinTransferFeatureEnabled &&
      !_coinTransferUnlocked &&
      (_coinTransferEligibility?.canPurchaseUnlock ?? false);
  bool get _canShowCoinTransferEntry =>
      _isFriend &&
      !_isBlocked &&
      _coinTransferFeatureEnabled &&
      _coinTransferUnlocked;
  int get _introMessageLimit {
    final raw = _relationship['introMessageLimit'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 3;
  }

  int get _introMessagesUsed {
    final raw = _relationship['introMessagesUsed'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  int get _introMessagesRemaining {
    final raw = _relationship['introMessagesRemaining'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return _isFriend ? _introMessageLimit : 0;
  }

  bool get _hasIntroAccess =>
      !_isFriend && !_isBlocked && _introMessagesRemaining > 0;

  String? get _effectivePeerUserId =>
      _resolvedPeerUserId ??
      (_looksLikeMongoId(widget.userId) ? widget.userId : null);
  Set<String> get _peerIdCandidates {
    final peerUid = _peerProfile['uid']?.toString().trim() ?? '';
    return <String>{
      widget.userId,
      if (_resolvedPeerUserId != null) _resolvedPeerUserId!,
      if (peerUid.isNotEmpty) peerUid,
    };
  }

  String get _peerDisplayName {
    final username = _peerProfile['username']?.toString().trim();
    if (username != null && username.isNotEmpty) {
      return username;
    }
    return widget.username;
  }

  String? get _peerAvatar {
    final avatar = _peerProfile['avatar']?.toString().trim();
    if (avatar != null && avatar.isNotEmpty) {
      return avatar;
    }
    return widget.avatar;
  }

  bool get _isPeerOnline => _peerProfile['status']?['isOnline'] == true;

  int get _peerLevel {
    final raw = _peerProfile['level'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 1;
  }

  LevelProgressSnapshot get _peerLevelInfo =>
      LevelProgressSnapshot.fromRoot(_peerProfile);
  UserShopProfile get _peerShopProfile =>
      UserShopProfile.fromJson(_peerProfile['shopProfile']);
  VipMembershipSnapshot get _peerVipMembership =>
      VipMembershipSnapshot.fromJson(
        _peerProfile['vipMembership'] is Map
            ? Map<String, dynamic>.from(_peerProfile['vipMembership'] as Map)
            : null,
      );

  int get _peerVipLevel {
    final raw = _peerProfile['vipLevel'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  bool _looksLikeMongoId(String? value) {
    final trimmed = value?.trim() ?? '';
    return RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(trimmed);
  }

  bool _matchesPeerUserId(String? value) {
    final candidate = value?.trim();
    if (candidate == null || candidate.isEmpty) return false;
    return _peerIdCandidates.contains(candidate);
  }

  String _requirePeerUserId() {
    final peerUserId = _effectivePeerUserId;
    if (peerUserId == null || peerUserId.isEmpty) {
      throw Exception(
          'Chat partner is still loading. Please try again in a moment.');
    }
    return peerUserId;
  }

  void _setChatActivity(bool isActive) {
    for (final candidate in _peerIdCandidates) {
      if (candidate.trim().isEmpty) continue;
      if (isActive) {
        ChatActivityService.markDirectChatOpen(candidate);
      } else {
        ChatActivityService.markDirectChatClosed(candidate);
      }
    }
  }

  void _setupListeners() {
    _subscriptions.add(SocketService.dmStream.listen(_handleIncomingMessage));
    _subscriptions.add(SocketService.typingStream.listen(_handleTypingEvent));
    _subscriptions.add(
      SocketService.messageReactionStream.listen(_handleReactionEvent),
    );
    _subscriptions.add(
      SocketService.messageReadStream.listen(_handleReadReceipt),
    );
    _subscriptions.add(
      SocketService.messageDeletedStream.listen(_handleDeletedMessage),
    );
    _subscriptions.add(
      SocketService.friendStream.listen(_handleFriendEvent),
    );
    _subscriptions.add(
      SocketService.profileStream.listen(_handleProfileEvent),
    );
    _subscriptions.add(
      SocketService.coinTransferStream.listen(_handleCoinTransferEvent),
    );
    _subscriptions.add(
      SocketService.resyncStream.listen((_) {
        unawaited(_loadMessages(reset: true, silent: _messages.isNotEmpty));
        unawaited(_loadRelationship());
        unawaited(_loadCoinTransferEligibility(silent: true));
      }),
    );
    _subscriptions.add(
      _audioPlayer.playerStateStream.listen((state) {
        if (!mounted) return;
        if (!state.playing &&
            state.processingState != ProcessingState.loading &&
            state.processingState != ProcessingState.buffering) {
          setState(() => _activeAudioMessageId = null);
        }
      }),
    );
    _subscriptions.add(
      _voiceRecorder.durationStream.listen((duration) {
        if (!mounted) return;
        setState(() => _voiceRecordingDuration = duration);
      }),
    );
  }

  Future<void> _loadMessages({
    bool reset = false,
    bool silent = false,
  }) async {
    final pending = _loadMessagesFuture;
    if (pending != null) {
      return pending;
    }

    final future = _loadMessagesInternal(reset: reset, silent: silent);
    _loadMessagesFuture = future;
    try {
      await future;
    } finally {
      if (identical(_loadMessagesFuture, future)) {
        _loadMessagesFuture = null;
      }
    }
  }

  Future<void> _loadMessagesInternal({
    bool reset = false,
    bool silent = false,
  }) async {
    final peerUserId = _effectivePeerUserId;
    if (peerUserId == null || peerUserId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPaging = false;
        });
      }
      return;
    }

    if (reset) {
      _currentPage = 1;
      _hasMore = true;
    }

    if (!_hasMore && !reset) return;
    if (_currentPage > 1 && _isPaging) return;

    final requestedPage = _currentPage;
    final shouldShowPrimaryLoader =
        requestedPage == 1 && (!silent || !_hasLoadedOnce);

    setState(() {
      if (requestedPage == 1) {
        if (shouldShowPrimaryLoader) {
          _isLoading = true;
        }
      } else {
        _isPaging = true;
      }
    });

    final result = await MessageService.getDirectMessages(
      peerUserId,
      page: requestedPage,
    );

    if (!mounted) return;

    final incomingMessages = List<MessageModel>.from(
      result['messages'] as List? ?? const [],
    ).reversed.toList(growable: false);
    final totalPages = result['pagination']?['pages'];

    setState(() {
      if (requestedPage == 1) {
        _messages = incomingMessages;
        _hasLoadedOnce = true;
      } else {
        _messages = [..._messages, ...incomingMessages];
      }

      _hasMore = totalPages is num ? totalPages > requestedPage : false;
      _isLoading = false;
      _isPaging = false;
    });

    if (_messages.any((message) => _matchesPeerUserId(message.senderId))) {
      unawaited(_markAsRead());
    }

    if (requestedPage == 1 && _messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  Future<void> _loadRelationship() async {
    try {
      final profile = await ProfileService.getProfile(widget.userId);
      if (!mounted) return;
      final userMap = profile['user'] is Map
          ? Map<String, dynamic>.from(profile['user'] as Map)
          : const <String, dynamic>{};
      final nextResolvedPeerUserId =
          userMap['_id']?.toString() ?? userMap['id']?.toString();
      final previousPeerUserId = _effectivePeerUserId;

      setState(() {
        _peerProfile = userMap;
        _resolvedPeerUserId = _looksLikeMongoId(nextResolvedPeerUserId)
            ? nextResolvedPeerUserId
            : _resolvedPeerUserId;
        _relationship = profile['relationship'] is Map
            ? Map<String, dynamic>.from(profile['relationship'] as Map)
            : const {};
      });

      final nextPeerUserId = _effectivePeerUserId;
      if (nextPeerUserId != null &&
          nextPeerUserId.isNotEmpty &&
          nextPeerUserId != previousPeerUserId) {
        _setChatActivity(ModalRoute.of(context)?.isCurrent == true);
        unawaited(_loadMessages(reset: true, silent: _messages.isNotEmpty));
      }
      unawaited(_loadCoinTransferEligibility(silent: true));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _relationship = const {};
      });
    }
  }

  Future<void> _loadPrivatePhotoState() async {
    final prefs = await SharedPreferences.getInstance();
    final consumedIds =
        prefs.getStringList('consumed_private_photos') ?? const [];
    if (!mounted) return;
    setState(() {
      _consumedPrivatePhotoIds.addAll(consumedIds);
    });
  }

  Future<void> _loadCoinTransferEligibility({bool silent = false}) async {
    final peerUserId = _effectivePeerUserId;
    final currentUserId = _currentUserId;
    if (peerUserId == null ||
        peerUserId.isEmpty ||
        currentUserId == null ||
        currentUserId.isEmpty) {
      if (!silent && mounted) {
        setState(() => _coinTransferEligibility = null);
      }
      return;
    }

    if (!silent && mounted) {
      setState(() => _isCoinTransferLoading = true);
    }

    try {
      final eligibility = await CoinTransferService.getEligibility(
        receiverUserId: peerUserId,
        chatId: CoinTransferService.buildDirectChatId(
          currentUserId,
          peerUserId,
        ),
      );
      if (!mounted) return;
      setState(() {
        _coinTransferEligibility = eligibility;
        _isCoinTransferLoading = false;
      });
    } catch (error) {
      CoinTransferService.debugPrintTransferError(error);
      if (!mounted) return;
      setState(() {
        _isCoinTransferLoading = false;
        if (!silent) {
          _coinTransferEligibility = null;
        }
      });
    }
  }

  Future<void> _markPrivatePhotoConsumed(String messageId) async {
    if (_consumedPrivatePhotoIds.contains(messageId)) return;
    final prefs = await SharedPreferences.getInstance();
    final nextIds = [..._consumedPrivatePhotoIds, messageId];
    await prefs.setStringList('consumed_private_photos', nextIds);
    if (!mounted) return;
    setState(() {
      _consumedPrivatePhotoIds.add(messageId);
    });
  }

  void _handleIncomingMessage(Map<String, dynamic> data) {
    final messageJson = data['message'];
    if (messageJson is! Map) return;

    final currentUserId = _currentUserId;
    if (currentUserId == null) return;

    final message =
        MessageModel.fromJson(Map<String, dynamic>.from(messageJson));
    final participantIds = <String>{
      message.senderId,
      if (message.recipientId != null) message.recipientId!,
    };
    final isRelevant = participantIds.contains(currentUserId) &&
        participantIds.any(_matchesPeerUserId);

    if (!isRelevant || _messages.any((item) => item.id == message.id)) {
      return;
    }

    _insertIncomingMessage(message);
    _scrollToBottom();

    if (_matchesPeerUserId(message.senderId)) {
      unawaited(_markAsRead());
    }
  }

  void _insertIncomingMessage(MessageModel message) {
    setState(() {
      if (_messages.any((item) => item.id == message.id)) {
        return;
      }
      _messages = [message, ..._messages];
    });
  }

  void _handleTypingEvent(Map<String, dynamic> data) {
    if (!_matchesPeerUserId(data['userId']?.toString())) return;
    final isTyping = data['isTyping'] == true;
    if (_isPartnerTyping == isTyping) return;
    setState(() => _isPartnerTyping = isTyping);
  }

  void _handleReactionEvent(Map<String, dynamic> data) {
    final messageId = data['messageId']?.toString();
    final userId = data['userId']?.toString();
    final reaction = data['reaction']?.toString();
    if (messageId == null || userId == null || reaction == null) return;
    _updateMessageReaction(
      messageId,
      userId,
      reaction,
      active: data.containsKey('active') ? data['active'] == true : null,
      createdAt: data['createdAt']?.toString(),
    );
  }

  void _handleReadReceipt(Map<String, dynamic> data) {
    final currentUserId = _currentUserId;
    final byUserId = data['byUserId']?.toString();
    final fromUserId = data['fromUserId']?.toString();
    if (currentUserId == null ||
        !_matchesPeerUserId(byUserId) ||
        fromUserId != currentUserId) {
      return;
    }

    setState(() {
      _messages = _messages.map((message) {
        final isOutgoingToCurrentChat = message.senderId == currentUserId &&
            _matchesPeerUserId(message.recipientId);
        if (!isOutgoingToCurrentChat || message.readBy.isNotEmpty) {
          return message;
        }

        return message.copyWith(
          readBy: [
            ...message.readBy,
            {
              'userId': byUserId,
              'readAt': DateTime.now().toIso8601String(),
            },
          ],
        );
      }).toList(growable: false);
    });
  }

  void _handleDeletedMessage(Map<String, dynamic> data) {
    final messageId = data['messageId']?.toString();
    if (messageId == null || messageId.isEmpty) return;

    setState(() {
      _messages = _messages
          .where((message) => message.id != messageId)
          .toList(growable: false);
    });
  }

  void _handleFriendEvent(Map<String, dynamic> data) {
    final type = data['_eventType']?.toString() ?? '';
    final peerId = _peerUserIdFromEvent(data);
    if (!_matchesPeerUserId(peerId)) return;

    switch (type) {
      case 'friend_online':
        _patchPeerPresence(true);
        break;
      case 'friend_offline':
        _patchPeerPresence(false);
        break;
      default:
        unawaited(_loadRelationship());
        break;
    }
  }

  void _handleProfileEvent(Map<String, dynamic> data) {
    final eventType = data['_eventType']?.toString() ?? '';
    if (eventType != 'profile_updated') return;

    final user = data['user'];
    final userId =
        user is Map ? user['id']?.toString() ?? user['_id']?.toString() : null;
    if (!_matchesPeerUserId(userId) || user is! Map) return;

    final nextUser = Map<String, dynamic>.from(_peerProfile);
    nextUser.addAll(Map<String, dynamic>.from(user));

    final fields = data['fields'];
    if (fields is Map) {
      nextUser.addAll(Map<String, dynamic>.from(fields));
    }

    setState(() {
      _peerProfile = nextUser;
      final nextResolvedPeerUserId =
          nextUser['_id']?.toString() ?? nextUser['id']?.toString();
      if (_looksLikeMongoId(nextResolvedPeerUserId)) {
        _resolvedPeerUserId = nextResolvedPeerUserId;
      }
    });
  }

  void _handleCoinTransferEvent(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    if (type == 'coin_transfer_unlock_updated') {
      unawaited(_loadCoinTransferEligibility(silent: true));
      return;
    }

    if (type != 'coin_transfer_completed') {
      return;
    }

    final transfer = data['transfer'];
    if (transfer is! Map) {
      return;
    }

    final chatId = transfer['chatId']?.toString() ?? '';
    final expectedChatId = CoinTransferService.buildDirectChatId(
      _currentUserId ?? '',
      _effectivePeerUserId ?? '',
    );
    if (chatId.isNotEmpty &&
        expectedChatId.isNotEmpty &&
        chatId != expectedChatId) {
      return;
    }

    unawaited(_loadCoinTransferEligibility(silent: true));
  }

  String? _peerUserIdFromEvent(Map<String, dynamic> data) {
    final user = data['user'];
    if (user is Map) {
      return user['_id']?.toString() ?? user['id']?.toString();
    }
    final from = data['from'];
    if (from is Map) {
      return from['_id']?.toString() ?? from['id']?.toString();
    }
    return data['userId']?.toString();
  }

  void _patchPeerPresence(bool isOnline) {
    setState(() {
      final nextProfile = Map<String, dynamic>.from(_peerProfile);
      final status = nextProfile['status'] is Map
          ? Map<String, dynamic>.from(nextProfile['status'] as Map)
          : <String, dynamic>{};
      status['isOnline'] = isOnline;
      status['lastActive'] = DateTime.now().toIso8601String();
      nextProfile['status'] = status;
      _peerProfile = nextProfile;
    });
  }

  void _updateMessageReaction(
    String messageId,
    String userId,
    String reaction, {
    bool? active,
    String? createdAt,
  }) {
    setState(() {
      final index = _messages.indexWhere((message) => message.id == messageId);
      if (index == -1) return;

      final message = _messages[index];
      final nextReactions = List<Reaction>.from(message.reactions);
      final existingIndex = nextReactions.indexWhere(
        (item) => item.userId == userId && item.reaction == reaction,
      );

      if (active == false && existingIndex != -1) {
        nextReactions.removeAt(existingIndex);
      } else if (active == true && existingIndex == -1) {
        nextReactions.add(
          Reaction(
            userId: userId,
            reaction: reaction,
            createdAt: createdAt != null
                ? DateTime.tryParse(createdAt) ?? DateTime.now()
                : DateTime.now(),
          ),
        );
      } else if (active == null) {
        if (existingIndex != -1) {
          nextReactions.removeAt(existingIndex);
        } else {
          nextReactions.add(
            Reaction(
              userId: userId,
              reaction: reaction,
              createdAt: DateTime.now(),
            ),
          );
        }
      }

      _messages[index] = message.copyWith(reactions: nextReactions);
    });
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _handleTyping(String value) {
    if (value.trim().isEmpty) {
      _typingTimer?.cancel();
      _clearTypingState();
      return;
    }

    final peerUserId = _effectivePeerUserId;
    if (peerUserId == null || peerUserId.isEmpty) return;

    if (!_hasSentTyping) {
      _hasSentTyping = true;
      SocketService.sendTyping(recipientId: peerUserId, isTyping: true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), _clearTypingState);
  }

  void _clearTypingState() {
    if (!_hasSentTyping) return;
    _hasSentTyping = false;
    final peerUserId = _effectivePeerUserId;
    if (peerUserId == null || peerUserId.isEmpty) return;
    SocketService.sendTyping(recipientId: peerUserId, isTyping: false);
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.errorRed,
      ),
    );
  }

  void _applyIntroMessageUsage() {
    if (_isFriend || _isBlocked) return;

    final nextUsed = _introMessagesUsed >= _introMessageLimit
        ? _introMessageLimit
        : _introMessagesUsed + 1;
    final nextRemaining =
        nextUsed >= _introMessageLimit ? 0 : _introMessageLimit - nextUsed;

    setState(() {
      _relationship = {
        ..._relationship,
        'introMessageLimit': _introMessageLimit,
        'introMessagesUsed': nextUsed,
        'introMessagesRemaining': nextRemaining,
        'requiresFriendshipForMore': nextRemaining == 0,
        'canMessage': nextRemaining > 0,
      };
    });
  }

  void _handleSuccessfulOutgoingMessage(MessageModel message) {
    _insertIncomingMessage(message);
    _scrollToBottom();
    _applyIntroMessageUsage();
  }

  Future<void> _handleVoicePressStart() async {
    if (!_voiceRecorder.supportsPressAndHold ||
        !_canMessage ||
        _isSending ||
        _isRecordingVoice) {
      return;
    }

    _voicePointerDown = true;
    await _startVoiceRecording();
    if (!mounted) return;

    if (!_voicePointerDown && _isRecordingVoice) {
      await _stopVoiceRecordingAndSend();
    }
  }

  Future<void> _handleVoicePressEnd({bool canceled = false}) async {
    _voicePointerDown = false;

    if (_isRecordingVoice) {
      if (canceled) {
        await _cancelVoiceRecording();
      } else {
        await _stopVoiceRecordingAndSend();
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || !_canMessage || _isSending) {
      return;
    }

    setState(() {
      _isSending = true;
      _showEmojiPicker = false;
    });

    final content = _messageController.text.trim();
    _messageController.clear();

    try {
      final peerUserId = _requirePeerUserId();
      final message = await MessageService.sendDirectMessage(
        recipientId: peerUserId,
        content: content,
      );
      if (!mounted) return;
      if (message == null) {
        throw Exception('Could not send message right now.');
      }

      _handleSuccessfulOutgoingMessage(message);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _sendEmoji(String emoji) async {
    if (!_canMessage || _isSending) return;

    try {
      final peerUserId = _requirePeerUserId();
      final message = await MessageService.sendDirectMessage(
        recipientId: peerUserId,
        content: emoji,
        type: 'emoji',
      );
      if (!mounted) return;
      if (message == null) {
        _showError('Could not send emoji right now.');
        return;
      }

      setState(() => _showEmojiPicker = false);
      _handleSuccessfulOutgoingMessage(message);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _pickAndSendImage({bool isPrivate = false}) async {
    if (!_canMessage || _isSending) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1440,
      maxHeight: 1440,
      imageQuality: isPrivate ? 76 : 82,
    );
    if (picked == null) return;

    setState(() => _isSending = true);
    try {
      final peerUserId = _requirePeerUserId();
      final upload = await UploadService.uploadImage(picked);
      final url = upload['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Image upload failed');
      }

      final message = await MessageService.sendDirectMessage(
        recipientId: peerUserId,
        content: url,
        type: isPrivate ? 'private_image' : 'image',
        metadata: isPrivate
            ? {
                'privateImage': true,
                'ephemeralSeconds': 5,
                'screenshotProtection': true,
              }
            : null,
      );
      if (!mounted) return;
      if (message == null) {
        throw Exception('Could not send image right now.');
      }

      _handleSuccessfulOutgoingMessage(message);

      if (isPrivate && mounted) {
        final note = kIsWeb
            ? 'Private photo sent. It auto-hides after 5 seconds when opened. Chrome cannot fully block screenshots.'
            : 'Private photo sent. It auto-hides after 5 seconds when opened.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(note)));
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _pickAndSendVoiceFile() async {
    if (!_canMessage || _isSending) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['m4a', 'mp3', 'aac', 'wav', 'ogg', 'webm'],
      withData: true,
    );
    final picked =
        result != null && result.files.isNotEmpty ? result.files.first : null;
    if (picked == null) return;

    final source = _platformFileToXFile(
      picked,
      fallbackMimeType: 'audio/webm',
    );
    if (source == null) {
      _showError('Could not access the selected audio file.');
      return;
    }

    setState(() => _isSending = true);
    try {
      final peerUserId = _requirePeerUserId();
      final upload = await UploadService.uploadAudio(source);
      final url = upload['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Audio upload failed');
      }

      final message = await MessageService.sendDirectMessage(
        recipientId: peerUserId,
        content: url,
        type: 'voice',
        metadata: {
          'filename': picked.name,
          'mimetype': upload['mimetype'],
        },
      );
      if (!mounted) return;
      if (message == null) {
        throw Exception('Could not send voice message right now.');
      }

      _handleSuccessfulOutgoingMessage(message);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _startVoiceRecording() async {
    if (!_canMessage || _isSending || _isRecordingVoice) return;

    final started = await _voiceRecorder.start();
    if (!mounted) return;

    if (!started) {
      _showError(
        'Hold-to-record is unavailable here. Use the file picker for audio instead.',
      );
      return;
    }

    setState(() {
      _isRecordingVoice = true;
      _voiceRecordingDuration = Duration.zero;
      _showEmojiPicker = false;
    });
  }

  Future<void> _stopVoiceRecordingAndSend() async {
    if (!_isRecordingVoice) return;

    setState(() {
      _isRecordingVoice = false;
      _isSending = true;
    });

    try {
      final peerUserId = _requirePeerUserId();
      final recorded = await _voiceRecorder.stop();
      if (!mounted) return;

      if (recorded == null || recorded.duration.inMilliseconds < 450) {
        setState(() {
          _isSending = false;
          _voiceRecordingDuration = Duration.zero;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hold a little longer to send a voice note.'),
          ),
        );
        return;
      }

      final upload = await UploadService.uploadAudio(recorded.file);
      final url = upload['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Audio upload failed');
      }

      final message = await MessageService.sendDirectMessage(
        recipientId: peerUserId,
        content: url,
        type: 'voice',
        metadata: {
          'filename': recorded.file.name,
          'mimetype': upload['mimetype'] ?? recorded.mimeType,
          'durationMs': recorded.duration.inMilliseconds,
        },
      );
      if (!mounted) return;
      if (message == null) {
        throw Exception('Could not send voice message right now.');
      }

      _handleSuccessfulOutgoingMessage(message);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _voiceRecordingDuration = Duration.zero;
        });
      }
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isRecordingVoice) return;
    await _voiceRecorder.cancel();
    if (!mounted) return;
    setState(() {
      _isRecordingVoice = false;
      _voiceRecordingDuration = Duration.zero;
    });
  }

  XFile? _platformFileToXFile(
    PlatformFile file, {
    required String fallbackMimeType,
  }) {
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return XFile.fromData(
        Uint8List.fromList(bytes),
        name: file.name,
        mimeType: file.extension == null
            ? fallbackMimeType
            : '${fallbackMimeType.split('/').first}/${file.extension}',
      );
    }

    final path = file.path;
    if (path != null && path.isNotEmpty) {
      return XFile(path, name: file.name);
    }

    return null;
  }

  Future<void> _toggleVoicePlayback(MessageModel message) async {
    final voiceUrl = _normalizeMediaUrl(message.content);
    if (voiceUrl == null || voiceUrl.isEmpty) return;

    try {
      if (_activeAudioMessageId == message.id && _audioPlayer.playing) {
        await _audioPlayer.stop();
        if (!mounted) return;
        setState(() => _activeAudioMessageId = null);
        return;
      }

      await _audioPlayer.stop();
      await _audioPlayer.setUrl(voiceUrl);
      await _audioPlayer.play();
      if (!mounted) return;
      setState(() => _activeAudioMessageId = message.id);
    } catch (error) {
      _showError('Audio playback failed.');
      debugPrint('Voice playback failed: $error');
    }
  }

  String? _normalizeMediaUrl(String? value) {
    return resolveMediaUrl(value);
  }

  Future<void> _openPrivatePhoto(MessageModel message) async {
    if (_consumedPrivatePhotoIds.contains(message.id)) return;

    final imageUrl = _normalizeMediaUrl(message.content);
    if (imageUrl == null || imageUrl.isEmpty) {
      _showError('Private photo is unavailable.');
      return;
    }

    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, __, ___) => _EphemeralPhotoViewer(
          imageUrl: imageUrl,
          seconds: message.ephemeralSeconds,
          screenshotNote: kIsWeb
              ? 'This photo hides after 5 seconds. Chrome cannot fully block screenshots.'
              : 'This photo hides after 5 seconds.',
        ),
      ),
    );

    await _markPrivatePhotoConsumed(message.id);
  }

  Future<void> _handleRelationshipAction() async {
    if (_friendBusy || _isFriend || _isBlocked) return;
    if (!_hasIncomingRequest && !_canSendFriendRequest) return;

    final peerUserId = _effectivePeerUserId;
    if (peerUserId == null || peerUserId.isEmpty) {
      _showError('User is still loading. Please try again in a moment.');
      return;
    }

    setState(() => _friendBusy = true);
    try {
      bool success = false;
      if (_hasIncomingRequest) {
        success = await FriendService.acceptFriendRequest(peerUserId);
        if (success && mounted) {
          setState(() {
            _relationship = {
              ..._relationship,
              'isFriend': true,
              'hasIncomingRequest': false,
              'hasOutgoingRequest': false,
              'canSendFriendRequest': false,
              'canMessage': true,
              'introMessagesRemaining': _introMessageLimit,
              'requiresFriendshipForMore': false,
            };
          });
        }
      } else if (_canSendFriendRequest) {
        success = await FriendService.sendFriendRequest(peerUserId);
        if (success && mounted) {
          setState(() {
            _relationship = {
              ..._relationship,
              'hasOutgoingRequest': true,
              'canSendFriendRequest': false,
            };
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() => _friendBusy = false);
      }
    }
  }

  String _relationshipLabel() {
    if (_isFriend) return 'Friends';
    if (_hasIncomingRequest) return 'Accept Friend';
    if (_isBlocked) return 'Unavailable';
    if (_hasIntroAccess) return 'Intro Chat';
    if (_hasOutgoingRequest) return 'Request Pending';
    return 'Add Friend';
  }

  String _relationshipActionLabel() {
    if (_hasIncomingRequest) return 'Accept Friend';
    return 'Add Friend';
  }

  String _relationshipDescription() {
    if (_isFriend) {
      return 'Realtime chat is open for messages, voice notes, private photos, gifts, and media.';
    }
    if (_isBlocked) {
      return 'Private chat is unavailable for this user right now.';
    }
    if (_hasIncomingRequest) {
      if (_hasIntroAccess) {
        final remainingLabel =
            _introMessagesRemaining == 1 ? 'message' : 'messages';
        return 'You can still send $_introMessagesRemaining more $remainingLabel, or accept the friend request now to unlock unlimited chat, gifts, and media.';
      }
      return 'Accept the friend request to unlock unlimited chat, gifts, and media instantly.';
    }
    if (_hasIntroAccess) {
      final remainingLabel =
          _introMessagesRemaining == 1 ? 'message' : 'messages';
      final requestSuffix = _hasOutgoingRequest
          ? ' Your friend request is already waiting for them.'
          : '';
      return 'You can send $_introMessagesRemaining more $remainingLabel before friendship is required. Private photos and voice notes work in this intro window.$requestSuffix';
    }
    if (_hasOutgoingRequest) {
      return 'Friend request sent. You have used the 3 intro messages, so chatting unlocks again when they accept.';
    }
    return 'You have used the 3 intro messages. Add each other as friends to keep chatting.';
  }

  Future<void> _handleReaction(String messageId, String reaction) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return;

    final messageIndex =
        _messages.indexWhere((message) => message.id == messageId);
    if (messageIndex == -1) return;

    final hasReaction = _messages[messageIndex].reactions.any(
          (item) => item.userId == currentUserId && item.reaction == reaction,
        );

    _updateMessageReaction(
      messageId,
      currentUserId,
      reaction,
      active: !hasReaction,
      createdAt: DateTime.now().toIso8601String(),
    );

    final success = await MessageService.addReaction(messageId, reaction);
    if (!success && mounted) {
      _updateMessageReaction(
        messageId,
        currentUserId,
        reaction,
        active: hasReaction,
      );
      _showError('Could not update reaction right now.');
    }
  }

  Future<void> _handleDeleteMessage(String messageId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await MessageService.deleteMessage(messageId);
    if (!success || !mounted) return;
    setState(() {
      _messages.removeWhere((message) => message.id == messageId);
    });
  }

  Future<void> _markAsRead() async {
    final peerUserId = _effectivePeerUserId;
    if (peerUserId == null || peerUserId.isEmpty) return;
    await MessageService.markAsRead(peerUserId);
  }

  Future<void> _showCoinTransferUnlock() async {
    if (_isCoinTransferPurchaseBusy) return;
    final limits = _coinTransferEligibility?.limits;
    final unlockPrice = limits?.unlockPriceInr ?? 599;
    final unlockCurrency = limits?.unlockCurrency ?? 'INR';
    final receiverPercentage = limits?.feePercentages.receiverPercentage ?? 70;
    final platformPercentage = limits?.feePercentages.platformPercentage ?? 30;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unlock Coin Transfers',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Send coins directly to friends in private chat.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$unlockPrice $unlockCurrency',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'When you send coins, your friend receives $receiverPercentage% and Friend Circle keeps $platformPercentage% as the platform fee.',
                          style: TextStyle(
                            color: Color(0xFF475569),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Maybe later'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF111827),
                          ),
                          child: const Text('Continue'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isCoinTransferPurchaseBusy = true);
    try {
      final result = await CoinTransferService.purchaseUnlock(
        purchaseSource: 'stripe',
      );
      if (!mounted) return;

      if (result.pendingCheckout && result.checkoutUrl.isNotEmpty) {
        final launched = await launchUrl(
          Uri.parse(result.checkoutUrl),
          mode: LaunchMode.externalApplication,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              launched
                  ? 'Complete the purchase and return to Friend Circle.'
                  : 'Checkout link is ready. Open it from your browser to finish the unlock.',
            ),
          ),
        );
      } else if (result.unlocked) {
        await _loadCoinTransferEligibility();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Coin transfers are now unlocked.'),
            backgroundColor: AppColors.successGreen,
          ),
        );
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isCoinTransferPurchaseBusy = false);
      }
    }
  }

  Future<void> _openCoinTransferComposer() async {
    final eligibility = _coinTransferEligibility;
    final peerUserId = _effectivePeerUserId;
    if (eligibility == null || peerUserId == null || peerUserId.isEmpty) {
      _showError(
          'Coin transfers are still loading. Please try again in a moment.');
      return;
    }

    if (eligibility.unlocked != true) {
      await _showCoinTransferUnlock();
      return;
    }

    if (!eligibility.eligibleAfterUnlock && eligibility.reasons.isNotEmpty) {
      _showError(eligibility.reasons.first.message);
      return;
    }

    final result = await showCoinTransferComposerSheet(
      context: context,
      eligibility: eligibility,
      receiverName: _peerDisplayName,
      onPreview: (amount) => CoinTransferService.previewTransfer(
        receiverUserId: peerUserId,
        chatId: eligibility.chatId,
        amount: amount,
      ),
      onSubmit: (amount) => CoinTransferService.sendTransfer(
        receiverUserId: peerUserId,
        chatId: eligibility.chatId,
        amount: amount,
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    context.read<AuthProvider>().updateBalance(
          coins: result.newBalance.coins,
          gems: result.newBalance.gems,
        );
    await _loadCoinTransferEligibility(silent: true);

    if (result.messageJson != null) {
      final message = MessageModel.fromJson(result.messageJson!);
      if (_messages.every((entry) => entry.id != message.id)) {
        _handleSuccessfulOutgoingMessage(message);
      }
    }

    if (!mounted) return;
    final receiverAmount = result.transfer.receiverAmount;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Sent ${result.transfer.grossAmount} coins. $_peerDisplayName received $receiverAmount.',
        ),
        backgroundColor: AppColors.successGreen,
      ),
    );
  }

  Future<void> _showGiftComposer() async {
    final peerUserId = _effectivePeerUserId;
    if (peerUserId == null || peerUserId.isEmpty) {
      _showError('User is still loading. Please try again in a moment.');
      return;
    }

    final sent = await showGiftBottomSheet(
      context: context,
      toUserId: peerUserId,
      toUsername: _peerDisplayName,
    );

    if (sent == true && mounted) {
      _scrollToBottom();
    }
  }

  Future<void> _openInvitedRoom(MessageModel message) async {
    final roomId = message.roomInviteRoomId;
    if (roomId == null || roomId.isEmpty) {
      _showError('This room invite is unavailable.');
      return;
    }

    try {
      final room = await RoomService.getRoomById(roomId);
      if (!mounted || room == null) {
        _showError('This room is unavailable right now.');
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
      );
    } catch (error) {
      _showError(error);
    }
  }

  void _loadMore() {
    if (!_hasMore || _isLoading || _isPaging) return;
    _currentPage += 1;
    unawaited(_loadMessages(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _currentUserId;
    final theme = Theme.of(context);

    return RoundedScaffold(
      titleWidget: _buildChatHeader(),
      actions: [
        _buildHeaderAction(
          icon: Icons.info_outline_rounded,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EnhancedProfileScreen(userId: widget.userId),
              ),
            );
          },
        ),
      ],
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFF8FAFC),
              theme.colorScheme.surface.withValues(alpha: 0.96),
            ],
          ),
        ),
        child: Column(
          children: [
            if (!_isFriend && !_isBlocked) _buildRelationshipBanner(),
            Expanded(
              child: Stack(
                children: [
                  Positioned(
                    top: 22,
                    right: -26,
                    child: Container(
                      width: 124,
                      height: 124,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF2563EB).withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 42,
                    left: -34,
                    child: Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  if (_isLoading && !_hasLoadedOnce && _messages.isEmpty)
                    const Center(child: CircularProgressIndicator())
                  else if (_messages.isEmpty)
                    _buildEmptyConversation()
                  else
                    _buildChatTimeline(currentUserId),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _isPartnerTyping
                  ? _buildTypingBar()
                  : const SizedBox.shrink(),
            ),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildChatHeader() {
    final accent = _isPartnerTyping
        ? const Color(0xFF8B5CF6)
        : (_isPeerOnline ? const Color(0xFF22C55E) : const Color(0xFF94A3B8));

    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            UserAvatar(
              imageUrl: _peerAvatar,
              username: _peerDisplayName,
              radius: 21,
              shopProfile: _peerShopProfile,
              vipMembership: _peerVipMembership,
              vipLevel: _peerVipLevel,
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: VipNameText(
                      _peerDisplayName,
                      membership: _peerVipMembership,
                      fallbackVipLevel: _peerVipLevel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      fallbackColor: resolveDisplayNameColor(
                        _peerShopProfile,
                        fallback: const Color(0xFF111827),
                      ),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_peerVipLevel > 0) ...[
                    const SizedBox(width: 6),
                    VipBadge(
                      membership: _peerVipMembership,
                      fallbackVipLevel: _peerVipLevel,
                      size: VipBadgeSize.small,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  _headerStatusLabel(),
                  key: ValueKey<String>(_headerStatusLabel()),
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        LevelBadge(
          level: _peerLevel,
          levelInfo: _peerLevelInfo,
          size: LevelBadgeSize.medium,
          showGlow: false,
        ),
      ],
    );
  }

  Widget _buildHeaderAction({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7DEE8)),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: const Color(0xFF111827)),
      ),
    );
  }

  String _headerStatusLabel() {
    if (_isPartnerTyping) return 'typing in realtime...';
    if (_isBlocked) return 'chat unavailable';
    if (_isFriend && _isPeerOnline) return 'online now';
    if (_isFriend && _canMessage) return 'live chat';
    if (_hasIntroAccess) {
      final remainingLabel = _introMessagesRemaining == 1
          ? '1 intro message left'
          : '$_introMessagesRemaining intro messages left';
      return 'intro chat - $remainingLabel';
    }
    if (_hasOutgoingRequest) return 'friend request pending';
    if (_hasIncomingRequest) return 'accept friend to unlock unlimited chat';
    return 'add friend to continue';
  }

  Widget _buildChatTimeline(String? currentUserId) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification &&
            notification.metrics.extentAfter < 180 &&
            _hasMore &&
            !_isLoading) {
          _loadMore();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        cacheExtent: 900,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        itemCount: _messages.length + (_isPaging ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _messages.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final message = _messages[index];
          final isFromMe = message.senderId == currentUserId;
          return _buildMessageCard(message, isFromMe);
        },
      ),
    );
  }

  Widget _buildMessageCard(MessageModel message, bool isFromMe) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;
    final metaColor = isFromMe ? Colors.white70 : const Color(0xFF64748B);

    return GestureDetector(
      onLongPress: () {
        if (isFromMe) {
          _showMessageOptions(message);
        } else {
          _showReactionOptions(message);
        }
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: 12,
          left: isFromMe ? 58 : 0,
          right: isFromMe ? 0 : 36,
        ),
        child: Row(
          mainAxisAlignment:
              isFromMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isFromMe)
              Padding(
                padding: const EdgeInsets.only(right: 10, bottom: 22),
                child: UserAvatar(
                  imageUrl: _peerAvatar,
                  username: _peerDisplayName,
                  radius: 16,
                ),
              ),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: isFromMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                      decoration: BoxDecoration(
                        gradient: isFromMe
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFF2563EB),
                                  Color(0xFF1D4ED8),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isFromMe ? null : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(24),
                          topRight: const Radius.circular(24),
                          bottomLeft: Radius.circular(isFromMe ? 24 : 8),
                          bottomRight: Radius.circular(isFromMe ? 8 : 24),
                        ),
                        border: Border.all(
                          color: isFromMe
                              ? Colors.white.withValues(alpha: 0.12)
                              : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isFromMe
                                    ? const Color(0xFF2563EB)
                                    : Colors.black)
                                .withValues(alpha: isFromMe ? 0.18 : 0.05),
                            blurRadius: isFromMe ? 18 : 14,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.replyTo != null) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isFromMe
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isFromMe
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Text(
                                _messageSummary(message.replyTo!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isFromMe
                                      ? Colors.white70
                                      : const Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          _buildMessageContent(message, isFromMe),
                        ],
                      ),
                    ),
                    if (message.reactions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: message.reactions
                            .map(
                              (reaction) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  reaction.reaction,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatMessageTime(message.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: metaColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isFromMe) ...[
                          const SizedBox(width: 6),
                          Icon(
                            message.isRead
                                ? Icons.done_all_rounded
                                : Icons.done_rounded,
                            size: 14,
                            color: message.isRead
                                ? const Color(0xFF38BDF8)
                                : metaColor,
                          ),
                        ],
                      ],
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

  String _formatMessageTime(DateTime dateTime) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(dateTime),
    );
  }

  Widget _buildEmptyConversation() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2563EB).withValues(alpha: 0.08),
              ),
              child: const Icon(
                Icons.forum_rounded,
                size: 36,
                color: Color(0xFF2563EB),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _canMessage
                  ? (_hasIntroAccess
                      ? 'Start the intro chat'
                      : 'Start the conversation')
                  : _relationshipLabel(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _canMessage
                  ? (_hasIntroAccess
                      ? 'You can send up to three intro messages here. Photos, private photos, and voice notes work before friendship is required.'
                      : 'Messages, voice notes, gifts, photos, private photos, reactions, and room invites update here in realtime.')
                  : _relationshipDescription(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF8B5CF6),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Typing',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, _buildTypingDot),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelationshipBanner() {
    final introOpen = _hasIntroAccess;
    final accent =
        introOpen ? const Color(0xFF2563EB) : const Color(0xFFB45309);
    final icon = _hasIncomingRequest
        ? Icons.person_add_alt_1_rounded
        : introOpen
            ? Icons.mark_chat_unread_outlined
            : _hasOutgoingRequest
                ? Icons.schedule_rounded
                : Icons.lock_outline_rounded;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            if (introOpen) const Color(0xFFF3F8FF) else const Color(0xFFFFF7ED),
            if (introOpen) const Color(0xFFF8FAFC) else const Color(0xFFFFFBEB),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: introOpen ? const Color(0xFFBFDBFE) : const Color(0xFFFED7AA),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _relationshipLabel(),
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _relationshipDescription(),
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (_hasIncomingRequest || _canSendFriendRequest)
            FilledButton(
              onPressed: _friendBusy ? null : _handleRelationshipAction,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF111827),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _friendBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_relationshipActionLabel()),
            )
          else if (_hasOutgoingRequest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Text(
                'Requested',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isRecordingVoice) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4F4),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFFFD5D5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.mic_rounded,
                    color: AppColors.errorRed,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Recording ${_formatVoiceDuration(_voiceRecordingDuration)} • release to send',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _cancelVoiceRecording,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _composerToolChip(
                  icon: Icons.card_giftcard_rounded,
                  label: 'Gift',
                  onPressed: _canSendGift ? _showGiftComposer : null,
                ),
                if (_canShowCoinTransferUnlock || _canShowCoinTransferEntry)
                  _composerToolChip(
                    icon: _canShowCoinTransferUnlock
                        ? Icons.workspace_premium_outlined
                        : Icons.toll_rounded,
                    label: _canShowCoinTransferUnlock
                        ? (_isCoinTransferPurchaseBusy
                            ? 'Unlocking...'
                            : 'Unlock Coins')
                        : (_isCoinTransferLoading
                            ? 'Loading...'
                            : 'Send Coins'),
                    onPressed: _isCoinTransferPurchaseBusy
                        ? null
                        : _openCoinTransferComposer,
                  ),
                _composerToolChip(
                  icon: Icons.photo_library_outlined,
                  label: 'Photo',
                  onPressed: _canMessage ? () => _pickAndSendImage() : null,
                ),
                _composerToolChip(
                  icon: Icons.timer_outlined,
                  label: 'Private',
                  onPressed: _canMessage
                      ? () => _pickAndSendImage(isPrivate: true)
                      : null,
                ),
                _buildVoiceComposerChip(),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  enabled: _canMessage,
                  onChanged: _handleTyping,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  onTap: () {
                    if (_showEmojiPicker) {
                      setState(() => _showEmojiPicker = false);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: _canMessage
                        ? 'Type a message...'
                        : 'Add friend to keep chatting',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: Color(0xFF93C5FD)),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: IconButton(
                  icon: Icon(
                    _showEmojiPicker
                        ? Icons.keyboard_rounded
                        : Icons.emoji_emotions_outlined,
                    color: const Color(0xFF475569),
                  ),
                  onPressed: _canMessage
                      ? () {
                          setState(() => _showEmojiPicker = !_showEmojiPicker);
                          if (_showEmojiPicker) {
                            FocusScope.of(context).unfocus();
                          }
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _isSending || !_canMessage
                      ? const Color(0xFFE2E8F0)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _isSending || !_canMessage
                        ? const Color(0xFFD1D9E6)
                        : const Color(0xFF111827),
                  ),
                ),
                child: IconButton(
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF111827),
                          ),
                        )
                      : Icon(
                          Icons.send_rounded,
                          color: const Color(0xFF111827),
                        ),
                  onPressed: _isSending || !_canMessage ? null : _sendMessage,
                ),
              ),
            ],
          ),
          if (_showEmojiPicker)
            Container(
              height: 250,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: GridView.count(
                crossAxisCount: 7,
                children: _emojiOptions
                    .map(
                      (emoji) => InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _sendEmoji(emoji),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _composerToolChip({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final foreground =
        onPressed != null ? const Color(0xFF111827) : const Color(0xFF64748B);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceComposerChip() {
    if (!_voiceRecorder.supportsPressAndHold) {
      return _composerToolChip(
        icon: Icons.mic_none_rounded,
        label: 'Voice',
        onPressed: _canMessage ? _pickAndSendVoiceFile : null,
      );
    }

    final enabled = _canMessage && !_isSending;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Listener(
        onPointerDown:
            enabled ? (_) => unawaited(_handleVoicePressStart()) : null,
        onPointerUp: enabled ? (_) => unawaited(_handleVoicePressEnd()) : null,
        onPointerCancel: enabled
            ? (_) => unawaited(_handleVoicePressEnd(canceled: true))
            : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _isRecordingVoice
                ? const Color(0xFFEFFCF7)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _isRecordingVoice
                  ? const Color(0xFFFDA4AF)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isRecordingVoice
                      ? Icons.mic_rounded
                      : Icons.mic_none_rounded,
                  size: 18,
                  color: enabled
                      ? const Color(0xFF111827)
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 8),
                Text(
                  _isRecordingVoice
                      ? _formatVoiceDuration(_voiceRecordingDuration)
                      : 'Hold Voice',
                  style: TextStyle(
                    color: enabled
                        ? const Color(0xFF111827)
                        : const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatVoiceDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildMessageContent(MessageModel message, bool isFromMe) {
    final foreground = isFromMe ? Colors.white : Colors.black87;

    if (message.isRoomInvite) {
      return _buildRoomInviteMessage(message, isFromMe);
    }

    if (message.isGift) {
      return _buildGiftMessage(message, isFromMe);
    }

    if (message.isCoinTransfer) {
      return _buildCoinTransferMessage(message, isFromMe);
    }

    if (message.isEmoji) {
      return Text(
        message.content,
        style: const TextStyle(fontSize: 34, height: 1),
      );
    }

    if (message.isVoice) {
      final isPlaying = _activeAudioMessageId == message.id;
      return InkWell(
        onTap: () => _toggleVoicePlayback(message),
        borderRadius: BorderRadius.circular(14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPlaying
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline_rounded,
              color: foreground,
              size: 28,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPlaying ? 'Stop voice message' : 'Play voice message',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    (message.metadata['filename']?.toString().isNotEmpty ??
                            false)
                        ? message.metadata['filename'].toString()
                        : 'Tap to listen',
                    style: TextStyle(
                      color: isFromMe ? Colors.white70 : Colors.black54,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (message.voiceDurationMs > 0)
                    Text(
                      _formatVoiceDuration(
                        Duration(milliseconds: message.voiceDurationMs),
                      ),
                      style: TextStyle(
                        color: isFromMe ? Colors.white70 : Colors.black54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (message.isImage) {
      return _buildImageMessage(message, isFromMe);
    }

    if (message.isPrivateImage) {
      return _buildPrivateImageMessage(message, isFromMe);
    }

    return Text(
      message.content,
      style: TextStyle(color: foreground, height: 1.4),
    );
  }

  Widget _buildRoomInviteMessage(MessageModel message, bool isFromMe) {
    final titleColor = isFromMe ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isFromMe ? Colors.white70 : Colors.black54;
    final buttonBackground = isFromMe ? Colors.white : const Color(0xFF0F172A);
    final buttonForeground = isFromMe ? const Color(0xFF0F172A) : Colors.white;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isFromMe
            ? Colors.white.withValues(alpha: 0.1)
            : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFromMe ? Colors.white24 : const Color(0xFFBFDBFE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isFromMe
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.wifi_tethering_rounded,
                  color: isFromMe ? Colors.white : const Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.roomInviteRoomName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isFromMe
                          ? 'Room invite sent in realtime'
                          : 'Tap below to jump into the room',
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: FilledButton.icon(
              onPressed: () => _openInvitedRoom(message),
              style: FilledButton.styleFrom(
                backgroundColor: buttonBackground,
                foregroundColor: buttonForeground,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text(isFromMe ? 'Open room' : 'Join room'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoinTransferMessage(MessageModel message, bool isFromMe) {
    final currentUserId = _currentUserId ?? '';
    final viewerIsSender = message.coinTransferSenderUserId == currentUserId;
    final grossAmount = message.coinTransferGrossAmount;
    final receiverAmount = message.coinTransferReceiverAmount;
    final platformFee = message.coinTransferPlatformFee;
    final status = message.coinTransferStatus.trim().isEmpty
        ? 'completed'
        : message.coinTransferStatus.trim();
    final titleColor = isFromMe ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isFromMe ? Colors.white70 : const Color(0xFF64748B);
    final badgeBackground = isFromMe
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFEFF6FF);
    final badgeForeground = isFromMe ? Colors.white : const Color(0xFF1D4ED8);
    final peerName = _peerDisplayName;
    final title = viewerIsSender
        ? 'You sent $grossAmount coins'
        : 'You received $receiverAmount coins';
    final subtitle = viewerIsSender
        ? '$peerName received $receiverAmount coins. Friend Circle fee: $platformFee.'
        : '${message.coinTransferSenderUsername} spent $grossAmount coins. Friend Circle fee: $platformFee.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isFromMe
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isFromMe ? Colors.white24 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: badgeBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.toll_rounded,
                  color: badgeForeground,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: badgeBackground,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status[0].toUpperCase() + status.substring(1),
              style: TextStyle(
                color: badgeForeground,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGiftMessage(MessageModel message, bool isFromMe) {
    final foreground = isFromMe ? Colors.white : const Color(0xFF0F172A);
    final subColor = isFromMe ? Colors.white70 : const Color(0xFF64748B);
    final giftName = message.giftName ?? 'Gift';
    final xpGained = message.giftRecipientXpGained;
    final level = message.giftRecipientLevel;
    final levelLine = xpGained > 0
        ? (isFromMe
            ? 'They received +$xpGained XP'
            : 'You received +$xpGained XP')
        : 'Gift delivered';
    final levelBadge = message.giftRecipientLeveledUp && level > 0
        ? 'Level $level reached'
        : (level > 0 ? 'Lv $level' : null);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isFromMe
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFromMe ? Colors.white24 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GiftIconBadge(
            icon: message.giftIcon,
            isFromMe: isFromMe,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  giftName,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  levelLine,
                  style: TextStyle(
                    color: subColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (levelBadge != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isFromMe
                          ? Colors.white.withValues(alpha: 0.14)
                          : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      levelBadge,
                      style: TextStyle(
                        color:
                            isFromMe ? Colors.white : const Color(0xFF1D4ED8),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                if ((message.giftNote?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 8),
                  Text(
                    message.giftNote!,
                    style: TextStyle(
                      color: subColor,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageMessage(MessageModel message, bool isFromMe) {
    final url = _normalizeMediaUrl(message.content);
    final labelColor = isFromMe ? Colors.white70 : Colors.black54;
    final previewWidth = MediaQuery.sizeOf(context).width < 380 ? 148.0 : 176.0;

    return GestureDetector(
      onTap: url == null
          ? null
          : () {
              showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  insetPadding: const EdgeInsets.all(18),
                  backgroundColor: Colors.transparent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: InteractiveViewer(
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => Container(
                          padding: const EdgeInsets.all(24),
                          color: Colors.black87,
                          child: const Text(
                            'Image unavailable',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: previewWidth,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 0.96,
                child: url == null
                    ? Container(
                        color: Colors.black12,
                        alignment: Alignment.center,
                        child: Text(
                          'Image unavailable',
                          style: TextStyle(color: labelColor),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.black12,
                          alignment: Alignment.center,
                          child: Text(
                            'Image unavailable',
                            style: TextStyle(color: labelColor),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Photo',
            style: TextStyle(
              color: labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivateImageMessage(MessageModel message, bool isFromMe) {
    final consumed = _consumedPrivatePhotoIds.contains(message.id);
    final subColor = isFromMe ? Colors.white70 : Colors.black54;
    final imageUrl = _normalizeMediaUrl(message.content);
    final previewWidth = MediaQuery.sizeOf(context).width < 380 ? 148.0 : 176.0;

    return InkWell(
      onTap: consumed ? null : () => _openPrivatePhoto(message),
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: previewWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 0.96,
                    child: imageUrl == null
                        ? Container(
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: Text(
                              'Private image unavailable',
                              style: TextStyle(color: subColor),
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.black12,
                              alignment: Alignment.center,
                              child: Text(
                                'Private image unavailable',
                                style: TextStyle(color: subColor),
                              ),
                            ),
                          ),
                  ),
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(
                        alpha: consumed ? 0.66 : 0.42,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            consumed
                                ? Icons.visibility_off_rounded
                                : Icons.shield_outlined,
                            color: Colors.white,
                            size: 26,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            consumed ? 'Expired' : 'Tap to view',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              consumed
                  ? 'This private photo was already opened.'
                  : 'Hides after ${message.ephemeralSeconds}s once opened.',
              style: TextStyle(
                color: subColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _messageSummary(MessageModel message) {
    return message.previewText;
  }

  Widget _buildTypingDot(int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1),
        duration: Duration(milliseconds: 520 + (index * 140)),
        curve: Curves.easeInOut,
        builder: (context, value, child) {
          return Transform.scale(scale: value, child: child);
        },
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: Colors.grey.shade600,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(MessageModel message) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading:
                  const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('Delete Message'),
              onTap: () {
                Navigator.pop(context);
                _handleDeleteMessage(message.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showReactionOptions(MessageModel message) {
    const reactions = [
      '\u{1F44D}',
      '\u{2764}\u{FE0F}',
      '\u{1F602}',
      '\u{1F62E}',
      '\u{1F622}',
      '\u{1F621}',
    ];

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Add Reaction',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: reactions.map((reaction) {
                final hasReacted = message.reactions.any(
                  (item) => item.reaction == reaction,
                );
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _handleReaction(message.id, reaction);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasReacted
                          ? AppColors.primaryBlue.withValues(alpha: 0.08)
                          : Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      reaction,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

const List<String> _emojiOptions = [
  '\u{1F44B}',
  '\u{1F44D}',
  '\u{1F44F}',
  '\u{2764}\u{FE0F}',
  '\u{1F525}',
  '\u{1F389}',
  '\u{1F60D}',
  '\u{1F60A}',
  '\u{1F602}',
  '\u{1F62E}',
  '\u{1F622}',
  '\u{1F621}',
  '\u{1F60E}',
  '\u{1F973}',
  '\u{1F31F}',
  '\u{1F48E}',
  '\u{1F381}',
  '\u{1F3B5}',
  '\u{1F680}',
  '\u{1F48C}',
];

class _GiftIconBadge extends StatelessWidget {
  final String? icon;
  final bool isFromMe;

  const _GiftIconBadge({
    required this.icon,
    required this.isFromMe,
  });

  @override
  Widget build(BuildContext context) {
    final background = isFromMe
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFEFF2F7);

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: GiftImage(
        source: icon,
        width: 40,
        height: 40,
        borderRadius: BorderRadius.circular(14),
        fallback: const Icon(
          Icons.card_giftcard_rounded,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _EphemeralPhotoViewer extends StatefulWidget {
  final String imageUrl;
  final int seconds;
  final String screenshotNote;

  const _EphemeralPhotoViewer({
    required this.imageUrl,
    required this.seconds,
    required this.screenshotNote,
  });

  @override
  State<_EphemeralPhotoViewer> createState() => _EphemeralPhotoViewerState();
}

class _EphemeralPhotoViewerState extends State<_EphemeralPhotoViewer> {
  Timer? _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        timer.cancel();
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _remainingSeconds -= 1;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.96),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const Text(
                    'Private photo unavailable',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 18,
              left: 18,
              right: 18,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$_remainingSeconds s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 24,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  widget.screenshotNote,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
