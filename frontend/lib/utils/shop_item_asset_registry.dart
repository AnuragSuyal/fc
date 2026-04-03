import '../models/shop_models.dart';

enum ShopAssetCategory {
  frames,
  entryEffects,
  micAuras,
  chatBubbles,
  nameplates,
  boosters,
  collectibles,
  bundles,
  uiBadge,
  banner,
}

class ShopAssetBinding {
  final String key;
  final String assetPath;
  final ShopAssetCategory category;

  const ShopAssetBinding({
    required this.key,
    required this.assetPath,
    required this.category,
  });

  bool get prefersAvatarCore => category == ShopAssetCategory.frames;
  bool get prefersWideLayout =>
      category == ShopAssetCategory.nameplates ||
      category == ShopAssetCategory.bundles ||
      category == ShopAssetCategory.banner;
}

class ShopSectionDecoration {
  final String assetPath;
  final bool banner;

  const ShopSectionDecoration({
    required this.assetPath,
    this.banner = false,
  });
}

class ShopItemAssetRegistry {
  static const String _root = 'assets/shop_catalog';

  static const Map<String, ShopAssetBinding> _sourceAssets =
      <String, ShopAssetBinding>{
    'booster_profile_highlight': ShopAssetBinding(
      key: 'booster_profile_highlight',
      assetPath: '$_root/boosters/booster_profile_highlight.png',
      category: ShopAssetCategory.boosters,
    ),
    'booster_xp': ShopAssetBinding(
      key: 'booster_xp',
      assetPath: '$_root/boosters/booster_xp.png',
      category: ShopAssetCategory.boosters,
    ),
    'pass_event_access': ShopAssetBinding(
      key: 'pass_event_access',
      assetPath: '$_root/boosters/pass_event_access.png',
      category: ShopAssetCategory.boosters,
    ),
    'ticket_discover_boost': ShopAssetBinding(
      key: 'ticket_discover_boost',
      assetPath: '$_root/boosters/ticket_discover_boost.png',
      category: ShopAssetCategory.boosters,
    ),
    'ticket_spotlight': ShopAssetBinding(
      key: 'ticket_spotlight',
      assetPath: '$_root/boosters/ticket_spotlight.png',
      category: ShopAssetCategory.boosters,
    ),
    'token_lucky_spin': ShopAssetBinding(
      key: 'token_lucky_spin',
      assetPath: '$_root/boosters/token_lucky_spin.png',
      category: ShopAssetCategory.boosters,
    ),
    'bundle_creator_boost': ShopAssetBinding(
      key: 'bundle_creator_boost',
      assetPath: '$_root/bundles/bundle_creator_boost.png',
      category: ShopAssetCategory.bundles,
    ),
    'bundle_cute_starter': ShopAssetBinding(
      key: 'bundle_cute_starter',
      assetPath: '$_root/bundles/bundle_cute_starter.png',
      category: ShopAssetCategory.bundles,
    ),
    'bundle_elite_entry': ShopAssetBinding(
      key: 'bundle_elite_entry',
      assetPath: '$_root/bundles/bundle_elite_entry.png',
      category: ShopAssetCategory.bundles,
    ),
    'bundle_profile_glow': ShopAssetBinding(
      key: 'bundle_profile_glow',
      assetPath: '$_root/bundles/bundle_profile_glow.png',
      category: ShopAssetCategory.bundles,
    ),
    'chat_bubble_candy': ShopAssetBinding(
      key: 'chat_bubble_candy',
      assetPath: '$_root/chat_bubbles/chat_bubble_candy.png',
      category: ShopAssetCategory.chatBubbles,
    ),
    'chat_bubble_galaxy': ShopAssetBinding(
      key: 'chat_bubble_galaxy',
      assetPath: '$_root/chat_bubbles/chat_bubble_galaxy.png',
      category: ShopAssetCategory.chatBubbles,
    ),
    'chat_bubble_love': ShopAssetBinding(
      key: 'chat_bubble_love',
      assetPath: '$_root/chat_bubbles/chat_bubble_love.png',
      category: ShopAssetCategory.chatBubbles,
    ),
    'chat_bubble_min_black': ShopAssetBinding(
      key: 'chat_bubble_min_black',
      assetPath: '$_root/chat_bubbles/chat_bubble_min_black.png',
      category: ShopAssetCategory.chatBubbles,
    ),
    'chat_bubble_neon': ShopAssetBinding(
      key: 'chat_bubble_neon',
      assetPath: '$_root/chat_bubbles/chat_bubble_neon.png',
      category: ShopAssetCategory.chatBubbles,
    ),
    'chat_bubble_royal': ShopAssetBinding(
      key: 'chat_bubble_royal',
      assetPath: '$_root/chat_bubbles/chat_bubble_royal.png',
      category: ShopAssetCategory.chatBubbles,
    ),
    'collectible_crystal_orb': ShopAssetBinding(
      key: 'collectible_crystal_orb',
      assetPath: '$_root/collectibles/collectible_crystal_orb.png',
      category: ShopAssetCategory.collectibles,
    ),
    'collectible_festival_box': ShopAssetBinding(
      key: 'collectible_festival_box',
      assetPath: '$_root/collectibles/collectible_festival_box.png',
      category: ShopAssetCategory.collectibles,
    ),
    'collectible_golden_duck': ShopAssetBinding(
      key: 'collectible_golden_duck',
      assetPath: '$_root/collectibles/collectible_golden_duck.png',
      category: ShopAssetCategory.collectibles,
    ),
    'collectible_lucky_coin_totem': ShopAssetBinding(
      key: 'collectible_lucky_coin_totem',
      assetPath: '$_root/collectibles/collectible_lucky_coin_totem.png',
      category: ShopAssetCategory.collectibles,
    ),
    'collectible_mystery_capsule': ShopAssetBinding(
      key: 'collectible_mystery_capsule',
      assetPath: '$_root/collectibles/collectible_mystery_capsule.png',
      category: ShopAssetCategory.collectibles,
    ),
    'collectible_toy_rocket': ShopAssetBinding(
      key: 'collectible_toy_rocket',
      assetPath: '$_root/collectibles/collectible_toy_rocket.png',
      category: ShopAssetCategory.collectibles,
    ),
    'mic_aura_blue': ShopAssetBinding(
      key: 'mic_aura_blue',
      assetPath: '$_root/mic_auras/mic_aura_blue.png',
      category: ShopAssetCategory.micAuras,
    ),
    'mic_aura_cosmic': ShopAssetBinding(
      key: 'mic_aura_cosmic',
      assetPath: '$_root/mic_auras/mic_aura_cosmic.png',
      category: ShopAssetCategory.micAuras,
    ),
    'mic_aura_diamond': ShopAssetBinding(
      key: 'mic_aura_diamond',
      assetPath: '$_root/mic_auras/mic_aura_diamond.png',
      category: ShopAssetCategory.micAuras,
    ),
    'mic_aura_fire': ShopAssetBinding(
      key: 'mic_aura_fire',
      assetPath: '$_root/mic_auras/mic_aura_fire.png',
      category: ShopAssetCategory.micAuras,
    ),
    'mic_aura_golden_echo': ShopAssetBinding(
      key: 'mic_aura_golden_echo',
      assetPath: '$_root/mic_auras/mic_aura_golden_echo.png',
      category: ShopAssetCategory.micAuras,
    ),
    'mic_aura_love_pulse': ShopAssetBinding(
      key: 'mic_aura_love_pulse',
      assetPath: '$_root/mic_auras/mic_aura_love_pulse.png',
      category: ShopAssetCategory.micAuras,
    ),
    'nameplate_diamond': ShopAssetBinding(
      key: 'nameplate_diamond',
      assetPath: '$_root/nameplates/nameplate_diamond.png',
      category: ShopAssetCategory.nameplates,
    ),
    'nameplate_gold': ShopAssetBinding(
      key: 'nameplate_gold',
      assetPath: '$_root/nameplates/nameplate_gold.png',
      category: ShopAssetCategory.nameplates,
    ),
    'nameplate_legend_ribbon': ShopAssetBinding(
      key: 'nameplate_legend_ribbon',
      assetPath: '$_root/nameplates/nameplate_legend_ribbon.png',
      category: ShopAssetCategory.nameplates,
    ),
    'nameplate_neon': ShopAssetBinding(
      key: 'nameplate_neon',
      assetPath: '$_root/nameplates/nameplate_neon.png',
      category: ShopAssetCategory.nameplates,
    ),
    'nameplate_supreme': ShopAssetBinding(
      key: 'nameplate_supreme',
      assetPath: '$_root/nameplates/nameplate_supreme.png',
      category: ShopAssetCategory.nameplates,
    ),
    'frame_diamond': ShopAssetBinding(
      key: 'frame_diamond',
      assetPath: '$_root/frames/frame_diamond.png',
      category: ShopAssetCategory.frames,
    ),
    'frame_flame': ShopAssetBinding(
      key: 'frame_flame',
      assetPath: '$_root/frames/frame_flame.png',
      category: ShopAssetCategory.frames,
    ),
    'frame_frost': ShopAssetBinding(
      key: 'frame_frost',
      assetPath: '$_root/frames/frame_frost.png',
      category: ShopAssetCategory.frames,
    ),
    'frame_galaxy': ShopAssetBinding(
      key: 'frame_galaxy',
      assetPath: '$_root/frames/frame_galaxy.png',
      category: ShopAssetCategory.frames,
    ),
    'frame_neon': ShopAssetBinding(
      key: 'frame_neon',
      assetPath: '$_root/frames/frame_neon.png',
      category: ShopAssetCategory.frames,
    ),
    'frame_rainbow': ShopAssetBinding(
      key: 'frame_rainbow',
      assetPath: '$_root/frames/frame_rainbow.png',
      category: ShopAssetCategory.frames,
    ),
    'frame_royal': ShopAssetBinding(
      key: 'frame_royal',
      assetPath: '$_root/frames/frame_royal.png',
      category: ShopAssetCategory.frames,
    ),
    'frame_supreme_orbit': ShopAssetBinding(
      key: 'frame_supreme_orbit',
      assetPath: '$_root/frames/frame_supreme_orbit.png',
      category: ShopAssetCategory.frames,
    ),
    'entry_confetti': ShopAssetBinding(
      key: 'entry_confetti',
      assetPath: '$_root/entry_effects/entry_confetti.png',
      category: ShopAssetCategory.entryEffects,
    ),
    'entry_diamond_burst': ShopAssetBinding(
      key: 'entry_diamond_burst',
      assetPath: '$_root/entry_effects/entry_diamond_burst.png',
      category: ShopAssetCategory.entryEffects,
    ),
    'entry_galaxy_portal': ShopAssetBinding(
      key: 'entry_galaxy_portal',
      assetPath: '$_root/entry_effects/entry_galaxy_portal.png',
      category: ShopAssetCategory.entryEffects,
    ),
    'entry_legend_arrival': ShopAssetBinding(
      key: 'entry_legend_arrival',
      assetPath: '$_root/entry_effects/entry_legend_arrival.png',
      category: ShopAssetCategory.entryEffects,
    ),
    'entry_pop': ShopAssetBinding(
      key: 'entry_pop',
      assetPath: '$_root/entry_effects/entry_pop.png',
      category: ShopAssetCategory.entryEffects,
    ),
    'entry_royal_carpet': ShopAssetBinding(
      key: 'entry_royal_carpet',
      assetPath: '$_root/entry_effects/entry_royal_carpet.png',
      category: ShopAssetCategory.entryEffects,
    ),
    'entry_spotlight': ShopAssetBinding(
      key: 'entry_spotlight',
      assetPath: '$_root/entry_effects/entry_spotlight.png',
      category: ShopAssetCategory.entryEffects,
    ),
    'entry_thunder': ShopAssetBinding(
      key: 'entry_thunder',
      assetPath: '$_root/entry_effects/entry_thunder.png',
      category: ShopAssetCategory.entryEffects,
    ),
    'badge_best_value': ShopAssetBinding(
      key: 'badge_best_value',
      assetPath: '$_root/ui/badge_best_value.png',
      category: ShopAssetCategory.uiBadge,
    ),
    'badge_daily_deal': ShopAssetBinding(
      key: 'badge_daily_deal',
      assetPath: '$_root/ui/badge_daily_deal.png',
      category: ShopAssetCategory.uiBadge,
    ),
    'badge_hot': ShopAssetBinding(
      key: 'badge_hot',
      assetPath: '$_root/ui/badge_hot.png',
      category: ShopAssetCategory.uiBadge,
    ),
    'badge_limited': ShopAssetBinding(
      key: 'badge_limited',
      assetPath: '$_root/ui/badge_limited.png',
      category: ShopAssetCategory.uiBadge,
    ),
    'shop_banner_mystery': ShopAssetBinding(
      key: 'shop_banner_mystery',
      assetPath: '$_root/ui/shop_banner_mystery.png',
      category: ShopAssetCategory.banner,
    ),
  };

