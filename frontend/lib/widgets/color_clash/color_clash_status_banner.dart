import 'package:flutter/material.dart';

import '../../providers/color_clash_session_controller.dart';
import '../../utils/constants.dart';

class ColorClashStatusBanner extends StatelessWidget {
  const ColorClashStatusBanner({
    super.key,
    required this.notice,
    this.onDismiss,
  });

  final ColorClashStatusNotice notice;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final tone = switch (notice.tone) {
      ColorClashNoticeTone.success => AppColors.successGreen,
      ColorClashNoticeTone.warning => AppColors.warningOrange,
      ColorClashNoticeTone.error => AppColors.errorRed,
      ColorClashNoticeTone.info => AppColors.primaryBlue,
    };
    final icon = switch (notice.tone) {
      ColorClashNoticeTone.success => Icons.check_circle_rounded,
      ColorClashNoticeTone.warning => Icons.warning_rounded,
      ColorClashNoticeTone.error => Icons.error_rounded,
      ColorClashNoticeTone.info => Icons.info_rounded,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notice.message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, color: tone, size: 18),
            ),
        ],
      ),
    );
  }
}
