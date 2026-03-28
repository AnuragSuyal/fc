import 'package:flutter/material.dart';
import '../../models/quest_model.dart';
import '../../services/economy_service.dart';
import '../../utils/constants.dart';
import '../../widgets/currency_icon.dart';

class QuestsScreen extends StatefulWidget {
  const QuestsScreen({super.key});

  @override
  State<QuestsScreen> createState() => _QuestsScreenState();
}

class _QuestsScreenState extends State<QuestsScreen> {
  List<QuestModel> _quests = [];
  bool _isLoading = true;
  String? _error;
  int _selectedTab = 0; // 0 = daily, 1 = weekly

  List<QuestModel> get _visibleQuests {
    final targetType = _selectedTab == 0 ? 'daily' : 'weekly';
    return _quests.where((quest) => quest.type == targetType).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadQuests();
  }

  Future<void> _loadQuests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final quests = await EconomyService.getDailyQuests();

      if (!mounted) return;

      setState(() {
        _quests = quests;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _claimQuest(QuestModel quest) async {
    try {
      await EconomyService.claimQuestReward(questId: quest.questId);

      if (!mounted) return;

      await _loadQuests();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quest reward claimed: +${quest.reward['coins'] ?? 0} coins, +${quest.reward['gems'] ?? 0} gems',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to claim: $e'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleQuests = _visibleQuests;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quests'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: Colors.red.shade300),
                      const SizedBox(height: 16),
                      const Text('Failed to load quests'),
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: TextStyle(color: Colors.grey.shade600)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadQuests,
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Tab selector
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedTab = 0),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _selectedTab == 0
                                      ? AppColors.primaryBlue
                                      : Colors.grey.shade200,
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(30),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'Daily',
                                    style: TextStyle(
                                      color: _selectedTab == 0
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: _selectedTab == 0
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedTab = 1),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _selectedTab == 1
                                      ? AppColors.primaryBlue
                                      : Colors.grey.shade200,
                                  borderRadius: const BorderRadius.horizontal(
                                    right: Radius.circular(30),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'Weekly',
                                    style: TextStyle(
                                      color: _selectedTab == 1
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: _selectedTab == 1
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Quest list
                    Expanded(
                      child: visibleQuests.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.assignment_outlined,
                                    size: 64,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _selectedTab == 0
                                        ? 'No daily quests available'
                                        : 'No weekly quests available',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: visibleQuests.length,
                              itemBuilder: (context, index) {
                                final quest = visibleQuests[index];
                                final canClaim = quest.canClaim;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: quest.completed
                                        ? Colors.green.shade50
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: quest.completed
                                          ? Colors.green.shade200
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: quest.completed
                                                  ? Colors.green
                                                  : AppColors.primaryBlue,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              quest.completed
                                                  ? Icons.check
                                                  : _getQuestIcon(quest.title),
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  quest.title,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text(
                                                  quest.description,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (quest.completed && !quest.claimed)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.orange.shade200,
                                                ),
                                              ),
                                              child: const Text(
                                                'READY',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.orange,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),

                                      const SizedBox(height: 12),

                                      // Progress bar
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: quest.progressPercentage,
                                          backgroundColor: Colors.grey.shade300,
                                          valueColor: AlwaysStoppedAnimation(
                                            quest.completed
                                                ? Colors.green
                                                : AppColors.primaryBlue,
                                          ),
                                          minHeight: 8,
                                        ),
                                      ),

                                      const SizedBox(height: 8),

                                      // Progress text
                                      Row(
                                        children: [
                                          Text(
                                            '${quest.progress}/${quest.target}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: quest.completed
                                                  ? Colors.green
                                                  : AppColors.primaryBlue,
                                            ),
                                          ),
                                          const Spacer(),

                                          // Reward preview
                                          if (quest.reward['coins'] != null)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                  right: 8),
                                              child: Row(
                                                children: [
                                                  const CurrencyIcon.coins(
                                                      size: 14),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    '+${quest.reward['coins']}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.amber,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                          if (quest.reward['gems'] != null)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                  right: 8),
                                              child: Row(
                                                children: [
                                                  const CurrencyIcon.gems(
                                                      size: 14),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    '+${quest.reward['gems']}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.purple,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                          if (quest.reward['xp'] != null)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                  right: 8),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.star,
                                                    size: 14,
                                                    color: Colors.blue,
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    '+${quest.reward['xp']} XP',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.blue,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),

                                      if (canClaim) ...[
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            onPressed: () => _claimQuest(quest),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                            ),
                                            child: const Text('Claim Reward'),
                                          ),
                                        ),
                                      ],
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

  IconData _getQuestIcon(String title) {
    if (title.contains('Game')) return Icons.games;
    if (title.contains('Gift')) return Icons.card_giftcard;
    if (title.contains('Friend')) return Icons.people;
    if (title.contains('Chat')) return Icons.chat;
    if (title.contains('Host')) return Icons.mic;
    return Icons.assignment;
  }
}
