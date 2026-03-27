import 'package:flutter/foundation.dart';
import 'api_service.dart';
import '../models/room_model.dart';

class RoomService {
  static Future<List<RoomModel>> getRooms({
    String? category,
    String? type,
    String? search,
    String? tag,
    String? sort,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (category != null && category != 'all') {
        queryParams['category'] = category;
      }
      if (type != null) {
        queryParams['type'] = type;
      }
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (tag != null) {
        queryParams['tag'] = tag;
      }
      if (sort != null && sort.isNotEmpty) {
        queryParams['sort'] = sort;
      }

      final queryString = Uri(queryParameters: queryParams).query;
      final response = await ApiService.get('/rooms?$queryString');
      return _parseRoomList(response, key: 'rooms');
    } catch (e) {
      debugPrint('Error getting rooms: $e');
      return [];
    }
  }

  static Future<List<RoomModel>> getTrendingRooms() async {
    try {
      final response = await ApiService.get('/rooms/trending');
      return _parseRoomList(response, key: 'rooms');
    } catch (e) {
      debugPrint('Error getting trending rooms: $e');
      return [];
    }
  }

  static Future<RoomModel?> getRoomById(String roomId) async {
    try {
      final response = await ApiService.get('/rooms/$roomId');
      return RoomModel.fromJson(response);
    } catch (e) {
      debugPrint('Error getting room: $e');
      return null;
    }
  }

  static Future<RoomModel?> createRoom({
    required String name,
    String? description,
    String type = 'voice',
    String category = 'all',
    List<String>? tags,
    Map<String, dynamic>? settings,
    Map<String, dynamic>? theme,
  }) async {
    try {
      final payload = _pruneNulls({
        'name': name,
        'description': description ?? '',
        'type': type,
        'category': category,
        'tags': tags ?? [],
        'settings': settings ??
            {
              'maxParticipants': 20,
              'entryFee': 0,
              'hdVoice': false,
              'allowGifts': true,
              'stageJoinsLocked': false,
              'maxActiveSpeakers': 8,
            },
        'theme': theme ?? {'background': 'default'},
      });
      final response = await ApiService.post(
        '/rooms',
        Map<String, dynamic>.from(payload as Map),
      );

      return RoomModel.fromJson(response);
    } catch (e) {
      debugPrint('Error creating room: $e');
      rethrow;
    }
  }

  static Future<RoomModel?> joinRoom(String roomId, {String? password}) async {
    try {
      final response = await ApiService.post(
        '/rooms/$roomId/join',
        password != null ? {'password': password} : {},
      );
      return RoomModel.fromJson(response);
    } catch (e) {
      debugPrint('Error joining room: $e');
      rethrow;
    }
  }

  static Future<bool> leaveRoom(String roomId) async {
    try {
      await ApiService.post('/rooms/$roomId/leave', {});
      return true;
    } catch (e) {
      debugPrint('Error leaving room: $e');
      return false;
    }
  }

  static Future<List<RoomModel>> getMyRooms() async {
    try {
      final response = await ApiService.get('/rooms/my-rooms');
      return _parseRoomList(response, key: 'rooms');
    } catch (e) {
      debugPrint('Error getting my rooms: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      final response = await ApiService.get('/rooms/categories');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting categories: $e');
      return const [
        {'id': 'all', 'name': 'All Rooms', 'icon': 'globe'},
        {'id': 'voice', 'name': 'Voice Chat', 'icon': 'mic'},
        {'id': 'music', 'name': 'Music', 'icon': 'music'},
        {'id': 'video', 'name': 'Video', 'icon': 'video'},
        {'id': 'chat', 'name': 'Chat', 'icon': 'chat'},
        {'id': 'battle', 'name': 'Battle', 'icon': 'battle'},
        {'id': 'auction', 'name': 'Auction', 'icon': 'auction'},
      ];
    }
  }

