import 'package:flutter/foundation.dart';
import 'api_service.dart';

class WalletService {
  // Get user balance
  static Future<Map<String, dynamic>> getBalance() async {
    try {
      final response = await ApiService.get('/wallet/balance');
      return response;
    } catch (e) {
      debugPrint('Error getting balance: $e');
      return {'coins': 0, 'gems': 0, 'tickets': 0, 'stars': 0, 'vipLevel': 0};
    }
  }

  // Get transaction history
  static Future<Map<String, dynamic>> getTransactions({
    int page = 1,
    int limit = 20,
    String? type,
  }) async {
    try {
      String url = '/wallet/transactions?page=$page&limit=$limit';
      if (type != null) {
        url += '&type=$type';
      }

      final response = await ApiService.get(url);
      return response;
    } catch (e) {
      debugPrint('Error getting transactions: $e');
      return {'transactions': {}, 'pagination': null};
    }
  }

  // Get coin packs
  static Future<List<dynamic>> getCoinPacks() async {
    try {
      final response = await ApiService.get('/wallet/shop/coins');
      return response is List ? response : [];
    } catch (e) {
      debugPrint('Error getting coin packs: $e');
      return [];
    }
  }

  // Get gem packs
  static Future<List<dynamic>> getGemPacks() async {
    try {
      final response = await ApiService.get('/wallet/shop/gems');
      return response is List ? response : [];
    } catch (e) {
      debugPrint('Error getting gem packs: $e');
      return [];
    }
  }

  // Get special offers
  static Future<List<dynamic>> getSpecialOffers() async {
    try {
      final response = await ApiService.get('/wallet/shop/offers');
      return response is List ? response : [];
    } catch (e) {
      debugPrint('Error getting offers: $e');
      return [];
    }
  }

  // Purchase coins
  static Future<Map<String, dynamic>?> purchaseCoins(String packId) async {
    try {
      final response = await ApiService.post('/wallet/purchase/coins', {
        'packId': packId,
      });
      return response;
    } catch (e) {
      debugPrint('Error purchasing coins: $e');
      return null;
    }
  }

  // Purchase gems
  static Future<Map<String, dynamic>?> purchaseGems(String packId) async {
    try {
      final response = await ApiService.post('/wallet/purchase/gems', {
        'packId': packId,
      });
      return response;
    } catch (e) {
      debugPrint('Error purchasing gems: $e');
      return null;
    }
  }

  // Convert coins to gems
  static Future<Map<String, dynamic>?> convertCoinsToGems(int coins) async {
    try {
      final response = await ApiService.post('/wallet/convert', {
        'coins': coins,
      });
      return response;
    } catch (e) {
      debugPrint('Error converting coins: $e');
      return null;
    }
  }
}






