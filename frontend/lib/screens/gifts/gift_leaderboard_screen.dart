import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/gift_service.dart';
import '../../utils/constants.dart';
import '../../widgets/user_avatar.dart';

class GiftLeaderboardScreen extends StatefulWidget {
  const GiftLeaderboardScreen({super.key});

  @override
  State<GiftLeaderboardScreen> createState() => _GiftLeaderboardScreenState();
}

class _GiftLeaderboardScreenState extends State<GiftLeaderboardScreen> {
  String _selectedPeriod = 'weekly';
  List<dynamic> _leaderboard = [];
  Map<String, dynamic>? _userRank;
  bool _isLoading = true;
  bool _isDisposed = false;

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  final List<Map<String, String>> _periods = [
    {'id': 'daily', 'name': 'Daily'},
    {'id': 'weekly', 'name': 'Weekly'},
    {'id': 'monthly', 'name': 'Monthly'},
    {'id': 'alltime', 'name': 'All Time'},
  ];

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    _safeSetState(() {
      _isLoading = true;
    });

    final data = await GiftService.getGiftLeaderboard(period: _selectedPeriod);

    if (!mounted) return;

    _safeSetState(() {
      _leaderboard = data['leaderboard'] ?? [];
      _userRank = data['userRank'];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final userId = authProvider.user?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gift Leaderboard'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Period selector
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: _periods.map((period) {
                      final isSelected = _selectedPeriod == period['id'];
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _safeSetState(() {
                              _selectedPeriod = period['id']!;
                            });
                            _loadLeaderboard();
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primaryBlue
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              period['name']!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color:
                                    isSelected ? Colors.white : Colors.black87,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // User rank card
                if (_userRank != null)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.primaryBlue.withAlpha(77)),
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
                              '#${_userRank!['rank']}',
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
                          '${_userRank!['count']} gifts',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Leaderboard list
                Expanded(
                  child: _leaderboard.isEmpty
                      ? Center(
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
                                'No data yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Be the first to send a gift!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _leaderboard.length,
                          itemBuilder: (context, index) {
                            final item = _leaderboard[index];
                            final isCurrentUser = item['userId'] == userId;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isCurrentUser
                                    ? AppColors.primaryBlue.withAlpha(26)
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
                                        '#${item['rank']}',
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
                                    imageUrl: item['avatar'],
                                    username: item['username'] ?? 'Unknown',
                                    radius: 20,
                                  ),
                                  const SizedBox(width: 12),

                                  // User info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['username'] ?? 'Unknown',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Level ${item['level'] ?? 1}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Gift count
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${item['count']}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
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
}






