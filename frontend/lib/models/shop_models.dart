class UserShopProfile {
  final Map<String, String> equipped;
  final Map<String, dynamic> activeBoosts;
  final DateTime? firstShopPurchaseAt;
  final DateTime? lastInventoryUpdatedAt;
  final List<String> recentlyViewedItemIds;

  const UserShopProfile({
    this.equipped = const {},
    this.activeBoosts = const {},
    this.firstShopPurchaseAt,
    this.lastInventoryUpdatedAt,
    this.recentlyViewedItemIds = const [],
  });

  factory UserShopProfile.fromJson(dynamic json) {
    if (json is! Map) return const UserShopProfile();
    final equipped = <String, String>{};
    final activeBoosts = <String, dynamic>{};

    if (json['equipped'] is Map) {
      for (final entry in (json['equipped'] as Map).entries) {
        equipped[entry.key.toString()] = entry.value?.toString() ?? '';
      }
    }
    if (json['activeBoosts'] is Map) {
      for (final entry in (json['activeBoosts'] as Map).entries) {
        activeBoosts[entry.key.toString()] = entry.value;
      }
    }

    return UserShopProfile(
      equipped: equipped,
      activeBoosts: activeBoosts,
      firstShopPurchaseAt: json['firstShopPurchaseAt'] != null
          ? DateTime.tryParse(json['firstShopPurchaseAt'].toString())
          : null,
      lastInventoryUpdatedAt: json['lastInventoryUpdatedAt'] != null
          ? DateTime.tryParse(json['lastInventoryUpdatedAt'].toString())
          : null,
      recentlyViewedItemIds: json['recentlyViewedItemIds'] is List
          ? List<String>.from(
              (json['recentlyViewedItemIds'] as List)
                  .map((entry) => entry.toString())
                  .where((entry) => entry.isNotEmpty),
            )
          : const [],
    );
  }

  String equippedItem(String slot) => equipped[slot] ?? '';

  Map<String, dynamic> toJson() => {
        'equipped': equipped,
        'activeBoosts': activeBoosts,
        'firstShopPurchaseAt': firstShopPurchaseAt?.toIso8601String(),
        'lastInventoryUpdatedAt': lastInventoryUpdatedAt?.toIso8601String(),
        'recentlyViewedItemIds': recentlyViewedItemIds,
      };
}

class ShopCollectionProgress {
  final String collectionSetId;
  final String name;
  final String description;
  final int totalItems;
  final int ownedItems;
  final double progressPercent;
  final bool complete;

  const ShopCollectionProgress({
    required this.collectionSetId,
    required this.name,
    required this.description,
    required this.totalItems,
    required this.ownedItems,
    required this.progressPercent,
    required this.complete,
  });

  factory ShopCollectionProgress.fromJson(dynamic json) {
    final map = json is Map ? Map<String, dynamic>.from(json) : const {};
    return ShopCollectionProgress(
      collectionSetId: map['collectionSetId']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      totalItems: _toInt(map['totalItems']) ?? 0,
      ownedItems: _toInt(map['ownedItems']) ?? 0,
      progressPercent: _toDouble(map['progressPercent']) ?? 0,
      complete: map['complete'] == true,
    );
  }
}

class ShopCategorySummary {
  final String id;
  final String name;
  final String description;
  final int itemCount;

  const ShopCategorySummary({
    required this.id,
    required this.name,
    required this.description,
    required this.itemCount,
  });

  factory ShopCategorySummary.fromJson(dynamic json) {
    final map = json is Map ? Map<String, dynamic>.from(json) : const {};
    return ShopCategorySummary(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      itemCount: _toInt(map['itemCount']) ?? 0,
    );
  }
}

class ShopDropRewardPreview {
  final String itemId;
  final String itemName;
  final String rarity;
  final int quantity;
  final double chancePercent;

  const ShopDropRewardPreview({
    required this.itemId,
    required this.itemName,
    required this.rarity,
    required this.quantity,
    required this.chancePercent,
  });

  factory ShopDropRewardPreview.fromJson(dynamic json) {
    final map = json is Map ? Map<String, dynamic>.from(json) : const {};
    return ShopDropRewardPreview(
      itemId: map['itemId']?.toString() ?? '',
      itemName: map['itemName']?.toString() ?? '',
      rarity: map['rarity']?.toString() ?? 'common',
      quantity: _toInt(map['quantity']) ?? 1,
      chancePercent: _toDouble(map['chancePercent']) ?? 0,
    );
  }
}

