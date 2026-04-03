import 'package:flutter/material.dart';

import '../../models/vip_model.dart';
import '../../utils/vip_tier_style.dart';

enum VipBadgeSize {
  small(28),
  medium(42),
  large(72);

  const VipBadgeSize(this.dimension);
  final double dimension;
}

class VipBadge extends StatelessWidget {
  final VipMembershipSnapshot? membership;
  final int fallbackVipLevel;
  final VipBadgeSize size;
  final bool allowExpiredPreview;

  const VipBadge({
    super.key,
    this.membership,
    this.fallbackVipLevel = 0,
    this.size = VipBadgeSize.medium,
    this.allowExpiredPreview = false,
  });

  @override
  Widget build(BuildContext context) {
    final sourceMembership = membership;
    final shouldShowMembership = sourceMembership != null &&
        (sourceMembership.isActive ||
            (allowExpiredPreview && sourceMembership.currentTierId != 'free'));
    final style = shouldShowMembership
        ? VipTierStyles.fromMembership(sourceMembership,
            fallbackLevel: fallbackVipLevel)
        : VipTierStyles.fromLevel(fallbackVipLevel);

    if (style.isFree || style.badgeAssetPath.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size.dimension * 0.24),
      child: Image.asset(
        style.badgeAssetPath,
        width: size.dimension,
        height: size.dimension,
        fit: BoxFit.cover,
      ),
    );
  }
}
