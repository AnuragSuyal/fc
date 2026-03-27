import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/user_service.dart';
import '../../services/socket_service.dart';
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
  List<UserModel> _onlineFriends = [];
  List<UserModel> _offlineFriends = [];
  bool _isLoading = true;
  final Set<String> _invitedUserIds = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final result = await UserService.getFriends();
    if (mounted) {
      setState(() {
        _onlineFriends = List<UserModel>.from(
          (result['online'] as List).map((e) => UserModel.fromJson(e)),
        );
        _offlineFriends = List<UserModel>.from(
          (result['offline'] as List).map((e) => UserModel.fromJson(e)),
        );
        _isLoading = false;
      });
    }
  }

  void _inviteUser(UserModel user) {
    if (_invitedUserIds.contains(user.id)) return;

    SocketService.socket?.emit('room:invite', {
      'roomId': widget.roomId,
      'roomName': widget.roomName,
      'targetUserId': user.id,
    });

    setState(() {
      _invitedUserIds.add(user.id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invited ${user.username} to the room'),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredOnline = _onlineFriends
        .where((f) =>
            f.username.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
    final filteredOffline = _offlineFriends
        .where((f) =>
            f.username.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Invite Friends',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                style: const TextStyle(color: Colors.white),
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: const InputDecoration(
                  icon: Icon(Icons.search, color: Colors.white54, size: 20),
                  hintText: 'Search for friends...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : (filteredOnline.isEmpty && filteredOffline.isEmpty)
                    ? const Center(
                        child: Text('No friends found',
                            style: TextStyle(color: Colors.white54)))
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        children: [
                          if (filteredOnline.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              child: Text('Online Friends',
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 13)),
                            ),
                            ...filteredOnline.map((user) =>
                                _buildFriendItem(user, isOnline: true)),
                          ],
                          if (filteredOffline.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              child: Text('Offline Friends',
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 13)),
                            ),
                            ...filteredOffline.map((user) =>
                                _buildFriendItem(user, isOnline: false)),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendItem(UserModel user, {bool isOnline = false}) {
    final isInvited = _invitedUserIds.contains(user.id);

    return ListTile(
      leading: Stack(
        children: [
          UserAvatar(
            imageUrl: user.avatar,
            username: user.username,
            radius: 22,
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1A1A1A), width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(user.username,
          style: const TextStyle(color: Colors.white, fontSize: 15)),
      subtitle: Text('Level ${user.level}',
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: ElevatedButton(
        onPressed: isInvited ? null : () => _inviteUser(user),
        style: ElevatedButton.styleFrom(
          backgroundColor: isInvited ? Colors.white10 : Colors.blueAccent,
          foregroundColor: isInvited ? Colors.white38 : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(80, 32),
        ),
        child: Text(isInvited ? 'Invited' : 'Invite',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }
}






