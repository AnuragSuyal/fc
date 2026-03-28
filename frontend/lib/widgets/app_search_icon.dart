import 'package:flutter/material.dart';

class AppSearchIcon extends StatelessWidget {
  final double size;

  const AppSearchIcon({
    super.key,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/search_magnifier_old.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
