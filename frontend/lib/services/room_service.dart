import 'package:flutter/foundation.dart';
import 'api_service.dart';
import '../models/room_model.dart';

class MyRoomResolution {
  const MyRoomResolution({
    required this.room,
    this.created = false,
    this.migrated = false,
    this.archivedLegacyRoomCount = 0,
  });

  final RoomModel room;
  final bool created;
  final bool migrated;
  final int archivedLegacyRoomCount;
}

class RoomService {
  static const String _defaultPermanentRoomName = 'New Room';

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

  static Future<RoomModel?> getRoomById(
    String roomId, {
    bool forceRefresh = false,
  }) async {
    try {
      final response = await ApiService.get(
        '/rooms/$roomId',
        dedupe: !forceRefresh,
      );
      return RoomModel.fromJson(response);
    } catch (e) {
      debugPrint('Error getting room: $e');
      return null;
    }
  }

  static Future<MyRoomResolution?> getMyRoomResolution({
    bool allocateIfMissing = false,
  }) async {
    try {
      final suffix = allocateIfMissing ? '?allocate=true' : '';
      final response = await ApiService.get('/rooms/my-room$suffix');
      final roomJson =
          response is Map<String, dynamic> ? response['room'] : null;
      if (roomJson is Map<String, dynamic>) {
        return MyRoomResolution(
          room: RoomModel.fromJson(roomJson),
          created: response['created'] == true,
          migrated: response['migrated'] == true,
          archivedLegacyRoomCount: response['archivedLegacyRoomCount'] is int
              ? response['archivedLegacyRoomCount'] as int
              : int.tryParse('${response['archivedLegacyRoomCount']}') ?? 0,
        );
      }
      return null;
    } catch (e) {
      debugPrint('Error getting my permanent room: $e');
      return null;
    }
  }

  static Future<RoomModel?> getMyRoom({bool allocateIfMissing = false}) async {
    final resolution =
        await getMyRoomResolution(allocateIfMissing: allocateIfMissing);
    return resolution?.room;
  }

  static Future<MyRoomResolution?> ensureMyRoom({
    String? name,
    String? description,
    String? announcement,
    String? topic,
    String? language,
    String? region,
    String? roomRules,
    String type = 'voice',
    String category = 'all',
    List<String>? tags,
    Map<String, dynamic>? settings,
    Map<String, dynamic>? theme,
  }) async {
    final payload = Map<String, dynamic>.from(_pruneNulls({
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (announcement != null) 'announcement': announcement,
      if (topic != null) 'topic': topic,
      if (language != null) 'language': language,
      if (region != null) 'region': region,
      if (roomRules != null) 'roomRules': roomRules,
      if (name != null || type != 'voice') 'type': type,
      if (name != null || category != 'all') 'category': category,
      if (tags != null) 'tags': tags,
      if (settings != null) 'settings': settings,
      if (theme != null) 'theme': theme,
    }) as Map);
    final normalizedName = (payload['name']?.toString().trim().isNotEmpty ?? false)
        ? payload['name'].toString().trim()
        : _defaultPermanentRoomName;
    payload['name'] = normalizedName;

    try {
      final response = await ApiService.post(
        '/rooms/my-room',
        payload,
      );
      final resolution = _parseRoomResolutionResponse(response);
      if (resolution != null) {
        return resolution;
      }

      if (_looksLikeHtmlPayload(response)) {
        return _ensureMyRoomViaLegacyCreate(payload);
      }
      return null;
    } catch (e) {
      debugPrint('Error ensuring permanent room: $e');
      if (_shouldFallbackToLegacyCreate(e)) {
        try {
          return await _ensureMyRoomViaLegacyCreate(payload);
        } catch (legacyError) {
          debugPrint('Legacy permanent room fallback failed: $legacyError');
          throw _normalizeMyRoomError(legacyError);
        }
      }
      throw _normalizeMyRoomError(e);
    }
  }

  static Future<MyRoomResolution?> resolveMyRoom({
    String? cachedRoomId,
  }) async {
    final normalizedCachedId = cachedRoomId?.trim() ?? '';
    if (normalizedCachedId.isNotEmpty) {
      final cachedRoom = await getRoomById(
        normalizedCachedId,
        forceRefresh: true,
      );
      if (cachedRoom != null) {
        return MyRoomResolution(room: cachedRoom);
      }
    }

    final ensured = await ensureMyRoom(name: _defaultPermanentRoomName);
    if (ensured != null) {
      return ensured;
    }

    final existing = await getMyRoomResolution(allocateIfMissing: false);
    if (existing != null) {
      return existing;
    }

    throw _normalizeMyRoomError(
      Exception('Could not open your room right now. Please try again.'),
    );
  }

