import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/vip_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/vip_service.dart';
import '../../utils/constants.dart';
import '../../widgets/rounded_scaffold.dart';

class VipScreen extends StatefulWidget {
  const VipScreen({super.key});

  @override
  State<VipScreen> createState() => _VipScreenState();
}

class _VipScreenState extends State<VipScreen> {
  List<VipLevelModel> _levels = [];
  VipStatusModel? _status;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        VipService.getVipLevels(),
        VipService.getVipStatus(),
      ]);
      if (!mounted) return;

      final levels = (results[0] as List)
          .map((e) =>
              VipLevelModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final statusMap = results[1] as Map<String, dynamic>?;

      setState(() {
        _levels = levels;
        _status = statusMap != null
            ? VipStatusModel.fromJson(statusMap)
            : _freeStatus();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status ??= _freeStatus();
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _purchase(VipLevelModel level, String period) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result =
          await VipService.purchaseVip(level: level.level, period: period);
      if (!mounted) return;
      await context.read<AuthProvider>().refreshBalance();
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(result['message']?.toString() ?? '${level.name} activated.'),
          backgroundColor: AppColors.successGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('VIP purchase failed: $e'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choosePlan(VipLevelModel level) async {
    final period = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(level.name,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Choose a renewal cycle for immediate activation.'),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.calendar_month_rounded),
                title: const Text('Monthly'),
                subtitle: Text('${level.price} coins every 30 days'),
                onTap: () => Navigator.pop(context, 'monthly'),
              ),
              ListTile(
                leading: const Icon(Icons.event_repeat_rounded),
                title: const Text('Annual'),
                subtitle: Text('${level.annualPrice} coins every 365 days'),
                onTap: () => Navigator.pop(context, 'annual'),
              ),
            ],
          ),
        ),
      ),
    );

    if (period != null) {
      await _purchase(level, period);
    }
  }

  Future<void> _claimDaily() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await VipService.claimDailyBonus();
      if (!mounted) return;

      if (result == null) {
        throw Exception('Daily bonus is unavailable.');
      }

      final newBalance = result['newBalance'] is Map
          ? Map<String, dynamic>.from(result['newBalance'] as Map)
          : <String, dynamic>{};
      context.read<AuthProvider>().updateBalance(
            coins: _toInt(newBalance['coins']),
            gems: _toInt(newBalance['gems']),
          );
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['alreadyClaimed'] == true
                ? 'Today\'s VIP bonus is already claimed.'
                : 'Claimed ${result['dailyCoins'] ?? 0} VIP coins.',
          ),
          backgroundColor: AppColors.successGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRenew() async {
    final ok = await VipService.cancelVip();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(ok ? 'Auto-renew cancelled.' : 'Could not cancel auto-renew.'),
        backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = context.watch<AuthProvider>().user;
    final status = _status ?? _freeStatus();
    final current = _color(status.currentLevel.color);
    final featured = status.nextLevel ??
        (_levels.isNotEmpty ? _levels.first : status.currentLevel);

    return RoundedScaffold(
      title: 'VIP Membership',
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: colorScheme.outline.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monetization_on_rounded,
                  size: 15, color: Colors.amber),
              const SizedBox(width: 4),
              Text('${user?.coins ?? 0}', style: theme.textTheme.labelLarge),
              const SizedBox(width: 10),
              const Icon(Icons.diamond_rounded,
                  size: 15, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 4),
              Text('${user?.gems ?? 0}', style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(silent: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        colors: [
                          current,
                          AppColors.accentBerry,
                          AppColors.textPrimary,
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            status.isActive
                                ? status.currentLevel.name
                                : 'Unlock VIP benefits',
                            style: theme.textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text(
                          status.isActive
                              ? 'Benefits active until ${DateFormat('dd MMM yyyy').format(status.expiry!)}.'
                              : 'Choose a plan to unlock premium rooms, bonus coins, and profile perks.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.82)),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                                child: _badge(
                                    'Current',
                                    status.currentLevel.level > 0
                                        ? 'VIP ${status.currentLevel.level}'
                                        : 'Free')),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _badge('Next',
                                    status.nextLevel?.name ?? featured.name)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _badge('Bonus',
                                    '${status.currentLevel.coinBonus}%')),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => _choosePlan(status.isActive
                                        ? status.currentLevel
                                        : featured),
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: current),
                                child: Text(status.isActive
                                    ? 'Renew'
                                    : 'Choose ${featured.name}'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : (status.nextLevel != null
                                        ? () => _choosePlan(status.nextLevel!)
                                        : status.isActive
                                            ? _claimDaily
                                            : null),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                        color: Colors.white
                                            .withValues(alpha: 0.30))),
                                child: Text(status.nextLevel != null
                                    ? 'Upgrade'
                                    : status.isActive
                                        ? 'Claim daily'
                                        : 'Plans below'),
                              ),
                            ),
                          ],
                        ),
                        if (status.isActive) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            children: [
                              TextButton(
                                  onPressed: _busy ? null : _claimDaily,
                                  child: const Text('Claim daily coins',
                                      style: TextStyle(color: Colors.white))),
                              TextButton(
                                  onPressed: _busy ? null : _cancelRenew,
                                  child: const Text('Cancel auto-renew',
                                      style: TextStyle(color: Colors.white))),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Card(
                        child: ListTile(
                            leading: const Icon(Icons.info_outline_rounded),
                            title: const Text('VIP loaded with warnings'),
                            subtitle: Text(_error!))),
                  ],
                  const SizedBox(height: 20),
                  Text('Progress',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(
                                status.nextLevel != null
                                    ? 'On the way to ${status.nextLevel!.name}'
                                    : 'Membership status',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            const Spacer(),
                            Text('${(status.progressRatio * 100).round()}%')
                          ]),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                              value: status.progressRatio,
                              minHeight: 10,
                              backgroundColor: current.withValues(alpha: 0.12),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(current)),
                          const SizedBox(height: 12),
                          Text(status.isActive
                              ? '${status.daysRemaining} days remaining on your current membership.'
                              : 'Your next plan will activate instantly after purchase.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('VIP Levels',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  for (final level in _levels.where((level) => level.level > 0))
                    _tierCard(context, level, status),
                ],
              ),
            ),
    );
  }

  Widget _tierCard(
      BuildContext context, VipLevelModel level, VipStatusModel status) {
    final tone = _color(level.color);
    final current = status.currentLevel.level == level.level;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                    backgroundColor: tone.withValues(alpha: 0.14),
                    child: Icon(Icons.workspace_premium_rounded, color: tone)),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(level.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800))),
                if (current) Chip(label: const Text('Current')),
              ],
            ),
            const SizedBox(height: 10),
            Text(level.description.isNotEmpty
                ? level.description
                : 'Premium member access'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${level.price} / month')),
                Chip(label: Text('${level.annualPrice} / year')),
                Chip(label: Text('${level.coinBonus}% coin bonus')),
              ],
            ),
            const SizedBox(height: 12),
            ...level.benefits.take(4).map((benefit) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 18, color: tone),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(benefit.description.isNotEmpty
                              ? '${benefit.name}: ${benefit.description}'
                              : benefit.name)),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _purchase(level, 'monthly'),
                    child: Text(current ? 'Renew monthly' : 'Monthly'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _purchase(level, 'annual'),
                    style: FilledButton.styleFrom(backgroundColor: tone),
                    child: Text(current ? 'Renew annual' : 'Annual'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.78))),
        ],
      ),
    );
  }

  VipStatusModel _freeStatus() {
    return VipStatusModel(
      currentLevel: VipLevelModel(
        level: 0,
        name: 'Free',
        description: 'Upgrade to unlock premium rooms and daily bonuses.',
        benefits: const [],
        minSpend: 0,
        price: 0,
        annualPrice: 0,
        color: '#64748B',
        icon: 'VIP',
        coinBonus: 0,
      ),
      progress: 0,
      totalSpent: 0,
    );
  }

  Color _color(String hex) {
    try {
      return Color(
          int.parse(hex.replaceFirst('#', ''), radix: 16) + 0xFF000000);
    } catch (_) {
      return AppColors.primaryBlue;
    }
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
