import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/socket_service.dart';

class RoomFeatureBottomSheet extends StatelessWidget {
  final String roomId;
  final VoidCallback? onOpenGoldenDragon;
  final bool canActivateGoldenDragon;
  final int goldenDragonAvailableCount;
  final String? goldenDragonDisabledReason;

  const RoomFeatureBottomSheet({
    super.key,
    required this.roomId,
    this.onOpenGoldenDragon,
    this.canActivateGoldenDragon = false,
    this.goldenDragonAvailableCount = 0,
    this.goldenDragonDisabledReason,
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

  void _openGoldenDragon(BuildContext context) {
    if (!canActivateGoldenDragon || onOpenGoldenDragon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            goldenDragonDisabledReason ??
                'Only hosts and room admins can launch Golden Dragon here.',
          ),
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
    onOpenGoldenDragon?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
        decoration: const BoxDecoration(
          color: Color(0xFF17161F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SingleChildScrollView(
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
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => _openGoldenDragon(context),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: canActivateGoldenDragon ? 1 : 0.72,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          Color(0xFFF97316),
                          Color(0xFFDC2626),
                          Color(0xFF7F1D1D),
                        ],
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color:
                              const Color(0xFFF97316).withValues(alpha: 0.24),
                          blurRadius: 24,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Row(
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            'assets/images/golden_dragon_icon.png',
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Golden Dragon',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                canActivateGoldenDragon
                                    ? 'Start a 10-second premium room rush. Fastest tappers pull a bigger share.'
                                    : (goldenDragonDisabledReason ??
                                        'Only hosts and moderators can activate this premium room event.'),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.84),
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  _tag(
                                    goldenDragonAvailableCount > 0
                                        ? '$goldenDragonAvailableCount ready'
                                        : 'Buy 199 / 499 / 999 INR',
                                  ),
                                  _tag('Real-time tap race'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
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
                                color:
                                    feature.colors.last.withValues(alpha: 0.35),
                                blurRadius: 16,
                                spreadRadius: -6,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(
                            feature.icon,
                            color: Colors.white,
                            size: 30,
                          ),
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
        ),
      ),
    );
  }
}

Widget _tag(String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
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
