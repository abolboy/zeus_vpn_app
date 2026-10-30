import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zeus_vpn/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('floating command navigation opens every primary workspace',
      (tester) async {
    await tester.pumpWidget(const ZeusApp());
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('NODES').last);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Node control center'), findsOneWidget);

    await tester.tap(find.text('FEEDS').last);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Subscriptions'), findsOneWidget);

    await tester.tap(find.text('LAB').last);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('PATT-NG & WARP'), findsOneWidget);

    await tester.tap(find.text('HOME').last);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Selected server'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding a failing HTTPS feed and syncing keeps the app alive',
      (tester) async {
    await tester.pumpWidget(const ZeusApp());
    await tester.pump(const Duration(seconds: 2));

    // Open the FEEDS tab and the subscription manager.
    final feedsTab = find.text('FEEDS');
    expect(feedsTab, findsWidgets);
    await tester.tap(feedsTab.last);
    await tester.pump(const Duration(milliseconds: 500));

    final addFeed = find.text('ADD FIRST FEED');
    if (addFeed.evaluate().isNotEmpty) {
      await tester.tap(addFeed.first);
    } else {
      final manageFeeds = find.text('MANAGE FEEDS');
      expect(manageFeeds, findsWidgets);
      await tester.tap(manageFeeds.first);
    }
    await tester.pump(const Duration(milliseconds: 500));

    final input = find.byType(TextField).first;
    await tester.enterText(input, 'https://127.0.0.1:1/subscription');
    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('SUB 1'), findsOneWidget);
    await tester.tap(find.text('SAVE & SYNC'));
    await tester.pump(const Duration(milliseconds: 500));

    // The sheet is dismissed while its input had focus. Its controller must
    // remain alive until the sheet subtree has actually left the widget tree.
    expect(find.text('SUBSCRIPTIONS'), findsNothing);
    expect(tester.takeException(), isNull,
        reason: 'Closing the subscription sheet must not use a disposed controller.');

    // Let the local connection-refused path complete without depending on
    // a public subscription provider or external network availability.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(tester.takeException(), isNull,
        reason: 'The UI must not throw while a feed sync fails.');
    expect(find.text('FEEDS'), findsWidgets,
        reason: 'The app should remain navigable after a failed sync.');
  });
}
