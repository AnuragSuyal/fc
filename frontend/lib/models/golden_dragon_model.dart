class GoldenDragonProduct {
  const GoldenDragonProduct({
    required this.sku,
    required this.packageType,
    required this.name,
    required this.priceInr,
    required this.currency,
    required this.packetCoinAmount,
    required this.artworkAssetKey,
    required this.badgeLabel,
    this.availableCount = 0,
  });

  final String sku;
  final String packageType;
  final String name;
  final int priceInr;
  final String currency;
  final int packetCoinAmount;
  final String artworkAssetKey;
  final String badgeLabel;
  final int availableCount;

  factory GoldenDragonProduct.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return GoldenDragonProduct(
      sku: map['sku']?.toString() ?? '',
      packageType: map['packageType']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Golden Dragon Packet',
      priceInr: _asInt(map['priceInr'], fallback: 0),
      currency: map['currency']?.toString() ?? 'INR',
      packetCoinAmount: _asInt(map['packetCoinAmount'], fallback: 0),
      artworkAssetKey:
          map['artworkAssetKey']?.toString() ?? 'golden_dragon_packet_small',
      badgeLabel: map['badgeLabel']?.toString() ?? '',
      availableCount: _asInt(map['availableCount'], fallback: 0),
    );
  }

  String get artworkAssetPath => 'assets/images/$artworkAssetKey.png';
}

class GoldenDragonConfig {
  const GoldenDragonConfig({
    required this.featureEnabled,
    required this.allowedRoomTypes,
    required this.eventDurationMs,
    required this.participantJoinCutoffRemainingMs,
    required this.minimumRoomPresenceSeconds,
    required this.minimumAccountAgeDaysToClaim,
    required this.requireVerifiedAccountToClaim,
    required this.activatorCanClaim,
    required this.basePoolPercentage,
    required this.maxSharePercentagePerUser,
    required this.minValidTapsToParticipate,
    required this.maxCountedTapsPerSecond,
    required this.maxTotalCountedTaps,
    required this.maxCountedTapsPerRollingWindow,
    required this.rollingWindowSeconds,
    required this.leaderboardBroadcastIntervalMs,
    required this.inventoryRefundMode,
    required this.products,
  });

  final bool featureEnabled;
  final List<String> allowedRoomTypes;
  final int eventDurationMs;
  final int participantJoinCutoffRemainingMs;
  final int minimumRoomPresenceSeconds;
  final int minimumAccountAgeDaysToClaim;
  final bool requireVerifiedAccountToClaim;
  final bool activatorCanClaim;
  final int basePoolPercentage;
  final int maxSharePercentagePerUser;
  final int minValidTapsToParticipate;
  final int maxCountedTapsPerSecond;
  final int maxTotalCountedTaps;
  final int maxCountedTapsPerRollingWindow;
  final int rollingWindowSeconds;
  final int leaderboardBroadcastIntervalMs;
  final String inventoryRefundMode;
  final List<GoldenDragonProduct> products;

  factory GoldenDragonConfig.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return GoldenDragonConfig(
      featureEnabled: map['featureEnabled'] == true,
      allowedRoomTypes: _asStringList(map['allowedRoomTypes']),
      eventDurationMs: _asInt(map['eventDurationMs'], fallback: 10000),
      participantJoinCutoffRemainingMs:
          _asInt(map['participantJoinCutoffRemainingMs'], fallback: 5000),
      minimumRoomPresenceSeconds:
          _asInt(map['minimumRoomPresenceSeconds'], fallback: 2),
      minimumAccountAgeDaysToClaim:
          _asInt(map['minimumAccountAgeDaysToClaim'], fallback: 0),
      requireVerifiedAccountToClaim:
          map['requireVerifiedAccountToClaim'] == true,
      activatorCanClaim: map['activatorCanClaim'] == true,
      basePoolPercentage: _asInt(map['basePoolPercentage'], fallback: 30),
      maxSharePercentagePerUser:
          _asInt(map['maxSharePercentagePerUser'], fallback: 20),
      minValidTapsToParticipate:
          _asInt(map['minValidTapsToParticipate'], fallback: 1),
      maxCountedTapsPerSecond:
          _asInt(map['maxCountedTapsPerSecond'], fallback: 8),
      maxTotalCountedTaps: _asInt(map['maxTotalCountedTaps'], fallback: 50),
      maxCountedTapsPerRollingWindow:
          _asInt(map['maxCountedTapsPerRollingWindow'], fallback: 14),
      rollingWindowSeconds: _asInt(map['rollingWindowSeconds'], fallback: 2),
      leaderboardBroadcastIntervalMs:
          _asInt(map['leaderboardBroadcastIntervalMs'], fallback: 1000),
      inventoryRefundMode:
          map['inventoryRefundMode']?.toString() ?? 'restore_inventory',
      products: _asListOfMaps(map['products'])
          .map(GoldenDragonProduct.fromJson)
          .toList(growable: false),
    );
  }
}

