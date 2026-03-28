import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/socket_service.dart';

class RoomFeatureOverlay extends StatefulWidget {
  final String roomId;

  const RoomFeatureOverlay({
    super.key,
    required this.roomId,
  });

  @override
  State<RoomFeatureOverlay> createState() => _RoomFeatureOverlayState();
}

class _RoomFeatureOverlayState extends State<RoomFeatureOverlay> {
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _hideTimer;
  Map<String, dynamic>? _activeEvent;

  @override
  void initState() {
    super.initState();
    _subscription = SocketService.roomFeatureStream.listen((data) {
      if (data['roomId']?.toString() != widget.roomId || !mounted) {
        return;
      }

      _hideTimer?.cancel();
      setState(() {
        _activeEvent = Map<String, dynamic>.from(data);
      });

      _hideTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() {
          _activeEvent = null;
        });
      });
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = _activeEvent;
    final featureId = event?['featureId']?.toString() ?? '';
    final accent = _accentFor(featureId);
    final icon = _iconFor(featureId);
    final featureName = event?['featureName']?.toString() ?? 'Room Feature';
    final actorName = _actorNameFor(event);

    return IgnorePointer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 92, 16, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.12),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: event == null
                  ? const SizedBox.shrink()
                  : Container(
                      key: ValueKey(
                        '${event['featureId']}-${event['triggeredAt'] ?? ''}',
                      ),
                      constraints: const BoxConstraints(maxWidth: 360),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accent.withValues(alpha: 0.96),
                            Colors.black.withValues(alpha: 0.94),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.28),
                            blurRadius: 26,
                            spreadRadius: -10,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  icon,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      featureName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Started by $actorName',
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.72),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildEventBody(event),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEventBody(Map<String, dynamic> event) {
    final winnerName = event['winner']?['username']?.toString();
    final numbers = event['numbers'] is List
        ? (event['numbers'] as List).map((value) => '$value').toList()
        : const <String>[];
    final luckyNumber = event['luckyNumber'];
    final detail = event['detail']?.toString() ?? '';

    if (winnerName != null && winnerName.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            winnerName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
        ],
      );
    }

    if (numbers.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final number in numbers)
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    number.padLeft(2, '0'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              detail,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      );
    }

    if (luckyNumber != null) {
      return Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$luckyNumber'.padLeft(2, '0'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              detail,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ),
        ],
      );
    }

    return Text(
      detail,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.8),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  IconData _iconFor(String featureId) {
    switch (featureId) {
      case 'aura_pick':
        return Icons.palette_rounded;
      case 'crown_drop':
        return Icons.workspace_premium_rounded;
      case 'number_rush':
        return Icons.grid_4x4_rounded;
      case 'fortune_digits':
        return Icons.blur_circular_rounded;
      default:
        return Icons.auto_awesome_rounded;
    }
  }

  Color _accentFor(String featureId) {
    switch (featureId) {
      case 'aura_pick':
        return const Color(0xFFFF7A9C);
      case 'crown_drop':
        return const Color(0xFFFFA44E);
      case 'number_rush':
        return const Color(0xFF5E7DFF);
      case 'fortune_digits':
        return const Color(0xFF2CB67D);
      default:
        return const Color(0xFF8C52FF);
    }
  }

  String _actorNameFor(Map<String, dynamic>? event) {
    final actor = event?['actor'];
    if (actor is Map<String, dynamic>) {
      final name = actor['username']?.toString().trim() ?? '';
      if (name.isNotEmpty) {
        return name;
      }
    }
    return 'Someone';
  }
}