class ShopCatalogItem {
  final String itemId;
  final String itemName;
  final String itemDescription;
  final String itemCategory;
  final String itemSubcategory;
  final String itemType;
  final String rarity;
  final int priceCoins;
  final int effectivePriceCoins;
  final List<String> tags;
  final bool isConsumable;
  final bool isEquippable;
  final bool isTemporary;
  final int expiryDurationSeconds;
  final bool isStackable;
  final bool activationRequired;
  final bool oneActivePerCategory;
  final bool bundleOnly;
  final bool limitedEdition;
  final int stockCount;
  final int? remainingStock;
  final bool isFeatured;
  final bool isPopular;
  final bool isDailyDeal;
  final String offerLabel;
  final int discountPercent;
  final DateTime? offerEndsAt;
  final List<Map<String, dynamic>> bundleContents;
  final int bundleValueCoins;
  final String collectionSetId;
  final Map<String, dynamic> featureFlags;
  final Map<String, dynamic> previewStyle;
  final String equipSlot;
  final bool availableNow;
  final bool owned;
  final int quantity;
  final bool equipped;
  final bool favorited;
  final bool active;
  final bool wishlisted;
  final bool expired;
  final List<ShopDropRewardPreview> dropTablePreview;

  const ShopCatalogItem({
    required this.itemId,
    required this.itemName,
    required this.itemDescription,
    required this.itemCategory,
    required this.itemSubcategory,
    required this.itemType,
    required this.rarity,
    required this.priceCoins,
    required this.effectivePriceCoins,
    required this.tags,
    required this.isConsumable,
    required this.isEquippable,
    required this.isTemporary,
    required this.expiryDurationSeconds,
    required this.isStackable,
    required this.activationRequired,
    required this.oneActivePerCategory,
    required this.bundleOnly,
    required this.limitedEdition,
    required this.stockCount,
    required this.remainingStock,
    required this.isFeatured,
    required this.isPopular,
    required this.isDailyDeal,
    required this.offerLabel,
    required this.discountPercent,
    required this.offerEndsAt,
    required this.bundleContents,
    required this.bundleValueCoins,
    required this.collectionSetId,
    required this.featureFlags,
    required this.previewStyle,
    required this.equipSlot,
    required this.availableNow,
    required this.owned,
    required this.quantity,
    required this.equipped,
    required this.favorited,
    required this.active,
    required this.wishlisted,
    required this.expired,
    required this.dropTablePreview,
  });

  factory ShopCatalogItem.fromJson(dynamic json) {
    final map = json is Map ? Map<String, dynamic>.from(json) : const {};
    return ShopCatalogItem(
      itemId: map['itemId']?.toString() ?? '',
      itemName: map['itemName']?.toString() ?? '',
      itemDescription: map['itemDescription']?.toString() ?? '',
      itemCategory: map['itemCategory']?.toString() ?? '',
      itemSubcategory: map['itemSubcategory']?.toString() ?? '',
      itemType: map['itemType']?.toString() ?? '',
      rarity: map['rarity']?.toString() ?? 'common',
      priceCoins: _toInt(map['priceCoins']) ?? 0,
      effectivePriceCoins: _toInt(map['effectivePriceCoins']) ?? 0,
      tags: map['tags'] is List
          ? List<String>.from(
              (map['tags'] as List).map((entry) => entry.toString()))
          : const [],
      isConsumable: map['isConsumable'] == true,
      isEquippable: map['isEquippable'] == true,
      isTemporary: map['isTemporary'] == true,
      expiryDurationSeconds: _toInt(map['expiryDurationSeconds']) ?? 0,
      isStackable: map['isStackable'] == true,
      activationRequired: map['activationRequired'] == true,
      oneActivePerCategory: map['oneActivePerCategory'] == true,
      bundleOnly: map['bundleOnly'] == true,
      limitedEdition: map['limitedEdition'] == true,
      stockCount: _toInt(map['stockCount']) ?? 0,
      remainingStock: _toInt(map['remainingStock']),
      isFeatured: map['isFeatured'] == true,
      isPopular: map['isPopular'] == true,
      isDailyDeal: map['isDailyDeal'] == true,
      offerLabel: map['offerLabel']?.toString() ?? '',
      discountPercent: _toInt(map['discountPercent']) ?? 0,
      offerEndsAt: map['offerEndsAt'] != null
          ? DateTime.tryParse(map['offerEndsAt'].toString())
          : null,
      bundleContents: map['bundleContents'] is List
          ? List<Map<String, dynamic>>.from(
              (map['bundleContents'] as List).whereType<Map>().map(
                    (entry) => Map<String, dynamic>.from(entry),
                  ),
            )
          : const [],
      bundleValueCoins: _toInt(map['bundleValueCoins']) ?? 0,
      collectionSetId: map['collectionSetId']?.toString() ?? '',
      featureFlags: map['featureFlags'] is Map
          ? Map<String, dynamic>.from(map['featureFlags'] as Map)
          : const {},
      previewStyle: map['previewStyle'] is Map
          ? Map<String, dynamic>.from(map['previewStyle'] as Map)
          : const {},
      equipSlot: map['equipSlot']?.toString() ?? '',
      availableNow: map['availableNow'] != false,
      owned: map['owned'] == true,
      quantity: _toInt(map['quantity']) ?? 0,
      equipped: map['equipped'] == true,
      favorited: map['favorited'] == true,
      active: map['active'] == true,
      wishlisted: map['wishlisted'] == true,
      expired: map['expired'] == true,
      dropTablePreview: map['dropTablePreview'] is List
          ? List<ShopDropRewardPreview>.from(
              (map['dropTablePreview'] as List)
                  .map(ShopDropRewardPreview.fromJson),
            )
          : const [],
    );
  }
}