class DragonPacketInventorySummary {
  const DragonPacketInventorySummary({
    required this.availableTotal,
    required this.availableCounts,
  });

  final int availableTotal;
  final Map<String, int> availableCounts;

  factory DragonPacketInventorySummary.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    final availableCounts = <String, int>{};
    final rawCounts = map['availableCounts'];
    if (rawCounts is Map) {
      for (final entry in rawCounts.entries) {
        availableCounts[entry.key.toString()] =
            _asInt(entry.value, fallback: 0);
      }
    }
    return DragonPacketInventorySummary(
      availableTotal: _asInt(map['availableTotal'], fallback: 0),
      availableCounts: availableCounts,
    );
  }
}

class DragonPacketInventoryItem {
  const DragonPacketInventoryItem({
    required this.id,
    required this.userId,
    required this.productSku,
    required this.packageType,
    required this.packetCoinAmount,
    required this.purchasePriceInr,
    required this.currency,
    required this.purchaseSource,
    required this.purchaseStatus,
    required this.inventoryStatus,
    required this.paymentReference,
    required this.metadata,
    this.purchasedAt,
    this.reservedAt,
    this.consumedAt,
    this.refundedAt,
    this.revokedAt,
    this.linkedEventId = '',
    this.product,
  });

  final String id;
  final String userId;
  final String productSku;
  final String packageType;
  final int packetCoinAmount;
  final int purchasePriceInr;
  final String currency;
  final String purchaseSource;
  final String purchaseStatus;
  final String inventoryStatus;
  final DateTime? purchasedAt;
  final DateTime? reservedAt;
  final DateTime? consumedAt;
  final DateTime? refundedAt;
  final DateTime? revokedAt;
  final String linkedEventId;
  final Map<String, dynamic> paymentReference;
  final Map<String, dynamic> metadata;
  final GoldenDragonProduct? product;

  factory DragonPacketInventoryItem.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return DragonPacketInventoryItem(
      id: map['id']?.toString() ?? map['_id']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      productSku: map['productSku']?.toString() ?? '',
      packageType: map['packageType']?.toString() ?? '',
      packetCoinAmount: _asInt(map['packetCoinAmount'], fallback: 0),
      purchasePriceInr: _asInt(map['purchasePriceInr'], fallback: 0),
      currency: map['currency']?.toString() ?? 'INR',
      purchaseSource: map['purchaseSource']?.toString() ?? '',
      purchaseStatus: map['purchaseStatus']?.toString() ?? '',
      inventoryStatus: map['inventoryStatus']?.toString() ?? '',
      purchasedAt: _asDateTime(map['purchasedAt']),
      reservedAt: _asDateTime(map['reservedAt']),
      consumedAt: _asDateTime(map['consumedAt']),
      refundedAt: _asDateTime(map['refundedAt']),
      revokedAt: _asDateTime(map['revokedAt']),
      linkedEventId: map['linkedEventId']?.toString() ?? '',
      paymentReference: _asMap(map['paymentReference']),
      metadata: _asMap(map['metadata']),
      product: map['product'] is Map<String, dynamic>
          ? GoldenDragonProduct.fromJson(map['product'] as Map<String, dynamic>)
          : map['product'] is Map
              ? GoldenDragonProduct.fromJson(
                  Map<String, dynamic>.from(map['product'] as Map),
                )
              : null,
    );
  }

  bool get isAvailable =>
      inventoryStatus == 'available' && purchaseStatus == 'completed';

  String get artworkAssetPath =>
      product?.artworkAssetPath ??
      'assets/images/${_fallbackAssetKey(productSku, packageType)}.png';
}

