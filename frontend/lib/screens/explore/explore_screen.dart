import 'dart:async';

import 'package:flutter/foundation.dart';
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
import '../profile/enhanced_profile_screen.dart';
import '../rooms/create_room_screen.dart';
import '../rooms/room_detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    this.focusSignal,
  });

  final ValueListenable<int>? focusSignal;

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
  final _searchFocusNode = FocusNode();
  final List<RoomModel> _featuredRooms = [];
  List<RoomModel> _liveRooms = [];
  List<RoomModel> _myRooms = [];
  List<UserModel> _matchedUsers = [];
  List<Map<String, dynamic>> _categories = const [];
  String _selectedCategory = 'all';
  String _selectedSort = 'onlineCount';
  bool _isLoading = true;
  bool _isDisposed = false;
  int _activeRequestId = 0;
  String _lastLoadedQuery = '';
  Timer? _searchDebounce;
  Timer? _realtimeDebounce;
  StreamSubscription<Map<String, dynamic>>? _roomRealtimeSubscription;
  StreamSubscription<Map<String, dynamic>>? _socketResyncSubscription;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    widget.focusSignal?.addListener(_handleFocusSignal);
    _subscribeToRealtime();
    unawaited(_loadExploreData());
  }

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusSignal == widget.focusSignal) return;
    oldWidget.focusSignal?.removeListener(_handleFocusSignal);
    widget.focusSignal?.addListener(_handleFocusSignal);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _searchDebounce?.cancel();
    _realtimeDebounce?.cancel();
    _roomRealtimeSubscription?.cancel();
    _socketResyncSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    widget.focusSignal?.removeListener(_handleFocusSignal);
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) setState(fn);
  }

  String get _searchQuery => _searchController.text.trim();
  bool get _hasActiveSearch => _searchQuery.isNotEmpty;

  void _handleFocusSignal() {
    if (!mounted || _isDisposed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposed) return;
      _searchFocusNode.requestFocus();
    });
  }

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
        RoomService.getMyRooms(),
        RoomService.getCategories(),
        UserService.searchUsers(activeQuery),
      ]);

      if (_isDisposed || !mounted || requestId != _activeRequestId) return;

      final trending = results[0] as List<RoomModel>;
      final live = results[1] as List<RoomModel>;
      final mine = results[2] as List<RoomModel>;
      final categories = results[3] as List<Map<String, dynamic>>;
      final users = results[4] as List<UserModel>;
      final query = activeQuery.toLowerCase();

      _safeSetState(() {
        _lastLoadedQuery = activeQuery;
        _featuredRooms
          ..clear()
          ..addAll(
            trending.where((room) {
              final matchesCategory = _selectedCategory == 'all' ||
                  room.category == _selectedCategory ||
                  room.type == _selectedCategory;
              final matchesQuery = query.isEmpty ||
                  room.name.toLowerCase().contains(query) ||
                  room.roomId.toLowerCase().contains(query) ||
                  room.hostName.toLowerCase().contains(query) ||
                  room.tags.any((tag) => tag.toLowerCase().contains(query));
              return matchesCategory && matchesQuery;
            }).take(6),
          );
        _liveRooms = live;
        _myRooms = mine;
        _matchedUsers = users;
        _categories = categories.isEmpty
            ? _fallbackCategories
            : categories
                .map((category) => Map<String, dynamic>.from(category))
                .toList();
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Error loading explore screen: $error');
      if (_isDisposed || !mounted || requestId != _activeRequestId) return;
      _safeSetState(() => _isLoading = false);
    }
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

  UserModel? _findExactUserMatch(String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) return null;

    for (final user in _matchedUsers) {
      if (user.uid == normalized) {
        return user;
      }
    }

    return null;
  }

  RoomModel? _findExactRoomMatch(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    for (final room in _liveRooms) {
      if (room.roomId.toLowerCase() == normalized) {
        return room;
      }
    }

    for (final room in _featuredRooms) {
      if (room.roomId.toLowerCase() == normalized) {
        return room;
      }
    }

    return null;
  }

  Future<void> _handleSearchSubmitted([String? queryOverride]) async {
    final query = (queryOverride ?? _searchQuery).trim();
    if (query.isEmpty) return;

    if (_lastLoadedQuery != query) {
      await _loadExploreData(showLoader: false);
      if (!mounted || _isDisposed) return;
    }

    final exactUser = _findExactUserMatch(query);
    if (exactUser != null) {
      _openUserProfile(exactUser);
      return;
    }

    final exactRoom = _findExactRoomMatch(query);
    if (exactRoom != null) {
      _openRoom(exactRoom);
    }
  }

  void _openCreateRoom() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateRoomScreen()),
    ).then((created) {
      if (created == true) {
        unawaited(_loadExploreData(showLoader: false));
      }
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
          _buildSearchBar(),
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
              'Easy re-entry into rooms you already know.',
              actionLabel: 'Create',
              onAction: _openCreateRoom,
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
                    icon: Icons.local_fire_department_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _signalCard(
                    title: 'Your rooms',
                    value: '${_myRooms.length}',
                    icon: Icons.favorite_rounded,
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
    required IconData icon,
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
          Icon(icon, color: Colors.white),
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

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      textInputAction: TextInputAction.search,
      onSubmitted: _handleSearchSubmitted,
      decoration: InputDecoration(
        hintText: 'Search user UID, room UID, hosts',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: PopupMenuButton<String>(
          initialValue: _selectedSort,
          icon: const Icon(Icons.tune_rounded),
          onSelected: (value) {
            if (_selectedSort == value) return;
            _safeSetState(() => _selectedSort = value);
            unawaited(_loadExploreData(showLoader: false));
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'onlineCount', child: Text('Most online')),
            PopupMenuItem(value: 'newest', child: Text('Newest first')),
          ],
        ),
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
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
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
                              'VIP ${user.vipLevel}',
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
      height: 98,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final category = categories[index];
          final id = (category['id'] ?? 'all').toString();
          final label = (category['name'] ?? id).toString();
          final selected = id == _selectedCategory;
          final color = _categoryColor(id);

          return InkWell(
            onTap: () {
              if (_selectedCategory == id) return;
              _safeSetState(() => _selectedCategory = id);
              unawaited(_loadExploreData(showLoader: false));
            },
            borderRadius: BorderRadius.circular(26),
            child: Ink(
              width: 90,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.14) : Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: selected
                      ? color.withValues(alpha: 0.45)
                      : context.mood.outlineSoft,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_categoryIcon(id), color: color),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _shortLabel(label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w700,
                        ),
                  ),
                ],
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
    if (_myRooms.isEmpty) {
      return _buildMiniEmpty(
          'No saved rooms yet. Create one or join a live room.');
    }

    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _myRooms.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return InkWell(
              onTap: _openCreateRoom,
              borderRadius: BorderRadius.circular(26),
              child: Ink(
                width: 152,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: context.mood.loungeGradient,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.add_circle_outline_rounded, color: Colors.white),
                    Spacer(),
                    Text(
                      'Create room',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final room = _myRooms[index - 1];
          final accent = _categoryColor(room.type);
          return InkWell(
            onTap: () => _openRoom(room),
            borderRadius: BorderRadius.circular(26),
            child: Ink(
              width: 170,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: context.mood.outlineSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _pill(
                    room.type.toUpperCase(),
                    background: accent.withValues(alpha: 0.14),
                    foreground: AppColors.textPrimary,
                  ),
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
                    '${room.onlineCount} online',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
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
        'Try another search or category, or make the first move and create a room.',
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
            child: const Text('Create a room'),
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

  Widget _buildFeaturedBackdrop(RoomModel room, Color accent) {
    final coverImage = _normalizeImageUrl(room.coverImage);
    if (coverImage != null) {
      return Image.network(
        coverImage,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFeaturedFallback(accent, room.type),
      );
    }
    return _buildFeaturedFallback(accent, room.type);
  }

  Widget _buildFeaturedFallback(Color accent, String roomType) {
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
    final normalized = value?.trim();
    if (normalized == null ||
        normalized.isEmpty ||
        normalized.toLowerCase() == 'null') {
      return null;
    }
    return normalized;
  }

  Color _categoryColor(String id) {
    switch (id) {
      case 'music':
        return AppColors.accentBerry;
      case 'video':
        return AppColors.secondaryBlue;
      case 'chat':
        return AppColors.secondaryBlue;
      case 'battle':
      case 'auction':
        return AppColors.accentYellow;
      case 'all':
        return AppColors.primaryBlue;
      default:
        return AppColors.primaryBlue;
    }
  }

  IconData _categoryIcon(String id) {
    switch (id) {
      case 'music':
        return Icons.music_note_rounded;
      case 'video':
        return Icons.videocam_rounded;
      case 'chat':
        return Icons.chat_bubble_rounded;
      case 'battle':
        return Icons.flash_on_rounded;
      case 'auction':
        return Icons.sell_rounded;
      default:
        return Icons.mic_rounded;
    }
  }

  String _shortLabel(String label) {
    if (label.length <= 8) return label;
    return '${label.substring(0, 7)}…';
  }
}
