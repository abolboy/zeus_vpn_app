// lib/pages/home_page.dart — خانه: حالت قطع / در حال اتصال / متصل (با تأیید واقعی تونل)
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/controller.dart';
import '../ui/cyber.dart';
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

  /// لمس دکمهٔ گل: تم رنگیِ بعدی (سبز ← نعنایی ← کهربایی ← قرمز)
  void _nextTheme() {
    HapticFeedback.selectionClick();
    setThemeIdx((zeusThemeIdx.value + 1) % kPalettes.length);
  }

  /// راهنمای رنگ‌های تم (معنی هر رنگ در وضعیت اتصال)
  void _showPalette() {
    Widget row(Color col, String title, String sub) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(color: col, shape: BoxShape.circle, boxShadow: neonGlow(col, blur: 10, alpha: .7)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(sub, style: TextStyle(color: kMuted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface2,
      shape: BeveledRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: kBorder),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('پالت رنگ تم', icon: Icons.palette_outlined),
              row(kGreen, 'رنگ اصلی تم — امن', 'تونل سالم است و ترافیک رمزگذاری می‌شود'),
              row(kAmber, 'زرد — در حال اتصال', 'منتظر برقراری یا بررسی تونل'),
              row(kMagenta, 'قرمز — قطع / خطا', 'محافظت فعال نیست یا اتصال مشکل دارد'),
              row(kBlue, 'رنگ دوم تم — ترافیک', 'آپلود و آمار لحظه‌ای'),
            ],
          ),
        ),
      ),
    );
  }

  /// دکمهٔ بزرگ «اتصال سریع» با آیکون نئونی هم‌رنگ تم
  Widget _quickButton() {
    final off = c.busy || c.pinging;
    final col = off ? kMuted : kGreen;
    return CyberBox(
      color: col.withValues(alpha: .9),
      fill: col.withValues(alpha: .14),
      cut: 9,
      glow: !off,
      onTap: off ? null : _quickConnect,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(c.pinging ? Icons.network_check : Icons.bolt, color: col, size: 26, shadows: [Shadow(color: col, blurRadius: 12)]),
          const SizedBox(width: 6),
          Text(
            c.pinging ? 'در حال سنجش' : 'اتصال سریع',
            style: TextStyle(color: col, fontSize: 13.5, fontWeight: FontWeight.w800, shadows: [Shadow(color: col.withValues(alpha: .6), blurRadius: 8)]),
          ),
        ],
      ),
    );
  }

  /// اتصال سریع: اگر پینگی گرفته نشده «پینگ همه» می‌زند، سریع‌ترین سرور را انتخاب می‌کند و وصل می‌شود
  Future<void> _quickConnect() async {
    // قبل از نمایش اسنک وضعیت را چک کن؛ quickConnect در حالت busy/pinging بی‌صدا null
    // برمی‌گرداند و قبلاً پیام «در حال یافتن سریع‌ترین سرور...» بی‌نتیجه نمایش داده می‌شد
    if (c.busy || c.pinging) return;
    _snack('در حال یافتن سریع‌ترین سرور…');
    final msg = await c.quickConnect();
    if (msg != null) _snack(msg, err: !msg.startsWith('همین'));
  }

  // ───────── وضعیت واقعی (نه فقط CONNECTED پلاگین) ─────────
  bool get _transition => c.connecting || c.conn == ConnState.disconnecting;

  Color get _stateColor {
    if (c.connected) {
      return switch (c.tunnel) {
        TunnelState.ok => kGreen,
        TunnelState.failed => kRed,
        _ => kAmber,
      };
    }
    return _transition ? kAmber : kMagenta;
  }

  String get _stateText {
    if (c.connected) {
      return switch (c.tunnel) {
        TunnelState.ok => 'متصل',
        TunnelState.failed => 'تونل خراب',
        _ => 'تأیید تونل…',
      };
    }
    if (c.conn == ConnState.disconnecting) return 'قطع می‌شود…';
    return c.connecting ? 'در حال اتصال…' : 'قطع';
  }

  String get _title {
    if (!c.connected) return _transition ? 'در حال اتصال' : '';
    return switch (c.tunnel) {
      TunnelState.ok => 'اتصال فعال',
      TunnelState.failed => 'اتصال ناسالم',
      _ => 'بررسی اتصال',
    };
  }

  @override
  Widget build(BuildContext context) {
    // ✅ D1: ورود/خروج ترتیبی (نیمهٔ اول خروج، نیمهٔ دوم ورود) → هیچ overlap بین دو حالت
    const seq = Interval(0.5, 1.0, curve: Curves.easeOutCubic);
    return ListenableBuilder(
      listenable: c,
      builder: (_, __) => ZeusBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: ZeusHeader(
            title: _title,
            leading: IconButton(icon: const Icon(Icons.menu), onPressed: widget.onOpenMenu),
            actions: [
              Center(child: PaletteFlower(onTap: _nextTheme, onLongPress: _showPalette)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: _quickButton(),
              ),
            ],
          ),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 520),
            switchInCurve: seq,
            switchOutCurve: seq,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, .03), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            child: c.connected ? _connectedView() : _idleView(),
          ),
        ),
      ),
    );
  }

  // ───────────── حالت قطع / در حال اتصال ─────────────
  Widget _idleView() {
    final sel = c.selected;
    final col = _stateColor;
    return ListView(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _logo(),
        _idleCommandCenter(),
        _updateBanner(),
        _announce(),
        const SizedBox(height: 14),
        GlassCard(
          hud: true,
          child: Row(
            children: [
              NeonIconBox(_transition ? Icons.sync : Icons.shield_outlined, color: col),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_transition ? _stateText : 'اتصال قطع است',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      _transition
                          ? (sel?.displayName ?? 'WARP')
                          : (c.ready ? 'برای اتصال، سرور انتخاب کنید' : 'هستهٔ اتصال آماده نیست'),
                      style: TextStyle(color: c.ready ? kMuted : kRed, fontSize: 12),
                    ),
                  ],
                ),
              ),
              StatusBadge(_stateText, color: col, pulse: _transition),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: _ring(
            child: Icon(Icons.power_settings_new, size: 64, color: col, shadows: [Shadow(color: col, blurRadius: 18)]),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: NeonButton(
            outlined: true,
            icon: Icons.public,
            label: sel == null ? 'انتخاب سرور' : '${sel.flag} ${sel.displayName}',
            onTap: widget.onGoServers,
          ),
        ),
        if (c.warpOn)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: StatusBadge(
                c.warpReady ? '☁ WARP فعال' : '☁ WARP فعال است ولی ثبت نشده',
                color: c.warpReady ? kGreen : kAmber,
              ),
            ),
          ),
        const SizedBox(height: 20),
        _trafficCard(),
        _credit(),
      ],
    );
  }

  // مرکز فرماندهی در حالت آماده‌به‌کار؛ مقادیر از کنترلر واقعی VPN خوانده می‌شوند.
  // نقشه صرفاً نمایش گرافیکی مسیر/شبکه است و موقعیت جغرافیایی دقیق ادعا نمی‌کند.
  Widget _idleCommandCenter() => GlassCard(
        hud: true,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.public, color: kBlue, size: 17),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    'نمای شبکه ZEUS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                StatusBadge(
                  c.connected ? 'LIVE' : 'STANDBY',
                  color: c.connected ? kGreen : kMuted,
                  pulse: c.connected,
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 94,
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _MapPainter(zeusClock, _stateColor),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(height: 1, color: kBorder),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _kv(
                    'پینگ سرور',
                    c.selected?.pingText ?? '--',
                    Icons.network_ping,
                  ),
                ),
                Expanded(
                  child: _kv(
                    'دانلود',
                    fmtMbps(c.downSpeed),
                    Icons.download_rounded,
                  ),
                ),
                Expanded(
                  child: _kv(
                    'آپلود',
                    fmtMbps(c.upSpeed),
                    Icons.upload_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  /// بنر نسخهٔ جدید (از GitHub Releases)
  bool _updateHidden = false;

  Widget _updateBanner() {
    final u = c.update;
    if (u == null || _updateHidden) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassCard(
        borderColor: kGreen.withValues(alpha: .6),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Icon(Icons.system_update_alt, color: kGreen, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                u.version.isEmpty ? 'نسخهٔ جدید آماده است (بیلد ${u.build})' : 'نسخهٔ ${u.version} آماده است',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            TextButton(
              onPressed: () => launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication),
              child: Text('دانلود', style: TextStyle(color: kGreen, fontWeight: FontWeight.w800)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 18, color: kMuted),
              onPressed: () => setState(() => _updateHidden = true),
            ),
          ],
        ),
      ),
    );
  }

  /// اعلان ارائه‌دهندهٔ اشتراک (از هدر/توضیح اشتراک)؛ با ضربدر بسته می‌شود
  final Set<String> _hiddenAnnounce = {};

  Widget _announce() {
    final items = c.announcements.where((a) => !_hiddenAnnounce.contains(a)).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final text = items.first;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassCard(
        borderColor: kAmber.withValues(alpha: .5),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            const Icon(Icons.campaign_outlined, color: kAmber, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.5))),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 18, color: kMuted),
              onPressed: () => setState(() => _hiddenAnnounce.add(text)),
            ),
          ],
        ),
      ),
    );
  }

  /// امضا: نام بزرگ با «برق» (چند جهش نور در هر چرخه) و دو آیکون رعد
  Widget _credit() => Padding(
        padding: const EdgeInsets.only(top: 30, bottom: 12),
        child: RepaintBoundary(
          child: ValueListenableBuilder<double>(
            valueListenable: zeusClock,
            builder: (_, t, __) {
              final k = pow(max(0.0, sin(t * 2.6)), 6).toDouble();
              final k2 = pow(max(0.0, sin(t * 4.1 + 1.3)), 10).toDouble();
              final f = max(k, k2); // شدت برق 0..1
              final text = Color.lerp(kGreen, Colors.white, f * .65) ?? kGreen;
              final bolt = kGreen.withValues(alpha: .35 + .65 * f);
              Widget b() => Icon(Icons.bolt, color: bolt, size: 30, shadows: [Shadow(color: kGreen, blurRadius: 8 + 22 * f)]);
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  b(),
                  const SizedBox(width: 8),
                  Text(
                    'abolboy',
                    style: TextStyle(
                      color: text,
                      fontFamily: kMono,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 5,
                      shadows: [
                        Shadow(color: kGreen, blurRadius: 10 + 26 * f),
                        Shadow(color: kGreen.withValues(alpha: .7 * f), blurRadius: 34 * f + 1),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  b(),
                ],
              );
            },
          ),
        ),
      );

  Widget _logo() => Padding(
        padding: EdgeInsets.only(top: 6),
        child: Column(
          children: [
            GlitchText('ZEUS VPN', size: 38, fontStyle: FontStyle.italic),
            SizedBox(height: 6),
            Text(
              'NO LOGS  //  NO LIMITS  //  YOUR RULES',
              style: TextStyle(color: kMuted, fontFamily: kMono, fontSize: 10, letterSpacing: 2),
            ),
          ],
        ),
      );

  Widget _trafficCard() => GlassCard(
        hud: true,
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'مانیتور ترافیک',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                StatusBadge(
                  c.connected ? 'LIVE' : 'STANDBY',
                  color: c.connected ? kGreen : kMuted,
                  pulse: c.connected,
                ),
              ],
            ),
            const SizedBox(height: 12),
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
              child: CustomPaint(size: Size.infinite, painter: _SparkPainter(down: c.downHistory, up: c.upHistory)),
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
              Text(label, style: TextStyle(color: kMuted, fontSize: 11)),
              Text(v,
                  style: TextStyle(
                    color: col,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
        ],
      );

  // ───────────── حالت متصل ─────────────
  Widget _connectedView() {
    final sel = c.selected;
    final col = _stateColor;
    final proto = sel == null ? 'WARP' : sel.subtitle.replaceAll(' • ', ' · ');
    final checking = c.tunnel == TunnelState.checking || c.tunnel == TunnelState.idle;
    return ListView(
      key: const ValueKey('connected'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        SizedBox(height: 120, child: CustomPaint(size: Size.infinite, painter: _MapPainter(zeusClock, col))),
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: col.withValues(alpha: .12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border.all(color: col.withValues(alpha: 0.5)),
            ),
            child: Text(proto, style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ),
        GlassCard(
          borderColor: col.withValues(alpha: 0.5),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text('Ping: ${sel?.pingText ?? '--'}', style: TextStyle(color: kMuted, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: kMuted),
            ],
          ),
        ),

        // ✅ A1: وضعیت واقعی تونل
        if (c.tunnel != TunnelState.ok)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: col.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: col.withValues(alpha: .5)),
            ),
            child: Row(
              children: [
                if (checking)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kAmber))
                else
                  const Icon(Icons.warning_amber_rounded, color: kRed, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    checking
                        ? 'سرویس VPN فعال شد؛ در حال بررسی عبور ترافیک از تونل…'
                        : 'ترافیک از تونل عبور نمی‌کند. سرور احتمالاً خاموش یا مسدود است.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (!checking)
                  TextButton(
                    onPressed: c.recheckTunnel,
                    child: const Text('بررسی مجدد', style: TextStyle(color: kAmber, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),

        const SizedBox(height: 10),
        Center(
          child: _ring(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.duration,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                Text(_stateText, style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.w600)),
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
              Expanded(
                child: _kv(
                  'IP شما',
                  c.publicIp,
                  Icons.location_on_outlined,
                  trailing: c.publicIp == '…'
                      ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: kMuted))
                      : InkWell(
                          onTap: c.refreshIp,
                          child: Icon(Icons.refresh, size: 14, color: kMuted),
                        ),
                ),
              ),
              Container(width: 1, height: 36, color: kBorder),
              Expanded(child: _kv('موقعیت', sel == null ? 'Cloudflare' : sel.displayName, Icons.flag_outlined)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _speedPanel(),
        const SizedBox(height: 14),
        Center(
          child: Text(
            'برای قطع اتصال، دایرهٔ بالا را لمس کنید',
            style: TextStyle(color: kMuted, fontSize: 11.5),
          ),
        ),
        _credit(),
      ],
    );
  }

  // ───────── پنل تست سرعت حرفه‌ای (پینگ → دانلود → آپلود + نمودار زنده + نمره) ─────────
  String _mbpsText(double v) => v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  String _speedPhaseText() => switch (c.speedPhase) {
        SpeedPhase.ping => 'اندازه‌گیری پینگ سرور تست…',
        SpeedPhase.download => 'دانلود استریمی… ${_mbpsText(c.speedLiveMbps)} Mbps',
        SpeedPhase.upload => 'آپلود… ${_mbpsText(c.speedLiveMbps)} Mbps',
        SpeedPhase.done => 'تست کامل شد',
        SpeedPhase.failed => 'تست ناموفق بود',
        SpeedPhase.idle =>
            c.tunnel == TunnelState.ok ? 'آمادهٔ اندازه‌گیری دانلود و آپلود' : 'برای تست، اتصال باید سالم باشد',
      };

  Color _gradeColor() {
    final v = c.speedDownMbps;
    if (v >= 10) return kGreen;
    if (v >= 4) return kAmber;
    return kRed;
  }

  Widget _speedPanel() {
    final testing = c.testingSpeed;
    final hasResult = c.speedPhase == SpeedPhase.done;
    final ready = c.tunnel == TunnelState.ok;
    return GlassCard(
      hud: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              NeonIconBox(Icons.speed, color: ready ? kGreen : kMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('تست سرعت', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(_speedPhaseText(), style: TextStyle(color: kMuted, fontSize: 11)),
                  ],
                ),
              ),
              if (hasResult) ...[
                StatusBadge(c.speedGrade, color: _gradeColor()),
                const SizedBox(width: 8),
              ],
              NeonButton(
                label: testing ? 'لغو' : (hasResult ? 'دوباره' : 'شروع'),
                icon: testing ? Icons.close : Icons.play_arrow,
                color: testing ? kRed : kGreen,
                onTap: ready ? (testing ? c.cancelSpeedTest : c.speedTest) : null,
              ),
            ],
          ),
          if (testing) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: c.speedProgress > 0 ? c.speedProgress : null,
                minHeight: 5,
                backgroundColor: kBorder,
                color: kGreen,
              ),
            ),
          ],
          if (c.speedSamples.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: CustomPaint(
                size: Size.infinite,
                painter: _SpeedGraph(samples: c.speedSamples, live: c.speedLiveMbps),
              ),
            ),
          ],
          if (hasResult) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _chipResult('پینگ', c.speedTtfbMs >= 0 ? '${c.speedTtfbMs.round()} ms' : '--', kAmber),
                _chipResult('دانلود', '${_mbpsText(c.speedDownMbps)} Mbps', kGreen),
                if (c.speedUpMbps > 0) _chipResult('آپلود', '${_mbpsText(c.speedUpMbps)} Mbps', kBlue),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              c.speedResult,
              textAlign: TextAlign.center,
              style: TextStyle(color: kText, fontFamily: kMono, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
          if (c.speedError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(c.speedError, textAlign: TextAlign.center, style: const TextStyle(color: kRed, fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _chipResult(String label, String value, Color col) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: col.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: col.withValues(alpha: .35)),
          ),
          child: Column(
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: col, fontFamily: kMono, fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: kMuted, fontSize: 10.5)),
            ],
          ),
        ),
      );

  Widget _totalCell(IconData i, String label, int total, int rate, Color col) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, size: 16, color: col),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: kMuted, fontSize: 12)),
            ]),
            const SizedBox(height: 4),
            Text(fmtSize(total),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
            Text(fmtMbps(rate), style: TextStyle(color: col, fontSize: 12)),
          ],
        ),
      );

  Widget _kv(String k, String v, IconData i, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(i, size: 12, color: kMuted),
              const SizedBox(width: 4),
              Text(k, style: TextStyle(color: kMuted, fontSize: 11)),
              if (trailing != null) ...[const Spacer(), trailing],
            ]),
            const SizedBox(height: 3),
            Text(v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );

  // ───────────── رینگ ─────────────
  Widget _ring({required Widget child}) {
    final spinning = _transition || c.busy || (c.connected && c.tunnel != TunnelState.ok && c.tunnel != TunnelState.failed);
    return GestureDetector(
      onTap: c.busy
          ? null
          : () {
              HapticFeedback.mediumImpact();
              _toggle();
            },
      // RepaintBoundary: رسم رآکتور بقیهٔ صفحه را دوباره رسم نمی‌کند
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: zeusClock,
          builder: (_, __) => SizedBox(
            width: 236,
            height: 236,
            child: CustomPaint(
              painter: ReactorPainter(
                t: (zeusClock.value % 12) / 12,
                color: _stateColor,
                spinning: spinning,
                full: c.connected && c.tunnel == TunnelState.ok,
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────── Painters ─────────────
/// نمودار زندهٔ تست سرعت (نمونه‌های لحظه‌ای Mbps)
class _SpeedGraph extends CustomPainter {
  final List<double> samples;
  final double live;
  _SpeedGraph({required this.samples, required this.live});

  @override
  void paint(Canvas canvas, Size s) {
    if (samples.isEmpty) return;
    final grid = Paint()
      ..color = kBorder
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final y = s.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    final maxV = max(1.0, samples.reduce(max));
    final n = max(1, samples.length - 1);
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = s.width * i / n;
      final y = s.height - (samples[i] / maxV) * s.height * .88;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = kGreen
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    final fill = Path.from(path)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kGreen.withValues(alpha: .3), kGreen.withValues(alpha: 0)],
          ).createShader(Offset.zero & s));
    if (live > 0) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${live >= 100 ? live.toStringAsFixed(0) : live.toStringAsFixed(1)} Mbps',
          style: TextStyle(color: kText, fontSize: 10, fontFamily: kMono),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(s.width - tp.width - 2, 0));
    }
  }

  @override
  bool shouldRepaint(_SpeedGraph o) => true;
}

