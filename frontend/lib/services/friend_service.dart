import 'package:flutter/foundation.dart';
import 'api_service.dart';

class FriendService {
  // Get friends list (online/offline)
  static Future<Map<String, dynamic>> getFriends() async {
    try {
      final response = await ApiService.get('/friends');
      return response;
    } catch (e) {
      debugPrint('Error getting friends: $e');
      return {'online': [], 'offline': [], 'total': 0};
    }
  }

  // Get friend requests
  static Future<List<dynamic>> getFriendRequests() async {
    try {
      final response = await ApiService.get('/friends/requests');
      return response is List ? response : [];
    } catch (e) {
      debugPrint('Error getting friend requests: $e');
      return [];
    }
  }

  // Get friend suggestions
  static Future<List<dynamic>> getFriendSuggestions() async {
    try {
      final response = await ApiService.get('/friends/suggestions');
      return response is List ? response : [];
    } catch (e) {
      debugPrint('Error getting suggestions: $e');
      return [];
    }
  }

  // Get blocked users
  static Future<List<dynamic>> getBlockedUsers() async {
    try {
      final response = await ApiService.get('/friends/blocked');
      return response is List ? response : [];
    } catch (e) {
      debugPrint('Error getting blocked users: $e');
      return [];
    }
  }

  // Send friend request
  static Future<bool> sendFriendRequest(String userId) async {
    try {
      await ApiService.post('/friends/request/$userId', {});
      return true;
    } catch (e) {
      debugPrint('Error sending friend request: $e');
      return false;
    }
  }

  // Accept friend request
  static Future<bool> acceptFriendRequest(String userId) async {
    try {
      await ApiService.post('/friends/accept/$userId', {});
      return true;
    } catch (e) {
      debugPrint('Error accepting friend request: $e');
      return false;
    }
  }

  // Reject friend request
  static Future<bool> rejectFriendRequest(String userId) async {
    try {
      await ApiService.post('/friends/reject/$userId', {});
      return true;
    } catch (e) {
      debugPrint('Error rejecting friend request: $e');
      return false;
    }
  }

  // Remove friend
  static Future<bool> removeFriend(String userId) async {
    try {
      await ApiService.delete('/friends/$userId');
      return true;
    } catch (e) {
      debugPrint('Error removing friend: $e');
      return false;
    }
  }

  // Block user
  static Future<bool> blockUser(String userId) async {
    try {
      await ApiService.post('/friends/block/$userId', {});
      return true;
    } catch (e) {
      debugPrint('Error blocking user: $e');
      return false;
    }
  }

  // Unblock user
  static Future<bool> unblockUser(String userId) async {
    try {
      await ApiService.delete('/friends/block/$userId');
      return true;
    } catch (e) {
      debugPrint('Error unblocking user: $e');
      return false;
    }
  }
}






