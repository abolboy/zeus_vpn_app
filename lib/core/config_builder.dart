// lib/core/config_builder.dart — ساخت کانفیگ Xray از لینک + PattNG + WARP
import 'dart:convert';

import 'package:flutter_v2ray_client/flutter_v2ray.dart';

import '../warp.dart';
import 'models.dart';

const int kSocksPort = 10808;
const int kHttpPort = 10809;

class ConfigBuilder {
  final Patt patt;
  final WarpConfig? warp;
  final bool warpOn;
  ConfigBuilder({required this.patt, this.warp, this.warpOn = false});

  bool get _warpReady => warpOn && (warp?.isValid ?? false);

  // ───────── public ─────────

  /// کانفیگ کامل برای یک لینک سرور
  Map<String, dynamic> build(String uri) {
    final parsed = V2ray.parseFromURL(uri);
    final cfg = _deepCopy(jsonDecode(parsed.getFullConfiguration()) as Map);

    final outs = ((cfg['outbounds'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    if (outs.isEmpty) throw Exception('کانفیگ نامعتبر است');

    final main = outs.first..['tag'] = 'proxy';
    final ss = (main['streamSettings'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    _applyTransport(ss);
    _applyTls(ss, (main['protocol'] ?? '').toString());
    _applyFlow(main);
    _applyMux(main);

    final result = <Map<String, dynamic>>[main];
    final sockopt = (ss['sockopt'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final frag = _fragmentOut();

    if (frag != null) {
      sockopt['dialerProxy'] = 'fragment';
      if (_warpReady) {
        (frag['streamSettings'] as Map<String, dynamic>)['sockopt'] = {'dialerProxy': 'warp'};
      }
      result.add(frag);
    } else if (_warpReady) {
      sockopt['dialerProxy'] = 'warp';
    }
    if (_warpReady) result.add(warp!.toXrayOutbound(tag: 'warp'));
    if (sockopt.isNotEmpty) ss['sockopt'] = sockopt;
    main['streamSettings'] = ss;

    result
      ..add(_dnsOut())
      ..add(_directOut())
      ..add(_blockOut());
    return _wrap(cfg, result);
  }

  /// فقط WARP (بدون سرور)
  Map<String, dynamic> buildWarpOnly() {
    final w = warp;
    if (w == null || !w.isValid) throw Exception('WARP ثبت نشده است');
    return _wrap(<String, dynamic>{}, [w.toXrayOutbound(tag: 'proxy'), _dnsOut(), _directOut(), _blockOut()]);
  }

  /// کانفیگ سبک برای تست پینگ (بدون WARP و بدون stats)
  Map<String, dynamic> buildForPing(String uri) {
    final cfg = ConfigBuilder(patt: patt).build(uri);
    cfg.remove('stats');
    cfg.remove('policy');
    return cfg;
  }

  // ───────── wrapper ─────────
  Map<String, dynamic> _wrap(Map<String, dynamic> cfg, List<Map<String, dynamic>> outbounds) {
    cfg['log'] = {'loglevel': _safeLogLevel()};
    cfg['inbounds'] = _inbounds();
    cfg['outbounds'] = outbounds;
    cfg['dns'] = _dns();
    cfg['routing'] = _routing();
    // پلاگین برای آمار حجم به stats + policy نیاز دارد
    cfg['stats'] = <String, dynamic>{};
    cfg['policy'] = {
      'levels': {'0': {'handshake': 4, 'connIdle': 300, 'uplinkOnly': 1, 'downlinkOnly': 1}},
      'system': {'statsOutboundUplink': true, 'statsOutboundDownlink': true},
    };
    return cfg;
  }

  /// سطح debug مقصد همهٔ اتصالات را در Logcat می‌نویسد؛ به‌جای حذف، به info محدود می‌شود
  String _safeLogLevel() {
    const allowed = ['none', 'error', 'warning', 'info'];
    return allowed.contains(patt.logLevel) ? patt.logLevel : 'info';
  }

  // ───────── parts ─────────
  List<Map<String, dynamic>> _inbounds() => [
        {
          'tag': 'socks',
          'port': kSocksPort,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true},
          'sniffing': {'enabled': true, 'destOverride': ['http', 'tls', 'quic'], 'routeOnly': false},
        },
        {
          'tag': 'http',
          'port': kHttpPort,
          'listen': '127.0.0.1',
          'protocol': 'http',
          'settings': <String, dynamic>{},
        },
      ];

  /// ✅ DNS از طریق ماژول Xray: DoH (TCP) اول، UDP بعد → روی سرورهای بدون UDP هم کار می‌کند
  /// و همهٔ پرس‌وجوها از تونل عبور می‌کنند (بدون نشت).
  Map<String, dynamic> _dns() {
    final servers = <dynamic>[];
    switch (patt.dnsMode) {
      case 'custom':
        final custom = _csv(patt.customDns);
        servers.addAll(custom.isEmpty ? ['https://1.1.1.1/dns-query', '1.1.1.1'] : custom);
        break;
      case 'doh':
        servers.addAll(['https://1.1.1.1/dns-query', 'https://dns.google/dns-query']);
        break;
      default: // 'default' / 'auto'
        servers.addAll(['https://1.1.1.1/dns-query', '1.1.1.1', '8.8.8.8']);
    }
    if (patt.bypassIran) {
      // DNS ایرانی فقط برای دامنه‌های ایرانی؛ خودِ سرور با geoip:ir مستقیم می‌رود
      servers.insert(0, {
        'address': '78.157.42.100',
        'domains': ['geosite:category-ir', 'regexp:.*\\.ir\$'],
        'skipFallback': true,
      });
    }
    return {'servers': servers, 'queryStrategy': 'UseIP', 'disableFallbackIfMatch': true};
  }

  Map<String, dynamic> _routing() {
    final rules = <Map<String, dynamic>>[
      // ✅ همهٔ پرس‌وجوهای DNS دستگاه → ماژول DNS داخلی
      {'type': 'field', 'inboundTag': ['socks', 'http'], 'port': '53', 'outboundTag': 'dns-out'},
    ];
    if (patt.bypassLan) {
      rules.add({'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'direct'});
      rules.add({'type': 'field', 'domain': ['regexp:.*\\.local\$', 'domain:localhost'], 'outboundTag': 'direct'});
    }
    if (patt.bypassIran) {
      rules.add({'type': 'field', 'domain': ['geosite:category-ir', 'regexp:.*\\.ir\$'], 'outboundTag': 'direct'});
      rules.add({'type': 'field', 'ip': ['geoip:ir'], 'outboundTag': 'direct'});
    }
    rules.add({'type': 'field', 'port': '0-65535', 'outboundTag': 'proxy'});
    return {'domainStrategy': 'IPIfNonMatch', 'rules': rules};
  }

  Map<String, dynamic> _dnsOut() => {
        'tag': 'dns-out',
        'protocol': 'dns',
        'settings': {'nonIPQuery': 'skip'},
      };

  Map<String, dynamic> _directOut() => {
        'tag': 'direct',
        'protocol': 'freedom',
        'settings': {'domainStrategy': 'UseIP'},
      };

  Map<String, dynamic> _blockOut() => {
        'tag': 'block',
        'protocol': 'blackhole',
        'settings': {'response': {'type': 'http'}},
      };

  Map<String, dynamic>? _fragmentOut() {
    final fragOn = patt.frag.isNotEmpty && patt.frag != 'none';
    if (!fragOn && !patt.noise) return null;
    final settings = <String, dynamic>{'domainStrategy': 'UseIP'};
    if (fragOn) {
      settings['fragment'] = {
        'packets': patt.frag,
        'length': _range(patt.fragLen, '100-200', min: 1),
        'interval': _range(patt.fragInt, '10-20'),
      };
    }
    if (patt.noise) {
      settings['noises'] = [
        {
          'type': patt.noiseType,
          // برای rand بازهٔ بایت است و باید معتبر باشد؛ برای str/base64 متن آزاد است
          'packet': patt.noiseType == 'rand' ? _range(patt.noisePacket, '10-20', min: 1) : patt.noisePacket,
          'delay': _range(patt.noiseDelay, '10-20'),
        },
      ];
    }
    return {
      'tag': 'fragment',
      'protocol': 'freedom',
      'settings': settings,
      'streamSettings': {
        'sockopt': {'tcpNoDelay': true, 'tcpKeepAliveIdle': 100},
      },
    };
  }

  void _applyTls(Map<String, dynamic> ss, String protocol) {
    final sec = (ss['security'] ?? 'none').toString();
    // REALITY فقط برای VLESS/Trojan معنا دارد؛ روی VMess/SS کانفیگ را خراب می‌کرد
    if (patt.reality && (protocol == 'vless' || protocol == 'trojan')) {
      ss['security'] = 'reality';
      ss.remove('tlsSettings');
      final old = (ss['realitySettings'] as Map?)?.cast<String, dynamic>() ?? {};
      ss['realitySettings'] = {
        ...old,
        if (patt.sni.isNotEmpty) 'serverName': patt.sni,
        if (patt.fp.isNotEmpty) 'fingerprint': patt.fp,
        if (patt.pbk.isNotEmpty) 'publicKey': patt.pbk,
        if (patt.sid.isNotEmpty) 'shortId': patt.sid,
        if (patt.spx.isNotEmpty) 'spiderX': patt.spx,
      };
      return;
    }
    if (sec == 'tls') {
      final tls = (ss['tlsSettings'] as Map?)?.cast<String, dynamic>() ?? {};
      if (patt.fp.isNotEmpty) tls['fingerprint'] = patt.fp;
      if (patt.sni.isNotEmpty) tls['serverName'] = patt.sni;
      if (patt.cs.isNotEmpty) tls['cipherSuites'] = patt.cs;
      if (patt.pcs.isNotEmpty) tls['pinnedPeerCertificateChainSha256'] = _csv(patt.pcs);
      if (patt.vcn.isNotEmpty) tls['verifyPeerCertInNames'] = _csv(patt.vcn);
      if (patt.overrideStream && patt.alpn.isNotEmpty) tls['alpn'] = _csv(patt.alpn);
      ss['tlsSettings'] = tls;
    } else if (sec == 'reality') {
      final r = (ss['realitySettings'] as Map?)?.cast<String, dynamic>() ?? {};
      if (patt.fp.isNotEmpty) r['fingerprint'] = patt.fp;
      if (patt.sni.isNotEmpty) r['serverName'] = patt.sni;
      ss['realitySettings'] = r;
    }
  }

  void _applyTransport(Map<String, dynamic> ss) {
    if (!patt.overrideStream) return;
    final net = patt.network;
    ss['network'] = net;
    for (final k in ['wsSettings', 'grpcSettings', 'tcpSettings', 'httpupgradeSettings', 'xhttpSettings', 'kcpSettings']) {
      ss.remove(k);
    }
    switch (net) {
      case 'ws':
        ss['wsSettings'] = {
          'path': patt.path,
          if (patt.host.isNotEmpty) 'headers': {'Host': patt.host},
        };
        break;
      case 'grpc':
        ss['grpcSettings'] = {'serviceName': patt.path.replaceFirst('/', '')};
        break;
      case 'httpupgrade':
        ss['httpupgradeSettings'] = {'path': patt.path, if (patt.host.isNotEmpty) 'host': patt.host};
        break;
      case 'xhttp':
        ss['xhttpSettings'] = {'path': patt.path, if (patt.host.isNotEmpty) 'host': patt.host};
        break;
      default:
        if (patt.headerType == 'http') {
          ss['tcpSettings'] = {
            'header': {
              'type': 'http',
              'request': {
                'path': [patt.path],
                'headers': {if (patt.host.isNotEmpty) 'Host': [patt.host]},
              },
            },
          };
        }
    }
  }

  void _applyFlow(Map<String, dynamic> main) {
    if (!patt.reality || main['protocol'] != 'vless') return;
    final vnext = ((main['settings'] as Map?)?['vnext'] as List?)?.cast<Map>();
    if (vnext == null) return;
    for (final v in vnext) {
      for (final u in ((v['users'] as List?)?.cast<Map>() ?? const [])) {
        if (patt.flow.isEmpty) {
          u.remove('flow');
        } else {
          u['flow'] = patt.flow;
        }
      }
    }
  }

  /// Xray اجازهٔ Mux همراه با XTLS Vision را نمی‌دهد
  bool _hasVisionFlow(Map<String, dynamic> main) {
    final vnext = ((main['settings'] as Map?)?['vnext'] as List?)?.cast<Map>();
    if (vnext == null) return false;
    for (final v in vnext) {
      for (final u in ((v['users'] as List?)?.cast<Map>() ?? const [])) {
        if ((u['flow'] ?? '').toString().startsWith('xtls')) return true;
      }
    }
    return false;
  }

  void _applyMux(Map<String, dynamic> main) {
    if (patt.mux && !_hasVisionFlow(main)) {
      main['mux'] = {'enabled': true, 'concurrency': int.tryParse(patt.muxConc) ?? 8};
    } else {
      main.remove('mux');
    }
  }

  // ───────── utils ─────────
  /// مقدار بازه‌ای Xray («100-200» یا «50»)؛ مقدار نامعتبر/منفی هسته را کرش می‌دهد
  static String _range(String v, String fallback, {int min = 0}) {
    final m = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(v.trim());
    if (m == null) return fallback;
    final a = int.tryParse(m.group(1)!);
    final b = m.group(2) == null ? a : int.tryParse(m.group(2)!);
    if (a == null || b == null || a < min || a > b || b > 2147483647) return fallback;
    return v.trim();
  }

  static List<String> _csv(String s) =>
      s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  static Map<String, dynamic> _deepCopy(Map m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
}
