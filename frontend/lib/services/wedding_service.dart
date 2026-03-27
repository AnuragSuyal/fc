import 'package:flutter/foundation.dart';
import 'api_service.dart';

class WeddingService {
  static Future<List<Map<String, dynamic>>> getRings() async {
    try {
      final res = await ApiService.get('/wedding/rings');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) { debugPrint('getRings error: $e'); return []; }
  }

  static Future<Map<String, dynamic>?> getMyWedding() async {
    try { return await ApiService.get('/wedding/me'); }
    catch (e) { debugPrint('getMyWedding error: $e'); return null; }
  }

  static Future<dynamic> propose({required String partnerId, required String ringId}) =>
      ApiService.post('/wedding/propose', {'partnerId': partnerId, 'ringId': ringId});

  static Future<dynamic> accept(String weddingId) =>
      ApiService.post('/wedding/$weddingId/accept', {});

  static Future<dynamic> reject(String weddingId) =>
      ApiService.post('/wedding/$weddingId/reject', {});

  static Future<dynamic> divorce() =>
      ApiService.delete('/wedding/divorce');

  static Future<dynamic> bless({required String weddingId, String? message}) =>
      ApiService.post('/wedding/$weddingId/bless', {'message': message ?? '💕'});

  static Future<List<dynamic>> getCoupleRankings() async {
    try {
      final res = await ApiService.get('/wedding/rankings');
      return res is List ? res : (res['rankings'] ?? []);
    } catch (e) { debugPrint('getCoupleRankings error: $e'); return []; }
  }
}


