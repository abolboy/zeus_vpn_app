// lib/pages/settings_page.dart — تنظیمات اپ + PattNG + WARP
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/controller.dart';
import '../ui/theme.dart';
import '../warp.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onGoLogs;
  const SettingsPage({super.key, required this.onBack, required this.onGoLogs});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final c = ZeusController.I;
  bool _dirty = false; // تغییری انجام شده که نیاز به اتصال مجدد دارد
  int _resetGen = 0; // با هر بازنشانی، فیلدهای متنی دوباره ساخته می‌شوند

  static const _fragPackets = ['none', 'tlshello', '1-1', '1-2', '1-3', '1-5', '5-10', '10-20'];
  static const _noiseTypes = ['rand', 'str', 'base64'];
  static const _fps = ['', 'chrome', 'firefox', 'safari', 'ios', 'android', 'edge', 'random', 'randomized'];
  static const _networks = ['tcp', 'ws', 'grpc', 'httpupgrade', 'xhttp'];
  static const _flows = ['', 'xtls-rprx-vision', 'xtls-rprx-vision-udp443'];
  static const _logLevels = ['none', 'error', 'warning', 'info']; // debug عمداً حذف شده (حریم خصوصی)

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: err ? kRed.withValues(alpha: 0.9) : kSurface2,
    ));
  }

  /// ذخیرهٔ تنظیمات هسته + علامت‌گذاری برای اتصال مجدد
  void _patt(VoidCallback change) {
    change();
    c.savePatt();
    if (c.connected || c.connecting) _dirty = true;
    c.refresh();
    setState(() {});
  }

  void _app(VoidCallback change) {
    change();
    c.saveSettings();
    c.refresh();
    setState(() {});
  }

  Future<void> _reconnect() async {
    _dirty = false;
    await c.disconnect();
    final err = await c.connect();
    if (err != null) _snack(err, err: true);
  }

  Future<void> _registerWarp() async {
    final err = await c.warpRegister();
    if (err != null) {
      _snack(err, err: true);
    } else {
      _snack('WARP با موفقیت ثبت شد');
      if (c.connected) setState(() => _dirty = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (_, __) {
        final p = c.patt;
        final s = c.settings;
        return ZeusBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: ZeusHeader(
              title: 'تنظیمات',
              leading: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: widget.onBack),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                if (_dirty && c.connected) _reconnectBanner(),

                // ───────── WARP ─────────
                const SectionLabel('Cloudflare WARP'),
                GlassCard(
                  child: Column(
                    children: [
                      _switch(
                        icon: Icons.cloud_outlined,
                        title: 'WARP روی سرور',
                        subtitle: c.warp?.isValid == true
                            ? 'ثبت‌شده • ${c.warp!.addressV4}'
                            : 'ثبت نشده — اول «ثبت WARP» را بزنید',
                        value: c.warpOn,
                        onChanged: (v) async {
                          await c.setWarpOn(v);
                          if (c.connected) setState(() => _dirty = true);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.how_to_reg_outlined, color: kGreen),
                        title: Text(c.warp?.isValid == true ? 'ثبت مجدد WARP' : 'ثبت WARP'),
                        subtitle: Text(c.connected ? 'از طریق تونل فعلی ثبت می‌شود' : 'به اینترنت آزاد یا اتصال فعال نیاز دارد',
                            style: const TextStyle(fontSize: 11)),
                        trailing: c.busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kGreen))
                            : const Icon(Icons.chevron_left, color: kMuted),
                        onTap: c.busy ? null : _registerWarp,
                      ),
                      if (c.warp?.isValid == true) ...[
                        const Divider(height: 1),
                        _dropdown<String>(
                          icon: Icons.router_outlined,
                          title: 'Endpoint',
                          value: kWarpEndpoints.contains(c.warp!.endpoint) ? c.warp!.endpoint : kWarpEndpoints.first,
                          items: kWarpEndpoints,
                          onChanged: (v) async {
                            await c.setWarpEndpoint(v);
                            if (c.connected) setState(() => _dirty = true);
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                // ───────── Fragment / Noise / Mux ─────────
                const SectionLabel('PattNG — Fragment و Noise'),
                GlassCard(
                  child: Column(
                    children: [
                      _dropdown<String>(
                        icon: Icons.call_split,
                        title: 'Fragment packets',
                        value: _fragPackets.contains(p.frag) ? p.frag : 'none',
                        items: _fragPackets,
                        onChanged: (v) => _patt(() => p.frag = v),
                      ),
                      if (p.frag != 'none') ...[
                        _text('Fragment length', p.fragLen, (v) => _patt(() => p.fragLen = v), hint: '100-200'),
                        _text('Fragment interval (ms)', p.fragInt, (v) => _patt(() => p.fragInt = v), hint: '10-20'),
                      ],
                      const Divider(height: 1),
                      _switch(
                        icon: Icons.graphic_eq,
                        title: 'Noise',
                        subtitle: 'ارسال بسته‌های تصادفی پیش از هندشیک (مناسب UDP/WireGuard)',
                        value: p.noise,
                        onChanged: (v) => _patt(() => p.noise = v),
                      ),
                      if (p.noise) ...[
                        _dropdown<String>(
                          icon: Icons.shuffle,
                          title: 'Noise type',
                          value: _noiseTypes.contains(p.noiseType) ? p.noiseType : 'rand',
                          items: _noiseTypes,
                          onChanged: (v) => _patt(() => p.noiseType = v),
                        ),
                        _text('Noise packet', p.noisePacket, (v) => _patt(() => p.noisePacket = v),
                            hint: p.noiseType == 'rand' ? '10-20 (بازهٔ بایت)' : 'متن یا base64'),
                        _text('Noise delay (ms)', p.noiseDelay, (v) => _patt(() => p.noiseDelay = v), hint: '10-16'),
                      ],
                      const Divider(height: 1),
                      _switch(
                        icon: Icons.layers_outlined,
                        title: 'Mux',
                        subtitle: 'چند اتصال روی یک کانال',
                        value: p.mux,
                        onChanged: (v) => _patt(() => p.mux = v),
                      ),
                      if (p.mux) _text('Mux concurrency', p.muxConc, (v) => _patt(() => p.muxConc = v), hint: '8', number: true),
                    ],
                  ),
                ),

                // ───────── TLS / REALITY ─────────
                const SectionLabel('TLS و REALITY'),
                GlassCard(
                  child: Column(
                    children: [
                      _dropdown<String>(
                        icon: Icons.fingerprint,
                        title: 'uTLS Fingerprint',
                        value: _fps.contains(p.fp) ? p.fp : '',
                        items: _fps,
                        label: (v) => v.isEmpty ? 'پیش‌فرض لینک' : v,
                        onChanged: (v) => _patt(() => p.fp = v),
                      ),
                      _text('SNI (خالی = از لینک)', p.sni, (v) => _patt(() => p.sni = v), hint: 'example.com'),
                      _text('ALPN (با کاما)', p.alpn, (v) => _patt(() => p.alpn = v), hint: 'h2,http/1.1'),
                      const Divider(height: 1),
                      _switch(
                        icon: Icons.verified_user_outlined,
                        title: 'اجبار REALITY',
                        subtitle: 'امنیت لینک به REALITY تغییر می‌کند (برای لینک‌های VLESS)',
                        value: p.reality,
                        onChanged: (v) => _patt(() => p.reality = v),
                      ),
                      if (p.reality) ...[
                        _text('Public key (pbk)', p.pbk, (v) => _patt(() => p.pbk = v)),
                        _text('Short ID (sid)', p.sid, (v) => _patt(() => p.sid = v)),
                        _text('SpiderX (spx)', p.spx, (v) => _patt(() => p.spx = v), hint: '/'),
                        _dropdown<String>(
                          icon: Icons.bolt,
                          title: 'Flow',
                          value: _flows.contains(p.flow) ? p.flow : '',
                          items: _flows,
                          label: (v) => v.isEmpty ? 'بدون flow' : v,
                          onChanged: (v) => _patt(() => p.flow = v),
                        ),
                      ],
                      ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                        title: const Text('پیشرفته', style: TextStyle(fontSize: 14)),
                        iconColor: kMuted,
                        collapsedIconColor: kMuted,
                        children: [
                          _text('Cipher suites', p.cs, (v) => _patt(() => p.cs = v)),
                          _text('Pinned cert SHA256 (با کاما)', p.pcs, (v) => _patt(() => p.pcs = v)),
                          _text('Verify peer cert names (با کاما)', p.vcn, (v) => _patt(() => p.vcn = v)),
                        ],
                      ),
                    ],
                  ),
                ),

                // ───────── Transport ─────────
                const SectionLabel('Transport'),
                GlassCard(
                  child: Column(
                    children: [
                      _switch(
                        icon: Icons.swap_horiz,
                        title: 'بازنویسی Transport لینک',
                        subtitle: 'network / path / host لینک با مقادیر زیر جایگزین می‌شوند',
                        value: p.overrideStream,
                        onChanged: (v) => _patt(() => p.overrideStream = v),
                      ),
                      if (p.overrideStream) ...[
                        _dropdown<String>(
                          icon: Icons.lan_outlined,
                          title: 'Network',
                          value: _networks.contains(p.network) ? p.network : 'tcp',
                          items: _networks,
                          onChanged: (v) => _patt(() => p.network = v),
                        ),
                        _text('Path / serviceName', p.path, (v) => _patt(() => p.path = v), hint: '/'),
                        _text('Host header', p.host, (v) => _patt(() => p.host = v), hint: 'cdn.example.com'),
                        if (p.network == 'tcp')
                          _dropdown<String>(
                            icon: Icons.http,
                            title: 'TCP header',
                            value: p.headerType == 'http' ? 'http' : 'none',
                            items: const ['none', 'http'],
                            onChanged: (v) => _patt(() => p.headerType = v),
                          ),
                      ],
                    ],
                  ),
                ),

                // ───────── DNS / Routing ─────────
                const SectionLabel('DNS و مسیریابی'),
                GlassCard(
                  child: Column(
                    children: [
                      _dropdown<String>(
                        icon: Icons.dns_outlined,
                        title: 'DNS',
                        value: const ['default', 'doh', 'custom'].contains(p.dnsMode) ? p.dnsMode : 'default',
                        items: const ['default', 'doh', 'custom'],
                        label: (v) => {'default': 'پیش‌فرض (1.1.1.1 / 8.8.8.8)', 'doh': 'DNS over HTTPS', 'custom': 'دلخواه'}[v]!,
                        onChanged: (v) => _patt(() => p.dnsMode = v),
                      ),
                      if (p.dnsMode == 'custom')
                        _text('سرورهای DNS (با کاما)', p.customDns, (v) => _patt(() => p.customDns = v), hint: '1.1.1.1,9.9.9.9'),
                      const Divider(height: 1),
                      _switch(
                        icon: Icons.home_outlined,
                        title: 'Bypass LAN',
                        subtitle: 'آدرس‌های محلی از تونل رد نمی‌شوند',
                        value: p.bypassLan,
                        onChanged: (v) => _patt(() => p.bypassLan = v),
                      ),
                      _switch(
                        icon: Icons.flag_outlined,
                        title: 'Bypass Iran',
                        subtitle: 'سایت‌ها و IPهای ایران مستقیم باز می‌شوند',
                        value: p.bypassIran,
                        onChanged: (v) => _patt(() => p.bypassIran = v),
                      ),
                    ],
                  ),
                ),

                // ───────── App ─────────
                const SectionLabel('برنامه'),
                GlassCard(
                  child: Column(
                    children: [
                      _dropdown<int>(
                        icon: Icons.network_check,
                        title: 'روش پینگ',
                        value: s.delayMode == 1 ? 1 : 0,
                        items: const [0, 1],
                        label: (v) => v == 0 ? 'واقعی (از طریق هسته) — دقیق‌تر' : 'TCP — سریع‌تر',
                        onChanged: (v) => _app(() => s.delayMode = v),
                      ),
                      _switch(
                        icon: Icons.receipt_long_outlined,
                        title: 'ذخیرهٔ لاگ',
                        subtitle: 'لاگ‌های اطلاعاتی در صفحهٔ لاگ نگه داشته شوند',
                        value: s.saveLogs,
                        onChanged: (v) => _app(() => s.saveLogs = v),
                      ),
                      _dropdown<String>(
                        icon: Icons.bug_report_outlined,
                        title: 'سطح لاگ هسته',
                        value: _logLevels.contains(p.logLevel) ? p.logLevel : 'warning',
                        items: _logLevels,
                        onChanged: (v) => _patt(() => p.logLevel = v),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.article_outlined, color: kGreen),
                        title: const Text('مشاهدهٔ لاگ‌ها'),
                        subtitle: Text('${c.logs.length} رکورد', style: const TextStyle(fontSize: 11)),
                        trailing: const Icon(Icons.chevron_left, color: kMuted),
                        onTap: widget.onGoLogs,
                      ),
                      ListTile(
                        leading: const Icon(Icons.restart_alt, color: kAmber),
                        title: const Text('بازنشانی تنظیمات هسته'),
                        subtitle: const Text('همهٔ موارد PattNG به پیش‌فرض برمی‌گردند', style: TextStyle(fontSize: 11)),
                        onTap: _confirmReset,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                const Center(
                  child: Text('ZEUS VPN  •  No logs. No limits. Your rules.',
                      style: TextStyle(color: kMuted, fontSize: 11, letterSpacing: 1)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بازنشانی تنظیمات'),
        content: const Text('Fragment، Noise، TLS، Transport و DNS به حالت پیش‌فرض برگردند؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف', style: TextStyle(color: kMuted))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بازنشانی')),
        ],
      ),
    );
    if (ok == true) {
      // قبلاً loadJson(const {}) مقادیر فعلی را نگه می‌داشت و هیچ چیز بازنشانی نمی‌شد
      _patt(() {
        c.patt.resetDefaults();
        _resetGen++;
      });
      _snack('تنظیمات بازنشانی شد');
    }
  }

  // ───────── widgets ─────────
  Widget _reconnectBanner() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kAmber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kAmber.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: kAmber, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text('تغییرات بعد از اتصال مجدد اعمال می‌شوند', style: TextStyle(fontSize: 12))),
            TextButton(
              onPressed: c.busy ? null : _reconnect,
              child: const Text('اتصال مجدد', style: TextStyle(color: kAmber, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  Widget _switch({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      SwitchListTile(
        secondary: Icon(icon, color: value ? kGreen : kMuted),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 11)),
        value: value,
        activeColor: kGreen,
        onChanged: onChanged,
      );

  Widget _dropdown<T>({
    required IconData icon,
    required String title,
    required T value,
    required List<T> items,
    required ValueChanged<T> onChanged,
    String Function(T)? label,
  }) =>
      ListTile(
        leading: Icon(icon, color: kGreen),
        title: Text(title),
        // عرض ثابت برای منو: قبلاً Dropdown تمام عرض را می‌گرفت و عنوان حرف‌به‌حرف می‌شکست («DN S»)
        trailing: SizedBox(
          width: 150,
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: kSurface2,
            style: const TextStyle(color: kText, fontSize: 13),
            items: items
                .map((e) => DropdownMenuItem<T>(
                      value: e,
                      child: Text(label == null ? '$e' : label(e), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );

  Widget _text(String label, String value, ValueChanged<String> onChanged, {String? hint, bool number = false}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: TextFormField(
          key: ValueKey('f_${label}_$_resetGen'),
          initialValue: value,
          textDirection: TextDirection.ltr,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
            labelStyle: const TextStyle(color: kMuted, fontSize: 12),
          ),
          onChanged: onChanged,
        ),
      );
}
