import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/room_model.dart';
import '../../services/room_service.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/room_card.dart';
import 'create_room_screen.dart';
import 'room_detail_screen.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  List<RoomModel> _rooms = [];
  List<Map<String, dynamic>> _categories = [];
  String _selectedCategory = 'all';
  String _selectedSort = 'trending';
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  final TextEditingController _searchController = TextEditingController();
  List<RoomModel> _myRooms = [];
  bool _isLoadingMyRooms = true;
  int _activeRequestId = 0;
  bool _isDisposed = false;
  Timer? _searchDebounce;
  Timer? _realtimeRefreshDebounce;
  StreamSubscription<Map<String, dynamic>>? _roomRealtimeSubscription;
  StreamSubscription<Map<String, dynamic>>? _socketResyncSubscription;

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _subscribeToRealtime();
    _loadCategories();
    _loadMyRooms();
    _loadRooms();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _searchDebounce?.cancel();
    _realtimeRefreshDebounce?.cancel();
    _roomRealtimeSubscription?.cancel();
    _socketResyncSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _subscribeToRealtime() {
    _roomRealtimeSubscription = SocketService.roomUpdateStream.listen((data) {
      if (_isDisposed || !mounted) return;

      final eventType = data['_eventType']?.toString();
      final shouldRefresh = {
        'room_created',
        'room_deleted',
        'lobby_update',
        'room_updated',
      }.contains(eventType);

      if (!shouldRefresh) return;

      _realtimeRefreshDebounce?.cancel();
      _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 600), () {
        _refreshRooms();
      });
    });

    _socketResyncSubscription = SocketService.resyncStream.listen((_) {
      _realtimeRefreshDebounce?.cancel();
      _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 500), () {
        _refreshRooms();
      });
    });
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!_isDisposed && mounted) {
        _loadRooms(reset: true);
      }
    });
  }

  String get _backendSort {
    switch (_selectedSort) {
      case 'newest':
        return 'newest';
      case 'online':
      case 'trending':
      default:
        return 'onlineCount';
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await RoomService.getCategories();
      if (!_isDisposed && mounted) {
        _safeSetState(() {
          _categories = categories;
        });
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }

  Future<void> _loadMyRooms() async {
    _safeSetState(() => _isLoadingMyRooms = true);
    try {
      final rooms = await RoomService.getMyRooms();
      if (!_isDisposed && mounted) {
        _safeSetState(() {
          _myRooms = rooms;
          _isLoadingMyRooms = false;
        });
      }
    } catch (_) {
      _safeSetState(() => _isLoadingMyRooms = false);
    }
  }

  Future<void> _loadRooms({bool reset = false}) async {
    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      _activeRequestId++;
      _safeSetState(() {
        _rooms = [];
        _isLoading = true;
        _isLoadingMore = false;
      });
    }

    if (!_hasMore || (_currentPage > 1 && _isLoadingMore)) return;

    final requestId = _activeRequestId;

    if (_currentPage > 1) {
      _safeSetState(() => _isLoadingMore = true);
    } else if (!reset) {
      _safeSetState(() => _isLoading = true);
    }

    try {
      final rooms = await RoomService.getRooms(
        category: _selectedCategory,
        search:
            _searchController.text.isNotEmpty ? _searchController.text : null,
        sort: _backendSort,
        page: _currentPage,
      );

      if (!_isDisposed && mounted && requestId == _activeRequestId) {
        _safeSetState(() {
          if (_currentPage == 1) {
            _rooms = rooms;
          } else {
            _rooms.addAll(rooms);
          }

          _hasMore = rooms.length == 20;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (!_isDisposed && mounted && requestId == _activeRequestId) {
        _safeSetState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onCategoryChanged(String category) {
    if (_selectedCategory == category) return;
    setState(() {
      _selectedCategory = category;
    });
    _loadRooms(reset: true);
  }

  void _onSortChanged(String? value) {
    if (value != null && _selectedSort != value) {
      setState(() {
        _selectedSort = value;
      });
      _loadRooms(reset: true);
    }
  }

  Future<void> _refreshRooms() async {
    await Future.wait([
      _loadCategories(),
      _loadMyRooms(),
      _loadRooms(reset: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(gradient: mood.shellGradient),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshRooms,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Rooms',
                              style: theme.textTheme.headlineMedium),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _buildHero(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _buildSearchBar(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _buildInfoRow(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final category = _categories[index];
                          final selected = _selectedCategory == category['id'];
                          return ChoiceChip(
                            label: Text(category['name'] ?? ''),
                            selected: selected,
                            onSelected: (_) =>
                                _onCategoryChanged(category['id']),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                    child: _sectionHeader(
                      'Your rooms',
                      'Quick jump back into your familiar corners.',
                      actionLabel: 'Create',
                      onAction: _openCreateRoom,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _buildMyRoomsStrip(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                    child: _sectionHeader(
                      'Popular now',
                      'Fresh rooms with the most energy.',
                    ),
                  ),
                ),
                if (_isLoading && _rooms.isEmpty)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_rooms.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      child: _buildEmptyState(),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index == _rooms.length) {
                            if (!_isLoadingMore && _hasMore) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _currentPage++;
                                _loadRooms();
                              });
                            }
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          return RoomCard(room: _rooms[index]);
                        },
                        childCount: _rooms.length + (_hasMore ? 1 : 0),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: context.mood.loungeGradient,
        boxShadow: [
          BoxShadow(
            color: context.mood.shadow,
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Find the right room fast',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'From chill voice spaces to louder party rooms, this list is built for quick discovery.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.84),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _heroMetric('Live rooms', '${_rooms.length}')),
              const SizedBox(width: 10),
              Expanded(child: _heroMetric('My rooms', '${_myRooms.length}')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroMetric(String label, String value) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
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

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      decoration: const InputDecoration(
        hintText: 'Search rooms or room UID',
        prefixIcon: Icon(Icons.search_rounded),
      ),
    );
  }

  Widget _buildInfoRow() {
    return Row(
      children: [
        Expanded(
          child: _buildInfoChip(
            label: 'Live rooms',
            value: '${_rooms.length}',
            icon: Icons.graphic_eq_rounded,
            color: AppColors.primaryBlue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildInfoChip(
            label: 'My rooms',
            value: '${_myRooms.length}',
            icon: Icons.favorite_rounded,
            color: AppColors.secondaryBlue,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.mood.outlineSoft),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedSort,
              items: const [
                DropdownMenuItem(value: 'trending', child: Text('Trending')),
                DropdownMenuItem(value: 'newest', child: Text('Newest')),
                DropdownMenuItem(value: 'online', child: Text('Most online')),
              ],
              onChanged: _onSortChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
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

  Widget _sectionHeader(
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

  Widget _buildMyRoomsStrip() {
    if (_isLoadingMyRooms) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _myRooms.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return InkWell(
              onTap: _openCreateRoom,
              borderRadius: BorderRadius.circular(28),
              child: Ink(
                width: 156,
                decoration: BoxDecoration(
                  gradient: context.mood.heroGradient,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.add_circle_outline_rounded,
                          color: Colors.white),
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
              ),
            );
          }

          final room = _myRooms[index - 1];
          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => RoomDetailScreen(room: room)),
              );
            },
            borderRadius: BorderRadius.circular(28),
            child: Ink(
              width: 170,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: context.mood.outlineSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const Spacer(),
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

  Widget _buildEmptyState() {
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
          const Icon(
            Icons.weekend_rounded,
            color: AppColors.primaryBlue,
            size: 34,
          ),
          const SizedBox(height: 16),
          Text('No rooms found', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Try another search or category, or make the first move and create a room.',
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

  void _openCreateRoom() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateRoomScreen()),
    ).then((created) {
      if (created == true) _refreshRooms();
    });
  }
}
