// lib/core/clash_import.dart — خواندن اشتراک‌های فرمت Clash / Clash.Meta (YAML)
//
// بسیاری از پنل‌ها (و برنامهٔ Hiddify) اشتراک را به‌صورت YAML با کلید `proxies:` می‌دهند. این فایل
// پروکسی‌هایی را که هستهٔ Xray اجرا می‌کند (vless / vmess / trojan / ss) به لینک استاندارد تبدیل می‌کند.
// نوع‌های دیگر (hysteria2، tuic، wireguard، ssh، masque، …) نیاز به هستهٔ دیگری دارند و رد می‌شوند.
import 'dart:convert';

import 'package:yaml/yaml.dart';

class ClashImport {
  final List<String> links;
  final int unsupported; // تعداد پروکسی‌هایی که این هسته نمی‌تواند اجرا کند
  const ClashImport(this.links, this.unsupported);
}

bool looksLikeClash(String body) => RegExp(r'^\s*proxies\s*:', multiLine: true).hasMatch(body);

ClashImport parseClash(String body) {
  dynamic doc;
  try {
    doc = loadYaml(body);
  } catch (_) {
    return const ClashImport(<String>[], 0);
  }
  if (doc is! Map) return const ClashImport(<String>[], 0);
  final proxies = doc['proxies'];
  if (proxies is! List) return const ClashImport(<String>[], 0);
  final out = <String>[];
  var skipped = 0;
  for (final p in proxies) {
    if (p is! Map) continue;
    String? link;
    try {
      link = _toLink(p);
    } catch (_) {
      link = null;
    }
    if (link == null) {
      skipped++;
    } else {
      out.add(link);
    }
  }
  return ClashImport(out, skipped);
}

String _s(dynamic v) => v == null ? '' : v.toString();
bool _b(dynamic v) => v == true || _s(v).toLowerCase() == 'true';
String _enc(String v) => Uri.encodeComponent(v);
Map? _m(dynamic v) => v is Map ? v : null;

String _query(Map<String, String> q) =>
    q.entries.where((e) => e.value.isNotEmpty).map((e) => '${_enc(e.key)}=${_enc(e.value)}').join('&');

String? _toLink(Map p) {
  final type = _s(p['type']).toLowerCase();
  final name = _s(p['name']);
  final server = _s(p['server']);
  final port = int.tryParse(_s(p['port'])) ?? 0;
  if (server.isEmpty || port <= 0) return null;
  final host = server.contains(':') ? '[$server]' : server;
  final frag = name.isEmpty ? '' : '#${_enc(name)}';
  switch (type) {
    case 'vless':
      return _vless(p, host, port, frag);
    case 'vmess':
      return _vmess(p, server, port, name);
    case 'trojan':
      return _trojan(p, host, port, frag);
    case 'ss':
      return _ss(p, host, port, frag);
    default:
      return null;
  }
}

/// نوع انتقال + پارامترهای مربوط (ws / grpc / h2 / tcp)
({String net, String path, String host}) _transport(Map p) {
  var net = _s(p['network']).toLowerCase();
  if (net.isEmpty) net = 'tcp';
  var path = '';
  var host = '';
  if (net == 'ws') {
    final o = _m(p['ws-opts']);
    path = _s(o?['path']);
    final h = _m(o?['headers']);
    host = _s(h?['Host'] ?? h?['host']);
  } else if (net == 'grpc') {
    path = _s(_m(p['grpc-opts'])?['grpc-service-name']);
  } else if (net == 'h2') {
    final o = _m(p['h2-opts']);
    path = _s(o?['path']);
    final hs = o?['host'];
    host = hs is List && hs.isNotEmpty ? _s(hs.first) : _s(hs);
  }
  return (net: net, path: path, host: host);
}

String _alpn(Map p) {
  final a = p['alpn'];
  return a is List ? a.map(_s).join(',') : _s(a);
}

String? _vless(Map p, String host, int port, String frag) {
  final uuid = _s(p['uuid']);
  if (uuid.isEmpty) return null;
  final t = _transport(p);
  final q = <String, String>{'encryption': 'none', 'type': t.net};
  final reality = _m(p['reality-opts']);
  final sni = _s(p['servername'] ?? p['sni']);
  if (reality != null && _s(reality['public-key']).isNotEmpty) {
    q['security'] = 'reality';
    q['pbk'] = _s(reality['public-key']);
    q['sid'] = _s(reality['short-id']);
    q['sni'] = sni;
    q['fp'] = _s(p['client-fingerprint']);
  } else if (_b(p['tls'])) {
    q['security'] = 'tls';
    q['sni'] = sni;
    q['fp'] = _s(p['client-fingerprint']);
    q['alpn'] = _alpn(p);
    if (_b(p['skip-cert-verify'])) q['allowInsecure'] = '1';
  } else {
    q['security'] = 'none';
  }
  q['flow'] = _s(p['flow']);
  if (t.net == 'grpc') {
    q['serviceName'] = t.path;
  } else {
    q['path'] = t.path;
  }
  q['host'] = t.host;
  return 'vless://${_enc(uuid)}@$host:$port?${_query(q)}$frag';
}

String? _vmess(Map p, String server, int port, String name) {
  final uuid = _s(p['uuid']);
  if (uuid.isEmpty) return null;
  final t = _transport(p);
  final j = <String, dynamic>{
    'v': '2',
    'ps': name,
    'add': server,
    'port': port.toString(),
    'id': uuid,
    'aid': (int.tryParse(_s(p['alterId'])) ?? 0).toString(),
    'scy': _s(p['cipher']).isEmpty ? 'auto' : _s(p['cipher']),
    'net': t.net,
    'type': 'none',
    'host': t.host,
    'path': t.path,
    'tls': _b(p['tls']) ? 'tls' : '',
    'sni': _s(p['servername'] ?? p['sni']),
    'alpn': _alpn(p),
    'fp': _s(p['client-fingerprint']),
  };
  return 'vmess://${base64Encode(utf8.encode(jsonEncode(j)))}';
}

String? _trojan(Map p, String host, int port, String frag) {
  final pwd = _s(p['password']);
  if (pwd.isEmpty) return null;
  final t = _transport(p);
  final q = <String, String>{
    'security': 'tls',
    'sni': _s(p['sni'] ?? p['servername']),
    'type': t.net,
    'alpn': _alpn(p),
    'fp': _s(p['client-fingerprint']),
  };
  if (_b(p['skip-cert-verify'])) q['allowInsecure'] = '1';
  if (t.net == 'grpc') {
    q['serviceName'] = t.path;
  } else {
    q['path'] = t.path;
  }
  q['host'] = t.host;
  return 'trojan://${_enc(pwd)}@$host:$port?${_query(q)}$frag';
}

String? _ss(Map p, String host, int port, String frag) {
  final cipher = _s(p['cipher']);
  final pwd = _s(p['password']);
  if (cipher.isEmpty || pwd.isEmpty) return null;
  final ui = base64Url.encode(utf8.encode('$cipher:$pwd')).replaceAll('=', '');
  return 'ss://$ui@$host:$port$frag';
}
