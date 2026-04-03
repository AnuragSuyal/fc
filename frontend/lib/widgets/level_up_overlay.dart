import 'dart:async';

import 'package:flutter/material.dart';

import '../services/level_up_celebration_service.dart';
import 'level_badge.dart';

class LevelUpOverlayHost extends StatefulWidget {
  const LevelUpOverlayHost({super.key});

  @override
  State<LevelUpOverlayHost> createState() => _LevelUpOverlayHostState();
}

class _LevelUpOverlayHostState extends State<LevelUpOverlayHost> {
  StreamSubscription<LevelUpCelebration?>? _subscription;
  LevelUpCelebration? _active;

  @override
  void initState() {
    super.initState();
    _subscription = LevelUpCelebrationService.stream.listen((celebration) {
      if (!mounted) return;
      setState(() => _active = celebration);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final celebration = _active;
    if (celebration == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: true,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              child: Container(
                key: ValueKey<String>(celebration.id),
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: LinearGradient(
                    colors: celebration.milestoneTierChanged
                        ? const [Color(0xFF21160E), Color(0xFF090B0F)]
                        : const [Color(0xFF181B20), Color(0xFF090A0D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    LevelBadge(
                      level: celebration.newLevel,
                      levelInfo: celebration.levelInfo,
                      size: LevelBadgeSize.large,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            celebration.milestoneTierChanged
                                ? 'Milestone unlocked'
                                : 'Level up',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            celebration.milestoneTierChanged
                                ? 'Level ${celebration.newLevel} reached a new badge tier.'
                                : 'You moved from level ${celebration.previousLevel} to ${celebration.newLevel}.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (celebration.xpGained > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              '+${celebration.xpGained} XP',
                              style: const TextStyle(
                                color: Color(0xFFFFD166),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ],
                      ),
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
