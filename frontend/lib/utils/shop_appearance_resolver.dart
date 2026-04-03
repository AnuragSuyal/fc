import 'package:flutter/material.dart';

import '../models/shop_models.dart';
import '../models/vip_model.dart';
import 'vip_tier_style.dart';

class ShopResolvedVisual {
  final List<Color> colors;
  final IconData icon;
  final Color? nameColor;
  final Color? accent;
  final bool rainbow;

  const ShopResolvedVisual({
    required this.colors,
    required this.icon,
    this.nameColor,
    this.accent,
    this.rainbow = false,
  });
}

class ShopAvatarDecor {
  final List<Color>? frameColors;
  final List<Color>? borderColors;
  final List<Color>? glowColors;

  const ShopAvatarDecor({
    this.frameColors,
    this.borderColors,
    this.glowColors,
  });

  bool get hasDecoration =>
      frameColors != null || borderColors != null || glowColors != null;
}

Color resolveShopRarityColor(String rarity) {
  switch (rarity.toLowerCase()) {
    case 'mythic':
      return const Color(0xFFFF7AF6);
    case 'legendary':
      return const Color(0xFFF59E0B);
    case 'epic':
      return const Color(0xFF8B5CF6);
    case 'rare':
      return const Color(0xFF38BDF8);
    case 'uncommon':
      return const Color(0xFF22C55E);
    default:
      return const Color(0xFF94A3B8);
  }
}

List<Color> resolvePreviewColors(
  Map<String, dynamic> previewStyle, {
  String itemId = '',
  String rarity = 'common',
}) {
  final rawColors = previewStyle['colors'];
  if (rawColors is List && rawColors.isNotEmpty) {
    final parsed =
        rawColors.map(_tryColor).whereType<Color>().toList(growable: false);
    if (parsed.isNotEmpty) {
      return parsed;
    }
  }

  return _resolveItemVisual(itemId, rarity: rarity).colors;
}

IconData resolvePreviewIcon(dynamic rawIcon, {String itemId = ''}) {
  final iconName = rawIcon?.toString().trim() ?? '';
  final mapped = _iconMap[iconName];
  if (mapped != null) {
    return mapped;
  }
  return _resolveItemVisual(itemId).icon;
}

ShopAvatarDecor resolveAvatarDecor(UserShopProfile? shopProfile) {
  if (shopProfile == null) {
    return const ShopAvatarDecor();
  }

  final frame = _resolveMaybe(shopProfile.equippedItem('profileFrameItemId'));
  final border = _resolveMaybe(shopProfile.equippedItem('avatarBorderItemId'));
  final glow = _resolveMaybe(shopProfile.equippedItem('profileGlowItemId'));

  return ShopAvatarDecor(
    frameColors: frame?.colors,
    borderColors: border?.colors,
    glowColors: glow?.colors ?? frame?.colors,
  );
}

Color resolveDisplayNameColor(
  UserShopProfile? shopProfile, {
  VipMembershipSnapshot? vipMembership,
  int fallbackVipLevel = 0,
  Color fallback = Colors.white,
}) {
  if (shopProfile == null) {
    final vipStyle =
        VipTierStyles.fromMembership(vipMembership, fallbackLevel: fallbackVipLevel);
    return vipStyle.isFree ? fallback : vipStyle.nameColors.last;
  }

  final nameplate = _resolveMaybe(shopProfile.equippedItem('nameplateItemId'));
  if (nameplate?.nameColor != null) {
    return nameplate!.nameColor!;
  }

  final frame = _resolveMaybe(shopProfile.equippedItem('profileFrameItemId'));
  final border = _resolveMaybe(shopProfile.equippedItem('avatarBorderItemId'));
  if (frame?.accent != null || border?.accent != null) {
    return frame?.accent ?? border?.accent ?? fallback;
  }

  final vipStyle =
      VipTierStyles.fromMembership(vipMembership, fallbackLevel: fallbackVipLevel);
  return vipStyle.isFree ? fallback : vipStyle.nameColors.last;
}

List<Color>? resolveNameplateColors(UserShopProfile? shopProfile) {
  if (shopProfile == null) {
    return null;
  }
  return _resolveMaybe(shopProfile.equippedItem('nameplateItemId'))?.colors;
}

Color? resolveChatBubbleAccent(UserShopProfile? shopProfile) {
  if (shopProfile == null) {
    return null;
  }
  return _resolveMaybe(shopProfile.equippedItem('chatBubbleItemId'))?.accent;
}

Color? resolveSpeakingGlowColor(UserShopProfile? shopProfile) {
  if (shopProfile == null) {
    return null;
  }
  return _resolveMaybe(shopProfile.equippedItem('speakingGlowItemId'))?.accent;
}