  static const Map<String, String> _itemToAssetKey = <String, String>{
    'frame_neon': 'frame_neon',
    'frame_royal': 'frame_royal',
    'frame_diamond': 'frame_diamond',
    'frame_galaxy': 'frame_galaxy',
    'frame_flame': 'frame_flame',
    'frame_rainbow': 'frame_rainbow',
    'frame_frost': 'frame_frost',
    'frame_supreme_orbit': 'frame_supreme_orbit',
    'entry_pop': 'entry_pop',
    'entry_confetti': 'entry_confetti',
    'entry_spotlight': 'entry_spotlight',
    'entry_thunder': 'entry_thunder',
    'entry_royal_carpet': 'entry_royal_carpet',
    'entry_diamond_burst': 'entry_diamond_burst',
    'entry_galaxy_portal': 'entry_galaxy_portal',
    'entry_legend_arrival': 'entry_legend_arrival',
    'mic_aura_blue': 'mic_aura_blue',
    'mic_aura_fire': 'mic_aura_fire',
    'mic_ring_diamond': 'mic_aura_diamond',
    'mic_love_pulse': 'mic_aura_love_pulse',
    'mic_golden_echo': 'mic_aura_golden_echo',
    'mic_cosmic_halo': 'mic_aura_cosmic',
    'bubble_candy': 'chat_bubble_candy',
    'bubble_neon': 'chat_bubble_neon',
    'bubble_royal': 'chat_bubble_royal',
    'bubble_galaxy': 'chat_bubble_galaxy',
    'bubble_minimal_black': 'chat_bubble_min_black',
    'bubble_love': 'chat_bubble_love',
    'nameplate_midnight_gold': 'nameplate_gold',
    'nameplate_neon_pop': 'nameplate_neon',
    'nameplate_diamond_shine': 'nameplate_diamond',
    'nameplate_legend_ribbon': 'nameplate_legend_ribbon',
    'nameplate_supreme_prism': 'nameplate_supreme',
    'booster_xp_2x_1h': 'booster_xp',
    'booster_xp_2x_24h': 'booster_xp',
    'booster_profile_highlight_1d': 'booster_profile_highlight',
    'booster_discover_ticket': 'ticket_discover_boost',
    'utility_lucky_spin_token': 'token_lucky_spin',
    'utility_event_access_pass': 'pass_event_access',
    'utility_spotlight_ticket': 'ticket_spotlight',
    'capsule_mystery': 'collectible_mystery_capsule',
    'collectible_golden_duck': 'collectible_golden_duck',
    'festival_box': 'collectible_festival_box',
    'collectible_lucky_coin_totem': 'collectible_lucky_coin_totem',
    'collectible_premium_toy_rocket': 'collectible_toy_rocket',
    'collectible_rare_crystal_orb': 'collectible_crystal_orb',
    'bundle_cute_starter_pack': 'bundle_cute_starter',
    'bundle_profile_glow_pack': 'bundle_profile_glow',
    'bundle_elite_entry_pack': 'bundle_elite_entry',
    'bundle_creator_boost_pack': 'bundle_creator_boost',
  };

