// lib/ui/theme.dart — پالت Hacker Matrix، پس‌زمینهٔ متحرک و ویجت‌های مشترک
import 'dart:math';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/foundation.dart' show ValueListenable;

// ───────────── پالت Hacker Matrix (سبز روی مشکی) ─────────────
// ساختار و چیدمان دست‌نخورده ماند؛ فقط رنگ‌ها به سبک ترمینال هکری تغییر کردند.
// نام‌های قدیمی (kCyan/kMagenta/…) حفظ شده‌اند تا بقیهٔ صفحات بدون تغییر کار کنند.
const Color kCyan = Color(0xFF00FF66);      // رنگ اصلی — سبز ماتریکس
const Color kMagenta = Color(0xFFFF2E2E);   // کانال دوم گلیچ / وضعیت قطع — قرمز هکری
const Color kPurple = Color(0xFF00A86B);    // هالهٔ دوم — سبز یشمی
const Color kGreen = kCyan;                 // وضعیت سالم (نام قدیمی برای سازگاری صفحات)
const Color kBlue = Color(0xFF00E5B0);      // نعنایی — رنگ آپلود
const Color kAmber = Color(0xFFFFC400);     // هشدار ترمینال
const Color kRed = Color(0xFFFF3131);       // خطا
const Color kSurface = Color(0xFF030B07);   // مشکیِ ته‌رنگ سبز
const Color kSurface2 = Color(0xFF0A1A10);  // سطح دوم پنل‌ها
const Color kBorder = Color(0x3300FF66);    // حاشیهٔ سبز کم‌رنگ
const Color kText = Color(0xFFD9FFE9);      // متن اصلی — سفیدِ ته‌رنگ سبز
const Color kMuted = Color(0xFF5F8F73);     // متن کم‌اهمیت
const Color kGreenDim = Color(0x2200FF66);

