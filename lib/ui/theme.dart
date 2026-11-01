  // lib/ui/theme.dart — ZEUS Cyberpunk Neon design system
  import 'dart:math';
  import 'dart:ui';

  import 'package:flutter/material.dart';

  // ───────────────────────── پالت ─────────────────────────
  const Color kCyan = Color(0xFF00F0FF);
  const Color kMagenta = Color(0xFFFF2BD6);
  const Color kYellow = Color(0xFFFCEE0A);
  const Color kPurple = Color(0xFF9D4EDD);

  // نام‌های سازگار با فایل‌های دیگر
  const Color kGreen = kCyan;     // accent اصلی
  const Color kBlue = kMagenta;   // accent دوم
  const Color kRed = Color(0xFFFF3860);
  const Color kAmber = kYellow;
  const Color kText = Color(0xFFEAF6FF);
  const Color kMuted = Color(0xFF8C86B0);
  const Color kSurface = Color(0xFF07020F);
  const Color kSurface2 = Color(0xFF130A24);
  const Color kBorder = Color(0x3300F0FF);

  Color pingColor(int ms) {
    if (ms < 0) return kMuted;
    if (ms < 250) return kCyan;
    if (ms < 600) return kYellow;
    return kRed;
  }

  List<BoxShadow> neonGlow(Color c, {double blur = 18, double spread = 0, double alpha = .55}) => [
        BoxShadow(color: c.withValues(alpha: alpha), blurRadius: blur, spreadRadius: spread),
        BoxShadow(color: c.withValues(alpha: alpha * .4), blurRadius: blur * 2.2, spreadRadius: spread),
      ];

  const LinearGradient kNeonGradient = LinearGradient(colors: [kCyan, kMagenta]);

  // ───────────────────────── پس‌زمینهٔ متحرک ─────────────────────────
  class ZeusBackground extends StatefulWidget {
    final Widget child;
    const ZeusBackground({super.key, required this.child});
    @override
    State<ZeusBackground> createState() => _ZeusBackgroundState();
  }

  class _ZeusBackgroundState extends State<ZeusBackground> with SingleTickerProviderStateMixin {
    late final AnimationController _c =
        AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
    late final List<_Particle> _ps = List.generate(26, (i) => _Particle(Random(i * 7 + 3)));

    @override
    void dispose() {
      _c.dispose();
      super.dispose();
    }

    @override
    Widget build(BuildContext context) {
      return Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(painter: _BgPainter(_c.value, _ps)),
            ),
          ),
          widget.child,
        ],
      );
    }
  }

  class _Particle {
    final double x, y0, speed, size;
    final Color color;
    _Particle(Random r)
        : x = r.nextDouble(),
          y0 = r.nextDouble(),
          speed = .25 + r.nextDouble() * .9,
          size = 1 + r.nextDouble() * 2.2,
          color = [kCyan, kMagenta, kYellow, kPurple][r.nextInt(4)];
  }

  class _BgPainter extends CustomPainter {
    final double t;
    final List<_Particle> ps;
    _BgPainter(this.t, this.ps);

    @override
    void paint(Canvas c, Size s) {
      final rect = Offset.zero & s;
      c.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E0420), Color(0xFF07020F), Color(0xFF020008)],
          ).createShader(rect),
      );

      // هاله‌های رنگی شناور
      _blob(c, Offset(s.width * .15 + sin(t * 2 * pi) * 22, s.height * .12), 170, kMagenta, .22);
      _blob(c, Offset(s.width * .88 + cos(t * 2 * pi) * 22, s.height * .32), 210, kCyan, .16);
      _blob(c, Offset(s.width * .5, s.height * 1.0), 300, kPurple, .28);

      // گرید پرسپکتیو در پایین صفحه
      final gridTop = s.height * .60;
      final gridH = s.height - gridTop;
      final cx = s.width / 2;
      final line = Paint()..strokeWidth = 1;
      for (int i = -9; i <= 9; i++) {
        final xTop = cx + i * s.width * .045;
        final xBot = cx + i * s.width * .22;
        line.color = kCyan.withValues(alpha: .10);
        c.drawLine(Offset(xTop, gridTop), Offset(xBot, s.height), line);
      }
      const rows = 14;
      for (int k = 0; k < rows; k++) {
        final f = ((k / rows) + t * 2) % 1.0;
        final y = gridTop + gridH * (f * f);
        line.color = kMagenta.withValues(alpha: .04 + f * .22);
        line.strokeWidth = .6 + f * 1.2;
        c.drawLine(Offset(0, y), Offset(s.width, y), line);
      }
      // محو کردن خط افق
      c.drawRect(
        Rect.fromLTWH(0, gridTop - 40, s.width, 90),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF07020F), const Color(0xFF07020F).withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, gridTop - 40, s.width, 90)),
      );

      // اسکن‌لاین عبوری
      final sy = ((t * 1.7) % 1.0) * s.height;
      c.drawRect(
        Rect.fromLTWH(0, sy - 30, s.width, 60),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kCyan.withValues(alpha: 0), kCyan.withValues(alpha: .07), kCyan.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, sy - 30, s.width, 60)),
      );

      // ذرات
      final dot = Paint();
      for (final p in ps) {
        final y = ((p.y0 - t * p.speed) % 1.0) * s.height;
        final tw = .5 + .5 * sin(t * 2 * pi * 3 + p.x * 10);
        dot
          ..color = p.color.withValues(alpha: .25 + .55 * tw)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size);
        c.drawCircle(Offset(p.x * s.width, y), p.size, dot);
      }

      // خطوط افقی CRT ملایم
      final crt = Path();
      for (double y = 0; y < s.height; y += 4) {
        crt.moveTo(0, y);
        crt.lineTo(s.width, y);
      }
      c.drawPath(crt, Paint()..color = Colors.black.withValues(alpha: .10)..strokeWidth = 1);
    }

    void _blob(Canvas c, Offset o, double r, Color col, double a) {
      c.drawCircle(
        o,
        r,
        Paint()
          ..shader = RadialGradient(colors: [col.withValues(alpha: a), col.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: o, radius: r)),
      );
    }

    @override
    bool shouldRepaint(_BgPainter old) => old.t != t;
  }

  // ───────────────────────── متن نئونی ─────────────────────────
  class NeonText extends StatelessWidget {
    final String text;
    final double size;
    final Color color;
    final FontWeight weight;
    final double letterSpacing;
    const NeonText(this.text,
        {super.key, this.size = 18, this.color = kCyan, this.weight = FontWeight.w900, this.letterSpacing = 2});

    @override
    Widget build(BuildContext context) => Text(
          text,
          style: TextStyle(
            fontSize: size,
            fontWeight: weight,
            letterSpacing: letterSpacing,
            color: kText,
            shadows: [
              Shadow(color: color, blurRadius: 10),
              Shadow(color: color.withValues(alpha: .7), blurRadius: 24),
            ],
          ),
        );
  }

  /// نقطهٔ تپنده (وضعیت)
  class PulseDot extends StatefulWidget {
    final Color color;
    final double size;
    const PulseDot({super.key, this.color = kCyan, this.size = 8});
    @override
    State<PulseDot> createState() => _PulseDotState();
  }

  class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
    late final AnimationController _c =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    @override
    void dispose() {
      _c.dispose();
      super.dispose();
    }

    @override
    Widget build(BuildContext context) => AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final v = _c.value;
            return SizedBox(
              width: widget.size * 3,
              height: widget.size * 3,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: widget.size * (1 + 2 * v),
                    height: widget.size * (1 + 2 * v),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: widget.color.withValues(alpha: (1 - v) * .8), width: 1.2),
                    ),
                  ),
                  Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color,
                      boxShadow: neonGlow(widget.color, blur: 8),
                    ),
                  ),
                ],
              ),
            );
          },
        );
  }

  // ───────────────────────── هدر ─────────────────────────
  class ZeusHeader extends StatelessWidget implements PreferredSizeWidget {
    final String title;
    final Widget? leading;
    final List<Widget>? actions;
    const ZeusHeader({super.key, required this.title, this.leading, this.actions});

    @override
    Size get preferredSize => const Size.fromHeight(64);

    @override
    Widget build(BuildContext context) {
      return SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Stack(
            children: [
              Positioned(
                left: 24,
                right: 24,
                bottom: 0,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      kCyan.withValues(alpha: 0),
                      kCyan.withValues(alpha: .7),
                      kMagenta.withValues(alpha: .7),
                      kMagenta.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
              Row(
                children: [
                  const SizedBox(width: 4),
                  leading ?? const SizedBox(width: 48),
                  Expanded(child: Center(child: NeonText(title, size: 17))),
                  if (actions != null) ...actions! else const SizedBox(width: 48),
                  const SizedBox(width: 4),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }

  // ───────────────────────── کارت شیشه‌ای نئونی ─────────────────────────
  class GlassCard extends StatefulWidget {
    final Widget child;
    final EdgeInsetsGeometry? margin;
    final EdgeInsetsGeometry? padding;
    final Color? borderColor;
    final VoidCallback? onTap;
    final bool glow;
    const GlassCard({
      super.key,
      required this.child,
      this.margin,
      this.padding,
      this.borderColor,
      this.onTap,
      this.glow = false,
    });
    @override
    State<GlassCard> createState() => _GlassCardState();
  }

  class _GlassCardState extends State<GlassCard> {
    bool _down = false;

    @override
    Widget build(BuildContext context) {
      final bc = widget.borderColor ?? kBorder;
      final accent = widget.borderColor ?? kCyan;
      Widget card = AnimatedScale(
        scale: _down ? .975 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          margin: widget.margin ?? const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: widget.glow || _down ? neonGlow(accent, blur: 16, alpha: .35) : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: CustomPaint(
                foregroundPainter: _CornerPainter(accent.withValues(alpha: .9)),
                child: Container(
                  padding: widget.padding ?? const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: bc, width: 1),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: .07),
                        kSurface2.withValues(alpha: .55),
                        kMagenta.withValues(alpha: .05),
                      ],
                    ),
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      );
      if (widget.onTap == null) return card;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: card,
      );
    }
  }

  /// براکت‌های نئونی گوشه‌ها (سبک HUD)
  class _CornerPainter extends CustomPainter {
    final Color color;
    _CornerPainter(this.color);
    @override
    void paint(Canvas c, Size s) {
      const l = 14.0;
      final p = Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      // بالا-چپ و پایین-راست
      c.drawLine(const Offset(10, 0), const Offset(10 + l, 0), p);
      c.drawLine(const Offset(0, 10), const Offset(0, 10 + l), p);
      c.drawLine(Offset(s.width - 10, s.height), Offset(s.width - 10 - l, s.height), p);
      c.drawLine(Offset(s.width, s.height - 10), Offset(s.width, s.height - 10 - l), p);
    }

    @override
    bool shouldRepaint(_CornerPainter old) => old.color != color;
  }

  // ───────────────────────── برچسب بخش ─────────────────────────
  class SectionLabel extends StatelessWidget {
    final String text;
    const SectionLabel(this.text, {super.key});
    @override
    Widget build(BuildContext context) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
          child: Row(
            children: [
              Container(width: 3, height: 14, decoration: BoxDecoration(color: kMagenta, boxShadow: neonGlow(kMagenta, blur: 6))),
              const SizedBox(width: 8),
              Text(text.toUpperCase(),
                  style: const TextStyle(color: kCyan, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 2)),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 1, color: kCyan.withValues(alpha: .15))),
            ],
          ),
        );
  }

  // ───────────────────────── بج وضعیت ─────────────────────────
  class StatusBadge extends StatelessWidget {
    final String text;
    final Color color;
    final bool pulse;
    const StatusBadge(this.text, {super.key, this.color = kCyan, this.pulse = false});
    @override
    Widget build(BuildContext context) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: .6)),
            boxShadow: [BoxShadow(color: color.withValues(alpha: .25), blurRadius: 8)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pulse) ...[PulseDot(color: color, size: 5), const SizedBox(width: 2)],
              Text(text, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .8)),
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
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (w, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(position: Tween(begin: const Offset(0, .4), end: Offset.zero).animate(a), child: w),
                  ),
                  child: Text(
                    value,
                    key: ValueKey(value),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      shadows: [Shadow(color: color.withValues(alpha: .8), blurRadius: 10)],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(color: kMuted, fontSize: 10.5, letterSpacing: .8)),
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: List.generate(items.length, (i) {
              final sel = i == index;
              return GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: sel ? kNeonGradient : null,
                    color: sel ? null : kSurface2.withValues(alpha: .7),
                    border: Border.all(color: sel ? Colors.transparent : kBorder),
                    boxShadow: sel ? neonGlow(kCyan, blur: 12, alpha: .45) : null,
                  ),
                  child: Text(
                    items[i],
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5,
                      color: sel ? Colors.black : kMuted,
                    ),
                  ),
                ),
              );
            }),
          ),
        );
  }

  // ───────────────────────── دکمهٔ نئونی ─────────────────────────
  class NeonButton extends StatefulWidget {
    final String label;
    final IconData? icon;
    final VoidCallback? onTap;
    final Color color;
    final bool outlined;
    const NeonButton({
      super.key,
      required this.label,
      this.icon,
      this.onTap,
      this.color = kCyan,
      this.outlined = false,
    });
    @override
    State<NeonButton> createState() => _NeonButtonState();
  }

  class _NeonButtonState extends State<NeonButton> {
    bool _down = false;
    @override
    Widget build(BuildContext context) {
      final enabled = widget.onTap != null;
      final col = enabled ? widget.color : kMuted;
      return GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          transform: Matrix4.identity()..scale(_down ? .96 : 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: widget.outlined ? col.withValues(alpha: .08) : col,
            border: Border.all(color: col.withValues(alpha: widget.outlined ? .8 : 0)),
            boxShadow: enabled ? neonGlow(col, blur: _down ? 22 : 14, alpha: .5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: widget.outlined ? col : Colors.black),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: widget.outlined ? col : Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
