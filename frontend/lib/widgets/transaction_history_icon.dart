import 'package:flutter/material.dart';

class TransactionHistoryIcon extends StatelessWidget {
  final double size;

  const TransactionHistoryIcon({
    super.key,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/transaction_history_icon.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