const LinearGradient kNeonGradient = LinearGradient(
  colors: [Color(0xFF00FF66), Color(0xFF00B34A)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

List<BoxShadow> neonGlow(Color c, {double blur = 16, double alpha = .45}) => [
      BoxShadow(color: c.withValues(alpha: alpha), blurRadius: blur, spreadRadius: 0),
    ];

/// رنگ پینگ: -2 تست‌نشده، -1 timeout
Color pingColor(int ms) {
  if (ms == -2) return kMuted;
  if (ms < 0) return kRed;
  if (ms < 150) return kGreen;
  if (ms < 400) return kAmber;
  return kRed;
}

// ───────────────────────── پس‌زمینهٔ متحرک ─────────────────────────
/// وقتی enabled=false فقط child را برمی‌گرداند (پس‌زمینهٔ واحد در ریشهٔ اپ رندر می‌شود — رفع D1)
class ZeusBackground extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const ZeusBackground({super.key, required this.child, this.enabled = false});
  @override
  State<ZeusBackground> createState() => _ZeusBackgroundState();
}

class _ZeusBackgroundState extends State<ZeusBackground> with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _speed = 1;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _ticker = createTicker(_tick)..start();
  }

  /// زمان را با سرعتی که به وضعیت اتصال بستگی دارد جمع می‌کند (بدون پرش هنگام تغییر سرعت)
  void _tick(Duration e) {
    final dt = ((e - _last).inMicroseconds / 1e6).clamp(0.0, 0.1).toDouble();
    _last = e;
    final target = zeusActive.value ? 1.9 : 1.0;
    _speed += (target - _speed) * min(1.0, dt * 2.0);
    _clock.value += dt * _speed;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: kSurface),
        RepaintBoundary(
          child: ValueListenableBuilder<Color>(
            valueListenable: zeusAccent,
            builder: (_, accent, __) => TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: accent),
              duration: const Duration(milliseconds: 700),
              builder: (_, col, __) => CustomPaint(
                size: Size.infinite,
                painter: _BgPainter(_clock, col ?? accent),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// بارش دادهٔ دیجیتال + گرید پرسپکتیو + هاله + اسکن + گلیچ، همه به رنگ وضعیت اتصال
class _BgPainter extends CustomPainter {
  final ValueListenable<double> clock;
  final Color accent;
  _BgPainter(this.clock, this.accent) : super(repaint: clock);

  static double _h(int a, int b) {
    final v = sin(a * 127.1 + b * 311.7) * 43758.5453;
    return (v - v.floorToDouble()).abs();
  }

  void _glow(Canvas c, Offset o, double r, Color col) => c.drawCircle(
        o,
        r,
        Paint()..shader = RadialGradient(colors: [col, Colors.transparent]).createShader(Rect.fromCircle(center: o, radius: r)),
      );

  @override
  void paint(Canvas canvas, Size s) {
    final t = clock.value;
    final rect = Offset.zero & s;

    // پایه — مشکی ته‌رنگ سبز ماتریکس
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kSurface, Color(0xFF06180E), kSurface],
        ).createShader(rect),
    );

    // هاله‌ها
    final wob = sin(t * .45);
    _glow(canvas, Offset(s.width * (.12 + .05 * wob), s.height * .10), s.width * .7, accent.withValues(alpha: .20));
    _glow(canvas, Offset(s.width * (.92 - .05 * wob), s.height * .90), s.width * .65, kPurple.withValues(alpha: .18));

    // گرید پرسپکتیو (سبک Synthwave)
    final hz = s.height * .62;
    final cx = s.width / 2;
    final gp = Paint()..strokeWidth = 1;
    gp.color = accent.withValues(alpha: .10);
    for (var i = -8; i <= 8; i++) {
      canvas.drawLine(Offset(cx, hz), Offset(cx + i * s.width * .22, s.height), gp);
    }
    final move = (t * .22) % 1.0;
    for (var k = 0; k < 9; k++) {
      final p = (k + move) / 9;
      final y = hz + (s.height - hz) * p * p;
      gp.color = accent.withValues(alpha: .04 + .14 * p);
      canvas.drawLine(Offset(0, y), Offset(s.width, y), gp);
    }
    canvas.drawLine(
      Offset(0, hz),
      Offset(s.width, hz),
      Paint()
        ..strokeWidth = 1.5
        ..color = accent.withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // بارش دادهٔ دیجیتال — متراکم‌تر و سریع‌تر (حس باران ماتریکس)
    const cell = 12.0;
    final cols = (s.width / 14).floor();
    final bar = Paint();
    for (var c = 0; c < cols; c++) {
      if (_h(c, 1) < .14) continue;
      final speed = .45 + _h(c, 2) * 1.0;
      final len = 8 + (_h(c, 3) * 16).floor();
      final span = s.height / cell + len + 4;
      final head = (t * speed * 5 + _h(c, 4) * span) % span - len;
      final x = c * 14.0 + 3;
      for (var j = 0; j < len; j++) {
        final row = head - j;
        final y = row * cell;
        if (y < -cell || y > s.height) continue;
        final w = 3 + _h(c, row.floor()) * 7;
        if (j == 0) {
          bar.color = accent.withValues(alpha: .22);
          canvas.drawRect(Rect.fromLTWH(x - 2, y - 2, w + 4, 7), bar);
          bar.color = Colors.white.withValues(alpha: .55);
        } else {
          bar.color = accent.withValues(alpha: .30 * (1 - j / len));
        }
        canvas.drawRect(Rect.fromLTWH(x, y, w, 3), bar);
      }
    }

    // پرتو اسکن
    final sy = ((t * .18) % 1.0) * (s.height + 160) - 80;
    final beam = Rect.fromLTWH(0, sy - 50, s.width, 100);
    canvas.drawRect(
      beam,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, accent.withValues(alpha: .07), Colors.transparent],
        ).createShader(beam),
    );

    // گلیچ لحظه‌ای: نوارهای جابه‌جا شده
    final cyc = t / 6.5;
    final ph = cyc - cyc.floorToDouble();
    if (ph > .985) {
      final n = cyc.floor();
      final gy = _h(n, 9) * s.height;
      final off = (_h(n, 8) - .5) * 24;
      canvas.drawRect(Rect.fromLTWH(off, gy, s.width, 6 + _h(n, 7) * 14), Paint()..color = kMagenta.withValues(alpha: .10));
      canvas.drawRect(Rect.fromLTWH(-off, gy + 4, s.width, 3), Paint()..color = kCyan.withValues(alpha: .10));
    }

    // وینیت
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 1.1,
          colors: [Colors.transparent, kSurface.withValues(alpha: .7)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_BgPainter o) => o.accent != accent;
}

// ───────────── وضعیت سراسری افکت‌ها (پوستهٔ اپ آن‌ها را بر اساس اتصال تنظیم می‌کند) ─────────────
/// رنگ لهجهٔ محیط: قرمز=قطع، زرد=در حال اتصال، سبز ماتریکس=امن، قرمز=خطا
final ValueNotifier<Color> zeusAccent = ValueNotifier<Color>(kMagenta);

/// وقتی تونل سالم است بارش سریع‌تر می‌شود
final ValueNotifier<bool> zeusActive = ValueNotifier<bool>(false);

/// فونت تک‌فاصلهٔ داخل اپ (JetBrains Mono در pubspec ثبت شده)
const String kMono = 'JetBrainsMono';

