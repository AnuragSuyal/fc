import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vip_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/vip_service.dart';
import '../../utils/constants.dart';
import '../../widgets/currency_icon.dart';
import '../../widgets/rounded_scaffold.dart';
import '../../widgets/vip/membership_faq_section.dart';
import '../../widgets/vip/membership_hero_card.dart';
import '../../widgets/vip/membership_purchase_panel.dart';
import '../../widgets/vip/vip_benefit_list.dart';
import '../../widgets/vip/vip_comparison_table.dart';
import '../../widgets/vip/vip_identity_preview.dart';
import '../../widgets/vip/vip_tier_card.dart';

class VipScreen extends StatefulWidget {
  const VipScreen({super.key});

  @override
  State<VipScreen> createState() => _VipScreenState();
}

class _VipScreenState extends State<VipScreen> {
  VipCatalogModel _catalog = const VipCatalogModel(
    tiers: <VipTierModel>[],
    comparisonRows: <VipComparisonRow>[],
    planDefinitions: <VipPlanOption>[],
  );
  VipStatusModel? _status;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _selectedTierId = '';
  String _selectedPlanDuration = 'monthly';

  VipTierModel? get _selectedTier {
    final match = _catalog.tiers.where((tier) => tier.tierId == _selectedTierId);
    if (match.isNotEmpty) {
      return match.first;
    }
    return _catalog.tiers.isNotEmpty ? _catalog.tiers.first : null;
  }

