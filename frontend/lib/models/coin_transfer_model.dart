class CoinTransferReason {
  final String code;
  final String message;

  const CoinTransferReason({
    required this.code,
    required this.message,
  });

  factory CoinTransferReason.fromJson(Map<String, dynamic> json) {
    return CoinTransferReason(
      code: json['code']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
    );
  }
}

class CoinTransferFeePercentages {
  final int receiverPercentage;
  final int platformPercentage;

  const CoinTransferFeePercentages({
    required this.receiverPercentage,
    required this.platformPercentage,
  });

  factory CoinTransferFeePercentages.fromJson(Map<String, dynamic>? json) {
    return CoinTransferFeePercentages(
      receiverPercentage: _toInt(json?['receiverPercentage']) ?? 70,
      platformPercentage: _toInt(json?['platformPercentage']) ?? 30,
    );
  }
}

class CoinTransferWindowUsage {
  final int amountUsed;
  final int amountRemaining;
  final int countUsed;
  final int countRemaining;

  const CoinTransferWindowUsage({
    required this.amountUsed,
    required this.amountRemaining,
    required this.countUsed,
    required this.countRemaining,
  });

  factory CoinTransferWindowUsage.fromJson(Map<String, dynamic>? json) {
    return CoinTransferWindowUsage(
      amountUsed: _toInt(json?['amountUsed']) ?? 0,
      amountRemaining: _toInt(json?['amountRemaining']) ?? 0,
      countUsed: _toInt(json?['countUsed']) ?? 0,
      countRemaining: _toInt(json?['countRemaining']) ?? 0,
    );
  }
}

class CoinTransferUsage {
  final CoinTransferWindowUsage daily;
  final CoinTransferWindowUsage monthly;
  final int uniqueReceiversToday;
  final int uniqueReceiversRemainingToday;
  final int sameSenderToReceiverAmountToday;
  final int sameSenderToReceiverAmountRemainingToday;
  final int cooldownSecondsRemaining;
  final DateTime? friendshipConnectedAt;
  final int bilateralRecentCount;

  const CoinTransferUsage({
    required this.daily,
    required this.monthly,
    required this.uniqueReceiversToday,
    required this.uniqueReceiversRemainingToday,
    required this.sameSenderToReceiverAmountToday,
    required this.sameSenderToReceiverAmountRemainingToday,
    required this.cooldownSecondsRemaining,
    required this.friendshipConnectedAt,
    required this.bilateralRecentCount,
  });

  factory CoinTransferUsage.fromJson(Map<String, dynamic>? json) {
    return CoinTransferUsage(
      daily: CoinTransferWindowUsage.fromJson(
        json?['daily'] is Map
            ? Map<String, dynamic>.from(json!['daily'] as Map)
            : null,
      ),
      monthly: CoinTransferWindowUsage.fromJson(
        json?['monthly'] is Map
            ? Map<String, dynamic>.from(json!['monthly'] as Map)
            : null,
      ),
      uniqueReceiversToday: _toInt(json?['uniqueReceiversToday']) ?? 0,
      uniqueReceiversRemainingToday:
          _toInt(json?['uniqueReceiversRemainingToday']) ?? 0,
      sameSenderToReceiverAmountToday:
          _toInt(json?['sameSenderToReceiverAmountToday']) ?? 0,
      sameSenderToReceiverAmountRemainingToday:
          _toInt(json?['sameSenderToReceiverAmountRemainingToday']) ?? 0,
      cooldownSecondsRemaining: _toInt(json?['cooldownSecondsRemaining']) ?? 0,
      friendshipConnectedAt: DateTime.tryParse(
        json?['friendshipConnectedAt']?.toString() ?? '',
      ),
      bilateralRecentCount: _toInt(json?['bilateralRecentCount']) ?? 0,
    );
  }
}

class CoinTransferBreakdown {
  final int senderSpend;
  final int receiverAmount;
  final int platformFee;
  final int grossAmount;
  final CoinTransferFeePercentages feePercentages;

  const CoinTransferBreakdown({
    required this.senderSpend,
    required this.receiverAmount,
    required this.platformFee,
    required this.grossAmount,
    required this.feePercentages,
  });

