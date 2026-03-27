import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/ranking_service.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import '../../widgets/rounded_scaffold.dart';
import '../../widgets/user_avatar.dart';

class RankingsScreen extends StatefulWidget {
  const RankingsScreen({super.key});

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen>
    with TickerProviderStateMixin {
  // CHANGED: SingleTickerProvider â†’ TickerProviderStateMixin
  late TabController _mainTabController;
  late TabController _periodTabController;

  Map<String, dynamic> _giftRankings = {};
  Map<String, dynamic> _charmRankings = {};
  Map<String, dynamic> _werewolfRankings = {};
  Map<String, dynamic> _drawingRankings = {};
  Map<String, dynamic> _karaokeRankings = {};
  Map<String, dynamic> _unoRankings = {};
  Map<String, dynamic> _overallRankings = {};

  bool _isLoading = true;
  bool _isDisposed = false;
  String _selectedPeriod = 'alltime';
  int _selectedGameIndex = 0;

  final List<Map<String, dynamic>> _periods = [
    {'id': 'daily', 'name': 'Daily', 'icon': Icons.today},
    {'id': 'weekly', 'name': 'Weekly', 'icon': Icons.date_range},
    {'id': 'monthly', 'name': 'Monthly', 'icon': Icons.calendar_month},
    {'id': 'alltime', 'name': 'All Time', 'icon': Icons.history},
  ];

  final List<Map<String, dynamic>> _gameTabs = [
    {'id': 'werewolf', 'name': 'Werewolf', 'icon': 'ðŸº'},
    {'id': 'drawing', 'name': 'Drawing', 'icon': 'ðŸŽ¨'},
    {'id': 'karaoke', 'name': 'Karaoke', 'icon': 'ðŸŽ¤'},
    {'id': 'uno', 'name': 'UNO', 'icon': 'ðŸƒ'},
  ];

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 4, vsync: this);
    _periodTabController = TabController(length: 4, vsync: this);

    _mainTabController.addListener(_onMainTabChanged);
    _periodTabController.addListener(_onPeriodChanged);

