// lib/ui/cyber.dart — افکت‌های Cyberpunk: متن گلیچی، صفحهٔ بوت هکری، CRT و رآکتور HUD
import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

double _bump(double v, double at, double w) => max(0.0, 1 - (v - at).abs() / w);

// ───────────────────────── متن گلیچی ─────────────────────────
/// متن با جدا شدن کانال‌های رنگی (سایان/مجنتا) و پرش‌های گلیچ گاه‌به‌گاه.
/// حروف انگلیسی هنگام گلیچ مثل «ترمینال خراب» جابه‌جا می‌شوند.
class GlitchText extends StatefulWidget {
  final String text;
  final double size;
  final FontWeight weight;
  final double letterSpacing;
  final Color colorA;
  final Color colorB;
  final FontStyle? fontStyle;
  const GlitchText(
    this.text, {
    super.key,
    this.size = 36,
    this.weight = FontWeight.w900,
    this.letterSpacing = 3,
    this.colorA = kCyan,
    this.colorB = kMagenta,
    this.fontStyle,
  });

  @override
  State<GlitchText> createState() => _GlitchTextState();
}

class _GlitchTextState extends State<GlitchText> {
  static const _junk = '!<>-_/[]{}=+*^?#01';

  String _scramble(String s, double g, int seed) {
    final r = Random(seed);
    final b = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      b.write(ch.trim().isEmpty || r.nextDouble() > g * .5 ? ch : _junk[r.nextInt(_junk.length)]);
    }
    return b.toString();
  }

  Widget _layers(String shown, double amp, double g, bool ascii) {
    final base = TextStyle(
      fontFamily: ascii ? kMono : null,
      fontSize: widget.size,
      fontWeight: widget.weight,
      fontStyle: widget.fontStyle,
      // letterSpacing روی حروف فارسی اتصال حروف را می‌شکند
      letterSpacing: ascii ? widget.letterSpacing : 0,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: Offset(-amp, -g * 1.5),
          child: Text(shown, style: base.copyWith(color: widget.colorA.withValues(alpha: .75))),
        ),
        Transform.translate(
          offset: Offset(amp, g * 1.5),
          child: Text(shown, style: base.copyWith(color: widget.colorB.withValues(alpha: .75))),
        ),
        Text(
          shown,
          style: base.copyWith(color: kText, shadows: [Shadow(color: widget.colorA.withValues(alpha: .6), blurRadius: 14)]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ascii = isAscii(widget.text);
    // حالت عادی یک ویجت ثابت است؛ فقط در لحظهٔ گلیچ دوباره ساخته می‌شود (نه هر فریم)
    final idle = RepaintBoundary(child: _layers(widget.text, .9, 0, ascii));
    return AnimatedBuilder(
      animation: Listenable.merge([zeusClock, zeusFx]),
      child: idle,
      builder: (_, idleChild) {
        if (zeusFx.value == 0) return idleChild!;
        final v = (zeusClock.value % 4.2) / 4.2;
        final g = max(_bump(v, .55, .035), max(_bump(v, .62, .02), _bump(v, .90, .03)));
        if (g <= 0) return idleChild!;
        final shown = (ascii && g > .25) ? _scramble(widget.text, g, (v * 90).floor()) : widget.text;
        return RepaintBoundary(child: _layers(shown, .9 + g * 6, g, ascii));
      },
    );
  }
}

// ───────────────────────── CRT: اسکن‌لاین + وینیت ─────────────────────────
/// لایهٔ ثابت (فقط یک بار رسم می‌شود) روی کل برنامه؛ ورودی لمس را نمی‌گیرد.
class CrtOverlay extends StatelessWidget {
  const CrtOverlay({super.key});

  @override
  Widget build(BuildContext context) => const IgnorePointer(
        child: RepaintBoundary(child: CustomPaint(size: Size.infinite, painter: _CrtPainter())),
      );
}

class _CrtPainter extends CustomPainter {
  const _CrtPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final line = Paint()..color = const Color(0x12000000);
    for (double y = 0; y < s.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, s.width, 1), line);
    }
    canvas.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = RadialGradient(
          radius: 1.15,
          colors: [Colors.transparent, kSurface.withValues(alpha: .55)],
          stops: const [.62, 1],
        ).createShader(Offset.zero & s),
    );
  }

  @override
  bool shouldRepaint(_CrtPainter o) => false;
}