class DragonPacketProductsResponse {
  const DragonPacketProductsResponse({
    required this.config,
    required this.products,
  });

  final GoldenDragonConfig config;
  final List<GoldenDragonProduct> products;

  factory DragonPacketProductsResponse.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return DragonPacketProductsResponse(
      config: GoldenDragonConfig.fromJson(
        map['config'] is Map<String, dynamic>
            ? map['config'] as Map<String, dynamic>
            : map['config'] is Map
                ? Map<String, dynamic>.from(map['config'] as Map)
                : map,
      ),
      products: _asListOfMaps(map['products'])
          .map(GoldenDragonProduct.fromJson)
          .toList(growable: false),
    );
  }
}

class DragonPacketInventoryResponse {
  const DragonPacketInventoryResponse({
    required this.config,
    required this.products,
    required this.summary,
    required this.items,
    required this.allItems,
  });

  final GoldenDragonConfig config;
  final List<GoldenDragonProduct> products;
  final DragonPacketInventorySummary summary;
  final List<DragonPacketInventoryItem> items;
  final List<DragonPacketInventoryItem> allItems;

  factory DragonPacketInventoryResponse.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return DragonPacketInventoryResponse(
      config: GoldenDragonConfig.fromJson(_asMap(map['config'])),
      products: _asListOfMaps(map['products'])
          .map(GoldenDragonProduct.fromJson)
          .toList(growable: false),
      summary: DragonPacketInventorySummary.fromJson(_asMap(map['summary'])),
      items: _asListOfMaps(map['items'])
          .map(DragonPacketInventoryItem.fromJson)
          .toList(growable: false),
      allItems: _asListOfMaps(map['allItems'])
          .map(DragonPacketInventoryItem.fromJson)
          .toList(growable: false),
    );
  }
}

class GoldenDragonPurchaseResult {
  const GoldenDragonPurchaseResult({
    required this.success,
    required this.pendingCheckout,
    required this.checkoutUrl,
    required this.checkoutSessionId,
    this.inventoryItem,
    this.config,
  });

  final bool success;
  final bool pendingCheckout;
  final String checkoutUrl;
  final String checkoutSessionId;
  final DragonPacketInventoryItem? inventoryItem;
  final GoldenDragonConfig? config;

  factory GoldenDragonPurchaseResult.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return GoldenDragonPurchaseResult(
      success: map['success'] == true,
      pendingCheckout: map['pendingCheckout'] == true,
      checkoutUrl: map['checkoutUrl']?.toString() ?? '',
      checkoutSessionId: map['checkoutSessionId']?.toString() ?? '',
      inventoryItem: map['inventoryItem'] is Map<String, dynamic>
          ? DragonPacketInventoryItem.fromJson(
              map['inventoryItem'] as Map<String, dynamic>,
            )
          : map['inventoryItem'] is Map
              ? DragonPacketInventoryItem.fromJson(
                  Map<String, dynamic>.from(map['inventoryItem'] as Map),
                )
              : null,
      config: map['config'] is Map<String, dynamic>
          ? GoldenDragonConfig.fromJson(map['config'] as Map<String, dynamic>)
          : map['config'] is Map
              ? GoldenDragonConfig.fromJson(
                  Map<String, dynamic>.from(map['config'] as Map),
                )
              : null,
    );
  }
}

class GoldenDragonClaimParticipant {
  const GoldenDragonClaimParticipant({
    required this.participantId,
    required this.userId,
    required this.username,
    required this.avatar,
    required this.acceptedTapCount,
    required this.rawTapCount,
    required this.computedScore,
    required this.finalCoinReward,
    required this.finalRank,
    required this.eligibilityStatus,
    required this.payoutStatus,
    required this.fraudFlags,
    this.firstTapAt,
    this.lastTapAt,
  });

  final String participantId;
  final String userId;
  final String username;
  final String avatar;
  final int acceptedTapCount;
  final int rawTapCount;
  final double computedScore;
  final int finalCoinReward;
  final int finalRank;
  final String eligibilityStatus;
  final String payoutStatus;
  final List<String> fraudFlags;
  final DateTime? firstTapAt;
  final DateTime? lastTapAt;

