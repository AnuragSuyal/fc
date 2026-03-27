class GiftModel {
  final String id;
  final String name;
  final String description;
  final String icon;

  // Pricing
  final int coinsPrice;
  final int gemsPrice;

  // Categorization
  final String category; // simple, premium, luxury, legendary
  final int tier;

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
  final bool active;

  GiftModel({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.coinsPrice,
    required this.gemsPrice,
    required this.category,
    required this.tier,
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
    required this.active,
  });

  factory GiftModel.fromJson(Map<String, dynamic> json) {
    return GiftModel(
      id: json['_id'] ?? '',
      name: json['name'] ?? 'Gift',
      description: json['description'] ?? '',
      icon: json['icon'] ?? 'ðŸŽ',
      coinsPrice: json['price']?['coins'] ?? 0,
      gemsPrice: json['price']?['gems'] ?? 0,
      category: json['category'] ?? 'simple',
      tier: json['tier'] ?? 1,
      animation: json['animation'] ?? {},
      effects: json['effects'] ?? {},
      isLimited: json['availability']?['limited'] ?? false,
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
      active: json['active'] ?? true,
    );
  }

  // Helper to check if gift is affordable
  bool canAfford(int userCoins, int userGems) {
    return userCoins >= coinsPrice && userGems >= gemsPrice;
  }

  // Helper to check if gift is available
  bool isAvailable() {
    if (!active) return false;
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






