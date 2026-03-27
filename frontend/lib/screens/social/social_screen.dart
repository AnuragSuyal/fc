import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/group_model.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/friend_service.dart';
import '../../services/group_service.dart';
import '../../services/message_service.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/user_avatar.dart';
import '../friends/friends_screen.dart';
import '../messages/chat_screen.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabController;

  final List<StreamSubscription> _subs = [];
  final Set<String> _joinedGroupIds = <String>{};
  final Map<String, int> _groupActivityCounts = <String, int>{};

  List<ConversationModel> _conversations = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _friendRequests = [];
  List<Map<String, dynamic>> _suggestions = [];
  List<GroupModel> _myGroups = [];
  List<GroupModel> _discoverGroups = [];
  List<GroupModel> _leaderboard = [];

  Timer? _messageRefreshDebounce;
  Timer? _friendRefreshDebounce;
  Timer? _groupRefreshDebounce;

  bool _isLoading = true;
  bool _isDisposed = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _loadHub();
    _bindRealtime();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _messageRefreshDebounce?.cancel();
    _friendRefreshDebounce?.cancel();
    _groupRefreshDebounce?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    for (final groupId in _joinedGroupIds) {
      SocketService.leaveGroup(groupId);
    }
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  List<Map<String, dynamic>> get _onlineFriends =>
      _friends.where((friend) => _isUserOnline(friend)).toList();

  int get _unreadCount => _conversations.fold<int>(
        0,
        (total, conversation) => total + conversation.unreadCount,
      );

  int get _groupAlertCount => _groupActivityCounts.values.fold<int>(
        0,
        (total, count) => total + count,
      );

  bool get _hasData =>
      _conversations.isNotEmpty ||
      _friends.isNotEmpty ||
      _friendRequests.isNotEmpty ||
      _myGroups.isNotEmpty ||
      _discoverGroups.isNotEmpty ||
      _leaderboard.isNotEmpty;

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1) {
      context.read<AuthProvider>().clearPendingFriendRequests();
    }
  }

  Future<void> _loadHub({bool silent = false}) async {
    if (!silent) {
      _safeSetState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        MessageService.getConversations(),
        FriendService.getFriends(),
        FriendService.getFriendRequests(),
        FriendService.getFriendSuggestions(),
        GroupService.getMyGroups(),
        GroupService.getDiscoverGroups(),
        GroupService.getLeaderboard(),
      ]);

      final conversations = results[0] as List<ConversationModel>;
      final friendsPayload = results[1] as Map<String, dynamic>;
      final requests = _toMapList(results[2]);
      final suggestions = _toMapList(results[3]);
      final myGroups = results[4] as List<GroupModel>;
      final discoverGroups = results[5] as List<GroupModel>;
      final leaderboard = results[6] as List<GroupModel>;
      final onlineFriends = _toMapList(friendsPayload['online']);
      final offlineFriends = _toMapList(friendsPayload['offline']);

      _syncGroupSockets(myGroups);

      _safeSetState(() {
        _conversations = conversations;
        _friends = [...onlineFriends, ...offlineFriends];
        _friendRequests = requests;
        _suggestions = suggestions;
        _myGroups = myGroups;
        _discoverGroups = discoverGroups;
        _leaderboard = leaderboard;
        _isLoading = false;
      });
    } catch (_) {
      _safeSetState(() {
        _isLoading = false;
        _error = 'Could not load social activity right now.';
      });
    }
  }

  Future<void> _refreshMessages() async {
    final conversations = await MessageService.getConversations();
    if (!mounted) return;
    _safeSetState(() {
      _conversations = conversations;
    });
  }

  Future<void> _refreshFriends() async {
    final results = await Future.wait<dynamic>([
      FriendService.getFriends(),
      FriendService.getFriendRequests(),
      FriendService.getFriendSuggestions(),
    ]);

    if (!mounted) return;

    final friendsPayload = results[0] as Map<String, dynamic>;
    final onlineFriends = _toMapList(friendsPayload['online']);
    final offlineFriends = _toMapList(friendsPayload['offline']);
    final requests = _toMapList(results[1]);
    final suggestions = _toMapList(results[2]);

    _safeSetState(() {
      _friends = [...onlineFriends, ...offlineFriends];
      _friendRequests = requests;
      _suggestions = suggestions;
    });

    if (_tabController.index == 1) {
      context.read<AuthProvider>().clearPendingFriendRequests();
    }
  }

  Future<void> _refreshGroups() async {
    final results = await Future.wait<dynamic>([
      GroupService.getMyGroups(),
      GroupService.getDiscoverGroups(),
      GroupService.getLeaderboard(),
    ]);

    if (!mounted) return;

    final myGroups = results[0] as List<GroupModel>;
    final discoverGroups = results[1] as List<GroupModel>;
    final leaderboard = results[2] as List<GroupModel>;
    _syncGroupSockets(myGroups);

    _safeSetState(() {
      _myGroups = myGroups;
      _discoverGroups = discoverGroups;
      _leaderboard = leaderboard;
    });
  }

  void _bindRealtime() {
    _subs.add(
      SocketService.dmStream.listen(_handleDirectMessage),
    );
    _subs.add(
      SocketService.friendStream.listen(_handleFriendEvent),
    );
    _subs.add(
      SocketService.groupMessageStream.listen(_handleGroupMessage),
    );
    _subs.add(
      SocketService.resyncStream.listen((_) => _loadHub(silent: true)),
    );
  }

  void _handleDirectMessage(Map<String, dynamic> event) {
    final messageJson = event['message'];
    final currentUserId = context.read<AuthProvider>().user?.id;

    if (messageJson is! Map || currentUserId == null) {
      _scheduleMessageRefresh();
      return;
    }

    final message =
        MessageModel.fromJson(Map<String, dynamic>.from(messageJson));
    final partnerId = message.senderId == currentUserId
        ? message.recipientId
        : message.senderId;

    if (partnerId == null || partnerId.isEmpty) {
      _scheduleMessageRefresh();
      return;
    }

    final index = _conversations.indexWhere(
      (conversation) =>
          conversation.id == partnerId ||
          conversation.user['_id']?.toString() == partnerId,
    );

    if (index == -1) {
      _scheduleMessageRefresh();
      _markLive('New direct message');
      return;
    }

    final existing = _conversations[index];
    final updatedConversation = ConversationModel(
      id: existing.id,
      user: Map<String, dynamic>.from(existing.user),
      lastMessage: message,
      unreadCount:
          message.senderId == currentUserId ? 0 : existing.unreadCount + 1,
    );

    final updated = [..._conversations]..removeAt(index);
    updated.insert(0, updatedConversation);

    _safeSetState(() {
      _conversations = updated;
    });

    _markLive('New direct message');
  }

  void _handleFriendEvent(Map<String, dynamic> event) {
    final type = event['_eventType']?.toString() ?? '';
    final userId = event['userId']?.toString();

    switch (type) {
      case 'friend_online':
        if (userId != null) {
          _patchPresence(userId, true);
        }
        _markLive('A friend came online');
        break;
      case 'friend_offline':
        if (userId != null) {
          _patchPresence(userId, false);
        }
        _markLive('Friend presence updated');
        break;
      case 'friend_request_received':
        final fromUser = event['from'];
        if (fromUser is Map) {
          final request = <String, dynamic>{
            'from': Map<String, dynamic>.from(fromUser)
          };
          final fromId = request['from']?['_id']?.toString();
          _safeSetState(() {
            if (fromId != null &&
                !_friendRequests.any(
                  (item) => item['from']?['_id']?.toString() == fromId,
                )) {
              _friendRequests = [request, ..._friendRequests];
            }
          });
        } else {
          _scheduleFriendRefresh();
        }
        _markLive('New friend request');
        break;
      default:
        _scheduleFriendRefresh();
        _markLive('Friend activity updated');
        break;
    }
  }

  void _handleGroupMessage(Map<String, dynamic> event) {
    final groupId = event['groupId']?.toString();
    if (groupId == null || groupId.isEmpty) return;

    final index = _myGroups.indexWhere((group) => group.id == groupId);
    if (index == -1) return;

    final group = _myGroups[index];
    final reorderedGroups = [..._myGroups]..removeAt(index);
    reorderedGroups.insert(0, group);

    _safeSetState(() {
      _myGroups = reorderedGroups;
      _groupActivityCounts[groupId] = (_groupActivityCounts[groupId] ?? 0) + 1;
    });

    _markLive('New group message');
  }

  void _patchPresence(String userId, bool isOnline) {
    List<Map<String, dynamic>> patchList(List<Map<String, dynamic>> source) {
      return source.map((entry) {
        if (entry['_id']?.toString() != userId) {
          return entry;
        }

        final updated = Map<String, dynamic>.from(entry);
        final status = updated['status'] is Map
            ? Map<String, dynamic>.from(updated['status'])
            : <String, dynamic>{};
        status['isOnline'] = isOnline;
        status['lastActive'] = DateTime.now().toIso8601String();
        updated['status'] = status;
        return updated;
      }).toList();
    }

    final updatedConversations = _conversations.map((conversation) {
      if (conversation.user['_id']?.toString() != userId) {
        return conversation;
      }

      final user = Map<String, dynamic>.from(conversation.user);
      final status = user['status'] is Map
          ? Map<String, dynamic>.from(user['status'])
          : <String, dynamic>{};
      status['isOnline'] = isOnline;
      status['lastActive'] = DateTime.now().toIso8601String();
      user['status'] = status;

      return ConversationModel(
        id: conversation.id,
        user: user,
        lastMessage: conversation.lastMessage,
        unreadCount: conversation.unreadCount,
      );
    }).toList();

    _safeSetState(() {
      _friends = patchList(_friends);
      _suggestions = patchList(_suggestions);
      _conversations = updatedConversations;
    });
  }

  void _scheduleMessageRefresh() {
    _messageRefreshDebounce?.cancel();
    _messageRefreshDebounce = Timer(
      const Duration(milliseconds: 500),
      _refreshMessages,
    );
  }

  void _scheduleFriendRefresh() {
    _friendRefreshDebounce?.cancel();
    _friendRefreshDebounce = Timer(
      const Duration(milliseconds: 700),
      _refreshFriends,
    );
  }

  void _scheduleGroupRefresh() {
    _groupRefreshDebounce?.cancel();
    _groupRefreshDebounce = Timer(
      const Duration(milliseconds: 800),
      _refreshGroups,
    );
  }

  void _syncGroupSockets(List<GroupModel> groups) {
    final nextIds = groups.map((group) => group.id).toSet();

    for (final groupId in _joinedGroupIds.difference(nextIds)) {
      SocketService.leaveGroup(groupId);
    }

    for (final groupId in nextIds.difference(_joinedGroupIds)) {
      SocketService.joinGroup(groupId);
    }

    _joinedGroupIds
      ..clear()
      ..addAll(nextIds);
  }

  void _markLive(String label) {
    // Intentionally left minimal after removing the hero status card.
  }

  Future<void> _openConversation({
    required String userId,
    required String username,
    String? avatar,
  }) async {
    if (userId.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: userId,
          username: username,
          avatar: _mediaUrl(avatar),
        ),
      ),
    );

    if (!mounted) return;
    await _refreshMessages();
  }

  Future<void> _handleJoinGroup(GroupModel group) async {
    final success = await GroupService.joinGroup(group.id);
    if (!mounted) return;

    if (success) {
      await _refreshGroups();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Joined ${group.name}'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  Future<void> _handleLeaveGroup(GroupModel group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text('Leave ${group.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await GroupService.leaveGroup(group.id);
    if (!mounted) return;

    if (success) {
      await _refreshGroups();
    }
  }

  Future<void> _handleClaimTreasure(GroupModel group) async {
    final result = await GroupService.claimTreasure(group.id);
    if (!mounted || result == null) return;

    await context.read<AuthProvider>().refreshBalance();
    await _refreshGroups();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Treasure claimed: +${result['coins'] ?? 0} coins'),
        backgroundColor: const Color(0xFFF59E0B),
      ),
    );
  }

  Future<void> _showCreateGroupDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final mottoController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Group'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mottoController,
                decoration: const InputDecoration(
                  labelText: 'Motto',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              final group = await GroupService.createGroup(
                name: name,
                description: descriptionController.text.trim(),
                motto: mottoController.text.trim(),
              );

              if (!context.mounted) return;
              Navigator.pop(context);

              if (group != null) {
                await _refreshGroups();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Group "${group.name}" created'),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
                _tabController.animateTo(2);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final currentUserId = context.select<AuthProvider, String?>(
      (auth) => auth.user?.id,
    );
    final authPendingRequests = context.select<AuthProvider, int>(
      (auth) => auth.pendingFriendRequests,
    );
    final pendingRequests = _friendRequests.length > authPendingRequests
        ? _friendRequests.length
        : authPendingRequests;
    final theme = Theme.of(context);
    final mood = context.mood;

    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: _buildErrorCard(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: mood.outlineSoft),
                boxShadow: [
                  BoxShadow(
                    color: mood.shadow,
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: theme.colorScheme.onSurface,
                  borderRadius: BorderRadius.circular(16),
                ),
                labelColor: theme.colorScheme.surface,
                unselectedLabelColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.62),
                tabs: [
                  Tab(
                    child: _SocialTabLabel(
                      label: 'Messages',
                      count: _unreadCount,
                    ),
                  ),
                  Tab(
                    child: _SocialTabLabel(
                      label: 'Friends',
                      count: pendingRequests,
                    ),
                  ),
                  Tab(
                    child: _SocialTabLabel(
                      label: 'Groups',
                      count: _groupAlertCount,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading && !_hasData
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryBlue,
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMessagesTab(currentUserId),
                      _buildFriendsTab(),
                      _buildGroupsTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: _loadHub,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesTab(String? currentUserId) {
    return RefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _refreshMessages,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
        children: [
          _SectionHeader(
            title: 'Inbox',
            subtitle: _conversations.isEmpty
                ? 'No active chats yet'
                : '${_conversations.length} active conversation${_conversations.length == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 12),
          if (_conversations.isEmpty)
            _buildEmptyCard(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'No conversations yet',
              subtitle:
                  'Start a chat with a friend and your inbox will update live here.',
              actionLabel: _onlineFriends.isNotEmpty
                  ? 'Message a friend'
                  : 'Open friends',
              onAction: () {
                _tabController.animateTo(1);
              },
            )
          else ...[
            if (_unreadCount > 0) ...[
              _buildInlinePulse(
                icon: Icons.mark_chat_unread_outlined,
                title: 'Unread right now',
                detail:
                    '$_unreadCount message${_unreadCount == 1 ? '' : 's'} waiting in your inbox',
                color: const Color(0xFF5E5CE6),
              ),
              const SizedBox(height: 12),
            ],
            ..._conversations.map(
              (conversation) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildConversationCard(conversation, currentUserId),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFriendsTab() {
    return const FriendsScreen(embedded: true);
  }

  Widget _buildGroupsTab() {
    return RefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _refreshGroups,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
        children: [
          _SectionHeader(
            title: 'Groups',
            subtitle: _myGroups.isEmpty
                ? 'Create or join a crew'
                : '${_myGroups.length} group${_myGroups.length == 1 ? '' : 's'} in your orbit',
            actionLabel: 'Create',
            onAction: _showCreateGroupDialog,
          ),
          const SizedBox(height: 12),
          if (_myGroups.isEmpty)
            _buildEmptyCard(
              icon: Icons.group_work_outlined,
              title: 'No groups yet',
              subtitle:
                  'Start a private circle for your people or join one and group messages will update here live.',
              actionLabel: 'Create group',
              onAction: _showCreateGroupDialog,
            )
          else
            SizedBox(
              height: 208,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _myGroups.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    _buildMyGroupCard(_myGroups[index]),
              ),
            ),
          const SizedBox(height: 20),
          _SectionHeader(
            title: 'Discover',
            subtitle: _discoverGroups.isEmpty
                ? 'No new groups to discover'
                : 'Find new circles to join',
          ),
          const SizedBox(height: 12),
          if (_discoverGroups.isEmpty)
            _buildMiniEmptyCard(
              'Fresh public groups will appear here when they become available.',
            )
          else
            ..._discoverGroups.take(8).map(
                  (group) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildDiscoverGroupTile(group),
                  ),
                ),
          const SizedBox(height: 20),
          _SectionHeader(
            title: 'Leaderboard',
            subtitle: 'Top active circles right now',
            actionLabel: 'Refresh',
            onAction: _refreshGroups,
          ),
          const SizedBox(height: 12),
          if (_leaderboard.isEmpty)
            _buildMiniEmptyCard(
              'Leaderboard data is not available yet.',
            )
          else
            ..._leaderboard.take(5).toList().asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildLeaderboardTile(entry.key + 1, entry.value),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildConversationCard(
    ConversationModel conversation,
    String? currentUserId,
  ) {
    final username = conversation.user['username']?.toString() ?? 'Unknown';
    final avatar = _mediaUrl(conversation.user['avatar']?.toString());
    final isOnline = conversation.user['status']?['isOnline'] == true;
    final isFromMe = conversation.lastMessage.senderId == currentUserId;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _openConversation(
        userId: conversation.id,
        username: username,
        avatar: conversation.user['avatar']?.toString(),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: conversation.unreadCount > 0
                ? AppColors.primaryBlue.withValues(alpha: 0.18)
                : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              children: [
                UserAvatar(
                  imageUrl: avatar,
                  username: username,
                  radius: 28,
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF34D399),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        conversation.lastMessage.timeAgo,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isFromMe
                        ? 'You: ${conversation.lastMessage.content}'
                        : conversation.lastMessage.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: conversation.unreadCount > 0 && !isFromMe
                          ? const Color(0xFF0F172A)
                          : AppColors.textSecondary,
                      fontWeight: conversation.unreadCount > 0 && !isFromMe
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (conversation.unreadCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: const BoxDecoration(
                  color: AppColors.primaryBlue,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${conversation.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyGroupCard(GroupModel group) {
    final groupAvatar = _mediaUrl(group.avatar);
    final memberCount =
        group.memberCount > 0 ? group.memberCount : group.members.length;
    final activityCount = _groupActivityCounts[group.id] ?? 0;

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () async {
        _safeSetState(() {
          _groupActivityCounts.remove(group.id);
        });
        await Navigator.pushNamed(
          context,
          '/groups/detail',
          arguments: group.id,
        );
        if (!mounted) return;
        _scheduleGroupRefresh();
      },
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A),
              Color(0xFF312E81),
              Color(0xFF5B21B6),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF312E81).withValues(alpha: 0.16),
              blurRadius: 20,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  imageUrl: groupAvatar,
                  username: group.name,
                  radius: 22,
                ),
                const Spacer(),
                if (activityCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$activityCount new',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              group.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              group.motto.isNotEmpty ? group.motto : group.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                height: 1.45,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                _SmallGlassTag(label: '$memberCount members'),
                const SizedBox(width: 8),
                if (group.hasTreasure) _SmallGlassTag(label: 'Treasure'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleLeaveGroup(group),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: const Text('Leave'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: group.hasTreasure
                        ? () => _handleClaimTreasure(group)
                        : () async {
                            _groupActivityCounts.remove(group.id);
                            await Navigator.pushNamed(
                              context,
                              '/groups/detail',
                              arguments: group.id,
                            );
                            if (!mounted) return;
                            _scheduleGroupRefresh();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF312E81),
                    ),
                    child: Text(group.hasTreasure ? 'Claim' : 'Open'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoverGroupTile(GroupModel group) {
    final memberCount =
        group.memberCount > 0 ? group.memberCount : group.members.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          UserAvatar(
            imageUrl: _mediaUrl(group.avatar),
            username: group.name,
            radius: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$memberCount members  •  ${group.motto.isNotEmpty ? group.motto : group.type}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _handleJoinGroup(group),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTile(int rank, GroupModel group) {
    final badgeColor = switch (rank) {
      1 => const Color(0xFFF59E0B),
      2 => const Color(0xFF94A3B8),
      3 => const Color(0xFFC08457),
      _ => const Color(0xFFE2E8F0),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '#$rank',
                style: TextStyle(
                  color: rank <= 3 ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${group.stats['totalXp'] ?? 0} XP  •  ${group.memberCount > 0 ? group.memberCount : group.members.length} members',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pushNamed(
                context,
                '/groups/detail',
                arguments: group.id,
              );
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  Widget _buildInlinePulse({
    required IconData icon,
    required String title,
    required String detail,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniEmptyCard(String text) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          height: 1.5,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _toMapList(dynamic value) {
    if (value is! List) return [];

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  bool _isUserOnline(Map<String, dynamic> user) {
    return user['status']?['isOnline'] == true || user['isOnline'] == true;
  }

  String? _mediaUrl(String? path) {
    if (path == null || path.isEmpty || path == 'null') {
      return null;
    }

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    return '${ApiService.baseUrl}/uploads/$path';
  }
}

class _SocialTabLabel extends StatelessWidget {
  final String label;
  final int count;

  const _SocialTabLabel({
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = DefaultTextStyle.of(context).style.color ??
        Theme.of(context).textTheme.bodyMedium?.color ??
        AppColors.textSecondary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: activeColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _SmallGlassTag extends StatelessWidget {
  final String label;

  const _SmallGlassTag({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
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
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
