import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../utils/media_url.dart';

class GiftImage extends StatelessWidget {
  const GiftImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.borderRadius,
    this.fallback,
  });

  final String? source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final trimmed = source?.trim();
    Widget child;

    if (trimmed == null || trimmed.isEmpty || trimmed == 'null') {
      child = fallback ?? const _GiftImageFallback();
    } else if (trimmed.startsWith('assets/')) {
      child = Image.asset(
        trimmed,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => fallback ?? const _GiftImageFallback(),
      );
    } else {
      final resolvedUrl = resolveMediaUrl(trimmed);
      if (resolvedUrl == null) {
        child = fallback ?? const _GiftImageFallback();
      } else {
        child = CachedNetworkImage(
          imageUrl: resolvedUrl,
          width: width,
          height: height,
          fit: fit,
          errorWidget: (_, __, ___) => fallback ?? const _GiftImageFallback(),
        );
      }
    }

    if (borderRadius != null) {
      child = ClipRRect(
        borderRadius: borderRadius!,
        child: child,
      );
    }

    return child;
  }
}

class _GiftImageFallback extends StatelessWidget {
  const _GiftImageFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.card_giftcard_rounded,
        color: Colors.white70,
      ),
    );
  }
}
