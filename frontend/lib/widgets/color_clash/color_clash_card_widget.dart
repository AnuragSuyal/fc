import 'package:flutter/material.dart';

import '../../models/color_clash_card_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import 'color_clash_visuals.dart';

class ColorClashCardWidget extends StatelessWidget {
  const ColorClashCardWidget({
    super.key,
    required this.card,
    this.isSelected = false,
    this.isPlayable = false,
    this.isDimmed = false,
    this.onTap,
    this.height = 150,
  });

  final ColorClashCardModel card;
  final bool isSelected;
  final bool isPlayable;
  final bool isDimmed;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tone = colorClashCardTone(card);
    final labelColor = card.isNumberCard ? Colors.white : tone;
    final background = card.isNumberCard
        ? colorClashHueGradient(card.hue)
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              tone.withValues(alpha: 0.12),
            ],
          );

    return Opacity(
      opacity: isDimmed ? 0.42 : 1,
      child: AnimatedScale(
        scale: isSelected ? 1.04 : 1,
        duration: const Duration(milliseconds: 180),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: height * 0.72,
          height: height,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: onTap,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: background,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: isSelected
                        ? tone
                        : isPlayable
                            ? tone.withValues(alpha: 0.65)
                            : context.mood.outlineSoft,
                    width: isSelected ? 2.2 : 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tone.withValues(
                        alpha: isSelected
                            ? 0.24
                            : isPlayable
                                ? 0.14
                                : 0.06,
                      ),
                      blurRadius: isSelected ? 18 : 12,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              card.hueLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: card.isNumberCard
                                        ? Colors.white.withValues(alpha: 0.88)
                                        : tone,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          if (isPlayable)
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: AppColors.successGreen,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: height * 0.34,
                          height: height * 0.34,
                          decoration: BoxDecoration(
                            color: card.isNumberCard
                                ? Colors.white.withValues(alpha: 0.22)
                                : tone.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: card.isNumberCard
                              ? Center(
                                  child: Text(
                                    '${card.value ?? ''}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          color: labelColor,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                )
                              : Icon(
                                  colorClashCardIcon(card.kind),
                                  color: tone,
                                  size: height * 0.16,
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        card.shortLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: labelColor,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        card.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: card.isNumberCard
                                  ? Colors.white.withValues(alpha: 0.82)
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
