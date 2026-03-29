import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/color_clash_home_model.dart';
import '../../models/color_clash_season_model.dart';
import '../../models/color_clash_table_model.dart';
import '../../providers/color_clash_session_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/color_clash/color_clash_status_banner.dart';
import '../../widgets/rounded_scaffold.dart';
import '../../widgets/user_avatar.dart';
import 'color_clash_lobby_screen.dart';
import 'color_clash_matchmaking_screen.dart';
import 'color_clash_season_screen.dart';
import 'color_clash_table_screen.dart';

class ColorClashHomeScreen extends StatefulWidget {
  const ColorClashHomeScreen({super.key});

  static const String routeName = '/games/color-clash';

  @override
  State<ColorClashHomeScreen> createState() => _ColorClashHomeScreenState();
}

class _ColorClashHomeScreenState extends State<ColorClashHomeScreen> {
  String? _lastPendingMatchKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<ColorClashSessionController>();
      controller.trackUiEvent('home_screen_opened');
      controller.loadHome(force: true);
      controller.loadTables(force: true);
      controller.loadSeasonSummary(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ColorClashSessionController>();
    _maybeOpenPendingMatch(controller);

    final home = controller.home;
    final tables = controller.tables;
    final queuePresets = home?.queuePresets ?? tables?.queuePresets ?? const [];
    final friendRooms = home?.rooms ?? tables?.rooms ?? const [];
    final seasonProgress = home?.userProgress.currentSeason;
    final eligibility = home?.userProgress.eligibility;

    return RoundedScaffold(
      title: 'Color Clash',
      actions: [
        IconButton(
          tooltip: 'Season',
          onPressed: () {
            Navigator.of(context).pushNamed(ColorClashSeasonScreen.routeName);
          },
          icon: const Icon(Icons.emoji_events_outlined),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          await controller.loadHome(force: true);
          await controller.loadTables(force: true);
          await controller.loadSeasonSummary(force: true);
        },
        child: Builder(
          builder: (context) {
            if (controller.isHomeLoading && home == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (controller.homeError != null && home == null) {
              return _ColorClashErrorState(
                title: 'Color Clash could not load',
                message: controller.homeError!,
                onRetry: () async {
                  await controller.loadHome(force: true);
                  await controller.loadTables(force: true);
                },
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                if (controller.statusNotice != null)
                  ColorClashStatusBanner(
                    notice: controller.statusNotice!,
                    onDismiss: controller.clearStatusNotice,
                  ),
                _HomeHero(
                  queuePresets: queuePresets,
                  stakeEligible: eligibility?.stakeEligible ?? true,
                  rankedEligible: eligibility?.rankedEligible ?? true,
                  onQueueTap: (mode) => _openQueue(context, queuePresets, mode),
                  onCreateRoom: () => _showCreateRoomSheet(context),
                ),
                if (home?.activeMatch != null) ...[
                  const SizedBox(height: 18),
                  _SectionHeading(
                    title: 'Resume Match',
                    actionLabel: 'Reconnect',
                    onAction: () {
                      Navigator.of(context).pushNamed(
                        ColorClashTableScreen.routeName,
                        arguments: <String, dynamic>{
                          'matchId': home!.activeMatch!.matchId,
                          'roomId': home.activeMatch!.roomId,
                        },
                      );
                    },
                  ),
                  _ActiveMatchCard(activeMatch: home!.activeMatch!),
                ],
                const SizedBox(height: 18),
                _SectionHeading(
                  title: 'Play Now',
                  actionLabel: 'Refresh',
                  onAction: () async {
                    await controller.loadTables(force: true);
                  },
                ),
                if (queuePresets.isEmpty)
                  const _ColorClashEmptyCard(
                    title: 'No queues live right now',
                    message:
                        'Fresh tables will appear here as soon as the backend opens them.',
                  )
                else
                  ...queuePresets.map(
                    (preset) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _QueuePresetCard(
                        preset: preset,
                        onTap: preset.enabled
                            ? () => Navigator.of(context).pushNamed(
                                  ColorClashMatchmakingScreen.routeName,
                                  arguments: <String, dynamic>{
                                    'mode': preset.mode,
                                    'stakeAmount': preset.stakeAmount,
                                    'themePackId': preset.themePackId,
                                  },
                                )
                            : null,
                      ),
                    ),
                  ),
                if (seasonProgress != null || home?.season != null) ...[
                  const SizedBox(height: 18),
                  _SectionHeading(
                    title: 'Season Pulse',
                    actionLabel: 'View season',
                    onAction: () {
                      Navigator.of(context).pushNamed(
                        ColorClashSeasonScreen.routeName,
                      );
                    },
                  ),
                  _SeasonSummaryCard(
                    seasonName: home?.season?.name ?? 'Current season',
                    progress: seasonProgress,
                    userRank: home?.userProgress.currentUserRank,
                  ),
                ],
                if (eligibility != null && eligibility.hasAnyLock) ...[
                  const SizedBox(height: 18),
                  _SectionHeading(title: 'Access Status'),
                  _EligibilityCard(eligibility: eligibility),
                ],
                const SizedBox(height: 18),
                _SectionHeading(title: 'Theme Pack'),
                _ThemeSelectionCard(
                  home: home,
                  onEquip: (themePackId) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final equipped = await controller.equipTheme(themePackId);
                    if (!context.mounted || equipped == null) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          '${equipped.colorClashThemeLabel} is now equipped.',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                _SectionHeading(title: 'Friend Rooms'),
                if (friendRooms.isEmpty)
                  const _ColorClashEmptyCard(
                    title: 'No friend rooms yet',
                    message:
                        'Create a private room or wait for a shared table to appear.',
                  )
                else
                  ...friendRooms.map(
                    (room) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _FriendRoomCard(
                        room: room,
                        onJoin: () => _joinRoom(context, room.roomId),
                        onSpectate: room.allowSpectators
                            ? () => _joinRoom(
                                  context,
                                  room.roomId,
                                  spectator: true,
                                )
                            : null,
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                _SectionHeading(title: 'How It Flows'),
                _TutorialCard(
                  completed: home?.tutorial.isV1Complete ?? false,
                  onAcknowledge: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final completed = await controller.completeTutorial();
                    if (!context.mounted || !completed) return;
                    messenger.showSnackBar(
                      const SnackBar(
                        content:
                            Text('Color Clash basics saved to your profile.'),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _maybeOpenPendingMatch(ColorClashSessionController controller) {
    final target = controller.pendingMatchTarget;
    if (target == null) return;
    final targetKey = '${target.roomId}:${target.matchId}:${target.source}';
    if (_lastPendingMatchKey == targetKey) return;
    _lastPendingMatchKey = targetKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.consumePendingMatchTarget();
      Navigator.of(context).pushNamed(
        ColorClashTableScreen.routeName,
        arguments: <String, dynamic>{
          'matchId': target.matchId,
          'roomId': target.roomId,
        },
      );
    });
  }

  void _openQueue(
    BuildContext context,
    List<ColorClashQueuePresetModel> presets,
    String mode,
  ) {
    final matchingPreset =
        presets.where((entry) => entry.mode == mode).toList();
    if (matchingPreset.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This queue is not available yet.')),
      );
      return;
    }

    final preset = matchingPreset.first;
    Navigator.of(context).pushNamed(
      ColorClashMatchmakingScreen.routeName,
      arguments: <String, dynamic>{
        'mode': preset.mode,
        'stakeAmount': preset.stakeAmount,
        'themePackId': preset.themePackId,
      },
    );
  }

  Future<void> _joinRoom(
    BuildContext context,
    String roomId, {
    bool spectator = false,
  }) async {
    final controller = context.read<ColorClashSessionController>();
    final session = await controller.joinRoom(roomId, spectator: spectator);
    if (!context.mounted || session == null) return;
    Navigator.of(context).pushNamed(
      ColorClashLobbyScreen.routeName,
      arguments: <String, dynamic>{'roomId': roomId},
    );
  }

  Future<void> _showCreateRoomSheet(BuildContext context) async {
    final controller = context.read<ColorClashSessionController>();
    final roomNameController = TextEditingController();
    String visibility = 'invite_only';
    String tableMode = 'friend_room';
    String themePackId =
        controller.home?.themes.equippedThemePackId ?? 'forest_picnic';
    int maxPlayers = 4;
    bool allowSpectators = true;
    int stakeEntryFee = 0;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
                top: 24,
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: context.mood.outlineSoft),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create a friend room',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: roomNameController,
                      decoration: const InputDecoration(
                        labelText: 'Room name',
                        hintText: 'Friday card circle',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: visibility,
                      items: const [
                        DropdownMenuItem(
                            value: 'public', child: Text('Public')),
                        DropdownMenuItem(
                            value: 'private', child: Text('Private')),
                        DropdownMenuItem(
                          value: 'invite_only',
                          child: Text('Invite only'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() => visibility = value);
                        }
                      },
                      decoration:
                          const InputDecoration(labelText: 'Visibility'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: tableMode,
                      items: const [
                        DropdownMenuItem(
                          value: 'friend_room',
                          child: Text('Friend room'),
                        ),
                        DropdownMenuItem(
                          value: 'custom_chaos',
                          child: Text('Custom chaos'),
                        ),
                        DropdownMenuItem(
                          value: 'gold_stake',
                          child: Text('Gold stake'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          tableMode = value;
                          if (value != 'gold_stake') {
                            stakeEntryFee = 0;
                          } else if (stakeEntryFee == 0) {
                            stakeEntryFee = 50;
                          }
                        });
                      },
                      decoration:
                          const InputDecoration(labelText: 'Table type'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: themePackId,
                      items: const [
                        DropdownMenuItem(
                          value: 'forest_picnic',
                          child: Text('Forest Picnic'),
                        ),
                        DropdownMenuItem(
                          value: 'neon_orbit',
                          child: Text('Neon Orbit'),
                        ),
                        DropdownMenuItem(
                          value: 'candy_carnival',
                          child: Text('Candy Carnival'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() => themePackId = value);
                        }
                      },
                      decoration:
                          const InputDecoration(labelText: 'Theme pack'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: maxPlayers,
                      items: const [2, 4, 6, 8]
                          .map(
                            (count) => DropdownMenuItem<int>(
                              value: count,
                              child: Text('$count players'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() => maxPlayers = value);
                        }
                      },
                      decoration:
                          const InputDecoration(labelText: 'Table size'),
                    ),
                    if (tableMode == 'gold_stake') ...[
                      const SizedBox(height: 12),
                      TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Entry fee',
                          hintText: '50',
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            stakeEntryFee = int.tryParse(value) ?? 0;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: allowSpectators,
                      onChanged: (value) {
                        setModalState(() => allowSpectators = value);
                      },
                      title: const Text('Allow spectators'),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          final sheetNavigator = Navigator.of(context);
                          final rootNavigator = Navigator.of(this.context);
                          final session = await controller.createFriendRoom(
                            name: roomNameController.text,
                            visibility: visibility,
                            allowSpectators: allowSpectators,
                            maxPlayers: maxPlayers,
                            themePackId: themePackId,
                            tableMode: tableMode,
                            stakeEntryFee: stakeEntryFee,
                          );
                          if (!context.mounted || session == null) return;
                          sheetNavigator.pop();
                          if (!mounted) return;
                          rootNavigator.pushNamed(
                            ColorClashLobbyScreen.routeName,
                            arguments: <String, dynamic>{
                              'roomId': session.room.roomId,
                            },
                          );
                        },
                        child: const Text('Open lobby'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ColorClashErrorState extends StatelessWidget {
  const _ColorClashErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_tethering_error_rounded,
              size: 54,
              color: AppColors.errorRed.withValues(alpha: 0.82),
            ),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.queuePresets,
    required this.stakeEligible,
    required this.rankedEligible,
    required this.onQueueTap,
    required this.onCreateRoom,
  });

  final List<ColorClashQueuePresetModel> queuePresets;
  final bool stakeEligible;
  final bool rankedEligible;
  final void Function(String mode) onQueueTap;
  final VoidCallback onCreateRoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryBlue,
            mood.berry,
            AppColors.accentSky,
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
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Original social card nights',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Color Clash',
            style: theme.textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Fast voice-first table energy with real matchmaking, private rooms, season climb, and reconnect-safe play.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroActionChip(
                label: 'Casual',
                icon: Icons.bolt_rounded,
                onTap: () => onQueueTap('casual_free'),
              ),
              _HeroActionChip(
                label: 'Gold Stake',
                icon: Icons.workspace_premium_outlined,
                enabled: stakeEligible,
                onTap: () => onQueueTap('gold_stake'),
              ),
              _HeroActionChip(
                label: 'Ranked',
                icon: Icons.track_changes_rounded,
                enabled: rankedEligible,
                onTap: () => onQueueTap('ranked'),
              ),
              _HeroActionChip(
                label: 'Friend Room',
                icon: Icons.groups_rounded,
                onTap: onCreateRoom,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _HeroActionChip extends StatelessWidget {
  const _HeroActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: enabled
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: enabled ? 0.22 : 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: enabled ? 1 : 0.54),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueuePresetCard extends StatelessWidget {
  const _QueuePresetCard({
    required this.preset,
    required this.onTap,
  });

  final ColorClashQueuePresetModel preset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
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
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [
                    AppColors.primaryBlue,
                    AppColors.secondaryBlue,
                  ],
                ),
              ),
              child: Icon(
                preset.isRanked
                    ? Icons.track_changes_rounded
                    : preset.isStakeTable
                        ? Icons.workspace_premium_outlined
                        : Icons.bolt_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.modeLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preset.isStakeTable
                        ? '${preset.stakeAmount} gold entry • ${preset.playerCount} seats'
                        : '${preset.playerCount} seats • ${preset.region}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TinyPill(label: preset.region),
                      _TinyPill(label: preset.themePackId.colorClashThemeLabel),
                      if (!preset.enabled &&
                          (preset.disabledReason ?? '').isNotEmpty)
                        _TinyPill(
                          label: preset.disabledReason!,
                          tone: AppColors.warningOrange,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              onTap == null
                  ? Icons.lock_outline_rounded
                  : Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SeasonSummaryCard extends StatelessWidget {
  const _SeasonSummaryCard({
    required this.seasonName,
    required this.progress,
    required this.userRank,
  });

  final String seasonName;
  final ColorClashSeasonProgressModel? progress;
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
            seasonName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SeasonStat(label: 'Rating', value: '${progress?.rating ?? 0}'),
              _SeasonStat(
                label: 'Tier',
                value: progress == null
                    ? 'Unplaced'
                    : '${progress!.tierName} • D${progress!.division}',
              ),
              _SeasonStat(label: 'Stars', value: '${progress?.stars ?? 0}'),
              _SeasonStat(
                label: 'Your rank',
                value: userRank == null ? '—' : '#${userRank!.rank}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeasonStat extends StatelessWidget {
  const _SeasonStat({
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

class _EligibilityCard extends StatelessWidget {
  const _EligibilityCard({required this.eligibility});

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
          if (eligibility.rankedLockReason.isNotEmpty)
            _LockRow(
              icon: Icons.track_changes_rounded,
              title: 'Ranked queue',
              subtitle: eligibility.rankedLockReason,
            ),
          if (eligibility.rankedLockReason.isNotEmpty &&
              eligibility.stakeLockReason.isNotEmpty)
            const Divider(height: 20),
          if (eligibility.stakeLockReason.isNotEmpty)
            _LockRow(
              icon: Icons.workspace_premium_outlined,
              title: 'Stake tables',
              subtitle: eligibility.stakeLockReason,
            ),
        ],
      ),
    );
  }
}

class _LockRow extends StatelessWidget {
  const _LockRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.errorRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: AppColors.errorRed),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeSelectionCard extends StatelessWidget {
  const _ThemeSelectionCard({
    required this.home,
    required this.onEquip,
  });

  final ColorClashHomeModel? home;
  final Future<void> Function(String themePackId) onEquip;

  @override
  Widget build(BuildContext context) {
    final equipped = home?.themes.equippedThemePackId ?? 'forest_picnic';
    final owned = home?.themes.ownedThemePackIds ??
        const <String>['forest_picnic', 'neon_orbit', 'candy_carnival'];
    const themeIds = <String>[
      'forest_picnic',
      'neon_orbit',
      'candy_carnival',
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: themeIds.map((themePackId) {
          final isOwned = owned.contains(themePackId);
          return ChoiceChip(
            label: Text(themePackId.colorClashThemeLabel),
            selected: equipped == themePackId,
            onSelected: isOwned ? (_) => onEquip(themePackId) : null,
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _FriendRoomCard extends StatelessWidget {
  const _FriendRoomCard({
    required this.room,
    required this.onJoin,
    this.onSpectate,
  });

  final ColorClashRoomSummaryModel room;
  final VoidCallback onJoin;
  final VoidCallback? onSpectate;

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
          Row(
            children: [
              UserAvatar(
                imageUrl: room.host?.avatar,
                username: room.host?.username ?? room.name,
                radius: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      room.description.isEmpty
                          ? '${room.tableMode.replaceAll('_', ' ')} • ${room.visibility}'
                          : room.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _TinyPill(
                label: room.themePackId.colorClashThemeLabel,
                tone: AppColors.secondaryBlue,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TinyPill(
                  label: '${room.participantCount}/${room.maxPlayers} inside'),
              _TinyPill(label: room.visibility),
              if (room.isPaidTable)
                _TinyPill(
                  label: '${room.stake.entryFee} gold',
                  tone: AppColors.warningOrange,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onJoin,
                  child: const Text('Join room'),
                ),
              ),
              if (onSpectate != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onSpectate,
                    child: const Text('Spectate'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TutorialCard extends StatelessWidget {
  const _TutorialCard({
    required this.completed,
    required this.onAcknowledge,
  });

  final bool completed;
  final Future<void> Function() onAcknowledge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.accentYellow.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              completed ? Icons.check_circle_rounded : Icons.menu_book_rounded,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  completed ? 'Basics saved' : 'Quick rules primer',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  completed
                      ? 'You’ve already cleared the starter walkthrough marker for Color Clash.'
                      : 'Review the core cards, remember that the server is authoritative, and mark the tutorial as understood.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: completed
                      ? OutlinedButton(
                          onPressed: null,
                          child: const Text('Completed'),
                        )
                      : FilledButton(
                          onPressed: onAcknowledge,
                          child: const Text('Mark basics learned'),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveMatchCard extends StatelessWidget {
  const _ActiveMatchCard({required this.activeMatch});

  final ColorClashHomeActiveMatchModel activeMatch;

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
            activeMatch.tableMode.replaceAll('_', ' ').toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Live on round ${activeMatch.publicState?.roundNumber ?? 1}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: activeMatch.players
                .map(
                  (player) => _TinyPill(
                    label: 'Seat ${player.seatIndex + 1} • ${player.username}',
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _ColorClashEmptyCard extends StatelessWidget {
  const _ColorClashEmptyCard({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _TinyPill extends StatelessWidget {
  const _TinyPill({
    required this.label,
    this.tone = AppColors.primaryBlue,
  });

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tone,
            ),
      ),
    );
  }
}
