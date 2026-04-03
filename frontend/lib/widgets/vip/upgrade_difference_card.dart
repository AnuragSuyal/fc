import 'package:flutter/material.dart';

import '../../models/vip_model.dart';

class UpgradeDifferenceCard extends StatelessWidget {
  final VipTierModel targetTier;
  final VipTierModel? currentTier;

  const UpgradeDifferenceCard({
    super.key,
    required this.targetTier,
    required this.currentTier,
  });

  @override
  Widget build(BuildContext context) {
    final previousIds = currentTier?.cumulativeBenefits
            .map((benefit) => benefit.id)
            .toSet() ??
        <String>{};
    final unlocked = targetTier.cumulativeBenefits
        .where((benefit) => !previousIds.contains(benefit.id))
        .toList(growable: false);

    if (unlocked.isEmpty) {
      return const SizedBox.shrink();
    }

    final accent = _parseColor(targetTier.ui.accent);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: accent.withValues(alpha: 0.08),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            currentTier == null
                ? 'You unlock instantly'
                : 'What you gain from upgrading',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 10),
          ...unlocked.take(5).map(
                (benefit) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.add_circle_rounded, color: accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          benefit.title,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  static Color _parseColor(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ??
        0x8B5CF6;
    return Color(value + 0xFF000000);
  }
}
