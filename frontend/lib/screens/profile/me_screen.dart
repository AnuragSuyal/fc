import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/post_model.dart';
import '../../models/room_model.dart';
import '../../models/stats_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/economy_service.dart';
import '../../services/friend_service.dart';
import '../../services/profile_service.dart';
import '../../services/room_service.dart';
import '../../services/settings_service.dart';
import '../../services/socket_service.dart';
import '../../services/wedding_service.dart';
import '../../utils/constants.dart';
import '../../widgets/currency_icon.dart';
import '../../widgets/user_avatar.dart';
import '../rooms/room_detail_screen.dart';

class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen>
    with AutomaticKeepAliveClientMixin<MeScreen>, WidgetsBindingObserver {
  UserModel? _profileUser;
  StatsModel? _economyStats;
  List<PostModel> _posts = [];
  Map<String, dynamic> _gameStats = {};
  List<dynamic> _visitors = [];
  List<RoomModel> _myRooms = [];
  int _onlineFriends = 0;
  int _totalFriends = 0;
  int _pendingRequests = 0;
  int _roomInviteCount = 0;
  String? _latestRoomInviteId;
  String? _latestRoomInviteName;
  Map<String, dynamic>? _weddingStatus;
  String _realtimeLabel = 'Waiting for live updates';
  DateTime? _lastRefreshedAt;
  bool _isLoading = true;
  String? _error;
  bool _isDisposed = false;
  String? _currentUserId;

  final List<StreamSubscription> _subs = [];
  Timer? _socialRefreshDebounce;
  Timer? _roomRefreshDebounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final auth = context.read<AuthProvider>();
    _profileUser = auth.user;
    _pendingRequests = auth.pendingFriendRequests;
    _currentUserId = auth.user?.id;

    _bindRealtime();
    _loadDashboard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDashboard(silent: true);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    for (final sub in _subs) {
      sub.cancel();
    }
    _socialRefreshDebounce?.cancel();
    _roomRefreshDebounce?.cancel();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  void _bindRealtime() {
    _subs.add(
      SocketService.balanceStream.listen((_) {
        _markRealtime('Balance updated live');
      }),
    );

    _subs.add(
      SocketService.levelUpStream.listen((_) {
        _markRealtime('Level updated live');
      }),
    );

    _subs.add(
      SocketService.friendStream.listen((event) {
        final type = event['_eventType']?.toString() ?? '';
        if (type == 'friend_request_received') {
          _safeSetState(() {
            _pendingRequests += 1;
          });
          _markRealtime('New friend request');
        } else if (type == 'friend_online' || type == 'friend_offline') {
          _markRealtime('Friend presence updated');
        } else {
          _markRealtime('Friend activity updated');
        }
        _scheduleSocialRefresh();
      }),
    );

    _subs.add(
      SocketService.roomInviteStream.listen((event) {
        final roomId = event['roomId']?.toString();
        final roomName = event['roomName']?.toString();

        _safeSetState(() {
          _roomInviteCount += 1;
          _latestRoomInviteId = roomId;
          _latestRoomInviteName =
              roomName != null && roomName.trim().isNotEmpty ? roomName : null;
        });

        _markRealtime('New room invite');
      }),
    );

    _subs.add(
      SocketService.roomUpdateStream.listen((event) {
        final type = event['_eventType']?.toString() ?? '';
        if (type == 'room_created' ||
            type == 'room_deleted' ||
            type == 'lobby_update' ||
            type == 'room_updated') {
          _markRealtime('Room activity updated');
          _scheduleRoomsRefresh();
        }
      }),
    );

    _subs.add(
      SocketService.postStream.listen((event) {
        final ownUserId = _currentUserId;
        if (ownUserId == null) return;
        if (event['userId']?.toString() == ownUserId) {
          _markRealtime('Posts updated live');
          _loadDashboard(silent: true);
        }
      }),
    );

    _subs.add(
      SocketService.weddingStream.listen((event) {
        final type = event['_eventType']?.toString() ?? 'update';
        switch (type) {
          case 'proposal':
            _markRealtime('New mingle invite');
            break;
          case 'proposal_sent':
            _markRealtime('Mingle invite sent');
            break;
          case 'accepted':
            _markRealtime('Mingle accepted');
            break;
          case 'rejected':
            _markRealtime('Mingle invite rejected');
            break;
          case 'divorced':
            _markRealtime('Relationship status updated');
            break;
          default:
            _markRealtime('Mingle activity updated');
        }
        _refreshWedding();
      }),
    );

    _subs.add(
      SocketService.resyncStream.listen((_) {
        _markRealtime('Resynced after reconnect');
        _loadDashboard(silent: true);
      }),
    );
  }

  void _markRealtime(String label) {
    _safeSetState(() {
      _realtimeLabel = label;
      _lastRefreshedAt = DateTime.now();
    });
  }

  void _scheduleSocialRefresh() {
    _socialRefreshDebounce?.cancel();
    _socialRefreshDebounce = Timer(
      const Duration(milliseconds: 500),
      _refreshSocialData,
    );
  }

  void _scheduleRoomsRefresh() {
    _roomRefreshDebounce?.cancel();
    _roomRefreshDebounce = Timer(
      const Duration(milliseconds: 700),
      _refreshRooms,
    );
  }

  Future<void> _loadDashboard({bool silent = false}) async {
    if (!silent) {
      _safeSetState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final auth = context.read<AuthProvider>();

    try {
      await auth.refreshBalance();

      final results = await Future.wait<dynamic>([
        ProfileService.getMyProfile(),
        EconomyService.getUserStats(),
        FriendService.getFriends(),
        FriendService.getFriendRequests(),
        RoomService.getMyRooms(),
        WeddingService.getMyWedding(),
      ]);

      final profileData = results[0] as Map<String, dynamic>;
      final economyData = results[1] as Map<String, dynamic>;
      final friendsData = results[2] as Map<String, dynamic>;
      final requestsData = results[3] as List<dynamic>;
      final roomsData = results[4] as List<RoomModel>;
      final weddingData = results[5] as Map<String, dynamic>?;

      final userJson = profileData['user'];
      final loadedUser = userJson is Map<String, dynamic>
          ? UserModel.fromJson(userJson)
          : auth.user;

      final posts = (profileData['posts'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(PostModel.fromJson)
          .toList();

      final visitorsData = loadedUser != null && loadedUser.id.isNotEmpty
          ? await ProfileService.getVisitors(loadedUser.id, limit: 5)
          : const <String, dynamic>{'visitors': [], 'total': 0};

      if (!mounted) return;

      _safeSetState(() {
        _profileUser = loadedUser;
        _economyStats =
            economyData.isNotEmpty ? StatsModel.fromJson(economyData) : null;
        _posts = posts;
        _gameStats = loadedUser?.gameStats ?? {};
        _visitors = visitorsData['visitors'] is List
            ? List<dynamic>.from(visitorsData['visitors'])
            : [];
        _myRooms = roomsData;
        _onlineFriends = friendsData['online'] is List
            ? (friendsData['online'] as List).length
            : 0;
        _totalFriends =
            _toInt(friendsData['total']) ?? _onlineFriends + _pendingRequests;
        _pendingRequests = requestsData.length > auth.pendingFriendRequests
            ? requestsData.length
            : auth.pendingFriendRequests;
        _weddingStatus = weddingData;
        _lastRefreshedAt = DateTime.now();
        _isLoading = false;
        _error = loadedUser == null
            ? 'Could not load your profile right now.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      _safeSetState(() {
        _isLoading = false;
        _error = 'Could not load your Me tab right now.';
      });
    }
  }

  Future<void> _refreshSocialData() async {
    try {
      final results = await Future.wait<dynamic>([
        FriendService.getFriends(),
        FriendService.getFriendRequests(),
      ]);

      if (!mounted) return;

      final friendsData = results[0] as Map<String, dynamic>;
      final requestsData = results[1] as List<dynamic>;
      final auth = context.read<AuthProvider>();

      _safeSetState(() {
        _onlineFriends = friendsData['online'] is List
            ? (friendsData['online'] as List).length
            : _onlineFriends;
        _totalFriends = _toInt(friendsData['total']) ?? _totalFriends;
        _pendingRequests = requestsData.length > auth.pendingFriendRequests
            ? requestsData.length
            : auth.pendingFriendRequests;
      });
    } catch (_) {}
  }

  Future<void> _refreshRooms() async {
    try {
      final rooms = await RoomService.getMyRooms();
      if (!mounted) return;
      _safeSetState(() {
        _myRooms = rooms;
      });
    } catch (_) {}
  }

  Future<void> _refreshWedding() async {
    try {
      final wedding = await WeddingService.getMyWedding();
      if (!mounted) return;
      _safeSetState(() {
        _weddingStatus = wedding;
      });
    } catch (_) {}
  }

  Future<void> _selectRegion() async {
    final currentRegion = _profileUser?.region ?? 'Global';
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  'Select Region',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ...AppRegions.values.map(
                (region) => ListTile(
                  leading: Icon(
                    region == currentRegion
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: AppColors.primaryBlue,
                  ),
                  title: Text(region),
                  onTap: () => Navigator.pop(context, region),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected == null || selected == currentRegion) return;

    final response = await SettingsService.saveProfile({'region': selected});
    if (!mounted || response == null) return;

    _safeSetState(() {
      _profileUser = _profileUser?.copyWith(region: selected);
    });
    context.read<AuthProvider>().updateUserDetails(region: selected);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Region updated to $selected')),
    );
  }

  Future<void> _openLatestInvite() async {
    final roomId = _latestRoomInviteId;
    if (roomId == null || roomId.isEmpty) {
      if (!mounted) return;
      Navigator.pushNamed(context, '/explore');
      return;
    }

    final room = await RoomService.getRoomById(roomId);
    if (!mounted) return;

    if (room == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That room is no longer available.')),
      );
      return;
    }

    _safeSetState(() {
      if (_roomInviteCount > 0) {
        _roomInviteCount -= 1;
      }
    });

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
    );
  }

  Future<void> _handleMenuAction(String value) async {
    if (value == 'support') {
      Navigator.pushNamed(context, '/settings/support');
      return;
    }

    if (value == 'logout') {
      final auth = context.read<AuthProvider>();
      await auth.logout();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final authUser = context.select<AuthProvider, UserModel?>(
      (auth) => auth.user,
    );
    final authPendingRequests = context.select<AuthProvider, int>(
      (auth) => auth.pendingFriendRequests,
    );
    final profileUser = _profileUser ?? authUser;

    if (_isLoading && profileUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (profileUser == null) {
      return _buildErrorState();
    }

    final username = authUser?.username.isNotEmpty == true
        ? authUser!.username
        : profileUser.username;
    final avatarUrl = _mediaUrl(
      authUser?.avatar.isNotEmpty == true
          ? authUser!.avatar
          : profileUser.avatar,
    );
    final coverUrl = _mediaUrl(
      profileUser.coverPhoto?.isNotEmpty == true
          ? profileUser.coverPhoto
          : authUser?.coverPhoto,
    );
    final bio = profileUser.bio ?? authUser?.bio;
    final uid =
        authUser?.uid.isNotEmpty == true ? authUser!.uid : profileUser.uid;
    final region = authUser?.region.isNotEmpty == true
        ? authUser!.region
        : profileUser.region;
    final level = authUser?.level ?? _economyStats?.level ?? profileUser.level;
    final xp = authUser?.xp ?? _economyStats?.xp ?? profileUser.xp;
    final coins = authUser?.coins ?? _economyStats?.coins ?? profileUser.coins;
    final gems = authUser?.gems ?? _economyStats?.gems ?? profileUser.gems;
    final vipLevel =
        authUser?.vipLevel ?? _economyStats?.vipLevel ?? profileUser.vipLevel;
    final nextLevelXp = _economyStats?.nextLevelXp ?? (level * 1000);
    final xpProgress =
        nextLevelXp > 0 ? (xp / nextLevelXp).clamp(0.0, 1.0) : 0.0;
    final pendingRequests = _pendingRequests > authPendingRequests
        ? _pendingRequests
        : authPendingRequests;

    return RefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _loadDashboard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        children: [
          _buildHeroCard(
            username: username,
            avatarUrl: avatarUrl,
            coverUrl: coverUrl,
            bio: bio,
            uid: uid,
            region: region,
            level: level,
            xp: xp,
            vipLevel: vipLevel,
            xpProgress: xpProgress,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _buildInlineError(),
          ],
          const SizedBox(height: 18),
          _buildStatStrip(
            coins: coins,
            gems: gems,
            level: level,
            nextLevelXp: nextLevelXp,
            onlineFriends: _onlineFriends,
          ),
          const SizedBox(height: 18),
          _buildLiveCard(
            pendingRequests: pendingRequests,
            weddingLabel: _weddingLabel(),
          ),
          const SizedBox(height: 18),
          _buildSectionHeader(
            title: 'Shortcuts',
            actionLabel: 'View profile',
            onAction: () {
              Navigator.pushNamed(context, '/profile',
                  arguments: profileUser.id);
            },
          ),
          const SizedBox(height: 12),
          _buildQuickActions(pendingRequests),
          const SizedBox(height: 18),
          _buildSectionHeader(
            title: 'My Rooms',
            actionLabel: 'Create',
            onAction: () {
              Navigator.pushNamed(context, '/rooms/create');
            },
          ),
          const SizedBox(height: 12),
          _buildRoomsSection(),
          const SizedBox(height: 18),
          _buildSectionHeader(
            title: 'Recent Posts',
            actionLabel: 'Create',
            onAction: () {
              Navigator.pushNamed(context, '/posts/create');
            },
          ),
          const SizedBox(height: 12),
          _buildPostsSection(),
          const SizedBox(height: 18),
          _buildSectionHeader(
            title: 'Profile Tools',
          ),
          const SizedBox(height: 12),
          _buildToolsGrid(),
        ],
      ),
    );
  }

  Widget _buildHeroCard({
    required String username,
    required String? avatarUrl,
    required String? coverUrl,
    required String? bio,
    required String uid,
    required String region,
    required int level,
    required int xp,
    required int vipLevel,
    required double xpProgress,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryBlue,
            AppColors.accentBerry,
            AppColors.secondaryBlue,
          ],
        ),
        image: coverUrl != null
            ? DecorationImage(
                image: NetworkImage(coverUrl),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.32),
                  BlendMode.darken,
                ),
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.accentBerry.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -28,
            right: -10,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            bottom: -36,
            left: -12,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Me',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const Spacer(),
                    _TopActionButton(
                      icon: Icons.settings_outlined,
                      onTap: () {
                        Navigator.pushNamed(context, '/settings');
                      },
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      onSelected: _handleMenuAction,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'support',
                          child: Text('Support'),
                        ),
                        PopupMenuItem(
                          value: 'logout',
                          child: Text('Logout'),
                        ),
                      ],
                      child: const _TopActionButton(
                        icon: Icons.more_horiz_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.55),
                              width: 3,
                            ),
                          ),
                          child: UserAvatar(
                            imageUrl: avatarUrl,
                            username: username,
                            radius: 38,
                            fontSize: 28,
                          ),
                        ),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFF34D399),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (uid.isNotEmpty) ...[
                            _HeroChip(
                              icon: Icons.badge_outlined,
                              label: 'UID $uid',
                              onTap: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: uid),
                                );
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('UID copied to clipboard'),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _HeroChip(
                                icon: Icons.bolt_rounded,
                                label: 'Level $level',
                              ),
                              _HeroChip(
                                icon: Icons.auto_awesome_rounded,
                                label: 'XP $xp',
                              ),
                              _HeroChip(
                                icon: Icons.public_rounded,
                                label: region,
                                onTap: _selectRegion,
                              ),
                              if (vipLevel > 0)
                                _HeroChip(
                                  icon: Icons.workspace_premium_rounded,
                                  label: 'VIP $vipLevel',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (bio != null && bio.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    bio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: xpProgress,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFFFFD166)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pushNamed(context, '/settings/account');
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit profile'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
    );
  }

  Widget _buildStatStrip({
    required int coins,
    required int gems,
    required int level,
    required int nextLevelXp,
    required int onlineFriends,
  }) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Coins',
            value: '$coins',
            icon: const CurrencyIcon.coins(size: 20),
            color: const Color(0xFFFFB703),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Gems',
            value: '$gems',
            icon: const CurrencyIcon.gems(size: 20),
            color: const Color(0xFF8B5CF6),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Next Level',
            value: '$nextLevelXp',
            icon: Image.asset(
              'assets/images/me_next_level.png',
              width: 30,
              height: 30,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
            color: const Color(0xFF0EA5E9),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Friends Online',
            value: '$onlineFriends',
            icon: Image.asset(
              'assets/images/me_friends_online.png',
              width: 30,
              height: 30,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
            color: const Color(0xFF10B981),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveCard({
    required int pendingRequests,
    required String weddingLabel,
  }) {
    final inviteLabel = _roomInviteCount > 0
        ? '$_roomInviteCount invite${_roomInviteCount == 1 ? '' : 's'}'
        : 'No invites';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
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
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: SocketService.isConnected
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFF59E0B),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  SocketService.isConnected
                      ? 'Realtime connected'
                      : 'Realtime reconnecting',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                _lastRefreshedAt != null
                    ? _timeAgo(_lastRefreshedAt!)
                    : 'Syncing',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _realtimeLabel,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoPill(
                icon: Icons.mark_email_unread_outlined,
                label:
                    '$pendingRequests request${pendingRequests == 1 ? '' : 's'}',
                color: const Color(0xFF5E5CE6),
              ),
              _InfoPill(
                icon: Icons.meeting_room_outlined,
                label: inviteLabel,
                color: const Color(0xFF0EA5E9),
              ),
              _InfoPill(
                icon: Icons.favorite_border_rounded,
                label: weddingLabel,
                color: const Color(0xFFEF476F),
              ),
            ],
          ),
          if (_latestRoomInviteId != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.headset_mic_outlined,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Latest invite',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _latestRoomInviteName ?? 'Tap to open the room',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _openLatestInvite,
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActions(int pendingRequests) {
    final actions = [
      _QuickAction(
        icon: Image.asset(
          'assets/images/me_wallet_quick_action.png',
          width: 32,
          height: 26,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        title: 'Wallet',
        subtitle: 'Coins and gems',
        color: const Color(0xFFFFB703),
        onTap: () => Navigator.pushNamed(context, '/wallet'),
      ),
      _QuickAction(
        icon: Image.asset(
          'assets/images/me_vip_quick_action.png',
          width: 30,
          height: 30,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        title: 'VIP',
        subtitle: 'Perks and status',
        color: const Color(0xFF8B5CF6),
        onTap: () => Navigator.pushNamed(context, '/vip'),
      ),
      _QuickAction(
        icon: const Icon(Icons.favorite_border_rounded),
        title: 'Mingle',
        subtitle: _weddingLabel(),
        color: const Color(0xFFEF476F),
        onTap: () => Navigator.pushNamed(context, '/mingle'),
      ),
      _QuickAction(
        icon: const Icon(Icons.task_alt_rounded),
        title: 'Quests',
        subtitle: 'Daily progress',
        color: const Color(0xFF0EA5E9),
        onTap: () => Navigator.pushNamed(context, '/quests'),
      ),
      _QuickAction(
        icon: const Icon(Icons.card_giftcard_rounded),
        title: 'Rewards',
        subtitle: 'Claim daily gifts',
        color: const Color(0xFF10B981),
        onTap: () => Navigator.pushNamed(context, '/daily-rewards'),
      ),
      _QuickAction(
        icon: const Icon(Icons.visibility_outlined),
        title: 'Visitors',
        subtitle: _visitors.isEmpty
            ? 'People who saw your profile'
            : '${_visitors.length} profile viewer${_visitors.length == 1 ? '' : 's'}',
        color: const Color(0xFF6366F1),
        onTap: () =>
            Navigator.pushNamed(context, '/visitors', arguments: _visitors),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final action = actions[index];
        return InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: action.onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: action.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: IconTheme(
                      data: IconThemeData(color: action.color, size: 24),
                      child: action.icon,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  action.title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  action.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoomsSection() {
    if (_myRooms.isEmpty) {
      return _buildEmptyStateCard(
        icon: Icons.add_home_work_outlined,
        title: 'No rooms yet',
        subtitle:
            'Create your first room and it will start updating here live.',
        actionLabel: 'Create room',
        onAction: () {
          Navigator.pushNamed(context, '/rooms/create');
        },
      );
    }

    return SizedBox(
      height: 192,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _myRooms.length.clamp(0, 6),
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final room = _myRooms[index];
          return InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
              );
            },
            child: Container(
              width: 238,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _roomColor(room.category).withValues(alpha: 0.96),
                    _roomColor(room.type).withValues(alpha: 0.78),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _roomColor(room.category).withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MiniRoomBadge(label: room.type.toUpperCase()),
                      _MiniRoomBadge(label: '${room.onlineCount} online'),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    room.description.isNotEmpty
                        ? room.description
                        : 'Tap to open and manage this room.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        '${room.followers} fans',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Open',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPostsSection() {
    if (_posts.isEmpty) {
      return _buildEmptyStateCard(
        icon: Icons.post_add_outlined,
        title: 'No posts yet',
        subtitle:
            'Share a room update, milestone, or mood so your profile feels alive.',
        actionLabel: 'Create post',
        onAction: () {
          Navigator.pushNamed(context, '/posts/create');
        },
      );
    }

    return Column(
      children: _posts.take(3).map((post) {
        final preview = post.content.trim().isNotEmpty
            ? post.content.trim()
            : 'Shared a media post';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      post.type.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    post.timeAgo,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _PostMetric(
                    icon: Icons.favorite_border_rounded,
                    value: post.likeCount,
                  ),
                  const SizedBox(width: 16),
                  _PostMetric(
                    icon: Icons.mode_comment_outlined,
                    value: post.commentCount,
                  ),
                  const SizedBox(width: 16),
                  _PostMetric(
                    icon: Icons.visibility_outlined,
                    value: post.views,
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildToolsGrid() {
    final items = [
      _ToolCardData(
        icon: Icons.bar_chart_rounded,
        title: 'Game Stats',
        value: '${_gameStats.length}',
        subtitle: 'Tracked games',
        color: const Color(0xFF0EA5E9),
        onTap: () {
          Navigator.pushNamed(context, '/game-stats', arguments: _gameStats);
        },
      ),
      _ToolCardData(
        icon: Icons.dynamic_feed_outlined,
        title: 'Social Move',
        value: '$_totalFriends',
        subtitle: 'Friends posts',
        color: const Color(0xFF2563EB),
        onTap: () {
          Navigator.pushNamed(context, '/feed');
        },
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.icon, color: item.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  item.value,
                  style: TextStyle(
                    color: item.color,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.person_off_outlined,
              size: 54,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Your Me tab could not be loaded.',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Pull to refresh and try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _loadDashboard,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineError() {
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
            onPressed: () => _loadDashboard(silent: true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
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
        const Spacer(),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
      ],
    );
  }

  Widget _buildEmptyStateCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(height: 14),
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
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  String _weddingLabel() {
    final wedding = _weddingStatus;
    if (wedding == null) {
      return 'Single';
    }

    if (wedding['married'] == true) {
      final partner = wedding['partner'];
      final partnerName = partner is Map<String, dynamic>
          ? partner['username']?.toString()
          : null;
      return partnerName != null && partnerName.isNotEmpty
          ? 'With $partnerName'
          : 'Mingling';
    }

    final currentWedding = wedding['wedding'];
    if (currentWedding is Map<String, dynamic>) {
      final status = currentWedding['status']?.toString() ?? '';
      if (status == 'pending') {
        final currentUserId = context.read<AuthProvider>().user?.id ?? '';
        final proposer = currentWedding['proposerId'];
        final proposerId = proposer is Map<String, dynamic>
            ? proposer['_id']?.toString()
            : proposer?.toString();
        if (proposerId == currentUserId) {
          return 'Invite pending';
        }
        return 'Needs reply';
      }
    }

    return 'Single';
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

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  Color _roomColor(String key) {
    switch (key.toLowerCase()) {
      case 'music':
        return const Color(0xFFF97316);
      case 'battle':
        return const Color(0xFFDC2626);
      case 'video':
        return const Color(0xFF2563EB);
      case 'chat':
        return const Color(0xFF0891B2);
      case 'voice':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF0F766E);
    }
  }

  String _timeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    }
    if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    }
    if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    }
    return 'Just now';
  }
}

class _QuickAction {
  final Widget icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _ToolCardData {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ToolCardData({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _HeroChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
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
        ),
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _TopActionButton({
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Widget icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: icon),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniRoomBadge extends StatelessWidget {
  final String label;

  const _MiniRoomBadge({
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

class _PostMetric extends StatelessWidget {
  final IconData icon;
  final int value;

  const _PostMetric({
    required this.icon,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          '$value',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
