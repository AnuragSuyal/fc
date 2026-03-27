import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/constants.dart';

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final games = const [
      _Game(
        name: 'Werewolf',
        subtitle: 'Voice strategy party',
        players: '2.3k playing',
        icon: Icons.nightlight_round,
        color: AppColors.primaryBlue,
      ),
      _Game(
        name: 'Ludo Star',
        subtitle: 'Classic board chaos',
        players: '1.5k playing',
        icon: Icons.casino_rounded,
        color: AppColors.accentYellow,
      ),
      _Game(
        name: 'Uno Party',
        subtitle: 'Fast social cards',
        players: '800 playing',
        icon: Icons.style_rounded,
        color: AppColors.accentSky,
      ),
      _Game(
        name: 'Teen Patti',
        subtitle: 'Table energy on',
        players: '3.1k playing',
        icon: Icons.auto_awesome_rounded,
        color: AppColors.secondaryBlue,
      ),
      _Game(
        name: 'Chess King',
        subtitle: 'Quiet ranked battles',
        players: '400 playing',
        icon: Icons.extension_rounded,
        color: AppColors.accentBerry,
      ),
      _Game(
        name: 'Antakshari',
        subtitle: 'Sing-off rooms',
        players: '1.2k playing',
        icon: Icons.music_note_rounded,
        color: AppColors.primaryBlue,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: context.mood.heroGradient,
            boxShadow: [
              BoxShadow(
                color: context.mood.shadow,
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Game night energy',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Jump into playful lobbies',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Party tables, casual competitions, and warm-up rounds built for fast fun.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.84),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text('Popular games', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: games.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.86,
          ),
          itemBuilder: (context, index) {
            final game = games[index];
            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: context.mood.outlineSoft),
                boxShadow: [
                  BoxShadow(
                    color: game.color.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: game.color.withValues(alpha: 0.14),
                    child: Icon(game.icon, color: game.color, size: 28),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    game.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(game.subtitle, style: theme.textTheme.bodySmall),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(
                        Icons.people_alt_outlined,
                        size: 16,
                        color: AppColors.textSecondary.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(game.players,
                            style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('Opening ${game.name} lobby...')),
                        );
                      },
                      style:
                          FilledButton.styleFrom(backgroundColor: game.color),
                      child: const Text('Play now'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Game {
  final String name;
  final String subtitle;
  final String players;
  final IconData icon;
  final Color color;

  const _Game({
    required this.name,
    required this.subtitle,
    required this.players,
    required this.icon,
    required this.color,
  });
}
