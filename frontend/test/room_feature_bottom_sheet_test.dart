import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/rooms/room_feature_bottom_sheet.dart';

void main() {
  testWidgets('golden dragon entry triggers callback when enabled',
      (tester) async {
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (_) => RoomFeatureBottomSheet(
                      roomId: 'room-1',
                      canActivateGoldenDragon: true,
                      onOpenGoldenDragon: () {
                        opened = true;
                      },
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Golden Dragon'), findsOneWidget);

    await tester.tap(find.text('Golden Dragon'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });
}
