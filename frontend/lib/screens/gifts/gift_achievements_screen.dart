import 'package:flutter/material.dart';
import '../../services/gift_service.dart';
import '../../utils/constants.dart';

class GiftAchievementsScreen extends StatefulWidget {
  const GiftAchievementsScreen({super.key});

  @override
  State<GiftAchievementsScreen> createState() => _GiftAchievementsScreenState();
}

class _GiftAchievementsScreenState extends State<GiftAchievementsScreen> {
  Map<String, dynamic> _data = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAchievements();
  }

  Future<void> _loadAchievements() async {
    final data = await GiftService.getGiftAchievements();

    if (!mounted) return;

    setState(() {
      _data = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final achievements = _data['achievements'] as List? ?? [];
    final specialTitles = _data['specialTitles'] as List? ?? [];
    final stats = _data['stats'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gift Achievements'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.primaryBlue,
                          AppColors.secondaryBlue
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Icon(
                              Icons.card_giftcard,
                              color: Colors.white,
                              size: 32,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${stats['giftsSent'] ?? 0}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'Sent',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            const Icon(
                              Icons.card_giftcard,
                              color: Colors.white,
                              size: 32,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${stats['giftsReceived'] ?? 0}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'Received',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Achievements
                  const Text(
                    'Achievements',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  ...achievements.map((achievement) {
                    final progress = (achievement['progress'] ?? 0) /
                        (achievement['target'] ?? 1);
                    final isCompleted = achievement['completed'] ?? false;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? Colors.green.shade50
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isCompleted
                              ? Colors.green.shade200
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: isCompleted
                                  ? Colors.green.shade100
                                  : Colors.grey.shade200,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                achievement['reward']?['badge'] ?? 'ðŸŽ',
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  achievement['name'] ?? '',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isCompleted
                                        ? Colors.green.shade700
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  achievement['description'] ?? '',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: progress.clamp(0.0, 1.0),
                                          backgroundColor: Colors.grey.shade300,
                                          valueColor: AlwaysStoppedAnimation(
                                            isCompleted
                                                ? Colors.green
                                                : AppColors.primaryBlue,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${achievement['progress'] ?? 0}/${achievement['target'] ?? 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isCompleted
                                            ? Colors.green
                                            : Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (isCompleted)
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            ),
                        ],
                      ),
                    );
                  }),

                  if (specialTitles.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Special Titles',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...specialTitles.map((title) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.emoji_events,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title['title'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber,
                                    ),
                                  ),
                                  Text(
                                    title['requirement'] ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.amber.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }
}






