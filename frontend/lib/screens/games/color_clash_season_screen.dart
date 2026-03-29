import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/color_clash_season_model.dart';
import '../../providers/color_clash_session_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/color_clash/color_clash_status_banner.dart';
import '../../widgets/rounded_scaffold.dart';
import '../../widgets/user_avatar.dart';

class ColorClashSeasonScreen extends StatefulWidget {
  const ColorClashSeasonScreen({super.key});

  static const String routeName = '/games/color-clash/season';

  @override
  State<ColorClashSeasonScreen> createState() => _ColorClashSeasonScreenState();
}

class _ColorClashSeasonScreenState extends State<ColorClashSeasonScreen> {
  Future<ColorClashLeaderboardPayloadModel?>? _leaderboardFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<ColorClashSessionController>();
      controller.trackUiEvent('season_screen_opened');
      controller.loadSeasonSummary(force: true);
      setState(() {
        _leaderboardFuture = controller.loadLeaderboard(limit: 20);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ColorClashSessionController>();
    final summary = controller.seasonSummary;
    final season = summary?.season;
    final progress = summary?.userProgress;
    final eligibility = summary?.eligibility;

    return RoundedScaffold(
      title: 'Season Ladder',
      body: Builder(
        builder: (context) {
          if (controller.isSeasonLoading && summary == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (controller.seasonError != null && summary == null) {
            return _SeasonMessage(
              title: 'Season data unavailable',
              message: controller.seasonError!,
              actionLabel: 'Retry',
              onPressed: () async {
                await controller.loadSeasonSummary(force: true);
                setState(() {
                  _leaderboardFuture = controller.loadLeaderboard(limit: 20);
                });
              },
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              if (controller.statusNotice != null)
                ColorClashStatusBanner(
                  notice: controller.statusNotice!,
                  onDismiss: controller.clearStatusNotice,
                ),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryBlue,
                      context.mood.berry,
                      AppColors.accentSky,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      season?.name ?? 'Color Clash Season',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      season == null
                          ? 'Season config is loading from the backend.'
                          : 'Ends ${_formatDate(season.endsAt)} • ${season.rankedEnabled ? 'Ranked live' : 'Ranked paused'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.86),
                          ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _SeasonHeroPill(
                          label: 'Rating ${progress?.rating ?? 0}',
                        ),
                        _SeasonHeroPill(
                          label: progress == null
                              ? 'Unplaced'
                              : '${progress.tierName} • D${progress.division}',
                        ),
                        _SeasonHeroPill(
                          label:
                              '${progress?.placementMatchesRemaining ?? 0} placement left',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (progress != null)
                _SeasonProgressCard(
                  progress: progress,
                  userRank: summary?.userRank,
                ),
              if (eligibility != null && eligibility.hasAnyLock) ...[
                const SizedBox(height: 18),
                _RankedLockCard(eligibility: eligibility),
              ],
              const SizedBox(height: 18),
              Text(
                'Top players',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              FutureBuilder<ColorClashLeaderboardPayloadModel?>(
                future: _leaderboardFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !(snapshot.hasData)) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final leaderboard = snapshot.data;
                  if (snapshot.hasError || leaderboard == null) {
                    return _SeasonMessage(
                      title: 'Leaderboard unavailable',
                      message: controller.seasonError ??
                          'We could not load ranked standings right now.',
                    );
                  }
                  if (leaderboard.rankings.isEmpty) {
                    return const _SeasonMessage(
                      title: 'No season matches yet',
                      message:
                          'The ranked board will fill in once matches settle.',
                    );
                  }
                  return Column(
                    children: leaderboard.rankings
                        .take(12)
                        .map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                border:
                                    Border.all(color: context.mood.outlineSoft),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.backgroundWhite,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      '#${entry.rank}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  UserAvatar(
                                    imageUrl: entry.avatar,
                                    username: entry.username,
                                    radius: 18,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.username,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${entry.tierId} • D${entry.division} • ${entry.stars} stars',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${entry.rating}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'soon';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _SeasonHeroPill extends StatelessWidget {
  const _SeasonHeroPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
            ),
      ),
    );
  }
}

class _SeasonProgressCard extends StatelessWidget {
  const _SeasonProgressCard({
    required this.progress,
    required this.userRank,
  });

  final ColorClashSeasonProgressModel progress;
  final ColorClashLeaderboardUserRankModel? userRank;

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
          Text(
            'Your climb',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ProgressStat(label: 'Rating', value: '${progress.rating}'),
              _ProgressStat(
                label: 'Tier',
                value: '${progress.tierName} • D${progress.division}',
              ),
              _ProgressStat(label: 'Stars', value: '${progress.stars}'),
              _ProgressStat(
                label: 'Placement',
                value: '${progress.placementMatchesRemaining} left',
              ),
              _ProgressStat(label: 'Wins', value: '${progress.wins}'),
              _ProgressStat(label: 'Losses', value: '${progress.losses}'),
              _ProgressStat(
                label: 'Rank',
                value: userRank == null ? '—' : '#${userRank!.rank}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressStat extends StatelessWidget {
  const _ProgressStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _RankedLockCard extends StatelessWidget {
  const _RankedLockCard({required this.eligibility});

  final ColorClashEligibilityModel eligibility;

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
          Text(
            'Eligibility',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 10),
          if (eligibility.rankedLockReason.isNotEmpty)
            Text(
              'Ranked: ${eligibility.rankedLockReason}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          if (eligibility.stakeLockReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Stake: ${eligibility.stakeLockReason}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _SeasonMessage extends StatelessWidget {
  const _SeasonMessage({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onPressed,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (actionLabel != null && onPressed != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onPressed,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
