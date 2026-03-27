import 'package:flutter/foundation.dart';
import '../models/gift_model.dart';
import '../models/gift_transaction_model.dart';
import 'api_service.dart';

class GiftService {
  // Get gift catalog (categorized)
  static Future<Map<String, List<GiftModel>>> getGiftCatalog() async {
    try {
      final response = await ApiService.get('/gifts/catalog');

      final Map<String, List<GiftModel>> categorized = {};

      if (response is Map<String, dynamic>) {
        response.forEach((category, gifts) {
          if (gifts is List) {
            categorized[category] = gifts
                .map((g) => GiftModel.fromJson(g))
                .where((g) => g.isAvailable())
                .toList();
          }
        });
      }

      return categorized;
    } catch (e) {
      debugPrint('Error getting gift catalog: $e');
      return {};
    }
  }

  // Get single gift details
  static Future<GiftModel?> getGiftById(String giftId) async {
    try {
      final response = await ApiService.get('/gifts/$giftId');
      return GiftModel.fromJson(response);
    } catch (e) {
      debugPrint('Error getting gift: $e');
      return null;
    }
  }

  // Send gift to user
  static Future<Map<String, dynamic>> sendGift({
    required String toUserId,
    required String giftId,
    String? roomId,
    String? message,
    bool broadcast = false,
  }) async {
    try {
      final response = await ApiService.post('/gifts/send', {
        'toUserId': toUserId,
        'giftId': giftId,
        if (roomId != null) 'roomId': roomId,
        if (message != null) 'message': message,
        'broadcast': broadcast,
      });

      // Log the response for debugging
      debugPrint('Send gift response: $response');

      return response;
    } catch (e) {
      debugPrint('Error sending gift: $e');
      rethrow;
    }
  }

  // Get gift history
  static Future<Map<String, dynamic>> getGiftHistory({
    int page = 1,
    int limit = 20,
    String? type, // 'sent' or 'received'
  }) async {
    try {
      String endpoint = '/gifts/history?page=$page&limit=$limit';
      if (type != null) {
        endpoint += '&type=$type';
      }

      final response = await ApiService.get(endpoint);

      final transactions = (response['transactions'] as List)
          .map((t) => GiftTransactionModel.fromJson(t))
          .toList();

      return {
        'transactions': transactions,
        'pagination': response['pagination'],
      };
    } catch (e) {
      debugPrint('Error getting gift history: $e');
      return {'transactions': [], 'pagination': null};
    }
  }

  // Get gift leaderboard
  static Future<Map<String, dynamic>> getGiftLeaderboard({
    String period = 'alltime', // daily, weekly, monthly, alltime
    int limit = 50,
  }) async {
    try {
      final response = await ApiService.get(
        '/gifts/leaderboard?period=$period&limit=$limit',
      );

      return response;
    } catch (e) {
      debugPrint('Error getting leaderboard: $e');
      return {'leaderboard': [], 'userRank': null};
    }
  }

  // Get gift achievements
  static Future<Map<String, dynamic>> getGiftAchievements() async {
    try {
      final response = await ApiService.get('/gifts/achievements');
      return response;
    } catch (e) {
      debugPrint('Error getting achievements: $e');
      return {
        'achievements': [],
        'specialTitles': [],
        'stats': {'giftsSent': 0, 'giftsReceived': 0}
      };
    }
  }
}