  static Future<List<Map<String, dynamic>>> searchYoutubeVideos(
    String roomId,
    String query,
  ) async {
    try {
      final encodedQuery = Uri.encodeQueryComponent(query);
      final response = await ApiService.get(
          '/rooms/$roomId/youtube-search?query=$encodedQuery');
      final results =
          response is Map<String, dynamic> ? response['results'] : null;
      if (results is! List) return const [];

      return results
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (e) {
      debugPrint('Error searching YouTube videos: $e');
      rethrow;
    }
  }

  static Future<RoomModel?> createRoom({
    required String name,
    String? description,
    String? announcement,
    String? topic,
    String? language,
    String? region,
    String? roomRules,
    String type = 'voice',
    String category = 'all',
    List<String>? tags,
    Map<String, dynamic>? settings,
    Map<String, dynamic>? theme,
  }) async {
    try {
      final ensured = await ensureMyRoom(
        name: name,
        description: description,
        announcement: announcement,
        topic: topic,
        language: language,
        region: region,
        roomRules: roomRules,
        type: type,
        category: category,
        tags: tags,
        settings: settings ??
            {
              'maxParticipants': 20,
              'entryFee': 0,
              'hdVoice': false,
              'allowGifts': true,
              'stageJoinsLocked': false,
              'maxActiveSpeakers': 8,
            },
        theme: theme ?? {'background': 'default'},
      );
      return ensured?.room;
    } catch (e) {
      debugPrint('Error creating permanent room: $e');
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

  static Future<List<RoomModel>> getFollowedRooms() async {
    try {
      final response = await ApiService.get('/rooms/followed');
      return _parseRoomList(response, key: 'rooms');
    } catch (e) {
      debugPrint('Error getting followed rooms: $e');
      return [];
    }
  }

  static Future<List<RoomModel>> getRecentRooms() async {
    try {
      final response = await ApiService.get('/rooms/recent');
      return _parseRoomList(response, key: 'rooms');
    } catch (e) {
      debugPrint('Error getting recent rooms: $e');
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

  static Future<bool> inviteFriend(String roomId, String targetUserId) async {
    try {
      await ApiService.post('/rooms/$roomId/invite', {
        'targetUserId': targetUserId,
      });
      return true;
    } catch (e) {
      debugPrint('Error inviting friend to room: $e');
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

  static Future<RoomModel?> lockSeat(String roomId, int seatIndex) async {
    final response =
        await ApiService.post('/rooms/$roomId/seat/$seatIndex/lock', {});
    final roomJson = response is Map<String, dynamic> ? response['room'] : null;
    if (roomJson is Map<String, dynamic>) {
      return RoomModel.fromJson(roomJson);
    }
    return null;
  }

  static Future<RoomModel?> unlockSeat(String roomId, int seatIndex) async {
    final response =
        await ApiService.post('/rooms/$roomId/seat/$seatIndex/unlock', {});
    final roomJson = response is Map<String, dynamic> ? response['room'] : null;
    if (roomJson is Map<String, dynamic>) {
      return RoomModel.fromJson(roomJson);
    }
    return null;
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

  static Future<void> promoteParticipant(
    String roomId,
    String userId, {
    int? seatIndex,
  }) async {
    await ApiService.post('/rooms/$roomId/promote/$userId', {
      if (seatIndex != null) 'seatIndex': seatIndex,
    });
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

  static Future<String?> reportRoom(
    String roomId,
    String reason, {
    String? targetUserId,
    String type = 'room',
  }) async {
    try {
      final response = await ApiService.post('/rooms/$roomId/report', {
        'reason': reason,
        if (targetUserId != null) 'targetUserId': targetUserId,
        'type': type,
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

  static MyRoomResolution? _parseRoomResolutionResponse(dynamic response) {
    if (response is Map<String, dynamic>) {
      final nestedRoomJson = response['room'];
      if (nestedRoomJson is Map<String, dynamic>) {
        return MyRoomResolution(
          room: RoomModel.fromJson(nestedRoomJson),
          created: response['created'] == true,
          migrated: response['migrated'] == true,
          archivedLegacyRoomCount: response['archivedLegacyRoomCount'] is int
              ? response['archivedLegacyRoomCount'] as int
              : int.tryParse('${response['archivedLegacyRoomCount']}') ?? 0,
        );
      }

      if (_looksLikeRoomPayload(response)) {
        return MyRoomResolution(
          room: RoomModel.fromJson(response),
          created: response['created'] == true,
          migrated: response['migrated'] == true,
          archivedLegacyRoomCount: response['archivedLegacyRoomCount'] is int
              ? response['archivedLegacyRoomCount'] as int
              : int.tryParse('${response['archivedLegacyRoomCount']}') ?? 0,
        );
      }
    }
    return null;
  }

  static bool _looksLikeHtmlPayload(dynamic response) {
    if (response is! String) {
      return false;
    }
    final normalized = response.trimLeft().toLowerCase();
    return normalized.startsWith('<!doctype') || normalized.startsWith('<html');
  }

  static bool _looksLikeRoomPayload(Map<String, dynamic> payload) {
    return (payload['_id'] ?? payload['id']) != null &&
        (payload['name'] != null ||
            payload['hostId'] != null ||
            payload['participants'] != null);
  }

  static bool _shouldFallbackToLegacyCreate(Object error) {
    final normalized = error.toString().toLowerCase();
    return normalized.contains('unexpected token \'<\'') ||
        normalized.contains('<!doctype') ||
        normalized.contains('<html') ||
        normalized.contains('server error: 404') ||
        normalized.contains('server error: 405') ||
        normalized.contains('server error: 500');
  }

  static Exception _normalizeMyRoomError(Object error) {
    final normalized = error.toString().toLowerCase();
    if (normalized.contains('unexpected token \'<\'') ||
        normalized.contains('<!doctype') ||
        normalized.contains('<html')) {
      return Exception('Could not open your room right now. Please try again.');
    }
    return error is Exception
        ? error
        : Exception('Could not open your room right now. Please try again.');
  }

  static Future<MyRoomResolution?> _ensureMyRoomViaLegacyCreate(
    Map<String, dynamic> payload,
  ) async {
    final legacyPayload = Map<String, dynamic>.from(payload);
    legacyPayload['name'] = (legacyPayload['name']?.toString().trim().isNotEmpty ??
            false)
        ? legacyPayload['name'].toString().trim()
        : _defaultPermanentRoomName;

    final response = await ApiService.post('/rooms', legacyPayload);
    return _parseRoomResolutionResponse(response);
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
