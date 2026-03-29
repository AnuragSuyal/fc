import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/color_clash_session_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/color_clash/color_clash_status_banner.dart';
import '../../widgets/rounded_scaffold.dart';
import 'color_clash_table_screen.dart';

class ColorClashMatchmakingScreen extends StatefulWidget {
  const ColorClashMatchmakingScreen({
    super.key,
    this.mode,
    this.stakeAmount,
    this.themePackId,
  });

  static const String routeName = '/games/color-clash/matchmaking';

  final String? mode;
  final int? stakeAmount;
  final String? themePackId;

  @override
  State<ColorClashMatchmakingScreen> createState() =>
      _ColorClashMatchmakingScreenState();
}

class _ColorClashMatchmakingScreenState
    extends State<ColorClashMatchmakingScreen> {
  String? _mode;
  int? _stakeAmount;
  String? _themePackId;
  String? _lastPendingTargetKey;
  bool _requestedJoin = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _mode ??= widget.mode ?? args?['mode']?.toString() ?? 'casual_free';
    _stakeAmount ??= args?['stakeAmount'] is int
        ? args!['stakeAmount'] as int
        : int.tryParse('${args?['stakeAmount'] ?? widget.stakeAmount ?? 0}') ??
            0;
    _themePackId ??= widget.themePackId ??
        args?['themePackId']?.toString() ??
        'forest_picnic';

    if (!_requestedJoin) {
      _requestedJoin = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = context.read<ColorClashSessionController>();
        controller.trackUiEvent(
          'matchmaking_screen_opened',
          payload: <String, Object?>{
            'mode': _mode,
            'stakeAmount': _stakeAmount,
          },
        );
        controller.joinMatchmaking(
          mode: _mode!,
          stakeAmount: _stakeAmount,
          themePackId: _themePackId,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ColorClashSessionController>();
    _maybeHandlePendingTarget(controller);
    final state = controller.matchmakingState;
    final mood = context.mood;

    return RoundedScaffold(
      title: 'Finding a Table',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          children: [
            if (controller.statusNotice != null)
              ColorClashStatusBanner(
                notice: controller.statusNotice!,
                onDismiss: controller.clearStatusNotice,
              ),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primaryBlue,
                    mood.berry,
                    AppColors.secondaryBlue,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _modeLabel(_mode ?? state.mode ?? 'casual_free'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (_stakeAmount ?? state.stakeAmount) > 0
                        ? '${_stakeAmount ?? state.stakeAmount} gold entry • $_themePackId'
                        : 'Free queue • ${(_themePackId ?? 'forest_picnic').replaceAll('_', ' ')}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: mood.outlineSoft),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _QueueStageIcon(stage: state.stage),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _stageTitle(state.stage),
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _stageMessage(state),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    if (state.estimatedWaitMs != null &&
                        state.stage == ColorClashQueueStage.queued)
                      _InfoRow(
                        label: 'Estimated wait',
                        value: '${(state.estimatedWaitMs! / 1000).ceil()} sec',
                      ),
                    if ((state.queueTicketId ?? '').isNotEmpty)
                      _InfoRow(
                        label: 'Queue ticket',
                        value: state.queueTicketId!,
                      ),
                    _InfoRow(
                      label: 'Theme pack',
                      value: (_themePackId ?? 'forest_picnic')
                          .replaceAll('_', ' '),
                    ),
                    const Spacer(),
                    if ((state.errorMessage ?? '').isNotEmpty) ...[
                      Text(
                        state.errorMessage!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.errorRed,
                            ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: state.stage == ColorClashQueueStage.joining
                            ? null
                            : () async {
                                final navigator = Navigator.of(context);
                                await controller.leaveMatchmaking();
                                if (!context.mounted) return;
                                navigator.maybePop();
                              },
                        child: Text(
                          state.stage == ColorClashQueueStage.matched
                              ? 'Joining table'
                              : 'Cancel queue',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _maybeHandlePendingTarget(ColorClashSessionController controller) {
    final target = controller.pendingMatchTarget;
    if (target == null) return;
    final key = '${target.roomId}:${target.matchId}:${target.source}';
    if (_lastPendingTargetKey == key) return;
    _lastPendingTargetKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.consumePendingMatchTarget();
      Navigator.of(context).pushReplacementNamed(
        ColorClashTableScreen.routeName,
        arguments: <String, dynamic>{
          'matchId': target.matchId,
          'roomId': target.roomId,
        },
      );
    });
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'gold_stake':
        return 'Gold Stake Queue';
      case 'ranked':
        return 'Ranked Queue';
      default:
        return 'Casual Queue';
    }
  }

  String _stageTitle(ColorClashQueueStage stage) {
    switch (stage) {
      case ColorClashQueueStage.joining:
        return 'Entering queue';
      case ColorClashQueueStage.queued:
        return 'Searching for players';
      case ColorClashQueueStage.matched:
        return 'Match found';
      case ColorClashQueueStage.leaving:
        return 'Leaving queue';
      case ColorClashQueueStage.error:
        return 'Queue paused';
      case ColorClashQueueStage.idle:
        return 'Queue ready';
    }
  }

  String _stageMessage(ColorClashMatchmakingState state) {
    switch (state.stage) {
      case ColorClashQueueStage.joining:
        return 'We’re reserving your spot and checking the backend queue.';
      case ColorClashQueueStage.queued:
        return 'Stay here while the realtime layer waits for a compatible Color Clash table.';
      case ColorClashQueueStage.matched:
        return 'A match was formed. We’re syncing your room and reconnect-safe match session now.';
      case ColorClashQueueStage.leaving:
        return 'Removing you from the queue cleanly.';
      case ColorClashQueueStage.error:
        return state.errorMessage ?? 'The queue hit a temporary issue.';
      case ColorClashQueueStage.idle:
        return 'Choose a queue from the Color Clash home screen.';
    }
  }
}

class _QueueStageIcon extends StatelessWidget {
  const _QueueStageIcon({required this.stage});

  final ColorClashQueueStage stage;

  @override
  Widget build(BuildContext context) {
    final icon = switch (stage) {
      ColorClashQueueStage.joining => Icons.sync_rounded,
      ColorClashQueueStage.queued => Icons.radar_rounded,
      ColorClashQueueStage.matched => Icons.check_circle_rounded,
      ColorClashQueueStage.leaving => Icons.logout_rounded,
      ColorClashQueueStage.error => Icons.error_outline_rounded,
      ColorClashQueueStage.idle => Icons.play_circle_outline_rounded,
    };
    final color = switch (stage) {
      ColorClashQueueStage.error => AppColors.errorRed,
      ColorClashQueueStage.matched => AppColors.successGreen,
      _ => AppColors.primaryBlue,
    };

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