  factory GoldenDragonClaimParticipant.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return GoldenDragonClaimParticipant(
      participantId:
          map['participantId']?.toString() ?? map['_id']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      username: map['username']?.toString() ?? 'User',
      avatar: map['avatar']?.toString() ?? '',
      acceptedTapCount: _asInt(map['acceptedTapCount'], fallback: 0),
      rawTapCount: _asInt(map['rawTapCount'], fallback: 0),
      computedScore: _asDouble(map['computedScore'], fallback: 0),
      finalCoinReward: _asInt(map['finalCoinReward'], fallback: 0),
      finalRank: _asInt(map['finalRank'], fallback: 0),
      eligibilityStatus: map['eligibilityStatus']?.toString() ?? 'pending',
      payoutStatus: map['payoutStatus']?.toString() ?? 'pending',
      fraudFlags: _asStringList(map['fraudFlags']),
      firstTapAt: _asDateTime(map['firstTapAt']),
      lastTapAt: _asDateTime(map['lastTapAt']),
    );
  }
}

class GoldenDragonEventBase {
  const GoldenDragonEventBase({
    required this.eventId,
    required this.eventReferenceId,
    required this.roomId,
    required this.roomName,
    required this.activatorUserId,
    required this.activatorName,
    required this.activatorAvatar,
    required this.productSku,
    required this.packageType,
    required this.packetTotalCoins,
    required this.eventStatus,
    required this.eventDurationMs,
    required this.dragonVisualType,
    this.startAtServer,
    this.endAtServer,
    this.joinCutoffAtServer,
    this.settledAt,
    this.totalValidClaimants = 0,
    this.totalDistributed = 0,
    this.totalRefunded = 0,
    this.configSnapshot = const <String, dynamic>{},
  });

  final String eventId;
  final String eventReferenceId;
  final String roomId;
  final String roomName;
  final String activatorUserId;
  final String activatorName;
  final String activatorAvatar;
  final String productSku;
  final String packageType;
  final int packetTotalCoins;
  final String eventStatus;
  final DateTime? startAtServer;
  final DateTime? endAtServer;
  final DateTime? joinCutoffAtServer;
  final DateTime? settledAt;
  final int totalValidClaimants;
  final int totalDistributed;
  final int totalRefunded;
  final int eventDurationMs;
  final String dragonVisualType;
  final Map<String, dynamic> configSnapshot;

  bool get isLive =>
      eventStatus == 'scheduled' ||
      eventStatus == 'live' ||
      eventStatus == 'settling';

  bool get isSettled =>
      eventStatus == 'settled' ||
      eventStatus == 'no_claim' ||
      eventStatus == 'refunded';

  int remainingMsAt(DateTime now) {
    if (endAtServer == null) return 0;
    return endAtServer!.difference(now).inMilliseconds.clamp(0, 1 << 31);
  }

  int get remainingMs => remainingMsAt(DateTime.now());

  bool get tapWindowOpen {
    final now = DateTime.now();
    if (startAtServer == null || endAtServer == null) return false;
    return now.isAfter(startAtServer!) && now.isBefore(endAtServer!);
  }
}

GoldenDragonEventBase _eventBaseFromJson(Map<String, dynamic>? json) {
  final map = json ?? const <String, dynamic>{};
  return GoldenDragonEventBase(
    eventId: map['eventId']?.toString() ?? '',
    eventReferenceId: map['eventReferenceId']?.toString() ?? '',
    roomId: map['roomId']?.toString() ?? '',
    roomName: map['roomName']?.toString() ?? 'Voice Room',
    activatorUserId: map['activatorUserId']?.toString() ?? '',
    activatorName: map['activatorName']?.toString() ?? 'Someone',
    activatorAvatar: map['activatorAvatar']?.toString() ?? '',
    productSku: map['productSku']?.toString() ?? '',
    packageType: map['packageType']?.toString() ?? '',
    packetTotalCoins: _asInt(map['packetTotalCoins'], fallback: 0),
    eventStatus: map['eventStatus']?.toString() ?? '',
    startAtServer: _asDateTime(map['startAtServer']),
    endAtServer: _asDateTime(map['endAtServer']),
    joinCutoffAtServer: _asDateTime(map['joinCutoffAtServer']),
    settledAt: _asDateTime(map['settledAt']),
    totalValidClaimants: _asInt(map['totalValidClaimants'], fallback: 0),
    totalDistributed: _asInt(map['totalDistributed'], fallback: 0),
    totalRefunded: _asInt(map['totalRefunded'], fallback: 0),
    eventDurationMs: _asInt(map['eventDurationMs'], fallback: 10000),
    dragonVisualType: map['dragonVisualType']?.toString() ?? '',
    configSnapshot: _asMap(map['configSnapshot']),
  );
}

