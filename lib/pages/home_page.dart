  // lib/pages/home_page.dart — خانه + حالت «اتصال فعال»
  import 'dart:math';

  import 'package:flutter/material.dart';

  import '../core/controller.dart';
  import '../core/models.dart';
  import '../ui/theme.dart';

  class HomePage extends StatefulWidget {
    final VoidCallback onGoServers;
    final VoidCallback onGoSettings;
    final VoidCallback onOpenMenu;
    const HomePage({super.key, required this.onGoServers, required this.onGoSettings, required this.onOpenMenu});
    @override
    State<HomePage> createState() => _HomePageState();
  }

  class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
    final c = ZeusController.I;
    late final AnimationController _spin =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

    @override
    void dispose() {
      _spin.dispose();
      super.dispose();
    }

    void _snack(String m, {bool err = false}) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: err ? kRed.withValues(alpha: 0.9) : kSurface2,
      ));
    }

    Future<void> _toggle() async {
      if (!c.connected && !c.connecting && c.selUri == null && !c.warpReady) {
        widget.onGoServers();
        return;
      }
      final err = await c.toggle();
      if (err != null) _snack(err, err: true);
    }

    @override
    Widget build(BuildContext context) {
      return ListenableBuilder(
        listenable: c,
        builder: (_, __) => ZeusBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: ZeusHeader(
              title: c.connected ? 'اتصال فعال' : '',
              leading: IconButton(icon: const Icon(Icons.menu), onPressed: widget.onOpenMenu),
              actions: [IconButton(icon: const Icon(Icons.settings_outlined), onPressed: widget.onGoSettings)],
            ),
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: c.connected ? _connectedView() : _idleView(),
            ),
          ),
        ),
      );
    }

    // ───────────── حالت قطع / در حال اتصال ─────────────
    Widget _idleView() {
      final sel = c.selected;
      final connecting = c.connecting || c.conn == ConnState.disconnecting;
      return ListView(
        key: const ValueKey('idle'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _logo(),
          const SizedBox(height: 14),
          GlassCard(
            child: Row(
              children: [
                NeonIconBox(connecting ? Icons.sync : Icons.shield_outlined, color: connecting ? kAmber : kGreen),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(connecting ? 'در حال اتصال…' : 'اتصال قطع است',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        connecting
                            ? (sel?.displayName ?? 'WARP')
                            : (c.ready ? 'برای اتصال، سرور انتخاب کنید' : 'هستهٔ اتصال آماده نیست'),
                        style: TextStyle(color: c.ready ? kMuted : kRed, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.settings_outlined, color: kGreen.withValues(alpha: 0.6), size: 18),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Center(child: _ring(connecting: connecting, child: Icon(Icons.power_settings_new, size: 64, color: connecting ? kAmber : kGreen))),
          const SizedBox(height: 18),
          Center(
            child: OutlinedButton.icon(
              onPressed: widget.onGoServers,
              icon: const Icon(Icons.public, size: 18),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(sel == null ? 'انتخاب سرور' : '${sel.flag} ${sel.displayName}',
                      style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  const Icon(Icons.keyboard_arrow_down, size: 18, color: kMuted),
                ],
              ),
            ),
          ),
          if (c.warpOn)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(c.warpReady ? '☁ WARP فعال' : '☁ WARP فعال است ولی ثبت نشده',
                    style: TextStyle(color: c.warpReady ? kGreen : kAmber, fontSize: 12)),
              ),
            ),
          const SizedBox(height: 20),
          _trafficCard(),
        ],
      );
    }

    Widget _logo() => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            children: [
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(colors: [kGreen, Color(0xFF8AFFC9)]).createShader(r),
                child: const Text('ZEUS VPN',
                    style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: 2, fontStyle: FontStyle.italic, color: Colors.white)),
              ),
              const SizedBox(height: 4),
              const Text('NO LOGS  •  NO LIMITS  •  YOUR RULES',
                  style: TextStyle(color: kMuted, fontSize: 10, letterSpacing: 2)),
            ],
          ),
        );

    Widget _trafficCard() => GlassCard(
          child: Column(
            children: [
              Row(
                children: [
                  _speedCell(Icons.download_rounded, 'دانلود', fmtRate(c.downSpeed), kGreen),
                  const Spacer(),
                  _speedCell(Icons.upload_rounded, 'آپلود', fmtRate(c.upSpeed), kBlue),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 70,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _SparkPainter(down: c.downHistory, up: c.upHistory),
                ),
              ),
            ],
          ),
        );

    Widget _speedCell(IconData i, String label, String v, Color col) => Row(
          children: [
            Icon(i, color: col, size: 20),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: kMuted, fontSize: 11)),
                Text(v, style: TextStyle(color: col, fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        );

    // ───────────── حالت متصل ─────────────
    Widget _connectedView() {
      final sel = c.selected;
      final proto = sel == null ? 'WARP' : sel.subtitle.replaceAll(' • ', ' · ');
      return ListView(
        key: const ValueKey('connected'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          SizedBox(height: 120, child: CustomPaint(size: Size.infinite, painter: _MapPainter(_spin))),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kGreenDim,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                border: Border.all(color: kGreen.withValues(alpha: 0.4)),
              ),
              child: Text(proto, style: const TextStyle(color: kGreen, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ),
          GlassCard(
            borderColor: kGreen.withValues(alpha: 0.4),
            onTap: widget.onGoServers,
            child: Row(
              children: [
                Text(sel?.flag ?? '☁', style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sel?.displayName ?? 'Cloudflare WARP',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text('Ping: ${sel?.pingText ?? '--'}', style: const TextStyle(color: kMuted, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left, color: kMuted),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: _ring(
              connecting: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.duration, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                  const Text('متصل', style: TextStyle(color: kGreen, fontSize: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(child: _totalCell(Icons.download_rounded, 'دانلود', c.downTotal, c.downSpeed, kGreen)),
              Expanded(child: _totalCell(Icons.upload_rounded, 'آپلود', c.upTotal, c.upSpeed, kBlue)),
            ],
          ),
          const SizedBox(height: 14),
          GlassCard(
            child: Row(
              children: [
                Expanded(child: _kv('IP شما', c.publicIp, Icons.location_on_outlined)),
                Container(width: 1, height: 36, color: kBorder),
                Expanded(child: _kv('موقعیت', sel == null ? 'Cloudflare' : sel.displayName, Icons.flag_outlined)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: c.testingSpeed ? null : c.speedTest,
                  icon: c.testingSpeed
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kGreen))
                      : const Icon(Icons.speed, size: 18),
                  label: Text(c.speedResult.isEmpty ? 'تست سرعت' : c.speedResult),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: kRed,
                side: const BorderSide(color: kRed),
                backgroundColor: kRed.withValues(alpha: 0.08),
              ),
              onPressed: c.busy ? null : () => c.disconnect(),
              icon: const Icon(Icons.power_settings_new, size: 20),
              label: const Text('قطع اتصال', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      );
    }

    Widget _totalCell(IconData i, String label, int total, int rate, Color col) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(i, size: 16, color: col),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              Text(fmtSize(total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(fmtMbps(rate), style: TextStyle(color: col, fontSize: 12)),
            ],
          ),
        );

    Widget _kv(String k, String v, IconData i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Icon(i, size: 12, color: kMuted), const SizedBox(width: 4), Text(k, style: const TextStyle(color: kMuted, fontSize: 11))]),
              const SizedBox(height: 3),
              Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        );

    // ───────────── رینگ ─────────────
    Widget _ring({required bool connecting, required Widget child}) => GestureDetector(
          onTap: c.busy ? null : _toggle,
          child: AnimatedBuilder(
            animation: _spin,
            builder: (_, __) => SizedBox(
              width: 200,
              height: 200,
              child: CustomPaint(
                painter: _RingPainter(
                  t: _spin.value,
                  color: c.connected ? kGreen : (connecting ? kAmber : kGreen),
                  spinning: connecting || c.busy,
                  connected: c.connected,
                ),
                child: Center(child: child),
              ),
            ),
          ),
        );
  }

  // ───────────── Painters ─────────────
  class _RingPainter extends CustomPainter {
    final double t;
    final Color color;
    final bool spinning, connected;
    _RingPainter({required this.t, required this.color, required this.spinning, required this.connected});

    @override
    void paint(Canvas canvas, Size s) {
      final c = s.center(Offset.zero);
      final r = s.width / 2 - 8;
      // glow
      canvas.drawCircle(c, r - 18, Paint()..color = color.withValues(alpha: connected ? 0.10 : 0.05));
      // base rings
      final base = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = color.withValues(alpha: 0.2);
      canvas.drawCircle(c, r, base);
      canvas.drawCircle(c, r - 12, base);
      // ticks
      final tick = Paint()..strokeWidth = 1.2..color = color.withValues(alpha: 0.35);
      for (var i = 0; i < 36; i++) {
        final a = i * pi / 18;
        canvas.drawLine(c + Offset(cos(a), sin(a)) * (r - 2), c + Offset(cos(a), sin(a)) * (r - 6), tick);
      }
      // arc
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      final start = spinning ? t * 2 * pi : -pi / 2;
      final sweep = spinning ? pi * 0.55 : (connected ? 2 * pi : pi * 1.5);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r - 12), start, sweep, false, arc);
      // inner fill
      canvas.drawCircle(c, r - 28, Paint()..color = kSurface);
      canvas.drawCircle(c, r - 28, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = color.withValues(alpha: 0.4));
    }

    @override
    bool shouldRepaint(_RingPainter o) => o.t != t || o.color != color || o.spinning != spinning || o.connected != connected;
  }

  class _SparkPainter extends CustomPainter {
    final List<int> down, up;
    _SparkPainter({required this.down, required this.up});

    @override
    void paint(Canvas canvas, Size s) {
      final grid = Paint()..color = kBorder..strokeWidth = 1;
      for (var i = 1; i < 4; i++) {
        final y = s.height * i / 4;
        canvas.drawLine(Offset(0, y), Offset(s.width, y), grid);
      }
      final maxV = max(1, [...down, ...up].reduce(max));
      void draw(List<int> d, Color col) {
        if (d.length < 2) return;
        final path = Path();
        for (var i = 0; i < d.length; i++) {
          final x = s.width * i / (d.length - 1);
          final y = s.height - (d[i] / maxV) * s.height * 0.9;
          i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        }
        canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = col);
        final fill = Path.from(path)..lineTo(s.width, s.height)..lineTo(0, s.height)..close();
        canvas.drawPath(fill, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [col.withValues(alpha: 0.35), col.withValues(alpha: 0)]).createShader(Offset.zero & s));
      }
      draw(up, kBlue);
      draw(down, kGreen);
    }

    @override
    bool shouldRepaint(_SparkPainter o) => true;
  }

  /// نقشهٔ نقطه‌ای تزئینی با یک مسیر درخشان
  class _MapPainter extends CustomPainter {
    final Animation<double> anim;
    _MapPainter(this.anim) : super(repaint: anim);

    @override
    void paint(Canvas canvas, Size s) {
      final rnd = Random(7);
      final dot = Paint()..color = kGreen.withValues(alpha: 0.18);
      for (var i = 0; i < 260; i++) {
        final x = rnd.nextDouble() * s.width;
        final y = rnd.nextDouble() * s.height;
        // شکل تقریبی قاره‌ها: حذف نقاط در نواحی «اقیانوس»
        final nx = x / s.width, ny = y / s.height;
        if ((nx > 0.28 && nx < 0.45 && ny > 0.1 && ny < 0.5) || (nx > 0.33 && nx < 0.4 && ny > 0.55) || ny > 0.92) continue;
        canvas.drawCircle(Offset(x, y), 1.3, dot);
      }
      final a = Offset(s.width * 0.48, s.height * 0.42);
      final b = Offset(s.width * 0.62, s.height * 0.30);
      final path = Path()..moveTo(a.dx, a.dy)..quadraticBezierTo((a.dx + b.dx) / 2, a.dy - 40, b.dx, b.dy);
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = kGreen.withValues(alpha: 0.6));
      for (final p in [a, b]) {
        canvas.drawCircle(p, 4, Paint()..color = kGreen);
        canvas.drawCircle(p, 4 + 10 * anim.value, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = kGreen.withValues(alpha: 1 - anim.value));
      }
    }

    @override
    bool shouldRepaint(_MapPainter o) => false;
  }
