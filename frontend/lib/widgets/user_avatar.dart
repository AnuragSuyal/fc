import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/shop_models.dart';
import '../models/vip_model.dart';
import '../utils/shop_appearance_resolver.dart';
import '../utils/constants.dart';
import '../utils/media_url.dart';
import '../utils/vip_tier_style.dart';

class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final String username;
  final double radius;
  final double? fontSize;
  final UserShopProfile? shopProfile;
  final VipMembershipSnapshot? vipMembership;
  final int vipLevel;

  const UserAvatar({
    super.key,
    this.imageUrl,
    required this.username,
    this.radius = 20,
    this.fontSize,
    this.shopProfile,
    this.vipMembership,
    this.vipLevel = 0,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveUrl = resolveMediaUrl(imageUrl) ?? '';

    if (effectiveUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: effectiveUrl,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        maxWidthDiskCache: (radius * 4).round(),
        maxHeightDiskCache: (radius * 4).round(),
        memCacheWidth: (radius * 4).round(),
        memCacheHeight: (radius * 4).round(),
        imageBuilder: (context, imageProvider) => _buildImage(imageProvider),
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    final colors = _getColors(username);
    final decor = _resolveDecor();
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: decor.borderColors ?? colors,
        ),
        boxShadow: [
          for (final glow in decor.glowColors ?? const <Color>[])
            BoxShadow(
              color: glow.withValues(alpha: 0.22),
              blurRadius: radius * 0.9,
              spreadRadius: 1.2,
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(2.4),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: decor.frameColors == null
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: decor.frameColors!,
                  ),
            color: decor.frameColors == null ? null : Colors.white,
          ),
          child: Center(
            child: Text(
              _getInitials(username),
              style: TextStyle(
                fontSize: fontSize ?? radius * 0.6,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(ImageProvider imageProvider) {
    final colors = _getColors(username);
    final decor = _resolveDecor();
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: decor.borderColors ?? colors,
        ),
        boxShadow: [
          for (final glow in decor.glowColors ?? const <Color>[])
            BoxShadow(
              color: glow.withValues(alpha: 0.24),
              blurRadius: radius * 0.95,
              spreadRadius: 1.2,
            ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(2.4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: decor.frameColors == null
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: decor.frameColors!,
                ),
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: Colors.white,
          backgroundImage: imageProvider,
        ),
      ),
    );
  }

  ShopAvatarDecor _resolveDecor() {
    final shopDecor = resolveAvatarDecor(shopProfile);
    if (shopDecor.hasDecoration) {
      return shopDecor;
    }

    final vipStyle =
        VipTierStyles.fromMembership(vipMembership, fallbackLevel: vipLevel);
    if (vipStyle.isFree) {
      return shopDecor;
    }

    return ShopAvatarDecor(
      frameColors: vipStyle.frameColors,
      borderColors: vipStyle.frameColors,
      glowColors: <Color>[
        vipStyle.accent,
        ...vipStyle.frameColors.take(1),
      ],
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    return name[0].toUpperCase();
  }

  List<Color> _getColors(String name) {
    if (name.isEmpty) {
      return const [AppColors.primaryBlue, AppColors.accentBerry];
    }

    final hash = name.codeUnits.fold(0, (prev, element) => prev + element);
    const palettes = [
      [AppColors.primaryBlue, AppColors.accentYellow],
      [AppColors.secondaryBlue, AppColors.accentSky],
      [AppColors.accentBerry, AppColors.primaryBlue],
      [AppColors.successGreen, AppColors.accentYellow],
      [AppColors.accentSky, AppColors.accentBerry],
    ];
    return palettes[hash % palettes.length];
  }
}
