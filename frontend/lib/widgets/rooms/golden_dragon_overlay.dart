import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/golden_dragon_model.dart';
import '../../providers/golden_dragon_session_controller.dart';

class GoldenDragonOverlay extends StatefulWidget {
  const GoldenDragonOverlay({
    super.key,
    required this.controller,
    required this.visible,
    this.onClose,
  });

  final GoldenDragonSessionController controller;
  final bool visible;
  final VoidCallback? onClose;

  @override
  State<GoldenDragonOverlay> createState() => _GoldenDragonOverlayState();
}

class _GoldenDragonOverlayState extends State<GoldenDragonOverlay>
    with TickerProviderStateMixin {
  final List<_TapBurstModel> _bursts = <_TapBurstModel>[];
  int _burstSeed = 0;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: widget.visible ? 1 : 0,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final result = widget.controller.result;
            final event = widget.controller.activeEvent;
            if (result == null && event == null) {
              return const SizedBox.shrink();
            }

            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _buildBackdrop(),
                if (event != null && result == null) _buildLiveEvent(event),
                if (result != null) _buildResult(result),
                ..._bursts.map(_buildBurst),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBackdrop() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.1),
          radius: 1.05,
          colors: <Color>[
            const Color(0xFFB91C1C).withValues(alpha: 0.34),
            const Color(0xFF4A0B0B).withValues(alpha: 0.64),
            Colors.black.withValues(alpha: 0.86),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: -40,
            top: 120,
            child: _glowOrb(const Color(0xFFFF6A00), 160),
          ),
          Positioned(
            right: -60,
            top: 84,
            child: _glowOrb(const Color(0xFFFFD166), 180),
          ),
          Positioned(
            left: 40,
            bottom: 120,
            child: _glowOrb(const Color(0xFFEF4444), 140),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveEvent(GoldenDragonLiveEvent event) {
    final remainingSeconds = (widget.controller.remainingMs / 1000).ceil();
    final topClaimants = widget.controller.topClaimants.take(3).toList();
    final myTaps = widget.controller.myAcceptedTapCount;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        child: Column(
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _buildLiveHeader(
                    event: event,
                    remainingSeconds: remainingSeconds,
                    myTaps: myTaps,
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (topClaimants.isNotEmpty) _buildLeaderboard(topClaimants),
            const Spacer(),
            _buildTapStage(event),
            const Spacer(),
            if ((widget.controller.lastTapAck?.riskState ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child:
                    _buildStatusBanner(widget.controller.lastTapAck!.riskState),
              ),
            Text(
              widget.controller.isTapEnabled
                  ? 'Tap the Golden Dragon fast. The server decides every counted tap.'
                  : 'Claim window is closing. Final result is syncing from the server.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.80),
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveHeader({
    required GoldenDragonLiveEvent event,
    required int remainingSeconds,
    required int myTaps,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF7F1D1D),
            Color(0xFFEF4444),
            Color(0xFFF59E0B),
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Golden Dragon',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                  ),
                ),
              ),
              _statPill(
                icon: Icons.timer_rounded,
                label: '${math.max(0, remainingSeconds)}s',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${event.packetTotalCoins} coins are live in ${event.roomName}.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.84),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _statPill(
                icon: Icons.people_alt_rounded,
                label: '${widget.controller.participantCount} tappers',
              ),
              _statPill(
                icon: Icons.touch_app_rounded,
                label: '$myTaps counted taps',
              ),
              _statPill(
                icon: Icons.local_fire_department_rounded,
                label: widget.controller.leaderboard?.hypeState
                        .replaceAll('_', ' ')
                        .toUpperCase() ??
                    'LIVE',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboard(List<GoldenDragonClaimParticipant> claimants) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFD166)),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: claimants.map((participant) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: Colors.black.withValues(alpha: 0.18),
                  ),
                  child: Text(
                    '#${participant.finalRank > 0 ? participant.finalRank : claimants.indexOf(participant) + 1} ${participant.username}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTapStage(GoldenDragonLiveEvent event) {
    final canTap = widget.controller.isTapEnabled;
    return Column(
      children: <Widget>[
        SizedBox(
          width: 280,
          height: 280,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.96, end: canTap ? 1.04 : 1.0),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeInOut,
                builder: (context, scale, child) => Transform.scale(
                  scale: scale,
                  child: child,
                ),
                child: Opacity(
                  opacity: 0.95,
                  child: Image.asset(
                    'assets/images/golden_dragon_ring.png',
                    width: 248,
                    height: 248,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                child: IgnorePointer(
                  child: Image.asset(
                    'assets/images/golden_dragon_burst.png',
                    width: 220,
                    height: 220,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              GestureDetector(
                onTap: canTap ? _handleTap : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: canTap ? 204 : 188,
                  height: canTap ? 204 : 188,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: const Color(0xFFFFB703).withValues(alpha: 0.38),
                        blurRadius: 30,
                        spreadRadius: -8,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Image.asset(
                          'assets/images/golden_dragon_icon.png',
                          fit: BoxFit.cover,
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.white.withValues(alpha: 0.10),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 18,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: Colors.black.withValues(alpha: 0.28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Text(
                    canTap ? 'Tap faster!' : 'Waiting for result...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${event.activatorName} released this packet',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildResult(GoldenDragonEventResult result) {
    final myReward = result.myClaim?.finalCoinReward ?? 0;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(34),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFF55110C),
                  Color(0xFFB91C1C),
                  Color(0xFFF59E0B),
                ],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFFF97316).withValues(alpha: 0.32),
                  blurRadius: 36,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Image.asset(
                  'assets/images/golden_dragon_winner.png',
                  width: 168,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 14),
                Text(
                  myReward > 0
                      ? 'You won $myReward coins'
                      : 'Golden Dragon settled',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  result.eventStatus == 'no_claim'
                      ? 'No valid claimants joined in time. The packet was restored to inventory.'
                      : '${result.totalDistributed} of ${result.packetTotalCoins} coins were distributed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.84),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                if (result.winners.isNotEmpty)
                  _buildWinnersTable(result.winners),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          widget.controller.dismissResult();
                          widget.onClose?.call();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF7C2D12),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(fontWeight: FontWeight.w900),
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
    );
  }

  Widget _buildWinnersTable(List<GoldenDragonClaimParticipant> winners) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.black.withValues(alpha: 0.18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: winners.take(5).map((winner) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                  child: Text(
                    '#${winner.finalRank}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    winner.username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '+${winner.finalCoinReward}',
                  style: const TextStyle(
                    color: Color(0xFFFFF1B5),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  Widget _buildStatusBanner(String riskState) {
    final label = switch (riskState) {
      'rate_limited' => 'Fast taps are being soft-throttled for fairness.',
      'tap_cap' => 'Your maximum counted taps are already locked in.',
      'flagged' => 'Your taps are being reviewed for fairness signals.',
      'duplicate_sequence' => 'Duplicate taps were ignored.',
      'not_in_room' => 'Rejoin the room to keep claiming.',
      _ => 'Golden Dragon is syncing with the server.',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _statPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.black.withValues(alpha: 0.16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowOrb(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.20),
        ),
      ),
    );
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    widget.controller.sendTap();
    final seed = _burstSeed++;
    setState(() {
      _bursts.add(_TapBurstModel(id: seed));
    });
  }

  Widget _buildBurst(_TapBurstModel burst) {
    return _TapBurst(
      key: ValueKey<int>(burst.id),
      seed: burst.id,
      onFinished: () {
        if (!mounted) return;
        setState(() {
          _bursts.removeWhere((entry) => entry.id == burst.id);
        });
      },
    );
  }
}

class _TapBurstModel {
  const _TapBurstModel({required this.id});

  final int id;
}

class _TapBurst extends StatefulWidget {
  const _TapBurst({
    super.key,
    required this.seed,
    required this.onFinished,
  });

  final int seed;
  final VoidCallback onFinished;

  @override
  State<_TapBurst> createState() => _TapBurstState();
}

class _TapBurstState extends State<_TapBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Offset _offset;

  @override
  void initState() {
    super.initState();
    final random = math.Random(widget.seed);
    _offset = Offset(
      (random.nextDouble() * 140) - 70,
      (random.nextDouble() * 140) - 70,
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
    _opacity = Tween<double>(begin: 0.9, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _scale = Tween<double>(begin: 0.6, end: 1.4).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onFinished();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Transform.translate(
              offset: _offset * _controller.value,
              child: Transform.scale(
                scale: _scale.value,
                child: Opacity(
                  opacity: _opacity.value,
                  child: Image.asset(
                    'assets/images/golden_dragon_burst.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
