class VipLevelModel {
  final int level;
  final String name;
  final String description;
  final List<VipBenefit> benefits;
  final int minSpend;
  final int price;
  final int annualPrice;
  final String color;
  final String icon;
  final int coinBonus;

  VipLevelModel({
    required this.level,
    required this.name,
    required this.description,
    required this.benefits,
    required this.minSpend,
    required this.price,
    required this.annualPrice,
    required this.color,
    required this.icon,
    required this.coinBonus,
  });

  factory VipLevelModel.fromJson(Map<String, dynamic> json) {
    return VipLevelModel(
      level: json['level'] ?? 0,
      name: _cleanText(json['name']?.toString() ?? 'Free'),
      description: _cleanText(json['description']?.toString() ?? ''),
      benefits: (json['benefits'] as List? ?? [])
          .map((b) => VipBenefit.fromJson(Map<String, dynamic>.from(b as Map)))
          .toList(),
      minSpend: json['minSpend'] ?? 0,
      price: json['price'] ?? 0,
      annualPrice: json['annualPrice'] ?? 0,
      color: json['color'] ?? '#808080',
      icon: json['icon']?.toString() ?? 'VIP',
      coinBonus: json['coinBonus'] ?? 0,
    );
  }

  static String _cleanText(String value) {
    return value
        .replaceAll('Ã—', 'x')
        .replaceAll('Ã¢â‚¬Â¢', '')
        .replaceAll('Ã°Å¸â€ â€œ', 'VIP')
        .trim();
  }
}

class VipBenefit {
  final String id;
  final String name;
  final String description;

  VipBenefit({
    required this.id,
    required this.name,
    required this.description,
  });

  factory VipBenefit.fromJson(Map<String, dynamic> json) {
    return VipBenefit(
      id: json['id'] ?? '',
      name: VipLevelModel._cleanText(json['name']?.toString() ?? ''),
      description: VipLevelModel._cleanText(json['description']?.toString() ?? ''),
    );
  }
}

class VipStatusModel {
  final VipLevelModel currentLevel;
  final VipLevelModel? nextLevel;
  final double progress;
  final Map<String, dynamic>? progressToNext;
  final int totalSpent;
  final DateTime? expiry;

  VipStatusModel({
    required this.currentLevel,
    this.nextLevel,
    required this.progress,
    this.progressToNext,
    required this.totalSpent,
    this.expiry,
  });

  factory VipStatusModel.fromJson(Map<String, dynamic> json) {
    return VipStatusModel(
      currentLevel: VipLevelModel.fromJson(
        Map<String, dynamic>.from((json['currentLevel'] as Map?) ?? const {}),
      ),
      nextLevel: json['nextLevel'] != null
          ? VipLevelModel.fromJson(
              Map<String, dynamic>.from(json['nextLevel'] as Map),
            )
          : null,
      progress: (json['progress'] ?? 0).toDouble(),
      progressToNext: json['progressToNext'] is Map
          ? Map<String, dynamic>.from(json['progressToNext'] as Map)
          : null,
      totalSpent: json['totalSpent'] ?? 0,
      expiry: json['expiry'] != null
          ? DateTime.tryParse(json['expiry'].toString())
          : null,
    );
  }

  bool get isVip => currentLevel.level > 0;
  bool get hasExpiry => expiry != null;
  bool get isExpired => hasExpiry && expiry!.isBefore(DateTime.now());
  bool get isActive => isVip && !isExpired;

  double get progressRatio {
    final value = progress > 1 ? progress / 100 : progress;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  int get daysRemaining {
    if (expiry == null) return 0;
    final diff = expiry!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }
}