bool isAscii(String s) => s.isNotEmpty && s.codeUnits.every((u) => u < 128);

// ───────────── پنل گوشه‌بریده (Chamfer) ─────────────
Path chamferPath(Size s, double c) {
  final k = min(c, min(s.width, s.height) / 2);
  return Path()
    ..moveTo(k, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height - k)
    ..lineTo(s.width - k, s.height)
    ..lineTo(0, s.height)
    ..lineTo(0, k)
    ..close();
}

class _ChamferClipper extends CustomClipper<Path> {
  final double cut;
  const _ChamferClipper(this.cut);
  @override
  Path getClip(Size s) => chamferPath(s, cut);
  @override
  bool shouldReclip(_ChamferClipper o) => o.cut != cut;
}

class _CyberBorderPainter extends CustomPainter {
  final Color color;
  final double cut;
  final double width;
  final bool glow;
  final bool brackets;
  const _CyberBorderPainter({required this.color, required this.cut, required this.width, required this.glow, required this.brackets});

  @override
  void paint(Canvas canvas, Size s) {
    final path = chamferPath(s, cut);
    if (glow) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 3
          ..color = color.withValues(alpha: .35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
    if (brackets) {
      // براکت‌های HUD روی دو گوشهٔ بدون برش
      final bc = color == kBorder ? kCyan.withValues(alpha: .75) : color.withValues(alpha: .95);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = bc;
      const l = 12.0;
      canvas.drawLine(Offset(s.width - l, 0), Offset(s.width, 0), p);
      canvas.drawLine(Offset(s.width, 0), Offset(s.width, l), p);
      canvas.drawLine(Offset(0, s.height - l), Offset(0, s.height), p);
      canvas.drawLine(Offset(0, s.height), Offset(l, s.height), p);
    }
  }

  @override
  bool shouldRepaint(_CyberBorderPainter o) =>
      o.color != color || o.cut != cut || o.width != width || o.glow != glow || o.brackets != brackets;
}

/// پایهٔ همهٔ المان‌های «پنل‌مانند» برنامه: گوشه‌های بریده، حاشیهٔ نئونی، بلور اختیاری
class CyberBox extends StatelessWidget {
  final Widget child;
  final Color color;
  final Color? fill;
  final double cut;
  final double borderWidth;
  final bool glow;
  final bool blur;
  final bool brackets;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  const CyberBox({
    super.key,
    required this.child,
    this.color = kBorder,
    this.fill,
    this.cut = 12,
    this.borderWidth = 1,
    this.glow = false,
    this.blur = false,
    this.brackets = false,
    this.onTap,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    Widget body = Material(
      color: fill ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: color.withValues(alpha: .15),
        highlightColor: color.withValues(alpha: .08),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (blur) body = BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: body);
    return CustomPaint(
      foregroundPainter: _CyberBorderPainter(color: color, cut: cut, width: borderWidth, glow: glow, brackets: brackets),
      child: ClipPath(clipper: _ChamferClipper(cut), child: body),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? borderColor;
  final bool glow;
  final bool hud; // براکت‌های گوشه برای کارت‌های مهم
  final VoidCallback? onTap;
  final double radius;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.borderColor,
    this.glow = false,
    this.hud = false,
    this.onTap,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: CyberBox(
          color: borderColor ?? kBorder,
          fill: kSurface2.withValues(alpha: .62),
          cut: min(16.0, max(6.0, radius * .8)),
          glow: glow,
          blur: true,
          brackets: hud || glow,
          onTap: onTap,
          padding: padding,
          child: child,
        ),
      );
}

// ───────────────────────── هدر ─────────────────────────
class ZeusHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  const ZeusHeader({super.key, this.title = '', this.leading, this.actions});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) => AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: leading,
        actions: actions,
        title: title.isEmpty ? null : NeonText(title, size: 16),
      );
}

// ───────────────────────── عنوان بخش ─────────────────────────
class SectionLabel extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;
  const SectionLabel(this.text, {super.key, this.icon, this.color = kCyan});

  @override
  Widget build(BuildContext context) {
    final ascii = isAscii(text);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Text('▸', style: TextStyle(color: color, fontSize: 13, shadows: [Shadow(color: color, blurRadius: 8)])),
          const SizedBox(width: 6),
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontFamily: ascii ? kMono : null,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: ascii ? 1.4 : 0,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color.withValues(alpha: .5), Colors.transparent]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── متن نئونی ─────────────────────────
class NeonText extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  final FontWeight weight;
  const NeonText(this.text, {super.key, this.size = 20, this.color = kCyan, this.weight = FontWeight.w900});

  @override
  Widget build(BuildContext context) {
    final ascii = isAscii(text);
    return Text(
      text,
      style: TextStyle(
        fontFamily: ascii ? kMono : null,
        fontSize: size,
        fontWeight: weight,
        // letterSpacing اتصال حروف فارسی را می‌شکند
        letterSpacing: ascii ? 2 : 0,
        color: kText,
        shadows: [
          Shadow(color: color, blurRadius: 10),
          Shadow(color: color.withValues(alpha: .6), blurRadius: 22),
        ],
      ),
    );
  }
}

