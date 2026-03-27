import 'package:flutter/foundation.dart';
import '../models/quest_model.dart';
import 'api_service.dart';

class EconomyService {
  static Future<Map<String, dynamic>> claimDailyReward() async {
    try { return await ApiService.post('/economy/daily-reward', {}); }
    catch (e) { debugPrint('claimDailyReward error: $e'); rethrow; }
  }

  static Future<Map<String, dynamic>> getUserStats() async {
    try { return await ApiService.get('/economy/stats'); }
    catch (e) { debugPrint('getUserStats error: $e'); return {}; }
  }

  static Future<List<QuestModel>> getDailyQuests() async {
    try {
      final res = await ApiService.get('/economy/quests');
      if (res is List) return res.map((q) => QuestModel.fromJson(q)).toList();
      return [];
    } catch (e) { debugPrint('getDailyQuests error: $e'); return []; }
  }

  static Future<Map<String, dynamic>> claimQuestReward({required String questId}) async {
    try { return await ApiService.post('/economy/quests/claim', {'questId': questId}); }
    catch (e) { debugPrint('claimQuestReward error: $e'); rethrow; }
  }

  static Future<Map<String, dynamic>> progressQuest({required String templateId, int increment = 1}) async {
    try { return await ApiService.post('/economy/quests/progress', {'templateId': templateId, 'increment': increment}); }
    catch (e) { debugPrint('progressQuest error: $e'); return {}; }
  }

  static Future<Map<String, dynamic>> getConversionRates() async {
    try { return await ApiService.get('/economy/conversion-rates'); }
    catch (e) { debugPrint('getConversionRates error: $e'); return {}; }
  }

  static Future<Map<String, dynamic>?> purchasePack(String productId) async {
    try { return await ApiService.post('/economy/purchase', {'productId': productId}); }
    catch (e) { debugPrint('purchasePack error: $e'); rethrow; }
  }

  static Future<Map<String, dynamic>> getTransactions({int page = 1, String? type}) async {
    try {
      final q = type != null ? '?page=$page&type=$type' : '?page=$page';
      return await ApiService.get('/economy/transactions$q');
    } catch (e) { debugPrint('getTransactions error: $e'); return {'transactions': []}; }
  }
}