  factory CoinTransferBreakdown.fromJson(Map<String, dynamic>? json) {
    final grossAmount =
        _toInt(json?['grossAmount']) ?? _toInt(json?['senderSpend']) ?? 0;
    return CoinTransferBreakdown(
      senderSpend: _toInt(json?['senderSpend']) ?? grossAmount,
      receiverAmount: _toInt(json?['receiverAmount']) ?? 0,
      platformFee: _toInt(json?['platformFee']) ?? 0,
      grossAmount: grossAmount,
      feePercentages: CoinTransferFeePercentages.fromJson(
        json?['feePercentages'] is Map
            ? Map<String, dynamic>.from(json!['feePercentages'] as Map)
            : {
                'receiverPercentage': _toInt(json?['receiverPercentage']) ?? 70,
                'platformPercentage': _toInt(json?['platformPercentage']) ?? 30,
              },
      ),
    );
  }

  factory CoinTransferBreakdown.calculate({
    required int amount,
    required CoinTransferFeePercentages feePercentages,
  }) {
    final receiverAmount = (amount * feePercentages.receiverPercentage) ~/ 100;
    return CoinTransferBreakdown(
      senderSpend: amount,
      receiverAmount: receiverAmount,
      platformFee: amount - receiverAmount,
      grossAmount: amount,
      feePercentages: feePercentages,
    );
  }
}

class CoinTransferEntitlement {
  final String id;
  final String userId;
  final String entitlementKey;
  final String purchaseSource;
  final int purchaseAmountInr;
  final String currency;
  final String status;
  final DateTime? purchasedAt;
  final DateTime? revokedAt;
  final DateTime? expiresAt;
  final Map<String, dynamic> metadata;

  const CoinTransferEntitlement({
    required this.id,
    required this.userId,
    required this.entitlementKey,
    required this.purchaseSource,
    required this.purchaseAmountInr,
    required this.currency,
    required this.status,
    required this.purchasedAt,
    required this.revokedAt,
    required this.expiresAt,
    required this.metadata,
  });

  factory CoinTransferEntitlement.fromJson(Map<String, dynamic>? json) {
    return CoinTransferEntitlement(
      id: json?['id']?.toString() ?? '',
      userId: json?['userId']?.toString() ?? '',
      entitlementKey: json?['entitlementKey']?.toString() ?? '',
      purchaseSource: json?['purchaseSource']?.toString() ?? '',
      purchaseAmountInr: _toInt(json?['purchaseAmountInr']) ?? 0,
      currency: json?['currency']?.toString() ?? 'INR',
      status: json?['status']?.toString() ?? '',
      purchasedAt: DateTime.tryParse(json?['purchasedAt']?.toString() ?? ''),
      revokedAt: DateTime.tryParse(json?['revokedAt']?.toString() ?? ''),
      expiresAt: DateTime.tryParse(json?['expiresAt']?.toString() ?? ''),
      metadata: json?['metadata'] is Map
          ? Map<String, dynamic>.from(json!['metadata'] as Map)
          : const <String, dynamic>{},
    );
  }
}

class CoinTransferLimits {
  final bool featureEnabled;
  final int unlockPriceInr;
  final String unlockCurrency;
  final int minTransferAmount;
  final int maxTransferPerTxn;
  final int dailySendLimitAmount;
  final int dailySendLimitCount;
  final int monthlySendLimitAmount;
  final int monthlySendLimitCount;
  final int cooldownSecondsBetweenTransfers;
  final int maxUniqueReceiversPerDay;
  final int maxReceivedFromSameSenderPerDay;
  final int accountAgeMinDaysForTransfer;
  final int minFriendshipAgeHours;
  final int minChatMessagesExchanged;
  final bool requireVerifiedAccount;
  final CoinTransferFeePercentages feePercentages;

  const CoinTransferLimits({
    required this.featureEnabled,
    required this.unlockPriceInr,
    required this.unlockCurrency,
    required this.minTransferAmount,
    required this.maxTransferPerTxn,
    required this.dailySendLimitAmount,
    required this.dailySendLimitCount,
    required this.monthlySendLimitAmount,
    required this.monthlySendLimitCount,
    required this.cooldownSecondsBetweenTransfers,
    required this.maxUniqueReceiversPerDay,
    required this.maxReceivedFromSameSenderPerDay,
    required this.accountAgeMinDaysForTransfer,
    required this.minFriendshipAgeHours,
    required this.minChatMessagesExchanged,
    required this.requireVerifiedAccount,
    required this.feePercentages,
  });