  VipPlanOption? get _selectedPlan {
    final tier = _selectedTier;
    if (tier == null) return null;
    final exact = tier.planOptions
        .where((plan) => plan.planDuration == _selectedPlanDuration);
    if (exact.isNotEmpty) {
      return exact.first;
    }
    return tier.planOptions.isNotEmpty ? tier.planOptions.first : null;
  }

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
        VipService.getVipCatalog(selectedTierId: _selectedTierId),
        VipService.getVipStatus(),
      ]);
      if (!mounted) return;

      final catalog = results[0] as VipCatalogModel;
      final status = results[1] as VipStatusModel?;
      final membership = status?.membership;
      final defaultTierId = _selectedTierId.isNotEmpty
          ? _selectedTierId
          : (membership?.activeTierId.isNotEmpty == true
              ? membership!.activeTierId
              : membership?.currentTierId.isNotEmpty == true &&
                      membership!.currentTierId != 'free'
                  ? membership.currentTierId
                  : (catalog.tiers.isNotEmpty ? catalog.tiers.first.tierId : ''));
      final defaultTier = catalog.tiers
          .where((tier) => tier.tierId == defaultTierId)
          .cast<VipTierModel?>()
          .firstOrNull;
      final defaultPlan = defaultTier?.planOptions.isNotEmpty == true
          ? defaultTier!.planOptions.first.planDuration
          : 'monthly';

      setState(() {
        _catalog = catalog;
        _status = status;
        _selectedTierId = defaultTierId;
        _selectedPlanDuration = _selectedPlanDuration.isNotEmpty
            ? _selectedPlanDuration
            : defaultPlan;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _purchaseSelectedTier() async {
    final tier = _selectedTier;
    final plan = _selectedPlan;
    if (tier == null || plan == null || _busy) return;

    setState(() => _busy = true);
    try {
      final result = await VipService.purchaseVip(
        tierId: tier.tierId,
        planDuration: plan.planDuration,
      );
      if (!mounted) return;

      final newBalance = result['newBalance'] is Map
          ? Map<String, dynamic>.from(result['newBalance'] as Map)
          : const <String, dynamic>{};
      final membershipMap = result['membership'] is Map
          ? Map<String, dynamic>.from(result['membership'] as Map)
          : (newBalance['vipMembership'] is Map
              ? Map<String, dynamic>.from(newBalance['vipMembership'] as Map)
              : const <String, dynamic>{});

      context.read<AuthProvider>().mergeProfilePatch({
        'coins': newBalance['coins'],
        'gems': newBalance['gems'],
        'xp': newBalance['xp'],
        'level': newBalance['level'],
        'vipLevel': newBalance['vipLevel'],
        if (membershipMap.isNotEmpty) 'vipMembership': membershipMap,
      });

      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                '${tier.displayName} activated successfully.',
          ),
          backgroundColor: AppColors.successGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restoreMembership() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await VipService.restoreVip();
      if (!mounted) return;
      final membershipMap = result['membership'] is Map
          ? Map<String, dynamic>.from(result['membership'] as Map)
          : const <String, dynamic>{};
      context.read<AuthProvider>().mergeProfilePatch({
        if (membershipMap.isNotEmpty) 'vipMembership': membershipMap,
        'vipLevel': membershipMap['vipLevel'],
      });
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Membership restored.',
          ),
          backgroundColor: AppColors.successGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _claimMonthlyReward() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await VipService.claimMonthlyReward();
      if (!mounted) return;

      final newBalance = result['newBalance'] is Map
          ? Map<String, dynamic>.from(result['newBalance'] as Map)
          : const <String, dynamic>{};
      final membershipMap = result['membership'] is Map
          ? Map<String, dynamic>.from(result['membership'] as Map)
          : const <String, dynamic>{};

      context.read<AuthProvider>().mergeProfilePatch({
        'coins': newBalance['coins'],
        'gems': newBalance['gems'],
        if (membershipMap.isNotEmpty) 'vipMembership': membershipMap,
        'vipLevel': membershipMap['vipLevel'],
      });

      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['alreadyClaimed'] == true
                ? 'This cycle is already claimed.'
                : 'Claimed ${result['monthlyCoins'] ?? 0} coins.',
          ),
          backgroundColor: AppColors.successGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _cancelAutoRenew() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await VipService.cancelVip();
      if (!mounted) return;
      final membershipMap = result['membership'] is Map
          ? Map<String, dynamic>.from(result['membership'] as Map)
          : const <String, dynamic>{};
      context.read<AuthProvider>().mergeProfilePatch({
        if (membershipMap.isNotEmpty) 'vipMembership': membershipMap,
        'vipLevel': membershipMap['vipLevel'],
      });
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Auto-renew updated.',
          ),
          backgroundColor: AppColors.successGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final status = _status;
    final selectedTier = _selectedTier;

    return RoundedScaffold(
      title: 'Membership',
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CurrencyIcon.coins(size: 16),
              const SizedBox(width: 4),
              Text('${user?.coins ?? 0}',
                  style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : selectedTier == null || status == null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: () => _load(silent: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    children: [
                      MembershipHeroCard(
                        membership: status.membership,
                        onPrimaryTap: _purchaseSelectedTier,
                        onRestoreTap: _restoreMembership,
                        onClaimTap: _claimMonthlyReward,
                        busy: _busy,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.info_outline_rounded),
                            title: const Text('Membership loaded with warnings'),
                            subtitle: Text(_error!),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Text(
                        'Choose Your Tier',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 280,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _catalog.tiers.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 14),
                          itemBuilder: (context, index) {
                            final tier = _catalog.tiers[index];
                            return VipTierCard(
                              tier: tier,
                              selected: tier.tierId == selectedTier.tierId,
                              onTap: () {
                                setState(() {
                                  _selectedTierId = tier.tierId;
                                  _selectedPlanDuration = tier.planOptions.isNotEmpty
                                      ? tier.planOptions.first.planDuration
                                      : 'monthly';
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 22),
                      VipIdentityPreview(
                        tier: selectedTier,
                        username: user?.username ?? 'FriendCircle User',
                        level: user?.level ?? 27,
                      ),
                      const SizedBox(height: 22),
                      VipBenefitList(tier: selectedTier),
                      const SizedBox(height: 22),
                      MembershipPurchasePanel(
                        targetTier: selectedTier,
                        currentTier: status.membership.activeTier ??
                            (status.membership.currentTierId != 'free'
                                ? status.membership.currentTier
                                : null),
                        selectedPlan: _selectedPlan,
                        onPlanSelected: (plan) {
                          setState(() => _selectedPlanDuration = plan.planDuration);
                        },
                        onPurchase: _purchaseSelectedTier,
                        onCancelAutoRenew:
                            status.membership.isActive ? _cancelAutoRenew : null,
                        busy: _busy,
                        autoRenew: status.membership.autoRenew,
                        activeCurrentTier: status.membership.isActive,
                      ),
                      const SizedBox(height: 22),
                      VipComparisonTable(
                        rows: _catalog.comparisonRows,
                        tiers: _catalog.tiers,
                        highlightedTierId: selectedTier.tierId,
                      ),
                      const SizedBox(height: 22),
                      const MembershipFaqSection(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.workspace_premium_outlined,
              size: 46,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              _error?.replaceFirst('Exception: ', '') ??
                  'Membership is unavailable right now.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _load,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
