import 'package:flutter/material.dart';

import '../../models/vip_model.dart';
import '../../widgets/currency_icon.dart';
import '../../widgets/vip/vip_badge.dart';
import '../../widgets/vip/vip_name_text.dart';

class MembershipHeroCard extends StatelessWidget {
  final VipMembershipSnapshot membership;
  final VoidCallback? onPrimaryTap;
  final VoidCallback? onRestoreTap;
  final VoidCallback? onClaimTap;
  final bool busy;

  const MembershipHeroCard({
    super.key,
    required this.membership,
    this.onPrimaryTap,
    this.onRestoreTap,
    this.onClaimTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeTier = membership.activeTier ?? membership.currentTier;
    final theme = Theme.of(context);
    final colors = activeTier.ui.gradient.isNotEmpty
        ? activeTier.ui.gradient.map(_parseColor).toList(growable: false)
        : const <Color>[Color(0xFF172033), Color(0xFF334155)];
    final accent = _parseColor(activeTier.ui.accent);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: colors.length >= 2 ? colors : <Color>[colors.first, accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              VipBadge(
                membership: membership,
                allowExpiredPreview: true,
                size: VipBadgeSize.large,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      membership.isActive
                          ? 'Current Membership'
                          : membership.isExpired
                              ? 'Membership Expired'
                              : 'Unlock Premium Identity',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    VipNameText(
                      activeTier.displayName,
                      membership: membership,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      membership.isActive
                          ? '${membership.daysRemaining} days remaining'
                          : membership.isExpired
                              ? 'Benefits ended. You can renew or upgrade any time.'
                              : 'Preview every perk before you buy.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _pill(
                icon: Icons.bolt_rounded,
                label: '+${activeTier.xpBoostPercent}% XP',
              ),
              _pill(
                icon: Icons.wallet_giftcard_rounded,
                label: '${activeTier.monthlyCoinReward} monthly coins',
              ),
              _pill(
                icon: Icons.workspace_premium_rounded,
                label: activeTier.nameColorStyle.label,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onPrimaryTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    membership.isActive ? 'Renew / Upgrade' : 'Choose a Tier',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onRestoreTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.26),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Restore'),
                ),
              ),
            ],
          ),
          if (membership.monthlyRewardAmount > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const CurrencyIcon.coins(size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      membership.canClaimMonthlyReward
                          ? 'Monthly reward ready: ${membership.monthlyRewardAmount} coins'
                          : 'Monthly reward claimed. Next reward unlocks with your membership cycle.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onClaimTap != null)
                    FilledButton(
                      onPressed:
                          membership.canClaimMonthlyReward && !busy ? onClaimTap : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Claim'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  static Color _parseColor(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ??
        0x334155;
    return Color(value + 0xFF000000);
  }
}
