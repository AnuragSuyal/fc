import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/shop_models.dart';

void main() {
  test('shop home payload parses catalog sections and first reward', () {
    final home = ShopHomeData.fromJson({
      'balance': {'coins': 3200, 'level': 18, 'xp': 9400},
      'shopProfile': {
        'equipped': {'profileFrameItemId': 'frame_neon'},
        'activeBoosts': {'xpBoostItemId': 'booster_xp_2x_1h'},
      },
      'categories': [
        {
          'id': 'profile_cosmetics',
          'name': 'Profile',
          'description': 'Frames',
          'itemCount': 10,
        }
      ],
      'catalog': [
        {
          'itemId': 'frame_neon',
          'itemName': 'Neon Frame',
          'itemDescription': 'Bright profile frame',
          'itemCategory': 'profile_cosmetics',
          'itemSubcategory': 'profile_frame',
          'itemType': 'permanent_cosmetic',
          'rarity': 'rare',
          'priceCoins': 650,
          'effectivePriceCoins': 650,
          'tags': ['NEW'],
          'previewStyle': {
            'icon': 'bolt',
            'colors': ['#10E7FF', '#7C4DFF'],
          },
          'owned': true,
          'equipped': true,
        }
      ],
      'sections': {
        'featured': [
          {
            'itemId': 'frame_neon',
            'itemName': 'Neon Frame',
            'itemDescription': 'Bright profile frame',
            'itemCategory': 'profile_cosmetics',
            'itemSubcategory': 'profile_frame',
            'itemType': 'permanent_cosmetic',
            'rarity': 'rare',
            'priceCoins': 650,
            'effectivePriceCoins': 650,
            'previewStyle': {'icon': 'bolt'},
            'owned': true,
            'equipped': true,
          }
        ],
        'collectionProgress': [
          {
            'collectionSetId': 'galaxy_set',
            'name': 'Galaxy Set',
            'description': 'Cosmic items',
            'totalItems': 6,
            'ownedItems': 2,
            'progressPercent': 33.3,
            'complete': false,
          }
        ]
      },
      'inventorySummary': {
        'totalEntries': 3,
        'ownedEntries': 3,
        'equippedEntries': 1,
        'activeEntries': 1,
        'favoriteEntries': 0,
        'expiredEntries': 0,
      },
      'firstPurchaseReward': {
        'itemId': 'collectible_lucky_coin_totem',
        'itemName': 'Lucky Coin Totem',
        'itemDescription': 'A first-purchase collectible',
        'itemCategory': 'collectibles',
        'itemSubcategory': 'totem',
        'itemType': 'collectible',
        'rarity': 'rare',
        'priceCoins': 0,
        'effectivePriceCoins': 0,
      },
    });

    expect(home.balance['coins'], 3200);
    expect(home.shopProfile.equipped['profileFrameItemId'], 'frame_neon');
    expect(home.catalog.single.owned, isTrue);
    expect(home.sections.featured.single.equipped, isTrue);
    expect(home.sections.collectionProgress.single.progressPercent, 33.3);
    expect(home.firstPurchaseReward?.itemId, 'collectible_lucky_coin_totem');
  });

  test('inventory payload parses expiry and active states', () {
    final inventory = ShopInventoryData.fromJson({
      'shopProfile': {
        'activeBoosts': {
          'xpBoostItemId': 'booster_xp_2x_1h',
          'xpBoostMultiplier': 2,
        }
      },
      'summary': {
        'totalEntries': 2,
        'ownedEntries': 2,
        'equippedEntries': 1,
        'activeEntries': 1,
        'favoriteEntries': 1,
        'expiredEntries': 0,
      },
      'collections': [],
      'items': [
        {
          'inventoryEntryId': 'inv_1',
          'userId': 'user_1',
          'itemId': 'frame_neon',
          'quantity': 1,
          'isEquipped': true,
          'favorited': true,
          'item': {
            'itemId': 'frame_neon',
            'itemName': 'Neon Frame',
            'itemDescription': 'Bright profile frame',
            'itemCategory': 'profile_cosmetics',
            'itemSubcategory': 'profile_frame',
            'itemType': 'permanent_cosmetic',
            'rarity': 'rare',
            'priceCoins': 650,
            'effectivePriceCoins': 650,
          }
        },
        {
          'inventoryEntryId': 'inv_2',
          'userId': 'user_1',
          'itemId': 'booster_xp_2x_1h',
          'quantity': 0,
          'isActive': true,
          'item': {
            'itemId': 'booster_xp_2x_1h',
            'itemName': '2x XP Booster 1 hour',
            'itemDescription': 'Boost XP gains',
            'itemCategory': 'boosters',
            'itemSubcategory': 'xp_boost',
            'itemType': 'booster',
            'rarity': 'rare',
            'priceCoins': 380,
            'effectivePriceCoins': 380,
          }
        }
      ],
    });

    expect(inventory.summary.activeEntries, 1);
    expect(inventory.items.first.isEquipped, isTrue);
    expect(inventory.items.first.favorited, isTrue);
    expect(inventory.items.last.isActive, isTrue);
    expect(inventory.shopProfile.activeBoosts['xpBoostMultiplier'], 2);
  });
}
