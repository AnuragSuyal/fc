import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/coin_transfer_model.dart';
import '../../services/coin_transfer_service.dart';
import '../../services/socket_service.dart';
import '../../widgets/rounded_scaffold.dart';

class CoinTransferHistoryScreen extends StatefulWidget {
  const CoinTransferHistoryScreen({super.key});

  @override
  State<CoinTransferHistoryScreen> createState() =>
      _CoinTransferHistoryScreenState();
}

class _CoinTransferHistoryScreenState extends State<CoinTransferHistoryScreen> {
  final List<CoinTransferRecord> _transfers = <CoinTransferRecord>[];
  StreamSubscription<Map<String, dynamic>>? _coinTransferSubscription;
  StreamSubscription<Map<String, dynamic>>? _resyncSubscription;
  bool _isLoading = true;
  bool _isPaging = false;
  String _view = 'all';
  int _page = 1;
  int _pages = 1;

  @override
  void initState() {
    super.initState();
    _coinTransferSubscription =
        SocketService.coinTransferStream.listen((_) => _reload());
    _resyncSubscription = SocketService.resyncStream.listen((_) => _reload());
    unawaited(_loadHistory(reset: true));
  }

  @override
  void dispose() {
    _coinTransferSubscription?.cancel();
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
    final nextPage = reset ? 1 : _page;
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
      final page = await CoinTransferService.getHistory(
        view: _view,
        page: nextPage,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _transfers
            ..clear()
            ..addAll(page.transfers);
        } else {
          _transfers.addAll(page.transfers);
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
    setState(() {
      _view = nextView;
    });
    unawaited(_loadHistory(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    return RoundedScaffold(
      title: 'Coin Transfers',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                _filterChip('All', 'all'),
                const SizedBox(width: 8),
                _filterChip('Sent', 'sent'),
                const SizedBox(width: 8),
                _filterChip('Received', 'received'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () =>
                        _loadHistory(reset: true, showLoader: false),
                    child: _transfers.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 180),
                              Center(
                                child: Text(
                                  'No coin transfers yet',
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
                                setState(() {
                                  _page += 1;
                                });
                                unawaited(
                                  _loadHistory(
                                    reset: false,
                                    showLoader: true,
                                  ),
                                );
                              }
                              return false;
                            },
                            child: ListView.separated(
                              padding: const EdgeInsets.all(20),
                              itemCount:
                                  _transfers.length + (_isPaging ? 1 : 0),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                if (index >= _transfers.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                return _TransferTile(
                                    transfer: _transfers[index]);
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
      selectedColor: const Color(0xFF1D4ED8),
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

class _TransferTile extends StatelessWidget {
  final CoinTransferRecord transfer;

  const _TransferTile({required this.transfer});

  @override
  Widget build(BuildContext context) {
    final isSent = transfer.isSent;
    final accent = isSent ? const Color(0xFF2563EB) : const Color(0xFF16A34A);
    final peerName = transfer.peer.username.trim().isNotEmpty
        ? transfer.peer.username
        : 'Friend';
    final formattedDate = transfer.createdAt != null
        ? DateFormat('dd MMM, hh:mm a').format(transfer.createdAt!.toLocal())
        : 'Recently';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: accent.withValues(alpha: 0.12),
                backgroundImage: transfer.peer.avatar.isNotEmpty
                    ? NetworkImage(transfer.peer.avatar)
                    : null,
                child: transfer.peer.avatar.isEmpty
                    ? Text(
                        peerName.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSent ? 'Sent to $peerName' : 'Received from $peerName',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formattedDate,
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
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  transfer.status.toUpperCase(),
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricBlock(
                  label: isSent ? 'You spent' : 'Gross',
                  value: '${transfer.grossAmount}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricBlock(
                  label: 'Friend received',
                  value: '${transfer.receiverAmount}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricBlock(
                  label: 'Platform fee',
                  value: '${transfer.platformFee}',
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
  final String label;
  final String value;

  const _MetricBlock({
    required this.label,
    required this.value,
  });

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
        children: [
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
