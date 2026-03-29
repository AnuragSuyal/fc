import 'package:flutter/material.dart';
import '../models/gift_model.dart';
import '../screens/gifts/send_gift_screen.dart';
import '../theme/app_theme.dart';
import '../utils/constants.dart';
import 'currency_icon.dart';
import 'gift_image.dart';

class GiftCard extends StatelessWidget {
  final GiftModel gift;
  final bool showPrice;
  final VoidCallback? onTap;
  final bool isSelected;

  const GiftCard({
    super.key,
    required this.gift,
    this.showPrice = true,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;
    final tierColor = _tierColor(gift.tier);

    return GestureDetector(
      onTap: onTap ??
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SendGiftScreen(gift: gift),
              ),
            );
          },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              tierColor.withValues(alpha: 0.18),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppColors.primaryBlue : mood.outlineSoft,
            width: isSelected ? 2.2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  )
                ]
              : [
                  BoxShadow(
                    color: mood.shadow.withValues(alpha: 0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tierColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: GiftImage(
                source: gift.artworkSource,
                width: 44,
                height: 44,
                fallback: Icon(
                  Icons.card_giftcard_rounded,
                  color: tierColor,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              gift.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (showPrice) ...[
              const SizedBox(height: 4),
              if (gift.coinsPrice > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CurrencyIcon.coins(size: 14),
                    const SizedBox(width: 2),
                    Text(
                      '${gift.coinsPrice}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.warningOrange,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              if (gift.gemsPrice > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CurrencyIcon.gems(size: 14),
                    const SizedBox(width: 2),
                    Text(
                      '${gift.gemsPrice}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.accentBerry,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
            ],
            if (gift.isLimited && gift.getRemaining() != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.errorRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${gift.getRemaining()} left',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.errorRed,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _tierColor(int tier) {
    switch (tier) {
      case 1:
        return AppColors.accentSky;
      case 2:
        return AppColors.secondaryBlue;
      case 3:
        return AppColors.accentBerry;
      case 4:
        return AppColors.accentYellow;
      default:
        return AppColors.primaryBlue;
    }
  }
}
