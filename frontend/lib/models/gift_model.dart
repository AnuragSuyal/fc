import 'gift_catalog_constants.dart';

class GiftModel {
  final String id;
  final String? databaseId;
  final String name;
  final String description;
  final String icon;
  final String assetPath;

  // Pricing
  final int coinsPrice;
  final int gemsPrice;

  // Categorization
  final String category; // simple, premium, luxury, limited
  final int tier;
  final String rarity;
  final int sortOrder;

  // Animation
  final Map<String, dynamic> animation;

  // Effects
  final Map<String, dynamic> effects;

  // Availability
  final bool isLimited;
  final int? totalAvailable;
  final int? sold;
  final DateTime? startDate;
  final DateTime? endDate;

  // Requirements
  final int minLevel;
  final int requiredVip;

  // Stats
  final int totalSent;

  // Status
  final bool isActive;

  GiftModel({
    required this.id,
    this.databaseId,
    required this.name,
    required this.description,
    required this.icon,
    required this.assetPath,
    required this.coinsPrice,
    required this.gemsPrice,
    required this.category,
    required this.tier,
    required this.rarity,
    required this.sortOrder,
    required this.animation,
    required this.effects,
    required this.isLimited,
    this.totalAvailable,
    this.sold,
    this.startDate,
    this.endDate,
    required this.minLevel,
    required this.requiredVip,
    required this.totalSent,
    required this.isActive,
  });

  factory GiftModel.fromJson(Map<String, dynamic> json) {
    final category = normalizeGiftCategoryKey(json['category']?.toString());
    final databaseId = json['_id']?.toString();
    final stableId = json['giftId']?.toString() ??
        json['id']?.toString() ??
        databaseId ??
        '';
    final assetPath =
        json['assetPath']?.toString() ?? json['icon']?.toString() ?? '';

    return GiftModel(
      id: stableId,
      databaseId: databaseId,
      name: json['name']?.toString() ?? 'Gift',
      description: json['description']?.toString() ?? '',
      icon: assetPath,
      assetPath: assetPath,
      coinsPrice: json['price']?['coins'] ?? 0,
      gemsPrice: json['price']?['gems'] ?? 0,
      category: category,
      tier: json['tier'] ?? 1,
      rarity: json['rarity']?.toString() ?? category,
      sortOrder:
          json['sortOrder'] is num ? (json['sortOrder'] as num).toInt() : 0,
      animation: json['animation'] is Map
          ? Map<String, dynamic>.from(json['animation'])
          : <String, dynamic>{},
      effects: json['effects'] is Map
          ? Map<String, dynamic>.from(json['effects'])
          : <String, dynamic>{},
      isLimited:
          json['isLimited'] == true || json['availability']?['limited'] == true,
      totalAvailable: json['availability']?['totalAvailable'],
      sold: json['availability']?['sold'],
      startDate: json['availability']?['startDate'] != null
          ? DateTime.parse(json['availability']['startDate'])
          : null,
      endDate: json['availability']?['endDate'] != null
          ? DateTime.parse(json['availability']['endDate'])
          : null,
      minLevel: json['requirements']?['minLevel'] ?? 0,
      requiredVip: json['requirements']?['requiredVip'] ?? 0,
      totalSent: json['stats']?['totalSent'] ?? 0,
      isActive: json['isActive'] ?? json['active'] ?? true,
    );
  }

  String get artworkSource => assetPath.isNotEmpty ? assetPath : icon;

  bool get active => isActive;

  // Helper to check if gift is affordable
  bool canAfford(int userCoins, int userGems) {
    return userCoins >= coinsPrice && userGems >= gemsPrice;
  }

  // Helper to check if gift is available
  bool isAvailable() {
    if (!isActive) return false;
    if (!isLimited) return true;

    final now = DateTime.now();
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    if (totalAvailable != null && sold != null && sold! >= totalAvailable!) {
      return false;
    }

    return true;
  }

  // Helper to get remaining count
  int? getRemaining() {
    if (!isLimited || totalAvailable == null || sold == null) return null;
    return totalAvailable! - sold!;
  }
}
