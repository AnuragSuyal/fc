import 'package:flutter/material.dart';

import '../../models/shop_models.dart';
import '../../utils/shop_appearance_resolver.dart';
import 'shop_item_artwork.dart';

class ShopInventoryItemCard extends StatelessWidget {
  final ShopInventoryEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onToggleFavorite;
  final bool favoriteBusy;

  const ShopInventoryItemCard({
    super.key,
    required this.entry,
    this.onTap,
    this.onToggleFavorite,
    this.favoriteBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final colors = resolvePreviewColors(
      item?.previewStyle ?? const {},
      itemId: item?.itemId ?? entry.itemId,
      rarity: item?.rarity ?? 'common',
    );
    final accent = colors.first;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: accent.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 74,
                height: 58,
                child: ShopItemArtwork(
                  itemId: item?.itemId ?? entry.itemId,
                  previewStyle: item?.previewStyle ?? const {},
                  rarity: item?.rarity ?? 'common',
                  width: 74,
                  height: 58,
                  borderRadius: BorderRadius.circular(18),
                  iconSize: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item?.itemName ?? entry.itemId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (entry.quantity > 1)
                          _MiniChip(
                            label: 'x${entry.quantity}',
                            color: accent,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item?.itemDescription ?? 'Inventory item',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniChip(
                          label: (item?.rarity ?? 'common').toUpperCase(),
                          color: resolveShopRarityColor(item?.rarity ?? ''),
                        ),
                        if (entry.isEquipped)
                          const _MiniChip(
                            label: 'EQUIPPED',
                            color: Color(0xFF34D399),
                          ),
                        if (entry.isActive)
                          const _MiniChip(
                            label: 'ACTIVE',
                            color: Color(0xFF8B5CF6),
                          ),
                        if (entry.isExpired)
                          const _MiniChip(
                            label: 'EXPIRED',
                            color: Color(0xFFE11D48),
                          ),
                        if (!entry.isExpired &&
                            entry.expiryAt != null &&
                            item?.isTemporary == true)
                          _MiniChip(
                            label: _expiryLabel(entry.expiryAt!),
                            color: const Color(0xFFF59E0B),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: favoriteBusy ? null : onToggleFavorite,
                icon: favoriteBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        entry.favorited
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: entry.favorited
                            ? const Color(0xFFF59E0B)
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.54),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _expiryLabel(DateTime expiryAt) {
    final difference = expiryAt.difference(DateTime.now());
    if (difference.inDays >= 1) {
      return '${difference.inDays}d left';
    }
    if (difference.inHours >= 1) {
      return '${difference.inHours}h left';
    }
    final minutes = difference.inMinutes < 0 ? 0 : difference.inMinutes;
    return '${minutes}m left';
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