class GoldenDragonLiveEvent extends GoldenDragonEventBase {
  GoldenDragonLiveEvent({
    required super.eventId,
    required super.eventReferenceId,
    required super.roomId,
    required super.roomName,
    required super.activatorUserId,
    required super.activatorName,
    required super.activatorAvatar,
    required super.productSku,
    required super.packageType,
    required super.packetTotalCoins,
    required super.eventStatus,
    required super.eventDurationMs,
    required super.dragonVisualType,
    super.startAtServer,
    super.endAtServer,
    super.joinCutoffAtServer,
    super.settledAt,
    super.totalValidClaimants,
    super.totalDistributed,
    super.totalRefunded,
    super.configSnapshot,
  });

  factory GoldenDragonLiveEvent.fromJson(Map<String, dynamic>? json) {
    final base = _eventBaseFromJson(json);
    return GoldenDragonLiveEvent(
      eventId: base.eventId,
      eventReferenceId: base.eventReferenceId,
      roomId: base.roomId,
      roomName: base.roomName,
      activatorUserId: base.activatorUserId,
      activatorName: base.activatorName,
      activatorAvatar: base.activatorAvatar,
      productSku: base.productSku,
      packageType: base.packageType,
      packetTotalCoins: base.packetTotalCoins,
      eventStatus: base.eventStatus,
      startAtServer: base.startAtServer,
      endAtServer: base.endAtServer,
      joinCutoffAtServer: base.joinCutoffAtServer,
      settledAt: base.settledAt,
      totalValidClaimants: base.totalValidClaimants,
      totalDistributed: base.totalDistributed,
      totalRefunded: base.totalRefunded,
      eventDurationMs: base.eventDurationMs,
      dragonVisualType: base.dragonVisualType,
      configSnapshot: base.configSnapshot,
    );
  }
}

class GoldenDragonActiveEventResponse {
  const GoldenDragonActiveEventResponse({
    required this.active,
    this.event,
    this.myClaim,
  });

  final bool active;
  final GoldenDragonLiveEvent? event;
  final GoldenDragonClaimParticipant? myClaim;

  factory GoldenDragonActiveEventResponse.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return GoldenDragonActiveEventResponse(
      active: map['active'] == true,
      event: map['event'] is Map<String, dynamic>
          ? GoldenDragonLiveEvent.fromJson(
              map['event'] as Map<String, dynamic>,
            )
          : map['event'] is Map
              ? GoldenDragonLiveEvent.fromJson(
                  Map<String, dynamic>.from(map['event'] as Map),
                )
              : null,
      myClaim: map['myClaim'] is Map<String, dynamic>
          ? GoldenDragonClaimParticipant.fromJson(
              map['myClaim'] as Map<String, dynamic>,
            )
          : map['myClaim'] is Map
              ? GoldenDragonClaimParticipant.fromJson(
                  Map<String, dynamic>.from(map['myClaim'] as Map),
                )
              : null,
    );
  }
}

class GoldenDragonActivationResult {
  const GoldenDragonActivationResult({
    required this.success,
    required this.event,
    this.inventory,
  });

  final bool success;
  final GoldenDragonLiveEvent event;
  final DragonPacketInventoryItem? inventory;

  factory GoldenDragonActivationResult.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return GoldenDragonActivationResult(
      success: map['success'] == true,
      event: GoldenDragonLiveEvent.fromJson(_asMap(map['event'])),
      inventory: map['inventory'] is Map<String, dynamic>
          ? DragonPacketInventoryItem.fromJson(
              map['inventory'] as Map<String, dynamic>,
            )
          : map['inventory'] is Map
              ? DragonPacketInventoryItem.fromJson(
                  Map<String, dynamic>.from(map['inventory'] as Map),
                )
              : null,
    );
  }
}

