import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/room_model.dart';
import '../../providers/active_room_session_controller.dart';
import '../../screens/rooms/room_detail_screen.dart';
import '../../services/app_navigation_service.dart';
import '../../utils/media_url.dart';

class FloatingRoomOverlay extends StatefulWidget {
  const FloatingRoomOverlay({super.key});

  @override
  State<FloatingRoomOverlay> createState() => _FloatingRoomOverlayState();
}

class _FloatingRoomOverlayState extends State<FloatingRoomOverlay> {
  Offset _offset = const Offset(18, 116);

  @override
  Widget build(BuildContext context) {
    return Consumer<ActiveRoomSessionController>(
      builder: (context, controller, _) {
        final room = controller.activeRoom;
        if (!controller.showFloatingEntry || room == null) {
          return const SizedBox.shrink();
        }

        final mediaSize = MediaQuery.of(context).size;
        final safePadding = MediaQuery.of(context).padding;
        final right = _offset.dx.clamp(12.0, mediaSize.width - 148.0);
        final bottom = _offset.dy.clamp(96.0, mediaSize.height - 160.0) +
            safePadding.bottom;

        return Positioned(
          right: right,
          bottom: bottom,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _offset = Offset(
                  (_offset.dx - details.delta.dx).clamp(12.0, mediaSize.width),
                  (_offset.dy - details.delta.dy).clamp(96.0, mediaSize.height),
                );
              });
            },
            child: _FloatingRoomPill(
              room: room,
              onOpen: controller.isResumingRoom
                  ? null
                  : () => _openRoom(controller, room),
              onClose: () => _confirmLeave(controller),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openRoom(
    ActiveRoomSessionController controller,
    RoomModel room,
  ) async {
    if (!controller.beginRoomResume()) return;

    try {
      await appNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
      );
    } finally {
      controller.finishRoomResumeAttempt();
    }
  }

  Future<void> _confirmLeave(ActiveRoomSessionController controller) async {
    final shouldLeave = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
            color: const Color(0xF010121B),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Leave room completely?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This will disconnect the live room session and remove the floating room shortcut.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.68),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('Stay connected'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5D6C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('Leave room'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (shouldLeave == true) {
      await controller.leaveBackgroundRoom();
    }
  }
}

class _FloatingRoomPill extends StatelessWidget {
  const _FloatingRoomPill({
    required this.room,
    required this.onOpen,
    required this.onClose,
  });

  final RoomModel room;
  final VoidCallback? onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: 138,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
                color: const Color(0xD9111320),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onOpen,
                          child: Row(
                            children: [
                              _RoomArtwork(room: room),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      room.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF45E08E),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Expanded(
                                          child: Text(
                                            'Return to room',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: onClose,
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomArtwork extends StatelessWidget {
  const _RoomArtwork({required this.room});

  final RoomModel room;

  @override
  Widget build(BuildContext context) {
    final imageUrl = _resolveRoomImage(room);

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        gradient: const LinearGradient(
          colors: [Color(0xFF2F3A70), Color(0xFF171D3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipOval(
        child: imageUrl != null
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _FallbackArtwork(room: room),
              )
            : _FallbackArtwork(room: room),
      ),
    );
  }

  String? _resolveRoomImage(RoomModel room) {
    final candidates = [room.coverImage, room.hostAvatar];
    for (final candidate in candidates) {
      final resolved = resolveMediaUrl(candidate);
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }
    return null;
  }
}

class _FallbackArtwork extends StatelessWidget {
  const _FallbackArtwork({required this.room});

  final RoomModel room;

  @override
  Widget build(BuildContext context) {
    final initials = room.name.trim().isEmpty
        ? 'RM'
        : room.name
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((part) => part.isEmpty ? '' : part[0].toUpperCase())
            .join();

    return Container(
      alignment: Alignment.center,
      color: const Color(0xFF1B2040),
      child: Text(
        initials.isEmpty ? 'RM' : initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
