import 'package:flutter/material.dart';

import '../../utils/shop_appearance_resolver.dart';
import '../../utils/shop_item_asset_registry.dart';

class ShopItemArtwork extends StatelessWidget {
  final String itemId;
  final Map<String, dynamic> previewStyle;
  final String rarity;
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final double iconSize;

  const ShopItemArtwork({
    super.key,
    required this.itemId,
    required this.previewStyle,
    required this.rarity,
    required this.width,
    required this.height,
    required this.borderRadius,
    this.iconSize = 26,
  });

  @override
  Widget build(BuildContext context) {
    final binding = ShopItemAssetRegistry.resolveItem(itemId);
    final colors = resolvePreviewColors(
      previewStyle,
      itemId: itemId,
      rarity: rarity,
    );
    final icon = resolvePreviewIcon(
      previewStyle['icon'],
      itemId: itemId,
    );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.first.withValues(alpha: 0.24),
            colors.length > 1
                ? colors[1].withValues(alpha: 0.16)
                : colors.first.withValues(alpha: 0.10),
            const Color(0xFF0D1118),
          ],
          stops: const [0, 0.42, 1],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topLeft,
                  radius: 1.1,
                  colors: [
                    colors.first.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            if (binding?.prefersAvatarCore == true)
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: width * 0.48,
                  height: width * 0.48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.94),
                        colors.first.withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                ),
              ),
            if (binding != null)
              Padding(
                padding: _paddingFor(binding.category),
                child: RepaintBoundary(
                  child: Image.asset(
                    binding.assetPath,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              )
            else
              Center(
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: iconSize,
                ),
              ),
          ],
        ),
      ),
    );
  }

  EdgeInsets _paddingFor(ShopAssetCategory category) {
    switch (category) {
      case ShopAssetCategory.frames:
        return const EdgeInsets.all(6);
      case ShopAssetCategory.nameplates:
        return const EdgeInsets.symmetric(horizontal: 8, vertical: 18);
      case ShopAssetCategory.bundles:
        return const EdgeInsets.all(8);
      case ShopAssetCategory.collectibles:
      case ShopAssetCategory.entryEffects:
      case ShopAssetCategory.micAuras:
      case ShopAssetCategory.chatBubbles:
      case ShopAssetCategory.boosters:
        return const EdgeInsets.all(10);
      case ShopAssetCategory.uiBadge:
      case ShopAssetCategory.banner:
        return const EdgeInsets.all(0);
    }
  }
}

class ShopImageBadge extends StatelessWidget {
  final String assetPath;
  final double height;

  const ShopImageBadge({
    super.key,
    required this.assetPath,
    this.height = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
