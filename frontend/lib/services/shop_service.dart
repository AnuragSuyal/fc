import '../models/shop_models.dart';
import 'api_service.dart';

class ShopService {
  static int _nonce = 0;

  static Future<ShopHomeData> getHome() async {
    final response = await ApiService.get('/shop/home', dedupe: false);
    return ShopHomeData.fromJson(_asMap(response));
  }

  static Future<List<ShopCatalogItem>> getCatalog({
    String category = 'all',
  }) async {
    final response = await ApiService.get(
      '/shop/catalog?category=${Uri.encodeQueryComponent(category)}',
      dedupe: false,
    );
    final data = _asMap(response);
    final items = data['items'];
    if (items is! List) return const [];
    return List<ShopCatalogItem>.from(items.map(ShopCatalogItem.fromJson));
  }

  static Future<ShopInventoryData> getInventory() async {
    final response = await ApiService.get('/shop/inventory', dedupe: false);
    return ShopInventoryData.fromJson(_asMap(response));
  }

  static Future<Map<String, dynamic>> purchaseItem(String itemId) async {
    final response = await ApiService.post(
      '/shop/items/$itemId/purchase',
      const {},
      headers: _idempotencyHeaders('purchase', itemId),
    );
    return _asMap(response);
  }

  static Future<Map<String, dynamic>> useItem(String itemId) async {
    final response = await ApiService.post(
      '/shop/items/$itemId/use',
      const {},
      headers: _idempotencyHeaders('use', itemId),
    );
    return _asMap(response);
  }

  static Future<Map<String, dynamic>> equipItem(String itemId) async {
    final response =
        await ApiService.post('/shop/items/$itemId/equip', const {});
    return _asMap(response);
  }

  static Future<Map<String, dynamic>> unequipItem(String itemId) async {
    final response =
        await ApiService.post('/shop/items/$itemId/unequip', const {});
    return _asMap(response);
  }

  static Future<Map<String, dynamic>> toggleWishlist(String itemId) async {
    final response =
        await ApiService.post('/shop/items/$itemId/wishlist', const {});
    return _asMap(response);
  }

  static Future<Map<String, dynamic>> setInventoryFavorite(
    String itemId, {
    required bool favorited,
  }) async {
    final response = await ApiService.post(
      '/shop/inventory/$itemId/favorite',
      {'favorited': favorited},
    );
    return _asMap(response);
  }

  static Future<Map<String, dynamic>> viewItem(String itemId) async {
    final response =
        await ApiService.post('/shop/items/$itemId/view', const {});
    return _asMap(response);
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  static Map<String, String> _idempotencyHeaders(String scope, String itemId) {
    _nonce += 1;
    return <String, String>{
      'X-Idempotency-Key':
          'shop-$scope-$itemId-${DateTime.now().microsecondsSinceEpoch}-$_nonce',
    };
  }
}
