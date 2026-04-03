import 'package:flutter/material.dart';

import '../models/vip_model.dart';

class VipTierStyle {
  final String tierId;
  final int level;
  final String displayName;
  final String badgeAssetPath;
  final List<Color> nameColors;
  final List<Color> frameColors;
  final List<Color> surfaceGradient;
  final Color accent;
  final bool rainbow;

  const VipTierStyle({
    required this.tierId,
    required this.level,
    required this.displayName,
    required this.badgeAssetPath,
    required this.nameColors,
    required this.frameColors,
    required this.surfaceGradient,
    required this.accent,
    this.rainbow = false,
  });

  bool get isFree => level <= 0 || tierId == 'free';
}

class VipIdentityPalette {
  final VipTierStyle style;
  final Color fallbackNameColor;

  const VipIdentityPalette({
    required this.style,
    required this.fallbackNameColor,
  });
}

class VipTierStyles {
  static const String _assetBase = 'assets/vip_badges';

  static const List<String> orderedTierIds = <String>[
    'vip1',
    'vip2',
    'vip3',
    'vip4',
    'vip5',
    'vip6',
    'vip7',
    'vip8',
    'vip9',
    'vip10',
    'diamond',
    'legend',
    'supreme',
  ];

  static final Map<String, VipTierStyle> _styles = <String, VipTierStyle>{
    'free': _style(
      tierId: 'free',
      level: 0,
      displayName: 'Free',
      badge: '',
      nameColors: const <String>['#E2E8F0', '#94A3B8'],
      frameColors: const <String>['#334155', '#0F172A'],
      surfaceGradient: const <String>['#111827', '#1F2937'],
      accent: '#94A3B8',
    ),
    'vip1': _style(
      tierId: 'vip1',
      level: 1,
      displayName: 'VIP 1',
      badge: 'badge_vip1.png',
      nameColors: const <String>['#C6FF63', '#4DD23B'],
      frameColors: const <String>['#275E2C', '#B6FF64'],
      surfaceGradient: const <String>['#0D1D12', '#23492A', '#83FF4E'],
      accent: '#86F84E',
    ),
    'vip2': _style(
      tierId: 'vip2',
      level: 2,
      displayName: 'VIP 2',
      badge: 'badge_vip2.png',
      nameColors: const <String>['#B7E4FF', '#4290FF'],
      frameColors: const <String>['#153A7A', '#77C7FF'],
      surfaceGradient: const <String>['#08152B', '#123B80', '#6BC9FF'],
      accent: '#5EA8FF',
    ),
    'vip3': _style(
      tierId: 'vip3',
      level: 3,
      displayName: 'VIP 3',
      badge: 'badge_vip3.png',
      nameColors: const <String>['#F0C2FF', '#A44AFF'],
      frameColors: const <String>['#4D1C79', '#F0AEFF'],
      surfaceGradient: const <String>['#1D082A', '#5F1F89', '#F28BFF'],
      accent: '#C875FF',
    ),
    'vip4': _style(
      tierId: 'vip4',
      level: 4,
      displayName: 'VIP 4',
      badge: 'badge_vip4.png',
      nameColors: const <String>['#FFD996', '#FF9921'],
      frameColors: const <String>['#6C300B', '#FFD47C'],
      surfaceGradient: const <String>['#231208', '#8A4812', '#FFB33F'],
      accent: '#FF9E34',
    ),
    'vip5': _style(
      tierId: 'vip5',
      level: 5,
      displayName: 'VIP 5',
      badge: 'badge_vip5.png',
      nameColors: const <String>['#FFC7C7', '#E73C3C'],
      frameColors: const <String>['#7D171A', '#FF8A79'],
      surfaceGradient: const <String>['#260C11', '#81141C', '#FF6A59'],
      accent: '#FF665B',
    ),
    'vip6': _style(
      tierId: 'vip6',
      level: 6,
      displayName: 'VIP 6',
      badge: 'badge_vip6.png',
      nameColors: const <String>['#E0FF9A', '#2ACF7D'],
      frameColors: const <String>['#23643B', '#C8FF72'],
      surfaceGradient: const <String>['#102015', '#22623F', '#C9FF62'],
      accent: '#9AF05B',
    ),
    'vip7': _style(
      tierId: 'vip7',
      level: 7,
      displayName: 'VIP 7',
      badge: 'badge_vip7.png',
      nameColors: const <String>['#D5EAFF', '#4B90FF'],
      frameColors: const <String>['#2A4A87', '#C7EDFF'],
      surfaceGradient: const <String>['#0C1631', '#23468A', '#BDEBFF'],
      accent: '#7DBDFF',
    ),
    'vip8': _style(
      tierId: 'vip8',
      level: 8,
      displayName: 'VIP 8',
      badge: 'badge_vip8.png',
      nameColors: const <String>['#F7D8FF', '#9D52FF', '#F2C95D'],
      frameColors: const <String>['#6B30A8', '#F0C55D'],
      surfaceGradient: const <String>['#1C0C31', '#5A2494', '#F1CB67'],
      accent: '#D6AF58',
      rainbow: true,
    ),
    'vip9': _style(
      tierId: 'vip9',
      level: 9,
      displayName: 'VIP 9',
      badge: 'badge_vip9.png',
      nameColors: const <String>['#FFCACA', '#B0132E'],
      frameColors: const <String>['#511117', '#D56A5E'],
      surfaceGradient: const <String>['#140D11', '#501018', '#D66B5D'],
      accent: '#C9313E',
    ),
    'vip10': _style(
      tierId: 'vip10',
      level: 10,
      displayName: 'VIP 10',
      badge: 'badge_vip10.png',
      nameColors: const <String>['#FFE89F', '#F2BA37'],
      frameColors: const <String>['#7E3B12', '#FFE489'],
      surfaceGradient: const <String>['#231308', '#6B260B', '#F4C959'],
      accent: '#F4C552',
    ),
    'diamond': _style(
      tierId: 'diamond',
      level: 11,
      displayName: 'Diamond',
      badge: 'badge_diamond.png',
      nameColors: const <String>['#F0FAFF', '#83D0FF'],
      frameColors: const <String>['#27558E', '#D7F5FF'],
      surfaceGradient: const <String>['#0D1C31', '#214E86', '#D7F8FF'],
      accent: '#8FD7FF',
    ),
    'legend': _style(
      tierId: 'legend',
      level: 12,
      displayName: 'Legend',
      badge: 'badge_legend.png',
      nameColors: const <String>['#FFD88B', '#D73D2D', '#FF9F4A'],
      frameColors: const <String>['#7D2B15', '#FFB257'],
      surfaceGradient: const <String>['#1B0E09', '#74210F', '#F8A74B'],
      accent: '#FF9E47',
      rainbow: true,
    ),
    'supreme': _style(
      tierId: 'supreme',
      level: 13,
      displayName: 'Supreme',
      badge: 'badge_supreme.png',
      nameColors: const <String>[
        '#FF73D2',
        '#FFBE56',
        '#63E69F',
        '#65BCFF',
        '#C285FF'
      ],
      frameColors: const <String>['#E28CFF', '#FFD66B', '#77DBFF'],
      surfaceGradient: const <String>[
        '#281444',
        '#6A2DB3',
        '#FFB84D',
        '#56D4A7',
        '#60AFFF'
      ],
      accent: '#F1AAFF',
      rainbow: true,
    ),
  };

