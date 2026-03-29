import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/constants.dart';

class ColorClashSocialBar extends StatelessWidget {
  const ColorClashSocialBar({
    super.key,
    required this.onOpenReactions,
    required this.onOpenGifts,
    required this.onReturnToRoom,
    this.reactionsEnabled = true,
    this.giftsEnabled = true,
    this.returnEnabled = true,
  });

  final VoidCallback onOpenReactions;
  final VoidCallback onOpenGifts;
  final VoidCallback onReturnToRoom;
  final bool reactionsEnabled;
  final bool giftsEnabled;
  final bool returnEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SocialActionChip(
              icon: Icons.emoji_emotions_rounded,
              label: 'React',
              tone: AppColors.primaryBlue,
              enabled: reactionsEnabled,
              onTap: reactionsEnabled ? onOpenReactions : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SocialActionChip(
              icon: Icons.card_giftcard_rounded,
              label: 'Gift',
              tone: AppColors.warningOrange,
              enabled: giftsEnabled,
              onTap: giftsEnabled ? onOpenGifts : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SocialActionChip(
              icon: Icons.voice_chat_rounded,
              label: 'Room',
              tone: AppColors.accentBerry,
              enabled: returnEnabled,
              onTap: returnEnabled ? onReturnToRoom : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialActionChip extends StatelessWidget {
  const _SocialActionChip({
    required this.icon,
    required this.label,
    required this.tone,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: enabled ? 0.1 : 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: tone.withValues(alpha: enabled ? 0.16 : 0.08),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: enabled ? tone : tone.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: enabled ? tone : tone.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