  static final Set<String> _uiOnlyKeys = <String>{
    'badge_best_value',
    'badge_daily_deal',
    'badge_hot',
    'badge_limited',
    'shop_banner_mystery',
  };

  static ShopAssetBinding? resolveItem(String itemId) {
    final assetKey = _itemToAssetKey[itemId.trim().toLowerCase()];
    if (assetKey == null) {
      return null;
    }
    return _sourceAssets[assetKey];
  }

  static String? resolveItemAssetPath(String itemId) =>
      resolveItem(itemId)?.assetPath;

  static String? resolveItemPreviewAssetPath(String itemId) =>
      resolveItem(itemId)?.assetPath;

  static bool hasVisualForItem(String itemId) =>
      resolveItem(itemId)?.assetPath.isNotEmpty == true;

  static String? resolveBadgeAssetPath(ShopCatalogItem item) {
    if (item.isDailyDeal) {
      return _sourceAssets['badge_daily_deal']?.assetPath;
    }
    if (item.limitedEdition) {
      return _sourceAssets['badge_limited']?.assetPath;
    }

    final normalizedTags = item.tags.map((tag) => tag.toLowerCase()).toSet();
    if (normalizedTags.contains('best value')) {
      return _sourceAssets['badge_best_value']?.assetPath;
    }
    if (normalizedTags.contains('hot') || normalizedTags.contains('popular')) {
      return _sourceAssets['badge_hot']?.assetPath;
    }
    return null;
  }

