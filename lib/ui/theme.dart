  // lib/ui/theme.dart — پالت Cyberpunk Neon، پس‌زمینهٔ متحرک و ویجت‌های مشترک
  import 'dart:math';
  import 'dart:ui' show ImageFilter;

  import 'package:flutter/material.dart';

  // ───────────────────────── پالت ─────────────────────────
  const Color kCyan = Color(0xFF00F0FF);
  const Color kMagenta = Color(0xFFFF2BD6);
  const Color kGreen = kCyan; // رنگ اصلی/وضعیت سالم (نام قدیمی برای سازگاری صفحات)
  const Color kBlue = Color(0xFF6C8CFF);
  const Color kAmber = Color(0xFFFFB020);
  const Color kRed = Color(0xFFFF3B5C);
  const Color kSurface = Color(0xFF070A12);
  const Color kSurface2 = Color(0xFF0E1322);
  const Color kBorder = Color(0x3300F0FF);
  const Color kText = Color(0xFFE6F7FF);
  const Color kMuted = Color(0xFF7A8BA3);
  const Color kGreenDim = Color(0x2200F0FF);

  const LinearGradient kNeonGradient = LinearGradient(
    colors: [kCyan, kMagenta],
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
    if (ms < 200) return kGreen;
    if (ms < 500) return kAmber;
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
    late final AnimationController _ctl =
        AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();

    @override
    void dispose() {
      _ctl.dispose();
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
            child: AnimatedBuilder(
              animation: _ctl,
              builder: (_, __) => CustomPaint(painter: _BgPainter(_ctl.value)),
            ),
          ),
          widget.child,
        ],
      );
    }
  }

  class _BgPainter extends CustomPainter {
    final double t;
    _BgPainter(this.t);

    static final List<Offset> _seeds = List.generate(42, (i) {
      final r = Random(i * 97 + 13);
      return Offset(r.nextDouble(), r.nextDouble());
    });

    @override
    void paint(Canvas canvas, Size s) {
      // هاله‌های رنگی
      final wob = sin(t * 2 * pi);
      canvas.drawCircle(
        Offset(s.width * (0.15 + 0.05 * wob), s.height * 0.12),
        s.width * 0.6,
        Paint()
          ..shader = RadialGradient(colors: [kCyan.withValues(alpha: .16), Colors.transparent])
              .createShader(Rect.fromCircle(center: Offset(s.width * 0.15, s.height * 0.12), radius: s.width * 0.6)),
      );
      canvas.drawCircle(
        Offset(s.width * (0.9 - 0.05 * wob), s.height * 0.88),
        s.width * 0.55,
        Paint()
          ..shader = RadialGradient(colors: [kMagenta.withValues(alpha: .13), Colors.transparent])
              .createShader(Rect.fromCircle(center: Offset(s.width * 0.9, s.height * 0.88), radius: s.width * 0.55)),
      );

      // گرید
      final grid = Paint()
        ..color = kCyan.withValues(alpha: .06)
        ..strokeWidth = 1;
      const step = 36.0;
      final dy = (t * step * 2) % step;
      for (double y = -step + dy; y < s.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(s.width, y), grid);
      }
      for (double x = 0; x < s.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, s.height), grid);
      }

      // ذرات
      for (var i = 0; i < _seeds.length; i++) {
        final sd = _seeds[i];
        final speed = 0.25 + (i % 5) * 0.12;
        final y = ((sd.dy - t * speed) % 1.0 + 1.0) % 1.0;
        final x = sd.dx + 0.01 * sin((t + sd.dx) * 2 * pi * 2);
        final col = i.isEven ? kCyan : kMagenta;
        final a = .25 + .35 * (0.5 + 0.5 * sin((t * 3 + i) * 2 * pi));
        canvas.drawCircle(Offset(x * s.width, y * s.height), 1.2 + (i % 3) * .6,
            Paint()..color = col.withValues(alpha: a));
      }

      // اسکن‌لاین
      final sy = (t * 1.7 % 1.0) * s.height;
      canvas.drawRect(
        Rect.fromLTWH(0, sy - 40, s.width, 80),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, kCyan.withValues(alpha: .05), Colors.transparent],
          ).createShader(Rect.fromLTWH(0, sy - 40, s.width, 80)),
      );

      // وینیت
      canvas.drawRect(
        Offset.zero & s,
        Paint()
          ..shader = RadialGradient(
            radius: 1.1,
            colors: [Colors.transparent, kSurface.withValues(alpha: .7)],
          ).createShader(Offset.zero & s),
      );
    }

    @override
    bool shouldRepaint(_BgPainter o) => o.t != t;
  }

  // ───────────────────────── کارت شیشه‌ای ─────────────────────────
  class GlassCard extends StatelessWidget {
    final Widget child;
    final EdgeInsetsGeometry padding;
    final EdgeInsetsGeometry margin;
    final Color? borderColor;
    final bool glow;
    final VoidCallback? onTap;
    final double radius;
    const GlassCard({
      super.key,
      required this.child,
      this.padding = const EdgeInsets.all(14),
      this.margin = EdgeInsets.zero,
      this.borderColor,
      this.glow = false,
      this.onTap,
      this.radius = 16,
    });

    @override
    Widget build(BuildContext context) {
      final bc = borderColor ?? kBorder;
      return Padding(
        padding: margin,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: glow ? neonGlow(bc, blur: 18, alpha: .35) : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Material(
                color: kSurface2.withValues(alpha: .62),
                child: InkWell(
                  onTap: onTap,
                  splashColor: kCyan.withValues(alpha: .12),
                  highlightColor: kCyan.withValues(alpha: .06),
                  child: Container(
                    padding: padding,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: bc),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
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

  // ───────────────────────── متن نئونی ─────────────────────────
  class NeonText extends StatelessWidget {
    final String text;
    final double size;
    final Color color;
    final FontWeight weight;
    const NeonText(this.text, {super.key, this.size = 20, this.color = kCyan, this.weight = FontWeight.w900});

    @override
    Widget build(BuildContext context) => Text(
          text,
          style: TextStyle(
            fontSize: size,
            fontWeight: weight,
            letterSpacing: 1.5,
            color: kText,
            shadows: [
              Shadow(color: color, blurRadius: 10),
              Shadow(color: color.withValues(alpha: .6), blurRadius: 22),
            ],
          ),
        );
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
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: outlined ? color.withValues(alpha: .08) : color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: outlined ? .7 : 1)),
                boxShadow: enabled ? neonGlow(color, blur: 14, alpha: outlined ? .2 : .45) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 8),
                  ],
                  Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: .4)),
                ],
              ),
            ),
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
    Widget build(BuildContext context) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: .6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pulse) ...[PulseDot(color: color, size: 5), const SizedBox(width: 2)],
              Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
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
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => onChanged(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? kCyan.withValues(alpha: .16) : kSurface2.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: sel ? kCyan : kBorder),
                        boxShadow: sel ? neonGlow(kCyan, blur: 10, alpha: .3) : null,
                      ),
                      child: Text(items[i],
                          style: TextStyle(
                            color: sel ? kCyan : kMuted,
                            fontSize: 12,
                            fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                          )),
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
    Widget build(BuildContext context) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: .6)),
            boxShadow: neonGlow(color, blur: 10, alpha: .35),
          ),
          child: Icon(icon, color: color, size: size * .5),
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