List<Color>? resolveEntryEffectColors(UserShopProfile? shopProfile) {
  if (shopProfile == null) {
    return null;
  }
  return _resolveMaybe(shopProfile.equippedItem('entryEffectItemId'))?.colors;
}

bool hasRainbowIdentity(UserShopProfile? shopProfile) {
  if (shopProfile == null) return false;
  return _resolveMaybe(shopProfile.equippedItem('profileFrameItemId'))
              ?.rainbow ==
          true ||
      _resolveMaybe(shopProfile.equippedItem('nameplateItemId'))?.rainbow ==
          true;
}

ShopResolvedVisual? _resolveMaybe(String itemId) {
  if (itemId.trim().isEmpty) {
    return null;
  }
  return _resolveItemVisual(itemId);
}

ShopResolvedVisual _resolveItemVisual(
  String itemId, {
  String rarity = 'common',
}) {
  final normalized = itemId.trim().toLowerCase();
  if (normalized.isEmpty) {
    return ShopResolvedVisual(
      colors: <Color>[
        resolveShopRarityColor(rarity).withValues(alpha: 0.95),
        const Color(0xFF1F2937),
      ],
      icon: Icons.auto_awesome_rounded,
      accent: resolveShopRarityColor(rarity),
    );
  }

  switch (normalized) {
    case 'frame_neon':
      return _visual(['#10E7FF', '#7C4DFF'], Icons.bolt_rounded);
    case 'frame_royal':
    case 'entry_royal_carpet':
    case 'bundle_elite_entry_pack':
      return _visual(['#F59E0B', '#B91C1C'], Icons.workspace_premium_rounded);
    case 'frame_diamond':
    case 'entry_diamond_burst':
    case 'mic_ring_diamond':
      return _visual(['#E0F2FE', '#38BDF8'], Icons.diamond_rounded);
    case 'frame_galaxy':
    case 'entry_galaxy_portal':
    case 'bubble_galaxy':
      return _visual(['#4F46E5', '#A855F7'], Icons.travel_explore_rounded);
    case 'frame_soft_pink':
    case 'bubble_love':
    case 'entry_heart':
      return _visual(['#F9A8D4', '#FB7185'], Icons.favorite_rounded);
    case 'frame_flame':
    case 'entry_flame':
    case 'mic_aura_fire':
      return _visual(
        ['#FB923C', '#DC2626'],
        Icons.local_fire_department_rounded,
      );
    case 'frame_shadow':
    case 'bubble_minimal_black':
      return _visual(['#111827', '#4B5563'], Icons.nightlight_round_rounded);
    case 'frame_rainbow':
    case 'frame_supreme_orbit':
      return _visual(
        ['#EC4899', '#F59E0B', '#10B981', '#38BDF8'],
        Icons.color_lens_rounded,
        rainbow: true,
      );
    case 'frame_frost':
    case 'theme_winter_lounge':
      return _visual(['#E0F2FE', '#60A5FA'], Icons.ac_unit_rounded);
    case 'glow_starlight_24h':
      return _visual(['#FDE68A', '#A78BFA'], Icons.auto_awesome_rounded);
    case 'avatar_border_spark_orbit_3d':
      return _visual(
        ['#34D399', '#3B82F6'],
        Icons.radio_button_checked_rounded,
      );
    case 'entry_pop':
    case 'entry_confetti':
      return _visual(['#22C55E', '#14B8A6'], Icons.celebration_rounded);
    case 'entry_spotlight':
      return _visual(['#FDE68A', '#F59E0B'], Icons.light_mode_rounded);
    case 'entry_thunder':
      return _visual(['#60A5FA', '#6366F1'], Icons.bolt_rounded);
    case 'entry_legend_arrival':
      return _visual(
        ['#F59E0B', '#B91C1C', '#7C3AED'],
        Icons.military_tech_rounded,
      );
    case 'mic_aura_blue':
      return _visual(['#60A5FA', '#2563EB'], Icons.mic_rounded);
    case 'mic_love_pulse':
      return _visual(['#FB7185', '#F472B6'], Icons.favorite_rounded);
    case 'mic_golden_echo':
      return _visual(['#FDE68A', '#D97706'], Icons.graphic_eq_rounded);
    case 'mic_cosmic_halo':
      return _visual(['#6366F1', '#A855F7'], Icons.blur_circular_rounded);
    case 'bubble_candy':
      return _visual(['#FDBA74', '#F472B6'], Icons.chat_bubble_rounded);
    case 'bubble_neon':
      return _visual(['#22D3EE', '#8B5CF6'], Icons.chat_bubble_rounded);
    case 'bubble_royal':
      return _visual(['#F59E0B', '#B91C1C'], Icons.chat_bubble_rounded);
    case 'bubble_valentine_whisper':
      return _visual(['#FB7185', '#F472B6'], Icons.chat_bubble_rounded);
    case 'nameplate_midnight_gold':
      return _visual(
        ['#111827', '#F59E0B'],
        Icons.badge_rounded,
        nameColor: const Color(0xFFFCD34D),
      );
    case 'nameplate_cloud_pop':
      return _visual(
        ['#93C5FD', '#F9A8D4'],
        Icons.sell_rounded,
        nameColor: const Color(0xFFF9A8D4),
      );
    case 'nameplate_neon_pop':
      return _visual(
        ['#22D3EE', '#8B5CF6'],
        Icons.bolt_rounded,
        nameColor: const Color(0xFFC4B5FD),
      );
    case 'nameplate_diamond_shine':
      return _visual(
        ['#E0F2FE', '#38BDF8'],
        Icons.diamond_rounded,
        nameColor: const Color(0xFFBAE6FD),
      );
    case 'nameplate_legend_ribbon':
      return _visual(
        ['#F59E0B', '#B91C1C'],
        Icons.workspace_premium_rounded,
        nameColor: const Color(0xFFFBBF24),
      );
    case 'nameplate_supreme_prism':
      return _visual(
        ['#EC4899', '#F59E0B', '#10B981', '#38BDF8'],
        Icons.color_lens_rounded,
        nameColor: const Color(0xFFF8FAFC),
        rainbow: true,
      );
    case 'level_frame_prism':
      return _visual(['#8B5CF6', '#06B6D4'], Icons.military_tech_rounded);
    case 'room_card_neon_panel':
      return _visual(['#22D3EE', '#8B5CF6'], Icons.style_rounded);
    case 'popup_card_royal_theme':
      return _visual(['#B91C1C', '#F59E0B'], Icons.view_carousel_rounded);
    case 'booster_xp_2x_1h':
    case 'booster_xp_2x_24h':
      return _visual(['#34D399', '#22C55E'], Icons.trending_up_rounded);
    case 'booster_profile_highlight_1d':
      return _visual(['#F59E0B', '#FB7185'], Icons.visibility_rounded);
    case 'booster_discover_ticket':
      return _visual(['#38BDF8', '#2563EB'], Icons.explore_rounded);
    case 'utility_lucky_spin_token':
      return _visual(['#F59E0B', '#EC4899'], Icons.casino_rounded);
    case 'utility_event_access_pass':
      return _visual(
        ['#8B5CF6', '#F59E0B'],
        Icons.confirmation_number_rounded,
      );
    case 'utility_spotlight_ticket':
      return _visual(['#FDE68A', '#F59E0B'], Icons.light_mode_rounded);
    case 'capsule_mystery':
      return _visual(['#8B5CF6', '#EC4899'], Icons.inventory_2_rounded);
    case 'festival_box':
      return _visual(['#F59E0B', '#8B5CF6'], Icons.redeem_rounded);
    case 'collectible_golden_duck':
      return _visual(['#FBBF24', '#F59E0B'], Icons.pets_rounded);
    case 'collectible_lucky_coin_totem':
      return _visual(
        ['#FDE68A', '#F59E0B'],
        Icons.workspace_premium_rounded,
      );
    case 'collectible_premium_toy_rocket':
      return _visual(['#38BDF8', '#8B5CF6'], Icons.rocket_launch_rounded);
    case 'collectible_rare_crystal_orb':
      return _visual(['#E0F2FE', '#38BDF8'], Icons.auto_awesome_rounded);
    case 'bundle_cute_starter_pack':
      return _visual(['#F9A8D4', '#FB7185'], Icons.redeem_rounded);
    case 'bundle_party_pack':
      return _visual(['#F59E0B', '#EC4899'], Icons.party_mode_rounded);
    case 'bundle_profile_glow_pack':
      return _visual(['#22D3EE', '#8B5CF6'], Icons.flare_rounded);
    case 'bundle_creator_boost_pack':
      return _visual(['#22C55E', '#06B6D4'], Icons.trending_up_rounded);
    case 'bundle_seasonal_pack':
      return _visual(['#F59E0B', '#8B5CF6', '#22C55E'], Icons.redeem_rounded);
    case 'frame_diwali_rangoli':
      return _visual(['#F59E0B', '#FB7185'], Icons.lightbulb_rounded);
    case 'entry_holi_splash':
      return _visual(
        ['#F97316', '#A855F7', '#22C55E'],
        Icons.water_drop_rounded,
      );
    case 'popup_card_winter_lounge':
      return _visual(['#E0F2FE', '#60A5FA'], Icons.ac_unit_rounded);
  }

  if (normalized.contains('diamond')) {
    return _visual(['#E0F2FE', '#38BDF8'], Icons.diamond_rounded);
  }
  if (normalized.contains('galaxy') || normalized.contains('cosmic')) {
    return _visual(['#4F46E5', '#A855F7'], Icons.travel_explore_rounded);
  }
  if (normalized.contains('royal') || normalized.contains('legend')) {
    return _visual(
      ['#F59E0B', '#B91C1C'],
      Icons.workspace_premium_rounded,
    );
  }
  if (normalized.contains('love') || normalized.contains('heart')) {
    return _visual(['#FB7185', '#F472B6'], Icons.favorite_rounded);
  }
  if (normalized.contains('frost') || normalized.contains('winter')) {
    return _visual(['#E0F2FE', '#60A5FA'], Icons.ac_unit_rounded);
  }
  if (normalized.contains('shadow') || normalized.contains('black')) {
    return _visual(['#111827', '#374151'], Icons.nightlight_round_rounded);
  }
  if (normalized.contains('fire') || normalized.contains('flame')) {
    return _visual(
      ['#FB923C', '#DC2626'],
      Icons.local_fire_department_rounded,
    );
  }
  if (normalized.contains('rainbow') || normalized.contains('supreme')) {
    return _visual(
      ['#EC4899', '#F59E0B', '#10B981', '#38BDF8'],
      Icons.color_lens_rounded,
      rainbow: true,
    );
  }

  final fallbackAccent = resolveShopRarityColor(rarity);
  return ShopResolvedVisual(
    colors: <Color>[
      fallbackAccent.withValues(alpha: 0.96),
      const Color(0xFF111827),
    ],
    icon: Icons.auto_awesome_rounded,
    accent: fallbackAccent,
  );
}

