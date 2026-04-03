import 'dart:math';

import '../models/golden_dragon_model.dart';
import 'api_service.dart';

class GoldenDragonService {
  GoldenDragonService._();

  static final Random _random = Random();

  static Future<DragonPacketProductsResponse> getProducts() async {
    final response = await ApiService.get('/dragon-packets/products');
    return DragonPacketProductsResponse.fromJson(_asMap(response));
  }

  static Future<DragonPacketInventoryResponse> getInventory() async {
    final response = await ApiService.get('/dragon-packets/inventory');
    return DragonPacketInventoryResponse.fromJson(_asMap(response));
  }

  static Future<GoldenDragonPurchaseResult> purchasePacket({
    required String productSku,
    String purchaseSource = 'mock',
  }) async {
    final idempotencyKey = createIdempotencyKey('dragon-purchase');
    final response = await ApiService.post(
      '/dragon-packets/purchase',
      <String, dynamic>{
        'productSku': productSku,
        'purchaseSource': purchaseSource,
        'idempotencyKey': idempotencyKey,
      },
      headers: <String, String>{
        'X-Idempotency-Key': idempotencyKey,
      },
    );
    return GoldenDragonPurchaseResult.fromJson(_asMap(response));
  }

  static Future<GoldenDragonActivationResult> activateEvent({
    required String roomId,
    String? purchaseInventoryId,
    String? productSku,
  }) async {
    final idempotencyKey = createIdempotencyKey('dragon-activate-$roomId');
    final response = await ApiService.post(
      '/rooms/$roomId/dragon-events/activate',
      <String, dynamic>{
        if ((purchaseInventoryId ?? '').trim().isNotEmpty)
          'purchaseInventoryId': purchaseInventoryId!.trim(),
        if ((productSku ?? '').trim().isNotEmpty)
          'productSku': productSku!.trim(),
      },
      headers: <String, String>{
        'X-Idempotency-Key': idempotencyKey,
      },
    );
    return GoldenDragonActivationResult.fromJson(_asMap(response));
  }

  static Future<GoldenDragonActiveEventResponse> getActiveEvent(
    String roomId,
  ) async {
    final response = await ApiService.get(
      '/rooms/$roomId/dragon-events/active',
      dedupe: false,
    );
    return GoldenDragonActiveEventResponse.fromJson(_asMap(response));
  }

  static Future<GoldenDragonEventResult> getEventResult({
    required String roomId,
    required String eventId,
  }) async {
    final response = await ApiService.get(
      '/rooms/$roomId/dragon-events/$eventId/result',
      dedupe: false,
    );
    return GoldenDragonEventResult.fromJson(_asMap(response));
  }

  static Future<GoldenDragonHistoryPage> getHistory({
    String view = 'all',
    String roomId = '',
    String status = '',
    String dateFrom = '',
    String dateTo = '',
    int page = 1,
    int limit = 20,
  }) async {
    final uri = Uri(
      path: '/dragon-events/history',
      queryParameters: <String, String>{
        'view': view,
        'page': '$page',
        'limit': '$limit',
        if (roomId.trim().isNotEmpty) 'roomId': roomId.trim(),
        if (status.trim().isNotEmpty) 'status': status.trim(),
        if (dateFrom.trim().isNotEmpty) 'dateFrom': dateFrom.trim(),
        if (dateTo.trim().isNotEmpty) 'dateTo': dateTo.trim(),
      },
    );
    final response = await ApiService.get(uri.toString());
    return GoldenDragonHistoryPage.fromJson(_asMap(response));
  }

  static String createIdempotencyKey(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final entropy = _random.nextInt(1 << 32);
    return '$prefix-$now-$entropy';
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }
}
