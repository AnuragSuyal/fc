import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/color_clash_table_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/color_clash_session_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/color_clash/color_clash_status_banner.dart';
import '../../widgets/rounded_scaffold.dart';
import '../../widgets/user_avatar.dart';
import 'color_clash_table_screen.dart';

class ColorClashLobbyScreen extends StatefulWidget {
  const ColorClashLobbyScreen({
    super.key,
    this.roomId,
  });

  static const String routeName = '/games/color-clash/lobby';

  final String? roomId;

  @override
  State<ColorClashLobbyScreen> createState() => _ColorClashLobbyScreenState();
}

class _ColorClashLobbyScreenState extends State<ColorClashLobbyScreen> {
  String? _roomId;
  String? _lastPendingTargetKey;
  Timer? _countdownTicker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _roomId ??= widget.roomId ?? args?['roomId']?.toString();
    if ((_roomId ?? '').isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = context.read<ColorClashSessionController>();
      controller.trackUiEvent(
        'lobby_screen_opened',
        payload: <String, Object?>{'roomId': _roomId},
      );
      await controller.loadLobby(_roomId!, force: true);
      await controller.subscribeLobby(_roomId!);
    });
  }

  @override
  void initState() {
    super.initState();
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ColorClashSessionController>();
    final auth = context.watch<AuthProvider>();
    _maybeHandlePendingTarget(controller);

    final session = controller.lobbySession;
    final room = session?.room;
    final lobby = session?.lobby;
    final currentUserId = auth.user?.id ?? '';
    final currentPlayer = lobby?.playersByUserId[currentUserId];
    final isHost = room?.host?.userId == currentUserId;

    return RoundedScaffold(
      title: room?.name ?? 'Color Clash Lobby',
      actions: [
        if (isHost)
          IconButton(
            tooltip: 'Cancel room',
            onPressed: () async {
              final navigator = Navigator.of(context);
              final success = await controller.cancelRoom();
              if (!context.mounted || !success) return;
              navigator.maybePop();
            },
            icon: const Icon(Icons.close_rounded),
          ),
      ],
      body: Builder(
        builder: (context) {
          if (controller.isLobbyLoading && session == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (controller.lobbyError != null && session == null) {
            return _LobbyMessageCard(
              title: 'Lobby unavailable',
              message: controller.lobbyError!,
              actionLabel: 'Retry',
              onPressed: () async {
                if ((_roomId ?? '').isEmpty) return;
                await controller.loadLobby(_roomId!, force: true);
              },
            );
          }
          if (session == null || room == null || lobby == null) {
            return const _LobbyMessageCard(
              title: 'No lobby yet',
              message:
                  'Create a friend room or join an existing Color Clash room first.',
            );
          }

          final countdownSeconds = lobby.countdownEndsAt == null
              ? null
              : ((lobby.countdownEndsAt! -
                          DateTime.now().millisecondsSinceEpoch) /
                      1000)
                  .ceil()
                  .clamp(0, 999);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              if (controller.statusNotice != null)
                ColorClashStatusBanner(
                  notice: controller.statusNotice!,
                  onDismiss: controller.clearStatusNotice,
                ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: context.mood.outlineSoft),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                room.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${room.visibility} • ${room.themePackId.colorClashThemeLabel}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        if (countdownSeconds != null)
                          _CountdownBadge(seconds: countdownSeconds),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _LobbyPill(label: 'Status: ${lobby.status}'),
                        _LobbyPill(label: '${lobby.readyPlayers.length} ready'),
                        _LobbyPill(label: '${lobby.spectatorCount} spectators'),
                        if (room.isPaidTable)
                          _LobbyPill(
                            label: '${room.stake.entryFee} gold',
                            tone: AppColors.warningOrange,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Player seats',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: lobby.maxPlayers,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.28,
                ),
                itemBuilder: (context, index) {
                  final userId = lobby.seats[index];
                  final seatedPlayer =
                      userId == null ? null : lobby.playersByUserId[userId];
                  final isCurrentSeat = seatedPlayer?.userId == currentUserId;
                  final canTakeSeat =
                      userId == null && session.viewerRole != 'spectator';

                  return InkWell(
                    onTap: canTakeSeat
                        ? () =>
                            controller.setReady(ready: true, seatIndex: index)
                        : null,
                    borderRadius: BorderRadius.circular(26),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: isCurrentSeat
                              ? AppColors.primaryBlue
                              : context.mood.outlineSoft,
                          width: isCurrentSeat ? 1.6 : 1,
                        ),
                      ),
                      child: seatedPlayer == null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundWhite,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(Icons.add_rounded),
                                ),
                                const Spacer(),
                                Text(
                                  'Seat ${index + 1}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  canTakeSeat ? 'Tap to sit here' : 'Open seat',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    UserAvatar(
                                      imageUrl: seatedPlayer.avatar,
                                      username: seatedPlayer.username,
                                      radius: 20,
                                    ),
                                    const Spacer(),
                                    Icon(
                                      seatedPlayer.ready
                                          ? Icons.check_circle_rounded
                                          : Icons.timelapse_rounded,
                                      color: seatedPlayer.ready
                                          ? AppColors.successGreen
                                          : AppColors.warningOrange,
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Text(
                                  seatedPlayer.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Seat ${index + 1} • ${seatedPlayer.ready ? 'Ready' : 'Waiting'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              if (currentPlayer != null && !currentPlayer.isSpectator)
                _ActionPanel(
                  title: currentPlayer.ready
                      ? 'You are ready'
                      : currentPlayer.hasSeat
                          ? 'Seat locked in'
                          : 'Pick an open seat',
                  subtitle: currentPlayer.ready
                      ? 'Stay here while the backend countdown and sockets keep the lobby in sync.'
                      : currentPlayer.hasSeat
                          ? 'Tap ready when you want the countdown to include you.'
                          : 'Open seats can be claimed by tapping any empty card above.',
                  buttonLabel: currentPlayer.ready ? 'Unready' : 'Set ready',
                  onPressed: currentPlayer.hasSeat
                      ? () => controller.setReady(
                            ready: !currentPlayer.ready,
                            seatIndex: currentPlayer.seatIndex,
                          )
                      : null,
                )
              else
                _ActionPanel(
                  title: session.viewerRole == 'spectator'
                      ? 'Spectator view'
                      : 'Waiting for your seat',
                  subtitle: session.viewerRole == 'spectator'
                      ? 'You are watching the lobby only. Spectator gameplay stays read-only and hidden state remains private.'
                      : 'Pick any open seat above to join the player lineup.',
                  buttonLabel: 'Refresh lobby',
                  onPressed: () async {
                    if ((_roomId ?? '').isEmpty) return;
                    await controller.loadLobby(_roomId!, force: true);
                  },
                ),
              const SizedBox(height: 18),
              Text(
                'People in this room',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              ...lobby.orderedPlayers.map(
                (player) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: context.mood.outlineSoft),
                    ),
                    child: Row(
                      children: [
                        UserAvatar(
                          imageUrl: player.avatar,
                          username: player.username,
                          radius: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                player.username,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                player.isSpectator
                                    ? 'Spectator'
                                    : 'Seat ${((player.seatIndex ?? -1) + 1).clamp(0, 99)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (player.ready)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.successGreen,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _maybeHandlePendingTarget(ColorClashSessionController controller) {
    final target = controller.pendingMatchTarget;
    if (target == null || target.roomId != _roomId) return;
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
}

class _LobbyPill extends StatelessWidget {
  const _LobbyPill({
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

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$seconds s',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onPressed;

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
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onPressed,
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _LobbyMessageCard extends StatelessWidget {
  const _LobbyMessageCard({
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
