  // lib/main.dart — ZEUS VPN
  import 'dart:async';
  import 'dart:convert';
  import 'dart:io';
  import 'dart:math';

  import 'package:dio/dio.dart';
  import 'package:flutter/material.dart';
  import 'package:flutter_v2ray_client/flutter_v2ray.dart';
  import 'package:shared_preferences/shared_preferences.dart';

  import 'warp.dart';

  // ───────────────────────── Theme ─────────────────────────
  const Color kCyan = Color(0xFF00F0FF);
  const Color kMagenta = Color(0xFFFF007F);
  const Color kGreen = Color(0xFF00FF88);
  const Color kAmber = Color(0xFFFFB800);
  const Color kBg = Color(0xFF030308);
  const Color kGlass = Color(0xFF0A0A14);

  const int kSocksPort = 10808;
  const int kHttpPort = 10809;
  const String kPingUrl = 'https://www.gstatic.com/generate_204';
  const String kSpeedUrl = 'https://speed.cloudflare.com/__down?bytes=15000000';

  void main() => runApp(const ZeusApp());

  class ZeusApp extends StatelessWidget {
    const ZeusApp({super.key});
    @override
    Widget build(BuildContext context) {
      return MaterialApp(
        title: 'ZEUS VPN',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kBg,
          colorScheme: const ColorScheme.dark(primary: kCyan, secondary: kMagenta, surface: kGlass),
          useMaterial3: true,
        ),
        home: const HomePage(),
      );
    }
  }

  // ───────────────────────── Models ─────────────────────────
  class ServerNode {
    final String subTag;
    final String rawUri;
    final String displayName;
    String pingText;
    Color pingColor;
    ServerNode({
      required this.subTag,
      required this.rawUri,
      required this.displayName,
      this.pingText = '--',
      this.pingColor = Colors.grey,
    });
  }

  class Patt {
    String fp = 'chrome';
    String cs = '';
    String pcs = '';
    String vcn = '';
    String frag = 'none'; // none | tlshello | 1-3 ...
    String fragLen = '100-200';
    String fragInt = '10-20';
    bool noise = false;
    String noiseType = 'rand';
    String noisePacket = '10-20';
    String noiseDelay = '10-20';
    bool mux = false;
    String muxConc = '8';
    bool bypassLan = true;
    String logLevel = 'warning';
    String dnsMode = 'auto'; // auto | custom | doh
    String customDns = '1.1.1.1';
    bool reality = false;
    String pbk = '';
    String sid = '';
    String spx = '/';
    String flow = 'xtls-rprx-vision';
    String alpn = 'h2,http/1.1';
    String sni = '';
    bool overrideStream = false;
    String network = 'tcp';
    String path = '/';
    String host = '';
    String headerType = 'none';
  }

  // ───────────────────────── Helpers ─────────────────────────
  String _fmtBytes(num b) {
    if (b < 1024) return '${b.toStringAsFixed(0)} B/s';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB/s';
    return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }

  List<String> _csv(String s) =>
      s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Map<String, dynamic> _deepCopy(Map m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  String? _tryB64Decode(String s) {
    try {
      var t = s.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
      while (t.length % 4 != 0) t += '=';
      final out = utf8.decode(base64Decode(t), allowMalformed: true);
      return out;
    } catch (_) {
      return null;
    }
  }

  bool _isSupported(String uri) {
    final u = uri.toLowerCase();
    return u.startsWith('vless://') ||
        u.startsWith('vmess://') ||
        u.startsWith('trojan://') ||
        u.startsWith('ss://') ||
        u.startsWith('socks://');
  }

  String _nameOf(String uri) {
    try {
      if (uri.toLowerCase().startsWith('vmess://')) {
        final j = _tryB64Decode(uri.substring(8));
        if (j != null) {
          final m = jsonDecode(j);
          if (m is Map && (m['ps'] ?? '').toString().isNotEmpty) return m['ps'].toString();
          if (m is Map) return '${m['add']}:${m['port']}';
        }
      }
      final i = uri.indexOf('#');
      if (i >= 0 && i < uri.length - 1) return Uri.decodeComponent(uri.substring(i + 1)).trim();
      final u = Uri.parse(uri);
      return '${u.host}:${u.port}';
    } catch (_) {
      return uri.length > 30 ? uri.substring(0, 30) : uri;
    }
  }

  /// host:port برای TCP ping
  (String, int)? _hostPort(String uri) {
    try {
      if (uri.toLowerCase().startsWith('vmess://')) {
        final j = _tryB64Decode(uri.substring(8));
        if (j == null) return null;
        final m = jsonDecode(j) as Map;
        return (m['add'].toString(), int.parse(m['port'].toString()));
      }
      final u = Uri.parse(uri);
      if (u.host.isEmpty || u.port == 0) return null;
      return (u.host, u.port);
    } catch (_) {
      return null;
    }
  }

  // ───────────────────────── Page ─────────────────────────
  class HomePage extends StatefulWidget {
    const HomePage({super.key});
    @override
    State<HomePage> createState() => _HomePageState();
  }

  class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
    final Dio _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));

    late final V2ray _v2ray;
    late final AnimationController _ringCtl;
    late final AnimationController _pulseCtl;

    List<String> _subs = <String>[];
    List<ServerNode> _nodes = <ServerNode>[];
    String? _selUri;
    final Patt _patt = Patt();
    WarpConfig? _warp;
    bool _warpOn = false;

    bool _ready = false;
    bool _loading = false;
    bool _connected = false;
    bool _connecting = false;
    bool _busy = false;
    bool _testing = false;
    bool _pinging = false;
    int _delayMode = 0; // 0 = real (core), 1 = tcp
    int _syncGen = 0;

    String _speed = '';
    String _up = '0 B/s';
    String _down = '0 B/s';
    String _dur = '00:00:00';
    CancelToken? _speedToken;

    // ───────── lifecycle ─────────
    @override
    void initState() {
      super.initState();
      _ringCtl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
      _pulseCtl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
      _v2ray = V2ray(onStatusChanged: _onStatus);
      _boot();
    }

    @override
    void dispose() {
      _ringCtl.dispose();
      _pulseCtl.dispose();
      _speedToken?.cancel();
      _dio.close(force: true);
      super.dispose();
    }

    void _onStatus(V2RayStatus s) {
      if (!mounted) return;
      final st = s.state.toUpperCase();
      setState(() {
        _connected = st == 'CONNECTED';
        _connecting = st == 'CONNECTING' || st == 'CONNECT';
        _up = _fmtBytes(s.uploadSpeed);
        _down = _fmtBytes(s.downloadSpeed);
        _dur = _connected ? s.duration : '00:00:00';
        if (!_connected && !_connecting) _speed = '';
      });
    }

    Future<void> _boot() async {
      final p = await SharedPreferences.getInstance();
      _subs = p.getStringList('subs') ?? <String>[];
      _selUri = p.getString('sel');
      _warpOn = p.getBool('warp_on') ?? false;
      _warp = WarpConfig.tryDecode(p.getString('warp_json'));
      _delayMode = p.getInt('delay_mode') ?? 0;
      _loadPatt(p);
      _loadNodeCache(p);

      bool coreOk = true;
      try {
        await _v2ray.initialize(
          notificationIconResourceType: 'mipmap',
          notificationIconResourceName: 'ic_launcher',
        );
      } catch (_) {
        coreOk = false;
      }
      if (!mounted) return;
      setState(() => _ready = coreOk);
      if (!coreOk) _snack('هستهٔ اتصال راه‌اندازی نشد.', err: true);
      if (_subs.isNotEmpty) _syncAll();
    }

    // ───────── prefs ─────────
    void _loadPatt(SharedPreferences p) {
      final x = _patt;
      x.fp = p.getString('p_fp') ?? x.fp;
      x.cs = p.getString('p_cs') ?? x.cs;
      x.pcs = p.getString('p_pcs') ?? x.pcs;
      x.vcn = p.getString('p_vcn') ?? x.vcn;
      x.frag = p.getString('p_frag') ?? x.frag;
      x.fragLen = p.getString('p_fl') ?? x.fragLen;
      x.fragInt = p.getString('p_fi') ?? x.fragInt;
      x.noise = p.getBool('p_noise') ?? x.noise;
      x.noiseType = p.getString('p_nt') ?? x.noiseType;
      x.noisePacket = p.getString('p_np') ?? x.noisePacket;
      x.noiseDelay = p.getString('p_nd') ?? x.noiseDelay;
      x.mux = p.getBool('p_mux') ?? x.mux;
      x.muxConc = p.getString('p_mc') ?? x.muxConc;
      x.bypassLan = p.getBool('p_lan') ?? x.bypassLan;
      x.logLevel = p.getString('p_log') ?? x.logLevel;
      x.dnsMode = p.getString('p_dns') ?? x.dnsMode;
      x.customDns = p.getString('p_dnsc') ?? x.customDns;
      x.reality = p.getBool('p_real') ?? x.reality;
      x.pbk = p.getString('p_pbk') ?? x.pbk;
      x.sid = p.getString('p_sid') ?? x.sid;
      x.spx = p.getString('p_spx') ?? x.spx;
      x.flow = p.getString('p_flow') ?? x.flow;
      x.alpn = p.getString('p_alpn') ?? x.alpn;
      x.sni = p.getString('p_sni') ?? x.sni;
      x.overrideStream = p.getBool('p_ovr') ?? x.overrideStream;
      x.network = p.getString('p_net') ?? x.network;
      x.path = p.getString('p_path') ?? x.path;
      x.host = p.getString('p_host') ?? x.host;
      x.headerType = p.getString('p_ht') ?? x.headerType;
    }

    Future<void> _savePatt() async {
      final p = await SharedPreferences.getInstance();
      final x = _patt;
      await p.setString('p_fp', x.fp);
      await p.setString('p_cs', x.cs);
      await p.setString('p_pcs', x.pcs);
      await p.setString('p_vcn', x.vcn);
      await p.setString('p_frag', x.frag);
      await p.setString('p_fl', x.fragLen);
      await p.setString('p_fi', x.fragInt);
      await p.setBool('p_noise', x.noise);
      await p.setString('p_nt', x.noiseType);
      await p.setString('p_np', x.noisePacket);
      await p.setString('p_nd', x.noiseDelay);
      await p.setBool('p_mux', x.mux);
      await p.setString('p_mc', x.muxConc);
      await p.setBool('p_lan', x.bypassLan);
      await p.setString('p_log', x.logLevel);
      await p.setString('p_dns', x.dnsMode);
      await p.setString('p_dnsc', x.customDns);
      await p.setBool('p_real', x.reality);
      await p.setString('p_pbk', x.pbk);
      await p.setString('p_sid', x.sid);
      await p.setString('p_spx', x.spx);
      await p.setString('p_flow', x.flow);
      await p.setString('p_alpn', x.alpn);
      await p.setString('p_sni', x.sni);
      await p.setBool('p_ovr', x.overrideStream);
      await p.setString('p_net', x.network);
      await p.setString('p_path', x.path);
      await p.setString('p_host', x.host);
      await p.setString('p_ht', x.headerType);
    }

    Future<void> _saveWarp() async {
      final p = await SharedPreferences.getInstance();
      await p.setBool('warp_on', _warpOn);
      await p.setString('warp_json', _warp?.encode() ?? '');
    }

    Future<void> _saveSubs() async {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('subs', _subs);
    }

    Future<void> _saveSel() async {
      final p = await SharedPreferences.getInstance();
      if (_selUri == null) {
        await p.remove('sel');
      } else {
        await p.setString('sel', _selUri!);
      }
    }

    void _loadNodeCache(SharedPreferences p) {
      try {
        final raw = p.getString('nodes_cache');
        if (raw == null || raw.isEmpty) return;
        final list = jsonDecode(raw) as List;
        _nodes = list
            .map((e) => ServerNode(
                  subTag: (e['t'] ?? '').toString(),
                  rawUri: (e['u'] ?? '').toString(),
                  displayName: _nameOf((e['u'] ?? '').toString()),
                ))
            .where((n) => n.rawUri.isNotEmpty)
            .toList();
      } catch (_) {}
    }

    Future<void> _saveNodeCache() async {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        'nodes_cache',
        jsonEncode(_nodes.map((n) => <String, String>{'t': n.subTag, 'u': n.rawUri}).toList()),
      );
    }

    // ───────── subscriptions ─────────
    Future<List<String>> _fetchSub(String url) async {
      final r = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain, headers: {'User-Agent': 'v2rayNG/1.8.0'}),
      );
      final body = (r.data ?? '').trim();
      if (body.isEmpty) return <String>[];
      String text = body;
      if (!body.contains('://')) {
        final d = _tryB64Decode(body);
        if (d != null && d.contains('://')) text = d;
      }
      return text
          .split(RegExp(r'[\r\n]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && _isSupported(e))
          .toList();
    }

    Future<void> _syncAll() async {
      if (_subs.isEmpty) return;
      final gen = ++_syncGen;
      setState(() => _loading = true);

      final results = await Future.wait(_subs.map((u) async {
        try {
          return await _fetchSub(u);
        } catch (_) {
          return <String>[];
        }
      }));
      if (!mounted || gen != _syncGen) return;

      final fresh = <ServerNode>[];
      int okCount = 0;
      for (int i = 0; i < _subs.length; i++) {
        final list = results[i];
        if (list.isNotEmpty) okCount++;
        final tag = 'S${i + 1}';
        for (final uri in list) {
          fresh.add(ServerNode(subTag: tag, rawUri: uri, displayName: _nameOf(uri)));
        }
      }

      if (fresh.isEmpty) {
        setState(() => _loading = false);
        _snack('هیچ سروری دریافت نشد؛ از کش استفاده می‌شود.', err: true);
        return;
      }

      // ping قدیمی را نگه دار
      final oldPing = {for (final n in _nodes) n.rawUri: n};
      for (final n in fresh) {
        final o = oldPing[n.rawUri];
        if (o != null) {
          n.pingText = o.pingText;
          n.pingColor = o.pingColor;
        }
      }

      setState(() {
        _nodes = fresh;
        _loading = false;
        if (_selUri != null && !_nodes.any((n) => n.rawUri == _selUri)) _selUri = null;
      });
      await _saveNodeCache();
      await _saveSel();
      if (okCount < _subs.length) _snack('${_subs.length - okCount} اشتراک دریافت نشد.', err: true);
    }

    // ───────── config builder ─────────
    List<Map<String, dynamic>> _inbounds() => <Map<String, dynamic>>[
          <String, dynamic>{
            'tag': 'socks',
            'port': kSocksPort,
            'listen': '127.0.0.1',
            'protocol': 'socks',
            'settings': <String, dynamic>{'auth': 'noauth', 'udp': true},
            'sniffing': <String, dynamic>{'enabled': true, 'destOverride': <String>['http', 'tls', 'quic']},
          },
          <String, dynamic>{
            'tag': 'http',
            'port': kHttpPort,
            'listen': '127.0.0.1',
            'protocol': 'http',
            'settings': <String, dynamic>{},
          },
        ];

    Map<String, dynamic> _dns() {
      switch (_patt.dnsMode) {
        case 'custom':
          final servers = _csv(_patt.customDns);
          return <String, dynamic>{'servers': servers.isEmpty ? <String>['1.1.1.1'] : servers};
        case 'doh':
          return <String, dynamic>{
            'servers': <String>['https://1.1.1.1/dns-query', 'https://dns.google/dns-query', '8.8.8.8'],
            'queryStrategy': 'UseIP',
          };
        default:
          return <String, dynamic>{'servers': <String>['1.1.1.1', '8.8.8.8', 'localhost']};
      }
    }

    Map<String, dynamic> _routing() {
      final rules = <Map<String, dynamic>>[];
      if (_patt.bypassLan) {
        rules.add(<String, dynamic>{
          'type': 'field',
          'ip': <String>[
            '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '127.0.0.0/8',
            '169.254.0.0/16', '100.64.0.0/10', 'fc00::/7', 'fe80::/10', '::1/128',
          ],
          'outboundTag': 'direct',
        });
        rules.add(<String, dynamic>{
          'type': 'field',
          'domain': <String>['regexp:.*\\.local\$', 'domain:localhost'],
          'outboundTag': 'direct',
        });
      }
      return <String, dynamic>{'domainStrategy': 'IPIfNonMatch', 'rules': rules};
    }

    Map<String, dynamic> _directOut() => <String, dynamic>{
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': <String, dynamic>{'domainStrategy': 'UseIP'},
        };

    Map<String, dynamic> _blockOut() => <String, dynamic>{
          'tag': 'block',
          'protocol': 'blackhole',
          'settings': <String, dynamic>{'response': <String, dynamic>{'type': 'http'}},
        };

    Map<String, dynamic>? _fragmentOut() {
      final fragOn = _patt.frag.isNotEmpty && _patt.frag != 'none';
      if (!fragOn && !_patt.noise) return null;
      final settings = <String, dynamic>{'domainStrategy': 'UseIP'};
      if (fragOn) {
        settings['fragment'] = <String, dynamic>{
          'packets': _patt.frag,
          'length': _patt.fragLen,
          'interval': _patt.fragInt,
        };
      }
      if (_patt.noise) {
        settings['noises'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'type': _patt.noiseType,
            'packet': _patt.noisePacket,
            'delay': _patt.noiseDelay,
          },
        ];
      }
      return <String, dynamic>{
        'tag': 'fragment',
        'protocol': 'freedom',
        'settings': settings,
        'streamSettings': <String, dynamic>{
          'sockopt': <String, dynamic>{'tcpNoDelay': true, 'tcpKeepAliveIdle': 100},
        },
      };
    }

    void _applyTls(Map<String, dynamic> ss) {
      final sec = (ss['security'] ?? 'none').toString();
      if (_patt.reality) {
        ss['security'] = 'reality';
        ss.remove('tlsSettings');
        final old = (ss['realitySettings'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        ss['realitySettings'] = <String, dynamic>{
          ...old,
          if (_patt.sni.isNotEmpty) 'serverName': _patt.sni,
          if (_patt.fp.isNotEmpty) 'fingerprint': _patt.fp,
          if (_patt.pbk.isNotEmpty) 'publicKey': _patt.pbk,
          if (_patt.sid.isNotEmpty) 'shortId': _patt.sid,
          if (_patt.spx.isNotEmpty) 'spiderX': _patt.spx,
        };
        return;
      }
      if (sec == 'tls') {
        final tls = (ss['tlsSettings'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        if (_patt.fp.isNotEmpty) tls['fingerprint'] = _patt.fp;
        if (_patt.sni.isNotEmpty) tls['serverName'] = _patt.sni;
        if (_patt.cs.isNotEmpty) tls['cipherSuites'] = _patt.cs;
        if (_patt.pcs.isNotEmpty) tls['pinnedPeerCertificateChainSha256'] = _csv(_patt.pcs);
        if (_patt.vcn.isNotEmpty) tls['verifyPeerCertInNames'] = _csv(_patt.vcn);
        if (_patt.overrideStream && _patt.alpn.isNotEmpty) tls['alpn'] = _csv(_patt.alpn);
        ss['tlsSettings'] = tls;
      } else if (sec == 'reality') {
        final r = (ss['realitySettings'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        if (_patt.fp.isNotEmpty) r['fingerprint'] = _patt.fp;
        ss['realitySettings'] = r;
      }
    }

    void _applyTransport(Map<String, dynamic> ss) {
      if (!_patt.overrideStream) return;
      final net = _patt.network;
      ss['network'] = net;
      for (final k in ['wsSettings', 'grpcSettings', 'tcpSettings', 'httpupgradeSettings', 'xhttpSettings', 'kcpSettings']) {
        ss.remove(k);
      }
      switch (net) {
        case 'ws':
          ss['wsSettings'] = <String, dynamic>{
            'path': _patt.path,
            if (_patt.host.isNotEmpty) 'headers': <String, dynamic>{'Host': _patt.host},
          };
          break;
        case 'grpc':
          ss['grpcSettings'] = <String, dynamic>{'serviceName': _patt.path.replaceFirst('/', '')};
          break;
        case 'httpupgrade':
          ss['httpupgradeSettings'] = <String, dynamic>{'path': _patt.path, if (_patt.host.isNotEmpty) 'host': _patt.host};
          break;
        case 'xhttp':
          ss['xhttpSettings'] = <String, dynamic>{'path': _patt.path, if (_patt.host.isNotEmpty) 'host': _patt.host};
          break;
        default: // tcp
          if (_patt.headerType == 'http') {
            ss['tcpSettings'] = <String, dynamic>{
              'header': <String, dynamic>{
                'type': 'http',
                'request': <String, dynamic>{
                  'path': <String>[_patt.path],
                  'headers': <String, dynamic>{
                    if (_patt.host.isNotEmpty) 'Host': <String>[_patt.host],
                  },
                },
              },
            };
          }
      }
    }

    void _applyFlow(Map<String, dynamic> main) {
      if (!_patt.reality || main['protocol'] != 'vless') return;
      final settings = (main['settings'] as Map?)?.cast<String, dynamic>();
      final vnext = (settings?['vnext'] as List?)?.cast<Map>();
      if (vnext == null) return;
      for (final v in vnext) {
        final users = (v['users'] as List?)?.cast<Map>();
        if (users == null) continue;
        for (final u in users) {
          u['flow'] = _patt.flow;
        }
      }
    }

    Map<String, dynamic> _buildConfig(String uri) {
      final parsed = V2ray.parseFromURL(uri);
      final cfg = _deepCopy(jsonDecode(parsed.getFullConfiguration()) as Map);

      final outs = ((cfg['outbounds'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      if (outs.isEmpty) throw Exception('کانفیگ نامعتبر است');

      final main = outs.first;
      main['tag'] = 'proxy';
      final ss = (main['streamSettings'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      _applyTransport(ss);
      _applyTls(ss);
      _applyFlow(main);

      if (_patt.mux) {
        main['mux'] = <String, dynamic>{
          'enabled': true,
          'concurrency': int.tryParse(_patt.muxConc) ?? 8,
        };
      } else {
        main.remove('mux');
      }

      final result = <Map<String, dynamic>>[main];
      final sockopt = (ss['sockopt'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

      final frag = _fragmentOut();
      final warpOn = _warpOn && (_warp?.isValid ?? false);

      if (frag != null) {
        sockopt['dialerProxy'] = 'fragment';
        if (warpOn) {
          (frag['streamSettings'] as Map<String, dynamic>)['sockopt'] = <String, dynamic>{'dialerProxy': 'warp'};
        }
        result.add(frag);
      } else if (warpOn) {
        sockopt['dialerProxy'] = 'warp';
      }
      if (warpOn) result.add(_warp!.toXrayOutbound(tag: 'warp'));

      if (sockopt.isNotEmpty) ss['sockopt'] = sockopt;
      main['streamSettings'] = ss;

      result.add(_directOut());
      result.add(_blockOut());

      cfg['log'] = <String, dynamic>{'loglevel': _patt.logLevel};
      cfg['inbounds'] = _inbounds();
      cfg['outbounds'] = result;
      cfg['dns'] = _dns();
      cfg['routing'] = _routing();
      cfg.remove('stats');
      cfg.remove('policy');
      return cfg;
    }

    Map<String, dynamic> _buildWarpOnlyConfig() {
      final w = _warp;
      if (w == null || !w.isValid) throw Exception('WARP ثبت نشده است');
      return <String, dynamic>{
        'log': <String, dynamic>{'loglevel': _patt.logLevel},
        'inbounds': _inbounds(),
        'outbounds': <Map<String, dynamic>>[w.toXrayOutbound(tag: 'proxy'), _directOut(), _blockOut()],
        'dns': _dns(),
        'routing': _routing(),
      };
    }

    // ───────── connection ─────────
    Future<void> _toggle() async {
      if (!_ready || _busy) return;

      if (_connected || _connecting) {
        setState(() => _busy = true);
        try {
          await _v2ray.stopV2Ray();
        } catch (_) {}
        if (mounted) {
          setState(() {
            _busy = false;
            _connecting = false;
            _connected = false;
          });
        }
        return;
      }

      final warpOnly = _selUri == null && _warpOn && (_warp?.isValid ?? false);
      if (_selUri == null && !warpOnly) {
        _snack('اول یک سرور انتخاب کنید', err: true);
        return;
      }

      setState(() => _busy = true);
      try {
        final ok = await _v2ray.requestPermission();
        if (!ok) throw Exception('مجوز VPN داده نشد');
        final cfg = warpOnly ? _buildWarpOnlyConfig() : _buildConfig(_selUri!);
        final remark = warpOnly ? 'ZEUS • WARP' : (_nodeOf(_selUri!)?.displayName ?? 'ZEUS');
        if (mounted) setState(() => _connecting = true);
        await _v2ray.startV2Ray(remark: remark, config: jsonEncode(cfg), proxyOnly: false);
      } catch (e) {
        _snack('اتصال ناموفق: $e', err: true);
        if (mounted) setState(() => _connecting = false);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    ServerNode? _nodeOf(String uri) {
      for (final n in _nodes) {
        if (n.rawUri == uri) return n;
      }
      return null;
    }

    // ───────── ping ─────────
    Future<int> _realDelay(ServerNode n) async {
      final cfg = _buildConfig(n.rawUri);
      return await _v2ray.getServerDelay(config: jsonEncode(cfg), url: kPingUrl);
    }

    Future<int> _tcpDelay(ServerNode n) async {
      final hp = _hostPort(n.rawUri);
      if (hp == null) return -1;
      final sw = Stopwatch()..start();
      try {
        final s = await Socket.connect(hp.$1, hp.$2, timeout: const Duration(seconds: 5));
        s.destroy();
        return sw.elapsedMilliseconds;
      } catch (_) {
        return -1;
      }
    }

    Future<void> _pingOne(ServerNode n) async {
      if (!mounted) return;
      setState(() {
        n.pingText = '...';
        n.pingColor = kAmber;
      });
      int ms = -1;
      try {
        ms = _delayMode == 0 ? await _realDelay(n) : await _tcpDelay(n);
      } catch (_) {
        ms = -1;
      }
      if (!mounted) return;
      setState(() {
        if (ms < 0) {
          n.pingText = 'timeout';
          n.pingColor = kMagenta;
        } else {
          n.pingText = '$ms ms';
          n.pingColor = ms < 400 ? kGreen : (ms < 1000 ? kAmber : kMagenta);
        }
      });
    }

    Future<void> _pingAll() async {
      if (_pinging || _nodes.isEmpty) return;
      setState(() => _pinging = true);
      final queue = List<ServerNode>.from(_nodes);
      const workers = 4;
      Future<void> worker() async {
        while (queue.isNotEmpty && mounted) {
          final n = queue.removeAt(0);
          await _pingOne(n);
        }
      }
      await Future.wait(List.generate(workers, (_) => worker()));
      if (mounted) setState(() => _pinging = false);
    }

    // ───────── speed test ─────────
    Future<void> _speedTest() async {
      if (!_connected || _testing) return;
      setState(() {
        _testing = true;
        _speed = 'testing...';
      });
      _speedToken = CancelToken();
      final sw = Stopwatch()..start();
      try {
        final r = await _dio.get<List<int>>(
          kSpeedUrl,
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 40)),
          cancelToken: _speedToken,
        );
        sw.stop();
        final bytes = r.data?.length ?? 0;
        final sec = max(sw.elapsedMilliseconds, 1) / 1000.0;
        final mbps = (bytes * 8) / sec / 1e6;
        if (mounted) setState(() => _speed = '${mbps.toStringAsFixed(1)} Mbps');
      } catch (e) {
        if (mounted) setState(() => _speed = 'failed');
      } finally {
        if (mounted) setState(() => _testing = false);
      }
    }

    // ───────── WARP ─────────
    Future<void> _registerWarp() async {
      if (_busy) return;
      setState(() => _busy = true);
      try {
        final cfg = await registerWarp(
          proxyPort: _connected ? kHttpPort : null,
          preferredEndpoint: _warp?.endpoint,
        );
        _warp = cfg;
        await _saveWarp();
        _snack('WARP ثبت شد ✓');
      } on WarpException catch (e) {
        _snack(e.message, err: true);
      } catch (e) {
        _snack('خطای WARP: $e', err: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    // ───────── UI utils ─────────
    void _snack(String msg, {bool err = false}) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: err ? kMagenta.withValues(alpha: 0.85) : kGlass,
        behavior: SnackBarBehavior.floating,
      ));
    }

    Color get _stateColor => _connected ? kGreen : (_connecting ? kAmber : kCyan);
    String get _stateText {
      if (_busy && !_connected && !_connecting) return 'WORKING';
      if (_connected) return 'CONNECTED';
      if (_connecting) return 'CONNECTING…';
      return _ready ? 'DISCONNECTED' : 'CORE ERROR';
    }

    // ───────── build ─────────
    @override
    Widget build(BuildContext context) {
      final sel = _selUri == null ? null : _nodeOf(_selUri!);
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              const SizedBox(height: 8),
              _powerRing(),
              const SizedBox(height: 10),
              Text(_stateText,
                  style: TextStyle(color: _stateColor, fontSize: 14, letterSpacing: 3, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              _statsRow(),
              const SizedBox(height: 8),
              _selectedCard(sel),
              const Divider(color: Colors.white12, height: 16),
              Expanded(child: _nodeList()),
              _bottomBar(),
            ],
          ),
        ),
      );
    }

    Widget _header() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('ZEUS',
                  style: TextStyle(color: kCyan, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 6)),
              const SizedBox(width: 6),
              const Text('VPN', style: TextStyle(color: kMagenta, fontSize: 14, letterSpacing: 3)),
              const Spacer(),
              IconButton(
                tooltip: 'WARP',
                icon: Icon(Icons.cloud_outlined, color: _warpOn ? kGreen : Colors.white54),
                onPressed: _showWarpSheet,
              ),
              IconButton(
                tooltip: 'Subscriptions',
                icon: const Icon(Icons.link, color: Colors.white70),
                onPressed: _showSubsDialog,
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.tune, color: Colors.white70),
                onPressed: _showSettingsSheet,
              ),
            ],
          ),
        );

    Widget _powerRing() {
      return GestureDetector(
        onTap: _toggle,
        child: AnimatedBuilder(
          animation: Listenable.merge([_ringCtl, _pulseCtl]),
          builder: (_, __) {
            final scale = _connected ? 1 + 0.03 * sin(_pulseCtl.value * pi) : 1.0;
            return Transform.scale(
              scale: scale,
              child: SizedBox(
                width: 190,
                height: 190,
                child: CustomPaint(
                  painter: _RingPainter(
                    progress: _ringCtl.value,
                    color: _stateColor,
                    spinning: _connecting || _busy,
                  ),
                  child: Center(
                    child: Icon(Icons.power_settings_new, size: 72, color: _stateColor),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    Widget _statsRow() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat(Icons.arrow_upward, _up, kMagenta),
              _stat(Icons.timer_outlined, _dur, kCyan),
              _stat(Icons.arrow_downward, _down, kGreen),
            ],
          ),
        );

    Widget _stat(IconData i, String v, Color c) => Row(
          children: [
            Icon(i, size: 16, color: c),
            const SizedBox(width: 4),
            Text(v, style: TextStyle(color: c, fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        );

    Widget _selectedCard(ServerNode? sel) {
      final warpOnly = sel == null && _warpOn && (_warp?.isValid ?? false);
      final title = sel?.displayName ?? (warpOnly ? 'WARP (standalone)' : 'No server selected');
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: kGlass,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kCyan.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(warpOnly ? Icons.cloud : Icons.dns_outlined, color: kCyan, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
            if (_warpOn && sel != null)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text('+WARP', style: TextStyle(color: kGreen, fontSize: 11)),
              ),
            if (_speed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(_speed, style: const TextStyle(color: kAmber, fontSize: 12)),
              ),
          ],
        ),
      );
    }

    Widget _nodeList() {
      if (_loading && _nodes.isEmpty) {
        return const Center(child: CircularProgressIndicator(color: kCyan));
      }
      if (_nodes.isEmpty) {
        return Center(
          child: TextButton.icon(
            onPressed: _showSubsDialog,
            icon: const Icon(Icons.add_link, color: kCyan),
            label: const Text('افزودن اشتراک', style: TextStyle(color: kCyan)),
          ),
        );
      }
      return RefreshIndicator(
        color: kCyan,
        onRefresh: _syncAll,
        child: ListView.builder(
          itemCount: _nodes.length,
          itemBuilder: (_, i) {
            final n = _nodes[i];
            final selected = n.rawUri == _selUri;
            return ListTile(
              dense: true,
              selected: selected,
              selectedTileColor: kCyan.withValues(alpha: 0.08),
              leading: Container(
                width: 34,
                alignment: Alignment.center,
                child: Text(n.subTag, style: const TextStyle(color: kMagenta, fontSize: 11)),
              ),
              title: Text(n.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: selected ? kCyan : Colors.white, fontSize: 13)),
              trailing: InkWell(
                onTap: () => _pingOne(n),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(n.pingText, style: TextStyle(color: n.pingColor, fontSize: 12)),
                ),
              ),
              onTap: () async {
                setState(() => _selUri = n.rawUri);
                await _saveSel();
              },
            );
          },
        ),
      );
    }

    Widget _bottomBar() => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pinging ? null : _pingAll,
                  icon: _pinging
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kCyan))
                      : const Icon(Icons.network_check, size: 18),
                  label: Text(_delayMode == 0 ? 'Ping (real)' : 'Ping (tcp)'),
                  onLongPress: () async {
                    setState(() => _delayMode = _delayMode == 0 ? 1 : 0);
                    final p = await SharedPreferences.getInstance();
                    await p.setInt('delay_mode', _delayMode);
                    _snack(_delayMode == 0 ? 'حالت پینگ: واقعی (core)' : 'حالت پینگ: TCP');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_connected && !_testing) ? _speedTest : null,
                  icon: const Icon(Icons.speed, size: 18),
                  label: const Text('Speed'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: _loading ? null : _syncAll,
                icon: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kCyan))
                    : const Icon(Icons.refresh, color: kCyan),
              ),
            ],
          ),
        );

    // ───────── dialogs / sheets ─────────
    Future<void> _showSubsDialog() async {
      final ctl = TextEditingController();
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            backgroundColor: kGlass,
            title: const Text('Subscriptions', style: TextStyle(color: kCyan)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._subs.asMap().entries.map((e) => ListTile(
                        dense: true,
                        title: Text('S${e.key + 1}  ${e.value}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: kMagenta, size: 20),
                          onPressed: () async {
                            _subs.removeAt(e.key);
                            await _saveSubs();
                            setD(() {});
                            if (mounted) setState(() {});
                          },
                        ),
                      )),
                  TextField(
                    controller: ctl,
                    decoration: const InputDecoration(hintText: 'https://… subscription URL'),
                    keyboardType: TextInputType.url,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              FilledButton(
                onPressed: () async {
                  final u = ctl.text.trim();
                  if (u.isEmpty || !u.startsWith('http')) return;
                  if (!_subs.contains(u)) _subs.add(u);
                  await _saveSubs();
                  if (ctx.mounted) Navigator.pop(ctx);
                  _syncAll();
                },
                child: const Text('Add & Sync'),
              ),
            ],
          ),
        ),
      );
      ctl.dispose();
    }

    Future<void> _showWarpSheet() async {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: kGlass,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) {
            final w = _warp;
            final ep = (w != null && kWarpEndpoints.contains(w.endpoint)) ? w.endpoint : kWarpEndpoints.first;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Cloudflare WARP', style: TextStyle(color: kCyan, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    w == null || !w.isValid ? 'ثبت نشده' : 'ثبت شده • ${w.addressV4}\n${w.registeredAt}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('فعال‌سازی WARP'),
                    subtitle: const Text('با سرور: Proxy→WARP • بدون سرور: فقط WARP', style: TextStyle(fontSize: 11)),
                    value: _warpOn,
                    activeColor: kGreen,
                    onChanged: (v) async {
                      _warpOn = v;
                      await _saveWarp();
                      setS(() {});
                      if (mounted) setState(() {});
                    },
                  ),
                  DropdownButtonFormField<String>(
                    value: ep,
                    decoration: const InputDecoration(labelText: 'Endpoint'),
                    items: kWarpEndpoints.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      if (_warp != null) {
                        _warp = _warp!.copyWith(endpoint: v);
                        await _saveWarp();
                      }
                      setS(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            await _registerWarp();
                            setS(() {});
                          },
                    icon: const Icon(Icons.vpn_key_outlined),
                    label: Text(w == null ? 'ثبت‌نام WARP' : 'ثبت‌نام مجدد'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _connected ? 'ثبت‌نام از طریق سرور متصل انجام می‌شود' : 'اگر 403 گرفتید، اول به یک سرور وصل شوید',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
      );
      if (mounted) setState(() {});
    }

    Future<void> _showSettingsSheet() async {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: kGlass,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) {
            final x = _patt;
            Widget tf(String label, String v, void Function(String) on, {String? hint}) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: TextFormField(
                    initialValue: v,
                    decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (s) {
                      on(s.trim());
                      _savePatt();
                    },
                  ),
                );
            Widget dd(String label, String v, List<String> items, void Function(String) on) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: DropdownButtonFormField<String>(
                    value: items.contains(v) ? v : items.first,
                    decoration: InputDecoration(labelText: label, isDense: true),
                    items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (s) {
                      if (s == null) return;
                      on(s);
                      _savePatt();
                      setS(() {});
                    },
                  ),
                );
            Widget sw(String label, bool v, void Function(bool) on) => SwitchListTile(
                  dense: true,
                  title: Text(label, style: const TextStyle(fontSize: 13)),
                  value: v,
                  activeColor: kCyan,
                  onChanged: (b) {
                    on(b);
                    _savePatt();
                    setS(() {});
                  },
                );
            Widget sec(String t) => Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 2),
                  child: Text(t, style: const TextStyle(color: kMagenta, fontSize: 12, letterSpacing: 2)),
                );

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.85,
              maxChildSize: 0.95,
              builder: (_, sc) => ListView(
                controller: sc,
                padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
                children: [
                  const Text('PattNG Settings', style: TextStyle(color: kCyan, fontSize: 18, fontWeight: FontWeight.bold)),
                  sec('GENERAL'),
                  dd('Log level', x.logLevel, const ['none', 'error', 'warning', 'info', 'debug'], (v) => x.logLevel = v),
                  sw('Bypass LAN', x.bypassLan, (v) => x.bypassLan = v),
                  dd('DNS', x.dnsMode, const ['auto', 'custom', 'doh'], (v) => x.dnsMode = v),
                  if (x.dnsMode == 'custom') tf('Custom DNS (comma)', x.customDns, (v) => x.customDns = v),

                  sec('TLS'),
                  dd('Fingerprint', x.fp,
                      const ['chrome', 'firefox', 'safari', 'ios', 'android', 'edge', 'random', 'randomized', 'unsafe'],
                      (v) => x.fp = v),
                  tf('SNI override', x.sni, (v) => x.sni = v, hint: 'empty = from link'),
                  tf('Cipher suites', x.cs, (v) => x.cs = v, hint: 'TLS_AES_128_GCM_SHA256:…'),
                  tf('Pinned cert SHA256 (comma)', x.pcs, (v) => x.pcs = v),
                  tf('verifyPeerCertInNames (comma)', x.vcn, (v) => x.vcn = v),

                  sec('FRAGMENT / NOISE'),
                  dd('Fragment packets', x.frag, const ['none', 'tlshello', '1-1', '1-2', '1-3', '1-5'], (v) => x.frag = v),
                  if (x.frag != 'none') tf('Length', x.fragLen, (v) => x.fragLen = v),
                  if (x.frag != 'none') tf('Interval', x.fragInt, (v) => x.fragInt = v),
                  sw('Noise', x.noise, (v) => x.noise = v),
                  if (x.noise) dd('Noise type', x.noiseType, const ['rand', 'str', 'base64'], (v) => x.noiseType = v),
                  if (x.noise) tf('Noise packet', x.noisePacket, (v) => x.noisePacket = v, hint: x.noiseType == 'rand' ? '10-20' : 'text'),
                  if (x.noise) tf('Noise delay', x.noiseDelay, (v) => x.noiseDelay = v),

                  sec('MUX'),
                  sw('Mux', x.mux, (v) => x.mux = v),
                  if (x.mux) tf('Concurrency', x.muxConc, (v) => x.muxConc = v),

                  sec('REALITY (override)'),
                  sw('Force REALITY', x.reality, (v) => x.reality = v),
                  if (x.reality) tf('publicKey', x.pbk, (v) => x.pbk = v),
                  if (x.reality) tf('shortId', x.sid, (v) => x.sid = v),
                  if (x.reality) tf('spiderX', x.spx, (v) => x.spx = v),
                  if (x.reality) dd('flow', x.flow, const ['xtls-rprx-vision', ''], (v) => x.flow = v),

                  sec('TRANSPORT (override)'),
                  sw('Override transport from link', x.overrideStream, (v) => x.overrideStream = v),
                  if (x.overrideStream) dd('Network', x.network, const ['tcp', 'ws', 'grpc', 'httpupgrade', 'xhttp'], (v) => x.network = v),
                  if (x.overrideStream && x.network == 'tcp') dd('Header type', x.headerType, const ['none', 'http'], (v) => x.headerType = v),
                  if (x.overrideStream) tf('Path / serviceName', x.path, (v) => x.path = v),
                  if (x.overrideStream) tf('Host', x.host, (v) => x.host = v),
                  if (x.overrideStream) tf('ALPN (comma)', x.alpn, (v) => x.alpn = v),
                  const SizedBox(height: 12),
                  const Text('تغییرات بعد از اتصال مجدد اعمال می‌شوند.',
                      style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center),
                ],
              ),
            );
          },
        ),
      );
      if (mounted) setState(() {});
    }
  }

  // ───────────────────────── Ring painter ─────────────────────────
  class _RingPainter extends CustomPainter {
    final double progress;
    final Color color;
    final bool spinning;
    _RingPainter({required this.progress, required this.color, required this.spinning});

    @override
    void paint(Canvas canvas, Size size) {
      final c = size.center(Offset.zero);
      final r = size.width / 2 - 6;

      final base = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: 0.18);
      canvas.drawCircle(c, r, base);
      canvas.drawCircle(c, r - 14, base..strokeWidth = 1);

      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      final start = progress * 2 * pi;
      final sweep = spinning ? pi * 0.5 : pi * 1.6;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, false, glow);

      final tick = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: 0.45);
      for (int i = 0; i < 24; i++) {
        final a = i * (2 * pi / 24) - start * 0.5;
        final p1 = c + Offset(cos(a), sin(a)) * (r - 20);
        final p2 = c + Offset(cos(a), sin(a)) * (r - 26);
        canvas.drawLine(p1, p2, tick);
      }
    }

    @override
    bool shouldRepaint(covariant _RingPainter old) =>
        old.progress != progress || old.color != color || old.spinning != spinning;
  }
