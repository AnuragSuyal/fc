import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'api_service.dart';

class UserService {
  // Search users by username or permanent UID
  static Future<List<UserModel>> searchUsers(
    String query, {
    int limit = 12,
  }) async {
    try {
      final queryString = Uri(
        queryParameters: {
          'q': query,
          'limit': limit.toString(),
        },
      ).query;
      final response = await ApiService.get('/users/search?$queryString');

      if (response is Map && response['users'] is List) {
        return (response['users'] as List)
            .whereType<Map>()
            .map((json) => UserModel.fromJson(Map<String, dynamic>.from(json)))
            .toList();
      }

      return [];
    } catch (e) {
      debugPrint('Error searching users: $e');
      return [];
    }
  }

  // Get user by ID
  static Future<UserModel?> getUserById(String userId) async {
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final response = await ApiService.get('/users/$encodedUserId');
      final rawUser = response is Map && response['user'] is Map
          ? Map<String, dynamic>.from(response['user'] as Map)
          : response is Map
              ? Map<String, dynamic>.from(response)
              : null;
      if (rawUser == null) return null;
      return UserModel.fromJson(rawUser);
    } catch (e) {
      debugPrint('Error getting user: $e');
      return null;
    }
  }

  // Get user friends (online and offline)
  static Future<Map<String, dynamic>> getFriends() async {
    try {
      final response = await ApiService.get('/friends');
      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('Error getting friends: $e');
      return {'online': [], 'offline': [], 'total': 0};
    }
  }
}
