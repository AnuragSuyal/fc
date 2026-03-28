import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/room_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../services/room_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../utils/constants.dart';
import '../widgets/app_search_icon.dart';
import '../widgets/currency_icon.dart';
import '../widgets/user_avatar.dart';
import 'explore/explore_screen.dart';
import 'games/games_screen.dart';
import 'home/home_screen.dart';
import 'profile/enhanced_profile_screen.dart';
import 'profile/me_screen.dart';
import 'rooms/room_detail_screen.dart';
import 'social/social_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final _homeSearchController = TextEditingController();
  final _homeSearchFocusNode = FocusNode();
  List<RoomModel> _homeSearchRooms = const [];
  List<UserModel> _homeSearchUsers = const [];
  Timer? _homeSearchDebounce;
  int _homeSearchRequestId = 0;
  bool _isHomeSearchLoading = false;

  final List<_NavItem> _navItems = const [
    _NavItem(
      label: 'Home',
      icon: Icons.cottage_rounded,
      selectedAssetPath: 'assets/images/nav_home_active.png',
    ),
    _NavItem(
      label: 'Discover',
      icon: Icons.travel_explore_rounded,
      selectedAssetPath: 'assets/images/nav_discover_active.png',
    ),
    _NavItem(
      label: 'Games',
      icon: Icons.sports_esports_rounded,
      selectedAssetPath: 'assets/images/nav_games_active.png',
    ),
    _NavItem(
      label: 'Circle',
      icon: Icons.groups_rounded,
      selectedAssetPath: 'assets/images/nav_circle_active.png',
    ),
    _NavItem(
      label: 'Me',
      icon: Icons.face_retouching_natural_rounded,
      selectedAssetPath: 'assets/images/nav_me_active.png',
    ),
  ];

  bool get _showHeader => _selectedIndex == 0 || _selectedIndex == 2;
  String get _homeSearchQuery => _homeSearchController.text.trim();
  bool get _showHomeSearchResults =>
      _selectedIndex == 0 && _homeSearchQuery.isNotEmpty;

  @override
  void dispose() {
    _homeSearchDebounce?.cancel();
    _homeSearchController.dispose();
    _homeSearchFocusNode.dispose();
    super.dispose();
  }

  void _openExploreSearch() {
    setState(() => _selectedIndex = 1);
  }

  void _selectTab(int index) {
    FocusScope.of(context).unfocus();
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  void _handleHomeSearchChanged(String value) {
    final query = value.trim();
    _homeSearchDebounce?.cancel();

    if (query.isEmpty) {
      _homeSearchRequestId++;
      setState(() {
        _isHomeSearchLoading = false;
        _homeSearchRooms = const [];
        _homeSearchUsers = const [];
      });
      return;
    }

    setState(() => _isHomeSearchLoading = true);
    _homeSearchDebounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_runHomeSearch(query));
    });
  }

  Future<void> _runHomeSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final requestId = ++_homeSearchRequestId;
    final results = await Future.wait([
      RoomService.getRooms(
        search: trimmed,
        sort: 'onlineCount',
        limit: 8,
      ),
      UserService.searchUsers(trimmed, limit: 8),
    ]);

    if (!mounted ||
        requestId != _homeSearchRequestId ||
        trimmed != _homeSearchQuery) {
      return;
    }

    setState(() {
      _homeSearchRooms = results[0] as List<RoomModel>;
      _homeSearchUsers = results[1] as List<UserModel>;
      _isHomeSearchLoading = false;
    });
  }

  void _clearHomeSearch() {
    _homeSearchDebounce?.cancel();
    _homeSearchRequestId++;
    _homeSearchController.clear();
    setState(() {
      _isHomeSearchLoading = false;
      _homeSearchRooms = const [];
      _homeSearchUsers = const [];
    });
  }

  void _openHomeUserProfile(UserModel user) {
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EnhancedProfileScreen(userId: user.id),
      ),
    );
  }

  void _openHomeRoom(RoomModel room) {
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;
    final circleBadgeCount = context.select<AuthProvider, int>(
      (auth) => auth.pendingFriendRequests,
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(gradient: mood.shellGradient),
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Positioned(
                top: -40,
                right: -10,
                child: _Orb(color: mood.sun.withValues(alpha: 0.24), size: 156),
              ),
              Positioned(
                top: 130,
                left: -42,
                child: _Orb(color: mood.sky.withValues(alpha: 0.18), size: 122),
              ),
              Column(
                children: [
                  if (_showHeader)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _buildTopHeader(context),
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        _showHeader ? 16 : 8,
                        14,
                        94,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(36),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface
                                .withValues(alpha: 0.9),
                            border: Border.all(color: mood.outlineSoft),
                            boxShadow: [
                              BoxShadow(
                                color: mood.shadow,
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: IndexedStack(
                            index: _selectedIndex,
                            children: [
                              Stack(
                                children: [
                                  const HomeScreen(),
                                  if (_showHomeSearchResults)
                                    Positioned.fill(
                                      child: _buildHomeSearchResults(context),
                                    ),
                                ],
                              ),
                              const ExploreScreen(),
                              const GamesScreen(),
                              const SocialScreen(),
                              const MeScreen(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildBottomNav(
                  context,
                  circleBadgeCount: circleBadgeCount,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;
    final showHeaderCopy = _selectedIndex == 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: showHeaderCopy
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            if (showHeaderCopy) ...[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pick a game night',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Party games, quick laughs, and lobbies with your people.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF4B5563),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
            Consumer<AuthProvider>(
              builder: (context, authProvider, _) {
                final profileButton = PopupMenuButton<String>(
                  offset: const Offset(0, 46),
                  color: theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  onSelected: (value) async {
                    if (value == 'logout') {
                      await authProvider.logout();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, '/login');
                      }
                    } else if (value == 'settings') {
                      Navigator.pushNamed(context, '/settings');
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'settings',
                      child: Text('Settings'),
                    ),
                    PopupMenuItem(
                      value: 'logout',
                      child: Text('Logout'),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.32),
                      ),
                    ),
                    child: UserAvatar(
                      imageUrl: authProvider.user?.avatar,
                      radius: 20,
                      username: authProvider.user?.username ?? '?',
                    ),
                  ),
                );

                if (showHeaderCopy) {
                  return profileButton;
                }

                return Expanded(
                  child: Row(
                    children: [
                      profileButton,
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildHeaderWalletStrip(
                          context,
                          coins: authProvider.user?.coins ?? 0,
                          gems: authProvider.user?.gems ?? 0,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _selectedIndex == 0
                  ? _buildHomeSearchField(context)
                  : InkWell(
                      onTap: _openExploreSearch,
                      borderRadius: BorderRadius.circular(26),
                      child: Container(
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: mood.outlineSoft),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          children: [
                            const AppSearchIcon(size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Search games, party tables, hosts',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                            Icon(
                              Icons.tune_rounded,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.55),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHomeSearchField(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;
    final hasQuery = _homeSearchController.text.isNotEmpty;

    return TextField(
      controller: _homeSearchController,
      focusNode: _homeSearchFocusNode,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: _handleHomeSearchChanged,
      onSubmitted: (_) {
        _homeSearchDebounce?.cancel();
        unawaited(_runHomeSearch(_homeSearchQuery));
      },
      decoration: InputDecoration(
        hintText: 'Search user UID, room UID, hosts',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
        ),
        prefixIcon: const AppSearchIcon(size: 18),
        suffixIcon: _isHomeSearchLoading
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              )
            : hasQuery
                ? IconButton(
                    onPressed: _clearHomeSearch,
                    icon: Icon(
                      Icons.close_rounded,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    tooltip: 'Clear search',
                  )
                : Icon(
                    Icons.tune_rounded,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.95),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(color: mood.outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(color: mood.outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.32),
            width: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildHomeSearchResults(BuildContext context) {
    final theme = Theme.of(context);
    final hasMatches =
        _homeSearchUsers.isNotEmpty || _homeSearchRooms.isNotEmpty;
    final totalMatches = _homeSearchUsers.length + _homeSearchRooms.length;

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        physics: const BouncingScrollPhysics(),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.mood.outlineSoft),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const AppSearchIcon(size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Results for "$_homeSearchQuery"',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isHomeSearchLoading
                            ? 'Searching rooms and people in real time.'
                            : totalMatches == 0
                                ? 'No matches yet. Try a room UID, user UID, or host name.'
                                : '$totalMatches match${totalMatches == 1 ? '' : 'es'} found right now.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_isHomeSearchLoading && !hasMatches)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!hasMatches)
            _buildHomeSearchEmptyState(context)
          else ...[
            if (_homeSearchUsers.isNotEmpty) ...[
              _buildSearchSectionHeader(
                context,
                icon: Icons.person_search_rounded,
                title: 'People',
                subtitle: 'Matching user UIDs and host profiles',
              ),
              const SizedBox(height: 12),
              ..._homeSearchUsers.map(
                (user) => _buildHomeUserResultTile(context, user),
              ),
              const SizedBox(height: 8),
            ],
            if (_homeSearchRooms.isNotEmpty) ...[
              _buildSearchSectionHeader(
                context,
                icon: Icons.meeting_room_rounded,
                title: 'Rooms',
                subtitle: 'Live rooms that match the current search',
              ),
              const SizedBox(height: 12),
              ..._homeSearchRooms.map(
                (room) => _buildHomeRoomResultTile(context, room),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSearchSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textPrimary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHomeUserResultTile(BuildContext context, UserModel user) {
    final theme = Theme.of(context);
    final mood = context.mood;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openHomeUserProfile(user),
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: mood.outlineSoft),
          ),
          child: Row(
            children: [
              UserAvatar(
                imageUrl: user.avatar,
                radius: 24,
                username: user.username,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'UID ${user.uid}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.isOnline ? 'Online now' : user.region,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: user.isOnline
                            ? AppColors.successGreen
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeRoomResultTile(BuildContext context, RoomModel room) {
    final theme = Theme.of(context);
    final mood = context.mood;
    final accent = _roomAccent(room.type);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openHomeRoom(room),
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: mood.outlineSoft),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  _roomTypeIcon(room.type),
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Room UID ${room.roomId}  •  Host ${room.hostName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (room.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        room.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildRoomMetaPill(
                          context,
                          label: '${room.onlineCount} online',
                          icon: Icons.sensors_rounded,
                          color: AppColors.successGreen,
                        ),
                        _buildRoomMetaPill(
                          context,
                          label:
                              '${room.participantCount}/${room.maxParticipants}',
                          icon: Icons.people_outline_rounded,
                          color: AppColors.textPrimary,
                        ),
                        if (room.isPrivate)
                          _buildRoomMetaPill(
                            context,
                            label: 'Private',
                            icon: Icons.lock_rounded,
                            color: AppColors.warningOrange,
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
  }

  Widget _buildRoomMetaPill(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeSearchEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: mood.outlineSoft),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.manage_search_rounded,
              size: 30,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nothing matched yet',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different user UID, room UID, or the host name you want to find.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  IconData _roomTypeIcon(String type) {
    switch (type) {
      case 'music':
        return Icons.music_note_rounded;
      case 'video':
        return Icons.videocam_rounded;
      case 'game':
        return Icons.sports_esports_rounded;
      case 'chat':
        return Icons.chat_bubble_rounded;
      default:
        return Icons.mic_rounded;
    }
  }

  Color _roomAccent(String type) {
    switch (type) {
      case 'music':
        return const Color(0xFF7C3AED);
      case 'video':
        return const Color(0xFF2563EB);
      case 'game':
        return const Color(0xFFF97316);
      case 'chat':
        return const Color(0xFF10B981);
      default:
        return AppColors.primaryBlue;
    }
  }

  Widget _buildHeaderWalletStrip(
    BuildContext context, {
    required int coins,
    required int gems,
  }) {
    final mood = context.mood;

    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/wallet'),
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: mood.outlineSoft),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildHeaderBalanceMetric(
                context,
                icon: const CurrencyIcon.coins(size: 20),
                label: 'Coins',
                value: '$coins',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildHeaderBalanceMetric(
                context,
                icon: const CurrencyIcon.gems(size: 20),
                label: 'Diamonds',
                value: '$gems',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBalanceMetric(
    BuildContext context, {
    required Widget icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final mood = context.mood;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: mood.outlineSoft),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF1F2937),
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

  Widget _buildBottomNav(
    BuildContext context, {
    required int circleBadgeCount,
  }) {
    final theme = Theme.of(context);
    final mood = context.mood;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: mood.outlineSoft),
        boxShadow: [
          BoxShadow(
            color: mood.shadow,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: List.generate(_navItems.length, (index) {
          final item = _navItems[index];
          final selected = index == _selectedIndex;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _selectTab(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? theme.colorScheme.onSurface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : const [],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: selected
                                ? Image.asset(
                                    item.selectedAssetPath,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  )
                                : Icon(
                                    item.icon,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.56),
                                    size: 20,
                                  ),
                          ),
                          if (index == 3 && circleBadgeCount > 0)
                            Positioned(
                              right: -10,
                              top: -8,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: selected
                                        ? theme.colorScheme.onSurface
                                        : theme.colorScheme.surface,
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  circleBadgeCount > 99
                                      ? '99+'
                                      : '$circleBadgeCount',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: selected
                                      ? theme.colorScheme.surface
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.64),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedAssetPath,
  });

  final String label;
  final IconData icon;
  final String selectedAssetPath;
}

class _Orb extends StatelessWidget {
  const _Orb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}
