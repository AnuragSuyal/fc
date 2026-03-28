import 'dart:math' as math;

import 'package:flutter/widgets.dart';

enum _CurrencyKind { coins, gems }

class CurrencyIcon extends StatelessWidget {
  final _CurrencyKind _kind;
  final double size;
  final BoxFit fit;

  const CurrencyIcon.coins({
    super.key,
    this.size = 18,
    this.fit = BoxFit.contain,
  }) : _kind = _CurrencyKind.coins;

  const CurrencyIcon.gems({
    super.key,
    this.size = 18,
    this.fit = BoxFit.contain,
  }) : _kind = _CurrencyKind.gems;

  String get _assetPath {
    switch (_kind) {
      case _CurrencyKind.coins:
        return 'assets/images/currency_gold.png';
      case _CurrencyKind.gems:
        return 'assets/images/currency_diamond.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final adjustedSize = math.min(size * 1.6, size + 12);

    return SizedBox.square(
      dimension: adjustedSize,
      child: Image.asset(
        _assetPath,
        fit: fit,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
