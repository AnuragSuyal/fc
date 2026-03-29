import 'color_clash_model_utils.dart';

class ColorClashSettlementSummaryModel {
  const ColorClashSettlementSummaryModel({
    required this.matchId,
    required this.paidTable,
    required this.status,
    required this.currency,
    required this.entryFee,
    required this.totalEscrowed,
    required this.grossPool,
    required this.houseFee,
    required this.sinkAmount,
    required this.totalPaidOut,
    required this.refundedAmount,
    required this.escrowCount,
    required this.payouts,
    this.rankProgression,
    this.settlementKey,
    this.lockedAt,
    this.settledAt,
    this.refundedAt,
    this.error,
  });

  final String matchId;
  final bool paidTable;
  final String status;
  final String currency;
  final int entryFee;
  final int totalEscrowed;
  final int grossPool;
  final int houseFee;
  final int sinkAmount;
  final int totalPaidOut;
  final int refundedAmount;
  final int escrowCount;
  final List<ColorClashSettlementPayoutModel> payouts;
  final ColorClashRankProgressionModel? rankProgression;
  final String? settlementKey;
  final DateTime? lockedAt;
  final DateTime? settledAt;
  final DateTime? refundedAt;
  final String? error;

  factory ColorClashSettlementSummaryModel.fromJson(Map<String, dynamic> json) {
    return ColorClashSettlementSummaryModel(
      matchId: asId(json['matchId']),
      paidTable: asBool(json['paidTable']),
      status: json['status']?.toString() ?? 'none',
      currency: json['currency']?.toString() ?? 'none',
      entryFee: asInt(json['entryFee']),
      totalEscrowed: asInt(json['totalEscrowed']),
      grossPool: asInt(json['grossPool']),
      houseFee: asInt(json['houseFee']),
      sinkAmount: asInt(json['sinkAmount']),
      totalPaidOut: asInt(json['totalPaidOut']),
      refundedAmount: asInt(json['refundedAmount']),
      escrowCount: asInt(json['escrowCount']),
      payouts: asMapList(json['payouts'])
          .map(ColorClashSettlementPayoutModel.fromJson)
          .toList(growable: false),
      rankProgression: json['rankProgression'] == null
          ? null
          : ColorClashRankProgressionModel.fromJson(asMap(json['rankProgression'])),
      settlementKey: json['settlementKey']?.toString(),
      lockedAt: asDateTime(json['lockedAt']),
      settledAt: asDateTime(json['settledAt']),
      refundedAt: asDateTime(json['refundedAt']),
      error: json['error']?.toString(),
    );
  }

  bool get isPending => const <String>{
        'none',
        'pending',
        'processing',
        'locked',
      }.contains(status);

  bool get isSettled => status == 'settled';

  bool get isRefunded => status == 'refunded';

  bool get isFailed => status == 'failed';

  bool get isTerminal => isSettled || isRefunded || isFailed || status == 'skipped';

  String get statusLabel {
    switch (status) {
      case 'locked':
        return 'Settlement pending';
      case 'settled':
        return 'Settlement complete';
      case 'refunded':
        return 'Entries refunded';
      case 'failed':
        return 'Settlement issue';
      case 'skipped':
        return 'No settlement required';
      default:
        return 'Syncing result';
    }
  }
}

class ColorClashSettlementPayoutModel {
  const ColorClashSettlementPayoutModel({
    required this.userId,
    required this.place,
    required this.amount,
    this.transactionId,
  });

  final String userId;
  final int place;
  final int amount;
  final String? transactionId;

  factory ColorClashSettlementPayoutModel.fromJson(Map<String, dynamic> json) {
    final transactionId = asId(json['transactionId']);
    return ColorClashSettlementPayoutModel(
      userId: asId(json['userId']),
      place: asInt(json['place'], fallback: 1),
      amount: asInt(json['amount']),
      transactionId: transactionId.isEmpty ? null : transactionId,
    );
  }
}

class ColorClashRankProgressionModel {
  const ColorClashRankProgressionModel({
    required this.status,
    required this.results,
    this.error,
  });

  final String status;
  final List<ColorClashRankProgressResultModel> results;
  final String? error;

  factory ColorClashRankProgressionModel.fromJson(Map<String, dynamic> json) {
    return ColorClashRankProgressionModel(
      status: json['status']?.toString() ?? 'pending',
      results: asMapList(json['results'])
          .map(ColorClashRankProgressResultModel.fromJson)
          .toList(growable: false),
      error: json['error']?.toString(),
    );
  }

  bool get isApplied => status == 'applied';
}

class ColorClashRankProgressResultModel {
  const ColorClashRankProgressResultModel({
    required this.userId,
    required this.placement,
    required this.ratingBefore,
    required this.ratingAfter,
    required this.ratingDelta,
    required this.tierId,
    required this.division,
    required this.stars,
  });

  final String userId;
  final int placement;
  final int ratingBefore;
  final int ratingAfter;
  final int ratingDelta;
  final String tierId;
  final int division;
  final int stars;

  factory ColorClashRankProgressResultModel.fromJson(
    Map<String, dynamic> json,
  ) {
    return ColorClashRankProgressResultModel(
      userId: asId(json['userId']),
      placement: asInt(json['placement'], fallback: 1),
      ratingBefore: asInt(json['ratingBefore']),
      ratingAfter: asInt(json['ratingAfter']),
      ratingDelta: asInt(json['ratingDelta']),
      tierId: json['tierId']?.toString() ?? '',
      division: asInt(json['division'], fallback: 1),
      stars: asInt(json['stars']),
    );
  }
}
