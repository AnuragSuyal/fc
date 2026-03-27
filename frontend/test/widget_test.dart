// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';
import 'package:frontend/utils/constants.dart';

void main() {
  const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(secureStorageChannel, (methodCall) async {
    // Simplest mock for secure storage used during startup.
    switch (methodCall.method) {
      case 'read':
        return null;
      case 'write':
      case 'delete':
        return true;
      default:
        return null;
    }
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(secureStorageChannel, null);
  });

  testWidgets('App renders splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(); // allow first frame

    expect(find.text(AppStrings.appName), findsOneWidget);

    // Let the splash timer complete so no pending timers remain.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}