  static ShopSectionDecoration? resolveSectionDecoration(String title) {
    switch (title) {
      case 'Daily Deals':
        return ShopSectionDecoration(
          assetPath: _sourceAssets['badge_daily_deal']!.assetPath,
        );
      case 'Most Popular':
        return ShopSectionDecoration(
          assetPath: _sourceAssets['badge_hot']!.assetPath,
        );
      case 'Limited Edition':
        return ShopSectionDecoration(
          assetPath: _sourceAssets['badge_limited']!.assetPath,
        );
      case 'Best Value Bundles':
        return ShopSectionDecoration(
          assetPath: _sourceAssets['badge_best_value']!.assetPath,
        );
      case 'Mystery Capsules':
        return ShopSectionDecoration(
          assetPath: _sourceAssets['shop_banner_mystery']!.assetPath,
          banner: true,
        );
      default:
        return null;
    }
  }

  static List<String> missingCatalogVisuals(Iterable<String> itemIds) {
    final missing = itemIds
        .where((itemId) => !hasVisualForItem(itemId))
        .map((itemId) => itemId.trim().toLowerCase())
        .toList()
      ..sort();
    return missing;
  }

  static List<String> unmatchedSourceAssetKeys(Iterable<String> itemIds) {
    final mappedKeys = itemIds
        .map((itemId) => _itemToAssetKey[itemId.trim().toLowerCase()])
        .whereType<String>()
        .toSet();
    final unmatched = _sourceAssets.keys
        .where((key) => !_uiOnlyKeys.contains(key) && !mappedKeys.contains(key))
        .toList()
      ..sort();
    return unmatched;
  }

  static List<String> get availableSourceAssetKeys => _sourceAssets.keys
      .where((key) => !_uiOnlyKeys.contains(key))
      .toList()
    ..sort();
}
