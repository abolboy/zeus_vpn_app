// lib/ui/transitions.dart — ترنزیشن بدون هم‌پوشانی صفحات (رفع D1)
import 'dart:math';

import 'package:flutter/material.dart';

/// صفحهٔ قبلی اول کامل محو می‌شود، بعد صفحهٔ جدید وارد می‌شود.
/// چون در هیچ لحظه‌ای هر دو صفحه با opacity > 0 هم‌زمان نیستند، overlap رخ نمی‌دهد.
class ZeusRoute<T> extends PageRouteBuilder<T> {
  ZeusRoute({required Widget page, super.settings})
      : super(
          opaque: false, // پس‌زمینهٔ ریشه باید دیده شود
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 360),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (context, anim, secondary, child) {
            // ورود صفحهٔ جدید: نیمهٔ دوم بازه
            final enter = CurvedAnimation(
              parent: anim,
              curve: const Interval(0.45, 1.0, curve: Curves.easeOutCubic),
            );
            // خروج همین صفحه وقتی صفحهٔ بعدی روی آن push می‌شود: نیمهٔ اول بازه
            final exit = CurvedAnimation(
              parent: secondary,
              curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
            );
            return FadeTransition(
              opacity: Tween(begin: 1.0, end: 0.0).animate(exit),
              child: FadeTransition(
                opacity: enter,
                // ورود به‌صورت «گلیچ»: لرزش افقی که کم‌کم صاف می‌شود
                child: AnimatedBuilder(
                  animation: enter,
                  child: child,
                  builder: (_, ch) {
                    final left = 1 - enter.value;
                    final dx = sin(enter.value * 38) * 9 * left * left - 18 * left;
                    return Transform.translate(offset: Offset(dx, 0), child: ch);
                  },
                ),
              ),
            );
          },
        );
}

/// استفاده: Navigator.of(context).push(ZeusRoute(page: const SettingsPage(...)));
extension ZeusNav on NavigatorState {
  Future<T?> pushZeus<T>(Widget page) => push<T>(ZeusRoute<T>(page: page));
}
