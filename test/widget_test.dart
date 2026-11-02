import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zeus_vpn/main.dart';

void main() {
  testWidgets('ZEUS app builds', (WidgetTester tester) async {
    // کنترلر در boot به SharedPreferences نیاز دارد؛ در تست باید mock شود.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ZeusApp());

    // انیمیشن‌های پس‌زمینه بی‌پایان تکرار می‌شوند؛ pumpAndSettle هیچ‌وقت settle نمی‌شود.
    await tester.pump(const Duration(seconds: 1));

    // لوگوی صفحهٔ خانه (و هدر منوی کشویی) حاوی «ZEUS VPN» هستند.
    expect(find.textContaining('ZEUS'), findsWidgets);
  });
}
