import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'neon.dart';

void main() => runApp(const ZeusApp());

class ZeusApp extends StatelessWidget {
  const ZeusApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZEUS VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: const Color(0xFF030308)),
      home: const HomePage(),
    );
  }
}

class ServerNode {
  final String subTag;
  final String rawUri;
  final String displayName;
  String pingText;
  Color pingColor;
  ServerNode({required this.subTag, required this.rawUri, required this.displayName, this.pingText = '--', this.pingColor = Colors.grey});
}

class Patt {
  String fingerprint = 'unsafe';
  String cipherSuites = '';
  bool allowInsecure = false;
  String fragment = 'tlshello';
  String fragLength = '100-200';
  String fragInterval = '10-20';
  bool noise = false;
  String noiseType = 'rand';
  String noisePacket = '10-20';
  String noiseDelay = '10-20';
  bool mux = false;
  String muxConc = '8';
  bool bypassLan = false;
  String logLevel = 'warning';
  String dnsMode = 'auto';
  String customDns = '1.1.1.1';
  bool reality = false;
  String pbk = '';
  String sid = '';
  String spx = '/';
  String flow = 'xtls-rprx-vision';
  String alpn = 'h2,http/1.1';
  String sni = '';
  String path = '/';
  String host = '';
  String headerType = 'none';
  String network = 'tcp';
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 20)));

  List<String> _subUrls = [];
  List<ServerNode> _nodes = [];
  String? _selectedUri;
  Patt _patt = Patt();

  bool _ready = false;
  bool _loading = false;
  bool _connected = false;
  bool _testing = false;
  String _speed = '';
  String _up = '0 B/s';
  String _down = '0 B/s';
  String _dur = '00:00:00';

  VoidCallback? _refreshNodesUi;

  late V2ray _v2ray;
  late AnimationController _timeCtl;
  late AnimationController _pulseCtl;
  late AnimationController _ringCtl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _timeCtl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
    _pulseCtl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _ringCtl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04).animate(CurvedAnimation(parent: _pulseCtl, curve: Curves.easeInOut));

    _v2ray = V2ray(onStatusChanged: (status) {
      final dynamic s = status;
      String state = 'DISCONNECTED';
      int up = 0, down = 0;
      String dur = '00:00:00';
      try { state = (s.state ?? 'DISCONNECTED').toString(); } catch (_) {}
      try { up = (s.uploadSpeed ?? 0) as int; } catch (_) {}
      try { down = (s.downloadSpeed ?? 0) as int; } catch (_) {}
      try { dur = (s.duration ?? '00:00:00').toString(); } catch (_) {}
      if (mounted) {
        setState(() {
          _connected = state == 'CONNECTED';
          _up = _fmtSpeed(up);
          _down = _fmtSpeed(down);
          _dur = _connected ? dur : '00:00:00';
          if (!_connected) _speed = '';
        });
      }
    });

    _boot();
  }

  Future<void> _boot() async {
    await _v2ray.initialize(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    );
    final prefs = await SharedPreferences.getInstance();
    _subUrls = prefs.getStringList('subs') ?? [];
    _selectedUri = prefs.getString('sel');
    _loadPatt(prefs);
    setState(() => _ready = true);
    if (_subUrls.isNotEmpty) _syncAll();
  }

  void _loadPatt(SharedPreferences p) {
    _patt.fingerprint = p.getString('p_fp') ?? 'unsafe';
    _patt.cipherSuites = p.getString('p_cs') ?? '';
    _patt.allowInsecure = p.getBool('p_ins') ?? false;
    _patt.fragment = p.getString('p_frag') ?? 'tlshello';
    _patt.fragLength = p.getString('p_fl') ?? '100-200';
    _patt.fragInterval = p.getString('p_fi') ?? '10-20';
    _patt.noise = p.getBool('p_noise') ?? false;
    _patt.noiseType = p.getString('p_nt') ?? 'rand';
    _patt.noisePacket = p.getString('p_np') ?? '10-20';
    _patt.noiseDelay = p.getString('p_nd') ?? '10-20';
    _patt.mux = p.getBool('p_mux') ?? false;
    _patt.muxConc = p.getString('p_mc') ?? '8';
    _patt.bypassLan = p.getBool('p_lan') ?? false;
    _patt.logLevel = p.getString('p_log') ?? 'warning';
    _patt.dnsMode = p.getString('p_dns') ?? 'auto';
    _patt.customDns = p.getString('p_dnsc') ?? '1.1.1.1';
    _patt.reality = p.getBool('p_real') ?? false;
    _patt.pbk = p.getString('p_pbk') ?? '';
    _patt.sid = p.getString('p_sid') ?? '';
    _patt.spx = p.getString('p_spx') ?? '/';
    _patt.flow = p.getString('p_flow') ?? 'xtls-rprx-vision';
    _patt.alpn = p.getString('p_alpn') ?? 'h2,http/1.1';
    _patt.sni = p.getString('p_sni') ?? '';
    _patt.path = p.getString('p_path') ?? '/';
    _patt.host = p.getString('p_host') ?? '';
    _patt.headerType = p.getString('p_ht') ?? 'none';
    _patt.network = p.getString('p_net') ?? 'tcp';
  }

  Future<void> _savePatt() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('p_fp', _patt.fingerprint);
    await p.setString('p_cs', _patt.cipherSuites);
    await p.setBool('p_ins', _patt.allowInsecure);
    await p.setString('p_frag', _patt.fragment);
    await p.setString('p_fl', _patt.fragLength);
    await p.setString('p_fi', _patt.fragInterval);
    await p.setBool('p_noise', _patt.noise);
    await p.setString('p_nt', _patt.noiseType);
    await p.setString('p_np', _patt.noisePacket);
    await p.setString('p_nd', _patt.noiseDelay);
    await p.setBool('p_mux', _patt.mux);
    await p.setString('p_mc', _patt.muxConc);
    await p.setBool('p_lan', _patt.bypassLan);
    await p.setString('p_log', _patt.logLevel);
    await p.setString('p_dns', _patt.dnsMode);
    await p.setString('p_dnsc', _patt.customDns);
    await p.setBool('p_real', _patt.reality);
    await p.setString('p_pbk', _patt.pbk);
    await p.setString('p_sid', _patt.sid);
    await p.setString('p_spx', _patt.spx);
    await p.setString('p_flow', _patt.flow);
    await p.setString('p_alpn', _patt.alpn);
    await p.setString('p_sni', _patt.sni);
    await p.setString('p_path', _patt.path);
    await p.setString('p_host', _patt.host);
    await p.setString('p_ht', _patt.headerType);
    await p.setString('p_net', _patt.network);
  }

  String _fmtSpeed(int bps) {
    if (bps < 1024) return '$bps B/s';
    if (bps < 1048576) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / 1048576).toStringAsFixed(1)} MB/s';
  }

  int _pingMs(ServerNode n) => int.tryParse(n.pingText.replaceAll(' ms', '').trim()) ?? 999999;

  String _name(String uri) {
    try {
      final u = Uri.parse(uri);
      if (u.fragment.isNotEmpty) return Uri.decodeComponent(u.fragment);
      return '${u.host}:${u.port}';
    } catch (_) { return 'Node'; }
  }

  String _injectQuery(String uri) {
    try {
      final u = Uri.parse(uri);
      final q = Map<String, String>.from(u.queryParameters);
      q['fp'] = _patt.fingerprint;
      if (_patt.cipherSuites.isNotEmpty) q['cs'] = _patt.cipherSuites;
      if (_patt.allowInsecure) q['allowInsecure'] = '1';
      if (_patt.reality) {
        q['security'] = 'reality';
        q['pbk'] = _patt.pbk;
        q['sid'] = _patt.sid;
        q['spx'] = _patt.spx;
      }
      if (u.scheme == 'vless' && _patt.network == 'tcp' && _patt.flow.isNotEmpty && _patt.flow != 'none') {
        q['flow'] = _patt.flow;
      } else {
        q.remove('flow');
      }
      if (_patt.alpn.isNotEmpty) q['alpn'] = _patt.alpn;
      if (_patt.sni.isNotEmpty) q['sni'] = _patt.sni;
      if (_patt.path.isNotEmpty && _patt.path != '/') q['path'] = _patt.path;
      if (_patt.host.isNotEmpty) q['host'] = _patt.host;
      if (_patt.headerType != 'none') q['headerType'] = _patt.headerType;
      if (_patt.network.isNotEmpty && _patt.network != 'tcp') q['type'] = _patt.network;
      return u.replace(queryParameters: q).toString();
    } catch (_) { return uri; }
  }

  String _injectCore(String config) {
    try {
      final json = jsonDecode(config) as Map<String, dynamic>;
      final outs = json['outbounds'] as List?;
      if (outs == null || outs.isEmpty) return config;
      final main = outs[0] as Map<String, dynamic>;
      json['log'] = {'loglevel': _patt.logLevel};
      if (_patt.dnsMode == 'doh') {
        json['dns'] = {'servers': ['https+local://1.1.1.1/dns-query', 'https+local://8.8.8.8/dns-query']};
      } else if (_patt.dnsMode == 'custom' && _patt.customDns.isNotEmpty) {
        json['dns'] = {'servers': _patt.customDns.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()};
      }
      if (_patt.mux) main['mux'] = {'enabled': true, 'concurrency': int.tryParse(_patt.muxConc) ?? 8};
      if (_patt.fragment != 'none' || _patt.noise) {
        final fs = <String, dynamic>{};
        if (_patt.fragment != 'none') {
          fs['fragment'] = {'packets': _patt.fragment.startsWith('tlshello') ? 'tlshello' : _patt.fragment, 'length': _patt.fragLength, 'interval': _patt.fragInterval};
        }
        if (_patt.noise) fs['noise'] = {'type': _patt.noiseType, 'packet': _patt.noisePacket, 'delay': _patt.noiseDelay};
        final stream = (main['streamSettings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        final sock = (stream['sockopt'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        sock['dialerProxy'] = 'zeus-frag';
        stream['sockopt'] = sock;
        main['streamSettings'] = stream;
        outs.add({'tag': 'zeus-frag', 'protocol': 'freedom', 'settings': fs});
      }
      if (_patt.bypassLan) {
        outs.add({'tag': 'direct', 'protocol': 'freedom'});
        json['routing'] = {'domainStrategy': 'AsIs', 'rules': [{'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'direct'}]};
      }
      json['outbounds'] = outs;
      return jsonEncode(json);
    } catch (_) { return config; }
  }

  Future<void> _syncAll() async {
    if (_subUrls.isEmpty) return;
    final prev = _selectedUri;
    setState(() { _loading = true; _nodes = []; });
    final List<ServerNode> got = [];
    for (int i = 0; i < _subUrls.length; i++) {
      final tag = 'SUB-${i + 1}';
      try {
        final res = await _dio.get(_subUrls[i], options: Options(headers: {'User-Agent': 'v2rayNG/1.8.5'}));
        String body = res.data.toString().trim();
        try { body = utf8.decode(base64.decode(base64.normalize(body))); } catch (_) {}
        for (final raw in body.split('\n').map((e) => e.trim())) {
          if (raw.startsWith('vless://') || raw.startsWith('trojan://') || raw.startsWith('vmess://')) {
            final link = raw.startsWith('vmess://') ? raw : _injectQuery(raw);
            got.add(ServerNode(subTag: tag, rawUri: link, displayName: '[$tag] ${_name(link)}'));
          }
        }
      } catch (_) {}
    }
    setState(() {
      _nodes = got;
      if (prev != null && _nodes.any((n) => n.rawUri == prev)) { _selectedUri = prev; }
      else if (_nodes.isNotEmpty) { _selectedUri = _nodes.first.rawUri; }
      else { _selectedUri = null; }
    });
    _refreshNodesUi?.call();
    _pingAll();
    setState(() => _loading = false);
    _refreshNodesUi?.call();
  }

  Future<void> _pingAll() async {
    final q = List<ServerNode>.from(_nodes);
    await Future.wait(List.generate(20, (_) async {
      while (q.isNotEmpty) {
        final n = q.removeAt(0);
        await _pingOne(n);
      }
    }));
  }

  Future<void> _pingOne(ServerNode n) async {
    try {
      final u = Uri.parse(n.rawUri);
      if (u.port == 0) throw Exception('no port');
      final sw = Stopwatch()..start();
      final s = await Socket.connect(u.host, u.port, timeout: const Duration(seconds: 3));
      sw.stop();
      s.destroy();
      if (mounted) {
        setState(() {
          final p = sw.elapsedMilliseconds;
          n.pingText = '$p ms';
          n.pingColor = p < 200 ? neonGreen : (p < 500 ? neonAmber : neonMagenta);
        });
        _refreshNodesUi?.call();
      }
    } catch (_) {
      if (mounted) {
        setState(() { n.pingText = 'TIMEOUT'; n.pingColor = neonMagenta; });
        _refreshNodesUi?.call();
      }
    }
  }

  Future<void> _speedTest() async {
    setState(() { _testing = true; _speed = '...'; });
    try {
      final sw = Stopwatch()..start();
      final res = await _dio.get('https://speed.cloudflare.com/__down?bytes=10000000', options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 30)));
      sw.stop();
      double sec = sw.elapsedMilliseconds / 1000.0;
      if (sec == 0) sec = 0.1;
      final mbps = (res.data.length.toDouble() * 8) / (sec * 1048576);
      setState(() => _speed = '${mbps.toStringAsFixed(1)} Mbps');
    } catch (_) { setState(() => _speed = 'FAILED'); }
    setState(() => _testing = false);
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_connected) { await _v2ray.stopV2Ray(); return; }
    if (_selectedUri == null) { _snack('First select a node.', err: true); return; }
    final ok = await _v2ray.requestPermission();
    if (!ok) { _snack('VPN permission denied.', err: true); return; }
    final parser = V2ray.parseFromURL(_selectedUri!);
    final config = _injectCore(parser.getFullConfiguration());
    await _v2ray.startV2Ray(remark: parser.remark, config: config, proxyOnly: false);
  }

  void _snack(String m, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(color: Colors.white)), backgroundColor: err ? neonMagenta : neonGreen, behavior: SnackBarBehavior.floating));
  }

  @override
  void dispose() {
    _timeCtl.dispose();
    _pulseCtl.dispose();
    _ringCtl.dispose();
    super.dispose();
  }

  Widget _neonBox({required Widget child, Color color = neonCyan, double radius = 14, EdgeInsets padding = const EdgeInsets.all(14)}) {
    return AnimatedBuilder(
      animation: _ringCtl,
      builder: (context, _) {
        final t = _ringCtl.value * 2 * pi;
        return Container(
          padding: padding,
          decoration: BoxDecoration(
            color: glass.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: color.withValues(alpha: 0.35 + 0.25 * sin(t))),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.12 + 0.08 * sin(t)), blurRadius: 18)],
          ),
          child: child,
        );
      },
    );
  }

  Widget _dd(String label, List<String> items, String cur, Function(String) on) {
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.bold)),
      DropdownButtonFormField<String>(value: items.contains(cur) ? cur : items.first, dropdownColor: glass, style: const TextStyle(color: Colors.white, fontSize: 13), decoration: InputDecoration(filled: true, fillColor: Colors.white.withValues(alpha: 0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))), items: items.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { if (v != null) on(v); }),
    ]));
  }

  Widget _tf(String label, String cur, Function(String) on) {
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: TextFormField(initialValue: cur, style: const TextStyle(color: Colors.white, fontSize: 13), decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10), filled: true, fillColor: Colors.white.withValues(alpha: 0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))), onChanged: on));
  }

  Widget _sw(String label, bool val, Function(bool) on) {
    return SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)), value: val, onChanged: on);
  }

  void _openNodes() {
    String q = '';
    String tag = 'ALL';
    int sort = 0;
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setMs) {
        _refreshNodesUi = () => setMs(() {});
        var vis = _nodes.where((n) => (tag == 'ALL' || n.subTag == tag) && (q.isEmpty || n.displayName.toLowerCase().contains(q.toLowerCase()))).toList();
        if (sort == 1) vis.sort((a, b) => _pingMs(a).compareTo(_pingMs(b)));
        if (sort == 2) vis.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
        final tags = ['ALL', ..._nodes.map((e) => e.subTag).toSet()];
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.9,
          decoration: BoxDecoration(color: glass, borderRadius: const BorderRadius.vertical(top: Radius.circular(22)), border: Border(top: BorderSide(color: neonCyan.withValues(alpha: 0.6), width: 2))),
          child: Column(children: [
            const SizedBox(height: 12),
            Container(width: 54, height: 4, decoration: BoxDecoration(color: neonCyan.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(children: [
              const Icon(Icons.dns, color: neonCyan, size: 18), const SizedBox(width: 8),
              const Text('NODE CENTER', style: TextStyle(color: neonCyan, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 3)),
              const SizedBox(width: 8), Text('${vis.length}/${_nodes.length}', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.sort, color: neonAmber, size: 20), onPressed: () => setMs(() => sort = (sort + 1) % 3)),
              IconButton(icon: const Icon(Icons.network_ping, color: neonGreen, size: 20), onPressed: _pingAll),
              IconButton(icon: const Icon(Icons.refresh, color: neonCyan, size: 20), onPressed: _syncAll),
            ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(style: const TextStyle(color: Colors.white, fontSize: 13), onChanged: (v) => setMs(() => q = v), decoration: InputDecoration(hintText: 'SEARCH NODE...', hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12), prefixIcon: const Icon(Icons.search, color: neonCyan, size: 18), filled: true, fillColor: Colors.white.withValues(alpha: 0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))))),
            const SizedBox(height: 10),
            SizedBox(height: 34, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: tags.map((t) {
              final on = tag == t;
              return Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(onTap: () => setMs(() => tag = t), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), decoration: BoxDecoration(color: on ? neonCyan.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(20), border: Border.all(color: on ? neonCyan : Colors.white.withValues(alpha: 0.1))), child: Text(t, style: TextStyle(color: on ? neonCyan : Colors.white.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.bold)))));
            }).toList())),
            Expanded(child: vis.isEmpty ? Center(child: Text('NO NODES', style: TextStyle(color: Colors.white.withValues(alpha: 0.3)))) : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), itemCount: vis.length, itemBuilder: (ctx, i) {
              final n = vis[i];
              final sel = n.rawUri == _selectedUri;
              return GestureDetector(onTap: () { setState(() => _selectedUri = n.rawUri); SharedPreferences.getInstance().then((p) => p.setString('sel', n.rawUri)); setMs(() {}); Navigator.pop(ctx); },
                child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: sel ? neonCyan.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(12), border: Border.all(color: sel ? neonCyan : Colors.white.withValues(alpha: 0.06))),
                  child: Row(children: [
                    Icon(n.rawUri.startsWith('vless://') ? Icons.bolt_rounded : (n.rawUri.startsWith('trojan://') ? Icons.shield_rounded : Icons.memory_rounded), color: n.rawUri.startsWith('vless://') ? neonCyan : (n.rawUri.startsWith('trojan://') ? neonMagenta : neonAmber), size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.displayName, style: TextStyle(color: sel ? Colors.white : Colors.white70, fontSize: 13, fontWeight: sel ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(n.subTag, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 9, fontWeight: FontWeight.bold)),
                    ])),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: n.pingColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: n.pingColor.withValues(alpha: 0.5))), child: Text(n.pingText, style: TextStyle(color: n.pingColor, fontSize: 10, fontWeight: FontWeight.bold))),
                    if (sel) ...[const SizedBox(width: 8), const Icon(Icons.check_circle, color: neonGreen, size: 18)],
                  ])));
            })),
          ]),
        );
      }),
    ).then((_) { _refreshNodesUi = null; if (mounted) setState(() {}); });
  }

  void _openSubs() {
    final ctl = TextEditingController();
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setMs) {
      return Container(height: MediaQuery.of(ctx).size.height * 0.65, decoration: BoxDecoration(color: glass, borderRadius: const BorderRadius.vertical(top: Radius.circular(22)), border: Border(top: BorderSide(color: neonMagenta.withValues(alpha: 0.6), width: 2))),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 54, height: 4, decoration: BoxDecoration(color: neonMagenta.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8))),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('SUBSCRIPTIONS', style: TextStyle(color: neonMagenta, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 3))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
            Expanded(child: TextField(controller: ctl, style: const TextStyle(color: Colors.white, fontSize: 12), decoration: InputDecoration(hintText: 'https://...', hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 11), filled: true, fillColor: Colors.white.withValues(alpha: 0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))))),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.add_circle, color: neonGreen, size: 26), onPressed: () {
              final v = ctl.text.trim();
              if (!v.startsWith('http')) { _snack('Invalid URL!', err: true); return; }
              if (_subUrls.contains(v)) { _snack('Duplicate sub!', err: true); return; }
              setState(() => _subUrls.add(v));
              SharedPreferences.getInstance().then((p) => p.setStringList('subs', _subUrls));
              ctl.clear();
              setMs(() {});
            }),
          ])),
          Expanded(child: _subUrls.isEmpty ? Center(child: Text('EMPTY', style: TextStyle(color: Colors.white.withValues(alpha: 0.3)))) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _subUrls.length, itemBuilder: (ctx, i) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(10), border: Border.all(color: neonCyan.withValues(alpha: 0.2))), child: Row(children: [
            Text('S${i + 1}', style: const TextStyle(color: neonMagenta, fontSize: 10, fontWeight: FontWeight.bold)), const SizedBox(width: 8),
            Expanded(child: Text(_subUrls[i], style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
            IconButton(icon: const Icon(Icons.delete_outline, color: neonMagenta, size: 20), onPressed: () { setState(() => _subUrls.removeAt(i)); SharedPreferences.getInstance().then((p) => p.setStringList('subs', _subUrls)); setMs(() {}); }),
          ])))),
          Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: neonCyan.withValues(alpha: 0.1), side: const BorderSide(color: neonCyan)), onPressed: () { Navigator.pop(ctx); _syncAll(); }, child: const Text('SAVE & SYNC', style: TextStyle(color: neonCyan, fontWeight: FontWeight.bold, letterSpacing: 2))))),
        ]));
    }));
  }

  void _openPatt() {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setMs) {
      return Container(height: MediaQuery.of(ctx).size.height * 0.85, decoration: BoxDecoration(color: glass, borderRadius: const BorderRadius.vertical(top: Radius.circular(22)), border: Border(top: BorderSide(color: neonGreen.withValues(alpha: 0.6), width: 2))),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 54, height: 4, decoration: BoxDecoration(color: neonGreen.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8))),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('PATT-NG CORE', style: TextStyle(color: neonGreen, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 3))),
          Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            _dd('FINGERPRINT', ['unsafe', 'chrome', 'firefox', 'safari', 'randomized', 'randomizednoalpn'], _patt.fingerprint, (v) { setMs(() => _patt.fingerprint = v); _savePatt(); }),
            _tf('CIPHER SUITES', _patt.cipherSuites, (v) { _patt.cipherSuites = v; _savePatt(); }),
            _sw('ALLOW INSECURE', _patt.allowInsecure, (v) { setMs(() => _patt.allowInsecure = v); _savePatt(); }),
            _dd('FRAGMENT', ['tlshello', 'none'], _patt.fragment, (v) { setMs(() => _patt.fragment = v); _savePatt(); }),
            if (_patt.fragment != 'none') ...[_tf('FRAG LENGTH', _patt.fragLength, (v) { _patt.fragLength = v; _savePatt(); }), _tf('FRAG INTERVAL', _patt.fragInterval, (v) { _patt.fragInterval = v; _savePatt(); })],
            _sw('NOISE', _patt.noise, (v) { setMs(() => _patt.noise = v); _savePatt(); }),
            if (_patt.noise) ...[_dd('NOISE TYPE', ['rand', 'base64', 'str', 'hex'], _patt.noiseType, (v) { setMs(() => _patt.noiseType = v); _savePatt(); }), _tf('NOISE PACKET', _patt.noisePacket, (v) { _patt.noisePacket = v; _savePatt(); }), _tf('NOISE DELAY', _patt.noiseDelay, (v) { _patt.noiseDelay = v; _savePatt(); })],
            _sw('MUX', _patt.mux, (v) { setMs(() => _patt.mux = v); _savePatt(); }),
            if (_patt.mux) _tf('MUX CONCURRENCY', _patt.muxConc, (v) { _patt.muxConc = v; _savePatt(); }),
            _sw('BYPASS LAN', _patt.bypassLan, (v) { setMs(() => _patt.bypassLan = v); _savePatt(); }),
            _dd('LOG LEVEL', ['debug', 'info', 'warning', 'error', 'none'], _patt.logLevel, (v) { setMs(() => _patt.logLevel = v); _savePatt(); }),
            _dd('DNS', ['auto', 'doh', 'custom'], _patt.dnsMode, (v) { setMs(() => _patt.dnsMode = v); _savePatt(); }),
            if (_patt.dnsMode == 'custom') _tf('CUSTOM DNS', _patt.customDns, (v) { _patt.customDns = v; _savePatt(); }),
            _sw('REALITY', _patt.reality, (v) { setMs(() => _patt.reality = v); _savePatt(); }),
            if (_patt.reality) ...[_tf('PBK', _patt.pbk, (v) { _patt.pbk = v; _savePatt(); }), _tf('SID', _patt.sid, (v) { _patt.sid = v; _savePatt(); }), _tf('SPX', _patt.spx, (v) { _patt.spx = v; _savePatt(); })],
            _dd('FLOW', ['xtls-rprx-vision', 'none'], _patt.flow, (v) { setMs(() => _patt.flow = v); _savePatt(); }),
            _dd('ALPN', ['h2,http/1.1', 'h2', 'http/1.1', ''], _patt.alpn, (v) { setMs(() => _patt.alpn = v); _savePatt(); }),
            _dd('NETWORK', ['tcp', 'ws', 'grpc', 'http', 'kcp', 'quic', 'httpupgrade', 'splithttp'], _patt.network, (v) { setMs(() => _patt.network = v); _savePatt(); }),
            _tf('SNI', _patt.sni, (v) { _patt.sni = v; _savePatt(); }),
            _tf('PATH', _patt.path, (v) { _patt.path = v; _savePatt(); }),
            _tf('HOST', _patt.host, (v) { _patt.host = v; _savePatt(); }),
          ])),
          Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withValues(alpha: 0.1), side: const BorderSide(color: neonGreen)), onPressed: () { Navigator.pop(ctx); _syncAll(); }, child: const Text('APPLY & SYNC', style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold, letterSpacing: 2))))),
        ]));
    }));
  }

  @override
  Widget build(BuildContext context) {
    String selName = 'TAP TO SELECT';
    String selPing = '--';
    Color selPingC = Colors.grey;
    if (_loading) { selName = 'SYNCING...'; }
    else if (_selectedUri != null && _nodes.isNotEmpty) {
      final n = _nodes.firstWhere((e) => e.rawUri == _selectedUri, orElse: () => _nodes.first);
      selName = n.displayName;
      selPing = n.pingText;
      selPingC = n.pingColor;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF030308),
      body: Stack(children: [
        Positioned.fill(child: AnimatedBuilder(animation: _timeCtl, builder: (ctx, _) => CustomPaint(painter: CyberPainter(_timeCtl.value)))),
        Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(animation: _timeCtl, builder: (ctx, _) => CustomPaint(painter: ScanlinePainter(_timeCtl.value))))),
        SafeArea(child: Column(children: [
          const SizedBox(height: 18),
          AnimatedBuilder(animation: _timeCtl, builder: (ctx, _) {
            final g = sin(_timeCtl.value * 2 * pi * 2);
            return Stack(children: [
              if (g > 0.92) Transform.translate(offset: const Offset(2, 0), child: const Text('ZEUS VPN', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 8, color: neonMagenta))),
              if (g < -0.92) Transform.translate(offset: const Offset(-2, 0), child: const Text('ZEUS VPN', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 8, color: neonCyan))),
              Text('ZEUS VPN', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 8, color: Colors.white, shadows: [Shadow(color: neonCyan.withValues(alpha: 0.8), blurRadius: 12), Shadow(color: neonMagenta.withValues(alpha: 0.6), blurRadius: 22)])),
            ]);
          }),
          const SizedBox(height: 6),
          Text('CYBERPUNK NEON // PATT-NG CORE', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 9, letterSpacing: 3)),
          const SizedBox(height: 18),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
            Expanded(child: GestureDetector(onTap: _openSubs, child: _neonBox(color: neonMagenta, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14), child: Row(children: [const Icon(Icons.layers, color: neonMagenta, size: 18), const SizedBox(width: 8), const Text('SUBS', style: TextStyle(color: neonMagenta, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)), const Spacer(), Text('${_subUrls.length}', style: const TextStyle(color: neonMagenta, fontSize: 11, fontWeight: FontWeight.bold))]))),
            const SizedBox(width: 10),
            GestureDetector(onTap: _openPatt, child: _neonBox(color: neonGreen, padding: const EdgeInsets.all(12), child: const Icon(Icons.tune, color: neonGreen, size: 20))),
          ])),
          const SizedBox(height: 12),
          GestureDetector(onTap: _nodes.isEmpty ? () => _snack('Sync subs first!', err: true) : _openNodes, child: _neonBox(color: neonCyan, radius: 30, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.dns, color: neonCyan, size: 16), const SizedBox(width: 8),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 160), child: Text(selName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            if (selPing != '--') ...[const SizedBox(width: 6), Text(selPing, style: TextStyle(color: selPingC, fontSize: 10, fontWeight: FontWeight.bold))],
            const SizedBox(width: 6), const Icon(Icons.expand_more, color: neonCyan, size: 16),
          ]))),
          const Spacer(),
          GestureDetector(onTap: _toggle, child: ScaleTransition(scale: _connected ? _pulseAnim : const AlwaysStoppedAnimation(1.0), child: Stack(alignment: Alignment.center, children: [
            RotationTransition(turns: _ringCtl, child: Container(width: 170, height: 170, decoration: BoxDecoration(shape: BoxShape.circle, gradient: SweepGradient(colors: _connected ? [neonGreen, Colors.transparent, neonGreen] : [neonCyan, Colors.transparent, neonCyan])))),
            Container(width: 148, height: 148, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF030308), border: Border.all(color: _connected ? neonGreen : neonCyan, width: 2), boxShadow: [BoxShadow(color: (_connected ? neonGreen : neonCyan).withValues(alpha: 0.35), blurRadius: 26, spreadRadius: 3)]), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.power_settings_new, size: 44, color: _connected ? neonGreen : neonCyan),
              const SizedBox(height: 6),
              Text(_connected ? _dur : 'CONNECT', style: TextStyle(color: _connected ? neonGreen : neonCyan, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold)),
            ])),
          ]))),
          const Spacer(),
          if (_connected) Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: _neonBox(color: neonAmber, child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _stat('UP', _up, Icons.arrow_upward, neonMagenta),
            _stat('DOWN', _down, Icons.arrow_downward, neonCyan),
            GestureDetector(onTap: _testing ? null : _speedTest, child: _stat('SPEED', _testing ? '...' : (_speed.isEmpty ? 'TEST' : _speed), Icons.speed, neonGreen)),
          ]))),
          const SizedBox(height: 14),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: _neonBox(color: neonCyan, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _chip('FP', _patt.fingerprint.toUpperCase(), neonMagenta),
            _chip('FRAG', _patt.fragment.toUpperCase(), neonCyan),
            _chip('CS', _patt.cipherSuites.isNotEmpty ? 'ON' : 'AUTO', neonGreen),
            _chip('NET', _patt.network.toUpperCase(), neonAmber),
          ]))),
          const SizedBox(height: 24),
        ])),
      ]),
    );
  }

  Widget _stat(String t, String v, IconData i, Color c) => Column(children: [Icon(i, color: c, size: 16), const SizedBox(height: 4), Text(v, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold))]);
  Widget _chip(String t, String v, Color c) => Column(children: [Text(v, style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.bold)), Text(t, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 8))]);
}
