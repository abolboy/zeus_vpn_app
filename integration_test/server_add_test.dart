import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zeus_vpn/main.dart';

Future<void> _waitForSubscriptionSheetToClose(WidgetTester tester) async {
  final sheetTitle = find.text('ذخیره و همگام‌سازی');
  for (var attempt = 0; attempt < 60; attempt++) {
    if (sheetTitle.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    sheetTitle,
    findsNothing,
    reason: 'The subscription sheet should close after secure writes complete.',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('floating command navigation opens every primary workspace',
      (tester) async {
    await tester.pumpWidget(const ZeusApp());
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('سرورها').last);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('سرورها'), findsWidgets);

    await tester.tap(find.text('اشتراک').last);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('اشتراک‌ها'), findsOneWidget);

    await tester.tap(find.text('تنظیمات').last);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('تنظیمات و امنیت'), findsOneWidget);

    await tester.tap(find.text('خانه').last);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('انتخاب سرور'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding a failing HTTPS feed and syncing keeps the app alive',
      (tester) async {
    await tester.pumpWidget(const ZeusApp());
    await tester.pump(const Duration(seconds: 2));

    // Open the FEEDS tab and the subscription manager.
    final feedsTab = find.text('اشتراک');
    expect(feedsTab, findsWidgets);
    await tester.tap(feedsTab.last);
    await tester.pump(const Duration(milliseconds: 500));

    final addFeed = find.text('افزودن اشتراک');
    if (addFeed.evaluate().isNotEmpty) {
      await tester.tap(addFeed.first);
    } else {
      final manageFeeds = find.text('مدیریت اشتراک‌ها');
      expect(manageFeeds, findsWidgets);
      await tester.tap(manageFeeds.first);
    }
    await tester.pump(const Duration(milliseconds: 500));

    final input = find.byType(TextField).first;
    await tester.enterText(input, 'https://127.0.0.1:1/subscription');
    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('اشتراک ۱'), findsOneWidget);
    await tester.tap(find.text('ذخیره و همگام‌سازی'));
    await _waitForSubscriptionSheetToClose(tester);

    // The sheet is dismissed while its input had focus. Its controller must
    // remain alive until the sheet subtree has actually left the widget tree.
    expect(find.text('ذخیره و همگام‌سازی'), findsNothing);
    expect(tester.takeException(), isNull,
        reason: 'Closing the subscription sheet must not use a disposed controller.');

    // Let the local connection-refused path complete without depending on
    // a public subscription provider or external network availability.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(tester.takeException(), isNull,
        reason: 'The UI must not throw while a feed sync fails.');
    expect(find.text('اشتراک'), findsWidgets,
        reason: 'The app should remain navigable after a failed sync.');
  });

  testWidgets('adding a single VLESS link saves it as a direct node', (tester) async {
    await tester.pumpWidget(const ZeusApp());
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('اشتراک').last);
    await tester.pump(const Duration(milliseconds: 500));

    final addFeed = find.text('افزودن اشتراک');
    if (addFeed.evaluate().isNotEmpty) {
      await tester.tap(addFeed.first);
    } else {
      await tester.tap(find.text('مدیریت اشتراک‌ها').first);
    }
    await tester.pump(const Duration(milliseconds: 500));

    const singleLink =
        'vless://11111111-1111-4111-8111-111111111111@example.com:443'
        '?security=tls&type=tcp#single-node';
    await tester.enterText(find.byType(TextField).first, singleLink);
    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('سرور ۱'), findsOneWidget);
    await tester.tap(find.text('ذخیره و همگام‌سازی'));
    await _waitForSubscriptionSheetToClose(tester);
    expect(find.text('ذخیره و همگام‌سازی'), findsNothing);
    expect(tester.takeException(), isNull);

    // Dismiss the software keyboard before using the persistent bottom nav.
    // On the emulator the keyboard can remain visible after the modal closes,
    // placing the nav label outside the hit-testable viewport.
    tester.testTextInput.hide();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('سرورها').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('مرکز مدیریت سرورها'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('[DIRECT] single-node'),
      findsWidgets,
      reason: 'The saved direct node should be visible in the node workspace.',
    );
    expect(tester.takeException(), isNull);
  });
}
