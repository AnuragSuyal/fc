import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/friend_service.dart';
import '../../services/socket_service.dart';
import '../../services/user_service.dart';
import '../../models/user_model.dart';
import '../../widgets/app_search_icon.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/rounded_scaffold.dart';
import '../../utils/constants.dart';
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
  List<dynamic> _incomingRequests = [];
  List<dynamic> _outgoingRequests = [];
  List<dynamic> _suggestions = [];
  List<dynamic> _blockedUsers = [];

  bool _isLoading = true;
  bool _hasLoadedOnce = false;
  String? _error;
  bool _isDisposed = false;
  final List<StreamSubscription> _socketSubscriptions = [];
  Timer? _realtimeReloadDebounce;

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
    _realtimeReloadDebounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _setupRealtimeListeners() {
    _socketSubscriptions.addAll([
      SocketService.friendStream.listen(_handleRealtimeFriendEvent),
      SocketService.resyncStream.listen((_) {
        if (!mounted) return;
        _loadData(silent: true);
      }),
    ]);
  }

  void _handleRealtimeFriendEvent(Map<String, dynamic> event) {
    final type = event['_eventType']?.toString() ?? '';

    switch (type) {
      case 'friend_request_received':
        _upsertIncomingRequest(event);
        _removeSuggestionByUserId(_userIdFrom(event['from']));
        _scheduleRealtimeReload();
        break;
      case 'friend_request_sent':
        _upsertOutgoingRequest(event);
        _removeSuggestionByUserId(_peerUserId(event));
        _scheduleRealtimeReload();
        break;
      case 'friend_request_accepted':
        _removeRequestsForUser(_peerUserId(event));
        _removeSuggestionByUserId(_peerUserId(event));
        _scheduleRealtimeReload();
        break;
      case 'friend_request_rejected':
        _removeRequestsForUser(
          _peerUserId(event) ?? event['userId']?.toString(),
        );
        _scheduleRealtimeReload();
        break;
      case 'friend_online':
        _patchPresence(event['userId']?.toString(), true);
        break;
      case 'friend_offline':
        _patchPresence(event['userId']?.toString(), false);
        break;
      default:
        _scheduleRealtimeReload();
        break;
    }
  }

  void _scheduleRealtimeReload() {
    _realtimeReloadDebounce?.cancel();
    _realtimeReloadDebounce = Timer(
      const Duration(milliseconds: 600),
      () => _loadData(silent: true),
    );
  }

  Future<void> _loadData({bool silent = false}) async {
    final showLoading = !_hasLoadedOnce || !silent;

    _safeSetState(() {
      if (showLoading) {
        _isLoading = true;
      }
      _error = null;
    });

    try {
      // Load all data in parallel
      final results = await Future.wait([
        FriendService.getFriends(),
        FriendService.getFriendRequestOverview(),
        FriendService.getFriendSuggestions(),
        FriendService.getBlockedUsers(),
      ]);

      final friendsData = results[0] as Map<String, dynamic>;
      final requestsOverview = results[1] as Map<String, dynamic>;
      final suggestions = results[2] as List;
      final blocked = results[3] as List;

      if (!mounted) return;

      _safeSetState(() {
        _onlineFriends = friendsData['online'] ?? [];
        _allFriends = [
          ...?friendsData['online'],
          ...?friendsData['offline'],
        ];
        _incomingRequests = requestsOverview['incoming'] is List
            ? List<dynamic>.from(requestsOverview['incoming'] as List)
            : [];
        _outgoingRequests = requestsOverview['outgoing'] is List
            ? List<dynamic>.from(requestsOverview['outgoing'] as List)
            : [];
        _suggestions = suggestions;
        _blockedUsers = blocked;
        _hasLoadedOnce = true;
        _isLoading = false;
      });
      _syncPendingRequestCount(_incomingRequests.length);
    } catch (e) {
      if (!silent || !_hasLoadedOnce) {
        _safeSetState(() {
          _error = e.toString();
          _isLoading = false;
        });
      } else {
        debugPrint('Silent friend refresh failed: $e');
      }
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
              await _loadData(silent: true);
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
                      prefixIcon: AppSearchIcon(size: 18),
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

  int get _requestTotal => _incomingRequests.length + _outgoingRequests.length;

  void _syncPendingRequestCount([int? count]) {
    if (!mounted) return;
    context
        .read<AuthProvider>()
        .syncPendingFriendRequests(count ?? _incomingRequests.length);
  }

  Map<String, dynamic> _requestUser(dynamic request, {bool outgoing = false}) {
    if (request is! Map) return const <String, dynamic>{};
    final raw = outgoing ? request['user'] : request['from'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  Map<String, dynamic>? _mapUser(dynamic user) {
    if (user is Map<String, dynamic>) {
      return Map<String, dynamic>.from(user);
    }
    if (user is Map) {
      return Map<String, dynamic>.from(user);
    }
    return null;
  }

  Map<String, dynamic>? _findKnownUser(String userId) {
    final sources = <dynamic>[
      ..._suggestions,
      ..._onlineFriends,
      ..._allFriends,
      ..._blockedUsers,
      ..._incomingRequests.map(_requestUser),
      ..._outgoingRequests.map(
        (request) => _requestUser(request, outgoing: true),
      ),
    ];

    for (final source in sources) {
      final user = _mapUser(source);
      if (user != null && _userIdFrom(user) == userId) {
        return user;
      }
    }

    return null;
  }

  String _requestSubtitle(dynamic request, {required bool outgoing}) {
    final requestMap = request is Map ? Map<String, dynamic>.from(request) : {};
    final sentAt = requestMap['sentAt']?.toString();
    final prefix = outgoing ? 'Request sent' : 'Wants to be friends';
    if (sentAt == null || sentAt.isEmpty) return prefix;

    final parsed = DateTime.tryParse(sentAt);
    if (parsed == null) return prefix;
    final diff = DateTime.now().difference(parsed);
    if (diff.inMinutes < 1) {
      return outgoing ? 'Sent just now' : 'Sent just now';
    }
    if (diff.inHours < 1) {
      return '$prefix • ${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1) {
      return '$prefix • ${diff.inHours}h ago';
    }
    return '$prefix • ${diff.inDays}d ago';
  }

  String _requestBadgeLabel({required bool outgoing}) {
    return outgoing ? 'Sent request' : 'Received request';
  }

  String _requestTimeLabel(dynamic request, {required bool outgoing}) {
    final requestMap = request is Map ? Map<String, dynamic>.from(request) : {};
    final sentAt = requestMap['sentAt']?.toString();
    final prefix = outgoing ? 'Request sent' : 'Received request';
    if (sentAt == null || sentAt.isEmpty) return prefix;

    final parsed = DateTime.tryParse(sentAt);
    if (parsed == null) return prefix;
    final diff = DateTime.now().difference(parsed);
    if (diff.inMinutes < 1) {
      return outgoing ? 'Sent just now' : 'Received just now';
    }
    if (diff.inHours < 1) {
      return '$prefix - ${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1) {
      return '$prefix - ${diff.inHours}h ago';
    }
    return '$prefix - ${diff.inDays}d ago';
  }

  String? _peerUserId(Map<String, dynamic> event) {
    final user = event['user'];
    if (user is Map) {
      return user['_id']?.toString() ?? user['id']?.toString();
    }
    return event['userId']?.toString();
  }

  void _upsertIncomingRequest(Map<String, dynamic> event) {
    final from = event['from'];
    if (from is! Map) return;

    final user = Map<String, dynamic>.from(from);
    final userId = _userIdFrom(user);
    if (userId.isEmpty) return;

    final request = <String, dynamic>{
      'direction': 'incoming',
      'sentAt': event['sentAt'],
      'from': user,
    };

    _safeSetState(() {
      final nextRequests = _incomingRequests
          .where((item) => _userIdFrom(_requestUser(item)) != userId)
          .toList();
      _incomingRequests = [request, ...nextRequests];
    });
    _syncPendingRequestCount();
  }

  void _upsertOutgoingRequest(Map<String, dynamic> event) {
    final user = event['user'];
    if (user is! Map) return;

    final requestUser = Map<String, dynamic>.from(user);
    final userId = _userIdFrom(requestUser);
    if (userId.isEmpty) return;

    final request = <String, dynamic>{
      'direction': 'outgoing',
      'sentAt': event['sentAt'],
      'user': requestUser,
    };

    _safeSetState(() {
      final nextRequests = _outgoingRequests
          .where(
            (item) => _userIdFrom(_requestUser(item, outgoing: true)) != userId,
          )
          .toList();
      _outgoingRequests = [request, ...nextRequests];
    });
  }

  void _removeRequestsForUser(String? userId) {
    if (userId == null || userId.isEmpty) return;

    _safeSetState(() {
      _incomingRequests = _incomingRequests
          .where((item) => _userIdFrom(_requestUser(item)) != userId)
          .toList();
      _outgoingRequests = _outgoingRequests
          .where(
            (item) => _userIdFrom(_requestUser(item, outgoing: true)) != userId,
          )
          .toList();
    });
    _syncPendingRequestCount();
  }

  void _removeSuggestionByUserId(String? userId) {
    if (userId == null || userId.isEmpty) return;

    _safeSetState(() {
      _suggestions =
          _suggestions.where((item) => _userIdFrom(item) != userId).toList();
    });
  }

  void _removeBlockedUserByUserId(String? userId) {
    if (userId == null || userId.isEmpty) return;

    _safeSetState(() {
      _blockedUsers =
          _blockedUsers.where((item) => _userIdFrom(item) != userId).toList();
    });
  }

  void _removeFromFriendCollections(String? userId) {
    if (userId == null || userId.isEmpty) return;

    _safeSetState(() {
      _onlineFriends =
          _onlineFriends.where((item) => _userIdFrom(item) != userId).toList();
      _allFriends =
          _allFriends.where((item) => _userIdFrom(item) != userId).toList();
    });
  }

  void _upsertBlockedUser(Map<String, dynamic> user) {
    final userId = _userIdFrom(user);
    if (userId.isEmpty) return;

    _safeSetState(() {
      _blockedUsers = [
        user,
        ..._blockedUsers.where((item) => _userIdFrom(item) != userId),
      ];
    });
  }

  void _patchPresence(String? userId, bool isOnline) {
    if (userId == null || userId.isEmpty) return;

    List<dynamic> patchList(List<dynamic> source) {
      return source.map((entry) {
        if (entry is! Map || _userIdFrom(entry) != userId) {
          return entry;
        }

        final updated = Map<String, dynamic>.from(entry);
        final status = updated['status'] is Map
            ? Map<String, dynamic>.from(updated['status'] as Map)
            : <String, dynamic>{};
        status['isOnline'] = isOnline;
        status['lastActive'] = DateTime.now().toIso8601String();
        updated['status'] = status;
        return updated;
      }).toList();
    }

    List<dynamic> patchRequestList(
      List<dynamic> source, {
      required bool outgoing,
    }) {
      return source.map((entry) {
        if (entry is! Map) {
          return entry;
        }

        final request = Map<String, dynamic>.from(entry);
        final user = _requestUser(request, outgoing: outgoing);
        if (_userIdFrom(user) != userId) {
          return request;
        }

        final updatedUser = Map<String, dynamic>.from(user);
        final status = updatedUser['status'] is Map
            ? Map<String, dynamic>.from(updatedUser['status'] as Map)
            : <String, dynamic>{};
        status['isOnline'] = isOnline;
        status['lastActive'] = DateTime.now().toIso8601String();
        updatedUser['status'] = status;
        request[outgoing ? 'user' : 'from'] = updatedUser;
        return request;
      }).toList();
    }

    _safeSetState(() {
      _onlineFriends = patchList(_onlineFriends);
      _allFriends = patchList(_allFriends);
      _suggestions = patchList(_suggestions);
      _blockedUsers = patchList(_blockedUsers);
      _incomingRequests = patchRequestList(_incomingRequests, outgoing: false);
      _outgoingRequests = patchRequestList(_outgoingRequests, outgoing: true);
    });
  }

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

  Future<void> _handleAcceptRequest(String userId) async {
    final success = await FriendService.acceptFriendRequest(userId);
    if (success && mounted) {
      _removeRequestsForUser(userId);
      _removeSuggestionByUserId(userId);
      unawaited(_loadData(silent: true));
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
      _removeRequestsForUser(userId);
      unawaited(_loadData(silent: true));
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
        _removeFromFriendCollections(userId);
        unawaited(_loadData(silent: true));
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
      _removeSuggestionByUserId(userId);
      unawaited(_loadData(silent: true));
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
      final knownUser = _findKnownUser(userId);
      final success = await FriendService.blockUser(userId);
      if (success && mounted) {
        _removeSuggestionByUserId(userId);
        _removeRequestsForUser(userId);
        _removeFromFriendCollections(userId);
        if (knownUser != null) {
          _upsertBlockedUser(knownUser);
        }
        unawaited(_loadData(silent: true));
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
        _removeBlockedUserByUserId(userId);
        unawaited(_loadData(silent: true));
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
    final onlineCount = _onlineFriends.length;
    final allCount = _allFriends.length;
    final suggestionCount = _suggestions.length;

    final content = Column(
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: _buildEmbeddedToolbar(),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(18),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textSecondary,
              tabAlignment: TabAlignment.start,
              tabs: [
                _buildTopTab('Online', count: onlineCount),
                _buildTopTab('All', count: allCount),
                _buildTopTab('Requests', count: _requestTotal),
                _buildTopTab(
                  widget.embedded ? 'Suggest' : 'Suggestions',
                  count: suggestionCount,
                ),
                _buildTopTab('Blocked'),
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
                            onPressed: () => _loadData(),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryBlue,
                                foregroundColor: Colors.white),
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadData(silent: true),
                      color: AppColors.primaryBlue,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildOnlineTabView(),
                          _buildAllFriendsTabView(),
                          _buildRequestsTabView(),
                          _buildSuggestionsTabView(),
                          _buildBlockedTabView(),
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

  Widget _buildEmbeddedToolbar() {
    final requestCount = _requestTotal;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Friends',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                requestCount > 0
                    ? '$requestCount request${requestCount == 1 ? '' : 's'} waiting in Requests.'
                    : 'Use the tabs below to manage friends and requests.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _showAddFriendDialog,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: Color(0xFFD1D5DB)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: const Text('Add'),
        ),
      ],
    );
  }

  Widget _buildTopTab(String label, {int count = 0}) {
    final compact = widget.embedded;
    final showBadge = !compact && count > 0;

    return Tab(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (showBadge) ...[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isOnline(dynamic user) {
    return user is Map &&
        (user['status']?['isOnline'] == true || user['isOnline'] == true);
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Icon(icon, size: 34, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonCard({
    required dynamic user,
    required String subtitle,
    Widget? trailing,
    bool showPresence = false,
    VoidCallback? onTap,
  }) {
    final online = _isOnline(user);

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360 && trailing != null;

          final avatar = Stack(
            children: [
              UserAvatar(
                imageUrl: _avatarFrom(user),
                username: _usernameFrom(user),
                radius: 24,
              ),
              if (showPresence)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: online ? const Color(0xFF22C55E) : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          );

          final details = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _usernameFrom(user),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          );

          final actionBar = trailing == null
              ? null
              : Align(
                  alignment: compact ? Alignment.centerRight : Alignment.center,
                  child: trailing,
                );

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          avatar,
                          const SizedBox(width: 14),
                          details,
                        ],
                      ),
                      if (actionBar != null) ...[
                        const SizedBox(height: 12),
                        actionBar,
                      ],
                    ],
                  )
                : Row(
                    children: [
                      avatar,
                      const SizedBox(width: 14),
                      details,
                      if (actionBar != null) ...[
                        const SizedBox(width: 12),
                        actionBar,
                      ],
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Ink(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled
                  ? color.withValues(alpha: 0.18)
                  : const Color(0xFFE5E7EB),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: enabled
                    ? color.withValues(alpha: 0.12)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: enabled ? color : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineTabView() {
    if (_onlineFriends.isEmpty) {
      return _buildEmptyState(
        icon: Icons.wifi_tethering_off_rounded,
        title: 'No friends online right now',
        subtitle:
            'When someone from your circle comes online, they will show up here live.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _onlineFriends.length,
      itemBuilder: (context, index) {
        final friend = _onlineFriends[index];
        return _buildPersonCard(
          user: friend,
          showPresence: true,
          subtitle: 'Level ${friend['level'] ?? 1} - Online now',
          onTap: () =>
              _openProfile(_userIdFrom(friend), closeCurrentRoute: false),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildActionIcon(
                icon: Icons.message_rounded,
                color: const Color(0xFF2563EB),
                onPressed: () => _openChat(friend),
              ),
              const SizedBox(width: 8),
              _buildActionIcon(
                icon: Icons.more_horiz_rounded,
                color: const Color(0xFF475569),
                onPressed: () => _showFriendOptions(friend),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAllFriendsTabView() {
    if (_allFriends.isEmpty) {
      return _buildEmptyState(
        icon: Icons.groups_2_rounded,
        title: 'Your circle is still empty',
        subtitle:
            'Add a few friends and this tab will become your social home.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _allFriends.length,
      itemBuilder: (context, index) {
        final friend = _allFriends[index];
        final isOnline = _isOnline(friend);

        return _buildPersonCard(
          user: friend,
          showPresence: true,
          subtitle:
              '${isOnline ? 'Online' : 'Offline'} - Level ${friend['level'] ?? 1}',
          onTap: () =>
              _openProfile(_userIdFrom(friend), closeCurrentRoute: false),
          trailing: _buildActionIcon(
            icon: Icons.more_horiz_rounded,
            color: const Color(0xFF475569),
            onPressed: () => _showFriendOptions(friend),
          ),
        );
      },
    );
  }

  Widget _buildRequestsTabView() {
    if (_requestTotal == 0) {
      return _buildEmptyState(
        icon: Icons.mark_email_unread_outlined,
        title: 'No friend requests right now',
        subtitle:
            'Received requests will appear separately from sent requests so you always know what needs a reply.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_incomingRequests.isNotEmpty) ...[
          _buildRequestSectionHeaderV2(
            title: 'Received',
            subtitle: '${_incomingRequests.length} waiting for your reply',
            count: _incomingRequests.length,
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 12),
          ..._incomingRequests.map((request) {
            final user = _requestUser(request);
            final userId = _userIdFrom(user);
            return _buildRequestCard(
              user: user,
              outgoing: false,
              subtitle: _requestTimeLabel(request, outgoing: false),
              badgeLabel: _requestBadgeLabel(outgoing: false),
              badgeColor: const Color(0xFFF59E0B),
              onTap: userId.isEmpty
                  ? null
                  : () => _openProfile(userId, closeCurrentRoute: false),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildActionIcon(
                    icon: Icons.check_rounded,
                    color: const Color(0xFF16A34A),
                    onPressed: userId.isEmpty
                        ? null
                        : () => _handleAcceptRequest(userId),
                  ),
                  const SizedBox(width: 8),
                  _buildActionIcon(
                    icon: Icons.close_rounded,
                    color: const Color(0xFFDC2626),
                    onPressed: userId.isEmpty
                        ? null
                        : () => _handleRejectRequest(userId),
                  ),
                ],
              ),
            );
          }),
        ],
        if (_incomingRequests.isNotEmpty && _outgoingRequests.isNotEmpty)
          const SizedBox(height: 10),
        if (_outgoingRequests.isNotEmpty) ...[
          _buildRequestSectionHeaderV2(
            title: 'Sent',
            subtitle: '${_outgoingRequests.length} pending approval',
            count: _outgoingRequests.length,
            color: const Color(0xFF2563EB),
          ),
          const SizedBox(height: 12),
          ..._outgoingRequests.map((request) {
            final user = _requestUser(request, outgoing: true);
            final userId = _userIdFrom(user);
            return _buildRequestCard(
              user: user,
              outgoing: true,
              subtitle: _requestTimeLabel(request, outgoing: true),
              badgeLabel: _requestBadgeLabel(outgoing: true),
              badgeColor: const Color(0xFF2563EB),
              onTap: userId.isEmpty
                  ? null
                  : () => _openProfile(userId, closeCurrentRoute: false),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Waiting',
                  style: TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildSuggestionsTabView() {
    if (_suggestions.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_search_rounded,
        title: 'No fresh suggestions yet',
        subtitle: 'We will surface new people here when they are a good match.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final user = _suggestions[index];
        return _buildPersonCard(
          user: user,
          showPresence: true,
          subtitle: 'Level ${user['level'] ?? 1} - Suggested for your circle',
          onTap: () =>
              _openProfile(_userIdFrom(user), closeCurrentRoute: false),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildActionIcon(
                icon: Icons.person_add_alt_1_rounded,
                color: const Color(0xFF2563EB),
                onPressed: () =>
                    _handleSendRequest(user['_id'], user['username']),
              ),
              const SizedBox(width: 8),
              _buildActionIcon(
                icon: Icons.block_rounded,
                color: const Color(0xFFDC2626),
                onPressed: () =>
                    _handleBlockUser(user['_id'], user['username']),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBlockedTabView() {
    if (_blockedUsers.isEmpty) {
      return _buildEmptyState(
        icon: Icons.block_rounded,
        title: 'No blocked users',
        subtitle:
            'People you block will appear here until you decide to unblock them.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _blockedUsers.length,
      itemBuilder: (context, index) {
        final user = _blockedUsers[index];
        return _buildPersonCard(
          user: user,
          subtitle: 'Blocked',
          onTap: () =>
              _openProfile(_userIdFrom(user), closeCurrentRoute: false),
          trailing: _buildActionIcon(
            icon: Icons.person_add_alt_1_rounded,
            color: const Color(0xFF16A34A),
            onPressed: () => _handleUnblockUser(user['_id'], user['username']),
          ),
        );
      },
    );
  }

  Widget _buildRequestSectionHeaderV2({
    required String title,
    required String subtitle,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard({
    required dynamic user,
    required bool outgoing,
    required String subtitle,
    required String badgeLabel,
    required Color badgeColor,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            UserAvatar(
              imageUrl: _avatarFrom(user),
              username: _usernameFrom(user),
              radius: 22,
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
                          _usernameFrom(user),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeLabel,
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  if (!outgoing) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'This is a received request waiting for your reply.',
                      style: TextStyle(
                        color: Color(0xFFF59E0B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildOnlineTab() {
    if (_onlineFriends.isEmpty) {
      return _buildEmptyState(
        icon: Icons.wifi_tethering_off_rounded,
        title: 'No friends online right now',
        subtitle:
            'When someone from your circle comes online, they will show up here live.',
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

  // ignore: unused_element
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

  // ignore: unused_element
  Widget _buildRequestsTab() {
    if (_requestTotal == 0) {
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_incomingRequests.isNotEmpty) ...[
          _buildRequestSectionHeader(
            'Incoming',
            '${_incomingRequests.length} waiting for your reply',
          ),
          const SizedBox(height: 12),
          ..._incomingRequests.map((request) {
            final fromUser = _requestUser(request);
            final userId = fromUser['_id']?.toString() ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceGrey,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                onTap: userId.isEmpty
                    ? null
                    : () => _openProfile(userId, closeCurrentRoute: false),
                leading: UserAvatar(
                  imageUrl: fromUser['avatar'],
                  username: fromUser['username'] ?? '',
                  radius: 20,
                ),
                title: Text(fromUser['username'] ?? 'Unknown'),
                subtitle: Text(_requestSubtitle(request, outgoing: false)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: userId.isEmpty
                          ? null
                          : () => _handleAcceptRequest(userId),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: userId.isEmpty
                          ? null
                          : () => _handleRejectRequest(userId),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
        if (_incomingRequests.isNotEmpty && _outgoingRequests.isNotEmpty)
          const SizedBox(height: 8),
        if (_outgoingRequests.isNotEmpty) ...[
          _buildRequestSectionHeader(
            'Sent',
            '${_outgoingRequests.length} pending approval',
          ),
          const SizedBox(height: 12),
          ..._outgoingRequests.map((request) {
            final toUser = _requestUser(request, outgoing: true);
            final userId =
                toUser['_id']?.toString() ?? toUser['id']?.toString() ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceGrey,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                onTap: userId.isEmpty
                    ? null
                    : () => _openProfile(userId, closeCurrentRoute: false),
                leading: UserAvatar(
                  imageUrl: toUser['avatar'],
                  username: toUser['username'] ?? '',
                  radius: 20,
                ),
                title: Text(toUser['username'] ?? 'Unknown'),
                subtitle: Text(_requestSubtitle(request, outgoing: true)),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Sent',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildRequestSectionHeader(String title, String subtitle) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(
            title == 'Incoming'
                ? '${_incomingRequests.length}'
                : '${_outgoingRequests.length}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
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

  // ignore: unused_element
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
    final username = _usernameFrom(friend);
    final isOnline = _isOnline(friend);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      UserAvatar(
                        imageUrl: _avatarFrom(friend),
                        username: username,
                        radius: 26,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isOnline
                                  ? 'Online now'
                                  : 'Manage your connection options',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildFriendOptionTile(
                    icon: Icons.message_rounded,
                    title: 'Message',
                    subtitle: 'Open your direct chat instantly',
                    color: const Color(0xFF2563EB),
                    onTap: () {
                      Navigator.pop(context);
                      _openChat(friend);
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildFriendOptionTile(
                    icon: Icons.person_remove_rounded,
                    title: 'Remove Friend',
                    subtitle: 'Take them out of your friends list',
                    color: const Color(0xFFF59E0B),
                    onTap: () {
                      Navigator.pop(context);
                      _handleRemoveFriend(friend['_id'], friend['username']);
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildFriendOptionTile(
                    icon: Icons.block_rounded,
                    title: 'Block User',
                    subtitle: 'Stop contact and hide future requests',
                    color: const Color(0xFFDC2626),
                    onTap: () {
                      Navigator.pop(context);
                      _handleBlockUser(friend['_id'], friend['username']);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFriendOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
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
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: color.withValues(alpha: 0.9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
