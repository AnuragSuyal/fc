import 'package:flutter/material.dart';
import 'enhanced_profile_screen.dart'; // For BadgeDetailScreen
import '../../widgets/rounded_scaffold.dart';

class BadgesScreen extends StatelessWidget {
  final List<dynamic> badges;

  const BadgesScreen({super.key, required this.badges});

  @override
  Widget build(BuildContext context) {
    return RoundedScaffold(
      title: 'All Badges',
      body: badges.isEmpty
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
                    'No badges yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.9,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: badges.length,
              itemBuilder: (context, index) {
                final badge = badges[index];
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
                      color: _getRarityColor(badge['rarity'])
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _getRarityColor(badge['rarity'])
                            .withValues(alpha: 0.3),
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
}