  static VipTierStyle fromTierId(String? tierId) {
    final normalized = (tierId ?? '').trim().toLowerCase();
    return _styles[normalized] ?? _styles['free']!;
  }

  static VipTierStyle fromLevel(int vipLevel) {
    if (vipLevel <= 0) return _styles['free']!;
    final safeIndex = vipLevel.clamp(1, orderedTierIds.length);
    return fromTierId(orderedTierIds[safeIndex - 1]);
  }

  static VipTierStyle fromMembership(
    VipMembershipSnapshot? membership, {
    int fallbackLevel = 0,
  }) {
    if (membership == null) {
      return fromLevel(fallbackLevel);
    }
    if (membership.activeTierId.isNotEmpty) {
      return fromTierId(membership.activeTierId);
    }
    if (membership.currentTierId.isNotEmpty &&
        membership.currentTierId != 'free') {
      return fromTierId(membership.currentTierId);
    }
    return fromLevel(fallbackLevel);
  }

  static VipIdentityPalette resolvePalette(
    VipMembershipSnapshot? membership, {
    int fallbackLevel = 0,
  }) {
    final style = fromMembership(membership, fallbackLevel: fallbackLevel);
    return VipIdentityPalette(
      style: style,
      fallbackNameColor:
          style.nameColors.isNotEmpty ? style.nameColors.last : style.accent,
    );
  }

  static VipTierStyle _style({
    required String tierId,
    required int level,
    required String displayName,
    required String badge,
    required List<String> nameColors,
    required List<String> frameColors,
    required List<String> surfaceGradient,
    required String accent,
    bool rainbow = false,
  }) {
    return VipTierStyle(
      tierId: tierId,
      level: level,
      displayName: displayName,
      badgeAssetPath: badge.isEmpty ? '' : '$_assetBase/$badge',
      nameColors: nameColors.map(_parseColor).toList(growable: false),
      frameColors: frameColors.map(_parseColor).toList(growable: false),
      surfaceGradient:
          surfaceGradient.map(_parseColor).toList(growable: false),
      accent: _parseColor(accent),
      rainbow: rainbow,
    );
  }

  static Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16) ?? 0x94A3B8;
    return Color(value + 0xFF000000);
  }
}