class ShopInventoryEntry {
  final String inventoryEntryId;
  final String userId;
  final String itemId;
  final int quantity;
  final DateTime? acquiredAt;
  final DateTime? expiryAt;
  final bool isExpired;
  final bool isEquipped;
  final bool isActive;
  final bool favorited;
  final String sourceType;
  final String sourceReferenceId;
  final DateTime? lastUsedAt;
  final int usageCount;
  final Map<String, dynamic> metadata;
  final ShopCatalogItem? item;

  const ShopInventoryEntry({
    required this.inventoryEntryId,
    required this.userId,
    required this.itemId,
    required this.quantity,
    required this.acquiredAt,
    required this.expiryAt,
    required this.isExpired,
    required this.isEquipped,
    required this.isActive,
    required this.favorited,
    required this.sourceType,
    required this.sourceReferenceId,
    required this.lastUsedAt,
    required this.usageCount,
    required this.metadata,
    required this.item,
  });

  factory ShopInventoryEntry.fromJson(dynamic json) {
    final map = json is Map ? Map<String, dynamic>.from(json) : const {};
    return ShopInventoryEntry(
      inventoryEntryId: map['inventoryEntryId']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      itemId: map['itemId']?.toString() ?? '',
      quantity: _toInt(map['quantity']) ?? 0,
      acquiredAt: map['acquiredAt'] != null
          ? DateTime.tryParse(map['acquiredAt'].toString())
          : null,
      expiryAt: map['expiryAt'] != null
          ? DateTime.tryParse(map['expiryAt'].toString())
          : null,
      isExpired: map['isExpired'] == true,
      isEquipped: map['isEquipped'] == true,
      isActive: map['isActive'] == true,
      favorited: map['favorited'] == true,
      sourceType: map['sourceType']?.toString() ?? '',
      sourceReferenceId: map['sourceReferenceId']?.toString() ?? '',
      lastUsedAt: map['lastUsedAt'] != null
          ? DateTime.tryParse(map['lastUsedAt'].toString())
          : null,
      usageCount: _toInt(map['usageCount']) ?? 0,
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : const {},
      item: map['item'] is Map ? ShopCatalogItem.fromJson(map['item']) : null,
    );
  }
}

class ShopInventorySummary {
  final int totalEntries;
  final int ownedEntries;
  final int equippedEntries;
  final int activeEntries;
  final int favoriteEntries;
  final int expiredEntries;

  const ShopInventorySummary({
    required this.totalEntries,
    required this.ownedEntries,
    required this.equippedEntries,
    required this.activeEntries,
    required this.favoriteEntries,
    required this.expiredEntries,
  });

  factory ShopInventorySummary.fromJson(dynamic json) {
    final map = json is Map ? Map<String, dynamic>.from(json) : const {};
    return ShopInventorySummary(
      totalEntries: _toInt(map['totalEntries']) ?? 0,
      ownedEntries: _toInt(map['ownedEntries']) ?? 0,
      equippedEntries: _toInt(map['equippedEntries']) ?? 0,
      activeEntries: _toInt(map['activeEntries']) ?? 0,
      favoriteEntries: _toInt(map['favoriteEntries']) ?? 0,
      expiredEntries: _toInt(map['expiredEntries']) ?? 0,
    );
  }
}

