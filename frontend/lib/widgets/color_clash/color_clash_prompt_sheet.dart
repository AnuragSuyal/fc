import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import 'color_clash_visuals.dart';

Future<String?> showColorClashHuePrompt(
  BuildContext context, {
  required List<String> hues,
  String? title,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PromptSheet(
        title: title ?? 'Choose a hue',
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: hues
              .map(
                (hue) => InkWell(
                  onTap: () => Navigator.of(context).pop(hue),
                  borderRadius: BorderRadius.circular(20),
                  child: Ink(
                    width: 92,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: colorClashHueGradient(hue),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.blur_circular_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          colorClashHueTitle(hue),
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      );
    },
  );
}

Future<int?> showColorClashSeatPrompt(
  BuildContext context, {
  required List<int> seats,
  String? title,
}) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PromptSheet(
        title: title ?? 'Choose a target seat',
        child: Column(
          children: seats
              .map(
                (seat) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    tileColor: AppColors.backgroundWhite,
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primaryBlue,
                      child: Icon(
                        Icons.person_outline_rounded,
                        color: Colors.white,
                      ),
                    ),
                    title: Text('Seat ${seat + 1}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).pop(seat),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      );
    },
  );
}

class _PromptSheet extends StatelessWidget {
  const _PromptSheet({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: context.mood.outlineSoft),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
