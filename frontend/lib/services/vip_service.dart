import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/vip_model.dart';
import 'api_service.dart';

class VipService {
  static Future<VipCatalogModel> getVipCatalog({String? selectedTierId}) async {
    try {
      final suffix = selectedTierId == null || selectedTierId.trim().isEmpty
          ? ''
          : '?tierId=${Uri.encodeQueryComponent(selectedTierId.trim())}';
      final response = await ApiService.get('/vip/levels$suffix');
      return VipCatalogModel.fromJson(
        response is Map<String, dynamic>
            ? response
            : Map<String, dynamic>.from(response as Map),
      );
    } catch (error) {
      debugPrint('getVipCatalog error: $error');
      return const VipCatalogModel(
        tiers: <VipTierModel>[],
        comparisonRows: <VipComparisonRow>[],
        planDefinitions: <VipPlanOption>[],
      );
    }
  }

  static Future<VipStatusModel?> getVipStatus() async {
    try {
      final response = await ApiService.get('/vip/status');
      return VipStatusModel.fromJson(
        response is Map<String, dynamic>
            ? response
            : Map<String, dynamic>.from(response as Map),
      );
    } catch (error) {
      debugPrint('getVipStatus error: $error');
      return null;
    }
  }

  static Future<Map<String, dynamic>> purchaseVip({
    required String tierId,
    required String planDuration,
    bool autoRenew = false,
  }) async {
    final idempotencyKey = _generateIdempotencyKey('vip_purchase');
    try {
      final response = await ApiService.post(
        '/vip/purchase',
        {
          'tierId': tierId,
          'planDuration': planDuration,
          'autoRenew': autoRenew,
          'purchaseSource': 'coins',
          'idempotencyKey': idempotencyKey,
        },
        headers: {
          'X-Idempotency-Key': idempotencyKey,
        },
      );
      return response is Map<String, dynamic>
          ? response
          : Map<String, dynamic>.from(response as Map);
    } catch (error) {
      debugPrint('purchaseVip error: $error');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> claimMonthlyReward() async {
    final idempotencyKey = _generateIdempotencyKey('vip_reward');
    try {
      final response = await ApiService.post(
        '/vip/monthly-reward',
        {'idempotencyKey': idempotencyKey},
        headers: {'X-Idempotency-Key': idempotencyKey},
      );
      return response is Map<String, dynamic>
          ? response
          : Map<String, dynamic>.from(response as Map);
    } catch (error) {
      debugPrint('claimMonthlyReward error: $error');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> restoreVip() async {
    try {
      final response = await ApiService.post('/vip/restore', const {});
      return response is Map<String, dynamic>
          ? response
          : Map<String, dynamic>.from(response as Map);
    } catch (error) {
      debugPrint('restoreVip error: $error');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> cancelVip() async {
    try {
      final response = await ApiService.post('/vip/cancel', const {});
      return response is Map<String, dynamic>
          ? response
          : Map<String, dynamic>.from(response as Map);
    } catch (error) {
      debugPrint('cancelVip error: $error');
      rethrow;
    }
  }

  static String _generateIdempotencyKey(String prefix) {
    final random = Random();
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}';
  }
}
