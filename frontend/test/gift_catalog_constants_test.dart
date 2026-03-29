import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/gift_catalog_constants.dart';

void main() {
  test('gift category tabs expose the exact active categories', () {
    expect(
      giftCategoryTabs.map((category) => category.label).toList(),
      ['Simple', 'Premium', 'Luxury', 'Limited'],
    );
    expect(
      giftCategoryTabs.map((category) => category.key).toList(),
      ['simple', 'premium', 'luxury', 'limited'],
    );
    expect(normalizeGiftCategoryKey('legendary'), 'limited');
  });
}