  factory CoinTransferLimits.fromJson(Map<String, dynamic>? json) {
    return CoinTransferLimits(
      featureEnabled: json?['featureEnabled'] == true,
      unlockPriceInr: _toInt(json?['unlockPriceInr']) ?? 599,
      unlockCurrency: json?['unlockCurrency']?.toString() ?? 'INR',
      minTransferAmount: _toInt(json?['minTransferAmount']) ?? 100,
      maxTransferPerTxn: _toInt(json?['maxTransferPerTxn']) ?? 100000,
      dailySendLimitAmount: _toInt(json?['dailySendLimitAmount']) ?? 50000,
      dailySendLimitCount: _toInt(json?['dailySendLimitCount']) ?? 20,
      monthlySendLimitAmount: _toInt(json?['monthlySendLimitAmount']) ?? 300000,
      monthlySendLimitCount: _toInt(json?['monthlySendLimitCount']) ?? 200,
      cooldownSecondsBetweenTransfers:
          _toInt(json?['cooldownSecondsBetweenTransfers']) ?? 30,
      maxUniqueReceiversPerDay: _toInt(json?['maxUniqueReceiversPerDay']) ?? 10,
      maxReceivedFromSameSenderPerDay:
          _toInt(json?['maxReceivedFromSameSenderPerDay']) ?? 50000,
      accountAgeMinDaysForTransfer:
          _toInt(json?['accountAgeMinDaysForTransfer']) ?? 7,
      minFriendshipAgeHours: _toInt(json?['minFriendshipAgeHours']) ?? 24,
      minChatMessagesExchanged: _toInt(json?['minChatMessagesExchanged']) ?? 0,
      requireVerifiedAccount: json?['requireVerifiedAccount'] == true,
      feePercentages: CoinTransferFeePercentages.fromJson(
        json?['feePercentages'] is Map
            ? Map<String, dynamic>.from(json!['feePercentages'] as Map)
            : null,
      ),
    );
  }
}

class CoinTransferPeer {
  final String id;
  final String uid;
  final String username;
  final String avatar;

  const CoinTransferPeer({
    required this.id,
    required this.uid,
    required this.username,
    required this.avatar,
  });

  factory CoinTransferPeer.fromJson(Map<String, dynamic>? json) {
    return CoinTransferPeer(
      id: json?['id']?.toString() ?? '',
      uid: json?['uid']?.toString() ?? '',
      username: json?['username']?.toString() ?? '',
      avatar: json?['avatar']?.toString() ?? '',
    );
  }
}

class CoinTransferValidation {
  final bool canSend;
  final List<CoinTransferReason> reasons;

  const CoinTransferValidation({
    required this.canSend,
    required this.reasons,
  });

  factory CoinTransferValidation.fromJson(Map<String, dynamic>? json) {
    final reasons = json?['reasons'] is List
        ? (json!['reasons'] as List)
            .whereType<Map>()
            .map((item) =>
                CoinTransferReason.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : const <CoinTransferReason>[];
    return CoinTransferValidation(
      canSend: json?['canSend'] == true,
      reasons: reasons,
    );
  }
}

class CoinTransferEligibility {
  final bool unlocked;
  final CoinTransferEntitlement? entitlement;
  final bool featureEnabled;
  final bool canPurchaseUnlock;
  final bool eligibleAfterUnlock;
  final bool canSend;
  final int currentBalance;
  final String chatId;
  final CoinTransferPeer? receiver;
  final List<CoinTransferReason> reasons;
  final CoinTransferLimits limits;
  final CoinTransferUsage usage;
  final CoinTransferBreakdown? preview;

  const CoinTransferEligibility({
    required this.unlocked,
    required this.entitlement,
    required this.featureEnabled,
    required this.canPurchaseUnlock,
    required this.eligibleAfterUnlock,
    required this.canSend,
    required this.currentBalance,
    required this.chatId,
    required this.receiver,
    required this.reasons,
    required this.limits,
    required this.usage,
    required this.preview,
  });

