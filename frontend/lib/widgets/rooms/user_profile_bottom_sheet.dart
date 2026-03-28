import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/message_model.dart';
import '../../models/room_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/friend_service.dart';
import '../../services/message_service.dart';
import '../../services/profile_service.dart';
import '../../services/room_service.dart';
import '../../services/socket_service.dart';
import '../../utils/constants.dart';
import '../user_avatar.dart';

class UserProfileBottomSheet extends StatefulWidget {
  final Participant participant;
  final RoomModel room;
  final bool isMe;
  final bool canModerate;
  final bool isHost;
  final bool canManageRoles;
  final bool canManageSpeakerState;
  final bool canSendGifts;
  final bool isLocallyMuted;
  final VoidCallback onViewProfile;
  final VoidCallback onOpenChat;
  final VoidCallback onSendGift;
  final VoidCallback onLeaveSeat;
  final VoidCallback onRefreshRoom;
  final Future<void> Function()? onToggleLocalAudio;

  const UserProfileBottomSheet({
    super.key,
    required this.participant,
    required this.room,
    required this.isMe,
    required this.canModerate,
    required this.isHost,
    required this.canManageRoles,
    required this.canManageSpeakerState,
    required this.canSendGifts,
    this.isLocallyMuted = false,
    required this.onViewProfile,
    required this.onOpenChat,
    required this.onSendGift,
    required this.onLeaveSeat,
    required this.onRefreshRoom,
    this.onToggleLocalAudio,
  });

  @override
  State<UserProfileBottomSheet> createState() => _UserProfileBottomSheetState();
}

class _UserProfileBottomSheetState extends State<UserProfileBottomSheet> {
  UserModel? _profileUser;
  Map<String, dynamic> _relationship = const {};
  List<MessageModel> _recentMessages = const [];
  bool _isLoading = true;
  bool _isFriendBusy = false;
  Timer? _refreshTimer;
  final List<StreamSubscription> _subscriptions = [];

  Participant get participant => widget.participant;
  bool get _isFriend => _relationship['isFriend'] == true;
  bool get _hasIncomingRequest => _relationship['hasIncomingRequest'] == true;
  bool get _hasOutgoingRequest => _relationship['hasOutgoingRequest'] == true;
  bool get _canSendFriendRequest =>
      _relationship['canSendFriendRequest'] == true;
  bool get _isBlocked => _relationship['isBlocked'] == true;

