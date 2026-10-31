import 'package:flutter_test/flutter_test.dart';
import 'package:zeus_vpn/main.dart';

void main() {
  testWidgets('ZEUS app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const ZeusApp());
    expect(find.text('ZEUS'), findsOneWidget);
  });
}
