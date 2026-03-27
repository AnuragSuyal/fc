import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/profile_service.dart';
import '../../services/economy_service.dart';
import '../../models/user_model.dart';
import '../../models/post_model.dart';
import '../../models/stats_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/post_card.dart';
import '../../utils/constants.dart';
import '../../widgets/user_avatar.dart';

class EnhancedProfileScreen extends StatefulWidget {
  final String? userId;

  const EnhancedProfileScreen({super.key, this.userId});

  @override
  State<EnhancedProfileScreen> createState() => _EnhancedProfileScreenState();
}

class _EnhancedProfileScreenState extends State<EnhancedProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  UserModel? _user;
  StatsModel? _stats;
  List<PostModel> _posts = [];
  List<dynamic> _badges = [];
  Map<String, dynamic> _gameStats = {};
  List<dynamic> _visitors = [];
  int _visitorTotal = 0;
  bool _isLoading = true;
  bool _isOwner = false;
  bool _isDisposed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadProfile();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _tabController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  Future<void> _loadProfile() async {
    _safeSetState(() => _isLoading = true);

    final targetUserId = widget.userId ??
        Provider.of<AuthProvider>(context, listen: false).user?.id;

    if (targetUserId == null) {
      _safeSetState(() => _isLoading = false);
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isOwner = authProvider.user?.id == targetUserId;

    try {
      final futures = <Future<dynamic>>[
        widget.userId == null
            ? ProfileService.getMyProfile()
            : ProfileService.getProfile(targetUserId),
        if (isOwner) EconomyService.getUserStats(),
      ];

      final results = await Future.wait<dynamic>(futures);

      if (!mounted) return;

      final data = results[0] as Map<String, dynamic>;
      final userJson = data['user'];
      final loadedUser = userJson is Map<String, dynamic>
          ? UserModel.fromJson(userJson)
          : authProvider.user;
      final statsData = isOwner && results.length > 1
          ? results[1] as Map<String, dynamic>
          : null;

      _safeSetState(() {
        _user = loadedUser;
        _posts = (data['posts'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PostModel.fromJson)
            .toList();
        _badges = _user?.badges ?? [];
        _gameStats = _user?.gameStats ?? {};
        _isOwner = isOwner;
        _stats = statsData != null && statsData.isNotEmpty
            ? StatsModel.fromJson(statsData)
            : null;
        _errorMessage = _user == null ? 'User not found' : null;
        _isLoading = false;
      });

      if (!isOwner) {
        await ProfileService.addVisit(targetUserId);
      }

      if (isOwner) {
        _loadVisitors();
      }
    } catch (_) {
      _safeSetState(() {
        _errorMessage = 'Could not load profile';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadVisitors() async {
    if (_user == null) return;

    final visitorsData = await ProfileService.getVisitors(_user!.id);

    if (!mounted) return;

    _safeSetState(() {
      _visitors = visitorsData['visitors'] ?? [];
      _visitorTotal = visitorsData['total'] ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_user == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(_errorMessage ?? 'User not found'),
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return [
            // Cover Photo
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              actions: [
                if (_isOwner)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.menu, color: Colors.white),
                    onSelected: (value) {
                      Navigator.pushNamed(context, value);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                          value: '/wallet', child: Text('Wallet')),
                      const PopupMenuItem(
                          value: '/vip', child: Text('VIP Center')),
                      const PopupMenuItem(
                          value: '/daily-rewards',
                          child: Text('Daily Rewards')),
                      const PopupMenuItem(
                          value: '/quests', child: Text('Quests')),
                      const PopupMenuItem(
                          value: '/gifts/shop', child: Text('Gift Shop')),
                      const PopupMenuItem(
                          value: '/rankings', child: Text('Leaderboards')),
                      const PopupMenuItem(
                          value: '/settings', child: Text('Settings')),
                    ],
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Cover image
                    (_user!.coverPhoto?.isNotEmpty ?? false)
                        ? Image.network(
                            _user!.coverPhoto!.contains('http')
                                ? _user!.coverPhoto!
                                : '${ApiService.baseUrl}/uploads/${_user!.coverPhoto}',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.3),
                            ),
                          )
                        : Container(
                            color: AppColors.primaryBlue.withValues(alpha: 0.3),
                          ),

                    // Dark overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    ),

                    // Profile info overlay
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Row(
                        children: [
                          // Avatar
                          UserAvatar(
                            imageUrl: _user!.avatar.isEmpty
                                ? null
                                : (_user!.avatar.contains('http')
                                    ? _user!.avatar
                                    : '${ApiService.baseUrl}/uploads/${_user!.avatar}'),
                            username: _user!.username,
                            radius: 40,
                            fontSize: 32,
                          ),
                          const SizedBox(width: 16),

                          // Username, level, XP bar
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _user!.username,
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (_isOwner) _buildBalanceRow(),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                if (_user!.uid.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'UID ${_user!.uid}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Level ${_stats?.level ?? _user!.level}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (_user!.vipLevel > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'VIP ${_user!.vipLevel}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                // â”€â”€ Real-time XP progress bar â”€â”€
                                if (_isOwner) ...[
                                  const SizedBox(height: 8),
                                  _buildXpBar(),
                                ],
                              ],
                            ),
                          ),

                          // Edit button (if own profile)
                          if (_isOwner)
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.white),
                              onPressed: () {
                                Navigator.pushNamed(
                                    context, '/settings/account');
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Stats bar
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.1),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                      'Games',
                      '${_user!.stats['totalGames'] ?? 0}',
                      Icons.games,
                    ),
                    _buildStatItem(
                      'Wins',
                      '${_user!.stats['totalWins'] ?? 0}',
                      Icons.emoji_events,
                    ),
                    _buildStatItem(
                      'Win Rate',
                      '${_user!.stats['winRate'] ?? 0}%',
                      Icons.trending_up,
                    ),
                    _buildStatItem(
                      'Visitors',
                      '${_user!.stats['visitorCount'] ?? 0}',
                      Icons.people,
                    ),
                  ],
                ),
              ),
            ),

            // Bio
            if (_user!.bio?.isNotEmpty == true)
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _user!.bio ?? '',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),

            // Tabs
            SliverToBoxAdapter(
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Posts'),
                  Tab(text: 'Badges'),
                  Tab(text: 'Stats'),
                  Tab(text: 'Visitors'),
                ],
                labelColor: AppColors.primaryBlue,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AppColors.primaryBlue,
              ),
            ),
          ];
        },
        // Tab content
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildPostsTab(),
            _buildBadgesTab(),
            _buildStatsTab(),
            _buildVisitorsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primaryBlue, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceRow() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final coins = authProvider.user?.coins ?? _stats?.coins ?? 0;
        final gems = authProvider.user?.gems ?? _stats?.gems ?? 0;

        return RepaintBoundary(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monetization_on, size: 14, color: Colors.amber),
              const SizedBox(width: 2),
              Text(
                '$coins',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.diamond, size: 14, color: Color(0xFFAA66FF)),
              const SizedBox(width: 2),
              Text(
                '$gems',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildXpBar() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final xp = authProvider.user?.xp ?? _stats?.xp ?? 0;
        final nextLevelXp =
            _stats?.nextLevelXp ?? ((authProvider.user?.level ?? 1) * 1000);
        final progress =
            nextLevelXp > 0 ? (xp / nextLevelXp).clamp(0.0, 1.0) : 0.0;

        return RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'XP: $xp',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    'Next: $nextLevelXp',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPostsTab() {
    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.post_add,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No posts yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
            if (_isOwner) ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, '/posts/create');
                },
                icon: const Icon(Icons.add),
                label: const Text('Create Post'),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        return PostCard(
          post: _posts[index],
          showActions: _isOwner,
        );
      },
    );
  }

  Widget _buildBadgesTab() {
    if (_badges.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No badges yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.9,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _badges.length,
      itemBuilder: (context, index) {
        final badge = _badges[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BadgeDetailScreen(badge: badge),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: _getRarityColor(badge['rarity']).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _getRarityColor(badge['rarity']).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  badge['icon'] ?? 'ðŸ…',
                  style: const TextStyle(fontSize: 32),
                ),
                const SizedBox(height: 8),
                Text(
                  badge['name'] ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsTab() {
    if (_gameStats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No game stats yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_gameStats['werewolf'] != null)
          _buildGameStatCard(
            'Werewolf',
            _gameStats['werewolf'],
            Icons.whatshot,
          ),
        if (_gameStats['drawing'] != null)
          _buildGameStatCard(
            'Drawing',
            _gameStats['drawing'],
            Icons.brush,
          ),
        if (_gameStats['karaoke'] != null)
          _buildGameStatCard(
            'Karaoke',
            _gameStats['karaoke'],
            Icons.mic,
          ),
        if (_gameStats['uno'] != null)
          _buildGameStatCard(
            'UNO',
            _gameStats['uno'],
            Icons.style,
          ),
      ],
    );
  }

  Widget _buildGameStatCard(
      String title, Map<String, dynamic> stats, IconData icon) {
    final played = stats['played'] ?? 0;
    final won = stats['won'] ?? 0;
    final winRate = played > 0 ? (won / played * 100).toInt() : 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primaryBlue),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Level ${stats['level'] ?? 1}',
                    style: const TextStyle(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatChip('Played', '$played', Icons.games),
                _buildStatChip('Won', '$won', Icons.emoji_events),
                _buildStatChip('Win Rate', '$winRate%', Icons.trending_up),
              ],
            ),
            if (stats['speed'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.speed, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('Speed: ${stats['speed']}'),
                ],
              ),
            ],
            if (stats['logic'] != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.psychology, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('Logic: ${stats['logic']}'),
                ],
              ),
            ],
            if (stats['pitch'] != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.music_note, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('Pitch: ${stats['pitch']}'),
                ],
              ),
            ],
            if (stats['strategy'] != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.lightbulb, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('Strategy: ${stats['strategy']}'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade700),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildVisitorsTab() {
    if (!_isOwner) {
      return const Center(
        child: Text('Visitors only visible to profile owner'),
      );
    }

    if (_visitors.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No visitors yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'Total Visitors: $_visitorTotal',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/visitors',
                      arguments: _visitors);
                },
                child: const Text('View All'),
              ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _visitors.length > 5 ? 5 : _visitors.length,
          itemBuilder: (context, index) {
            final visitor = _visitors[index];
            final user = visitor['userId'] is Map
                ? visitor['userId'] as Map<String, dynamic>
                : null;
            final username = user?['username'] ?? 'Unknown';
            final avatar = user?['avatar'] ?? '';
            final level = user?['level'] ?? 1;
            final time = visitor['visitedAt'] != null
                ? DateTime.parse(visitor['visitedAt'])
                : DateTime.now();
            final message = visitor['message'];

            return ListTile(
              leading: UserAvatar(
                imageUrl: avatar.isEmpty
                    ? null
                    : (avatar.contains('http')
                        ? avatar
                        : '${ApiService.baseUrl}/uploads/$avatar'),
                username: username,
                radius: 20,
              ),
              title: Text(username),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Level $level'),
                  if (message != null)
                    Text(
                      '"$message"',
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              trailing: Text(_timeAgo(time)),
              onTap: () {
                Navigator.pushNamed(context, '/profile/${user?['_id'] ?? ''}');
              },
            );
          },
        ),
      ],
    );
  }

  Color _getRarityColor(String? rarity) {
    switch (rarity) {
      case 'common':
        return Colors.grey;
      case 'rare':
        return Colors.blue;
      case 'epic':
        return Colors.purple;
      case 'legendary':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

class BadgeDetailScreen extends StatelessWidget {
  final Map<String, dynamic> badge;

  const BadgeDetailScreen({super.key, required this.badge});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Badge Details'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color:
                      _getRarityColor(badge['rarity']).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    badge['icon'] ?? 'ðŸ…',
                    style: const TextStyle(fontSize: 60),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                badge['name'] ?? '',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:
                      _getRarityColor(badge['rarity']).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge['rarity']?.toUpperCase() ?? '',
                  style: TextStyle(
                    color: _getRarityColor(badge['rarity']),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                badge['description'] ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Earned: ${_formatDate(badge['earnedAt'])}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getRarityColor(String? rarity) {
    switch (rarity) {
      case 'common':
        return Colors.grey;
      case 'rare':
        return Colors.blue;
      case 'epic':
        return Colors.purple;
      case 'legendary':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }
}