class _SparkPainter extends CustomPainter {
  final List<int> down, up;
  _SparkPainter({required this.down, required this.up});

  @override
  void paint(Canvas canvas, Size s) {
    final grid = Paint()
      ..color = kBorder
      ..strokeWidth = 1;
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
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = col
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = Colors.white.withValues(alpha: .8));
      final fill = Path.from(path)
        ..lineTo(s.width, s.height)
        ..lineTo(0, s.height)
        ..close();
      canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [col.withValues(alpha: 0.35), col.withValues(alpha: 0)],
            ).createShader(Offset.zero & s));
    }
    draw(up, kBlue);
    draw(down, kGreen);
  }

  @override
  bool shouldRepaint(_SparkPainter o) => true;
}

/// نقشهٔ نقطه‌ای تزئینی با یک مسیر درخشان (رنگ = وضعیت تونل)
class _MapPainter extends CustomPainter {
  final ValueListenable<double> anim;
  final Color color;
  _MapPainter(this.anim, this.color) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size s) {
    final rnd = Random(7);
    final dot = Paint()..color = color.withValues(alpha: 0.18);
    for (var i = 0; i < 260; i++) {
      final x = rnd.nextDouble() * s.width;
      final y = rnd.nextDouble() * s.height;
      final nx = x / s.width, ny = y / s.height;
      if ((nx > 0.28 && nx < 0.45 && ny > 0.1 && ny < 0.5) || (nx > 0.33 && nx < 0.4 && ny > 0.55) || ny > 0.92) {
        continue;
      }
      canvas.drawCircle(Offset(x, y), 1.3, dot);
    }
    final a = Offset(s.width * 0.48, s.height * 0.42);
    final b = Offset(s.width * 0.62, s.height * 0.30);
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo((a.dx + b.dx) / 2, a.dy - 40, b.dx, b.dy);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    for (final p in [a, b]) {
      canvas.drawCircle(p, 4, Paint()..color = color);
      canvas.drawCircle(
          p,
          4 + 10 * ((anim.value / 3) % 1.0),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color.withValues(alpha: 1 - ((anim.value / 3) % 1.0)));
    }
  }

  @override
  bool shouldRepaint(_MapPainter o) => o.color != color;
}
