import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/room_service.dart';
import 'room_detail_screen.dart';

class MyRoomEntryScreen extends StatefulWidget {
  const MyRoomEntryScreen({super.key});

  static const routeName = '/rooms/my-room';
  static Future<void>? _launchFuture;

  static Future<void> open(
    BuildContext context, {
    bool replace = false,
  }) {
    final pendingLaunch = _launchFuture;
    if (pendingLaunch != null) {
      return pendingLaunch;
    }

    final route = MaterialPageRoute<void>(
      builder: (_) => const MyRoomEntryScreen(),
      settings: const RouteSettings(name: routeName),
    );
    final navigator = Navigator.of(context);
    final launch = replace ? navigator.pushReplacement(route) : navigator.push(route);
    _launchFuture = launch.whenComplete(() {
      if (identical(_launchFuture, launch)) {
        _launchFuture = null;
      }
    });
    return _launchFuture!;
  }

  @override
  State<MyRoomEntryScreen> createState() => _MyRoomEntryScreenState();
}

class _MyRoomEntryScreenState extends State<MyRoomEntryScreen> {
  Future<void>? _resolveFuture;
  String? _error;
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveFuture ??= _resolveAndOpenRoom();
    });
  }

  Future<void> _resolveAndOpenRoom() async {
    setState(() => _error = null);

    try {
      final authProvider = context.read<AuthProvider>();
      final cachedRoomId = authProvider.user?.permanentRoomId;
      final resolution = await RoomService.resolveMyRoom(
        cachedRoomId: cachedRoomId,
      );

      if (!mounted) return;
      final room = resolution?.room;
      if (room == null) {
        throw Exception('Could not open your room right now.');
      }

      authProvider.cachePermanentRoom(room.id);
      if (_didNavigate) return;
      _didNavigate = true;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RoomDetailScreen(room: room),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error);
        _resolveFuture = null;
      });
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    final normalized = message.toLowerCase();
    if (normalized.contains('unexpected token \'<\'') ||
        normalized.contains('<!doctype') ||
        normalized.contains('<html')) {
      return 'Could not open your room right now. Please try again.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF08080C),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF12131A),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.26),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF69DFFF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.home_work_rounded,
                        color: Color(0xFF69DFFF),
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Opening My Room',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error ??
                          'We are taking you to your permanent room. First-time accounts will get a room automatically.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_error == null)
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    else
                      Row(
                        children: [
                          FilledButton(
                            onPressed: () {
                              setState(() {
                                _resolveFuture = _resolveAndOpenRoom();
                              });
                            },
                            child: const Text('Retry'),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () => Navigator.maybePop(context),
                            child: const Text('Back'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
