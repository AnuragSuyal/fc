import 'package:flutter/foundation.dart';

import '../models/group_model.dart';
import 'api_service.dart';

class GroupService {
  static Future<List<GroupModel>> getMyGroups() async {
    try {
      final response = await ApiService.get('/groups/my-groups');
      return _parseGroupList(response);
    } catch (e) {
      debugPrint('Error getting my groups: $e');
      return [];
    }
  }

  static Future<List<GroupModel>> getMyInvites() async {
    try {
      final response = await ApiService.get('/groups/invites');
      return _parseGroupList(response);
    } catch (e) {
      debugPrint('Error getting group invites: $e');
      return [];
    }
  }

  static Future<List<GroupModel>> getDiscoverGroups() async {
    try {
      final response = await ApiService.get('/groups/discover');
      return _parseGroupList(response);
    } catch (e) {
      debugPrint('Error getting discover groups: $e');
      return [];
    }
  }

  static Future<GroupModel?> createGroup({
    required String name,
    String? description,
    String? motto,
    bool isPublic = true,
    bool approvalRequired = false,
    int maxMembers = 20,
    String type = 'small',
    String vibe = 'Orbit',
    List<String> invitedFriendIds = const [],
  }) async {
    try {
      final response = await ApiService.post('/groups', {
        'name': name,
        'description': description ?? '',
        'motto': motto ?? '',
        'isPublic': isPublic,
        'approvalRequired': approvalRequired,
        'maxMembers': maxMembers,
        'type': type,
        'vibe': vibe,
        'invitedFriendIds': invitedFriendIds,
      });
      return GroupModel.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      debugPrint('Error creating group: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> joinGroup(
    String groupId, {
    String? message,
  }) async {
    try {
      final response = await ApiService.post('/groups/$groupId/join', {
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
      });
      if (response is Map<String, dynamic>) {
        return response;
      }
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {'success': true};
    } catch (e) {
      debugPrint('Error joining group: $e');
      rethrow;
    }
  }

  static Future<bool> leaveGroup(String groupId) async {
    try {
      await ApiService.post('/groups/$groupId/leave', {});
      return true;
    } catch (e) {
      debugPrint('Error leaving group: $e');
      return false;
    }
  }

  static Future<List<GroupModel>> getLeaderboard() async {
    try {
      final response = await ApiService.get('/groups/leaderboard');
      return _parseGroupList(response);
    } catch (e) {
      debugPrint('Error getting group leaderboard: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> claimTreasure(String groupId) async {
    try {
      final response = await ApiService.post('/groups/$groupId/treasure', {});
      if (response is Map<String, dynamic>) {
        return response;
      }
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return null;
    } catch (e) {
      debugPrint('Error claiming treasure: $e');
      return null;
    }
  }

  static Future<GroupModel?> getGroupById(String groupId) async {
    try {
      final response = await ApiService.get('/groups/$groupId');
      if (response is Map<String, dynamic>) {
        return GroupModel.fromJson(response);
      }
      if (response is Map) {
        return GroupModel.fromJson(Map<String, dynamic>.from(response));
      }
      return null;
    } catch (e) {
      debugPrint('Error getting group: $e');
      return null;
    }
  }

  static Future<GroupModel?> inviteFriends(
    String groupId,
    List<String> userIds,
  ) async {
    try {
      final response = await ApiService.post('/groups/$groupId/invite', {
        'userIds': userIds,
      });
      final group = response is Map ? response['group'] : null;
      if (group is Map<String, dynamic>) {
        return GroupModel.fromJson(group);
      }
      if (group is Map) {
        return GroupModel.fromJson(Map<String, dynamic>.from(group));
      }
      return null;
    } catch (e) {
      debugPrint('Error inviting friends to group: $e');
      rethrow;
    }
  }

  static Future<GroupModel?> acceptInvite(String groupId) async {
    try {
      final response =
          await ApiService.post('/groups/$groupId/invitations/accept', {});
      return _parseGroupFromEnvelope(response);
    } catch (e) {
      debugPrint('Error accepting group invite: $e');
      rethrow;
    }
  }

  static Future<bool> rejectInvite(String groupId) async {
    try {
      await ApiService.post('/groups/$groupId/invitations/reject', {});
      return true;
    } catch (e) {
      debugPrint('Error rejecting group invite: $e');
      return false;
    }
  }

  static Future<GroupModel?> approveJoinRequest(
    String groupId,
    String userId,
  ) async {
    try {
      final response = await ApiService.post(
          '/groups/$groupId/requests/$userId/approve', {});
      return _parseGroupFromEnvelope(response);
    } catch (e) {
      debugPrint('Error approving join request: $e');
      rethrow;
    }
  }

  static Future<bool> rejectJoinRequest(String groupId, String userId) async {
    try {
      await ApiService.post('/groups/$groupId/requests/$userId/reject', {});
      return true;
    } catch (e) {
      debugPrint('Error rejecting join request: $e');
      return false;
    }
  }

  static Future<GroupModel?> updateMemberRole(
    String groupId,
    String userId,
    String role,
  ) async {
    try {
      final response =
          await ApiService.put('/groups/$groupId/members/$userId/role', {
        'role': role,
      });
      return _parseGroupFromEnvelope(response);
    } catch (e) {
      debugPrint('Error updating member role: $e');
      rethrow;
    }
  }

  static Future<GroupModel?> removeMember(String groupId, String userId) async {
    try {
      final response =
          await ApiService.delete('/groups/$groupId/members/$userId');
      return _parseGroupFromEnvelope(response);
    } catch (e) {
      debugPrint('Error removing group member: $e');
      rethrow;
    }
  }

  static Future<GroupModel?> updateGroup(
    String groupId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await ApiService.put('/groups/$groupId', data);
      if (response is Map<String, dynamic>) {
        return GroupModel.fromJson(response);
      }
      if (response is Map) {
        return GroupModel.fromJson(Map<String, dynamic>.from(response));
      }
      return null;
    } catch (e) {
      debugPrint('Error updating group: $e');
      rethrow;
    }
  }

  static Future<bool> deleteGroup(String groupId) async {
    try {
      await ApiService.delete('/groups/$groupId');
      return true;
    } catch (e) {
      debugPrint('Error deleting group: $e');
      return false;
    }
  }

  static GroupModel? _parseGroupFromEnvelope(dynamic response) {
    final group = response is Map ? response['group'] : null;
    if (group is Map<String, dynamic>) {
      return GroupModel.fromJson(group);
    }
    if (group is Map) {
      return GroupModel.fromJson(Map<String, dynamic>.from(group));
    }
    return null;
  }

  static List<GroupModel> _parseGroupList(dynamic response) {
    if (response is! List) {
      return [];
    }

    return response
        .whereType<Map>()
        .map((group) => GroupModel.fromJson(Map<String, dynamic>.from(group)))
        .toList(growable: false);
  }
}
