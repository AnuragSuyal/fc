import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/economy_service.dart';
import '../../utils/haptics_util.dart';
import '../../widgets/currency_icon.dart';

class DailyRewardsScreen extends StatefulWidget {
  const DailyRewardsScreen({super.key});

  @override
  State<DailyRewardsScreen> createState() => _DailyRewardsScreenState();
}

class _DailyRewardsScreenState extends State<DailyRewardsScreen> {
  bool _isLoading = false;
  bool _isClaiming = false;
  bool _alreadyClaimed = false;
  bool _canClaim = true;
  int _streak = 0;
  int _day = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    // In a real app, this would check if lastDailyReward is today
  }

  Future<void> _claimReward() async {
    if (_isClaiming || !_canClaim || _alreadyClaimed) return;

    setState(() {
      _isClaiming = true;
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await EconomyService.claimDailyReward();

      if (!mounted) return;

      if (result['alreadyClaimed'] == true) {
        setState(() {
          _alreadyClaimed = true;
          _canClaim = false;
          _isClaiming = false;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Already claimed today! Come back tomorrow.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Update auth provider balance
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.user != null) {
        authProvider.updateBalance(
          coins: authProvider.user!.coins + (result['coins'] as int? ?? 100),
          gems: authProvider.user!.gems,
        );
      }

      setState(() {
        _canClaim = false;
        _alreadyClaimed = true;
        _isClaiming = false;
        _streak = result['streak'] ?? 0;
        _day = result['day'] ?? 1;
        _isLoading = false;
      });

      // Show success dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reward Claimed! ðŸŽ‰'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  shape: BoxShape.circle,
                ),
                child: const CurrencyIcon.coins(size: 52),
              ),
              const SizedBox(height: 16),
              Text(
                'You received ${result['coins']} coins!',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Day ${result['streak']} streak',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Awesome!'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      HapticsUtil.error();
      setState(() {
        _isClaiming = false;
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Rewards'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.amber, Colors.orange],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.star,
                          size: 64,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Daily Login Rewards',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Day $_streak Streak',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Calendar-style rewards
                  const Text(
                    'Your Rewards',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      childAspectRatio: 1,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: 30,
                    itemBuilder: (context, index) {
                      final day = index + 1;
                      final isCurrentDay = day == _day;
                      final isPastDay = day < _day;

                      // Calculate reward for this day
                      int reward = 100;
                      if (day % 7 == 0) {
                        reward = 500; // Weekly bonus
                      } else if (day % 5 == 0) {
                        reward = 300; // Milestone
                      } else {
                        reward = 100 + (day * 10); // Increasing rewards
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: isPastDay
                              ? Colors.green.shade50
                              : isCurrentDay
                                  ? Colors.amber.shade50
                                  : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrentDay
                                ? Colors.amber
                                : isPastDay
                                    ? Colors.green.shade200
                                    : Colors.grey.shade300,
                            width: isCurrentDay ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Day $day',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isCurrentDay
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isCurrentDay
                                    ? Colors.amber.shade700
                                    : isPastDay
                                        ? Colors.green.shade700
                                        : Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const CurrencyIcon.coins(size: 20),
                            Text(
                              '$reward',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isCurrentDay
                                    ? Colors.amber.shade700
                                    : isPastDay
                                        ? Colors.green.shade700
                                        : Colors.grey.shade700,
                              ),
                            ),
                            if (isPastDay)
                              const Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Colors.green,
                              ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Streak info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.local_fire_department,
                            color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Keep logging in daily to increase your streak and earn bigger rewards!',
                            style: TextStyle(color: Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Claim button
                  if (_canClaim)
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _claimReward,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'CLAIM TODAY\'S REWARD',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'Already claimed today. Come back tomorrow!',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
