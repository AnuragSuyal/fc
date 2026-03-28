import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/room_service.dart';
import '../../services/socket_service.dart';
import '../../services/user_service.dart';
import '../../utils/constants.dart';
import '../app_search_icon.dart';
import '../user_avatar.dart';

class InviteFriendsBottomSheet extends StatefulWidget {
  final String roomId;
  final String roomName;

  const InviteFriendsBottomSheet({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  State<InviteFriendsBottomSheet> createState() =>
      _InviteFriendsBottomSheetState();
}

class _InviteFriendsBottomSheetState extends State<InviteFriendsBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _friendSubscription;

  List<UserModel> _friends = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  final Set<String> _invitedUserIds = {};
  final Set<String> _invitingUserIds = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _friendSubscription = SocketService.friendStream.listen(_handleFriendEvent);
  }

  @override
  void dispose() {
    _friendSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    if (!_isLoading && mounted) {
      setState(() => _isRefreshing = true);
    }

    final result = await UserService.getFriends();
    if (!mounted) return;

    final online = (result['online'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => UserModel.fromJson(Map<String, dynamic>.from(entry)));
    final offline = (result['offline'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => UserModel.fromJson(Map<String, dynamic>.from(entry)));
    final combined = [...online, ...offline];
    combined.sort((left, right) {
      if (left.isOnline != right.isOnline) {
        return left.isOnline ? -1 : 1;
      }
      return left.username
          .toLowerCase()
          .compareTo(right.username.toLowerCase());
    });

    setState(() {
      _friends = combined;
      _isLoading = false;
      _isRefreshing = false;
    });
  }

  void _handleFriendEvent(Map<String, dynamic> event) {
    final type = event['_eventType']?.toString();
    final userId = event['userId']?.toString();
    if (!mounted) return;

    if ((type == 'friend_online' || type == 'friend_offline') &&
        userId != null &&
        userId.isNotEmpty) {
      final nextOnline = type == 'friend_online';
      final updatedFriends = _friends.map((friend) {
        if (friend.id != userId) return friend;
        return friend.copyWith(isOnline: nextOnline);
      }).toList()
        ..sort((left, right) {
          if (left.isOnline != right.isOnline) {
            return left.isOnline ? -1 : 1;
          }
          return left.username
              .toLowerCase()
              .compareTo(right.username.toLowerCase());
        });

      setState(() {
        _friends = updatedFriends;
      });
      return;
    }

    unawaited(_loadFriends());
  }

  Future<void> _inviteUser(UserModel user) async {
    if (_invitedUserIds.contains(user.id) ||
        _invitingUserIds.contains(user.id)) {
      return;
    }

    setState(() {
      _invitingUserIds.add(user.id);
    });

    try {
      final invited = await RoomService.inviteFriend(widget.roomId, user.id);
      if (!mounted || !invited) return;

      setState(() {
        _invitingUserIds.remove(user.id);
        _invitedUserIds.add(user.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${user.username} received your room invite in chat.'),
          duration: const Duration(milliseconds: 1200),
          backgroundColor: AppColors.successGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _invitingUserIds.remove(user.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.errorRed,
        ),
      );
    }
  }

  List<UserModel> get _filteredFriends {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return _friends;

    return _friends.where((friend) {
      return friend.username.toLowerCase().contains(normalizedQuery) ||
          friend.uid.toLowerCase().contains(normalizedQuery);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filteredFriends = _filteredFriends;
    final onlineCount = _friends.where((friend) => friend.isOnline).length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Color(0xFF0F1115),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Invite Friends',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Send a live room invite straight into your friends\' chats.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _buildStatChip(
                      icon: Icons.groups_rounded,
                      label: '${_friends.length} friends',
                    ),
                    const SizedBox(width: 10),
                    _buildStatChip(
                      icon: Icons.circle,
                      label: '$onlineCount online',
                      accent: const Color(0xFF34D399),
                    ),
                    const Spacer(),
                    if (_isRefreshing)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF7DD3FC),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  icon: const AppSearchIcon(size: 20),
                  hintText: 'Search friends by name or UID',
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.32)),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white38,
                          ),
                        ),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
            child: Text(
              _searchQuery.isEmpty
                  ? 'Friends'
                  : '${filteredFriends.length} match${filteredFriends.length == 1 ? '' : 'es'}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredFriends.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: filteredFriends.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final user = filteredFriends[index];
                          return _buildFriendItem(user);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    Color accent = const Color(0xFF7DD3FC),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_search_rounded,
                color: Colors.white54,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No friends found',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty
                  ? 'Once you add friends, they will show up here for one-tap room invites.'
                  : 'Try a different name or UID in the search field.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.54),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendItem(UserModel user) {
    final isInvited = _invitedUserIds.contains(user.id);
    final isInviting = _invitingUserIds.contains(user.id);
    final statusLabel =
        user.isOnline ? 'Online now' : 'Tap + to notify in chat';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isInvited
              ? const Color(0xFF34D399).withValues(alpha: 0.35)
              : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              UserAvatar(
                imageUrl: user.avatar,
                username: user.username,
                radius: 24,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: user.isOnline
                        ? const Color(0xFF34D399)
                        : const Color(0xFF64748B),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF0F1115),
                      width: 2,
                    ),
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
                        user.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (user.vipLevel > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'VIP ${user.vipLevel}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Lv.${user.level} • $statusLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: user.isOnline
                        ? const Color(0xFF86EFAC)
                        : Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: isInvited || isInviting ? null : () => _inviteUser(user),
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isInvited
                    ? const Color(0xFF34D399).withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isInvited
                      ? const Color(0xFF34D399).withValues(alpha: 0.5)
                      : Colors.white10,
                ),
              ),
              child: Center(
                child: isInviting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        isInvited ? Icons.check_rounded : Icons.add_rounded,
                        color:
                            isInvited ? const Color(0xFF86EFAC) : Colors.white,
                        size: 22,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