    _loadAllRankings();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _mainTabController.removeListener(_onMainTabChanged);
    _periodTabController.removeListener(_onPeriodChanged);
    _mainTabController.dispose();
    _periodTabController.dispose();
    super.dispose();
  }

  void _onMainTabChanged() {
    if (!_isDisposed && mounted && !_mainTabController.indexIsChanging) {
      _loadRankingsForTab(_mainTabController.index);
    }
  }

  void _onPeriodChanged() {
    if (!_isDisposed && mounted && !_periodTabController.indexIsChanging) {
      setState(() {
        _selectedPeriod = _periods[_periodTabController.index]['id'];
      });
      _loadRankingsForTab(_mainTabController.index);
    }
  }

  Future<void> _loadAllRankings() async {
    if (_isDisposed) return;

    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _loadGiftRankings(),
        _loadCharmRankings(),
        _loadGameRankings('werewolf'),
        _loadGameRankings('drawing'),
        _loadGameRankings('karaoke'),
        _loadGameRankings('uno'),
        _loadOverallRankings(),
      ]);
    } catch (e) {
      debugPrint('Error loading rankings: $e');
    } finally {
      if (!_isDisposed && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadRankingsForTab(int index) async {
    if (_isDisposed) return;

    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      switch (index) {
        case 0: // Gifts
          await _loadGiftRankings();
          break;
        case 1: // Charm
          await _loadCharmRankings();
          break;
        case 2: // Games
          await _loadGameRankings(_gameTabs[_selectedGameIndex]['id']);
          break;
        case 3: // Overall
          await _loadOverallRankings();
          break;
      }
    } catch (e) {
      debugPrint('Error loading rankings for tab: $e');
    } finally {
      if (!_isDisposed && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadGiftRankings() async {
    if (_isDisposed) return;
    final data = await RankingService.getGiftRankings(
      period: _selectedPeriod,
      limit: 100,
    );
    if (!_isDisposed && mounted) {
      setState(() => _giftRankings = data);
    }
  }

  Future<void> _loadCharmRankings() async {
    if (_isDisposed) return;
    final data = await RankingService.getCharmRankings(
      period: _selectedPeriod,
      limit: 100,
    );
    if (!_isDisposed && mounted) {
      setState(() => _charmRankings = data);
    }
  }

  Future<void> _loadGameRankings(String gameType) async {
    if (_isDisposed) return;
    final data = await RankingService.getGameRankings(
      gameType,
      period: _selectedPeriod,
    );

    if (!_isDisposed && mounted) {
      setState(() {
        switch (gameType) {
          case 'werewolf':
            _werewolfRankings = data;
            break;
          case 'drawing':
            _drawingRankings = data;
            break;
          case 'karaoke':
            _karaokeRankings = data;
            break;
          case 'uno':
            _unoRankings = data;
            break;
        }
      });
    }
  }

  Future<void> _loadOverallRankings() async {
    if (_isDisposed) return;
    final data = await RankingService.getOverallRankings(limit: 100);
    if (!_isDisposed && mounted) {
      setState(() => _overallRankings = data);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposed) return const SizedBox.shrink();

    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.user?.id;

    return RoundedScaffold(
      title: 'Leaderboards',
      body: Column(
        children: [
          // Header tabs area (inside rounded body)
          Container(
            color: Colors.white,
            child: Column(
              children: [
                // Main category tabs
                TabBar(
                  controller: _mainTabController,
                  tabs: const [
                    Tab(text: 'Gifts'),
                    Tab(text: 'Charm'),
                    Tab(text: 'Games'),
                    Tab(text: 'Overall'),
                  ],
                  labelColor: AppColors.primaryBlue,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppColors.primaryBlue,
                  onTap: (index) {
                    setState(
                        () {}); // Ensure state updates for period tabs visibility
                  },
                ),

                // Period tabs (only for non-overall tabs)
                if (_mainTabController.index != 3)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: TabBar(
                      controller: _periodTabController,
                      isScrollable: true,
                      tabs: _periods
                          .map((p) => Tab(
                                text: p['name'],
                                icon: Icon(p['icon'], size: 16),
                              ))
                          .toList(),
                      labelColor: AppColors.primaryBlue,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: AppColors.primaryBlue,
                    ),
                  ),
                const Divider(height: 1),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : IndexedStack(
                    index: _mainTabController.index,
                    children: [
                      // Gifts tab
                      _buildRankingsList(
                        _giftRankings['rankings'] ?? [],
                        _giftRankings['userRank'],
                        currentUserId,
                        'gifts',
                      ),

                      // Charm tab
                      _buildRankingsList(
                        _charmRankings['rankings'] ?? [],
                        _charmRankings['userRank'],
                        currentUserId,
                        'charm',
                      ),

                      // Games tab
                      _buildGamesTab(currentUserId),

                      // Overall tab
                      _buildRankingsList(
                        _overallRankings['rankings'] ?? [],
                        null,
                        currentUserId,
                        'overall',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGamesTab(String? currentUserId) {
    return Column(
      children: [
        // Game selector chips
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _gameTabs.length,
            itemBuilder: (context, index) {
              final game = _gameTabs[index];
              final isSelected = _selectedGameIndex == index;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Row(
                    children: [
                      Text(game['icon']),
                      const SizedBox(width: 4),
                      Text(game['name']),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (!_isDisposed && mounted) {
                      setState(() {
                        _selectedGameIndex = index;
                        _isLoading = true;
                      });
                      _loadGameRankings(game['id']).then((_) {
                        if (!_isDisposed && mounted) {
                          setState(() => _isLoading = false);
                        }
                      });
                    }
                  },
                  backgroundColor: Colors.grey.shade100,
                  selectedColor: AppColors.primaryBlue.withValues(alpha: 0.1),
                  checkmarkColor: AppColors.primaryBlue,
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.primaryBlue : Colors.black87,
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),

        // Game rankings
        Expanded(
          child: _buildRankingsList(
            _getCurrentGameRankings(),
            _getCurrentGameUserRank(),
            currentUserId,
            'game',
          ),
        ),
      ],
    );
  }

  List<dynamic> _getCurrentGameRankings() {
    switch (_gameTabs[_selectedGameIndex]['id']) {
      case 'werewolf':
        return _werewolfRankings['rankings'] ?? [];
      case 'drawing':
        return _drawingRankings['rankings'] ?? [];
      case 'karaoke':
        return _karaokeRankings['rankings'] ?? [];
      case 'uno':
        return _unoRankings['rankings'] ?? [];
      default:
        return [];
    }
  }

  Map<String, dynamic>? _getCurrentGameUserRank() {
    switch (_gameTabs[_selectedGameIndex]['id']) {
      case 'werewolf':
        return _werewolfRankings['userRank'];
      case 'drawing':
        return _drawingRankings['userRank'];
      case 'karaoke':
        return _karaokeRankings['userRank'];
      case 'uno':
        return _unoRankings['userRank'];
      default:
        return null;
    }
  }

  Widget _buildRankingsList(
    List<dynamic> rankings,
    Map<String, dynamic>? userRank,
    String? currentUserId,
    String type,
  ) {
    if (_isDisposed) return const SizedBox.shrink();

    if (rankings.isEmpty) {
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
              'No rankings yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to top the leaderboard!',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // User's rank card (if available)
        if (userRank != null)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryBlue,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '#${userRank['rank']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Your Rank',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${userRank['score']} ${_getScoreLabel(type)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ],
            ),
          ),

        // Rankings list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rankings.length,
            itemBuilder: (context, index) {
              final rank = rankings[index];
              final isCurrentUser = rank['userId'] == currentUserId;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isCurrentUser
                      ? AppColors.primaryBlue.withValues(alpha: 0.1)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isCurrentUser
                        ? AppColors.primaryBlue
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    // Rank badge
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _getRankColor(index),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '#${rank['rank']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Avatar
                    UserAvatar(
                      imageUrl: rank['avatar'],
                      username: rank['username'] ?? '',
                      radius: 20,
                    ),
                    const SizedBox(width: 12),

                    // User info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                rank['username'] ?? 'Unknown',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if ((rank['vipLevel'] ?? 0) > 0) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.workspace_premium,
                                  size: 14,
                                  color: Colors.amber,
                                ),
                              ],
                            ],
                          ),
                          Text(
                            'Level ${rank['level'] ?? 1}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Score
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getScoreColor(type).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getScoreIcon(type),
                            size: 14,
                            color: _getScoreColor(type),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${rank['score']}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _getScoreColor(type),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getRankColor(int index) {
    switch (index) {
      case 0:
        return Colors.amber;
      case 1:
        return Colors.grey.shade400;
      case 2:
        return Colors.brown.shade400;
      default:
        return Colors.grey.shade300;
    }
  }

  String _getScoreLabel(String type) {
    switch (type) {
      case 'gifts':
        return 'gifts';
      case 'charm':
        return 'charm';
      case 'game':
        return 'wins';
      case 'overall':
        return 'pts';
      default:
        return 'pts';
    }
  }

  IconData _getScoreIcon(String type) {
    switch (type) {
      case 'gifts':
        return Icons.card_giftcard;
      case 'charm':
        return Icons.favorite;
      case 'game':
        return Icons.emoji_events;
      case 'overall':
        return Icons.stars;
      default:
        return Icons.stars;
    }
  }

  Color _getScoreColor(String type) {
    switch (type) {
      case 'gifts':
        return Colors.amber;
      case 'charm':
        return Colors.pink;
      case 'game':
        return Colors.blue;
      case 'overall':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}






