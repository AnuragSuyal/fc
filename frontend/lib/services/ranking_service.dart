import 'package:flutter/foundation.dart';
import 'api_service.dart';

class RankingService {
  static Future<Map<String, dynamic>> getGiftRankings({String period = 'alltime', int limit = 100}) async {
    try { return await ApiService.get('/rankings/gifts?period=$period&limit=$limit'); }
    catch (e) { debugPrint('getGiftRankings error: $e'); return {'rankings': [], 'userRank': null}; }
  }

  static Future<Map<String, dynamic>> getCharmRankings({String period = 'alltime', int limit = 100}) async {
    try { return await ApiService.get('/rankings/charm?period=$period&limit=$limit'); }
    catch (e) { debugPrint('getCharmRankings error: $e'); return {'rankings': [], 'userRank': null}; }
  }

  static Future<Map<String, dynamic>> getWealthRankings({int limit = 100}) async {
    try { return await ApiService.get('/rankings/wealth?limit=$limit'); }
    catch (e) { debugPrint('getWealthRankings error: $e'); return {'rankings': []}; }
  }

  static Future<Map<String, dynamic>> getOverallRankings({int limit = 100}) async {
    try { return await ApiService.get('/rankings/overall?limit=$limit'); }
    catch (e) { debugPrint('getOverallRankings error: $e'); return {'rankings': []}; }
  }

  static Future<List<dynamic>> getActiveRoomRankings() async {
    try {
      final res = await ApiService.get('/rankings/rooms/active');
      return res['rankings'] as List? ?? [];
    } catch (e) { debugPrint('getActiveRoomRankings error: $e'); return []; }
  }

  static Future<Map<String, dynamic>> getGameRankings(String gameType, {String period = 'alltime'}) async {
    try { return await ApiService.get('/rankings/games/$gameType?period=$period'); }
    catch (e) { debugPrint('getGameRankings error: $e'); return {'rankings': [], 'userRank': null}; }
  }
}