// ───────────────────────── صفحهٔ بوت هکری ─────────────────────────
/// ترمینالِ چند ثانیه‌ای هنگام باز شدن اپ؛ با لمس رد می‌شود. فقط AnimationController دارد
/// (بدون Timer) تا در تست‌ها مشکلی ایجاد نکند.
class BootOverlay extends StatefulWidget {
  final String version;
  const BootOverlay({super.key, required this.version});

  @override
  State<BootOverlay> createState() => _BootOverlayState();
}

class _BootOverlayState extends State<BootOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  bool _done = false;

  static const _steps = [
    'mount encrypted tunnel',
    'load xray core',
    'spawn matrix rain',
    'seal dns leaks',
    'randomize tls fingerprint',
    'arm kill-switch',
  ];

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _done = true);
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _c.value = 1,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final v = _c.value;
            final fade = v > .88 ? (1 - (v - .88) / .12) : 1.0;
            const dim = TextStyle(fontFamily: kMono, fontSize: 12.5, color: kMuted, height: 1.2);
            const ok = TextStyle(fontFamily: kMono, fontSize: 12.5, color: kCyan, fontWeight: FontWeight.w800);
            final lines = <Widget>[];
            for (var i = 0; i < _steps.length; i++) {
              final start = .06 + i * .13;
              final k = ((v - start) / .10).clamp(0.0, 1.0).toDouble();
              if (k <= 0) break;
              final label = '> ${_steps[i]} ';
              final cut = min(label.length, (label.length * k).ceil());
              lines.add(Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: label.substring(0, cut), style: dim),
                  if (k >= 1) const TextSpan(text: '[ OK ]', style: ok),
                ])),
              ));
            }
            return Opacity(
              opacity: fade.clamp(0.0, 1.0).toDouble(),
              child: Material(
                color: kSurface,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 56, 24, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GlitchText('ZEUS VPN', size: 34),
                        const SizedBox(height: 6),
                        Text('zeus//os ${widget.version}', style: dim),
                        const SizedBox(height: 30),
                        ...lines,
                        if (v > .74)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text(
                              '> ACCESS GRANTED',
                              style: TextStyle(
                                fontFamily: kMono,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: kMagenta,
                                letterSpacing: 2,
                                shadows: [Shadow(color: kMagenta, blurRadius: 12)],
                              ),
                            ),
                          ),
                        const Spacer(),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: v.clamp(0.02, 1.0).toDouble(),
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(color: kCyan, boxShadow: neonGlow(kCyan, blur: 8, alpha: .8)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('tap to skip', style: TextStyle(fontFamily: kMono, fontSize: 10, color: kMuted)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ───────────────────────── رآکتور HUD (دکمهٔ اتصال) ─────────────────────────
/// t بین 0..1 است و باید دورهٔ ۱۲ ثانیه‌ای داشته باشد؛ همهٔ ضریب‌ها عدد صحیح‌اند
/// تا هنگام برگشت t از 1 به 0 پرشی دیده نشود.
class ReactorPainter extends CustomPainter {
  final double t;
  final Color color;
  final bool spinning;
  final bool full;
  const ReactorPainter({required this.t, required this.color, required this.spinning, required this.full});

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2 - 14;
    const tau = 2 * pi;
    final pulse = .5 + .5 * sin(t * tau * 4);

    // هالهٔ پس‌زمینه
    canvas.drawCircle(
      c,
      r + 10,
      Paint()
        ..shader = RadialGradient(colors: [color.withValues(alpha: (full ? .26 : .12) + .07 * pulse), Colors.transparent])
            .createShader(Rect.fromCircle(center: c, radius: r + 10)),
    );

    // رادار
    if (full || spinning) {
      final a = t * tau * (spinning ? 6 : 2);
      final rr = Rect.fromCircle(center: c, radius: r - 26);
      canvas.drawCircle(
        c,
        r - 26,
        Paint()
          ..shader = SweepGradient(
            colors: [Colors.transparent, color.withValues(alpha: .38)],
            stops: const [.62, 1.0],
            transform: GradientRotation(a),
          ).createShader(rr),
      );
    }

    // حلقهٔ بیرونی با تیک‌های چرخان
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: .3),
    );
    final longTick = Paint()
      ..strokeWidth = 1.7
      ..color = color.withValues(alpha: .85);
    final shortTick = Paint()
      ..strokeWidth = 1
      ..color = color.withValues(alpha: .35);
    for (var i = 0; i < 72; i++) {
      final a = t * tau + i * tau / 72;
      final long = i % 6 == 0;
      final dir = Offset(cos(a), sin(a));
      canvas.drawLine(c + dir * r, c + dir * (r - (long ? 9 : 4)), long ? longTick : shortTick);
    }

    // قطعه‌های مجنتا در خلاف جهت
    final seg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = kMagenta.withValues(alpha: .85);
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r - 14), -t * tau * 3 + i * tau / 3, tau / 3 * .55, false, seg);
    }

    // نقطه‌های مداری
    const ks = [2, -3, 4];
    for (var i = 0; i < 3; i++) {
      final a = t * tau * ks[i] + i * 2.1;
      final p = c + Offset(cos(a), sin(a)) * (r - 3);
      // هالهٔ ساده (بدون MaskFilter.blur که هر فریم گران است)
      canvas.drawCircle(p, 5.5, Paint()..color = color.withValues(alpha: .28));
      canvas.drawCircle(p, 3.2, Paint()..color = color);
      canvas.drawCircle(p, 1.5, Paint()..color = Colors.white);
    }

    // کمان اصلی وضعیت
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = color;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: .22);
    final start = spinning ? t * tau * 4 : -pi / 2;
    final sweep = spinning ? pi * .6 : (full ? tau : pi * 1.5);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r - 26), start, sweep, false, glow);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r - 26), start, sweep, false, arc);

    // حلقهٔ خط‌چین داخلی
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: .5);
    for (var i = 0; i < 36; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r - 34), i * tau / 36, tau / 36 * .5, false, dash);
    }

    // هسته
    canvas.drawCircle(c, r - 42, Paint()..color = kSurface.withValues(alpha: .94));
    canvas.drawCircle(
      c,
      r - 42,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: .6),
    );

    // براکت‌های HUD در چهار گوشه
    final br = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: .8);
    final h = s.width / 2 - 2;
    const len = 16.0;
    for (final sx in const [-1.0, 1.0]) {
      for (final sy in const [-1.0, 1.0]) {
        final corner = c + Offset(sx * h, sy * h);
        canvas.drawLine(corner, corner + Offset(-sx * len, 0), br);
        canvas.drawLine(corner, corner + Offset(0, -sy * len), br);
      }
    }
  }

  @override
  bool shouldRepaint(ReactorPainter o) => o.t != t || o.color != color || o.spinning != spinning || o.full != full;
}

