import 'dart:async';

import 'package:flutter/material.dart';
import '../../services/friend_service.dart';
import '../../services/socket_service.dart';
import '../../services/user_service.dart';
import '../../models/user_model.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/rounded_scaffold.dart';
import '../../utils/constants.dart';
import '../gifts/gift_shop_screen.dart';
import '../messages/chat_screen.dart';
import '../profile/enhanced_profile_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<dynamic> _onlineFriends = [];
  List<dynamic> _allFriends = [];
  List<dynamic> _friendRequests = [];
  List<dynamic> _suggestions = [];
  List<dynamic> _blockedUsers = [];

  bool _isLoading = true;
  String? _error;
  bool _isDisposed = false;
  final List<StreamSubscription> _socketSubscriptions = [];

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 5, vsync: this); // Online, All, Requests, Suggestions, Blocked
    _setupRealtimeListeners();
    _loadData();
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final subscription in _socketSubscriptions) {
      subscription.cancel();
    }
    _tabController.dispose();
    super.dispose();
  }

  void _setupRealtimeListeners() {
    _socketSubscriptions.addAll([
      SocketService.friendStream.listen((_) {
        if (!mounted) return;
        _loadData();
      }),
      SocketService.resyncStream.listen((_) {
        if (!mounted) return;
        _loadData();
      }),
    ]);
  }

  Future<void> _loadData() async {
    _safeSetState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load all data in parallel
      final results = await Future.wait([
        FriendService.getFriends(),
        FriendService.getFriendRequests(),
        FriendService.getFriendSuggestions(),
        FriendService.getBlockedUsers(),
      ]);

      final friendsData = results[0] as Map<String, dynamic>;
      final requests = results[1] as List;
      final suggestions = results[2] as List;
      final blocked = results[3] as List;

      if (!mounted) return;

      _safeSetState(() {
        _onlineFriends = friendsData['online'] ?? [];
        _allFriends = [
          ...?friendsData['online'],
          ...?friendsData['offline'],
        ];
        _friendRequests = requests;
        _suggestions = suggestions;
        _blockedUsers = blocked;
        _isLoading = false;
      });
    } catch (e) {
      _safeSetState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showAddFriendDialog() {
    final queryController = TextEditingController();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    List<UserModel> results = [];
    bool isSearching = false;
    String? feedback;
    Timer? debounce;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> runSearch(String query) async {
            final trimmed = query.trim();
            if (trimmed.length < 2) {
              setDialogState(() {
                results = [];
                isSearching = false;
                feedback = trimmed.isEmpty
                    ? null
                    : 'Type at least 2 characters to search';
              });
              return;
            }

            setDialogState(() {
              isSearching = true;
              feedback = null;
            });

            final foundUsers = await UserService.searchUsers(trimmed);
            if (!mounted) return;

            setDialogState(() {
              results = foundUsers;
              isSearching = false;
              feedback = foundUsers.isEmpty ? 'No users found' : null;
            });
          }

          void scheduleSearch(String value) {
            debounce?.cancel();
            debounce = Timer(
              const Duration(milliseconds: 280),
              () => runSearch(value),
            );
          }

          Future<void> sendRequest(UserModel user) async {
            final success = await FriendService.sendFriendRequest(user.id);
            if (!mounted) return;

            if (success) {
              if (!dialogContext.mounted) return;
              debounce?.cancel();
              Navigator.pop(dialogContext);
              await _loadData();
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text('Friend request sent to ${user.username}!'),
                  backgroundColor: Colors.green,
                ),
              );
              return;
            }

            scaffoldMessenger.showSnackBar(
              SnackBar(
                content: Text('Unable to send request to ${user.username}'),
                backgroundColor: Colors.red,
              ),
            );
          }

          return AlertDialog(
            title: const Text('Add Friend'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Search by username and send a request instantly'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: queryController,
                    autofocus: true,
                    onChanged: scheduleSearch,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isSearching)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(),
                    )
                  else if (results.isNotEmpty)
                    SizedBox(
                      height: 260,
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final user = results[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: UserAvatar(
                              imageUrl: user.avatar,
                              username: user.username,
                              radius: 20,
                            ),
                            title: Text(user.username),
                            subtitle: Text(
                              'Level ${user.level}${user.isOnline ? ' • Online' : ''}',
                            ),
                            trailing: ElevatedButton(
                              onPressed: () => sendRequest(user),
                              child: const Text('Add'),
                            ),
                            onTap: () {
                              debounce?.cancel();
                              Navigator.pop(dialogContext);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                _openProfile(user.id, closeCurrentRoute: false);
                              });
                            },
                          );
                        },
                      ),
                    )
                  else if (feedback != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        feedback!,
                        style: TextStyle(color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  debounce?.cancel();
                  Navigator.pop(dialogContext);
                },
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      debounce?.cancel();
      queryController.dispose();
    });
  }

  String _userIdFrom(dynamic user) => user is Map
      ? (user['_id']?.toString() ?? user['id']?.toString() ?? '')
      : '';

  String _usernameFrom(dynamic user) =>
      user is Map ? (user['username']?.toString() ?? 'Unknown') : 'Unknown';

  String? _avatarFrom(dynamic user) =>
      user is Map ? user['avatar']?.toString() : null;

  void _openChat(dynamic user) {
    final userId = _userIdFrom(user);
    if (userId.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: userId,
          username: _usernameFrom(user),
          avatar: _avatarFrom(user),
        ),
      ),
    );
  }

  void _openProfile(
    String userId, {
    bool closeCurrentRoute = true,
  }) {
    if (userId.isEmpty) return;
    if (closeCurrentRoute) {
      Navigator.pop(context);
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EnhancedProfileScreen(userId: userId),
      ),
    );
  }

  void _openGiftShop(String userId) {
    if (userId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GiftShopScreen(initialRecipientId: userId),
      ),
    );
  }

  Future<void> _handleAcceptRequest(String userId) async {
    final success = await FriendService.acceptFriendRequest(userId);
    if (success && mounted) {
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request accepted!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _handleRejectRequest(String userId) async {
    final success = await FriendService.rejectFriendRequest(userId);
    if (success && mounted) {
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request rejected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _handleRemoveFriend(String userId, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Friend'),
        content: Text(
            'Are you sure you want to remove $username from your friends?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await FriendService.removeFriend(userId);
      if (success && mounted) {
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$username removed from friends'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleSendRequest(String userId, String username) async {
    final success = await FriendService.sendFriendRequest(userId);
    if (success && mounted) {
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Friend request sent to $username!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _handleBlockUser(String userId, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Text(
            'Are you sure you want to block $username? They will not be able to contact you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await FriendService.blockUser(userId);
      if (success && mounted) {
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$username blocked'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleUnblockUser(String userId, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unblock User'),
        content:
            Text('Unblock $username? They will be able to contact you again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await FriendService.unblockUser(userId);
      if (success && mounted) {
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$username unblocked'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Everything from your full friends hub lives here now.',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _showAddFriendDialog,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Add Friend'),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: Colors.white,
          child: Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppColors.primaryBlue,
              labelColor: AppColors.primaryBlue,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorWeight: 3,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Online'),
                Tab(text: 'All'),
                Tab(text: 'Requests'),
                Tab(text: 'Suggestions'),
                Tab(text: 'Blocked'),
              ],
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primaryBlue))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              size: 64, color: Colors.red.shade300),
                          const SizedBox(height: 16),
                          const Text('Failed to load friends'),
                          const SizedBox(height: 8),
                          Text(_error!,
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _loadData,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryBlue,
                                foregroundColor: Colors.white),
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      color: AppColors.primaryBlue,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildOnlineTab(),
                          _buildAllFriendsTab(),
                          _buildRequestsTab(),
                          _buildSuggestionsTab(),
                          _buildBlockedTab(),
                        ],
                      ),
                    ),
        ),
      ],
    );

    if (widget.embedded) {
      return Container(
        color: Colors.transparent,
        child: content,
      );
    }

    return RoundedScaffold(
      title: 'Friends',
      actions: [
        IconButton(
          icon: const Icon(Icons.person_add, color: Colors.white),
          onPressed: _showAddFriendDialog,
        ),
      ],
      body: content,
    );
  }

  Widget _buildOnlineTab() {
    if (_onlineFriends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No friends online',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _onlineFriends.length,
      itemBuilder: (context, index) {
        final friend = _onlineFriends[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceGrey,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            onTap: () =>
                _openProfile(_userIdFrom(friend), closeCurrentRoute: false),
            leading: Stack(
              children: [
                UserAvatar(
                  imageUrl: friend['avatar'],
                  username: friend['username'] ?? '',
                  radius: 24,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            title: Text(friend['username'] ?? 'Unknown'),
            subtitle: Text('Level ${friend['level'] ?? 1} â€¢ Online'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.message),
                  onPressed: () => _openChat(friend),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showFriendOptions(friend),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAllFriendsTab() {
    if (_allFriends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No friends yet',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Add friends to get started',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _allFriends.length,
      itemBuilder: (context, index) {
        final friend = _allFriends[index];
        final isOnline = friend['status']?['isOnline'] ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceGrey,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            onTap: () =>
                _openProfile(_userIdFrom(friend), closeCurrentRoute: false),
            leading: UserAvatar(
              imageUrl: friend['avatar'],
              username: friend['username'] ?? '',
              radius: 24,
            ),
            title: Text(friend['username'] ?? 'Unknown'),
            subtitle: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: isOnline ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(width: 8),
                Text('â€¢ Level ${friend['level'] ?? 1}'),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showFriendOptions(friend),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRequestsTab() {
    if (_friendRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No friend requests',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _friendRequests.length,
      itemBuilder: (context, index) {
        final request = _friendRequests[index];
        final fromUser = request['from'] is Map ? request['from'] : {};

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceGrey,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            leading: UserAvatar(
              imageUrl: fromUser['avatar'],
              username: fromUser['username'] ?? '',
              radius: 20,
            ),
            title: Text(fromUser['username'] ?? 'Unknown'),
            subtitle: const Text('Wants to be friends'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () => _handleAcceptRequest(fromUser['_id']),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _handleRejectRequest(fromUser['_id']),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuggestionsTab() {
    if (_suggestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No suggestions',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final user = _suggestions[index];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceGrey,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            leading: UserAvatar(
              imageUrl: user['avatar'],
              username: user['username'] ?? '',
              radius: 20,
            ),
            title: Text(user['username'] ?? 'Unknown'),
            subtitle: Text('Level ${user['level'] ?? 1} â€¢ Mutual friends'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.person_add, color: Colors.blue),
                  onPressed: () =>
                      _handleSendRequest(user['_id'], user['username']),
                ),
                IconButton(
                  icon: const Icon(Icons.block, color: Colors.red),
                  onPressed: () =>
                      _handleBlockUser(user['_id'], user['username']),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBlockedTab() {
    if (_blockedUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No blocked users',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _blockedUsers.length,
      itemBuilder: (context, index) {
        final user = _blockedUsers[index];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceGrey,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            leading: UserAvatar(
              imageUrl: user['avatar'],
              username: user['username'] ?? '',
              radius: 20,
            ),
            title: Text(user['username'] ?? 'Unknown'),
            subtitle: const Text('Blocked'),
            trailing: IconButton(
              icon: const Icon(Icons.person_add, color: Colors.green),
              onPressed: () =>
                  _handleUnblockUser(user['_id'], user['username']),
            ),
          ),
        );
      },
    );
  }

  void _showFriendOptions(Map<String, dynamic> friend) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.message),
              title: const Text('Message'),
              onTap: () {
                Navigator.pop(context);
                _openChat(friend);
              },
            ),
            ListTile(
              leading: const Icon(Icons.card_giftcard),
              title: const Text('Send Gift'),
              onTap: () {
                Navigator.pop(context);
                _openGiftShop(_userIdFrom(friend));
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text('Block User'),
              onTap: () {
                Navigator.pop(context);
                _handleBlockUser(friend['_id'], friend['username']);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove, color: Colors.red),
              title: const Text('Remove Friend'),
              onTap: () {
                Navigator.pop(context);
                _handleRemoveFriend(friend['_id'], friend['username']);
              },
            ),
          ],
        ),
      ),
    );
  }
}
