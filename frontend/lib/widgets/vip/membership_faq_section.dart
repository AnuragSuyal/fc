import 'package:flutter/material.dart';

class MembershipFaqSection extends StatelessWidget {
  const MembershipFaqSection({super.key});

  @override
  Widget build(BuildContext context) {
    const items = <(String, String)>[
      (
        'What happens on expiry?',
        'Your active badge, premium name color, and membership-only perks turn off automatically when the membership expires. Profile data falls back safely without showing the wrong tier.'
      ),
      (
        'How do upgrades work?',
        'Upgrades activate immediately. If you still have time left on a lower active tier, the backend applies membership credit so you do not lose the unused value.'
      ),
      (
        'How does restore work?',
        'Restore re-syncs your membership from the backend source of truth. It is designed for stale cache recovery and cross-device consistency.'
      ),
      (
        'What does auto-renew mean here?',
        'Auto-renew stores your intent on the membership record. You can turn it off from this page at any time, and the current membership remains active until the expiry date.'
      ),
      (
        'How do monthly rewards work?',
        'Each active membership tier includes a monthly coin reward. Claims are validated by the backend so rewards cannot be claimed twice in the same reward cycle.'
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FAQ & Trust',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 12),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              collapsedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: Text(
                item.$1,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              children: [
                Text(
                  item.$2,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