// ───────────────────────── دکمهٔ «پالت تم» (گل نئونی) ─────────────────────────
/// دکمهٔ گل‌مانند با پالتِ رنگ داخلش؛ گلبرگ‌ها آرام می‌چرخند و نقطه‌های پالت به رنگ‌های تم‌اند.
class PaletteFlower extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  final Color color;
  final List<Color> dots;
  const PaletteFlower({
    super.key,
    required this.onTap,
    this.size = 46,
    this.color = kGreen,
    this.dots = const [kGreen, kBlue, kAmber, kMagenta],
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: RepaintBoundary(child: CustomPaint(painter: _FlowerPainter(color, dots))),
        ),
      );
}

class _FlowerPainter extends CustomPainter {
  final Color color;
  final List<Color> dots;
  _FlowerPainter(this.color, this.dots) : super(repaint: zeusClock);

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2 - 3;
    final rot = zeusClock.value * .35;

    // شکل گل: ۸ گلبرگ گرد
    final flower = Path();
    const steps = 160;
    for (var i = 0; i <= steps; i++) {
      final a = i / steps * 2 * pi;
      final rr = r * (.86 + .14 * cos(8 * a));
      final p = c + Offset(cos(a + rot), sin(a + rot)) * rr;
      if (i == 0) {
        flower.moveTo(p.dx, p.dy);
      } else {
        flower.lineTo(p.dx, p.dy);
      }
    }
    flower.close();
    canvas.drawPath(
      flower,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = color.withValues(alpha: .25),
    );
    canvas.drawPath(flower, Paint()..color = color);

    // پالتِ تیره با سوراخ شست
    final u = r * .95;
    var body = Path()..addOval(Rect.fromCenter(center: c, width: u * 1.15, height: u * .98));
    final hole = Path()..addOval(Rect.fromCircle(center: c + Offset(u * .28, u * .2), radius: u * .12));
    body = Path.combine(PathOperation.difference, body, hole);
    canvas.drawPath(body, Paint()..color = kSurface);

    // نقطه‌های رنگی پالت = رنگ‌های تم
    final pos = [Offset(-.30, -.02), Offset(-.14, -.2), Offset(.14, -.2), Offset(.30, -.02)];
    for (var i = 0; i < pos.length && i < dots.length; i++) {
      canvas.drawCircle(c + pos[i] * u, u * .075, Paint()..color = dots[i]);
    }
  }

  @override
  bool shouldRepaint(_FlowerPainter o) => o.color != color || o.dots != dots;
}
