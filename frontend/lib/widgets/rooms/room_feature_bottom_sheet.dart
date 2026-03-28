import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/socket_service.dart';

class RoomFeatureBottomSheet extends StatelessWidget {
  final String roomId;

  const RoomFeatureBottomSheet({
    super.key,
    required this.roomId,
  });

  static const List<_RoomFeatureAction> _features = [
    _RoomFeatureAction(
      id: 'aura_pick',
      label: 'Aura Pick',
      subtitle: 'Spotlight one live listener',
      icon: Icons.palette_rounded,
      colors: [Color(0xFFFFA36C), Color(0xFFFF7A9C)],
    ),
    _RoomFeatureAction(
      id: 'crown_drop',
      label: 'Crown Drop',
      subtitle: 'Crown the live standout',
      icon: Icons.workspace_premium_rounded,
      colors: [Color(0xFFFFD86F), Color(0xFFFF8C42)],
    ),
    _RoomFeatureAction(
      id: 'number_rush',
      label: 'Number Rush',
      subtitle: 'Push a synced number board',
      icon: Icons.grid_4x4_rounded,
      colors: [Color(0xFF8D8BFF), Color(0xFF52A1FF)],
    ),
    _RoomFeatureAction(
      id: 'fortune_digits',
      label: 'Fortune Digits',
      subtitle: 'Drop one lucky room number',
      icon: Icons.blur_circular_rounded,
      colors: [Color(0xFF7CE38B), Color(0xFF2CB67D)],
    ),
  ];

  void _triggerFeature(BuildContext context, _RoomFeatureAction feature) {
    HapticFeedback.mediumImpact();
    SocketService.triggerRoomFeature(
      roomId: roomId,
      featureId: feature.id,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${feature.label} is live for the room'),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
        backgroundColor: feature.colors.first.withValues(alpha: 0.92),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
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
            'Live Room Features',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Trigger shared room moments everyone can see in realtime.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 18),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
              childAspectRatio: 0.72,
            ),
            itemCount: _features.length,
            itemBuilder: (context, index) {
              final feature = _features[index];
              return GestureDetector(
                onTap: () => _triggerFeature(context, feature),
                child: Column(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: feature.colors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: feature.colors.last.withValues(alpha: 0.35),
                            blurRadius: 16,
                            spreadRadius: -6,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(feature.icon, color: Colors.white, size: 30),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      feature.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feature.subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 9.5,
                        height: 1.2,
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

class _RoomFeatureAction {
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;

  const _RoomFeatureAction({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.colors,
  });
}