  factory CoinTransferEligibility.fromJson(Map<String, dynamic> json) {
    final reasons = json['reasons'] is List
        ? (json['reasons'] as List)
            .whereType<Map>()
            .map((item) =>
                CoinTransferReason.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : const <CoinTransferReason>[];
    return CoinTransferEligibility(
      unlocked: json['unlocked'] == true,
      entitlement: json['entitlement'] is Map
          ? CoinTransferEntitlement.fromJson(
              Map<String, dynamic>.from(json['entitlement'] as Map),
            )
          : null,
      featureEnabled: json['featureEnabled'] == true,
      canPurchaseUnlock: json['canPurchaseUnlock'] == true,
      eligibleAfterUnlock: json['eligibleAfterUnlock'] == true,
      canSend: json['canSend'] == true,
      currentBalance: _toInt(json['currentBalance']) ?? 0,
      chatId: json['chatId']?.toString() ?? '',
      receiver: json['receiver'] is Map
          ? CoinTransferPeer.fromJson(
              Map<String, dynamic>.from(json['receiver'] as Map),
            )
          : null,
      reasons: reasons,
      limits: CoinTransferLimits.fromJson(
        json['limits'] is Map
            ? Map<String, dynamic>.from(json['limits'] as Map)
            : null,
      ),
      usage: CoinTransferUsage.fromJson(
        json['usage'] is Map
            ? Map<String, dynamic>.from(json['usage'] as Map)
            : null,
      ),
      preview: json['preview'] is Map
          ? CoinTransferBreakdown.fromJson(
              Map<String, dynamic>.from(json['preview'] as Map),
            )
          : null,
    );
  }

  bool get hasUnlockReasonOnly {
    return reasons.length == 1 &&
        reasons.first.code == 'CHAT_TRANSFER_UNLOCK_REQUIRED';
  }
}

class CoinTransferPreview {
  final CoinTransferEligibility eligibility;
  final CoinTransferValidation validation;
  final CoinTransferBreakdown breakdown;

  const CoinTransferPreview({
    required this.eligibility,
    required this.validation,
    required this.breakdown,
  });

  factory CoinTransferPreview.fromJson(Map<String, dynamic> json) {
    final breakdown = CoinTransferBreakdown(
      senderSpend: _toInt(json['senderSpend']) ?? 0,
      receiverAmount: _toInt(json['receiverAmount']) ?? 0,
      platformFee: _toInt(json['platformFee']) ?? 0,
      grossAmount:
          _toInt(json['senderSpend']) ?? _toInt(json['grossAmount']) ?? 0,
      feePercentages: CoinTransferFeePercentages.fromJson(
        json['preview'] is Map
            ? Map<String, dynamic>.from(json['preview'] as Map)
            : json['limits'] is Map
                ? Map<String, dynamic>.from(json['limits'] as Map)
                : null,
      ),
    );
    return CoinTransferPreview(
      eligibility: CoinTransferEligibility.fromJson(json),
      validation: CoinTransferValidation.fromJson(
        json['validation'] is Map
            ? Map<String, dynamic>.from(json['validation'] as Map)
            : null,
      ),
      breakdown: breakdown,
    );
  }
}

class CoinTransferRecord {
  final String id;
  final String transferReferenceId;
  final String chatId;
  final String senderUserId;
  final String receiverUserId;
  final String direction;
  final int grossAmount;
  final int receiverAmount;
  final int platformFee;
  final String status;
  final String failureReason;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final CoinTransferFeePercentages feePercentages;
  final CoinTransferPeer peer;
  final String message;

  const CoinTransferRecord({
    required this.id,
    required this.transferReferenceId,
    required this.chatId,
    required this.senderUserId,
    required this.receiverUserId,
    required this.direction,
    required this.grossAmount,
    required this.receiverAmount,
    required this.platformFee,
    required this.status,
    required this.failureReason,
    required this.createdAt,
    required this.completedAt,
    required this.feePercentages,
    required this.peer,
    required this.message,
  });

  factory CoinTransferRecord.fromJson(Map<String, dynamic> json) {
    return CoinTransferRecord(
      id: json['id']?.toString() ?? '',
      transferReferenceId: json['transferReferenceId']?.toString() ?? '',
      chatId: json['chatId']?.toString() ?? '',
      senderUserId: json['senderUserId']?.toString() ?? '',
      receiverUserId: json['receiverUserId']?.toString() ?? '',
      direction: json['direction']?.toString() ?? 'sent',
      grossAmount: _toInt(json['grossAmount']) ?? 0,
      receiverAmount: _toInt(json['receiverAmount']) ?? 0,
      platformFee: _toInt(json['platformFee']) ?? 0,
      status: json['status']?.toString() ?? 'pending',
      failureReason: json['failureReason']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? ''),
      feePercentages: CoinTransferFeePercentages.fromJson(
        json['feePercentages'] is Map
            ? Map<String, dynamic>.from(json['feePercentages'] as Map)
            : null,
      ),
      peer: CoinTransferPeer.fromJson(
        json['peer'] is Map
            ? Map<String, dynamic>.from(json['peer'] as Map)
            : null,
      ),
      message: json['message']?.toString() ?? '',
    );
  }

  bool get isSent => direction == 'sent';
}

class CoinTransferHistoryPage {
  final List<CoinTransferRecord> transfers;
  final int page;
  final int limit;
  final int total;
  final int pages;

