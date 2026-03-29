class GiftCategoryTab {
  final String key;
  final String label;

  const GiftCategoryTab({
    required this.key,
    required this.label,
  });
}

const List<GiftCategoryTab> giftCategoryTabs = <GiftCategoryTab>[
  GiftCategoryTab(key: 'simple', label: 'Simple'),
  GiftCategoryTab(key: 'premium', label: 'Premium'),
  GiftCategoryTab(key: 'luxury', label: 'Luxury'),
  GiftCategoryTab(key: 'limited', label: 'Limited'),
];

String normalizeGiftCategoryKey(String? rawCategory) {
  final normalized = (rawCategory ?? '').trim().toLowerCase();
  if (normalized == 'legendary') {
    return 'limited';
  }

  for (final category in giftCategoryTabs) {
    if (category.key == normalized) {
      return normalized;
    }
  }

  return 'simple';
}
