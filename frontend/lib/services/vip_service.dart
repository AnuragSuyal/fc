import 'package:flutter/foundation.dart';
import 'api_service.dart';

class VipService {
  static Future<List<Map<String, dynamic>>> getVipLevels() async {
    try {
      final res = await ApiService.get('/vip/levels');
      return List<Map<String, dynamic>>.from(res is List ? res : []);
    } catch (e) { debugPrint('getVipLevels error: $e'); return []; }
  }

  static Future<Map<String, dynamic>?> getVipStatus() async {
    try { return await ApiService.get('/vip/status'); }
    catch (e) { debugPrint('getVipStatus error: $e'); return null; }
  }

  static Future<Map<String, dynamic>> purchaseVip({required int level, String period = 'monthly'}) async {
    try { return await ApiService.post('/vip/purchase', {'level': level, 'period': period}); }
    catch (e) { debugPrint('purchaseVip error: $e'); rethrow; }
  }

  static Future<bool> cancelVip() async {
    try { await ApiService.post('/vip/cancel', {}); return true; }
    catch (e) { debugPrint('cancelVip error: $e'); return false; }
  }

  static Future<Map<String, dynamic>?> claimDailyBonus() async {
    try { return await ApiService.post('/vip/daily-bonus', {}); }
    catch (e) { debugPrint('claimDailyBonus error: $e'); return null; }
  }
}


