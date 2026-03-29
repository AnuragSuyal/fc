import 'package:flutter/material.dart';

import '../../models/color_clash_card_model.dart';
import '../../utils/constants.dart';

Color colorClashHueColor(String? hue) {
  switch (hue) {
    case 'ember':
      return const Color(0xFFE46F43);
    case 'tide':
    case 'tidal':
      return const Color(0xFF3F9EEB);
    case 'grove':
      return const Color(0xFF38A66F);
    case 'solar':
      return const Color(0xFFF0B84A);
    default:
      return AppColors.accentBerry;
  }
}

LinearGradient colorClashHueGradient(String? hue) {
  final base = colorClashHueColor(hue);
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      base.withValues(alpha: 0.94),
      Color.lerp(base, Colors.white, 0.45) ?? base,
    ],
  );
}

IconData colorClashCardIcon(String kind) {
  switch (kind) {
    case 'freeze':
      return Icons.ac_unit_rounded;
    case 'flip_flow':
      return Icons.sync_alt_rounded;
    case 'pulse_plus_two':
      return Icons.bolt_rounded;
    case 'prism':
      return Icons.auto_awesome_rounded;
    case 'prism_surge':
      return Icons.flare_rounded;
    case 'shield':
      return Icons.shield_rounded;
    case 'echo':
      return Icons.multitrack_audio_rounded;
    case 'swap':
      return Icons.swap_horiz_rounded;
    default:
      return Icons.style_rounded;
  }
}

String colorClashHueTitle(String? hue) {
  switch (hue) {
    case 'ember':
      return 'Ember';
    case 'tide':
    case 'tidal':
      return 'Tide';
    case 'grove':
      return 'Grove';
    case 'solar':
      return 'Solar';
    default:
      return 'Prism';
  }
}

Color colorClashCardTone(ColorClashCardModel? card) {
  if (card == null) {
    return AppColors.primaryBlue;
  }
  if (card.isPrismFamily) {
    return const Color(0xFF8C69F7);
  }
  if (card.kind == 'echo') {
    return const Color(0xFF5C7CE7);
  }
  if (card.kind == 'shield') {
    return const Color(0xFF36A887);
  }
  return colorClashHueColor(card.hue);
}
