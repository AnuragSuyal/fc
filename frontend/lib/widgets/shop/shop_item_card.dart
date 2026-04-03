import 'package:flutter/material.dart';

import '../../models/shop_models.dart';
import '../../utils/shop_appearance_resolver.dart';
import '../../utils/shop_item_asset_registry.dart';
import 'shop_item_artwork.dart';

class ShopItemCard extends StatelessWidget {
  final ShopCatalogItem item;
  final VoidCallback? onTap;
  final VoidCallback? onToggleWishlist;
  final bool wishlistBusy;
  final bool compact;

  const ShopItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.onToggleWishlist,
    this.wishlistBusy = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = resolvePreviewColors(
      item.previewStyle,
      itemId: item.itemId,
      rarity: item.rarity,
    );
    final rarityColor = resolveShopRarityColor(item.rarity);
    final badgeAsset = ShopItemAssetRegistry.resolveBadgeAssetPath(item);
    final width = compact ? 164.0 : 186.0;
    final padding = compact ? 14.0 : 16.0;

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.first.withValues(alpha: 0.94),
                  colors.length > 1
                      ? colors[1].withValues(alpha: 0.82)
                      : colors.first.withValues(alpha: 0.65),
                  const Color(0xFF0D1016),
                ],
                stops: const [0, 0.52, 1],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: colors.first.withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (badgeAsset != null)
                        ShopImageBadge(
                          assetPath: badgeAsset,
                          height: compact ? 24 : 26,
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            item.itemCategory.replaceAll('_', ' '),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.84),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      const Spacer(),
                      if (onToggleWishlist != null)
                        IconButton(
                          onPressed: wishlistBusy ? null : onToggleWishlist,
                          icon: wishlistBusy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  item.wishlisted
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: item.wishlisted
                                      ? const Color(0xFFFF85B3)
                                      : Colors.white.withValues(alpha: 0.84),
                                ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final artHeight = compact ? 78.0 : 90.0;
                      return ShopItemArtwork(
                        itemId: item.itemId,
                        previewStyle: item.previewStyle,
                        rarity: item.rarity,
                        width: constraints.maxWidth,
                        height: artHeight,
                        borderRadius: BorderRadius.circular(24),
                        iconSize: compact ? 24 : 28,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _buildTopTags(rarityColor),
                  ),
                  const Spacer(),
                  Text(
                    item.itemName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.itemDescription,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.76),
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.discountPercent > 0
                                  ? '${item.effectivePriceCoins}'
                                  : '${item.priceCoins}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            Text(
                              _statusLabel(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.72),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Text(
                          item.owned ? _ownedActionLabel() : 'Preview',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTopTags(Color rarityColor) {
    final tags = <Widget>[
      _TagChip(label: item.rarity.toUpperCase(), color: rarityColor),
    ];
    if (item.owned) {
      tags.add(
        _TagChip(
          label: item.equipped ? 'EQUIPPED' : 'OWNED',
          color: item.equipped ? const Color(0xFF34D399) : Colors.white70,
        ),
      );
    }
    if (item.isDailyDeal || item.discountPercent > 0) {
      tags.add(
        _TagChip(
          label:
              item.discountPercent > 0 ? '-${item.discountPercent}%' : 'DEAL',
          color: const Color(0xFFF59E0B),
        ),
      );
    }
    if (item.limitedEdition) {
      tags.add(const _TagChip(label: 'LIMITED', color: Color(0xFFFF85B3)));
    }
    for (final tag in item.tags.take(2)) {
      tags.add(_TagChip(label: tag, color: Colors.white70));
    }
    return tags;
  }

  String _statusLabel() {
    if (!item.availableNow) {
      return 'Unavailable right now';
    }
    if (item.owned) {
      if (item.equipped) return 'Active on your profile';
      if (item.active) return 'Currently active';
      if (item.quantity > 1) return '${item.quantity} in inventory';
      return 'Ready in inventory';
    }
    if (item.bundleContents.isNotEmpty) {
      return '${item.bundleContents.length} item bundle';
    }
    if (item.itemType == 'capsule') {
      return 'Open for random rewards';
    }
    return '${item.priceCoins} coins';
  }

  String _ownedActionLabel() {
    if (item.isEquippable) {
      return item.equipped ? 'Manage' : 'Equip';
    }
    if (item.activationRequired) {
      return item.itemType == 'capsule' ? 'Open' : 'Use';
    }
    return 'Details';
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;

  const _TagChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.35,
            ),
      ),
    );
  }
}
