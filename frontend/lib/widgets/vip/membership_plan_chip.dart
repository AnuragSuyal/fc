import 'package:flutter/material.dart';

import '../../models/vip_model.dart';

class MembershipPlanChip extends StatelessWidget {
  final VipPlanOption plan;
  final bool selected;
  final VoidCallback? onTap;
  final Color accent;

  const MembershipPlanChip({
    super.key,
    required this.plan,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: selected
                ? accent.withValues(alpha: 0.16)
                : colorScheme.surface.withValues(alpha: 0.6),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.56)
                  : colorScheme.outline.withValues(alpha: 0.16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  if (plan.recommendedTag.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        plan.recommendedTag,
                        style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${plan.priceCoins} coins',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '${plan.durationDays} days',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (plan.savingsPercent > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Save ${plan.savingsPercent}%',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
