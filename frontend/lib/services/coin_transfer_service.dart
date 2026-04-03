import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/coin_transfer_model.dart';
import 'api_service.dart';

class CoinTransferService {
  static final Random _random = Random();

  static String buildDirectChatId(String leftUserId, String rightUserId) {
    final participants = [leftUserId.trim(), rightUserId.trim()]
      ..removeWhere((item) => item.isEmpty)
      ..sort();
    if (participants.length != 2) {
      return '';
    }
    return 'dm:${participants[0]}:${participants[1]}';
  }

  static Future<CoinTransferEligibility> getEligibility({
    String? receiverUserId,
    String? chatId,
  }) async {
    final queryParameters = <String, String>{};
    if ((receiverUserId ?? '').trim().isNotEmpty) {
      queryParameters['receiverUserId'] = receiverUserId!.trim();
    }
    if ((chatId ?? '').trim().isNotEmpty) {
      queryParameters['chatId'] = chatId!.trim();
    }

    final uri = Uri(
      path: '/coin-transfer/eligibility',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    final response = await ApiService.get(uri.toString());
    return CoinTransferEligibility.fromJson(
        Map<String, dynamic>.from(response));
  }

  static Future<CoinTransferPurchaseResult> purchaseUnlock({
    String purchaseSource = 'mock',
  }) async {
    final idempotencyKey = generateIdempotencyKey('unlock');
    final response = await ApiService.post(
      '/coin-transfer/unlock/purchase',
      {
        'purchaseSource': purchaseSource,
        'idempotencyKey': idempotencyKey,
      },
      headers: {
        'X-Idempotency-Key': idempotencyKey,
      },
    );
    return CoinTransferPurchaseResult.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<CoinTransferPreview> previewTransfer({
    required String receiverUserId,
    required String chatId,
    required int amount,
  }) async {
    final response = await ApiService.post('/coin-transfer/preview', {
      'receiverUserId': receiverUserId,
      'chatId': chatId,
      'amount': amount,
    });
    return CoinTransferPreview.fromJson(Map<String, dynamic>.from(response));
  }

  static Future<CoinTransferSendResult> sendTransfer({
    required String receiverUserId,
    required String chatId,
    required int amount,
    String? idempotencyKey,
  }) async {
    final safeIdempotencyKey = idempotencyKey ?? generateIdempotencyKey('send');
    final response = await ApiService.post(
      '/coin-transfer/send',
      {
        'receiverUserId': receiverUserId,
        'chatId': chatId,
        'amount': amount,
        'idempotencyKey': safeIdempotencyKey,
      },
      headers: {
        'X-Idempotency-Key': safeIdempotencyKey,
      },
    );
    return CoinTransferSendResult.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<CoinTransferHistoryPage> getHistory({
    String view = 'all',
    String status = '',
    String chatId = '',
    String dateFrom = '',
    String dateTo = '',
    int page = 1,
    int limit = 20,
  }) async {
    final queryParameters = <String, String>{
      'view': view,
      'page': '$page',
      'limit': '$limit',
      if (status.trim().isNotEmpty) 'status': status.trim(),
      if (chatId.trim().isNotEmpty) 'chatId': chatId.trim(),
      if (dateFrom.trim().isNotEmpty) 'dateFrom': dateFrom.trim(),
      if (dateTo.trim().isNotEmpty) 'dateTo': dateTo.trim(),
    };
    final uri = Uri(
      path: '/coin-transfer/history',
      queryParameters: queryParameters,
    );
    final response = await ApiService.get(uri.toString());
    return CoinTransferHistoryPage.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  static String generateIdempotencyKey(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final entropy = _random.nextInt(1 << 32);
    return 'coin_transfer_${prefix}_${now}_$entropy';
  }

  static CoinTransferBreakdown calculateBreakdown({
    required int amount,
    required CoinTransferFeePercentages feePercentages,
  }) {
    return CoinTransferBreakdown.calculate(
      amount: amount,
      feePercentages: feePercentages,
    );
  }

  static String formatFailureReason(
    List<CoinTransferReason> reasons, {
    String fallback = 'Coin transfer is unavailable right now.',
  }) {
    if (reasons.isEmpty) {
      return fallback;
    }
    return reasons.first.message;
  }

  static void debugPrintTransferError(Object error) {
    debugPrint('CoinTransferService error: $error');
  }
}
