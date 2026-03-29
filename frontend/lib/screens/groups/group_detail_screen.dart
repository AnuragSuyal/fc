import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/group_model.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/friend_service.dart';
import '../../services/group_service.dart';
import '../../services/message_service.dart';
import '../../services/room_service.dart';
import '../../services/socket_service.dart';
import '../../services/upload_service.dart';
import '../../utils/constants.dart';
import '../../utils/media_url.dart';
import '../../widgets/gifting/gift_bottom_sheet.dart';
import '../../widgets/user_avatar.dart';
import '../messages/chat_screen.dart';
import '../rooms/room_detail_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final String groupId;

  const GroupDetailScreen({
    super.key,
    required this.groupId,
  });

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final List<StreamSubscription> _subs = [];
  final Map<String, Timer> _typingTimers = <String, Timer>{};

  GroupModel? _group;
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isLoadingMessages = false;
  bool _isSending = false;
  String? _error;
  Set<String> _typingNames = <String>{};
  Timer? _typingStopTimer;
  bool _joinedSocketGroup = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _composerController.addListener(_handleComposerChanged);
    _bindRealtime();
    _loadGroup();
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    for (final sub in _subs) {
      sub.cancel();
    }
    if (_joinedSocketGroup) {
      SocketService.leaveGroup(widget.groupId);
    }
    _tabController.dispose();
    _composerController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _bindRealtime() {
    _subs.add(SocketService.groupMessageStream.listen(_handleIncomingMessage));
    _subs.add(SocketService.groupUpdateStream.listen(_handleGroupUpdate));
    _subs.add(SocketService.typingStream.listen(_handleTypingEvent));
    _subs.add(SocketService.resyncStream.listen((_) => _refreshAll()));
  }

  Future<void> _loadGroup({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final group = await GroupService.getGroupById(widget.groupId);
    if (!mounted) return;

    if (group == null) {
      setState(() {
        _isLoading = false;
        _error = 'Could not load this circle right now.';
      });
      return;
    }

    final shouldJoinSocket = group.isMember && !_joinedSocketGroup;
    if (shouldJoinSocket) {
      SocketService.joinGroup(widget.groupId);
      _joinedSocketGroup = true;
    } else if (!group.isMember && _joinedSocketGroup) {
      SocketService.leaveGroup(widget.groupId);
      _joinedSocketGroup = false;
    }

    setState(() {
      _group = group;
      _isLoading = false;
    });

    if (group.isMember) {
      await _loadMessages(silent: true);
    }
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoadingMessages = true);
    }

    try {
      final response = await MessageService.getGroupMessages(
        widget.groupId,
        limit: 50,
      );
      final messages = response['messages'] as List<dynamic>? ?? const [];
      if (!mounted) return;
      setState(() {
        _messages = messages.whereType<MessageModel>().toList(growable: false);
        _isLoadingMessages = false;
      });
      _scrollChatToBottom(jump: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMessages = false);
    }
  }

  Future<void> _refreshAll() async {
    await _loadGroup(silent: true);
  }

  void _handleIncomingMessage(Map<String, dynamic> event) {
    final groupId = event['groupId']?.toString();
    if (groupId != widget.groupId) return;

    final message = MessageModel.fromJson(Map<String, dynamic>.from(event));
    if (_messages.any((item) => item.id == message.id)) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _messages = [..._messages, message];
    });
    _scrollChatToBottom();
  }

  void _handleGroupUpdate(Map<String, dynamic> event) {
    final groupId = event['groupId']?.toString();
    if (groupId != widget.groupId) return;

    final action = event['action']?.toString() ?? '';
    final currentUserId = context.read<AuthProvider>().user?.id;
    final memberUserId = event['memberUserId']?.toString();

    if (action == 'deleted') {
      if (mounted) Navigator.pop(context);
      return;
    }

    if ((action == 'member_removed' || action == 'member_left') &&
        memberUserId == currentUserId) {
      _loadGroup(silent: true);
      return;
    }

    if (action == 'chat_activity') {
      return;
    }

    _loadGroup(silent: true);
  }

  void _handleTypingEvent(Map<String, dynamic> event) {
    if (event['groupId']?.toString() != widget.groupId) return;

    final currentUserId = context.read<AuthProvider>().user?.id;
    final userId = event['userId']?.toString();
    final username = event['username']?.toString() ?? 'Someone';
    final isTyping = event['isTyping'] == true;

    if (userId == null || userId == currentUserId) return;

    _typingTimers[userId]?.cancel();

    if (isTyping) {
      setState(() => _typingNames = {..._typingNames, username});
      _typingTimers[userId] = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() {
          _typingNames = Set<String>.from(_typingNames)..remove(username);
        });
      });
    } else {
      setState(() {
        _typingNames = Set<String>.from(_typingNames)..remove(username);
      });
    }
  }

  void _handleComposerChanged() {
    if (_group?.isMember != true) return;
    final hasText = _composerController.text.trim().isNotEmpty;
    SocketService.sendTyping(groupId: widget.groupId, isTyping: hasText);
    _typingStopTimer?.cancel();
    if (hasText) {
      _typingStopTimer = Timer(const Duration(seconds: 2), () {
        SocketService.sendTyping(groupId: widget.groupId, isTyping: false);
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_group?.isMember != true || _isSending) return;

    final text = _composerController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      final sent = await MessageService.sendGroupMessage(
        groupId: widget.groupId,
        content: text,
      );
      if (!mounted) return;
      _composerController.clear();
      SocketService.sendTyping(groupId: widget.groupId, isTyping: false);
      if (sent != null && !_messages.any((item) => item.id == sent.id)) {
        setState(() => _messages = [..._messages, sent]);
        _scrollChatToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_group?.isMember != true || _isSending) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1440,
      maxHeight: 1440,
      imageQuality: 82,
    );
    if (picked == null) return;

    setState(() => _isSending = true);
    try {
      final upload = await UploadService.uploadImage(picked);
      final url = upload['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Image upload failed');
      }

      final sent = await MessageService.sendGroupMessage(
        groupId: widget.groupId,
        content: url,
        type: 'image',
      );
      if (!mounted) return;

      SocketService.sendTyping(groupId: widget.groupId, isTyping: false);
      if (sent != null && !_messages.any((item) => item.id == sent.id)) {
        setState(() => _messages = [..._messages, sent]);
        _scrollChatToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _joinGroup() async {
    final group = _group;
    if (group == null) return;

    try {
      final response = await GroupService.joinGroup(group.id);
      if (!mounted) return;
      await _loadGroup(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response['pendingApproval'] == true
                ? 'Join request sent'
                : 'You joined ${group.name}',
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

  Future<void> _acceptInvite() async {
    final group = _group;
    if (group == null) return;
    try {
      await GroupService.acceptInvite(group.id);
      if (!mounted) return;
      await _loadGroup(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _openVoiceLounge() async {
    final roomId = _group?.linkedVoiceRoom?.id;
    if (roomId == null || roomId.isEmpty) return;

    final room = await RoomService.getRoomById(roomId);
    if (!mounted) return;
    if (room == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open voice lounge.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
    );
    if (!mounted) return;
    _loadGroup(silent: true);
  }

  Future<void> _openDirectChat(GroupUserModel user) async {
    if (user.id.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: user.id,
          username: user.username,
          avatar: resolveMediaUrl(user.avatar),
        ),
      ),
    );
  }

  Future<void> _giftMember(GroupUserModel user) async {
    if (user.id.isEmpty) return;
    await showGiftBottomSheet(
      context: context,
      toUserId: user.id,
      toUsername: user.username,
    );
  }

  Future<void> _approveJoinRequest(GroupJoinRequestModel request) async {
    try {
      await GroupService.approveJoinRequest(widget.groupId, request.user.id);
      if (!mounted) return;
      await _loadGroup(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  void _openImagePreview(String url) {
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
  }

  Widget _buildMessageBody(MessageModel message) {
    if (message.isImage || message.isPrivateImage) {
      return _buildImageMessage(message);
    }

    return Text(message.content);
  }

  Widget _buildImageMessage(MessageModel message) {
    final imageUrl = resolveMediaUrl(message.content);

    return InkWell(
      onTap: imageUrl == null ? null : () => _openImagePreview(imageUrl),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 1,
              child: imageUrl == null
                  ? Container(
                      color: const Color(0xFFE2E8F0),
                      alignment: Alignment.center,
                      child: const Text(
                        'Image unavailable',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFFE2E8F0),
                        alignment: Alignment.center,
                        child: const Text(
                          'Image unavailable',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message.isPrivateImage ? 'Private photo' : 'Photo',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rejectJoinRequest(GroupJoinRequestModel request) async {
    final success =
        await GroupService.rejectJoinRequest(widget.groupId, request.user.id);
    if (success && mounted) {
      _loadGroup(silent: true);
    }
  }

  Future<void> _showInviteFriendsSheet() async {
    final group = _group;
    if (group == null) return;

    final friendsPayload = await FriendService.getFriends();
    if (!mounted) return;

    final members = group.members.map((member) => member.user.id).toSet();
    final friends = <Map<String, dynamic>>[
      ...((friendsPayload['online'] as List?) ?? const []),
      ...((friendsPayload['offline'] as List?) ?? const []),
    ]
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((user) => !members.contains(user['_id']?.toString()))
        .toList();

    final selected = <String>{};
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              MediaQuery.of(context).viewInsets.bottom + 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Invite friends',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: friends.map((friend) {
                      final id = friend['_id']?.toString() ?? '';
                      final chosen = selected.contains(id);
                      return CheckboxListTile(
                        value: chosen,
                        onChanged: (_) {
                          setModalState(() {
                            if (chosen) {
                              selected.remove(id);
                            } else {
                              selected.add(id);
                            }
                          });
                        },
                        title: Text(friend['username']?.toString() ?? 'Friend'),
                        secondary: UserAvatar(
                          imageUrl:
                              resolveMediaUrl(friend['avatar']?.toString()),
                          username: friend['username']?.toString() ?? 'F',
                          radius: 18,
                        ),
                        contentPadding: EdgeInsets.zero,
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, true),
                    child: const Text('Send invites'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != true || !mounted || selected.isEmpty) return;

    try {
      await GroupService.inviteFriends(widget.groupId, selected.toList());
      if (!mounted) return;
      await _loadGroup(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _showMemberActions(GroupMemberModel member) async {
    final group = _group;
    if (group == null) return;

    final currentUserId = context.read<AuthProvider>().user?.id;
    final isSelf = member.user.id == currentUserId;
    final canManage = group.permissions['canManageMembers'] == true && !isSelf;
    final canPromote = group.permissions['canPromoteAdmins'] == true &&
        member.role != 'leader';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserAvatar(
                      imageUrl: resolveMediaUrl(member.user.avatar),
                      username: member.user.username,
                      radius: 24,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.user.username,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          member.role.toUpperCase(),
                          style:
                              const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.chat_bubble_outline_rounded),
                  title: const Text('Message'),
                  onTap: () {
                    Navigator.pop(context);
                    _openDirectChat(member.user);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.card_giftcard_rounded),
                  title: const Text('Send gift'),
                  onTap: () {
                    Navigator.pop(context);
                    _giftMember(member.user);
                  },
                ),
                if (canPromote && member.role == 'member')
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.shield_outlined),
                    title: const Text('Promote to admin'),
                    onTap: () async {
                      Navigator.pop(context);
                      await GroupService.updateMemberRole(
                        widget.groupId,
                        member.user.id,
                        'admin',
                      );
                      if (mounted) _loadGroup(silent: true);
                    },
                  ),
                if (canPromote && member.role == 'admin')
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.shield_moon_outlined),
                    title: const Text('Return to member'),
                    onTap: () async {
                      Navigator.pop(context);
                      await GroupService.updateMemberRole(
                        widget.groupId,
                        member.user.id,
                        'member',
                      );
                      if (mounted) _loadGroup(silent: true);
                    },
                  ),
                if (canManage && member.role != 'leader')
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_remove_alt_1_rounded,
                        color: Colors.red),
                    title: const Text('Kick from circle'),
                    onTap: () async {
                      Navigator.pop(context);
                      await GroupService.removeMember(
                        widget.groupId,
                        member.user.id,
                      );
                      if (mounted) _loadGroup(silent: true);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _scrollChatToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      final position = _chatScrollController.position.maxScrollExtent;
      if (jump) {
        _chatScrollController.jumpTo(position);
      } else {
        _chatScrollController.animateTo(
          position,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _leaveGroup() async {
    final group = _group;
    if (group == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave circle'),
        content: Text('Leave ${group.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final success = await GroupService.leaveGroup(group.id);
    if (!mounted || !success) return;
    Navigator.pop(context, true);
  }

  Future<void> _deleteGroup() async {
    final group = _group;
    if (group == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete circle'),
        content: Text('Delete ${group.name}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final success = await GroupService.deleteGroup(group.id);
    if (!mounted || !success) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;

    return Scaffold(
      appBar: AppBar(
        title: Text(group?.name ?? 'Circle'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : group == null
                  ? const Center(child: Text('Circle not found'))
                  : Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _refreshAll,
                            child: ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(18, 14, 18, 20),
                              children: [
                                _buildHero(group),
                                const SizedBox(height: 18),
                                TabBar(
                                  controller: _tabController,
                                  indicator: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  dividerColor: Colors.transparent,
                                  labelColor: Colors.white,
                                  unselectedLabelColor: const Color(0xFF64748B),
                                  tabs: const [
                                    Tab(text: 'Chat'),
                                    Tab(text: 'Members'),
                                    Tab(text: 'About'),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.56,
                                  child: TabBarView(
                                    controller: _tabController,
                                    children: [
                                      _buildChatTab(group),
                                      _buildMembersTab(group),
                                      _buildAboutTab(group),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildHero(GroupModel group) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1D4ED8),
            Color(0xFF0EA5A4),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                imageUrl: resolveMediaUrl(group.avatar),
                username: group.name,
                radius: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${group.viewerRole.toUpperCase()} • ${group.memberCount} members • ${group.onlineMembers} online',
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            group.motto.isNotEmpty ? group.motto : group.description,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroPill(group.vibe),
              _heroPill(group.isPublic ? 'Public' : 'Private'),
              if (group.approvalRequired) _heroPill('Approval on'),
              if (group.linkedVoiceRoom != null) _heroPill('Voice lounge'),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (group.isMember)
                FilledButton.icon(
                  onPressed: _openVoiceLounge,
                  icon: const Icon(Icons.graphic_eq_rounded),
                  label: const Text('Voice'),
                ),
              if (group.permissions['canInviteFriends'] == true)
                OutlinedButton.icon(
                  onPressed: _showInviteFriendsSheet,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side:
                        BorderSide(color: Colors.white.withValues(alpha: 0.36)),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Invite'),
                ),
              if (!group.isMember && group.isInvited)
                FilledButton(
                  onPressed: _acceptInvite,
                  child: const Text('Accept invite'),
                ),
              if (!group.isMember && !group.isInvited)
                FilledButton(
                  onPressed: _joinGroup,
                  child:
                      Text(group.approvalRequired ? 'Request to join' : 'Join'),
                ),
              if (group.hasTreasure &&
                  group.permissions['canClaimTreasure'] == true)
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await GroupService.claimTreasure(group.id);
                    if (!mounted || result == null) return;
                    await context.read<AuthProvider>().refreshBalance();
                    await _loadGroup(silent: true);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side:
                        BorderSide(color: Colors.white.withValues(alpha: 0.36)),
                  ),
                  icon: const Icon(Icons.card_giftcard_rounded),
                  label: const Text('Claim'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatTab(GroupModel group) {
    if (!group.isMember) {
      return _buildPanel(
        child: const Center(
          child: Text(
            'Join this circle to unlock the live group chat.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return _buildPanel(
      child: Column(
        children: [
          Expanded(
            child: _isLoadingMessages
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'No group messages yet. Start the energy.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        controller: _chatScrollController,
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                UserAvatar(
                                  imageUrl:
                                      resolveMediaUrl(message.senderAvatar),
                                  username: message.senderName,
                                  radius: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                message.senderName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              message.timeAgo,
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        _buildMessageBody(message),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          if (_typingNames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_typingNames.join(', ')} typing...',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          Row(
            children: [
              IconButton(
                onPressed: _isSending ? null : _pickAndSendImage,
                icon: const Icon(Icons.image_outlined),
                tooltip: 'Send image',
              ),
              Expanded(
                child: TextField(
                  controller: _composerController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Send energy to the circle...',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _isSending ? null : _sendMessage,
                child: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMembersTab(GroupModel group) {
    return _buildPanel(
      child: ListView(
        children: [
          if (group.permissions['canApproveRequests'] == true &&
              group.joinRequests.isNotEmpty) ...[
            const Text(
              'Join requests',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 10),
            ...group.joinRequests.map(
              (request) => Card(
                child: ListTile(
                  leading: UserAvatar(
                    imageUrl: resolveMediaUrl(request.user.avatar),
                    username: request.user.username,
                    radius: 18,
                  ),
                  title: Text(request.user.username),
                  subtitle: Text(
                    request.message.isNotEmpty
                        ? request.message
                        : 'Wants to join this circle',
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => _rejectJoinRequest(request),
                        child: const Text('Decline'),
                      ),
                      FilledButton(
                        onPressed: () => _approveJoinRequest(request),
                        child: const Text('Approve'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          ...group.members.map(
            (member) => Card(
              child: ListTile(
                leading: UserAvatar(
                  imageUrl: resolveMediaUrl(member.user.avatar),
                  username: member.user.username,
                  radius: 20,
                ),
                title: Text(member.user.username),
                subtitle: Text(
                  '${member.role.toUpperCase()} • Level ${member.user.level}${member.user.isOnline ? ' • online' : ''}',
                ),
                trailing: IconButton(
                  onPressed: () => _showMemberActions(member),
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutTab(GroupModel group) {
    return _buildPanel(
      child: ListView(
        children: [
          _aboutTile('Owner', group.leaderName),
          _aboutTile('Tag', group.tag),
          _aboutTile('Vibe', group.vibe),
          _aboutTile('Type', group.type),
          _aboutTile('Visibility', group.isPublic ? 'Public' : 'Private'),
          _aboutTile(
            'Join flow',
            group.approvalRequired ? 'Approval required' : 'Instant join',
          ),
          _aboutTile('Messages', '${group.stats['totalMessages'] ?? 0}'),
          _aboutTile('XP', '${group.stats['totalXp'] ?? 0}'),
          if (group.announcement.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Announcement',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              group.announcement,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (group.isMember && !group.isLeader)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _leaveGroup,
                child: const Text('Leave circle'),
              ),
            ),
          if (group.permissions['canDeleteGroup'] == true) ...[
            if (group.isMember && !group.isLeader) const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _deleteGroup,
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete circle'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPanel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _aboutTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
