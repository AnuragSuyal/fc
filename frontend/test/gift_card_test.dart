import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/gift_model.dart';
import 'package:frontend/widgets/gift_card.dart';
import 'package:frontend/widgets/gift_image.dart';

void main() {
  GiftModel buildGift({
    required String id,
    required String name,
    required String category,
    required int tier,
    required int price,
    bool isLimited = false,
    int? totalAvailable,
    int? sold,
  }) {
    return GiftModel(
      id: id,
      databaseId: 'db_$id',
      name: name,
      description: 'Live room collectible',
      icon: 'assets/gifts/$id.png',
      assetPath: 'assets/gifts/$id.png',
      coinsPrice: price,
      gemsPrice: 0,
      category: category,
      tier: tier,
      rarity: category,
      sortOrder: 1,
      animation: const <String, dynamic>{},
      effects: const <String, dynamic>{},
      isLimited: isLimited,
      totalAvailable: totalAvailable,
      sold: sold,
      minLevel: 0,
      requiredVip: 0,
      totalSent: 0,
      isActive: true,
    );
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('gift card renders the new catalog artwork, name, and price',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        GiftCard(
          gift: buildGift(
            id: 'simple_microphone',
            name: 'Microphone',
            category: 'simple',
            tier: 1,
            price: 40,
          ),
        ),
      ),
    );

    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.byType(GiftImage), findsOneWidget);
  });

  testWidgets('limited gift card shows remaining supply badge',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        GiftCard(
          gift: buildGift(
            id: 'limited_confetti_ball',
            name: 'Confetti Ball',
            category: 'limited',
            tier: 4,
            price: 4000,
            isLimited: true,
            totalAvailable: 10,
            sold: 2,
          ),
        ),
      ),
    );

    expect(find.text('Confetti Ball'), findsOneWidget);
    expect(find.text('8 left'), findsOneWidget);
  });
}
