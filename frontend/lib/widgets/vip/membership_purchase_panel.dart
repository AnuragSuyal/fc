import 'package:flutter/material.dart';

import '../../models/vip_model.dart';
import 'membership_plan_chip.dart';
import 'upgrade_difference_card.dart';

class MembershipPurchasePanel extends StatelessWidget {
  final VipTierModel targetTier;
  final VipTierModel? currentTier;
  final VipPlanOption? selectedPlan;
  final ValueChanged<VipPlanOption> onPlanSelected;
  final VoidCallback? onPurchase;
  final VoidCallback? onCancelAutoRenew;
  final bool busy;
  final bool autoRenew;
  final bool activeCurrentTier;

  const MembershipPurchasePanel({
    super.key,
    required this.targetTier,
    required this.currentTier,
    required this.selectedPlan,
    required this.onPlanSelected,
    required this.onPurchase,
    required this.onCancelAutoRenew,
    required this.busy,
    required this.autoRenew,
    required this.activeCurrentTier,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _parseColor(targetTier.ui.accent);
    final effectivePlan = selectedPlan ??
        (targetTier.planOptions.isNotEmpty ? targetTier.planOptions.first : null);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            activeCurrentTier && currentTier?.tierId == targetTier.tierId
                ? 'Renew or manage ${targetTier.displayName}'
                : 'Upgrade to ${targetTier.displayName}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a plan, preview the identity, and unlock your perks instantly.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: targetTier.planOptions
                .map(
                  (plan) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: MembershipPlanChip(
                        plan: plan,
                        selected: effectivePlan?.planDuration == plan.planDuration,
                        onTap: () => onPlanSelected(plan),
                        accent: accent,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 16),
          UpgradeDifferenceCard(
            targetTier: targetTier,
            currentTier: currentTier,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: accent.withValues(alpha: 0.08),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow(
                  context,
                  'XP boost',
                  '+${targetTier.xpBoostPercent}%',
                ),
                const SizedBox(height: 8),
                _summaryRow(
                  context,
                  'Monthly reward',
                  '${targetTier.monthlyCoinReward} coins',
                ),
                const SizedBox(height: 8),
                _summaryRow(
                  context,
                  'Gifting perk',
                  'Level ${targetTier.giftingPerkLevel}',
                ),
                const SizedBox(height: 8),
                _summaryRow(
                  context,
                  'Selected plan',
                  effectivePlan == null
                      ? 'Choose a plan'
                      : '${effectivePlan.label} • ${effectivePlan.priceCoins} coins',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy || effectivePlan == null ? null : onPurchase,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Text(
                    currentTier?.tierId == targetTier.tierId && activeCurrentTier
                        ? 'Renew ${targetTier.displayName}'
                        : 'Unlock ${targetTier.displayName}',
                  ),
                ),
              ),
              if (activeCurrentTier && onCancelAutoRenew != null) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: busy ? null : onCancelAutoRenew,
                  child: Text(autoRenew ? 'Cancel Auto-Renew' : 'Auto-Renew Off'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }

  static Color _parseColor(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ??
        0x8B5CF6;
    return Color(value + 0xFF000000);
  }
}