  @override
  void initState() {
    super.initState();
    _loadSheetData();
    _subscriptions.add(SocketService.friendStream.listen((_) {
      unawaited(_loadSheetData(refreshChat: false));
    }));
    _subscriptions.add(SocketService.dmStream.listen(_handleDmUpdate));
    _subscriptions.add(SocketService.resyncStream.listen((_) {
      unawaited(_loadSheetData());
    }));
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => _loadSheetData(refreshChat: false),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _loadSheetData({bool refreshChat = true}) async {
    try {
      final profileFuture = widget.isMe
          ? ProfileService.getMyProfile()
          : ProfileService.getProfile(participant.userId);
      final chatFuture = !widget.isMe && refreshChat
          ? MessageService.getDirectMessages(participant.userId, limit: 3)
          : Future.value({
              'messages': _recentMessages,
              'pagination': null,
            });
      final results = await Future.wait<dynamic>([profileFuture, chatFuture]);
      if (!mounted) return;

      final profileData = results[0] is Map<String, dynamic>
          ? results[0] as Map<String, dynamic>
          : <String, dynamic>{};
      final profileUserJson = profileData['user'];
      final relationship = profileData['relationship'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(profileData['relationship'])
          : <String, dynamic>{
              'isSelf': widget.isMe,
              'canMessage': widget.isMe,
            };
      final messagesMap = results[1] is Map<String, dynamic>
          ? results[1] as Map<String, dynamic>
          : <String, dynamic>{};

      setState(() {
        _profileUser = profileUserJson is Map<String, dynamic>
            ? UserModel.fromJson(profileUserJson)
            : _profileUser;
        _relationship = relationship;
        _recentMessages = List<MessageModel>.from(
          messagesMap['messages'] as List? ?? _recentMessages,
        ).reversed.toList(growable: false);
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleDmUpdate(Map<String, dynamic> data) {
    final currentUserId = context.read<AuthProvider>().user?.id;
    final messageJson = data['message'];
    if (currentUserId == null || messageJson is! Map) return;
    final message = MessageModel.fromJson(Map<String, dynamic>.from(messageJson));
    final ids = <String>{
      message.senderId,
      if (message.recipientId != null) message.recipientId!,
    };
    if (!ids.contains(currentUserId) || !ids.contains(participant.userId)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _recentMessages = [
        message,
        ..._recentMessages.where((item) => item.id != message.id),
      ].take(3).toList(growable: false);
    });
  }

  Future<void> _handlePrimaryAction() async {
    if (widget.isMe) {
      widget.onLeaveSeat();
      return;
    }
    if (_isBlocked || _isFriendBusy) return;
    if (!_hasIncomingRequest && !_canSendFriendRequest) return;

    setState(() => _isFriendBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_hasIncomingRequest) {
        final success = await FriendService.acceptFriendRequest(participant.userId);
        if (success) {
          setState(() {
            _relationship = {
              ..._relationship,
              'isFriend': true,
              'hasIncomingRequest': false,
              'hasOutgoingRequest': false,
              'canSendFriendRequest': false,
              'canMessage': true,
            };
          });
          messenger.showSnackBar(
            SnackBar(
              content: Text('You are now friends with ${participant.username}.'),
              backgroundColor: AppColors.successGreen,
            ),
          );
        }
      } else if (_canSendFriendRequest) {
        final success = await FriendService.sendFriendRequest(participant.userId);
        if (success) {
          setState(() {
            _relationship = {
              ..._relationship,
              'hasOutgoingRequest': true,
              'canSendFriendRequest': false,
            };
          });
          messenger.showSnackBar(
            SnackBar(
              content: Text('Friend request sent to ${participant.username}.'),
              backgroundColor: AppColors.successGreen,
            ),
          );
        }
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isFriendBusy = false);
    }
  }

  String _primaryLabel() {
    if (widget.isMe) return 'Leave Seat';
    if (_isFriend) return 'Friends';
    if (_hasIncomingRequest) return 'Accept Friend';
    if (_hasOutgoingRequest) return 'Requested';
    if (_isBlocked) return 'Unavailable';
    return 'Add Friend';
  }

  Color _primaryColor() {
    if (widget.isMe) return Colors.redAccent;
    if (_isFriend) return AppColors.successGreen;
    if (_hasOutgoingRequest) return Colors.grey.shade700;
    return const Color(0xFFFF528D);
  }

  @override
  Widget build(BuildContext context) {
    final user = _profileUser;
    final stats = user?.stats ?? const <String, dynamic>{};
    final friendCount = _asInt(stats['friendCount']);
    final followerCount = _asInt(stats['followerCount']);
    final followingCount = _asInt(stats['followingCount']);
    final visitorCount = _asInt(stats['visitorCount']);

    return Container(
      padding: const EdgeInsets.only(bottom: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF111115),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, color: Colors.white54),
                    onPressed: (widget.canModerate ||
                            widget.canManageRoles ||
                            widget.canManageSpeakerState)
                        ? () => _showModerationMenu(context)
                        : null,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.person_outline_rounded,
                        color: Colors.white54),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onViewProfile();
                    },
                  ),
                ],
              ),
              Center(child: _buildAvatar(user)),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  user?.username ?? participant.username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  user?.uid.isNotEmpty == true
                      ? 'UID ${user!.uid}'
                      : 'ID: ${participant.userId.substring(0, participant.userId.length > 8 ? 8 : participant.userId.length)}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill(
                    participant.role == 'host'
                        ? 'HOST'
                        : participant.role == 'cohost'
                            ? 'CO-HOST'
                            : participant.role == 'moderator'
                                ? 'ADMIN'
                                : 'LISTENER',
                    const Color(0xFFFF7A45).withValues(alpha: 0.16),
                    const Color(0xFFFFB083),
                  ),
                  _pill(
                    (user?.isOnline ?? participant.isOnline) ? 'ONLINE' : 'OFFLINE',
                    ((user?.isOnline ?? participant.isOnline)
                            ? AppColors.successGreen
                            : Colors.white24)
                        .withValues(alpha: 0.16),
                    (user?.isOnline ?? participant.isOnline)
                        ? AppColors.successGreen
                        : Colors.white70,
                  ),
                  if ((user?.vipLevel ?? participant.vipLevel) > 0)
                    _pill(
                      'VIP ${user?.vipLevel ?? participant.vipLevel}',
                      const Color(0xFFFFD24D).withValues(alpha: 0.16),
                      const Color(0xFFFFD24D),
                    ),
                  if (_isFriend)
                    _pill(
                      'FRIEND',
                      AppColors.successGreen.withValues(alpha: 0.16),
                      AppColors.successGreen,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (_isLoading && user == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                _card(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _statTile('Level', '${user?.level ?? participant.level}'),
                      _statTile('XP', '${user?.xp ?? 0}'),
                      _statTile('Friends', '$friendCount'),
                      _statTile('Followers', '$followerCount'),
                      _statTile('Following', '$followingCount'),
                      _statTile('Visitors', '$visitorCount'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Live Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _infoRow(
                        'Bio',
                        (user?.bio ?? '').trim().isEmpty
                            ? 'No bio yet'
                            : (user!.bio ?? ''),
                      ),
                      const SizedBox(height: 12),
                      _infoRow('Region', user?.region ?? 'Global'),
                      const SizedBox(height: 12),
                      _infoRow('Coins', '${user?.coins ?? 0}'),
                      const SizedBox(height: 12),
                      _infoRow('Diamonds', '${user?.gems ?? 0}'),
                      const SizedBox(height: 12),
                      _infoRow('Win Rate', '${stats['winRate'] ?? 0}%'),
                      const SizedBox(height: 12),
                      _infoRow('Gifts Sent', '${stats['giftsSent'] ?? 0}'),
                      const SizedBox(height: 12),
                      _infoRow(
                        'Gifts Received',
                        '${stats['giftsReceived'] ?? 0}',
                      ),
                      const SizedBox(height: 12),
                      _infoRow('Last Active', _lastActiveLabel(user?.lastActive)),
                    ],
                  ),
                ),
                if (!widget.isMe) ...[
                  const SizedBox(height: 16),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Live Chat Preview',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onOpenChat();
                              },
                              child: const Text('Open chat'),
                            ),
                          ],
                        ),
                        if (_recentMessages.isEmpty)
                          Text(
                            _isFriend
                                ? 'No private messages yet.'
                                : 'Add each other as friends to start private chat.',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          )
                        else
                          ..._recentMessages.map(_messagePreview),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  if (!widget.isMe) ...[
                    _squareAction(
                      icon: widget.isLocallyMuted
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      color: widget.isLocallyMuted
                          ? Colors.white
                          : const Color(0xFFFF7A45),
                      tooltip: widget.isLocallyMuted
                          ? 'Hear on this device'
                          : 'Mute on this device',
                      onTap: widget.onToggleLocalAudio,
                    ),
                    const SizedBox(width: 12),
                  ],
                  _squareAction(
                    icon: Icons.card_giftcard_rounded,
                    color: const Color(0xFFFFB347),
                    tooltip: 'Send gift',
                    onTap: widget.canSendGifts
                        ? () async => widget.onSendGift()
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onOpenChat();
                      },
                      icon: const Icon(Icons.chat_bubble_rounded,
                          color: Colors.white),
                      label: const Text(
                        'Chat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        side: const BorderSide(color: Colors.white10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: widget.isMe || _hasIncomingRequest || _canSendFriendRequest
                          ? _handlePrimaryAction
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor(),
                        disabledBackgroundColor: _primaryColor(),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: _isFriendBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _primaryLabel(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(UserModel? user) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 110,
          height: 110,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFFFF7A45), Color(0xFFFFCC00)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: UserAvatar(
                  username: user?.username ?? participant.username,
                  imageUrl: (user?.avatar.isNotEmpty == true)
                      ? user!.avatar
                      : participant.avatar,
                  radius: 50,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -10,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF52A1FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF111115), width: 2),
            ),
            child: Text(
              'Lv.${user?.level ?? participant.level}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(String text, Color background, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: child,
    );
  }

  Widget _statTile(String label, String value) {
    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _messagePreview(MessageModel message) {
    final currentUserId = context.read<AuthProvider>().user?.id;
    final isFromMe = message.senderId == currentUserId;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: isFromMe
                  ? const Color(0xFFFFB347)
                  : const Color(0xFF52A1FF),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFromMe
                      ? 'You'
                      : (message.senderName.isEmpty ? 'Friend' : message.senderName),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _previewText(message),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            message.timeAgo,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _previewText(MessageModel message) {
    if (message.isGift) return message.content;
    if (message.isImage) return 'Photo';
    if (message.isVoice) return 'Voice message';
    if (message.isEmoji) return 'Emote ${message.content}';
    if (message.isPrivateImage) return 'Private photo';
    return message.content;
  }

  Widget _squareAction({
    required IconData icon,
    required Color color,
    required String tooltip,
    required Future<void> Function()? onTap,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: color),
        onPressed: onTap == null ? null : () => unawaited(onTap()),
      ),
    );
  }

  String _lastActiveLabel(DateTime? lastActive) {
    if (lastActive == null) return 'Unknown';
    final diff = DateTime.now().difference(lastActive);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  void _showModerationMenu(BuildContext context) {
    if (!widget.canModerate &&
        !widget.canManageRoles &&
        !widget.canManageSpeakerState) {
      return;
    }
    final isAdminRole = widget.room.moderatorIds.contains(participant.userId) ||
        participant.role == 'moderator';
    final isCoHostRole = widget.room.coHostIds.contains(participant.userId) ||
        participant.role == 'cohost';
    final adminLimitReached = !isAdminRole &&
        widget.room.moderatorIds.length >= widget.room.maxAdminSlots;
    final adminLimitSubtitle = adminLimitReached
        ? widget.room.nextAdminUnlockLevel == null
            ? 'This room already uses all ${widget.room.maxAdminSlots} admin slots'
            : 'Room Lv.${widget.room.level} allows ${widget.room.maxAdminSlots} admins. Reach Lv.${widget.room.nextAdminUnlockLevel} to unlock 5 admins'
        : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.canModerate)
              ListTile(
                leading: Icon(
                  participant.isMuted ? Icons.mic : Icons.mic_off,
                  color: Colors.orange,
                ),
                title: Text(
                  participant.isMuted ? 'Unmute User' : 'Mute User',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await RoomService.muteParticipant(
                      widget.room.id,
                      participant.userId,
                      muted: !participant.isMuted,
                    );
                    widget.onRefreshRoom();
                  } catch (e) {
                    debugPrint('Failed to update mute state: $e');
                  }
                },
              ),
            if (widget.canManageSpeakerState)
              ListTile(
                leading: Icon(
                  participant.seatIndex >= 0
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  color: Colors.purpleAccent,
                ),
                title: Text(
                  participant.seatIndex >= 0
                      ? 'Move To Audience'
                      : 'Approve Mic Request',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    if (participant.seatIndex >= 0) {
                      await RoomService.demoteParticipant(
                        widget.room.id,
                        participant.userId,
                      );
                    } else {
                      await RoomService.promoteParticipant(
                        widget.room.id,
                        participant.userId,
                      );
                    }
                    widget.onRefreshRoom();
                  } catch (e) {
                    debugPrint('Failed to update speaker state: $e');
                  }
                },
              ),
            if (widget.isHost && widget.canManageRoles)
              ListTile(
                leading: Icon(
                  isAdminRole
                      ? Icons.admin_panel_settings
                      : Icons.shield_outlined,
                  color: const Color(0xFF52A1FF),
                ),
                title: Text(
                  isAdminRole ? 'Remove Admin' : 'Make Admin',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: (isCoHostRole && !isAdminRole) || adminLimitReached
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(ctx);
                        try {
                          if (isAdminRole) {
                            await RoomService.removeModerator(
                              widget.room.id,
                              participant.userId,
                            );
                          } else {
                            await RoomService.addModerator(
                              widget.room.id,
                              participant.userId,
                            );
                          }
                          widget.onRefreshRoom();
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                e.toString().replaceFirst('Exception: ', ''),
                              ),
                            ),
                          );
                        }
                      },
                subtitle: isCoHostRole && !isAdminRole
                    ? const Text(
                        'Remove co-host first to assign admin',
                        style: TextStyle(color: Colors.white54),
                      )
                    : adminLimitSubtitle == null
                        ? null
                        : Text(
                            adminLimitSubtitle,
                            style: const TextStyle(color: Colors.white54),
                          ),
              ),
            if (widget.isHost && widget.canManageRoles)
              ListTile(
                leading: Icon(
                  isCoHostRole ? Icons.person_remove : Icons.person_add,
                  color: Colors.cyanAccent,
                ),
                title: Text(
                  isCoHostRole ? 'Remove Co-host' : 'Make Co-host',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    if (isCoHostRole) {
                      await RoomService.removeCoHost(
                        widget.room.id,
                        participant.userId,
                      );
                    } else {
                      await RoomService.assignCoHost(
                        widget.room.id,
                        participant.userId,
                      );
                    }
                    widget.onRefreshRoom();
                  } catch (e) {
                    debugPrint('Failed to update co-host role: $e');
                  }
                },
              ),
            if (widget.canModerate)
              ListTile(
                leading:
                    const Icon(Icons.person_off, color: Colors.redAccent),
                title: const Text(
                  'Kick From Room',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await RoomService.kickParticipant(
                      widget.room.id,
                      participant.userId,
                    );
                    widget.onRefreshRoom();
                  } catch (e) {
                    debugPrint('Failed to kick participant: $e');
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
