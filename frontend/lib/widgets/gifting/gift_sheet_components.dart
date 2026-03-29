import 'package:flutter/material.dart';

import '../../models/gift_model.dart';
import '../gift_image.dart';
import '../currency_icon.dart';
import 'gift_sheet_theme.dart';

class GiftBalancePill extends StatelessWidget {
  const GiftBalancePill({
    super.key,
    required this.amount,
    required this.icon,
    required this.gradient,
    required this.glowColor,
  });

  final int amount;
  final Widget icon;
  final Gradient gradient;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.16),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: gradient,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 6),
                Text(
                  '$amount',
                  style: const TextStyle(
                    color: Color(0xFF091018),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GiftCategoryChip extends StatelessWidget {
  const GiftCategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: selected
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0x24FFFFFF),
                  Color(0x22FFD772),
                  Color(0x18FF72C0),
                ],
              )
            : null,
        color: selected ? null : GiftSheetTokens.panel,
        border: Border.all(
          color: selected
              ? GiftSheetTokens.gold.withValues(alpha: 0.32)
              : GiftSheetTokens.border,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: GiftSheetTokens.gold.withValues(alpha: 0.14),
                  blurRadius: 18,
                ),
              ]
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? GiftSheetTokens.primaryText
                    : GiftSheetTokens.secondaryText,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GiftCatalogTile extends StatelessWidget {
  const GiftCatalogTile({
    super.key,
    required this.gift,
    required this.selected,
    required this.affordable,
    required this.onTap,
  });

  final GiftModel gift;
  final bool selected;
  final bool affordable;
  final VoidCallback onTap;

  bool get _usesCoins => gift.coinsPrice > 0;
  int get _amount => _usesCoins ? gift.coinsPrice : gift.gemsPrice;

  @override
  Widget build(BuildContext context) {
    final accent = _usesCoins ? GiftSheetTokens.gold : GiftSheetTokens.cyan;

    return AnimatedScale(
      scale: selected ? 1.02 : 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: affordable ? 1 : 0.68,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: GiftSheetTokens.innerGlass(
            selected: selected,
            tint: accent,
          ).copyWith(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: selected
                  ? [
                      accent.withValues(alpha: 0.18),
                      GiftSheetTokens.panelStrong,
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.06),
                      GiftSheetTokens.panel,
                    ],
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (gift.isLimited)
                          _MiniBadge(
                            label: 'LIMITED',
                            color: GiftSheetTokens.accent,
                          ),
                        const Spacer(),
                        if (!affordable)
                          _MiniBadge(
                            label: 'LOCKED',
                            color: GiftSheetTokens.danger,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: GiftVisualBadge(
                          gift: gift,
                          accent: accent,
                          selected: selected,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      gift.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: GiftSheetTokens.primaryText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      gift.description.isEmpty ? 'Live room collectible' : gift.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: GiftSheetTokens.secondaryText,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (_usesCoins)
                          const CurrencyIcon.coins(size: 13)
                        else
                          const CurrencyIcon.gems(size: 13),
                        const SizedBox(width: 4),
                        Text(
                          '$_amount',
                          style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        if (selected)
                          Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: accent,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GiftVisualBadge extends StatelessWidget {
  const GiftVisualBadge({
    super.key,
    required this.gift,
    required this.accent,
    required this.selected,
    this.size = 76,
  });

  final GiftModel gift;
  final Color accent;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            accent.withValues(alpha: selected ? 0.42 : 0.22),
            Colors.transparent,
          ],
        ),
      ),
        child: Center(
          child: Container(
          width: size * 0.84,
          height: size * 0.84,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.26),
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: accent.withValues(alpha: selected ? 0.4 : 0.16),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: selected ? 0.18 : 0.08),
                blurRadius: 18,
              ),
            ],
          ),
          child: GiftImage(
            source: gift.artworkSource,
            width: size * 0.84,
            height: size * 0.84,
            fit: BoxFit.contain,
            borderRadius: BorderRadius.circular(size * 0.24),
            fallback: Icon(
              Icons.card_giftcard_rounded,
              size: size * 0.4,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.55,
        ),
      ),
    );
  }
}
