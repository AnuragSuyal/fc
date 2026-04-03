import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/golden_dragon_model.dart';
import '../../services/golden_dragon_service.dart';
import '../../services/socket_service.dart';
import '../../widgets/rounded_scaffold.dart';

class GoldenDragonHistoryScreen extends StatefulWidget {
  const GoldenDragonHistoryScreen({super.key});

  @override
  State<GoldenDragonHistoryScreen> createState() =>
      _GoldenDragonHistoryScreenState();
}

class _GoldenDragonHistoryScreenState extends State<GoldenDragonHistoryScreen> {
  final List<GoldenDragonHistoryItem> _events = <GoldenDragonHistoryItem>[];
  StreamSubscription<Map<String, dynamic>>? _dragonSubscription;
  StreamSubscription<Map<String, dynamic>>? _resyncSubscription;
  bool _isLoading = true;
  bool _isPaging = false;
  String _view = 'all';
  int _page = 1;
  int _pages = 1;

  @override
  void initState() {
    super.initState();
    _dragonSubscription =
        SocketService.dragonPacketStream.listen((_) => _reload());
    _resyncSubscription = SocketService.resyncStream.listen((_) => _reload());
    unawaited(_loadHistory(reset: true));
  }

  @override
  void dispose() {
    _dragonSubscription?.cancel();
    _resyncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    await _loadHistory(reset: true, showLoader: false);
  }

  Future<void> _loadHistory({
    bool reset = false,
    bool showLoader = true,
  }) async {
    if (_isPaging) return;
    if (showLoader && mounted) {
      setState(() {
        if (reset) {
          _isLoading = true;
        } else {
          _isPaging = true;
        }
      });
    }

    try {
      final page = await GoldenDragonService.getHistory(
        view: _view,
        page: reset ? 1 : _page,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _events
            ..clear()
            ..addAll(page.events);
        } else {
          _events.addAll(page.events);
        }
        _page = page.page;
        _pages = page.pages;
        _isLoading = false;
        _isPaging = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isPaging = false;
      });
    }
  }

  void _changeView(String nextView) {
    if (_view == nextView) return;
    setState(() => _view = nextView);
    unawaited(_loadHistory(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    return RoundedScaffold(
      title: 'Golden Dragon',
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  _filterChip('All', 'all'),
                  const SizedBox(width: 8),
                  _filterChip('Activated', 'activated_by_me'),
                  const SizedBox(width: 8),
                  _filterChip('Won', 'won_by_me'),
                  const SizedBox(width: 8),
                  _filterChip('Tapped', 'joined_by_me'),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () =>
                        _loadHistory(reset: true, showLoader: false),
                    child: _events.isEmpty
                        ? ListView(
                            children: const <Widget>[
                              SizedBox(height: 180),
                              Center(
                                child: Text(
                                  'No Golden Dragon events yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification.metrics.extentAfter < 220 &&
                                  !_isPaging &&
                                  _page < _pages) {
                                setState(() => _page += 1);
                                unawaited(
                                  _loadHistory(reset: false, showLoader: true),
                                );
                              }
                              return false;
                            },
                            child: ListView.separated(
                              padding: const EdgeInsets.all(20),
                              itemCount: _events.length + (_isPaging ? 1 : 0),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                if (index >= _events.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                return _DragonHistoryTile(
                                    event: _events[index]);
                              },
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _view == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _changeView(value),
      selectedColor: const Color(0xFFB91C1C),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF111827),
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }
}

class _DragonHistoryTile extends StatelessWidget {
  const _DragonHistoryTile({required this.event});

  final GoldenDragonHistoryItem event;

  @override
  Widget build(BuildContext context) {
    final formattedDate = event.startAtServer != null
        ? DateFormat('dd MMM, hh:mm a').format(event.startAtServer!.toLocal())
        : 'Recently';
    final myReward = event.myClaim?.finalCoinReward ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/images/${_assetKeyForEvent(event)}.png',
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${event.packetTotalCoins} coin Golden Dragon',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${event.roomName} • $formattedDate',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  event.eventStatus.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _MetricBlock(
                  label: 'Distributed',
                  value: '${event.totalDistributed}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricBlock(
                  label: 'Winners',
                  value: '${event.winnerCount}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricBlock(
                  label: 'You won',
                  value: '$myReward',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

String _assetKeyForEvent(GoldenDragonHistoryItem event) {
  switch (event.packageType) {
    case 'large':
      return 'golden_dragon_packet_large';
    case 'medium':
      return 'golden_dragon_packet_medium';
    default:
      return 'golden_dragon_packet_small';
  }
}
