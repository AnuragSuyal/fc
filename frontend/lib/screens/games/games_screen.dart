import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/color_clash_session_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import 'color_clash_home_screen.dart';
import 'color_clash_season_screen.dart';
import 'color_clash_table_screen.dart';

class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<ColorClashSessionController>();
      controller.loadHome(force: true);
      controller.loadSeasonSummary(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ColorClashSessionController>();
    final home = controller.home;
    final season = home?.season;
    final progress = home?.userProgress.currentSeason;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryBlue,
                context.mood.berry,
                AppColors.secondaryBlue,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.18),
                blurRadius: 26,
                offset: const Offset(0, 14),
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
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Featured original game',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Color Clash',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Premium social card sessions built on the new realtime backend spine.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.84),
                    ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryBlue,
                      ),
                      onPressed: () {
                        Navigator.of(context).pushNamed(
                          ColorClashHomeScreen.routeName,
                        );
                      },
                      child: const Text('Open game'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.28),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pushNamed(
                          ColorClashSeasonScreen.routeName,
                        );
                      },
                      child: const Text('Season'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (home?.activeMatch != null) ...[
          const SizedBox(height: 18),
          Text(
            'Resume live match',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: context.mood.outlineSoft),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.play_circle_fill_rounded,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Round ${home!.activeMatch!.publicState?.roundNumber ?? 1}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${home.activeMatch!.tableMode.replaceAll('_', ' ')} • version ${home.activeMatch!.version}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      ColorClashTableScreen.routeName,
                      arguments: <String, dynamic>{
                        'matchId': home.activeMatch!.matchId,
                        'roomId': home.activeMatch!.roomId,
                      },
                    );
                  },
                  child: const Text('Resume'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'Season snapshot',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: context.mood.outlineSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                season?.name ?? 'Color Clash Season',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                progress == null
                    ? 'Open the season page to see your current placement and eligibility.'
                    : '${progress.tierName} • Division ${progress.division} • Rating ${progress.rating}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'More game nights',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.05,
          children: const [
            _FutureGameCard(
              title: 'Voice Mysteries',
              subtitle: 'Social deduction next',
              icon: Icons.nightlight_round,
            ),
            _FutureGameCard(
              title: 'Board Social',
              subtitle: 'Classic rolls later',
              icon: Icons.casino_rounded,
            ),
            _FutureGameCard(
              title: 'Music Rooms',
              subtitle: 'Mic-led party modes',
              icon: Icons.music_note_rounded,
            ),
            _FutureGameCard(
              title: 'Quiet Strategy',
              subtitle: 'Deep ranked tables',
              icon: Icons.extension_rounded,
            ),
          ],
        ),
      ],
    );
  }
}

class _FutureGameCard extends StatelessWidget {
  const _FutureGameCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.backgroundWhite,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppColors.primaryBlue),
          ),
          const Spacer(),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
