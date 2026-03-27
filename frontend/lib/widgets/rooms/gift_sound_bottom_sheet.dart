import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/socket_service.dart';

class GiftSoundBottomSheet extends StatelessWidget {
  final String roomId;
  final int seatIndex;

  const GiftSoundBottomSheet({
    super.key,
    required this.roomId,
    this.seatIndex = -1,
  });

  static const List<Map<String, dynamic>> _sounds = [
    {'id': 'clap', 'name': 'Clap', 'icon': '👏', 'color': Color(0xFFFFD54F)},
    {'id': 'laugh', 'name': 'Laugh', 'icon': '😂', 'color': Color(0xFF81C784)},
    {'id': 'cheer', 'name': 'Cheer', 'icon': '🎉', 'color': Color(0xFF64B5F6)},
    {'id': 'wow', 'name': 'Wow', 'icon': '😮', 'color': Color(0xFFBA68C8)},
    {'id': 'kick', 'name': 'Kick', 'icon': '🔥', 'color': Color(0xFFE57373)},
    {'id': 'bell', 'name': 'Bell', 'icon': '🔔', 'color': Color(0xFFFFB74D)},
    {
      'id': 'whistle',
      'name': 'Whistle',
      'icon': '🎵',
      'color': Color(0xFF4DB6AC)
    },
    {
      'id': 'airhorn',
      'name': 'Airhorn',
      'icon': '📣',
      'color': Color(0xFFF06292)
    },
  ];

  void _sendSound(BuildContext context, String soundId, String name) {
    HapticFeedback.mediumImpact();
    SocketService.sendSoundEffect(
      roomId: roomId,
      soundId: soundId,
      seatIndex: seatIndex >= 0 ? seatIndex : null,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Played $name for the room'),
        duration: const Duration(milliseconds: 700),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.blueAccent.withValues(alpha: 0.9),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF17161F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Room Soundboard',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Play a quick audio reaction that everyone in the room hears.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 18),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 0.82,
            ),
            itemCount: _sounds.length,
            itemBuilder: (context, index) {
              final sound = _sounds[index];
              final color = sound['color'] as Color;
              return GestureDetector(
                onTap: () =>
                    _sendSound(context, sound['id'] as String, sound['name']),
                child: Column(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Center(
                        child: Text(
                          sound['icon'] as String,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sound['name'] as String,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