  static Future<RoomModel?> updateRoom(
    String roomId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await ApiService.put('/rooms/$roomId', data);
      return RoomModel.fromJson(response);
    } catch (e) {
      debugPrint('Error updating room: $e');
      return null;
    }
  }

  static Future<bool> deleteRoom(String roomId) async {
    try {
      await ApiService.delete('/rooms/$roomId');
      return true;
    } catch (e) {
      debugPrint('Error deleting room: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getRoomToken(String roomId) async {
    try {
      final response = await ApiService.post('/rooms/$roomId/token', {});
      return response;
    } catch (e) {
      debugPrint('Error getting room token: $e');
      rethrow;
    }
  }

  static Future<RoomModel?> takeSeat(String roomId, int seatIndex) async {
    try {
      final response = await ApiService.post('/rooms/$roomId/seat', {
        'seatIndex': seatIndex,
      });
      return RoomModel.fromJson(response);
    } catch (e) {
      debugPrint('Error taking seat: $e');
      rethrow;
    }
  }

  static Future<RoomModel?> leaveSeat(String roomId) async {
    try {
      final response = await ApiService.delete('/rooms/$roomId/seat');
      return RoomModel.fromJson(response);
    } catch (e) {
      debugPrint('Error leaving seat: $e');
      rethrow;
    }
  }

  static Future<void> lockSeat(String roomId, int seatIndex) async {
    await ApiService.post('/rooms/$roomId/seat/$seatIndex/lock', {});
  }

  static Future<void> unlockSeat(String roomId, int seatIndex) async {
    await ApiService.post('/rooms/$roomId/seat/$seatIndex/unlock', {});
  }

  static Future<void> muteParticipant(
    String roomId,
    String userId, {
    required bool muted,
  }) async {
    await ApiService.post('/rooms/$roomId/mute/$userId', {'muted': muted});
  }

  static Future<void> kickParticipant(
    String roomId,
    String userId, {
    String? reason,
  }) async {
    await ApiService.post('/rooms/$roomId/kick/$userId', {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  static Future<void> promoteParticipant(String roomId, String userId) async {
    await ApiService.post('/rooms/$roomId/promote/$userId', {});
  }

  static Future<void> demoteParticipant(String roomId, String userId) async {
    await ApiService.post('/rooms/$roomId/demote/$userId', {});
  }

  static Future<void> assignCoHost(String roomId, String userId) async {
    await ApiService.post('/rooms/$roomId/cohost/$userId', {});
  }

  static Future<void> removeCoHost(String roomId, String userId) async {
    await ApiService.delete('/rooms/$roomId/cohost/$userId');
  }

  static Future<RoomModel?> addModerator(String roomId, String userId) async {
    try {
      final response =
          await ApiService.post('/rooms/$roomId/moderators/$userId', {});
      return RoomModel.fromJson(response);
    } catch (e) {
      debugPrint('Error adding moderator: $e');
      rethrow;
    }
  }

  static Future<RoomModel?> removeModerator(
    String roomId,
    String userId,
  ) async {
    try {
      final response =
          await ApiService.delete('/rooms/$roomId/moderators/$userId');
      return RoomModel.fromJson(response);
    } catch (e) {
      debugPrint('Error removing moderator: $e');
      rethrow;
    }
  }

  static Future<void> setAnnouncement(
      String roomId, String announcement) async {
    await ApiService.post('/rooms/$roomId/announcement', {
      'announcement': announcement,
    });
  }

  static Future<int?> followRoom(String roomId) async {
    try {
      final response = await ApiService.post('/rooms/$roomId/follow', {});
      return response['followers'] as int?;
    } catch (e) {
      debugPrint('Error following room: $e');
      return null;
    }
  }

  static Future<int?> unfollowRoom(String roomId) async {
    try {
      final response = await ApiService.delete('/rooms/$roomId/follow');
      return response['followers'] as int?;
    } catch (e) {
      debugPrint('Error unfollowing room: $e');
      return null;
    }
  }

  static Future<String?> reportRoom(String roomId, String reason) async {
    try {
      final response = await ApiService.post('/rooms/$roomId/report', {
        'reason': reason,
      });
      return response['message']?.toString();
    } catch (e) {
      debugPrint('Error reporting room: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getBans(String roomId) async {
    try {
      final response = await ApiService.get('/rooms/$roomId/bans');
      if (response is List) {
        return response
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      }
      return const [];
    } catch (e) {
      debugPrint('Error getting room bans: $e');
      return const [];
    }
  }

  static Future<List<Map<String, dynamic>>> getReports(String roomId) async {
    try {
      final response = await ApiService.get('/rooms/$roomId/reports');
      if (response is List) {
        return response
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      }
      return const [];
    } catch (e) {
      debugPrint('Error getting room reports: $e');
      return const [];
    }
  }

  static Future<RoomModel?> transferOwnership(
    String roomId,
    String userId,
  ) async {
    try {
      final response = await ApiService.post(
          '/rooms/$roomId/transfer-ownership/$userId', {});
      return RoomModel.fromJson(response);
    } catch (e) {
      debugPrint('Error transferring room ownership: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> banParticipant(
    String roomId,
    String userId, {
    String? reason,
  }) async {
    try {
      final response = await ApiService.post('/rooms/$roomId/ban/$userId', {
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });
      final bans = response['bans'];
      if (bans is List) {
        return bans
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      }
      return const [];
    } catch (e) {
      debugPrint('Error banning room participant: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> unbanParticipant(
    String roomId,
    String userId,
  ) async {
    try {
      final response = await ApiService.delete('/rooms/$roomId/ban/$userId');
      final bans = response['bans'];
      if (bans is List) {
        return bans
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      }
      return const [];
    } catch (e) {
      debugPrint('Error unbanning room participant: $e');
      rethrow;
    }
  }

  static dynamic _pruneNulls(dynamic value) {
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        final cleaned = _pruneNulls(entry.value);
        if (cleaned != null) {
          result[entry.key.toString()] = cleaned;
        }
      }
      return result;
    }

    if (value is List) {
      return value.map(_pruneNulls).where((item) => item != null).toList();
    }

    return value;
  }

  static Future<List<RoomModel>> _parseRoomList(
    dynamic response, {
    String key = 'rooms',
  }) async {
    final rawList = _extractList(response, key: key);
    final normalized = rawList
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    if (normalized.isEmpty) {
      return const [];
    }

    if (normalized.length < 20) {
      return normalized.map(RoomModel.fromJson).toList(growable: false);
    }

    return compute(_parseRoomListIsolate, normalized);
  }

  static List<dynamic> _extractList(
    dynamic response, {
    String key = 'rooms',
  }) {
    if (response is List) {
      return List<dynamic>.from(response);
    }

    if (response is Map && response[key] is List) {
      return List<dynamic>.from(response[key] as List);
    }

    return const [];
  }
}

List<RoomModel> _parseRoomListIsolate(List<Map<String, dynamic>> raw) {
  return raw.map(RoomModel.fromJson).toList(growable: false);
}