ShopResolvedVisual _visual(
  List<String> colors,
  IconData icon, {
  Color? nameColor,
  bool rainbow = false,
}) {
  final parsed =
      colors.map(_tryColor).whereType<Color>().toList(growable: false);
  final fallback = parsed.isNotEmpty ? parsed.first : const Color(0xFF8B5CF6);
  return ShopResolvedVisual(
    colors: parsed.isNotEmpty
        ? parsed
        : const <Color>[Color(0xFF8B5CF6), Color(0xFF111827)],
    icon: icon,
    nameColor: nameColor,
    accent: parsed.length > 1 ? parsed[1] : fallback,
    rainbow: rainbow,
  );
}

Color? _tryColor(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) {
    return null;
  }
  final hex = raw.replaceFirst('#', '');
  if (hex.length != 6) {
    return null;
  }
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) {
    return null;
  }
  return Color(parsed + 0xFF000000);
}

const Map<String, IconData> _iconMap = <String, IconData>{
  'bolt': Icons.bolt_rounded,
  'crown': Icons.workspace_premium_rounded,
  'diamond': Icons.diamond_rounded,
  'auto_awesome': Icons.auto_awesome_rounded,
  'favorite': Icons.favorite_rounded,
  'local_fire_department': Icons.local_fire_department_rounded,
  'nightlight_round': Icons.nightlight_round_rounded,
  'palette': Icons.palette_rounded,
  'ac_unit': Icons.ac_unit_rounded,
  'flare': Icons.flare_rounded,
  'stars': Icons.auto_awesome_rounded,
  'radio_button_checked': Icons.radio_button_checked_rounded,
  'celebration': Icons.celebration_rounded,
  'light_mode': Icons.light_mode_rounded,
  'travel_explore': Icons.travel_explore_rounded,
  'military_tech': Icons.military_tech_rounded,
  'mic': Icons.mic_rounded,
  'graphic_eq': Icons.graphic_eq_rounded,
  'surround_sound': Icons.surround_sound_rounded,
  'blur_circular': Icons.blur_circular_rounded,
  'chat_bubble': Icons.chat_bubble_rounded,
  'emoji_emotions': Icons.emoji_emotions_rounded,
  'insert_emoticon': Icons.insert_emoticon_rounded,
  'sticky_note_2': Icons.sticky_note_2_rounded,
  'badge': Icons.badge_rounded,
  'sell': Icons.sell_rounded,
  'workspace_premium': Icons.workspace_premium_rounded,
  'style': Icons.style_rounded,
  'view_carousel': Icons.view_carousel_rounded,
  'trending_up': Icons.trending_up_rounded,
  'rocket_launch': Icons.rocket_launch_rounded,
  'visibility': Icons.visibility_rounded,
  'explore': Icons.explore_rounded,
  'casino': Icons.casino_rounded,
  'confirmation_number': Icons.confirmation_number_rounded,
  'inventory_2': Icons.inventory_2_rounded,
  'pets': Icons.pets_rounded,
  'redeem': Icons.redeem_rounded,
  'lightbulb': Icons.lightbulb_rounded,
  'water_drop': Icons.water_drop_rounded,
  'party_mode': Icons.party_mode_rounded,
};
