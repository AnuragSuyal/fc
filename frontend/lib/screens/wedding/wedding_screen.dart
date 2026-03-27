import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/socket_service.dart';
import '../../services/wedding_service.dart';
import '../../utils/constants.dart';

class WeddingScreen extends StatefulWidget {
  const WeddingScreen({super.key});

  @override
  State<WeddingScreen> createState() => _WeddingScreenState();
}

class _WeddingScreenState extends State<WeddingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final List<StreamSubscription> _subs = [];

  Map<String, dynamic>? _wedding;
  List<Map<String, dynamic>> _rankings = [];
  List<Map<String, dynamic>> _rings = [];
  bool _loading = true;
  bool _isSubmitting = false;
  String? _activeProposalDialogId;

  String get _currentUserId {
    final userId = context.read<AuthProvider>().user?.id;
    return userId?.trim() ?? '';
  }

  Map<String, dynamic>? get _currentWedding => _asMap(_wedding?['wedding']);

  Map<String, dynamic>? get _partner => _asMap(_wedding?['partner']);

  Map<String, dynamic>? get _ring => _asMap(_currentWedding?['ring']);

  String get _status =>
      _currentWedding?['status']?.toString() ??
      (_wedding?['married'] == true ? 'active' : '');

  bool get _isActive => _wedding?['married'] == true || _status == 'active';

  bool get _isPending => _status == 'pending';

  bool get _isPendingIncoming =>
      _isPending &&
      _idOf(_currentWedding?['partnerId']).isNotEmpty &&
      _idOf(_currentWedding?['partnerId']) == _currentUserId;

  bool get _isPendingOutgoing =>
      _isPending &&
      _idOf(_currentWedding?['proposerId']).isNotEmpty &&
      _idOf(_currentWedding?['proposerId']) == _currentUserId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    unawaited(_load());
    _subs.add(SocketService.weddingStream.listen(_onWeddingEvent));
    _subs.add(
      SocketService.resyncStream.listen((_) {
        unawaited(_load(showSpinner: false));
      }),
    );
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() => _loading = true);
    }

    try {
      final results = await Future.wait<dynamic>([
        WeddingService.getMyWedding(),
        WeddingService.getCoupleRankings(),
        WeddingService.getRings(),
      ]);

      if (!mounted) return;

      setState(() {
        _wedding = results[0] as Map<String, dynamic>?;
        _rankings = (results[1] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        _rings = (results[2] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _onWeddingEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    final type = data['_eventType']?.toString() ?? 'update';
    switch (type) {
      case 'proposal':
        _showSnack('New mingle invite received.', const Color(0xFFEF476F));
        unawaited(_load(showSpinner: false));
        _showProposalDialog(data);
        return;
      case 'proposal_sent':
        _showSnack(
          'Mingle invite sent live.',
          const Color(0xFFEF476F),
        );
        break;
      case 'accepted':
        _showSnack(
          'Your mingle invite was accepted live.',
          const Color(0xFFEF476F),
        );
        break;
      case 'rejected':
        _showSnack('Mingle invite declined.', Colors.grey);
        break;
      case 'divorced':
        _showSnack('Your mingle status changed.', const Color(0xFFE85168));
        break;
      case 'blessing':
        final from = _asMap(data['from']);
        final name = from?['username']?.toString().trim();
        _showSnack(
          '${name != null && name.isNotEmpty ? name : 'Someone'} sent a live vibe.',
          const Color(0xFFEF476F),
        );
        break;
      default:
        _showSnack('Mingle updated live.', const Color(0xFFEF476F));
        break;
    }

    unawaited(_load(showSpinner: false));
  }

  void _showProposalDialog(Map<String, dynamic> data) {
    final from = _asMap(data['from']) ?? const <String, dynamic>{};
    final ring = _asMap(data['ring']) ?? const <String, dynamic>{};
    final weddingId = data['weddingId']?.toString() ?? '';

    if (weddingId.isEmpty || _activeProposalDialogId == weddingId) {
      return;
    }

    _activeProposalDialogId = weddingId;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mingle Invite'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${from['username'] ?? 'Someone'} wants to mingle with you.',
            ),
            const SizedBox(height: 12),
            Text(
              'Ring: ${ring['name'] ?? 'Signature ring'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              _activeProposalDialogId = null;
              await _handleRejectInvite(weddingId);
            },
            child: const Text(
              'Decline',
              style: TextStyle(color: AppColors.errorRed),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              _activeProposalDialogId = null;
              await _handleAcceptInvite(weddingId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF476F),
              foregroundColor: Colors.white,
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    ).whenComplete(() {
      if (_activeProposalDialogId == weddingId) {
        _activeProposalDialogId = null;
      }
    });
  }

  void _showSnack(String message, Color background) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mingle'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'My Status'),
            Tab(text: 'Rankings'),
            Tab(text: 'Rings'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildStatus(),
                _buildRankings(),
                _buildRings(),
              ],
            ),
    );
  }

  Widget _buildStatus() {
    final partner = _partner;
    final partnerName =
        partner?['username']?.toString().trim().isNotEmpty == true
            ? partner!['username'].toString().trim()
            : 'someone special';
    final ringName = _ring?['name']?.toString().trim();
    final blessings = _toInt(_currentWedding?['stats']?['totalBlessings']) ?? 0;
    final coinsSpent = _toInt(_ring?['coinsSpent']) ?? 0;

    if (_isPendingIncoming) {
      return _buildStatusCard(
        icon: Icons.favorite_outline_rounded,
        iconColor: const Color(0xFFEF476F),
        title: '$partnerName invited you to mingle',
        subtitle:
            'Accept or decline below. This screen updates live when the status changes.',
        chips: [
          if (ringName != null && ringName.isNotEmpty) 'Ring: $ringName',
          'Live request',
        ],
        actions: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isSubmitting
                  ? null
                  : () => _handleRejectInvite(
                        _currentWedding?['_id']?.toString() ?? '',
                      ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.errorRed,
              ),
              child: const Text('Decline'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _isSubmitting
                  ? null
                  : () => _handleAcceptInvite(
                        _currentWedding?['_id']?.toString() ?? '',
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF476F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Accept'),
            ),
          ),
        ],
      );
    }

    if (_isPendingOutgoing) {
      return _buildStatusCard(
        icon: Icons.schedule_rounded,
        iconColor: const Color(0xFFEF476F),
        title: 'Waiting for $partnerName',
        subtitle:
            'Your mingle invite is live. If they reply, this page updates automatically.',
        chips: [
          if (ringName != null && ringName.isNotEmpty) 'Ring: $ringName',
          'Invite pending',
        ],
        actions: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isSubmitting ? null : () => _load(showSpinner: false),
              child: const Text('Refresh'),
            ),
          ),
        ],
      );
    }

    if (!_isActive) {
      return _buildStatusCard(
        icon: Icons.favorite_border_rounded,
        iconColor: const Color(0xFFEF476F),
        title: 'You are not mingling yet',
        subtitle:
            'Find someone special, choose a ring, and send a live invite.',
        chips: const [
          'Single',
          'Realtime ready',
        ],
        actions: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _showProposeDialog,
              icon: const Icon(Icons.favorite_rounded),
              label: const Text('Start Mingle'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF476F),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    return _buildStatusCard(
      icon: Icons.favorite_rounded,
      iconColor: const Color(0xFFEF476F),
      title: 'Mingling with $partnerName',
      subtitle:
          'Your connection stays synced live. Blessings and status changes appear right away.',
      chips: [
        if (ringName != null && ringName.isNotEmpty) 'Ring: $ringName',
        '$blessings vibe${blessings == 1 ? '' : 's'}',
        if (coinsSpent > 0) '$coinsSpent coins',
      ],
      actions: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _sendVibe,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Send vibe'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF476F),
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isSubmitting ? null : _endMingle,
            icon: const Icon(Icons.heart_broken_outlined),
            label: const Text('End'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.errorRed,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRankings() {
    if (_rankings.isEmpty) {
      return const Center(
        child: Text(
          'No mingle pairs ranked yet.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _rankings.length,
      itemBuilder: (context, index) {
        final couple = _rankings[index];
        final proposer = _asMap(couple['proposerId']) ?? const {};
        final partner = _asMap(couple['partnerId']) ?? const {};
        final blessingCount = _toInt(couple['stats']?['totalBlessings']) ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFFDE7EF),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Color(0xFFEF476F),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            title: Text(
              '${proposer['username'] ?? '?'} and ${partner['username'] ?? '?'}',
            ),
            subtitle: Text(
                '$blessingCount live vibe${blessingCount == 1 ? '' : 's'}'),
          ),
        );
      },
    );
  }

  Widget _buildRings() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _rings.length,
      itemBuilder: (context, index) {
        final ring = _rings[index];
        final price = _toInt(ring['price']) ?? 0;
        final rarity = ring['rarity']?.toString() ?? 'common';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            leading: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFFDE7EF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.diamond_outlined,
                color: Color(0xFFEF476F),
              ),
            ),
            title: Text(ring['name']?.toString() ?? ''),
            subtitle: Text(
              '${_titleCase(rarity)} • $price coins',
            ),
            trailing: ElevatedButton(
              onPressed: _isSubmitting
                  ? null
                  : () => _showProposeDialog(
                        preselectedRing: ring['id']?.toString(),
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Invite'),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required List<String> chips,
    required List<Widget> actions,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: chips
                    .map(
                      (chip) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F5F6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          chip,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 24),
            Row(children: actions),
          ],
        ),
      ),
    );
  }

  Future<void> _showProposeDialog({String? preselectedRing}) async {
    final partnerIdController = TextEditingController();
    var selectedRingId = preselectedRing ??
        (_rings.isNotEmpty ? _rings.first['id']?.toString() ?? '' : '');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Start Mingle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: partnerIdController,
                decoration: const InputDecoration(
                  labelText: 'Partner user ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRingId.isNotEmpty ? selectedRingId : null,
                decoration: const InputDecoration(
                  labelText: 'Select ring',
                  border: OutlineInputBorder(),
                ),
                items: _rings
                    .map(
                      (ring) => DropdownMenuItem<String>(
                        value: ring['id']?.toString(),
                        child: Text(
                          '${ring['name']} (${ring['price']} coins)',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  setDialogState(() {
                    selectedRingId = value ?? selectedRingId;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _isSubmitting
                  ? null
                  : () async {
                      Navigator.pop(dialogContext);
                      await _sendInvite(
                        partnerId: partnerIdController.text.trim(),
                        ringId: selectedRingId,
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF476F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Send invite'),
            ),
          ],
        ),
      ),
    );

    partnerIdController.dispose();
  }

  Future<void> _sendInvite({
    required String partnerId,
    required String ringId,
  }) async {
    if (partnerId.isEmpty || ringId.isEmpty) {
      _showSnack('Choose a partner and ring first.', AppColors.errorRed);
      return;
    }

    await _runAction(() async {
      await WeddingService.propose(partnerId: partnerId, ringId: ringId);
      _showSnack(
        'Mingle invite sent. Waiting live for a reply.',
        const Color(0xFFEF476F),
      );
      await _load(showSpinner: false);
    });
  }

  Future<void> _handleAcceptInvite(String weddingId) async {
    if (weddingId.isEmpty) return;

    await _runAction(() async {
      await WeddingService.accept(weddingId);
      _showSnack(
        'You are now mingling together.',
        const Color(0xFFEF476F),
      );
      await _load(showSpinner: false);
    });
  }

  Future<void> _handleRejectInvite(String weddingId) async {
    if (weddingId.isEmpty) return;

    await _runAction(() async {
      await WeddingService.reject(weddingId);
      _showSnack('Mingle invite declined.', Colors.grey);
      await _load(showSpinner: false);
    });
  }

  Future<void> _sendVibe() async {
    final weddingId = _currentWedding?['_id']?.toString() ?? '';
    if (weddingId.isEmpty) return;

    await _runAction(() async {
      await WeddingService.bless(
        weddingId: weddingId,
        message: 'Sending good vibes your way.',
      );
      _showSnack('Live vibe sent.', const Color(0xFFEF476F));
      await _load(showSpinner: false);
    });
  }

  Future<void> _endMingle() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End Mingle?'),
        content: const Text(
          'This will end your current mingle connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'End',
              style: TextStyle(color: AppColors.errorRed),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _runAction(() async {
      await WeddingService.divorce();
      _showSnack('Mingle ended.', Colors.grey);
      await _load(showSpinner: false);
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      await action();
    } catch (error) {
      _showSnack(
        error.toString().replaceFirst('Exception: ', ''),
        AppColors.errorRed,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  static String _idOf(dynamic value) {
    final map = _asMap(value);
    if (map != null) {
      return map['_id']?.toString() ?? map['id']?.toString() ?? '';
    }
    return value?.toString() ?? '';
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1).toLowerCase();
  }
}
