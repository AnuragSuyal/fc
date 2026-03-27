import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../utils/constants.dart';

class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final String username;
  final double radius;
  final double? fontSize;

  const UserAvatar({
    super.key,
    this.imageUrl,
    required this.username,
    this.radius = 20,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final String effectiveUrl =
        (imageUrl != null && imageUrl!.isNotEmpty && imageUrl != 'null')
            ? imageUrl!
            : '';

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
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _getInitials(username),
        style: TextStyle(
          fontSize: fontSize ?? radius * 0.6,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildImage(ImageProvider imageProvider) {
    final colors = _getColors(username);
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Colors.white,
        backgroundImage: imageProvider,
      ),
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
