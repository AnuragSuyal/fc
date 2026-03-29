import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../user_avatar.dart';

enum ColorClashProfileAction {
  viewProfile,
  sendGift,
}

Future<ColorClashProfileAction?> showColorClashProfileActionsSheet(
  BuildContext context, {
  required String userId,
  required String username,
  String? avatarUrl,
  required bool canGift,
}) {
  return showModalBottomSheet<ColorClashProfileAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  UserAvatar(
                    imageUrl: avatarUrl,
                    username: username,
                    radius: 26,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pick a social action for this Color Clash seat.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _ProfileActionTile(
                icon: Icons.person_rounded,
                title: 'View profile',
                subtitle: 'Open the full profile sheet for this player.',
                tone: AppColors.primaryBlue,
                onTap: () => Navigator.of(context).pop(
                  ColorClashProfileAction.viewProfile,
                ),
              ),
              if (canGift) ...[
                const SizedBox(height: 10),
                _ProfileActionTile(
                  icon: Icons.card_giftcard_rounded,
                  title: 'Send gift',
                  subtitle: 'Open the gift sheet with this seat preselected.',
                  tone: AppColors.warningOrange,
                  onTap: () => Navigator.of(context).pop(
                    ColorClashProfileAction.sendGift,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _ProfileActionTile extends StatelessWidget {
  const _ProfileActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: tone.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: tone),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: tone),
          ],
        ),
      ),
    );
  }
}
