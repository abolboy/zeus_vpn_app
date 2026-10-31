  import 'package:flutter/material.dart';
  import 'package:dio/dio.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import 'package:flutter_v2ray_client/flutter_v2ray.dart';
  import 'dart:convert';
  import 'dart:io';
  import 'dart:math';
  import 'warp.dart';

  const Color CYAN = Color(0xFF00F0FF);
  const Color MAGENTA = Color(0xFFFF007F);
  const Color GREEN = Color(0xFF00FF88);
  const Color AMBER = Color(0xFFFFB800);
  const Color BG = Color(0xFF030308);
  const Color GLASS = Color(0xFF0A0A14);

  /// اگر هستهٔ باندل‌شده در flutter_v2ray_client قدیمی‌تر از Xray 25.10 است، false کنید.
  const bool kCoreHasFinalmask = true;

  /// پورت HTTP proxy محلی هسته (پیش‌فرض flutter_v2ray_client)
  const int kLocalHttpProxyPort = 10809;

  void main() => runApp(const ZeusApp());

  class ZeusApp extends StatelessWidget {
    const ZeusApp({super.key});
    @override
    Widget build(BuildContext context) {
      return MaterialApp(
        title: 'ZEUS VPN',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: BG),
        home: const HomePage(),
      );
    }
  }

  class ServerNode {
    final String subTag;
    final String rawUri;
    final String displayName;
    final String baseUri;
    String pingText;
    Color pingColor;
    ServerNode({required this.subTag, required this.rawUri, required this.displayName, required this.baseUri, this.pingText = '--', this.pingColor = Colors.grey});
  }

  class Patt {
    String fp = 'unsafe';
    String cs = '';
    String pcs = '';
    String vcn = '';
    String frag = 'tlshello';
    String fragLen = '100-200';
    String fragInt = '10-20';
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
    String flow = 'keep';        // FIX: پیش‌فرض = مقدار خود نود
    String alpn = '';            // FIX: پیش‌فرض = مقدار خود نود
    String sni = '';
    String path = '/';
    String host = '';
    String headerType = 'none';
    String network = 'tcp';
    String warpEndpoint = warpEndpoints.first;
  }

  class HomePage extends StatefulWidget {
    const HomePage({super.key});
    @override
    State<HomePage> createState() => _HomePageState();
  }

  class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
    static const String _kNodeCache = 'nodes_cache_v1';

    final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 20)));
    List<String> _subs = [];
    List<ServerNode> _nodes = [];
    String? _selUri;
    final Patt _patt = Patt();
    bool _ready = false;
    bool _loading = false;
    int _syncGen = 0;
    bool _connected = false;
    bool _connecting = false;
    bool _busy = false;
    bool _testing = false;
    bool _warpOn = false;
    bool _warpBusy = false;
    String? _warpJson;
    int _delayMode = 0;
    String _speed = '';
    String _up = '0 B/s';
    String _down = '0 B/s';
    String _dur = '00:00:00';
    VoidCallback? _refreshNodes;
    late V2ray _v2ray;
    late AnimationController _timeCtl;
    late AnimationController _pulseCtl;
    late AnimationController _ringCtl;
    late Animation<double> _pulseAnim;

    // ============================================================
    //  LIFECYCLE
    // ============================================================
    @override
    void initState() {
      super.initState();
      _timeCtl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
      _pulseCtl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
      _ringCtl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
      _pulseAnim = Tween<double>(begin: 0.96, end: 1.04).animate(CurvedAnimation(parent: _pulseCtl, curve: Curves.easeInOut));
      _v2ray = V2ray(onStatusChanged: (V2RayStatus s) {
        if (!mounted) return;
        setState(() {
          final st = s.state.toUpperCase();
          _connected = st == 'CONNECTED';
          _connecting = st == 'CONNECTING' || st == 'CONNECT';
          _up = _fmt(s.uploadSpeed);
          _down = _fmt(s.downloadSpeed);
          _dur = _connected ? s.duration : '00:00:00';
          if (!_connected && !_connecting) _speed = '';
        });
      });
      _boot();
    }

    @override
    void dispose() {
      _timeCtl.dispose();
      _pulseCtl.dispose();
      _ringCtl.dispose();
      _dio.close(force: true);
      super.dispose();
    }

    Future<void> _boot() async {
      final p = await SharedPreferences.getInstance();
      _subs = p.getStringList('subs') ?? [];
      _selUri = p.getString('sel');
      _warpOn = p.getBool('warp_on') ?? false;
      _warpJson = p.getString('warp_json');
      if (_warpJson != null && _warpJson!.isEmpty) _warpJson = null;
      _loadPatt(p);
      _loadNodeCache(p); // FIX: نودهای کش‌شده قبل از سینک → قابل اتصال در حالت آفلاین
      var coreOk = true;
      try {
        await _v2ray.initialize(
          notificationIconResourceType: "mipmap",
          notificationIconResourceName: "ic_launcher",
        );
      } catch (_) {
        coreOk = false;
      }
      if (!mounted) return;
      setState(() => _ready = coreOk);
      if (!coreOk) WidgetsBinding.instance.addPostFrameCallback((_) => _snack('Core failed to initialize.', err: true));
      if (_subs.isNotEmpty) _syncAll();
    }

    // ============================================================
    //  PERSISTENCE
    // ============================================================
    void _loadPatt(SharedPreferences p) {
      _patt.fp = p.getString('p_fp') ?? 'unsafe';
      _patt.cs = p.getString('p_cs') ?? '';
      _patt.pcs = p.getString('p_pcs') ?? '';
      _patt.vcn = p.getString('p_vcn') ?? '';
      _patt.frag = p.getString('p_frag') ?? 'tlshello';
      _patt.fragLen = p.getString('p_fl') ?? '100-200';
      _patt.fragInt = p.getString('p_fi') ?? '10-20';
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
      _patt.flow = p.getString('p_flow') ?? 'keep';
      _patt.alpn = p.getString('p_alpn') ?? '';
      _patt.sni = p.getString('p_sni') ?? '';
      _patt.path = p.getString('p_path') ?? '/';
      _patt.host = p.getString('p_host') ?? '';
      _patt.headerType = p.getString('p_ht') ?? 'none';
      _patt.network = p.getString('p_net') ?? 'tcp';
      _patt.warpEndpoint = p.getString('p_wep') ?? warpEndpoints.first;
      // migration: مقادیر قدیمی که به‌صورت اجباری تزریق می‌شدند
      if (_patt.flow == 'xtls-rprx-vision' && p.getString('p_flow_migrated') == null) {
        _patt.flow = 'keep';
        p.setString('p_flow_migrated', '1');
      }
    }

    Future<void> _savePatt() async {
      final p = await SharedPreferences.getInstance();
      await Future.wait([
        p.setString('p_fp', _patt.fp),
        p.setString('p_cs', _patt.cs),
        p.setString('p_pcs', _patt.pcs),
        p.setString('p_vcn', _patt.vcn),
        p.setString('p_frag', _patt.frag),
        p.setString('p_fl', _patt.fragLen),
        p.setString('p_fi', _patt.fragInt),
        p.setBool('p_noise', _patt.noise),
        p.setString('p_nt', _patt.noiseType),
        p.setString('p_np', _patt.noisePacket),
        p.setString('p_nd', _patt.noiseDelay),
        p.setBool('p_mux', _patt.mux),
        p.setString('p_mc', _patt.muxConc),
        p.setBool('p_lan', _patt.bypassLan),
        p.setString('p_log', _patt.logLevel),
        p.setString('p_dns', _patt.dnsMode),
        p.setString('p_dnsc', _patt.customDns),
        p.setBool('p_real', _patt.reality),
        p.setString('p_pbk', _patt.pbk),
        p.setString('p_sid', _patt.sid),
        p.setString('p_spx', _patt.spx),
        p.setString('p_flow', _patt.flow),
        p.setString('p_alpn', _patt.alpn),
        p.setString('p_sni', _patt.sni),
        p.setString('p_path', _patt.path),
        p.setString('p_host', _patt.host),
        p.setString('p_ht', _patt.headerType),
        p.setString('p_net', _patt.network),
        p.setString('p_wep', _patt.warpEndpoint),
      ]);
    }

    Future<void> _saveWarp() async {
      final p = await SharedPreferences.getInstance();
      await p.setBool('warp_on', _warpOn);
      await p.setString('warp_json', _warpJson ?? '');
    }

    void _loadNodeCache(SharedPreferences p) {
      try {
        final raw = p.getString(_kNodeCache);
        if (raw == null || raw.isEmpty) return;
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _nodes = list.map((m) {
          final base = m['b'] as String;
          final tag = m['t'] as String;
          return ServerNode(subTag: tag, rawUri: _linkFor(base), baseUri: base, displayName: '[$tag] ${_name(base)}');
        }).toList();
        if (_selUri != null && !_nodes.any((n) => n.baseUri == _selUri) && _nodes.isNotEmpty) _selUri = _nodes.first.baseUri;
      } catch (_) {}
    }

    Future<void> _saveNodeCache() async {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kNodeCache, jsonEncode(_nodes.map((n) => {'t': n.subTag, 'b': n.baseUri}).toList()));
    }

    // ============================================================
    //  HELPERS
    // ============================================================
    String _fmt(int bps) {
      if (bps < 1024) return '$bps B/s';
      if (bps < 1048576) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
      return '${(bps / 1048576).toStringAsFixed(1)} MB/s';
    }

    int _ms(ServerNode n) => int.tryParse(n.pingText.replaceAll(' ms', '').trim()) ?? 999999;

    /// لینک نهایی همیشه در لحظه از baseUri با تنظیمات فعلی ساخته می‌شود (FIX: stale link)
    String _linkFor(String base) => base.startsWith('vmess://') ? base : _injectQuery(base);

    Map<String, dynamic>? _vmess(String uri) {
      try {
        final b = uri.substring('vmess://'.length).split('#').first.trim();
        List<int> bytes;
        try {
          bytes = base64.decode(base64.normalize(b));
        } catch (_) {
          bytes = base64Url.decode(base64Url.normalize(b));
        }
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }

    MapEntry<String, int>? _hostPort(String uri) {
      try {
        if (uri.startsWith('vmess://')) {
          final j = _vmess(uri);
          if (j == null) return null;
          return MapEntry(j['add'].toString(), int.tryParse(j['port'].toString()) ?? 0);
        }
        final u = Uri.parse(uri);
        return MapEntry(u.host, u.port);
      } catch (_) {
        return null;
      }
    }

    String _name(String uri) {
      try {
        if (uri.startsWith('vmess://')) {
          final j = _vmess(uri);
          if (j != null) {
            final ps = (j['ps'] ?? '').toString();
            return ps.isNotEmpty ? ps : '${j['add']}:${j['port']}';
          }
        }
        final u = Uri.parse(uri);
        if (u.fragment.isNotEmpty) {
          try {
            return Uri.decodeComponent(u.fragment);
          } catch (_) {
            return u.fragment;
          }
        }
        return '${u.host}:${u.port}';
      } catch (_) {
        return 'Node';
      }
    }

    static const List<String> _privateCidrs = ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '127.0.0.0/8', '169.254.0.0/16', 'fc00::/7', 'fe80::/10'];

    /// Xray Int32Range ("100-200" یا "50"); مقدار نامعتبر → fallback تا هسته کرش نکند
    String _range(String v, String fallback, {int min = 0}) {
      final m = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(v.trim());
      if (m == null) return fallback;
      final a = int.tryParse(m.group(1)!);
      final b = m.group(2) == null ? a : int.tryParse(m.group(2)!);
      if (a == null || b == null || a < min || a > b || b > 2147483647) return fallback;
      return v.trim();
    }

    // ============================================================
    //  CONFIG BUILDING
    // ============================================================
    String _injectQuery(String uri) {
      try {
        final u = Uri.parse(uri);
        final q = Map<String, String>.from(u.queryParameters);
        if (_patt.reality && _patt.pbk.isNotEmpty) {
          q['security'] = 'reality';
          q['pbk'] = _patt.pbk;
          if (_patt.sid.isNotEmpty) q['sid'] = _patt.sid;
          if (_patt.spx.isNotEmpty) q['spx'] = _patt.spx;
        }
        final secNow = q['security'] ?? 'none';
        final netNow = _patt.network != 'tcp' ? _patt.network : (q['type'] ?? 'tcp');

        // Fingerprint: 'unsafe' = حفظ مقدار نود، ولی TLS/REALITY بدون fp → chrome
        if (_patt.fp != 'unsafe') {
          q['fp'] = _patt.fp;
        } else if ((secNow == 'tls' || secNow == 'reality') && (q['fp'] ?? '').isEmpty) {
          q['fp'] = 'chrome';
        }

        // Flow: 'keep' = مقدار خود نود؛ فقط روی VLESS+TCP+TLS/REALITY معتبر است
        if (_patt.flow != 'keep') {
          final ok = u.scheme == 'vless' && netNow == 'tcp' && (secNow == 'tls' || secNow == 'reality') && _patt.flow != 'none';
          if (ok) {
            q['flow'] = _patt.flow;
          } else {
            q.remove('flow');
          }
        } else if (netNow != 'tcp') {
          q.remove('flow');
        }

        // ALPN: خالی = مقدار نود. WS/HTTPUpgrade فقط http/1.1 و gRPC فقط h2
        if (_patt.alpn.isNotEmpty) {
          if (netNow == 'ws' || netNow == 'httpupgrade') {
            q['alpn'] = 'http/1.1';
          } else if (netNow == 'grpc') {
            q['alpn'] = 'h2';
          } else {
            q['alpn'] = _patt.alpn;
          }
        }

        if (_patt.sni.isNotEmpty) q['sni'] = _patt.sni;
        if (_patt.path.isNotEmpty && _patt.path != '/') q['path'] = _patt.path;
        if (_patt.host.isNotEmpty) q['host'] = _patt.host;
        if (_patt.headerType != 'none') q['headerType'] = _patt.headerType;
        if (_patt.network.isNotEmpty && _patt.network != 'tcp') q['type'] = _patt.network;
        return u.replace(queryParameters: q).toString();
      } catch (_) {
        return uri;
      }
    }

    void _addLanBypass(Map<String, dynamic> json, List outs) {
      if (!outs.any((o) => o is Map && o['tag'] == 'direct')) outs.add({'tag': 'direct', 'protocol': 'freedom'});
      final routing = (json['routing'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final rules = (routing['rules'] as List?) ?? <dynamic>[];
      rules.insert(0, {'type': 'field', 'ip': _privateCidrs, 'outboundTag': 'direct'});
      routing['rules'] = rules;
      routing.putIfAbsent('domainStrategy', () => 'AsIs');
      json['routing'] = routing;
    }

    /// cs / pcs / vcn پارامتر share-link نیستند؛ باید مستقیم در tlsSettings بروند
    void _applyTlsExtras(Map<String, dynamic> main) {
      final stream = main['streamSettings'] as Map<String, dynamic>?;
      if (stream == null || stream['security'] != 'tls') return;
      final tls = (stream['tlsSettings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      if (_patt.cs.isNotEmpty) tls['cipherSuites'] = _patt.cs;
      if (_patt.pcs.isNotEmpty) tls['pinnedPeerCertificateChainSha256'] = [_patt.pcs];
      if (_patt.vcn.isNotEmpty) tls['verifyPeerCertInNames'] = [_patt.vcn];
      stream['tlsSettings'] = tls;
    }

    Map<String, dynamic> _fragmentMask(bool reality) => {
          'type': 'fragment',
          'settings': {
            'packets': reality ? '1-3' : _patt.frag,
            'lengths': [_range(_patt.fragLen, '100-200', min: 1)],
            'delays': [_range(_patt.fragInt, '10-20')],
          },
        };

    Map<String, dynamic> _noiseMask() => {
          'type': 'noise',
          'settings': {
            'reset': '30-60',
            'noise': [
              {_patt.noiseType == 'str' ? 'str' : 'rand': _range(_patt.noisePacket, '10-20', min: 1), 'delay': _range(_patt.noiseDelay, '10-20')},
            ],
          },
        };

    void _applyFinalmask(Map<String, dynamic> ob, {bool tcp = true, bool udp = true}) {
      final stream = (ob['streamSettings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final fm = (stream['finalmask'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      if (tcp && _patt.frag != 'none') {
        final l = (fm['tcp'] as List?) ?? <dynamic>[];
        l.insert(0, _fragmentMask(stream['security'] == 'reality'));
        fm['tcp'] = l;
      }
      if (udp && _patt.noise) {
        final l = (fm['udp'] as List?) ?? <dynamic>[];
        l.add(_noiseMask());
        fm['udp'] = l;
      }
      if (fm.isNotEmpty) {
        stream['finalmask'] = fm;
        ob['streamSettings'] = stream;
      }
    }

    /// Fallback برای هسته‌های قدیمی (Xray < 25.10): freedom + dialerProxy
    void _applyLegacyFragment(Map<String, dynamic> main, List outs) {
      if (_patt.frag == 'none' && !_patt.noise) return;
      final stream = (main['streamSettings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final sockopt = (stream['sockopt'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      sockopt['dialerProxy'] = 'fragment';
      stream['sockopt'] = sockopt;
      main['streamSettings'] = stream;
      outs.removeWhere((o) => o is Map && o['tag'] == 'fragment');
      outs.add({
        'tag': 'fragment',
        'protocol': 'freedom',
        'settings': {
          if (_patt.frag != 'none')
            'fragment': {
              'packets': stream['security'] == 'reality' ? '1-3' : _patt.frag,
              'length': _range(_patt.fragLen, '100-200', min: 1),
              'interval': _range(_patt.fragInt, '10-20'),
            },
          if (_patt.noise)
            'noises': [
              {'type': _patt.noiseType == 'str' ? 'str' : 'rand', 'packet': _range(_patt.noisePacket, '10-20', min: 1), 'delay': _range(_patt.noiseDelay, '10-20')}
            ],
        },
        'streamSettings': {'sockopt': {'tcpNoDelay': true}},
      });
    }

    String _injectCore(String config) {
      try {
        final json = jsonDecode(config) as Map<String, dynamic>;
        final outs = json['outbounds'] as List?;
        if (outs == null || outs.isEmpty) return config;
        var main = outs[0] as Map<String, dynamic>;
        json['log'] = {'loglevel': _patt.logLevel};

        // DNS: DoH باید از داخل تونل برود (https:// نه https+local://)
        if (_patt.dnsMode == 'doh') {
          json['dns'] = {'servers': ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query'], 'queryStrategy': 'UseIP'};
        } else if (_patt.dnsMode == 'custom' && _patt.customDns.isNotEmpty) {
          json['dns'] = {'servers': _patt.customDns.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()};
        }

        final warpActive = _warpOn && _warpJson != null && _warpJson!.isNotEmpty;
        if (warpActive) {
          final w = jsonDecode(_warpJson!) as Map<String, dynamic>;
          w['tag'] = (main['tag'] ?? 'proxy').toString();
          // endpoint انتخابی کاربر را روی کانفیگ ذخیره‌شده اعمال کن
          try {
            ((w['settings'] as Map)['peers'] as List)[0]['endpoint'] = _patt.warpEndpoint;
          } catch (_) {}
          outs[0] = w;
          main = w;
          if (kCoreHasFinalmask) _applyFinalmask(main, tcp: false, udp: true); // WARP = UDP → فقط noise
        } else {
          _applyTlsExtras(main);
          final hasFlow = RegExp(r'"flow":"xtls').hasMatch(jsonEncode(main['settings'] ?? <String, dynamic>{}));
          if (_patt.mux && !hasFlow) main['mux'] = {'enabled': true, 'concurrency': int.tryParse(_patt.muxConc) ?? 8};
          if (kCoreHasFinalmask) {
            _applyFinalmask(main);
          } else {
            _applyLegacyFragment(main, outs);
          }
        }

        if (_patt.bypassLan) _addLanBypass(json, outs);
        json['outbounds'] = outs;
        return jsonEncode(json);
      } catch (_) {
        return config;
      }
    }

    // ============================================================
    //  SYNC / PING / SPEED
    // ============================================================
    Future<void> _syncAll() async {
      final gen = ++_syncGen;
      if (_subs.isEmpty) {
        setState(() {
          _loading = false;
          _nodes = [];
          _selUri = null;
        });
        _saveNodeCache();
        _refreshNodes?.call();
        return;
      }
      final prev = _selUri;
      setState(() => _loading = true);

      // FIX: موازی + بدون پاک‌کردن نودهای فعلی
      final results = await Future.wait(List.generate(_subs.length, (i) => _fetchSub(_subs[i], 'SUB-${i + 1}')));
      if (!mounted || gen != _syncGen) return;

      final got = results.expand((e) => e).toList();
      final okCount = results.where((e) => e.isNotEmpty).length;

      setState(() {
        if (got.isNotEmpty) _nodes = got;
        if (prev != null && _nodes.any((n) => n.baseUri == prev)) {
          _selUri = prev;
        } else if (_nodes.isNotEmpty) {
          _selUri = _nodes.first.baseUri;
        } else {
          _selUri = null;
        }
        _loading = false;
      });

      if (got.isEmpty) {
        _snack(_nodes.isNotEmpty ? 'Sync failed — using cached nodes' : 'Sync failed — no nodes', err: true);
      } else {
        _saveNodeCache();
        if (okCount < _subs.length) _snack('${_subs.length - okCount} sub(s) failed', err: true);
      }
      _refreshNodes?.call();
      _pingAll();
    }

    Future<List<ServerNode>> _fetchSub(String url, String tag) async {
      final out = <ServerNode>[];
      try {
        final res = await _dio.get(url, options: Options(headers: {'User-Agent': 'v2rayNG/1.8.5'}, responseType: ResponseType.plain));
        String body = res.data.toString().trim();
        final compact = body.replaceAll(RegExp(r'\s'), '');
        try {
          body = utf8.decode(base64.decode(base64.normalize(compact)));
        } catch (_) {
          try {
            body = utf8.decode(base64Url.decode(base64Url.normalize(compact)));
          } catch (_) {}
        }
        for (final raw in body.split(RegExp(r'\r?\n')).map((e) => e.trim())) {
          if (raw.startsWith('vless://') || raw.startsWith('trojan://') || raw.startsWith('vmess://')) {
            out.add(ServerNode(subTag: tag, rawUri: _linkFor(raw), baseUri: raw, displayName: '[$tag] ${_name(raw)}'));
          }
        }
      } catch (_) {}
      return out;
    }

    Future<void> _pingAll() async {
      final c = _delayMode == 1 ? 4 : 20;
      final q = List<ServerNode>.from(_nodes);
      await Future.wait(List.generate(c, (_) async {
        while (q.isNotEmpty) {
          final n = q.removeAt(0);
          await _pingOne(n);
        }
      }));
    }

    Future<void> _pingOne(ServerNode n) async {
      void setPing(String text, Color c) {
        if (!mounted) return;
        setState(() {
          n.pingText = text;
          n.pingColor = c;
        });
        _refreshNodes?.call();
      }
      Color colorOf(int ms) => ms < 200 ? GREEN : (ms < 500 ? AMBER : MAGENTA);

      if (_delayMode == 1) {
        try {
          // FIX: تست REAL با همان کانفیگی که برای اتصال استفاده می‌شود
          final parser = V2ray.parseFromURL(_linkFor(n.baseUri));
          final ms = await _v2ray.getServerDelay(config: _injectCore(parser.getFullConfiguration()));
          if (ms <= 0) throw Exception('timeout');
          setPing('$ms ms', colorOf(ms));
        } catch (_) {
          setPing('TIMEOUT', MAGENTA);
        }
        return;
      }
      try {
        final hp = _hostPort(n.rawUri);
        if (hp == null || hp.value == 0) throw Exception('no port');
        final sw = Stopwatch()..start();
        final s = await Socket.connect(hp.key, hp.value, timeout: const Duration(seconds: 3));
        sw.stop();
        s.destroy();
        setPing('${sw.elapsedMilliseconds} ms', colorOf(sw.elapsedMilliseconds));
      } catch (_) {
        setPing('TIMEOUT', MAGENTA);
      }
    }

    Future<void> _speedTest() async {
      setState(() {
        _testing = true;
        _speed = '...';
      });
      try {
        final sw = Stopwatch()..start();
        final res = await _dio.get('https://speed.cloudflare.com/__down?bytes=10000000', options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 30)));
        sw.stop();
        double sec = sw.elapsedMilliseconds / 1000.0;
        if (sec == 0) sec = 0.1;
        final mbps = (res.data.length.toDouble() * 8) / (sec * 1048576);
        if (!mounted) return;
        setState(() => _speed = '${mbps.toStringAsFixed(1)} Mbps');
      } catch (_) {
        if (!mounted) return;
        setState(() => _speed = 'FAILED');
      }
      if (!mounted) return;
      setState(() => _testing = false);
    }

    // ============================================================
    //  CONNECT / DISCONNECT
    // ============================================================
    Future<void> _toggle() async {
      if (!_ready) {
        _snack('Core is initializing...', err: true);
        return;
      }
      if (_busy) return;
      _busy = true;
      try {
        if (_connected || _connecting) {
          await _v2ray.stopV2Ray(); // FIX: در حالت CONNECTING هم قابل لغو است
          return;
        }
        final idx = _nodes.indexWhere((n) => n.baseUri == _selUri);
        if (idx < 0) {
          _snack(_loading ? 'Syncing nodes, wait...' : 'First select a node.', err: true);
          return;
        }
        if (_warpOn && (_warpJson == null || _warpJson!.isEmpty)) {
          _snack('WARP is ON but no device registered.', err: true);
          return;
        }
        final ok = await _v2ray.requestPermission();
        if (!ok) {
          _snack('VPN permission denied.', err: true);
          return;
        }
        // FIX: لینک از baseUri با تنظیمات فعلی ساخته می‌شود — نه نسخهٔ کهنهٔ زمان سینک
        final parser = V2ray.parseFromURL(_linkFor(_nodes[idx].baseUri));
        final config = _injectCore(parser.getFullConfiguration());
        await _v2ray.startV2Ray(remark: parser.remark, config: config, proxyOnly: false);
      } catch (e) {
        final msg = e.toString().split('\n').first;
        _snack('Core error: ${msg.length > 90 ? msg.substring(0, 90) : msg}', err: true);
      } finally {
        _busy = false;
      }
    }

    Future<void> _registerWarp(StateSetter setMs, BuildContext ctx) async {
      if (_warpBusy) return;
      _warpBusy = true;
      if (ctx.mounted) setMs(() {});
      _snack('Registering WARP device...');
      try {
        final kp = await genWarpKeys(); // در isolate — UI فریز نمی‌شود
        final out = await registerWarp(kp, endpoint: _patt.warpEndpoint, proxyPort: _connected ? kLocalHttpProxyPort : null);
        if (!mounted) return;
        setState(() => _warpJson = jsonEncode(out));
        await _saveWarp();
        _snack('WARP registered!');
      } on WarpException catch (e) {
        if (mounted) _snack('WARP: $e', err: true);
      } catch (e) {
        if (mounted) _snack('WARP: ${e.toString().split('\n').first}', err: true);
      } finally {
        _warpBusy = false;
        if (ctx.mounted) setMs(() {});
      }
    }

    void _snack(String m, {bool err = false}) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(color: Colors.white)), backgroundColor: err ? MAGENTA : GREEN, behavior: SnackBarBehavior.floating));
    }

    // ============================================================
    //  SMALL WIDGETS
    // ============================================================
    Widget _box(Widget child, {Color color = CYAN, double radius = 14, EdgeInsets padding = const EdgeInsets.all(14)}) {
      return AnimatedBuilder(animation: _ringCtl, builder: (context, _) {
        final t = _ringCtl.value * 2 * pi;
        final a = 0.35 + 0.25 * sin(t);
        return Container(
          padding: padding,
          decoration: BoxDecoration(
            color: GLASS.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: color.withValues(alpha: a)),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 18)],
          ),
          child: child,
        );
      });
    }

    Widget _pill(IconData ic, String label, Color c, VoidCallback on) {
      return GestureDetector(onTap: on, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.5))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, color: c, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
        ]),
      ));
    }

    Widget _dd(String label, List<String> items, String cur, void Function(String) on) {
      return Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        InputDecorator(
          decoration: InputDecoration(filled: true, fillColor: Colors.white.withValues(alpha: 0.04), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          child: DropdownButtonHideUnderline(child: DropdownButton<String>(
            key: ValueKey('dd_$label'),
            value: items.contains(cur) ? cur : items.first,
            isExpanded: true,
            dropdownColor: GLASS,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            items: items.map((v) => DropdownMenuItem(value: v, child: Text(v.isEmpty ? '(keep node value)' : v))).toList(),
            onChanged: (v) {
              if (v != null) on(v);
            },
          )),
        ),
      ]));
    }

    Widget _tf(String label, String cur, void Function(String) on) {
      return Padding(padding: const EdgeInsets.only(bottom: 14), child: TextFormField(
        key: ValueKey('tf_$label'),
        initialValue: cur,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10), filled: true, fillColor: Colors.white.withValues(alpha: 0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        onChanged: on,
      ));
    }

    Widget _sw(String label, bool val, void Function(bool) on) {
      return SwitchListTile(key: ValueKey('sw_$label'), contentPadding: EdgeInsets.zero, title: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)), value: val, onChanged: on);
    }

    Widget _sheet(BuildContext ctx, double h, Color c, Widget child) => Container(
          height: MediaQuery.of(ctx).size.height * h,
          decoration: BoxDecoration(color: GLASS, borderRadius: const BorderRadius.vertical(top: Radius.circular(22)), border: Border(top: BorderSide(color: c.withValues(alpha: 0.6), width: 2))),
          child: child,
        );

    Widget _handle(Color c) => Column(children: [
          const SizedBox(height: 12),
          Container(width: 54, height: 4, decoration: BoxDecoration(color: c.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8))),
        ]);

    Widget _bigBtn(String label, Color c, VoidCallback on) => Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: c.withValues(alpha: 0.1), side: BorderSide(color: c)), onPressed: on, child: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.bold, letterSpacing: 2)))));

    // ============================================================
    //  SHEETS
    // ============================================================
    void _openNodes() {
      String q = '';
      String tag = 'ALL';
      int sort = 0;
      showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setMs) {
        _refreshNodes = () {
          if (ctx.mounted) setMs(() {});
        };
        var vis = _nodes.where((n) => (tag == 'ALL' || n.subTag == tag) && (q.isEmpty || n.displayName.toLowerCase().contains(q.toLowerCase()))).toList();
        if (sort == 1) vis.sort((a, b) => _ms(a).compareTo(_ms(b)));
        if (sort == 2) vis.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
        final tags = <String>['ALL', ..._nodes.map((e) => e.subTag).toSet()];
        return _sheet(ctx, 0.9, CYAN, Column(children: [
          _handle(CYAN),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(children: [
            const Icon(Icons.dns, color: CYAN, size: 18),
            const SizedBox(width: 8),
            const Text('NODE CENTER', style: TextStyle(color: CYAN, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 3)),
            const SizedBox(width: 8),
            Text('${vis.length}/${_nodes.length}', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
            if (_loading) ...[const Spacer(), const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: CYAN))],
          ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Wrap(spacing: 8, runSpacing: 8, children: [
            _pill(Icons.refresh, 'SYNC', CYAN, _syncAll),
            _pill(Icons.network_ping, 'PING ALL', GREEN, _pingAll),
            _pill(Icons.sort, sort == 0 ? 'SORT: AUTO' : (sort == 1 ? 'SORT: PING' : 'SORT: NAME'), AMBER, () => setMs(() => sort = (sort + 1) % 3)),
            _pill(Icons.timer_outlined, _delayMode == 0 ? 'DELAY: TCP' : 'DELAY: REAL', MAGENTA, () => setMs(() => _delayMode = _delayMode == 0 ? 1 : 0)),
          ])),
          const SizedBox(height: 10),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(style: const TextStyle(color: Colors.white, fontSize: 13), onChanged: (v) => setMs(() => q = v), decoration: InputDecoration(hintText: 'SEARCH NODE...', hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12), prefixIcon: const Icon(Icons.search, color: CYAN, size: 18), filled: true, fillColor: Colors.white.withValues(alpha: 0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))))),
          const SizedBox(height: 10),
          SizedBox(height: 34, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: tags.map((t) {
            final on = tag == t;
            return Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(onTap: () => setMs(() => tag = t), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), decoration: BoxDecoration(color: on ? CYAN.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(20), border: Border.all(color: on ? CYAN : Colors.white.withValues(alpha: 0.1))), child: Text(t, style: TextStyle(color: on ? CYAN : Colors.white.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.bold)))));
          }).toList())),
          Expanded(child: vis.isEmpty ? Center(child: Text('NO NODES', style: TextStyle(color: Colors.white.withValues(alpha: 0.3)))) : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), itemCount: vis.length, itemBuilder: (ctx, i) {
            final n = vis[i];
            final sel = n.baseUri == _selUri;
            final isVless = n.baseUri.startsWith('vless://');
            final isTrojan = n.baseUri.startsWith('trojan://');
            return GestureDetector(onTap: () {
              setState(() => _selUri = n.baseUri);
              SharedPreferences.getInstance().then((p) => p.setString('sel', n.baseUri));
              setMs(() {});
              Navigator.pop(ctx);
            }, child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: sel ? CYAN.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(12), border: Border.all(color: sel ? CYAN : Colors.white.withValues(alpha: 0.06))), child: Row(children: [
              Icon(isVless ? Icons.bolt_rounded : (isTrojan ? Icons.shield_rounded : Icons.memory_rounded), color: isVless ? CYAN : (isTrojan ? MAGENTA : AMBER), size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.displayName, style: TextStyle(color: sel ? Colors.white : Colors.white70, fontSize: 13, fontWeight: sel ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(n.subTag, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 9, fontWeight: FontWeight.bold)),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: n.pingColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: n.pingColor.withValues(alpha: 0.5))), child: Text(n.pingText, style: TextStyle(color: n.pingColor, fontSize: 10, fontWeight: FontWeight.bold))),
              if (sel) ...[const SizedBox(width: 8), const Icon(Icons.check_circle, color: GREEN, size: 18)],
            ])));
          })),
        ]));
      })).then((_) {
        _refreshNodes = null;
        if (mounted) setState(() {});
      });
    }

    void _openSubs() {
      final ctl = TextEditingController();
      showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setMs) {
        return _sheet(ctx, 0.65, MAGENTA, Column(children: [
          _handle(MAGENTA),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('SUBSCRIPTIONS', style: TextStyle(color: MAGENTA, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 3))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
            Expanded(child: TextField(controller: ctl, style: const TextStyle(color: Colors.white, fontSize: 12), decoration: InputDecoration(hintText: 'https://...', hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 11), filled: true, fillColor: Colors.white.withValues(alpha: 0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))))),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.add_circle, color: GREEN, size: 26), onPressed: () {
              final v = ctl.text.trim();
              final su = Uri.tryParse(v);
              if (su == null || !(su.scheme == 'http' || su.scheme == 'https') || su.host.isEmpty) {
                _snack('Invalid URL!', err: true);
                return;
              }
              if (_subs.contains(v)) {
                _snack('Duplicate sub!', err: true);
                return;
              }
              setState(() => _subs.add(v));
              SharedPreferences.getInstance().then((p) => p.setStringList('subs', _subs));
              ctl.clear();
              setMs(() {});
            }),
          ])),
          Expanded(child: _subs.isEmpty ? Center(child: Text('EMPTY', style: TextStyle(color: Colors.white.withValues(alpha: 0.3)))) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _subs.length, itemBuilder: (ctx, i) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(10), border: Border.all(color: CYAN.withValues(alpha: 0.2))), child: Row(children: [
            Text('S${i + 1}', style: const TextStyle(color: MAGENTA, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Expanded(child: Text(_subs[i], style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
            IconButton(icon: const Icon(Icons.delete_outline, color: MAGENTA, size: 20), onPressed: () {
              setState(() => _subs.removeAt(i));
              SharedPreferences.getInstance().then((p) => p.setStringList('subs', _subs));
              setMs(() {});
            }),
          ])))),
          _bigBtn('SAVE & SYNC', CYAN, () {
            Navigator.pop(ctx);
            _syncAll();
          }),
        ]));
      })).then((_) {
        ctl.dispose();
        if (mounted) setState(() {});
      });
    }

    void _openPatt() {
      showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setMs) {
        return _sheet(ctx, 0.85, GREEN, Column(children: [
          _handle(GREEN),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('PATT-NG CORE', style: TextStyle(color: GREEN, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 3))),
          Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            // ---------------- WARP ----------------
            _sw('WARP (Cloudflare WireGuard)', _warpOn, (v) {
              setMs(() => _warpOn = v);
              _saveWarp();
            }),
            if (_warpOn) ...[
              _dd('WARP ENDPOINT', warpEndpoints, _patt.warpEndpoint, (v) {
                setMs(() => _patt.warpEndpoint = v);
                _savePatt();
              }),
              if (_warpJson != null) ...[
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('WARP device: REGISTERED', style: TextStyle(color: GREEN, fontSize: 10, fontWeight: FontWeight.bold))),
                Padding(padding: const EdgeInsets.only(bottom: 14), child: SizedBox(width: double.infinity, height: 40, child: OutlinedButton(onPressed: () {
                  setState(() => _warpJson = null);
                  _saveWarp();
                  setMs(() {});
                }, child: const Text('RESET WARP DEVICE', style: TextStyle(color: AMBER, fontWeight: FontWeight.bold, letterSpacing: 1))))),
              ] else
                Padding(padding: const EdgeInsets.only(bottom: 14), child: SizedBox(width: double.infinity, height: 44, child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: CYAN.withValues(alpha: 0.1), side: const BorderSide(color: CYAN)),
                  onPressed: _warpBusy ? null : () => _registerWarp(setMs, ctx),
                  child: Text(_warpBusy ? 'REGISTERING...' : 'REGISTER WARP DEVICE', style: const TextStyle(color: CYAN, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ))),
              if (_warpJson == null && !_connected)
                Padding(padding: const EdgeInsets.only(bottom: 14), child: Text('Tip: if registration fails, connect to a node first and try again.', style: TextStyle(color: AMBER.withValues(alpha: 0.8), fontSize: 10))),
            ],
            // ---------------- TLS ----------------
            _dd('FINGERPRINT (unsafe = keep node value)', ['unsafe', 'chrome', 'firefox', 'safari', 'randomized', 'randomizednoalpn'], _patt.fp, (v) {
              setMs(() => _patt.fp = v);
              _savePatt();
            }),
            _tf('CIPHER SUITES', _patt.cs, (v) {
              _patt.cs = v.trim();
              _savePatt();
            }),
            _tf('PINNED CERT SHA256 (pcs)', _patt.pcs, (v) {
              _patt.pcs = v.trim();
              _savePatt();
            }),
            _tf('VERIFY CERT NAME (vcn)', _patt.vcn, (v) {
              _patt.vcn = v.trim();
              _savePatt();
            }),
            // ---------------- FRAGMENT / NOISE ----------------
            _dd('FRAGMENT (packets)', ['tlshello', '1-1', '1-2', '1-3', 'none'], _patt.frag, (v) {
              setMs(() => _patt.frag = v);
              _savePatt();
            }),
            if (_patt.frag != 'none') ...[
              _tf('FRAG LENGTH', _patt.fragLen, (v) {
                _patt.fragLen = v;
                _savePatt();
              }),
              _tf('FRAG INTERVAL', _patt.fragInt, (v) {
                _patt.fragInt = v;
                _savePatt();
              }),
            ],
            _sw('NOISE (UDP ONLY — needed for WARP)', _patt.noise, (v) {
              setMs(() => _patt.noise = v);
              _savePatt();
            }),
            if (_patt.noise) ...[
              _dd('NOISE TYPE', ['rand', 'str'], _patt.noiseType, (v) {
                setMs(() => _patt.noiseType = v);
                _savePatt();
              }),
              _tf('NOISE PACKET', _patt.noisePacket, (v) {
                _patt.noisePacket = v;
                _savePatt();
              }),
              _tf('NOISE DELAY', _patt.noiseDelay, (v) {
                _patt.noiseDelay = v;
                _savePatt();
              }),
            ],
            // ---------------- MISC ----------------
            _sw('MUX', _patt.mux, (v) {
              setMs(() => _patt.mux = v);
              _savePatt();
            }),
            if (_patt.mux) _tf('MUX CONCURRENCY', _patt.muxConc, (v) {
              _patt.muxConc = v;
              _savePatt();
            }),
            _sw('BYPASS LAN', _patt.bypassLan, (v) {
              setMs(() => _patt.bypassLan = v);
              _savePatt();
            }),
            _dd('LOG LEVEL', ['debug', 'info', 'warning', 'error', 'none'], _patt.logLevel, (v) {
              setMs(() => _patt.logLevel = v);
              _savePatt();
            }),
            _dd('DNS', ['auto', 'doh', 'custom'], _patt.dnsMode, (v) {
              setMs(() => _patt.dnsMode = v);
              _savePatt();
            }),
            if (_patt.dnsMode == 'custom') _tf('CUSTOM DNS', _patt.customDns, (v) {
              _patt.customDns = v;
              _savePatt();
            }),
            // ---------------- REALITY ----------------
            _sw('REALITY', _patt.reality, (v) {
              setMs(() => _patt.reality = v);
              _savePatt();
            }),
            if (_patt.reality) ...[
              _tf('PBK', _patt.pbk, (v) {
                _patt.pbk = v.trim();
                _savePatt();
              }),
              _tf('SID', _patt.sid, (v) {
                _patt.sid = v.trim();
                _savePatt();
              }),
              _tf('SPX', _patt.spx, (v) {
                _patt.spx = v.trim();
                _savePatt();
              }),
            ],
            // ---------------- TRANSPORT ----------------
            _dd('FLOW (keep = node value)', ['keep', 'xtls-rprx-vision', 'none'], _patt.flow, (v) {
              setMs(() => _patt.flow = v);
              _savePatt();
            }),
            _dd('ALPN', ['', 'h2,http/1.1', 'h2', 'http/1.1'], _patt.alpn, (v) {
              setMs(() => _patt.alpn = v);
              _savePatt();
            }),
            _dd('NETWORK (tcp = keep node value)', ['tcp', 'ws', 'grpc', 'http', 'kcp', 'quic', 'httpupgrade', 'splithttp', 'xhttp'], _patt.network, (v) {
              setMs(() => _patt.network = v);
              _savePatt();
            }),
            _tf('SNI', _patt.sni, (v) {
              _patt.sni = v.trim();
              _savePatt();
            }),
            _tf('PATH', _patt.path, (v) {
              _patt.path = v.trim();
              _savePatt();
            }),
            _tf('HOST', _patt.host, (v) {
              _patt.host = v.trim();
              _savePatt();
            }),
            const SizedBox(height: 8),
          ])),
          _bigBtn('APPLY & SYNC', GREEN, () {
            Navigator.pop(ctx);
            _syncAll();
          }),
        ]));
      })).then((_) {
        // FIX: چیپ‌های صفحهٔ اصلی و لینک نودها با تنظیمات جدید بازسازی شوند
        if (!mounted) return;
        setState(() {
          _nodes = _nodes.map((n) => ServerNode(subTag: n.subTag, rawUri: _linkFor(n.baseUri), baseUri: n.baseUri, displayName: n.displayName, pingText: n.pingText, pingColor: n.pingColor)).toList();
        });
      });
    }

    // ============================================================
    //  MAIN BUILD
    // ============================================================
    @override
    Widget build(BuildContext context) {
      S
