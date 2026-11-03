  // lib/core/models.dart — مدل‌ها و helperهای مستقل از UI
  import 'dart:convert';

  // ───────────── Server node ─────────────
  class ServerNode {
    String subTag;            // S1, S2, … (با حذف اشتراک دوباره‌شماره می‌شود)
    final String rawUri;
    final String displayName;
    final String protocol;    // VLESS / VMess / Trojan / Shadowsocks / SOCKS
    final String security;    // REALITY / TLS / NONE
    final String host;
    final int port;
    final String flag;        // ایموجی پرچم (اگر از نام قابل‌تشخیص باشد)
    int pingMs;               // -2 = تست‌نشده، -1 = timeout
    int jitterMs;             // نوسان پینگ (میانگین اختلاف از میانه) — حاصل تست چندنمونه‌ای
    int lossPct;              // درصد نمونه‌های ناموفق در تست چندنمونه‌ای (۰..۱۰۰)
    bool favorite;

    ServerNode({
      required this.subTag,
      required this.rawUri,
      required this.displayName,
      required this.protocol,
      required this.security,
      required this.host,
      required this.port,
      required this.flag,
      this.pingMs = -2,
      this.jitterMs = 0,
      this.lossPct = 0,
      this.favorite = false,
    });

    String get pingText => pingMs == -2 ? '--' : (pingMs < 0 ? 'timeout' : '$pingMs ms');
    String get subtitle => security == 'NONE' ? protocol : '$protocol • $security';

    factory ServerNode.fromUri(String uri, String subTag) {
      final p = ParsedLink.parse(uri);
      return ServerNode(
        subTag: subTag,
        rawUri: uri,
        displayName: p.name,
        protocol: p.protocol,
        security: p.security,
        host: p.host,
        port: p.port,
        flag: flagFromName(p.name),
      );
    }

    Map<String, dynamic> toJson() =>
        {'t': subTag, 'u': rawUri, 'f': favorite, 'p': pingMs, 'j': jitterMs, 'l': lossPct};

    static ServerNode? fromJson(Map m) {
      final u = (m['u'] ?? '').toString();
      if (u.isEmpty) return null;
      final n = ServerNode.fromUri(u, (m['t'] ?? 'S1').toString());
      n.favorite = m['f'] == true;
      final p = m['p'];
      if (p is int && p >= 0) n.pingMs = p;
      final j = m['j'];
      if (j is int && j >= 0) n.jitterMs = j;
      final l = m['l'];
      if (l is int && l >= 0 && l <= 100) n.lossPct = l;
      return n;
    }
  }

  // ───────────── Link parsing ─────────────
  class ParsedLink {
    final String name;
    final String protocol;
    final String security;
    final String host;
    final int port;
    const ParsedLink(this.name, this.protocol, this.security, this.host, this.port);

    static ParsedLink parse(String uri) {
      final low = uri.toLowerCase();
      try {
        if (low.startsWith('vmess://')) {
          final j = tryB64Decode(uri.substring(8));
          if (j != null) {
            final m = jsonDecode(j) as Map;
            final tls = (m['tls'] ?? '').toString().toLowerCase();
            final name = (m['ps'] ?? '').toString().trim();
            final host = (m['add'] ?? '').toString();
            final port = int.tryParse((m['port'] ?? '0').toString()) ?? 0;
            return ParsedLink(name.isEmpty ? '$host:$port' : name, 'VMess', tls == 'tls' ? 'TLS' : 'NONE', host, port);
          }
        }
        final u = Uri.parse(uri);
        final frag = u.fragment.isNotEmpty ? Uri.decodeComponent(u.fragment).trim() : '';
        final sec = (u.queryParameters['security'] ?? 'none').toLowerCase();
        String security = 'NONE';
        if (sec == 'reality') {
          security = 'REALITY';
        } else if (sec == 'tls' || sec == 'xtls') {
          security = 'TLS';
        }
        String proto;
        switch (u.scheme.toLowerCase()) {
          case 'vless':
            proto = 'VLESS';
            break;
          case 'trojan':
            proto = 'Trojan';
            if (security == 'NONE') security = 'TLS';
            break;
          case 'ss':
            proto = 'Shadowsocks';
            break;
          case 'socks':
            proto = 'SOCKS';
            break;
          default:
            proto = u.scheme.toUpperCase();
        }
        final host = u.host;
        final port = u.port;
        return ParsedLink(frag.isEmpty ? '$host:$port' : frag, proto, security, host, port);
      } catch (_) {
        return ParsedLink(uri.length > 30 ? uri.substring(0, 30) : uri, '?', 'NONE', '', 0);
      }
    }
  }

  bool isSupportedLink(String uri) {
    final u = uri.toLowerCase();
    return u.startsWith('vless://') ||
        u.startsWith('vmess://') ||
        u.startsWith('trojan://') ||
        u.startsWith('ss://') ||
        u.startsWith('socks://');
  }

  String? tryB64Decode(String s) {
    try {
      var t = s.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
      while (t.length % 4 != 0) {
        t += '=';
      }
      return utf8.decode(base64Decode(t), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// متن اشتراک (خام یا Base64) → لیست لینک‌های پشتیبانی‌شده
  List<String> parseSubscriptionBody(String body) {
    var text = body.trim();
    if (text.isEmpty) return const [];
    if (!text.contains('://')) {
      final d = tryB64Decode(text);
      if (d != null && d.contains('://')) text = d;
    }
    return text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && isSupportedLink(e))
        .toList();
  }

  // ───────────── Country / flag ─────────────
  final RegExp _flagRe = RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true);

  const Map<String, String> _countryWords = {
    'germany': '🇩🇪', 'de': '🇩🇪', 'frankfurt': '🇩🇪', 'berlin': '🇩🇪',
    'netherlands': '🇳🇱', 'nl': '🇳🇱', 'amsterdam': '🇳🇱',
    'united states': '🇺🇸', 'usa': '🇺🇸', 'us': '🇺🇸', 'america': '🇺🇸', 'new york': '🇺🇸', 'los angeles': '🇺🇸',
    'canada': '🇨🇦', 'ca': '🇨🇦', 'toronto': '🇨🇦',
    'singapore': '🇸🇬', 'sg': '🇸🇬',
    'france': '🇫🇷', 'fr': '🇫🇷', 'paris': '🇫🇷',
    'uk': '🇬🇧', 'united kingdom': '🇬🇧', 'london': '🇬🇧', 'england': '🇬🇧',
    'finland': '🇫🇮', 'fi': '🇫🇮', 'helsinki': '🇫🇮',
    'turkey': '🇹🇷', 'tr': '🇹🇷', 'istanbul': '🇹🇷',
    'iran': '🇮🇷', 'ir': '🇮🇷',
    'japan': '🇯🇵', 'jp': '🇯🇵', 'tokyo': '🇯🇵',
    'uae': '🇦🇪', 'dubai': '🇦🇪',
    'sweden': '🇸🇪', 'se': '🇸🇪', 'stockholm': '🇸🇪',
    'poland': '🇵🇱', 'pl': '🇵🇱', 'warsaw': '🇵🇱',
    'russia': '🇷🇺', 'ru': '🇷🇺', 'moscow': '🇷🇺',
    'india': '🇮🇳', 'in': '🇮🇳',
    'hong kong': '🇭🇰', 'hk': '🇭🇰',
    'korea': '🇰🇷', 'kr': '🇰🇷',
    'italy': '🇮🇹', 'it': '🇮🇹',
    'spain': '🇪🇸', 'es': '🇪🇸',
    'austria': '🇦🇹', 'at': '🇦🇹',
    'switzerland': '🇨🇭', 'ch': '🇨🇭',
    'armenia': '🇦🇲', 'am': '🇦🇲',
    'lithuania': '🇱🇹', 'lt': '🇱🇹',
    'latvia': '🇱🇻', 'lv': '🇱🇻',
    'estonia': '🇪🇪', 'ee': '🇪🇪',
    'romania': '🇷🇴', 'ro': '🇷🇴',
    'bulgaria': '🇧🇬', 'bg': '🇧🇬',
    'czech': '🇨🇿', 'cz': '🇨🇿',
    'ukraine': '🇺🇦', 'ua': '🇺🇦',
    'kazakhstan': '🇰🇿', 'kz': '🇰🇿',
  };

  String flagFromName(String name) {
  final m = _flagRe.firstMatch(name);
  if (m != null) return m.group(0)!;
  final norm = ' ${name.replaceAll(RegExp(r'[_\-\|\[\]\(\),.:/•·]'), ' ')} ';
  final low = norm.toLowerCase();
  // ابتدا کلمات بلند
  for (final e in _countryWords.entries.where((e) => e.key.length > 2)) {
    if (low.contains(' ${e.key} ')) return e.value;
  }
  // کدهای دو حرفی فقط وقتی با حروف بزرگ نوشته شده باشند؛ وگرنه کلمات انگلیسی
  // مثل «in» یا «it» یا «at» به‌اشتباه پرچم هند/ایتالیا/اتریش می‌گیرند.
  for (final e in _countryWords.entries.where((e) => e.key.length == 2)) {
    if (norm.contains(' ${e.key.toUpperCase()} ')) return e.value;
  }
  return '🌐';
}

// ───────────── PattNG settings ─────────────
  class Patt {
    String fp = 'chrome';
    String cs = '';
    String pcs = '';
    String vcn = '';
    String frag = 'none';
    String fragLen = '100-200';
    String fragInt = '10-20';
    bool noise = false;
    String noiseType = 'rand';
    String noisePacket = '10-20';
    String noiseDelay = '10-20';
    bool mux = false;
    String muxConc = '8';
    bool bypassLan = true;
    bool bypassIran = false;
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
    bool overrideStream = false;
    String network = 'tcp';
    String path = '/';
    String host = '';
    String headerType = 'none';

    /// بازگشت همهٔ فیلدها به مقادیر پیش‌فرض
    void resetDefaults() => loadJson(Patt().toJson());

    Map<String, dynamic> toJson() => {
          'fp': fp, 'cs': cs, 'pcs': pcs, 'vcn': vcn,
          'frag': frag, 'fl': fragLen, 'fi': fragInt,
          'noise': noise, 'nt': noiseType, 'np': noisePacket, 'nd': noiseDelay,
          'mux': mux, 'mc': muxConc,
          'lan': bypassLan, 'irn': bypassIran, 'log': logLevel,
          'dns': dnsMode, 'dnsc': customDns,
          'real': reality, 'pbk': pbk, 'sid': sid, 'spx': spx, 'flow': flow,
          'alpn': alpn, 'sni': sni,
          'ovr': overrideStream, 'net': network, 'path': path, 'host': host, 'ht': headerType,
        };

    void loadJson(Map m) {
      String s(String k, String d) => (m[k] ?? d).toString();
      bool b(String k, bool d) => m[k] is bool ? m[k] as bool : d;
      fp = s('fp', fp); cs = s('cs', cs); pcs = s('pcs', pcs); vcn = s('vcn', vcn);
      frag = s('frag', frag); fragLen = s('fl', fragLen); fragInt = s('fi', fragInt);
      noise = b('noise', noise); noiseType = s('nt', noiseType);
      noisePacket = s('np', noisePacket); noiseDelay = s('nd', noiseDelay);
      mux = b('mux', mux); muxConc = s('mc', muxConc);
      bypassLan = b('lan', bypassLan); bypassIran = b('irn', bypassIran); logLevel = s('log', logLevel);
      dnsMode = s('dns', dnsMode); customDns = s('dnsc', customDns);
      reality = b('real', reality); pbk = s('pbk', pbk); sid = s('sid', sid);
      spx = s('spx', spx); flow = s('flow', flow);
      alpn = s('alpn', alpn); sni = s('sni', sni);
      overrideStream = b('ovr', overrideStream); network = s('net', network);
      path = s('path', path); host = s('host', host); headerType = s('ht', headerType);
    }
  }

  // ───────────── App settings ─────────────
  class AppSettings {
    bool notifications = true;
    bool saveLogs = true;
    int delayMode = 0; // 0 = real (core) | 1 = tcp
    bool autoConnect = false;
    // ── WARP ──
    String warpMode = 'chain'; // chain = روی سرور فعال | only = فقط WARP بدون سرور
    int warpMtu = 1280;        // MTU تونل WireGuard (۱۲۸۰ امن‌ترین، ۱۳۸۰/۱۴۲۰ سریع‌تر روی بعضی ISPها)
    bool warpAutoFix = true;   // وقتی تونل تأیید نشد، endpoint بعدی به‌طور خودکار امتحان شود

    Map<String, dynamic> toJson() => {
          'notif': notifications,
          'logs': saveLogs,
          'delay': delayMode,
          'auto': autoConnect,
          'wmode': warpMode,
          'wmtu': warpMtu,
          'wfix': warpAutoFix,
        };

    void loadJson(Map m) {
      notifications = m['notif'] is bool ? m['notif'] : notifications;
      saveLogs = m['logs'] is bool ? m['logs'] : saveLogs;
      delayMode = m['delay'] is int ? m['delay'] : delayMode;
      autoConnect = m['auto'] is bool ? m['auto'] : autoConnect;
      final wm = (m['wmode'] ?? '').toString();
      if (wm == 'chain' || wm == 'only') warpMode = wm;
      final wmtu = m['wmtu'];
      if (wmtu is int && const [1280, 1380, 1420].contains(wmtu)) warpMtu = wmtu;
      if (m['wfix'] is bool) warpAutoFix = m['wfix'] as bool;
    }
  }

  // ───────────── Logs ─────────────
  enum LogKind { connection, core, system }

  enum LogLevel { info, warn, error }

  class LogEntry {
    final DateTime time;
    final LogKind kind;
    final LogLevel level;
    final String text;
    LogEntry(this.kind, this.level, this.text) : time = DateTime.now();

    String get timeText {
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    }

    String get levelText => switch (level) { LogLevel.info => 'INFO', LogLevel.warn => 'WARN', LogLevel.error => 'ERROR' };
  }

  // ───────────── Subscription record ─────────────
  class SubRecord {
    final String url;
    String name;
    int nodeCount;
    DateTime? lastSync;
    bool lastOk;
    SubRecord({required this.url, this.name = '', this.nodeCount = 0, this.lastSync, this.lastOk = true});

    Map<String, dynamic> toJson() =>
        {'u': url, 'n': name, 'c': nodeCount, 'ls': lastSync?.millisecondsSinceEpoch, 'ok': lastOk};

    static SubRecord? fromJson(dynamic v) {
      if (v is String) return SubRecord(url: v); // سازگاری با نسخهٔ قدیمی (List<String>)
      if (v is! Map) return null;
      final u = (v['u'] ?? '').toString();
      if (u.isEmpty) return null;
      return SubRecord(
        url: u,
        name: (v['n'] ?? '').toString(),
        nodeCount: v['c'] is int ? v['c'] : 0,
        lastSync: v['ls'] is int ? DateTime.fromMillisecondsSinceEpoch(v['ls']) : null,
        lastOk: v['ok'] is bool ? v['ok'] : true,
      );
    }
  }
