import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/color_clash_session_controller.dart';
import '../../utils/constants.dart';
import '../../widgets/color_clash/color_clash_status_banner.dart';
import '../../widgets/rounded_scaffold.dart';
import 'color_clash_table_screen.dart';

class ColorClashReconnectScreen extends StatefulWidget {
  const ColorClashReconnectScreen({
    super.key,
    this.matchId,
    this.roomId,
  });

  static const String routeName = '/games/color-clash/reconnect';

  final String? matchId;
  final String? roomId;

  @override
  State<ColorClashReconnectScreen> createState() =>
      _ColorClashReconnectScreenState();
}

class _ColorClashReconnectScreenState extends State<ColorClashReconnectScreen> {
  String? _matchId;
  String? _roomId;
  bool _requested = false;
  bool _forwarded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _matchId ??= widget.matchId ?? args?['matchId']?.toString();
    _roomId ??= widget.roomId ?? args?['roomId']?.toString();

    if (!_requested && (_matchId ?? '').isNotEmpty) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final controller = context.read<ColorClashSessionController>();
        controller.trackUiEvent(
          'reconnect_screen_opened',
          payload: <String, Object?>{
            'matchId': _matchId,
            'roomId': _roomId,
          },
        );
        await controller.reconnectMatch(_matchId!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ColorClashSessionController>();
    final reconnect = controller.reconnectState;
    final snapshot = controller.matchSnapshot;

    return RoundedScaffold(
      title: 'Reconnect Match',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Builder(
          builder: (context) {
            if ((_matchId ?? '').isEmpty) {
              return const _ReconnectMessage(
                title: 'No active match',
                message:
                    'A match id is required before Color Clash can recover session state.',
              );
            }

            if (reconnect.status == ColorClashReconnectStatus.reconnecting &&
                (snapshot == null || snapshot.matchId != _matchId)) {
              return const Center(child: CircularProgressIndicator());
            }

            if (reconnect.status == ColorClashReconnectStatus.failed) {
              return _ReconnectMessage(
                title: 'Reconnect failed',
                message:
                    reconnect.message ?? controller.matchError ?? 'Try again.',
                actionLabel: 'Retry',
                onPressed: () async {
                  if ((_matchId ?? '').isEmpty) return;
                  await controller.reconnectMatch(_matchId!);
                },
              );
            }

            if (snapshot == null || snapshot.matchId != _matchId) {
              return _ReconnectMessage(
                title: 'Waiting for match sync',
                message:
                    'The backend has not returned a match snapshot yet. Try again in a moment.',
                actionLabel: 'Retry',
                onPressed: () async {
                  if ((_matchId ?? '').isEmpty) return;
                  await controller.reconnectMatch(_matchId!);
                },
              );
            }

            if (!_forwarded) {
              _forwarded = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                Navigator.of(context).pushReplacementNamed(
                  ColorClashTableScreen.routeName,
                  arguments: <String, dynamic>{
                    'matchId': _matchId,
                    'roomId': _roomId,
                  },
                );
              });
            }

            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.statusNotice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ColorClashStatusBanner(
                        notice: controller.statusNotice!,
                        onDismiss: controller.clearStatusNotice,
                      ),
                    ),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.sync_rounded,
                      color: AppColors.primaryBlue,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Opening table',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The backend snapshot is ready. Moving you into the live Color Clash table now.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  const CircularProgressIndicator(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReconnectMessage extends StatelessWidget {
  const _ReconnectMessage({
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
            const SizedBox(height: 10),
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
