import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/post_model.dart';
import '../../models/level_progress_model.dart';
import '../../models/shop_models.dart';
import '../../models/stats_model.dart';
import '../../models/user_model.dart';
import '../../models/vip_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/economy_service.dart';
import '../../services/friend_service.dart';
import '../../services/post_service.dart';
import '../../services/profile_service.dart';
import '../../services/settings_service.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/post_card.dart';
import '../../widgets/level_badge.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/vip/vip_badge.dart';
import '../../widgets/vip/vip_name_text.dart';
import '../messages/chat_screen.dart';

class EnhancedProfileScreen extends StatefulWidget {
  final String? userId;

  const EnhancedProfileScreen({super.key, this.userId});

  @override
  State<EnhancedProfileScreen> createState() => _EnhancedProfileScreenState();
}

class _EnhancedProfileScreenState extends State<EnhancedProfileScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;

  UserModel? _user;
  StatsModel? _economyStats;
  List<PostModel> _posts = const [];
  Map<String, dynamic> _gameStats = const {};
  List<dynamic> _visitors = const [];
  Map<String, dynamic> _relationship = const {};

  bool _isLoading = true;
  bool _isOwner = false;
  bool _friendBusy = false;
  bool _isDisposed = false;
  String? _errorMessage;
  String? _viewerUserId;
  String? _joinedProfileUserId;
  int _visitorTotal = 0;
  String _liveLabel = 'Watching for live updates';
  DateTime? _lastLiveEventAt;

  final List<StreamSubscription> _subscriptions = [];
  Timer? _fallbackRefreshTimer;

  bool get _isFriend => _relationship['isFriend'] == true;
  bool get _hasIncomingRequest => _relationship['hasIncomingRequest'] == true;
  bool get _hasOutgoingRequest => _relationship['hasOutgoingRequest'] == true;
  bool get _canSendFriendRequest =>
      _relationship['canSendFriendRequest'] == true;
  bool get _isBlocked => _relationship['isBlocked'] == true;
  String? get _requestedUserId => widget.userId ?? _viewerUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewerUserId = context.read<AuthProvider>().user?.id;
    _tabController = TabController(length: 2, vsync: this);
    _bindRealtime();
    unawaited(_loadProfile(recordVisit: true));
  }

  @override
  void didUpdateWidget(covariant EnhancedProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _switchProfileRoom(null);
      unawaited(_loadProfile(recordVisit: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadProfile(silent: true));
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _fallbackRefreshTimer?.cancel();
    _switchProfileRoom(null);
    _tabController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  void _bindRealtime() {
    _subscriptions.add(SocketService.friendStream.listen(_handleFriendEvent));
    _subscriptions.add(SocketService.profileStream.listen(_handleProfileEvent));
    _subscriptions.add(SocketService.postStream.listen(_handlePostEvent));
    _subscriptions.add(
      SocketService.resyncStream.listen((_) {
        _markRealtime('Reconnected and resynced');
        unawaited(_loadProfile(silent: true));
      }),
    );
    _subscriptions.add(
      SocketService.levelUpStream.listen((_) {
        if (_isOwner) {
          _markRealtime('Level progress updated live');
          unawaited(_loadProfile(silent: true));
        }
      }),
    );
    _subscriptions.add(
      SocketService.balanceStream.listen((_) {
        if (_isOwner) {
          _markRealtime('Wallet synced live');
        }
      }),
    );

    _fallbackRefreshTimer = Timer.periodic(
      const Duration(seconds: 18),
      (_) => _loadProfile(silent: true),
    );
  }

  void _handlePostEvent(Map<String, dynamic> event) {
    final targetUserId = _user?.id;
    if (targetUserId == null) return;
    if (event['userId']?.toString() != targetUserId) return;
    _markRealtime('Posts updated live');
    unawaited(_loadProfile(silent: true));
  }

  void _handleFriendEvent(Map<String, dynamic> event) {
    final type = event['_eventType']?.toString() ?? '';
    final targetUserId = _user?.id;
    if (targetUserId == null) return;

    final payloadUserId = event['userId']?.toString() ??
        (event['from'] is Map ? event['from']['_id']?.toString() : null) ??
        (event['user'] is Map ? event['user']['_id']?.toString() : null);

    if (type == 'friend_online' || type == 'friend_offline') {
      if (payloadUserId != targetUserId) return;
      final isOnline = type == 'friend_online';
      _safeSetState(() {
        _user = _user?.copyWith(
          isOnline: isOnline,
          lastActive: DateTime.now(),
        );
      });
      _markRealtime(
        isOnline ? 'Friend is online now' : 'Friend just went offline',
      );
      return;
    }

    if (_isOwner ||
        payloadUserId == targetUserId ||
        type == 'friend_request_received' ||
        type == 'friend_request_accepted' ||
        type == 'friend_removed') {
      _markRealtime('Friend activity changed');
      unawaited(_loadProfile(silent: true));
    }
  }

  void _handleProfileEvent(Map<String, dynamic> event) {
    final targetUserId = _user?.id;
    if (targetUserId == null) return;
    if (event['userId']?.toString() != targetUserId) return;

    final type = event['_eventType']?.toString() ?? '';
    if (type == 'profile_visitor' && _isOwner) {
      final nextTotal = _toInt(event['visitorCount']);
      _safeSetState(() {
        _visitorTotal = nextTotal;
        final currentUser = _user;
        if (currentUser != null) {
          final nextStats = Map<String, dynamic>.from(currentUser.stats);
          nextStats['visitorCount'] = nextTotal;
          _user = currentUser.copyWith(stats: nextStats);
        }
      });
      _markRealtime('New visitor landed on your profile');
      unawaited(_refreshVisitors());
      return;
    }

    if (event['user'] is Map) {
      _applyRealtimeUserPatch(Map<String, dynamic>.from(event['user'] as Map));
    }

    switch (type) {
      case 'profile_updated':
        _markRealtime('Profile updated live');
        break;
      case 'profile_stats_updated':
        _markRealtime('Game stats updated live');
        break;
      case 'profile_badge_awarded':
        _markRealtime('New badge unlocked');
        break;
      default:
        _markRealtime('Profile synced live');
        break;
    }

    unawaited(_loadProfile(silent: true));
  }

  void _applyRealtimeUserPatch(Map<String, dynamic> incoming) {
    final currentUser = _user;
    if (currentUser == null) return;

    final base = currentUser.toJson();

    if (incoming['status'] is Map) {
      final status = Map<String, dynamic>.from(
        base['status'] as Map<String, dynamic>,
      );
      status.addAll(Map<String, dynamic>.from(incoming['status'] as Map));
      base['status'] = status;
    }

    base.addAll(incoming);

    _safeSetState(() {
      _user = UserModel.fromJson(base);
      _gameStats = _user?.gameStats ?? _gameStats;
    });
  }

  Future<void> _loadProfile({
    bool silent = false,
    bool recordVisit = false,
  }) async {
    final targetUserId = _requestedUserId;
    if (targetUserId == null || targetUserId.isEmpty) {
      _safeSetState(() {
        _isLoading = false;
        _errorMessage = 'User not found';
      });
      return;
    }

    if (!silent) {
      _safeSetState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final authProvider = context.read<AuthProvider>();
    final isOwner = authProvider.user?.id == targetUserId;

    try {
      final futures = <Future<dynamic>>[
        widget.userId == null
            ? ProfileService.getMyProfile()
            : ProfileService.getProfile(targetUserId),
        if (isOwner) EconomyService.getUserStats(),
        if (isOwner) ProfileService.getVisitors(targetUserId, limit: 12),
      ];

      final results = await Future.wait<dynamic>(futures);
      if (!mounted) return;

      final profileData = results[0] is Map<String, dynamic>
          ? results[0] as Map<String, dynamic>
          : <String, dynamic>{};
      final userJson = profileData['user'];
      final loadedUser = userJson is Map<String, dynamic>
          ? UserModel.fromJson(userJson)
          : authProvider.user;

      if (loadedUser == null) {
        throw Exception('User not found');
      }

      final statsData = isOwner && results.length > 1 && results[1] is Map
          ? Map<String, dynamic>.from(results[1] as Map)
          : null;
      final visitorsData = isOwner && results.isNotEmpty && results.last is Map
          ? Map<String, dynamic>.from(results.last as Map)
          : const <String, dynamic>{'visitors': [], 'total': 0};

      _switchProfileRoom(loadedUser.id);

      _safeSetState(() {
        _user = loadedUser;
        _relationship = profileData['relationship'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(profileData['relationship'])
            : <String, dynamic>{
                'isSelf': isOwner,
                'canMessage': isOwner,
              };
        _posts = (profileData['posts'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => PostModel.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false);
        _gameStats = loadedUser.gameStats ?? const {};
        _isOwner = isOwner;
        _economyStats = statsData != null && statsData.isNotEmpty
            ? StatsModel.fromJson(statsData)
            : _economyStats;
        _visitors = visitorsData['visitors'] is List
            ? List<dynamic>.from(visitorsData['visitors'] as List)
            : _visitors;
        _visitorTotal = _toInt(visitorsData['total']);
        _errorMessage = null;
        _isLoading = false;
      });

      if (!isOwner && recordVisit) {
        unawaited(ProfileService.addVisit(targetUserId));
      }
    } catch (_) {
      _safeSetState(() {
        if (!silent || _user == null) {
          _isLoading = false;
          _errorMessage = 'Could not load profile right now';
        }
      });
    }
  }

  Future<void> _refreshVisitors() async {
    final userId = _user?.id;
    if (!_isOwner || userId == null || userId.isEmpty) return;

    final visitorsData = await ProfileService.getVisitors(userId, limit: 12);
    if (!mounted) return;

    _safeSetState(() {
      _visitors = visitorsData['visitors'] is List
          ? List<dynamic>.from(visitorsData['visitors'] as List)
          : _visitors;
      _visitorTotal = _toInt(visitorsData['total']);
    });
  }

  void _upsertLocalPost(PostModel updatedPost) {
    final index = _posts.indexWhere((post) => post.id == updatedPost.id);
    if (index == -1) return;

    _safeSetState(() {
      _posts = List<PostModel>.from(_posts)..[index] = updatedPost;
    });
  }

  Future<void> _togglePostLike(PostModel post) async {
    await PostService.toggleLike(post.id);
  }

  Future<void> _deletePost(PostModel post) async {
    final success = await PostService.deletePost(post.id);
    if (!success) {
      throw Exception('Could not delete the post.');
    }

    _safeSetState(() {
      _posts =
          _posts.where((item) => item.id != post.id).toList(growable: false);
    });
  }

  void _switchProfileRoom(String? nextUserId) {
    final current = _joinedProfileUserId;
    if (current != null && current.isNotEmpty && current != nextUserId) {
      SocketService.leaveProfile(current);
      _joinedProfileUserId = null;
    }

    if (nextUserId == null || nextUserId.isEmpty) return;
    if (_joinedProfileUserId == nextUserId) return;

    SocketService.joinProfile(nextUserId);
    _joinedProfileUserId = nextUserId;
  }

  void _markRealtime(String label) {
    _safeSetState(() {
      _liveLabel = label;
      _lastLiveEventAt = DateTime.now();
    });
  }

  void _openBadgesFeature(List<dynamic> badges) {
    Navigator.pushNamed(context, '/badges', arguments: badges);
  }

  void _openSocialFeature() {
    if (_isOwner) {
      Navigator.pushNamed(context, '/visitors', arguments: _visitors);
      return;
    }

    Navigator.pushNamed(context, '/gifts/history');
  }

  void _openLevelFeature() {
    Navigator.pushNamed(context, '/rankings');
  }

  Future<void> _handleRelationshipAction() async {
    final user = _user;
    if (user == null || _isOwner || _friendBusy || _isBlocked) return;

    _safeSetState(() => _friendBusy = true);
    try {
      if (_hasIncomingRequest) {
        final success = await FriendService.acceptFriendRequest(user.id);
        if (success) {
          _safeSetState(() {
            _relationship = {
              ..._relationship,
              'isFriend': true,
              'hasIncomingRequest': false,
              'hasOutgoingRequest': false,
              'canSendFriendRequest': false,
              'canMessage': true,
            };
          });
          _markRealtime('Friend request accepted');
        }
      } else if (_canSendFriendRequest) {
        final success = await FriendService.sendFriendRequest(user.id);
        if (success) {
          _safeSetState(() {
            _relationship = {
              ..._relationship,
              'hasOutgoingRequest': true,
              'canSendFriendRequest': false,
            };
          });
          _markRealtime('Friend request sent');
        }
      }
    } finally {
      _safeSetState(() => _friendBusy = false);
    }
  }

  Future<void> _selectRegion() async {
    final user = _user;
    if (!_isOwner || user == null) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final mood = context.mood;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: mood.outlineSoft),
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
                      region == user.region
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
        );
      },
    );

    if (selected == null || selected == user.region) return;

    final response = await SettingsService.saveProfile({'region': selected});
    if (!mounted || response == null) return;

    _safeSetState(() {
      _user = user.copyWith(region: selected);
    });
    context.read<AuthProvider>().updateUserDetails(region: selected);
    _markRealtime('Region updated');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Region updated to $selected')),
    );
  }

  void _openChat() {
    final user = _user;
    if (user == null || _isBlocked) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: user.id,
          username: user.username,
          avatar: user.avatar,
        ),
      ),
    );
  }

  String _relationshipLabel() {
    if (_isFriend) return 'Friends';
    if (_hasIncomingRequest) return 'Accept Friend';
    if (_hasOutgoingRequest) return 'Requested';
    if (_isBlocked) return 'Unavailable';
    return 'Add Friend';
  }

  @override
  Widget build(BuildContext context) {
    final mood = context.mood;

    if (_isLoading && _user == null) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(gradient: mood.shellGradient),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final user = _user;
    if (user == null) {
      return _buildErrorState();
    }

    final authUser = context.select<AuthProvider, UserModel?>(
      (auth) => auth.user,
    );
    final username = _isOwner && authUser?.username.isNotEmpty == true
        ? authUser!.username
        : user.username;
    final avatarUrl = _mediaUrl(
      _isOwner && authUser?.avatar.isNotEmpty == true
          ? authUser!.avatar
          : user.avatar,
    );
    final coverUrl = _mediaUrl(
      _isOwner && authUser?.coverPhoto?.isNotEmpty == true
          ? authUser!.coverPhoto
          : user.coverPhoto,
    );
    final bio = _isOwner && (authUser?.bio?.trim().isNotEmpty ?? false)
        ? authUser!.bio
        : user.bio;
    final uid =
        _isOwner && authUser?.uid.isNotEmpty == true ? authUser!.uid : user.uid;
    final region = _isOwner && authUser?.region.isNotEmpty == true
        ? authUser!.region
        : user.region;
    final level = _isOwner
        ? (authUser?.level ?? _economyStats?.level ?? user.level)
        : user.level;
    final xp =
        _isOwner ? (authUser?.xp ?? _economyStats?.xp ?? user.xp) : user.xp;
    final levelInfo = _isOwner
        ? (authUser?.levelInfo ?? _economyStats?.levelInfo ?? user.levelInfo)
        : user.levelInfo;
    final coins = _isOwner
        ? (authUser?.coins ?? _economyStats?.coins ?? user.coins)
        : user.coins;
    final gems = _isOwner
        ? (authUser?.gems ?? _economyStats?.gems ?? user.gems)
        : user.gems;
    final vipLevel = _isOwner
        ? (authUser?.vipLevel ?? _economyStats?.vipLevel ?? user.vipLevel)
        : user.vipLevel;
    final shopProfile = _isOwner
        ? (authUser?.shopProfile ?? user.shopProfile)
        : user.shopProfile;
    final nextLevelXp =
        levelInfo.nextLevelXp ?? _economyStats?.nextLevelXp ?? 0;
    final xpProgress = levelInfo.progress;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: mood.shellGradient),
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.primaryBlue,
            onRefresh: _loadProfile,
            child: NestedScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTopBar(),
                          const SizedBox(height: 16),
                          _buildHeroCard(
                            username: username,
                            avatarUrl: avatarUrl,
                            coverUrl: coverUrl,
                            uid: uid,
                            bio: bio,
                            region: region,
                            level: level,
                            xp: xp,
                            levelInfo: levelInfo,
                            xpProgress: xpProgress,
                            nextLevelXp: nextLevelXp,
                            vipLevel: vipLevel,
                            vipMembership: _isOwner
                                ? (authUser?.vipMembership ?? user.vipMembership)
                                : user.vipMembership,
                            shopProfile: shopProfile,
                            coins: coins,
                            gems: gems,
                          ),
                          const SizedBox(height: 16),
                          _buildMetricsPanel(user.stats),
                          const SizedBox(height: 16),
                          _buildLiveProfileCard(
                            user: user,
                            level: level,
                            xp: xp,
                            region: region,
                            coins: coins,
                            gems: gems,
                            badgeCount: user.badges.length,
                          ),
                          if (user.badges.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildBadgesCard(user.badges),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _ProfileTabHeaderDelegate(
                      child: Container(
                        color: mood.shellBottom,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Container(
                          height: 58,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(22),
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
                            splashBorderRadius: BorderRadius.circular(18),
                            tabs: const [
                              Tab(text: 'Feed'),
                              Tab(text: 'Game Stats'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildFeedTab(),
                  _buildStatsTab(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final canPop = Navigator.canPop(context);

    return Row(
      children: [
        if (canPop)
          _TopActionButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.maybePop(context),
          )
        else
          const SizedBox(width: 48, height: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isOwner ? 'My Profile' : 'Profile',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(
                SocketService.isConnected
                    ? 'Connected to live updates'
                    : 'Offline mode with auto refresh',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (_isOwner)
          PopupMenuButton<String>(
            onSelected: (value) => Navigator.pushNamed(context, value),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            itemBuilder: (context) => const [
              PopupMenuItem(value: '/wallet', child: Text('Wallet')),
              PopupMenuItem(value: '/vip', child: Text('VIP Center')),
              PopupMenuItem(
                value: '/daily-rewards',
                child: Text('Daily Rewards'),
              ),
              PopupMenuItem(value: '/quests', child: Text('Quests')),
              PopupMenuItem(value: '/rankings', child: Text('Leaderboards')),
              PopupMenuItem(value: '/settings', child: Text('Settings')),
            ],
            child: const _TopActionButton(
              icon: Icons.more_horiz_rounded,
            ),
          )
        else
          const SizedBox(width: 48, height: 48),
      ],
    );
  }

  Widget _buildHeroCard({
    required String username,
    required String? avatarUrl,
    required String? coverUrl,
    required String uid,
    required String? bio,
    required String region,
    required int level,
    required int xp,
    required LevelProgressSnapshot levelInfo,
    required double xpProgress,
    required int nextLevelXp,
    required int vipLevel,
    required VipMembershipSnapshot vipMembership,
    required UserShopProfile shopProfile,
    required int coins,
    required int gems,
  }) {
    final user = _user!;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: context.mood.loungeGradient,
        image: coverUrl != null
            ? DecorationImage(
                image: NetworkImage(coverUrl),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.36),
                  BlendMode.darken,
                ),
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: context.mood.shadow,
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeroPill(
                  icon: user.isOnline
                      ? Icons.radio_button_checked_rounded
                      : Icons.schedule_rounded,
                  label: user.isOnline ? 'Online now' : _lastActiveLabel(user),
                  accent:
                      user.isOnline ? const Color(0xFF34D399) : Colors.white,
                ),
                if (user.isGuest)
                  const _HeroPill(
                    icon: Icons.flash_on_rounded,
                    label: 'Guest account',
                    accent: Color(0xFFFFD166),
                  ),
                if (_isFriend)
                  const _HeroPill(
                    icon: Icons.favorite_rounded,
                    label: 'Friend',
                    accent: Color(0xFFFF8FA3),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(
                  imageUrl: avatarUrl,
                  username: username,
                  radius: 38,
                  fontSize: 28,
                  shopProfile: shopProfile,
                  vipMembership: vipMembership,
                  vipLevel: vipLevel,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VipNameText(
                        username,
                        membership: vipMembership,
                        fallbackVipLevel: vipLevel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      LevelBadge(
                        level: level,
                        levelInfo: levelInfo,
                        size: LevelBadgeSize.large,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (uid.isNotEmpty)
                            _HeroChip(
                              icon: Icons.badge_outlined,
                              label: 'UID $uid',
                              onTap: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: uid),
                                );
                                if (!mounted) return;
                                _markRealtime('UID copied');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('UID copied to clipboard'),
                                  ),
                                );
                              },
                            ),
                          _HeroChip(
                            icon: Icons.public_rounded,
                            label: region,
                            onTap: _isOwner ? _selectRegion : null,
                          ),
                          _HeroChip(
                            icon: Icons.auto_awesome_rounded,
                            label: 'XP $xp',
                          ),
                          if (vipLevel > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                VipBadge(
                                  membership: vipMembership,
                                  fallbackVipLevel: vipLevel,
                                  size: VipBadgeSize.medium,
                                ),
                                const SizedBox(width: 6),
                                _HeroChip(
                                  icon: Icons.workspace_premium_rounded,
                                  label: vipMembership.currentTier.displayName,
                                ),
                              ],
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
                bio.trim(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 9,
                value: xpProgress,
                backgroundColor: Colors.white.withValues(alpha: 0.16),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFFFD166),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'XP $xp',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  nextLevelXp > 0
                      ? '${levelInfo.xpToNextLevel} XP to next level'
                      : 'Max level reached',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isOwner
                        ? () =>
                            Navigator.pushNamed(context, '/settings/account')
                        : (_isBlocked ? null : _openChat),
                    icon: Icon(
                      _isOwner
                          ? Icons.edit_outlined
                          : Icons.chat_bubble_outline_rounded,
                    ),
                    label: Text(_isOwner ? 'Edit Profile' : 'Chat'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.30),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isOwner
                        ? () => Navigator.pushNamed(context, '/posts/create')
                        : (_isFriend ||
                                _hasOutgoingRequest ||
                                _isBlocked ||
                                _friendBusy
                            ? null
                            : _handleRelationshipAction),
                    icon: _friendBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _isOwner
                                ? Icons.add_photo_alternate_outlined
                                : (_hasIncomingRequest
                                    ? Icons.person_add_alt_1_rounded
                                    : Icons.group_add_rounded),
                          ),
                    label:
                        Text(_isOwner ? 'Create Post' : _relationshipLabel()),
                    style: FilledButton.styleFrom(
                      backgroundColor: _isOwner
                          ? Colors.white
                          : (_isFriend
                              ? AppColors.successGreen
                              : AppColors.primaryBlue),
                      foregroundColor:
                          _isOwner ? AppColors.textPrimary : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            if (_isOwner) ...[
              const SizedBox(height: 12),
              Text(
                '$coins coins and $gems gems available',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.84),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsPanel(Map<String, dynamic> stats) {
    final tiles = [
      (
        'Games',
        '${_toInt(stats['totalGames'])}',
        Icons.sports_esports_rounded,
      ),
      (
        'Wins',
        '${_toInt(stats['totalWins'])}',
        Icons.emoji_events_rounded,
      ),
      (
        'Win Rate',
        '${stats['winRate'] ?? 0}%',
        Icons.trending_up_rounded,
      ),
      (
        _isOwner ? 'Visitors' : 'Friends',
        _isOwner ? '$_visitorTotal' : '${_toInt(stats['friendCount'])}',
        Icons.people_alt_outlined,
      ),
      (
        'Followers',
        '${_toInt(stats['followerCount'])}',
        Icons.favorite_border_rounded,
      ),
      (
        'Following',
        '${_toInt(stats['followingCount'])}',
        Icons.track_changes_rounded,
      ),
    ];

    return _ProfilePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Snapshot',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: tiles
                    .map(
                      (tile) => SizedBox(
                        width: itemWidth,
                        child: _MetricTile(
                          label: tile.$1,
                          value: tile.$2,
                          icon: tile.$3,
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLiveProfileCard({
    required UserModel user,
    required int level,
    required int xp,
    required String region,
    required int coins,
    required int gems,
    required int badgeCount,
  }) {
    final stats = user.stats;

    return _ProfilePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Live Profile',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: SocketService.isConnected
                      ? AppColors.successGreen.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  SocketService.isConnected ? 'LIVE' : 'SYNCING',
                  style: TextStyle(
                    color: SocketService.isConnected
                        ? AppColors.successGreen
                        : AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.mood.surfaceSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: user.isOnline
                        ? AppColors.successGreen
                        : AppColors.warningOrange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _liveLabel,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _lastLiveEventAt == null
                            ? 'Listening for profile activity'
                            : 'Updated ${_timeAgo(_lastLiveEventAt!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 12) / 2;
              final cards = [
                _LiveMiniCard(
                  label: 'Badges',
                  value: '$badgeCount',
                  icon: Icons.workspace_premium_outlined,
                  accent: const Color(0xFFFFC857),
                  onTap: () => _openBadgesFeature(user.badges),
                ),
                _LiveMiniCard(
                  label: _isOwner ? 'Visitors' : 'Gifts',
                  value: _isOwner
                      ? '$_visitorTotal'
                      : '${_toInt(stats['giftsReceived'])}',
                  icon: _isOwner
                      ? Icons.visibility_outlined
                      : Icons.card_giftcard_rounded,
                  accent: const Color(0xFF34D399),
                  onTap: _openSocialFeature,
                ),
                _LiveMiniCard(
                  label: 'Level',
                  value: '$level',
                  icon: Icons.bolt_rounded,
                  accent: const Color(0xFFFF7A45),
                  onTap: _openLevelFeature,
                ),
              ];

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: List.generate(cards.length, (index) {
                  final isLastOddCard =
                      cards.length.isOdd && index == cards.length - 1;
                  return SizedBox(
                    width: isLastOddCard ? constraints.maxWidth : itemWidth,
                    child: cards[index],
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.mood.surfaceSoft.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                _infoRow('Status', user.isOnline ? 'Online now' : 'Offline'),
                const SizedBox(height: 10),
                _infoRow('Last active', _lastActiveLabel(user)),
                const SizedBox(height: 10),
                _infoRow('Region', region),
                const SizedBox(height: 10),
                _infoRow('XP', '$xp'),
                if (_isOwner) ...[
                  const SizedBox(height: 10),
                  _infoRow('Coins', '$coins'),
                  const SizedBox(height: 10),
                  _infoRow('Gems', '$gems'),
                ],
                const SizedBox(height: 10),
                _infoRow('Gifts sent', '${_toInt(stats['giftsSent'])}'),
                const SizedBox(height: 10),
                _infoRow('Gifts received', '${_toInt(stats['giftsReceived'])}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgesCard(List<dynamic> badges) {
    final topBadges = badges.take(4).toList(growable: false);

    return _ProfilePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Highlights',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/badges', arguments: badges);
                },
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: topBadges
                .map(
                  (badge) => InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BadgeDetailScreen(
                            badge: badge is Map
                                ? Map<String, dynamic>.from(badge)
                                : const <String, dynamic>{},
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _badgeRarityColor(_badgeRarity(badge))
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        _badgeTitle(badge),
                        style: TextStyle(
                          color: _badgeRarityColor(_badgeRarity(badge)),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedTab() {
    if (_posts.isEmpty) {
      return _buildEmptyTab(
        icon: Icons.post_add_rounded,
        title:
            _isOwner ? 'Your feed is ready for a first post' : 'No posts yet',
        subtitle: _isOwner
            ? 'Share a room update, win, or moment so this profile feels alive.'
            : 'When this user posts, the feed updates here in real time.',
        actionLabel: _isOwner ? 'Create Post' : null,
        onAction: _isOwner
            ? () => Navigator.pushNamed(context, '/posts/create')
            : null,
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _ProfilePanel(
          child: Text(
            'Latest activity from this profile appears here automatically.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 14),
        ..._posts.map(
          (post) => PostCard(
            post: post,
            onLike: _isBlocked ? null : _togglePostLike,
            onDelete: _isOwner ? _deletePost : null,
            onPostChanged: _upsertLocalPost,
            showActions: !_isBlocked,
            showMenu: _isOwner,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsTab() {
    if (_gameStats.isEmpty) {
      return _buildEmptyTab(
        icon: Icons.bar_chart_rounded,
        title: 'Game stats will appear here',
        subtitle:
            'Wins, play counts, and game-specific strengths update as matches finish.',
      );
    }

    final entries = <({
      String key,
      String title,
      IconData icon,
      Color color,
    })>[
      (
        key: 'werewolf',
        title: 'Werewolf',
        icon: Icons.whatshot_rounded,
        color: const Color(0xFFFF7A45),
      ),
      (
        key: 'drawing',
        title: 'Drawing',
        icon: Icons.brush_rounded,
        color: const Color(0xFF52A1FF),
      ),
      (
        key: 'karaoke',
        title: 'Karaoke',
        icon: Icons.mic_rounded,
        color: const Color(0xFFB56CFF),
      ),
      (
        key: 'colorClash',
        title: 'Color Clash',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFF34D399),
      ),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: entries
          .map((entry) {
            final stats = _gameMap(entry.key);
            if (stats == null) return null;
            return _buildGameStatCard(
              title: entry.title,
              icon: entry.icon,
              accent: entry.color,
              stats: stats,
            );
          })
          .whereType<Widget>()
          .toList(growable: false),
    );
  }

  Widget _buildGameStatCard({
    required String title,
    required IconData icon,
    required Color accent,
    required Map<String, dynamic> stats,
  }) {
    final played = _toInt(stats['played']);
    final won = _toInt(stats['won']);
    final level = _toInt(stats['level']) == 0 ? 1 : _toInt(stats['level']);
    final winRate = played > 0 ? ((won / played) * 100).round() : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _ProfilePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Text(
                  'Level $level',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: 'Wins',
                    value: '$won',
                    icon: Icons.emoji_events_outlined,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    label: 'Played',
                    value: '$played',
                    icon: Icons.sports_esports_outlined,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    label: 'Rate',
                    value: '$winRate%',
                    icon: Icons.insights_rounded,
                    compact: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTab({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      children: [
        const SizedBox(height: 40),
        _ProfilePanel(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(
              children: [
                Icon(icon, size: 36, color: AppColors.textSecondary),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: onAction,
                    child: Text(actionLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: context.mood.shellGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _ProfilePanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: AppColors.errorRed,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _errorMessage ?? 'User not found',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _loadProfile,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic>? _gameMap(String key) {
    final raw = _gameStats[key];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }

  String _lastActiveLabel(UserModel user) {
    if (user.isOnline) return 'Online now';
    final lastActive = user.lastActive;
    if (lastActive == null) return 'Active recently';
    return _timeAgo(lastActive);
  }

  String _timeAgo(DateTime date) {
    final difference = DateTime.now().difference(date);
    if (difference.inDays > 0) return '${difference.inDays}d ago';
    if (difference.inHours > 0) return '${difference.inHours}h ago';
    if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
    return 'Just now';
  }

  String? _mediaUrl(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.startsWith('http')) return trimmed;
    return '${ApiService.baseUrl}/uploads/$trimmed';
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}

class _ProfilePanel extends StatelessWidget {
  final Widget child;

  const _ProfilePanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: child,
    );
  }
}

class _TopActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _TopActionButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(onPressed: onTap, icon: Icon(icon, size: 18)),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _HeroPill({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 7),
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
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 8),
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

    if (onTap == null) return child;
    return InkWell(
        borderRadius: BorderRadius.circular(14), onTap: onTap, child: child);
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool compact;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: context.mood.surfaceSoft,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(icon, size: compact ? 18 : 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: compact ? 16 : 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveMiniCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  const _LiveMiniCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: accent, size: 18),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: accent.withValues(alpha: 0.82),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _ProfileTabHeaderDelegate({required this.child});

  @override
  double get minExtent => 70;

  @override
  double get maxExtent => 70;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _ProfileTabHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}

class BadgeDetailScreen extends StatelessWidget {
  final Map<String, dynamic> badge;

  const BadgeDetailScreen({super.key, required this.badge});

  @override
  Widget build(BuildContext context) {
    final rarity = _badgeRarity(badge);
    final color = _badgeRarityColor(rarity);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: context.mood.shellGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TopActionButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.maybePop(context),
                ),
                const SizedBox(height: 24),
                _ProfilePanel(
                  child: Column(
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _badgeIconLabel(badge),
                          style: TextStyle(
                            fontSize: 40,
                            color: color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _badgeTitle(badge),
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        rarity.toUpperCase(),
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _badgeDescription(badge),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _badgeTitle(dynamic badge) {
  if (badge is Map && badge['name'] != null) {
    return badge['name'].toString();
  }
  return 'Badge';
}

String _badgeDescription(dynamic badge) {
  if (badge is Map && badge['description'] != null) {
    final value = badge['description'].toString().trim();
    if (value.isNotEmpty) return value;
  }
  return 'A profile highlight earned through activity.';
}

String _badgeRarity(dynamic badge) {
  if (badge is Map && badge['rarity'] != null) {
    final value = badge['rarity'].toString().trim().toLowerCase();
    if (value.isNotEmpty) return value;
  }
  return 'common';
}

String _badgeIconLabel(dynamic badge) {
  if (badge is Map && badge['icon'] != null) {
    final value = badge['icon'].toString().trim();
    if (value.isNotEmpty) {
      return value.length > 2 ? value.substring(0, 2) : value;
    }
  }
  final title = _badgeTitle(badge).trim();
  if (title.isEmpty) return 'BD';
  return title.substring(0, title.length >= 2 ? 2 : 1).toUpperCase();
}

Color _badgeRarityColor(String rarity) {
  switch (rarity) {
    case 'rare':
      return const Color(0xFF52A1FF);
    case 'epic':
      return const Color(0xFFB56CFF);
    case 'legendary':
      return const Color(0xFFFFC857);
    default:
      return const Color(0xFF7E8792);
  }
}
