import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/shop_models.dart';
import 'package:frontend/utils/shop_item_asset_registry.dart';

void main() {
  test('registry resolves direct and aliased item artwork paths', () {
    expect(
      ShopItemAssetRegistry.resolveItemAssetPath('frame_neon'),
      'assets/shop_catalog/frames/frame_neon.png',
    );
    expect(
      ShopItemAssetRegistry.resolveItemAssetPath('mic_ring_diamond'),
      'assets/shop_catalog/mic_auras/mic_aura_diamond.png',
    );
    expect(
      ShopItemAssetRegistry.resolveItemAssetPath('capsule_mystery'),
      'assets/shop_catalog/collectibles/collectible_mystery_capsule.png',
    );
    expect(
      ShopItemAssetRegistry.resolveItemAssetPath('bundle_creator_boost_pack'),
      'assets/shop_catalog/bundles/bundle_creator_boost.png',
    );
    expect(
      ShopItemAssetRegistry.resolveItemAssetPath('utility_spotlight_ticket'),
      'assets/shop_catalog/boosters/ticket_spotlight.png',
    );
  });

  test('registry resolves shop promo badges and section decorations', () {
    final dailyDeal = ShopCatalogItem.fromJson({
      'itemId': 'frame_neon',
      'itemName': 'Neon Frame',
      'itemDescription': 'Bright profile frame',
      'itemCategory': 'profile_cosmetics',
      'itemSubcategory': 'profile_frame',
      'itemType': 'permanent_cosmetic',
      'rarity': 'rare',
      'priceCoins': 650,
      'effectivePriceCoins': 520,
      'isDailyDeal': true,
    });

    final bestValue = ShopCatalogItem.fromJson({
      'itemId': 'bundle_profile_glow_pack',
      'itemName': 'Profile Glow Pack',
      'itemDescription': 'Bundle',
      'itemCategory': 'bundles',
      'itemSubcategory': 'bundle',
      'itemType': 'bundle',
      'rarity': 'rare',
      'priceCoins': 1540,
      'effectivePriceCoins': 1540,
      'tags': ['BEST VALUE'],
    });

    expect(
      ShopItemAssetRegistry.resolveBadgeAssetPath(dailyDeal),
      'assets/shop_catalog/ui/badge_daily_deal.png',
    );
    expect(
      ShopItemAssetRegistry.resolveBadgeAssetPath(bestValue),
      'assets/shop_catalog/ui/badge_best_value.png',
    );
    expect(
      ShopItemAssetRegistry.resolveSectionDecoration('Mystery Capsules')
          ?.assetPath,
      'assets/shop_catalog/ui/shop_banner_mystery.png',
    );
  });
}
