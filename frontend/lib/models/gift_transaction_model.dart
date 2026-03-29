// Make sure your GiftTransactionModel has all these fields:

class GiftTransactionModel {
  final String id;
  final String transactionId;
  final String type; // 'gift_sent', 'gift_received'
  final int coinsAmount;
  final int gemsAmount;

  // References
  final String? giftId;
  final String? giftName;
  final String? giftIcon;
  final String? recipientId;
  final String? recipientName;
  final String? recipientAvatar;
  final String? senderId;
  final String? senderName;
  final String? senderAvatar;
  final String? roomId;

  // Add this field for nested reference access
  final Map<String, dynamic>? reference;

  // Balance
  final int balanceBeforeCoins;
  final int balanceBeforeGems;
  final int balanceAfterCoins;
  final int balanceAfterGems;

  final String description;
  final DateTime createdAt;

  // Add computed getter for formatted date
  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  // Add getter for amount (for backward compatibility)
  Map<String, int> get amount => {
        'coins': coinsAmount,
        'gems': gemsAmount,
      };

  GiftTransactionModel({
    required this.id,
    required this.transactionId,
    required this.type,
    required this.coinsAmount,
    required this.gemsAmount,
    this.giftId,
    this.giftName,
    this.giftIcon,
    this.recipientId,
    this.recipientName,
    this.recipientAvatar,
    this.senderId,
    this.senderName,
    this.senderAvatar,
    this.roomId,
    this.reference,
    required this.balanceBeforeCoins,
    required this.balanceBeforeGems,
    required this.balanceAfterCoins,
    required this.balanceAfterGems,
    required this.description,
    required this.createdAt,
  });

  factory GiftTransactionModel.fromJson(Map<String, dynamic> json) {
    final reference = json['reference'] as Map<String, dynamic>?;
    final gift = reference?['giftId'] is Map
        ? reference!['giftId'] as Map<String, dynamic>
        : null;
    final recipient = reference?['recipientId'] is Map
        ? reference!['recipientId'] as Map<String, dynamic>
        : null;
    final sender =
        json['userId'] is Map ? json['userId'] as Map<String, dynamic> : null;

    return GiftTransactionModel(
      id: json['_id'] ?? '',
      transactionId: json['transactionId'] ?? '',
      type: json['type'] ?? '',
      coinsAmount: json['amount']?['coins'] ?? 0,
      gemsAmount: json['amount']?['gems'] ?? 0,
      giftId: gift?['giftId'] ?? gift?['_id'] ?? reference?['giftId'],
      giftName: gift?['name'],
      giftIcon: gift?['assetPath'] ?? gift?['icon'],
      recipientId: recipient?['_id'] ?? reference?['recipientId'],
      recipientName: recipient?['username'],
      recipientAvatar: recipient?['avatar'],
      senderId: sender?['_id'] ?? json['userId'],
      senderName: sender?['username'],
      senderAvatar: sender?['avatar'],
      roomId: reference?['roomId'],
      reference: reference,
      balanceBeforeCoins: json['balanceBefore']?['coins'] ?? 0,
      balanceBeforeGems: json['balanceBefore']?['gems'] ?? 0,
      balanceAfterCoins: json['balanceAfter']?['coins'] ?? 0,
      balanceAfterGems: json['balanceAfter']?['gems'] ?? 0,
      description: json['description'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}