class GoldenDragonLeaderboard {
  const GoldenDragonLeaderboard({
    required this.eventId,
    required this.roomId,
    required this.roomName,
    required this.countdownMs,
    required this.countdownSeconds,
    required this.totalParticipants,
    required this.hypeState,
    required this.topClaimants,
    this.updatedAt,
  });

  final String eventId;
  final String roomId;
  final String roomName;
  final int countdownMs;
  final int countdownSeconds;
  final int totalParticipants;
  final String hypeState;
  final List<GoldenDragonClaimParticipant> topClaimants;
  final DateTime? updatedAt;

  factory GoldenDragonLeaderboard.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return GoldenDragonLeaderboard(
      eventId: map['eventId']?.toString() ?? '',
      roomId: map['roomId']?.toString() ?? '',
      roomName: map['roomName']?.toString() ?? 'Voice Room',
      countdownMs: _asInt(map['countdownMs'], fallback: 0),
      countdownSeconds: _asInt(map['countdownSeconds'], fallback: 0),
      totalParticipants: _asInt(map['totalParticipants'], fallback: 0),
      hypeState: map['hypeState']?.toString() ?? 'warming_up',
      topClaimants: _asListOfMaps(map['topClaimants'])
          .map(GoldenDragonClaimParticipant.fromJson)
          .toList(growable: false),
      updatedAt: _asDateTime(map['updatedAt']),
    );
  }
}

class GoldenDragonTapAck {
  const GoldenDragonTapAck({
    required this.eventId,
    required this.accepted,
    required this.tapCounted,
    required this.currentCountedTaps,
    required this.riskState,
  });

  final String eventId;
  final bool accepted;
  final bool tapCounted;
  final int currentCountedTaps;
  final String riskState;

  factory GoldenDragonTapAck.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return GoldenDragonTapAck(
      eventId: map['eventId']?.toString() ?? '',
      accepted: map['accepted'] == true,
      tapCounted: map['tapCounted'] == true,
      currentCountedTaps: _asInt(map['currentCountedTaps'], fallback: 0),
      riskState: map['riskState']?.toString() ?? '',
    );
  }
}

class GoldenDragonEventResult extends GoldenDragonEventBase {
  GoldenDragonEventResult({
    required super.eventId,
    required super.eventReferenceId,
    required super.roomId,
    required super.roomName,
    required super.activatorUserId,
    required super.activatorName,
    required super.activatorAvatar,
    required super.productSku,
    required super.packageType,
    required super.packetTotalCoins,
    required super.eventStatus,
    required super.eventDurationMs,
    required super.dragonVisualType,
    required this.winners,
    required this.totalParticipants,
    required this.packetExhausted,
    required this.refundStatus,
    this.myClaim,
    super.startAtServer,
    super.endAtServer,
    super.joinCutoffAtServer,
    super.settledAt,
    super.totalValidClaimants,
    super.totalDistributed,
    super.totalRefunded,
    super.configSnapshot,
  });

  final List<GoldenDragonClaimParticipant> winners;
  final GoldenDragonClaimParticipant? myClaim;
  final int totalParticipants;
  final bool packetExhausted;
  final String refundStatus;

  factory GoldenDragonEventResult.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    final base = _eventBaseFromJson(map);
    return GoldenDragonEventResult(
      eventId: base.eventId,
      eventReferenceId: base.eventReferenceId,
      roomId: base.roomId,
      roomName: base.roomName,
      activatorUserId: base.activatorUserId,
      activatorName: base.activatorName,
      activatorAvatar: base.activatorAvatar,
      productSku: base.productSku,
      packageType: base.packageType,
      packetTotalCoins: base.packetTotalCoins,
      eventStatus: base.eventStatus,
      startAtServer: base.startAtServer,
      endAtServer: base.endAtServer,
      joinCutoffAtServer: base.joinCutoffAtServer,
      settledAt: base.settledAt,
      totalValidClaimants: base.totalValidClaimants,
      totalDistributed: base.totalDistributed,
      totalRefunded: base.totalRefunded,
      eventDurationMs: base.eventDurationMs,
      dragonVisualType: base.dragonVisualType,
      configSnapshot: base.configSnapshot,
      winners: _asListOfMaps(map['winners'])
          .map(GoldenDragonClaimParticipant.fromJson)
          .toList(growable: false),
      myClaim: map['myClaim'] is Map<String, dynamic>
          ? GoldenDragonClaimParticipant.fromJson(
              map['myClaim'] as Map<String, dynamic>,
            )
          : map['myClaim'] is Map
              ? GoldenDragonClaimParticipant.fromJson(
                  Map<String, dynamic>.from(map['myClaim'] as Map),
                )
              : null,
      totalParticipants: _asInt(map['totalParticipants'], fallback: 0),
      packetExhausted: map['packetExhausted'] == true,
      refundStatus: map['refundStatus']?.toString() ?? 'none',
    );
  }
}

