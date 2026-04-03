import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/room_model.dart';
import '../../models/user_model.dart';
import '../../services/room_service.dart';
import '../../services/socket_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/room_card.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/vip/vip_badge.dart';
import '../../widgets/vip/vip_name_text.dart';
import '../profile/enhanced_profile_screen.dart';
import '../rooms/my_room_entry_screen.dart';
import '../rooms/room_detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  static const _fallbackCategories = [
    {'id': 'all', 'name': 'All'},
    {'id': 'voice', 'name': 'Voice'},
    {'id': 'music', 'name': 'Music'},
    {'id': 'video', 'name': 'Video'},
    {'id': 'chat', 'name': 'Chat'},
    {'id': 'battle', 'name': 'Battle'},
    {'id': 'auction', 'name': 'Auction'},
  ];

  final _searchController = TextEditingController();
  final List<RoomModel> _featuredRooms = [];
  List<RoomModel> _liveRooms = [];
  List<RoomModel> _followedRooms = [];
  List<UserModel> _matchedUsers = [];
  List<Map<String, dynamic>> _categories = const [];
  String _selectedCategory = 'all';
  String? _hoveredCategory;
  String? _pressedCategory;
  final String _selectedSort = 'onlineCount';
  bool _isLoading = true;
  bool _isDisposed = false;
  int _activeRequestId = 0;
  Timer? _searchDebounce;
  Timer? _realtimeDebounce;
  Timer? _rallyExpiryTimer;
  StreamSubscription<Map<String, dynamic>>? _roomRealtimeSubscription;
  StreamSubscription<Map<String, dynamic>>? _socketResyncSubscription;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _subscribeToRealtime();
    unawaited(_loadExploreData());
  }

  @override
  void dispose() {
    _isDisposed = true;
    _searchDebounce?.cancel();
    _realtimeDebounce?.cancel();
    _rallyExpiryTimer?.cancel();
    _roomRealtimeSubscription?.cancel();
    _socketResyncSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) setState(fn);
  }

  String get _searchQuery => _searchController.text.trim();
  bool get _hasActiveSearch => _searchQuery.isNotEmpty;

  void _subscribeToRealtime() {
    _roomRealtimeSubscription = SocketService.roomUpdateStream.listen((data) {
      final eventType = data['_eventType']?.toString();
      if (!{
        'room_created',
        'room_deleted',
        'room_updated',
        'lobby_update',
        'participant_joined',
        'participant_left',
        'rally_fans',
      }.contains(eventType)) {
        return;
      }

      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 500), () {
        unawaited(_loadExploreData(showLoader: false));
      });
    });

    _socketResyncSubscription = SocketService.resyncStream.listen((_) {
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 500), () {
        unawaited(_loadExploreData(showLoader: false));
      });
    });
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 420), () {
      unawaited(_loadExploreData(showLoader: false));
    });
  }

  Future<void> _loadExploreData({bool showLoader = true}) async {
    if (showLoader) _safeSetState(() => _isLoading = true);
    final requestId = ++_activeRequestId;

    try {
      final activeQuery = _searchQuery;
      final results = await Future.wait([
        RoomService.getTrendingRooms(),
        RoomService.getRooms(
          category: _selectedCategory,
          search: activeQuery.isEmpty ? null : activeQuery,
          sort: _selectedSort,
          limit: 20,
        ),
        RoomService.getFollowedRooms(),
        RoomService.getCategories(),
        activeQuery.isEmpty
            ? Future.value(<UserModel>[])
            : UserService.searchUsers(activeQuery),
      ]);

      if (_isDisposed || !mounted || requestId != _activeRequestId) return;

      final trending = results[0] as List<RoomModel>;
      final live = results[1] as List<RoomModel>;
      final followed = results[2] as List<RoomModel>;
      final categories = results[3] as List<Map<String, dynamic>>;
      final users = results[4] as List<UserModel>;
      final query = activeQuery.toLowerCase();
      final spotlightRooms = _extractSpotlightRooms(
        liveRooms: live,
        trendingRooms: trending,
        query: query,
      );

      _safeSetState(() {
        _featuredRooms
          ..clear()
          ..addAll(spotlightRooms);
        _liveRooms = live;
        _followedRooms = followed;
        _matchedUsers = users;
        _categories = categories.isEmpty
            ? _fallbackCategories
            : categories
                .map((category) => Map<String, dynamic>.from(category))
                .toList();
        _isLoading = false;
      });
      _scheduleRallyRefresh([...live, ...followed, ...spotlightRooms]);
    } catch (error) {
      debugPrint('Error loading explore screen: $error');
      if (_isDisposed || !mounted || requestId != _activeRequestId) return;
      _safeSetState(() => _isLoading = false);
    }
  }

  List<RoomModel> _extractSpotlightRooms({
    required List<RoomModel> liveRooms,
    required List<RoomModel> trendingRooms,
    required String query,
  }) {
    final seenIds = <String>{};
    final spotlight = <RoomModel>[];

    bool matchesFilters(RoomModel room) {
      final matchesCategory = _selectedCategory == 'all' ||
          room.category == _selectedCategory ||
          room.type == _selectedCategory ||
          (_selectedCategory == 'battle' && room.type == 'game');
      final matchesQuery = query.isEmpty ||
          room.name.toLowerCase().contains(query) ||
          room.roomId.toLowerCase().contains(query) ||
          room.hostName.toLowerCase().contains(query) ||
          room.tags.any((tag) => tag.toLowerCase().contains(query));
      return matchesCategory && matchesQuery;
    }

    for (final room in [...liveRooms, ...trendingRooms]) {
      if (!room.isRallyActive ||
          seenIds.contains(room.id) ||
          !matchesFilters(room)) {
        continue;
      }
      seenIds.add(room.id);
      spotlight.add(room);
      if (spotlight.length == 6) break;
    }

    return spotlight;
  }

  void _scheduleRallyRefresh(List<RoomModel> rooms) {
    _rallyExpiryTimer?.cancel();

    final now = DateTime.now();
    DateTime? nearestExpiry;
    for (final room in rooms) {
      final expiry = room.rallyExpiresAt;
      if (expiry == null || !expiry.isAfter(now)) continue;
      if (nearestExpiry == null || expiry.isBefore(nearestExpiry)) {
        nearestExpiry = expiry;
      }
    }

    if (nearestExpiry == null) return;

    final duration = nearestExpiry.difference(now) + const Duration(seconds: 1);
    _rallyExpiryTimer = Timer(duration, () {
      if (!_isDisposed && mounted) {
        _loadExploreData(showLoader: false);
      }
    });
  }

  Future<void> _refresh() => _loadExploreData(showLoader: false);

  void _openRoom(RoomModel room) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
    ).then((_) => unawaited(_loadExploreData(showLoader: false)));
  }

  void _openUserProfile(UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EnhancedProfileScreen(userId: user.id),
      ),
    );
  }

  void _openCreateRoom() {
    MyRoomEntryScreen.open(context).then((_) {
      unawaited(_loadExploreData(showLoader: false));
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories.isEmpty ? _fallbackCategories : _categories;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _buildHero(),
          const SizedBox(height: 16),
          _buildCategoryStrip(categories),
          const SizedBox(height: 22),
          if (_hasActiveSearch) ...[
            _sectionTitle(
              'People',
              'Realtime matches for usernames and permanent user UIDs.',
            ),
            const SizedBox(height: 12),
            _buildUserResults(),
            const SizedBox(height: 22),
            _sectionTitle(
              'Rooms',
              'Realtime matches for room names, hosts, and room UIDs.',
            ),
            const SizedBox(height: 12),
            if (_isLoading && _liveRooms.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_liveRooms.isEmpty)
              _buildEmptyState(
                title: 'No matches found',
                message: 'Try another user UID, room UID, host, or room name.',
              )
            else
              ..._liveRooms.map((room) => RoomCard(room: room)),
          ] else ...[
            _sectionTitle(
              'Spotlight rooms',
              'Live spaces worth peeking into right now.',
            ),
            const SizedBox(height: 12),
            _buildFeaturedStrip(),
            const SizedBox(height: 22),
            _sectionTitle(
              'Your corners',
              'Followed rooms stay here for fast re-entry.',
            ),
            const SizedBox(height: 12),
            _buildMyRoomsStrip(),
            const SizedBox(height: 22),
            _sectionTitle(
              'Live right now',
              'Fresh rooms, playful energy, fast joins.',
            ),
            const SizedBox(height: 12),
            if (_isLoading && _liveRooms.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_liveRooms.isEmpty)
              _buildEmptyState()
            else
              ..._liveRooms.map((room) => RoomCard(room: room)),
          ],
        ],
      ),
    );
  }

  Widget _buildHero() {
    final theme = Theme.of(context);
    final mood = context.mood;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: mood.heroGradient,
        boxShadow: [
          BoxShadow(
            color: mood.shadow,
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Explore',
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Find rooms that feel more playful, casual, and alive.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.84),
                        ),
                      ),
                    ],
                  ),
                ),
                _metricBubble('Live', '${_liveRooms.length}'),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _signalCard(
                    title: 'Spotlight',
                    value: '${_featuredRooms.length}',
                    icon: Image.asset(
                      'assets/images/explore_spotlight.png',
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _signalCard(
                    title: 'Following',
                    value: '${_followedRooms.length}',
                    icon: Image.asset(
                      'assets/images/explore_following.png',
                      width: 32,
                      height: 28,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricBubble(String label, String value) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.74),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _signalCard({
    required String title,
    required String value,
    required Widget icon,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Center(child: icon),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.74),
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserResults() {
    if (_matchedUsers.isEmpty) {
      return _buildMiniEmpty(
        'No users found yet. Try a full username or exact user UID.',
      );
    }

    return Column(
      children: _matchedUsers
          .take(6)
          .map(
            (user) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () => _openUserProfile(user),
                borderRadius: BorderRadius.circular(24),
                child: Ink(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: context.mood.outlineSoft),
                  ),
                  child: Row(
                    children: [
                      UserAvatar(
                        imageUrl: user.avatar.isEmpty ? null : user.avatar,
                        username: user.username,
                        radius: 22,
                        shopProfile: user.shopProfile,
                        vipMembership: user.vipMembership,
                        vipLevel: user.vipLevel,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: VipNameText(
                                    user.username,
                                    membership: user.vipMembership,
                                    fallbackVipLevel: user.vipLevel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    fallbackColor: AppColors.textPrimary,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                if (user.vipLevel > 0) ...[
                                  const SizedBox(width: 6),
                                  VipBadge(
                                    membership: user.vipMembership,
                                    fallbackVipLevel: user.vipLevel,
                                    size: VipBadgeSize.small,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.uid.isNotEmpty
                                  ? 'UID ${user.uid}'
                                  : 'Profile',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _pill(
                            'Lv ${user.level}',
                            background:
                                AppColors.primaryBlue.withValues(alpha: 0.12),
                            foreground: AppColors.textPrimary,
                          ),
                          if (user.vipLevel > 0) ...[
                            const SizedBox(height: 8),
                            _pill(
                              user.vipMembership.currentTier.displayName,
                              background:
                                  AppColors.accentBerry.withValues(alpha: 0.12),
                              foreground: AppColors.textPrimary,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildCategoryStrip(List<Map<String, dynamic>> categories) {
    return SizedBox(
      height: 126,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final category = categories[index];
          final id = (category['id'] ?? 'all').toString();
          final label = (category['name'] ?? id).toString();
          final selected = id == _selectedCategory;
          final hovered = _hoveredCategory == id;
          final pressed = _pressedCategory == id;
          final engaged = selected || hovered || pressed;
          final color = _categoryColor(id);
          final artwork = _categoryArtwork(id);
          final labelStyle = (Theme.of(context).textTheme.labelMedium ??
                  const TextStyle(fontSize: 12))
              .copyWith(
            color: AppColors.textPrimary,
            fontWeight: selected || hovered || pressed
                ? FontWeight.w800
                : FontWeight.w700,
          );

          return InkWell(
            onTap: () {
              if (_selectedCategory == id) return;
              _safeSetState(() => _selectedCategory = id);
              unawaited(_loadExploreData(showLoader: false));
            },
            onHover: (value) {
              if (_hoveredCategory == (value ? id : null)) return;
              _safeSetState(() => _hoveredCategory = value ? id : null);
            },
            onHighlightChanged: (value) {
              if (_pressedCategory == (value ? id : null)) return;
              _safeSetState(() => _pressedCategory = value ? id : null);
            },
            borderRadius: BorderRadius.circular(26),
            splashColor: color.withValues(alpha: 0.12),
            highlightColor: color.withValues(alpha: 0.08),
            child: Ink(
              width: 104,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: 0.14)
                      : pressed
                          ? color.withValues(alpha: 0.12)
                          : hovered
                              ? color.withValues(alpha: 0.07)
                              : Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: selected
                        ? color.withValues(alpha: 0.45)
                        : engaged
                            ? color.withValues(alpha: 0.26)
                            : context.mood.outlineSoft,
                  ),
                  boxShadow: engaged
                      ? [
                          BoxShadow(
                            color: color.withValues(
                              alpha: pressed ? 0.16 : 0.09,
                            ),
                            blurRadius: pressed ? 10 : 16,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      scale: pressed
                          ? 0.94
                          : (hovered ? 1.06 : (selected ? 1.03 : 1)),
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: artwork != null
                          ? SizedBox(
                              width: 62,
                              height: 62,
                              child: Image.asset(
                                artwork,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            )
                          : Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(_categoryIcon(id), color: color),
                            ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 32,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          style: labelStyle,
                          child: Text(
                            label.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(
    String title,
    String subtitle, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
      ],
    );
  }

  Widget _buildFeaturedStrip() {
    if (_featuredRooms.isEmpty) {
      return _buildMiniEmpty(
          'No spotlight rooms yet. Try a different category.');
    }

    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _featuredRooms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final room = _featuredRooms[index];
          final accent = _categoryColor(room.type);
          return InkWell(
            onTap: () => _openRoom(room),
            borderRadius: BorderRadius.circular(30),
            child: Ink(
              width: 280,
              decoration: BoxDecoration(
                color: const Color(0xFF0B1120),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.18),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _buildFeaturedBackdrop(room, accent),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.12),
                              Colors.black.withValues(alpha: 0.22),
                              Colors.black.withValues(alpha: 0.78),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: -34,
                      right: -18,
                      child: Container(
                        width: 124,
                        height: 124,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _roomPill(room.type.toUpperCase()),
                              const Spacer(),
                              _pill(
                                '${room.onlineCount} online',
                                background:
                                    Colors.white.withValues(alpha: 0.14),
                                foreground: Colors.white,
                              ),
                              if (room.isRallyActive) ...[
                                const SizedBox(width: 8),
                                _pill(
                                  'RALLY ON',
                                  background: AppColors.warningOrange
                                      .withValues(alpha: 0.18),
                                  foreground: Colors.white,
                                ),
                              ],
                            ],
                          ),
                          const Spacer(),
                          Text(
                            room.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            room.description.isEmpty
                                ? 'Drop in and join the room.'
                                : room.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.86),
                                  height: 1.4,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              UserAvatar(
                                imageUrl: room.hostAvatar,
                                username: room.hostName,
                                radius: 14,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      room.hostName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'UID ${room.roomId}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Colors.white
                                                .withValues(alpha: 0.78),
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMyRoomsStrip() {
    if (_followedRooms.isEmpty) {
      return _buildMiniEmpty(
        'No followed rooms yet. Follow a live room and it will appear here in realtime.',
      );
    }

    final activeRooms = _followedRooms.where((room) => room.roomActive).toList();
    final offlineRooms =
        _followedRooms.where((room) => !room.roomActive).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (activeRooms.isNotEmpty) ...[
          _buildFollowedRoomGroupLabel(
            'Active now',
            '${activeRooms.length} live',
            color: AppColors.successGreen,
          ),
          const SizedBox(height: 10),
          _buildFollowedRoomLane(activeRooms, isLiveSection: true),
        ],
        if (activeRooms.isNotEmpty && offlineRooms.isNotEmpty)
          const SizedBox(height: 18),
        if (offlineRooms.isNotEmpty) ...[
          _buildFollowedRoomGroupLabel(
            'Offline',
            '${offlineRooms.length} waiting',
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 10),
          _buildFollowedRoomLane(offlineRooms, isLiveSection: false),
        ],
      ],
    );
  }

  Widget _buildFollowedRoomGroupLabel(
    String title,
    String subtitle, {
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildFollowedRoomLane(
    List<RoomModel> rooms, {
    required bool isLiveSection,
  }) {
    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: rooms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final room = rooms[index];
          return _buildFollowedRoomCard(room, highlightLive: isLiveSection);
        },
      ),
    );
  }

  Widget _buildFollowedRoomCard(
    RoomModel room, {
    required bool highlightLive,
  }) {
    final accent = _categoryColor(room.type);
    final isLive = room.roomActive;

    return InkWell(
      onTap: () => _openRoom(room),
      borderRadius: BorderRadius.circular(26),
      child: Ink(
        width: 176,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: isLive ? 1 : 0.9),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: highlightLive
                ? accent.withValues(alpha: 0.26)
                : context.mood.outlineSoft,
          ),
          boxShadow: highlightLive
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Opacity(
          opacity: isLive ? 1 : 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _pill(
                    isLive ? 'LIVE' : 'OFFLINE',
                    background: isLive
                        ? AppColors.successGreen.withValues(alpha: 0.14)
                        : Colors.black.withValues(alpha: 0.06),
                    foreground:
                        isLive ? AppColors.successGreen : AppColors.textSecondary,
                  ),
                  const Spacer(),
                  _pill(
                    room.type.toUpperCase(),
                    background: accent.withValues(alpha: 0.14),
                    foreground: AppColors.textPrimary,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildMyRoomPreview(room, accent),
              const Spacer(),
              Text(
                room.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                isLive
                    ? '${room.onlineCount} online • ${room.followers} fans'
                    : 'Waiting for host/admin • ${room.followers} fans',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniEmpty(String text) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
      ),
    );
  }

  Widget _buildEmptyState({
    String title = 'No rooms found',
    String message =
        'Try another search or category, or open your permanent room and tune it for your crowd.',
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.secondaryBlue.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.waves_rounded,
              color: AppColors.secondaryBlue,
            ),
          ),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _openCreateRoom,
            child: const Text('Open my room'),
          ),
        ],
      ),
    );
  }

  Widget _roomPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _pill(
    String label, {
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _buildMyRoomPreview(RoomModel room, Color accent) {
    final imageUrl = _normalizeImageUrl(room.coverImage) ??
        _normalizeImageUrl(room.hostAvatar);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 46,
        width: double.infinity,
        color: accent.withValues(alpha: 0.08),
        child: imageUrl == null
            ? Center(
                child: Icon(
                  _categoryIcon(room.type),
                  size: 24,
                  color: accent,
                ),
              )
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(
                    _categoryIcon(room.type),
                    size: 24,
                    color: accent,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildFeaturedBackdrop(RoomModel room, Color accent) {
    final coverImage = _normalizeImageUrl(room.coverImage);
    if (coverImage != null) {
      return Image.network(
        coverImage,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFeaturedFallback(accent, room),
      );
    }
    return _buildFeaturedFallback(accent, room);
  }

  Widget _buildFeaturedFallback(Color accent, RoomModel room) {
    final hostAvatar = _normalizeImageUrl(room.hostAvatar);
    if (hostAvatar != null) {
      return Image.network(
        hostAvatar,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            _buildFeaturedIconFallback(accent, room.type),
      );
    }
    return _buildFeaturedIconFallback(accent, room.type);
  }

  Widget _buildFeaturedIconFallback(Color accent, String roomType) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.96),
            AppColors.accentBerry,
            const Color(0xFF050608),
          ],
        ),
      ),
      child: Align(
        alignment: Alignment.center,
        child: Icon(
          _categoryIcon(roomType),
          size: 92,
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
    );
  }

  String? _normalizeImageUrl(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty || raw.toLowerCase() == 'null') {
      return null;
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return AppConfig.normalizeBackendUrl(raw);
    }
    final normalizedPath = raw.startsWith('/') ? raw : '/$raw';
    return '${AppConfig.socketUrl}$normalizedPath';
  }

  Color _categoryColor(String id) {
    switch (id) {
      case 'voice':
        return AppColors.secondaryBlue;
      case 'music':
        return AppColors.accentBerry;
      case 'video':
        return AppColors.accentSky;
      case 'chat':
        return AppColors.successGreen;
      case 'battle':
        return AppColors.warningOrange;
      case 'auction':
        return AppColors.errorRed;
      case 'all':
        return AppColors.primaryBlue;
      default:
        return AppColors.primaryBlue;
    }
  }

  String? _categoryArtwork(String id) {
    switch (id) {
      case 'all':
        return 'assets/images/explore_all_rooms.png';
      case 'voice':
        return 'assets/images/explore_voice_chat.png';
      case 'music':
        return 'assets/images/explore_music.png';
      case 'video':
        return 'assets/images/explore_video.png';
      default:
        return null;
    }
  }

  IconData _categoryIcon(String id) {
    switch (id) {
      case 'all':
        return Icons.explore_rounded;
      case 'voice':
        return Icons.record_voice_over_rounded;
      case 'music':
        return Icons.music_note_rounded;
      case 'video':
        return Icons.videocam_rounded;
      case 'chat':
        return Icons.chat_bubble_rounded;
      case 'battle':
        return Icons.sports_esports_rounded;
      case 'auction':
        return Icons.gavel_rounded;
      default:
        return Icons.grid_view_rounded;
    }
  }

  // ignore: unused_element
  String _shortLabel(String label) {
    if (label.length <= 8) return label;
    return '${label.substring(0, 7)}…';
  }
}
