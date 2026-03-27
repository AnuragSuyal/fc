import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../widgets/rounded_scaffold.dart';

class GameStatsScreen extends StatelessWidget {
  final Map<String, dynamic> gameStats;

  const GameStatsScreen({super.key, required this.gameStats});

  @override
  Widget build(BuildContext context) {
    return RoundedScaffold(
      title: 'Game Statistics',
      body: gameStats.isEmpty
          ? Center(
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
                    'No game stats available',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (gameStats['werewolf'] != null)
                  _buildGameStatCard(
                    'Werewolf',
                    gameStats['werewolf'],
                    Icons.whatshot,
                  ),
                if (gameStats['drawing'] != null)
                  _buildGameStatCard(
                    'Drawing',
                    gameStats['drawing'],
                    Icons.brush,
                  ),
                if (gameStats['karaoke'] != null)
                  _buildGameStatCard(
                    'Karaoke',
                    gameStats['karaoke'],
                    Icons.mic,
                  ),
                if (gameStats['uno'] != null)
                  _buildGameStatCard(
                    'UNO',
                    gameStats['uno'],
                    Icons.style,
                  ),
              ],
            ),
    );
  }

  Widget _buildGameStatCard(
      String title, Map<String, dynamic> stats, IconData icon) {
    final played = stats['played'] ?? 0;
    final won = stats['won'] ?? 0;
    final winRate = played > 0 ? (won / played * 100).toInt() : 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
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
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
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
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatCircle('Played', '$played', Icons.games),
                _buildStatCircle('Won', '$won', Icons.emoji_events),
                _buildStatCircle('Win Rate', '$winRate%', Icons.trending_up),
              ],
            ),
            const Divider(height: 24),

            // Additional stats
            if (stats['speed'] != null)
              _buildStatRow(Icons.speed, 'Speed', stats['speed']),
            if (stats['logic'] != null)
              _buildStatRow(Icons.psychology, 'Logic', stats['logic']),
            if (stats['pitch'] != null)
              _buildStatRow(Icons.music_note, 'Pitch', stats['pitch']),
            if (stats['strategy'] != null)
              _buildStatRow(Icons.lightbulb, 'Strategy', stats['strategy']),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCircle(String label, String value, IconData icon) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(icon, color: AppColors.primaryBlue, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
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

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: const TextStyle(color: AppColors.primaryBlue),
          ),
        ],
      ),
    );
  }
}