class GoldenDragonHistoryItem extends GoldenDragonEventBase {
  GoldenDragonHistoryItem({
    required super.eventId,
    required super.eventReferenceId,
    required super.roomId,
    required super.roomName,
    required super.activatorUserId,
    required super.activatorName,
    required super.activatorAvatar,
    required super.productSku,
    required super.packageType,
    required super.packetTotalCoins,
    required super.eventStatus,
    required super.eventDurationMs,
    required super.dragonVisualType,
    required this.winnerCount,
    this.myClaim,
    super.startAtServer,
    super.endAtServer,
    super.joinCutoffAtServer,
    super.settledAt,
    super.totalValidClaimants,
    super.totalDistributed,
    super.totalRefunded,
    super.configSnapshot,
  });

  final GoldenDragonClaimParticipant? myClaim;
  final int winnerCount;

  factory GoldenDragonHistoryItem.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    final base = _eventBaseFromJson(map);
    return GoldenDragonHistoryItem(
      eventId: base.eventId,
      eventReferenceId: base.eventReferenceId,
      roomId: base.roomId,
      roomName: base.roomName,
      activatorUserId: base.activatorUserId,
      activatorName: base.activatorName,
      activatorAvatar: base.activatorAvatar,
      productSku: base.productSku,
      packageType: base.packageType,
      packetTotalCoins: base.packetTotalCoins,
      eventStatus: base.eventStatus,
      startAtServer: base.startAtServer,
      endAtServer: base.endAtServer,
      joinCutoffAtServer: base.joinCutoffAtServer,
      settledAt: base.settledAt,
      totalValidClaimants: base.totalValidClaimants,
      totalDistributed: base.totalDistributed,
      totalRefunded: base.totalRefunded,
      eventDurationMs: base.eventDurationMs,
      dragonVisualType: base.dragonVisualType,
      configSnapshot: base.configSnapshot,
      myClaim: map['myClaim'] is Map<String, dynamic>
          ? GoldenDragonClaimParticipant.fromJson(
              map['myClaim'] as Map<String, dynamic>,
            )
          : map['myClaim'] is Map
              ? GoldenDragonClaimParticipant.fromJson(
                  Map<String, dynamic>.from(map['myClaim'] as Map),
                )
              : null,
      winnerCount: _asInt(map['winnerCount'], fallback: 0),
    );
  }
}

class GoldenDragonHistoryPage {
  const GoldenDragonHistoryPage({
    required this.events,
    required this.page,
    required this.limit,
    required this.total,
    required this.pages,
  });

  final List<GoldenDragonHistoryItem> events;
  final int page;
  final int limit;
  final int total;
  final int pages;

  factory GoldenDragonHistoryPage.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    final pagination = _asMap(map['pagination']);
    return GoldenDragonHistoryPage(
      events: _asListOfMaps(map['events'])
          .map(GoldenDragonHistoryItem.fromJson)
          .toList(growable: false),
      page: _asInt(pagination['page'], fallback: 1),
      limit: _asInt(pagination['limit'], fallback: 20),
      total: _asInt(pagination['total'], fallback: 0),
      pages: _asInt(pagination['pages'], fallback: 1),
    );
  }
}

String _fallbackAssetKey(String sku, String packageType) {
  if (sku.contains('large') || packageType == 'large') {
    return 'golden_dragon_packet_large';
  }
  if (sku.contains('medium') || packageType == 'medium') {
    return 'golden_dragon_packet_medium';
  }
  return 'golden_dragon_packet_small';
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
}

List<String> _asStringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value.map((entry) => entry.toString()).toList(growable: false);
}

DateTime? _asDateTime(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

double _asDouble(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? fallback;
}
