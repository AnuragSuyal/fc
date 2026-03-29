import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/rooms/room_seat_tile.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF080B16),
        body: Center(child: child),
      ),
    );
  }

  testWidgets('locked seat renders badge and manager lock control',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        RoomSeatTile(
          seatIndex: 2,
          isLocked: true,
          canManageLock: true,
          showLabel: true,
          onToggleLock: _noop,
        ),
      ),
    );

    expect(find.byKey(const Key('room-seat-locked-badge-2')), findsOneWidget);
    expect(find.byKey(const Key('room-seat-lock-control-2')), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
  });

  testWidgets('normal users do not see lock controls', (tester) async {
    await tester.pumpWidget(
      wrap(
        const RoomSeatTile(
          seatIndex: 3,
          isLocked: false,
          canManageLock: false,
          showLabel: true,
        ),
      ),
    );

    expect(find.byKey(const Key('room-seat-lock-control-3')), findsNothing);
    expect(find.text('Seat 3'), findsOneWidget);
  });

  testWidgets('seat tile reflects realtime-style lock state updates',
      (tester) async {
    var locked = false;

    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RoomSeatTile(
                seatIndex: 4,
                isLocked: locked,
                canManageLock: true,
                onToggleLock: () => setState(() => locked = !locked),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Seat 4'), findsOneWidget);
    expect(find.byKey(const Key('room-seat-locked-badge-4')), findsNothing);

    await tester.tap(find.byKey(const Key('room-seat-lock-control-4')));
    await tester.pumpAndSettle();

    expect(find.text('Locked'), findsOneWidget);
    expect(find.byKey(const Key('room-seat-locked-badge-4')), findsOneWidget);
  });
}

void _noop() {}