class ShopSections {
  final List<ShopCatalogItem> featured;
  final List<ShopCatalogItem> newArrivals;
  final List<ShopCatalogItem> popular;
  final List<ShopCatalogItem> limited;
  final List<ShopCatalogItem> dailyDeals;
  final List<ShopCatalogItem> weekendSpecials;
  final List<ShopCatalogItem> bundles;
  final List<ShopCatalogItem> mysteryCapsules;
  final List<ShopCatalogItem> lowCostImpulse;
  final List<ShopCatalogItem> aspiration;
  final List<ShopCatalogItem> recentlyViewed;
  final List<ShopCatalogItem> recommended;
  final List<ShopCatalogItem> wishlist;
  final List<ShopCollectionProgress> collectionProgress;

  const ShopSections({
    this.featured = const [],
    this.newArrivals = const [],
    this.popular = const [],
    this.limited = const [],
    this.dailyDeals = const [],
    this.weekendSpecials = const [],
    this.bundles = const [],
    this.mysteryCapsules = const [],
    this.lowCostImpulse = const [],
    this.aspiration = const [],
    this.recentlyViewed = const [],
    this.recommended = const [],
    this.wishlist = const [],
    this.collectionProgress = const [],
  });

  factory ShopSections.fromJson(dynamic json) {
    final map = json is Map ? Map<String, dynamic>.from(json) : const {};
    List<ShopCatalogItem> parseItems(String key) => map[key] is List
        ? List<ShopCatalogItem>.from(
            (map[key] as List).map(ShopCatalogItem.fromJson),
          )
        : const [];
    return ShopSections(
      featured: parseItems('featured'),
      newArrivals: parseItems('newArrivals'),
      popular: parseItems('popular'),
      limited: parseItems('limited'),
      dailyDeals: parseItems('dailyDeals'),
      weekendSpecials: parseItems('weekendSpecials'),
      bundles: parseItems('bundles'),
      mysteryCapsules: parseItems('mysteryCapsules'),
      lowCostImpulse: parseItems('lowCostImpulse'),
      aspiration: parseItems('aspiration'),
      recentlyViewed: parseItems('recentlyViewed'),
      recommended: parseItems('recommended'),
      wishlist: parseItems('wishlist'),
      collectionProgress: map['collectionProgress'] is List
          ? List<ShopCollectionProgress>.from(
              (map['collectionProgress'] as List)
                  .map(ShopCollectionProgress.fromJson),
            )
          : const [],
    );
  }
}

class ShopHomeData {
  final Map<String, dynamic> balance;
  final UserShopProfile shopProfile;
  final List<ShopCategorySummary> categories;
  final List<ShopCatalogItem> catalog;
  final ShopSections sections;
  final ShopInventorySummary inventorySummary;
  final ShopCatalogItem? firstPurchaseReward;

  const ShopHomeData({
    required this.balance,
    required this.shopProfile,
    required this.categories,
    required this.catalog,
    required this.sections,
    required this.inventorySummary,
    required this.firstPurchaseReward,
  });

  factory ShopHomeData.fromJson(Map<String, dynamic> json) => ShopHomeData(
        balance: json['balance'] is Map
            ? Map<String, dynamic>.from(json['balance'] as Map)
            : const {},
        shopProfile: UserShopProfile.fromJson(json['shopProfile']),
        categories: json['categories'] is List
            ? List<ShopCategorySummary>.from(
                (json['categories'] as List).map(ShopCategorySummary.fromJson),
              )
            : const [],
        catalog: json['catalog'] is List
            ? List<ShopCatalogItem>.from(
                (json['catalog'] as List).map(ShopCatalogItem.fromJson),
              )
            : const [],
        sections: ShopSections.fromJson(json['sections']),
        inventorySummary:
            ShopInventorySummary.fromJson(json['inventorySummary']),
        firstPurchaseReward: json['firstPurchaseReward'] is Map
            ? ShopCatalogItem.fromJson(json['firstPurchaseReward'])
            : null,
      );
}

class ShopInventoryData {
  final UserShopProfile shopProfile;
  final ShopInventorySummary summary;
  final List<ShopCollectionProgress> collections;
  final List<ShopInventoryEntry> items;

  const ShopInventoryData({
    required this.shopProfile,
    required this.summary,
    required this.collections,
    required this.items,
  });

  factory ShopInventoryData.fromJson(Map<String, dynamic> json) =>
      ShopInventoryData(
        shopProfile: UserShopProfile.fromJson(json['shopProfile']),
        summary: ShopInventorySummary.fromJson(json['summary']),
        collections: json['collections'] is List
            ? List<ShopCollectionProgress>.from(
                (json['collections'] as List)
                    .map(ShopCollectionProgress.fromJson),
              )
            : const [],
        items: json['items'] is List
            ? List<ShopInventoryEntry>.from(
                (json['items'] as List).map(ShopInventoryEntry.fromJson),
              )
            : const [],
      );
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