  const CoinTransferHistoryPage({
    required this.transfers,
    required this.page,
    required this.limit,
    required this.total,
    required this.pages,
  });

  factory CoinTransferHistoryPage.fromJson(Map<String, dynamic> json) {
    final transfers = json['transfers'] is List
        ? (json['transfers'] as List)
            .whereType<Map>()
            .map((item) =>
                CoinTransferRecord.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : const <CoinTransferRecord>[];
    final pagination = json['pagination'] is Map
        ? Map<String, dynamic>.from(json['pagination'] as Map)
        : const <String, dynamic>{};
    return CoinTransferHistoryPage(
      transfers: transfers,
      page: _toInt(pagination['page']) ?? 1,
      limit: _toInt(pagination['limit']) ?? 20,
      total: _toInt(pagination['total']) ?? transfers.length,
      pages: _toInt(pagination['pages']) ?? 1,
    );
  }
}

class CoinTransferPurchaseResult {
  final bool success;
  final bool unlocked;
  final bool mockActivated;
  final bool pendingCheckout;
  final String checkoutUrl;
  final String checkoutSessionId;
  final CoinTransferEntitlement? entitlement;
  final CoinTransferLimits config;

  const CoinTransferPurchaseResult({
    required this.success,
    required this.unlocked,
    required this.mockActivated,
    required this.pendingCheckout,
    required this.checkoutUrl,
    required this.checkoutSessionId,
    required this.entitlement,
    required this.config,
  });

  factory CoinTransferPurchaseResult.fromJson(Map<String, dynamic> json) {
    return CoinTransferPurchaseResult(
      success: json['success'] == true,
      unlocked: json['unlocked'] == true,
      mockActivated: json['mockActivated'] == true,
      pendingCheckout: json['pendingCheckout'] == true,
      checkoutUrl: json['checkoutUrl']?.toString() ?? '',
      checkoutSessionId: json['checkoutSessionId']?.toString() ?? '',
      entitlement: json['entitlement'] is Map
          ? CoinTransferEntitlement.fromJson(
              Map<String, dynamic>.from(json['entitlement'] as Map),
            )
          : null,
      config: CoinTransferLimits.fromJson(
        json['config'] is Map
            ? Map<String, dynamic>.from(json['config'] as Map)
            : null,
      ),
    );
  }
}

class CoinTransferBalanceSnapshot {
  final int coins;
  final int gems;
  final int vipLevel;

  const CoinTransferBalanceSnapshot({
    required this.coins,
    required this.gems,
    required this.vipLevel,
  });

  factory CoinTransferBalanceSnapshot.fromJson(Map<String, dynamic>? json) {
    return CoinTransferBalanceSnapshot(
      coins: _toInt(json?['coins']) ?? 0,
      gems: _toInt(json?['gems']) ?? 0,
      vipLevel: _toInt(json?['vipLevel']) ?? 0,
    );
  }
}

class CoinTransferSendResult {
  final bool success;
  final bool duplicate;
  final CoinTransferRecord transfer;
  final String transactionId;
  final CoinTransferBalanceSnapshot newBalance;
  final CoinTransferBalanceSnapshot receiverBalance;
  final Map<String, dynamic>? messageJson;

  const CoinTransferSendResult({
    required this.success,
    required this.duplicate,
    required this.transfer,
    required this.transactionId,
    required this.newBalance,
    required this.receiverBalance,
    required this.messageJson,
  });

  factory CoinTransferSendResult.fromJson(Map<String, dynamic> json) {
    return CoinTransferSendResult(
      success: json['success'] == true,
      duplicate: json['duplicate'] == true,
      transfer: CoinTransferRecord.fromJson(
        json['transfer'] is Map
            ? Map<String, dynamic>.from(json['transfer'] as Map)
            : const <String, dynamic>{},
      ),
      transactionId: json['transactionId']?.toString() ?? '',
      newBalance: CoinTransferBalanceSnapshot.fromJson(
        json['newBalance'] is Map
            ? Map<String, dynamic>.from(json['newBalance'] as Map)
            : null,
      ),
      receiverBalance: CoinTransferBalanceSnapshot.fromJson(
        json['receiverBalance'] is Map
            ? Map<String, dynamic>.from(json['receiverBalance'] as Map)
            : null,
      ),
      messageJson: json['message'] is Map
          ? Map<String, dynamic>.from(json['message'] as Map)
          : null,
    );
  }
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
