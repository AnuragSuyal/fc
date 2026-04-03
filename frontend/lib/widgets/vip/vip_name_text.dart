import 'package:flutter/material.dart';

import '../../models/vip_model.dart';
import '../../utils/vip_tier_style.dart';

class VipNameText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final VipMembershipSnapshot? membership;
  final int fallbackVipLevel;
  final Color fallbackColor;
  final int maxLines;
  final TextOverflow overflow;

  const VipNameText(
    this.text, {
    super.key,
    this.style,
    this.membership,
    this.fallbackVipLevel = 0,
    this.fallbackColor = Colors.white,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    final palette = VipTierStyles.resolvePalette(
      membership,
      fallbackLevel: fallbackVipLevel,
    );
    final nameColors = palette.style.isFree
        ? <Color>[fallbackColor, fallbackColor]
        : palette.style.nameColors;

    final baseStyle = (style ?? DefaultTextStyle.of(context).style).copyWith(
      color: nameColors.length == 1 ? nameColors.first : fallbackColor,
    );

    if (!palette.style.rainbow || nameColors.length < 2) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: overflow,
        style: baseStyle.copyWith(color: nameColors.last),
      );
    }

    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: nameColors,
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(
        Rect.fromLTWH(0, 0, bounds.width == 0 ? 1 : bounds.width, bounds.height),
      ),
      blendMode: BlendMode.srcIn,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: overflow,
        style: baseStyle.copyWith(color: Colors.white),
      ),
    );
  }
}
