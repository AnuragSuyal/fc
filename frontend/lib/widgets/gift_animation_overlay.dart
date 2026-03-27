import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/socket_service.dart';
import '../utils/constants.dart';

/// Wrap any child widget with this to show animated gift banners in real time.
class GiftAnimationOverlay extends StatefulWidget {
  final Widget  child;
  final String? filterRoomId;

  const GiftAnimationOverlay({super.key, required this.child, this.filterRoomId});

  @override
  State<GiftAnimationOverlay> createState() => _GiftAnimationOverlayState();
}

class _GiftAnimationOverlayState extends State<GiftAnimationOverlay> {
  StreamSubscription? _sub;
  final List<_GiftEntry> _active = [];

  @override
  void initState() { super.initState(); _sub = SocketService.giftStream.listen(_onGift); }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  void _onGift(Map<String, dynamic> data) {
    if (!mounted) return;
    final rid = data['roomId']?.toString();
    if (widget.filterRoomId != null && rid != widget.filterRoomId) return;

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() => _active.add(_GiftEntry(
      id: id,
      icon:       data['giftIcon']?.toString() ?? '🎁',
      giftName:   data['giftName']?.toString() ?? 'Gift',
      senderName: data['sender']?['username']?.toString() ?? 'Someone',
    )));
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _active.removeWhere((e) => e.id == id));
    });
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
    widget.child,
    ..._active.map((e) => _Banner(entry: e, key: ValueKey(e.id))),
  ]);
}

class _GiftEntry { final String id, icon, giftName, senderName; _GiftEntry({required this.id, required this.icon, required this.giftName, required this.senderName}); }

class _Banner extends StatefulWidget {
  final _GiftEntry entry;
  const _Banner({super.key, required this.entry});
  @override State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset>   _slide;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _slide = Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final top = 80.0 + Random().nextInt(200).toDouble();
    return Positioned(top: top, left: 16, child: SlideTransition(position: _slide, child: FadeTransition(opacity: _fade, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(24)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.entry.icon, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.entry.senderName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          Text(widget.entry.giftName,   style: const TextStyle(color: AppColors.warningOrange, fontSize: 11)),
        ]),
      ]),
    ))));
  }
}




