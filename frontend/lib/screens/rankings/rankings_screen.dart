import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/ranking_service.dart';
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
  late final TabController _mainTabController;
  late final TabController _periodTabController;

  Map<String, dynamic> _giftRankings = <String, dynamic>{};
  Map<String, dynamic> _charmRankings = <String, dynamic>{};
  Map<String, dynamic> _werewolfRankings = <String, dynamic>{};
  Map<String, dynamic> _drawingRankings = <String, dynamic>{};
  Map<String, dynamic> _karaokeRankings = <String, dynamic>{};
  Map<String, dynamic> _colorClashRankings = <String, dynamic>{};
  Map<String, dynamic> _overallRankings = <String, dynamic>{};

  bool _isLoading = true;
  bool _isDisposed = false;
  String _selectedPeriod = 'alltime';
  int _selectedGameIndex = 0;

  final List<Map<String, dynamic>> _periods = const [
    {'id': 'daily', 'name': 'Daily', 'icon': Icons.today},
    {'id': 'weekly', 'name': 'Weekly', 'icon': Icons.date_range},
    {'id': 'monthly', 'name': 'Monthly', 'icon': Icons.calendar_month},
    {'id': 'alltime', 'name': 'All Time', 'icon': Icons.history},
  ];

  final List<Map<String, dynamic>> _gameTabs = const [
    {'id': 'werewolf', 'name': 'Werewolf', 'icon': Icons.pets_rounded},
    {'id': 'drawing', 'name': 'Drawing', 'icon': Icons.brush_rounded},
    {'id': 'karaoke', 'name': 'Karaoke', 'icon': Icons.mic_rounded},
    {
      'id': 'color_clash',
      'name': 'Color Clash',
      'icon': Icons.auto_awesome_rounded,
    },
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
    if (_isDisposed || !mounted || _mainTabController.indexIsChanging) {
      return;
    }
    _loadRankingsForTab(_mainTabController.index);
  }

  void _onPeriodChanged() {
    if (_isDisposed || !mounted || _periodTabController.indexIsChanging) {
      return;
    }
    setState(() {
      _selectedPeriod =
          _periods[_periodTabController.index]['id'].toString();
    });
    _loadRankingsForTab(_mainTabController.index);
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
        _loadGameRankings('color_clash'),
        _loadOverallRankings(),
      ]);
    } catch (error) {
      debugPrint('Error loading rankings: $error');
    } finally {
      if (!_isDisposed && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadRankingsForTab(int index) async {
    if (_isDisposed || !mounted) return;

    setState(() => _isLoading = true);
    try {
      switch (index) {
        case 0:
          await _loadGiftRankings();
          break;
        case 1:
          await _loadCharmRankings();
          break;
        case 2:
          await _loadGameRankings(_currentGameId);
          break;
        case 3:
          await _loadOverallRankings();
          break;
      }
    } catch (error) {
      debugPrint('Error loading rankings for tab: $error');
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
          case 'color_clash':
            _colorClashRankings = data;
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

  String get _currentGameId =>
      _gameTabs[_selectedGameIndex]['id'].toString();

  @override
  Widget build(BuildContext context) {
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    final currentUserId = context.read<AuthProvider>().user?.id;

    return RoundedScaffold(
      title: 'Leaderboards',
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: Column(
              children: [
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
                  onTap: (_) => setState(() {}),
                ),
                if (_mainTabController.index != 3)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: TabBar(
                      controller: _periodTabController,
                      isScrollable: true,
                      tabs: _periods
                          .map(
                            (period) => Tab(
                              text: period['name'].toString(),
                              icon: Icon(period['icon'] as IconData, size: 16),
                            ),
                          )
                          .toList(growable: false),
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
                      _buildRankingsList(
                        _giftRankings['rankings'] as List<dynamic>? ?? const [],
                        _giftRankings['userRank'] as Map<String, dynamic>?,
                        currentUserId,
                        'gifts',
                      ),
                      _buildRankingsList(
                        _charmRankings['rankings'] as List<dynamic>? ?? const [],
                        _charmRankings['userRank'] as Map<String, dynamic>?,
                        currentUserId,
                        'charm',
                      ),
                      _buildGamesTab(currentUserId),
                      _buildRankingsList(
                        _overallRankings['rankings'] as List<dynamic>? ?? const [],
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
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _gameTabs.length,
            itemBuilder: (context, index) {
              final game = _gameTabs[index];
              final isSelected = _selectedGameIndex == index;
              final icon = game['icon'] as IconData;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 16,
                        color: isSelected
                            ? AppColors.primaryBlue
                            : Colors.black87,
                      ),
                      const SizedBox(width: 6),
                      Text(game['name'].toString()),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (_) {
                    if (_isDisposed || !mounted) return;
                    setState(() {
                      _selectedGameIndex = index;
                      _isLoading = true;
                    });
                    _loadGameRankings(game['id'].toString()).then((_) {
                      if (!_isDisposed && mounted) {
                        setState(() => _isLoading = false);
                      }
                    });
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
    switch (_currentGameId) {
      case 'werewolf':
        return _werewolfRankings['rankings'] as List<dynamic>? ?? const [];
      case 'drawing':
        return _drawingRankings['rankings'] as List<dynamic>? ?? const [];
      case 'karaoke':
        return _karaokeRankings['rankings'] as List<dynamic>? ?? const [];
      case 'color_clash':
        return _colorClashRankings['rankings'] as List<dynamic>? ?? const [];
      default:
        return const [];
    }
  }

  Map<String, dynamic>? _getCurrentGameUserRank() {
    switch (_currentGameId) {
      case 'werewolf':
        return _werewolfRankings['userRank'] as Map<String, dynamic>?;
      case 'drawing':
        return _drawingRankings['userRank'] as Map<String, dynamic>?;
      case 'karaoke':
        return _karaokeRankings['userRank'] as Map<String, dynamic>?;
      case 'color_clash':
        return _colorClashRankings['userRank'] as Map<String, dynamic>?;
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
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

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
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
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
        if (userRank != null)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.3),
              ),
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
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rankings.length,
            itemBuilder: (context, index) {
              final rank = rankings[index] as Map<String, dynamic>;
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
                    UserAvatar(
                      imageUrl: rank['avatar']?.toString(),
                      username: rank['username']?.toString() ?? '',
                      radius: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  rank['username']?.toString() ?? 'Unknown',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
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
