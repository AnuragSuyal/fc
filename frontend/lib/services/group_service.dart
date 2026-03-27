import 'package:flutter/foundation.dart';
import '../models/group_model.dart';
import 'api_service.dart';

class GroupService {
  // Get my groups
  static Future<List<GroupModel>> getMyGroups() async {
    try {
      final response = await ApiService.get('/groups/my-groups');

      if (response is List) {
        return response.map((g) => GroupModel.fromJson(g)).toList();
      }

      return [];
    } catch (e) {
      debugPrint('Error getting my groups: $e');
      return [];
    }
  }

  // Get discover groups (public groups to join)
  static Future<List<GroupModel>> getDiscoverGroups() async {
    try {
      final response = await ApiService.get('/groups/discover');

      if (response is List) {
        return response.map((g) => GroupModel.fromJson(g)).toList();
      }

      return [];
    } catch (e) {
      debugPrint('Error getting discover groups: $e');
      return [];
    }
  }

  // Create group
  static Future<GroupModel?> createGroup({
    required String name,
    String? description,
    String? motto,
    bool isPublic = true,
  }) async {
    try {
      final response = await ApiService.post('/groups', {
        'name': name,
        'description': description ?? '',
        'motto': motto ?? '',
        'isPublic': isPublic,
      });
      return GroupModel.fromJson(response);
    } catch (e) {
      debugPrint('Error creating group: $e');
      return null;
    }
  }

  // Join group
  static Future<bool> joinGroup(String groupId) async {
    try {
      await ApiService.post('/groups/$groupId/join', {});
      return true;
    } catch (e) {
      debugPrint('Error joining group: $e');
      return false;
    }
  }

  // Leave group
  static Future<bool> leaveGroup(String groupId) async {
    try {
      await ApiService.post('/groups/$groupId/leave', {});
      return true;
    } catch (e) {
      debugPrint('Error leaving group: $e');
      return false;
    }
  }

  // Get group leaderboard
  static Future<List<GroupModel>> getLeaderboard() async {
    try {
      final response = await ApiService.get('/groups/leaderboard');

      if (response is List) {
        return response.map((g) => GroupModel.fromJson(g)).toList();
      }

      return [];
    } catch (e) {
      debugPrint('Error getting group leaderboard: $e');
      return [];
    }
  }

  // Claim treasure chest
  static Future<Map<String, dynamic>?> claimTreasure(String groupId) async {
    try {
      final response = await ApiService.post('/groups/$groupId/treasure', {});
      return response;
    } catch (e) {
      debugPrint('Error claiming treasure: $e');
      return null;
    }
  }

  // Get single group
  static Future<GroupModel?> getGroupById(String groupId) async {
    try {
      final response = await ApiService.get('/groups/$groupId');
      return GroupModel.fromJson(response);
    } catch (e) {
      debugPrint('Error getting group: $e');
      return null;
    }
  }
}






