import 'package:intl/intl.dart';

class TransactionModel {
  final String id;
  final String transactionId;
  final String userId;
  final String type;
  final TransactionAmount amount;
  final TransactionBalance? balanceBefore;
  final TransactionBalance? balanceAfter;
  final TransactionReference? reference;
  final String description;
  final String status;
  final DateTime? createdAt;
  final DateTime? completedAt;

  TransactionModel({
    required this.id,
    required this.transactionId,
    required this.userId,
    required this.type,
    required this.amount,
    this.balanceBefore,
    this.balanceAfter,
    this.reference,
    required this.description,
    required this.status,
    this.createdAt,
    this.completedAt,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['_id'] ?? '',
      transactionId: json['transactionId'] ?? '',
      userId: json['userId'] ?? '',
      type: json['type'] ?? '',
      amount: TransactionAmount.fromJson(json['amount'] ?? {}),
      balanceBefore: json['balanceBefore'] != null
          ? TransactionBalance.fromJson(json['balanceBefore'])
          : null,
      balanceAfter: json['balanceAfter'] != null
          ? TransactionBalance.fromJson(json['balanceAfter'])
          : null,
      reference: json['reference'] != null
          ? TransactionReference.fromJson(json['reference'])
          : null,
      description: json['description'] ?? '',
      status: json['status'] ?? 'pending',
      createdAt:
          json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
    );
  }

  String get formattedDate => createdAt != null
      ? DateFormat('MMM dd, yyyy HH:mm').format(createdAt!)
      : '';

  bool get isCredit =>
      type == 'purchase_coins' ||
      type == 'purchase_gems' ||
      type == 'gift_received' ||
      type == 'quest_reward' ||
      type == 'daily_bonus';
  bool get isDebit => !isCredit;
}

class TransactionAmount {
  final int coins;
  final int gems;
  final int realMoney;
  final String currency;

  TransactionAmount({
    required this.coins,
    required this.gems,
    required this.realMoney,
    required this.currency,
  });

  factory TransactionAmount.fromJson(Map<String, dynamic> json) {
    return TransactionAmount(
      coins: json['coins'] ?? 0,
      gems: json['gems'] ?? 0,
      realMoney: json['realMoney'] ?? 0,
      currency: json['currency'] ?? 'USD',
    );
  }
}

class TransactionBalance {
  final int coins;
  final int gems;

  TransactionBalance({required this.coins, required this.gems});

  factory TransactionBalance.fromJson(Map<String, dynamic> json) {
    return TransactionBalance(
      coins: json['coins'] ?? 0,
      gems: json['gems'] ?? 0,
    );
  }
}

class TransactionReference {
  final dynamic giftId; // Potential to be a Map if populated
  final String? roomId;
  final dynamic
      recipientId; // Potential to be a Map (username, avatar) if populated

  TransactionReference({this.giftId, this.roomId, this.recipientId});

  factory TransactionReference.fromJson(Map<String, dynamic> json) {
    return TransactionReference(
      giftId: json['giftId'],
      roomId: json['roomId'],
      recipientId: json['recipientId'],
    );
  }
}