// ───────────────────────── نقطهٔ ضربان‌دار ─────────────────────────
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot({super.key, required this.color, this.size = 8});
  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          width: widget.size + 8,
          height: widget.size + 8,
          alignment: Alignment.center,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: .3 + .5 * _c.value),
                  blurRadius: 4 + 8 * _c.value,
                  spreadRadius: 1 + 2 * _c.value,
                ),
              ],
            ),
          ),
        ),
      );
}

// ───────────────────────── دکمهٔ نئونی ─────────────────────────
class NeonButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onTap;
  final bool outlined;
  const NeonButton({
    super.key,
    required this.label,
    this.icon,
    this.color = kCyan,
    this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = outlined ? color : Colors.black;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : .45,
      child: CyberBox(
        color: color.withValues(alpha: outlined ? .8 : 1),
        fill: outlined ? color.withValues(alpha: .08) : color,
        cut: 10,
        glow: enabled,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
            ],
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: isAscii(label) ? .6 : 0)),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── بج وضعیت ─────────────────────────
class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final bool pulse;
  const StatusBadge(this.text, {super.key, this.color = kCyan, this.pulse = false});

  @override
  Widget build(BuildContext context) => CyberBox(
        color: color.withValues(alpha: .65),
        fill: color.withValues(alpha: .12),
        cut: 5,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pulse) ...[PulseDot(color: color, size: 5), const SizedBox(width: 2)],
            Text(
              text,
              style: TextStyle(
                color: color,
                fontFamily: isAscii(text) ? kMono : null,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

// ───────────────────────── جعبهٔ آمار ─────────────────────────
class StatBox extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const StatBox({super.key, required this.value, required this.label, this.color = kCyan});

  @override
  Widget build(BuildContext context) => Expanded(
        child: GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontFamily: kMono,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    shadows: [Shadow(color: color.withValues(alpha: .7), blurRadius: 8)],
                  )),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: kMuted, fontSize: 10.5)),
            ],
          ),
        ),
      );
}

// ───────────────────────── تب‌های قرصی ─────────────────────────
class PillTabs extends StatelessWidget {
  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;
  const PillTabs({super.key, required this.items, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: List.generate(items.length, (i) {
            final sel = i == index;
            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: CyberBox(
                color: sel ? kCyan : kBorder,
                fill: sel ? kCyan.withValues(alpha: .16) : kSurface2.withValues(alpha: .6),
                cut: 7,
                glow: sel,
                onTap: () => onChanged(i),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: Text(
                  items[i],
                  style: TextStyle(
                    color: sel ? kCyan : kMuted,
                    fontFamily: isAscii(items[i]) ? kMono : null,
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            );
          }),
        ),
      );
}

// ───────────────────────── جعبهٔ آیکون نئونی ─────────────────────────
class NeonIconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const NeonIconBox(this.icon, {super.key, this.color = kCyan, this.size = 40});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CyberBox(
          color: color.withValues(alpha: .65),
          fill: color.withValues(alpha: .12),
          cut: 8,
          glow: true,
          child: Center(child: Icon(icon, color: color, size: size * .5)),
        ),
      );
}

// ───────────────────────── ردیف لیستی ─────────────────────────
class ZeusTile extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color color;
  const ZeusTile({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.color = kCyan,
  });

  @override
  Widget build(BuildContext context) => GlassCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: onTap,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Row(
            children: [
              leading ?? (icon != null ? NeonIconBox(icon!, color: color, size: 36) : const SizedBox.shrink()),
              if (leading != null || icon != null) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: kMuted, fontSize: 11)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      );
}

// ───────────────────────── قالب‌بندی حجم/سرعت ─────────────────────────
String fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const u = ['KB', 'MB', 'GB', 'TB'];
  double v = bytes / 1024;
  int i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${u[i]}';
}

String fmtRate(int bps) => '${fmtSize(bps)}/s';
String fmtMbps(int bps) => '${(bps * 8 / 1e6).toStringAsFixed(2)} Mbps';
