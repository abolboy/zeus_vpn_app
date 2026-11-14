  // lib/core/models.dart — مدل‌ها و helperهای مستقل از UI
  import 'dart:convert';
  
  /// Redacts credentials from network and configuration errors before they
  /// enter the in-memory log list or are copied to the clipboard.
  String redactSensitiveLogText(String value) {
    var text = value;

    // Entire share URIs may contain UUIDs, passwords, or base64 credentials.
    text = text.replaceAllMapped(
      RegExp(r'\b(?:vless|vmess|trojan|ss|socks5?|https?)://\S+',
          caseSensitive: false),
      (match) {
        final raw = match.group(0) ?? '';
        final separator = raw.indexOf('://');
        if (separator <= 0) return '[REDACTED_URI]';
        final scheme = raw.substring(0, separator).toLowerCase();
        final uri = Uri.tryParse(raw);
        if (uri == null || uri.host.isEmpty) return scheme + '://[REDACTED]';
        final port = uri.hasPort ? ':' + uri.port.toString() : '';
        return scheme + '://' + uri.host + port + '/[REDACTED]';
      },
    );

    // Redact standalone credential assignments in exception/config text.
    text = text.replaceAllMapped(
      RegExp(
        r'((?:private[_-]?key|pre[_-]?shared[_-]?key|secret[_-]?key|password|passwd|access[_-]?token|client[_-]?secret|api[_-]?key|token|authorization)\s*[:=]\s*)(?:"[^"]*"|[^\s,;]+)',
        caseSensitive: false,
      ),
      (match) => (match.group(1) ?? '') + '[REDACTED]',
    );

    // Cover secrets embedded in URL query strings even when the whole string
    // is not recognized as a URI.
    text = text.replaceAllMapped(
      RegExp(
        r'([?&](?:token|access_token|refresh_token|key|password|pass|auth|secret|client_secret|api_key)=)[^&#\s]+',
        caseSensitive: false,
      ),
      (match) => (match.group(1) ?? '') + '[REDACTED]',
    );

    // Authorization headers are sometimes formatted as a Bearer scheme.
    text = text.replaceAll(
      RegExp(r'(Bearer\s+)[A-Za-z0-9._~+/-]+=*', caseSensitive: false),
      r'$1[REDACTED]',
    );
    return text;
  }

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
    bool viaTcp = false;     // پینگ از راه TCP (جایگزین وقتی پینگ واقعی هسته جواب نداد)

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
        // فرمت «کل Base64» ی ss:// به فرمت قابل‌اجرا تبدیل می‌شود
        rawUri: normalizeLink(uri),
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
        // فرمت «کل لینک Base64» در ss:// با Uri.parse قابل‌خواند نیست (host مجهول می‌شود)؛ اینجا دستی باز می‌شود.
        if (low.startsWith('ss://')) {
          final ss = _parseSsBody(uri);
          if (ss != null) return ss;
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

    /// بدنهٔ ss:// بدون «@» را به‌صورت Base64 کامل باز می‌کند؛ null یعنی این فرمت نیست.
    static ParsedLink? _parseSsBody(String uri) {
      try {
        var body = uri.substring(5);
        final hash = body.indexOf('#');
        final frag = hash >= 0 ? Uri.decodeComponent(body.substring(hash + 1)).trim() : '';
        if (hash >= 0) body = body.substring(0, hash);
        final qm = body.indexOf('?');
        if (qm >= 0) body = body.substring(0, qm);
        if (body.contains('@')) return null; // فرمت استاندارد؛ مسیر عمومی هندلش می‌کند
        final d = tryB64Decode(body);
        if (d == null) return null;
        final at = d.lastIndexOf('@');
        if (at <= 0) return null;
        final hostport = d.substring(at + 1);
        final colon = hostport.lastIndexOf(':');
        if (colon <= 0) return null;
        var host = hostport.substring(0, colon);
        final port = int.tryParse(hostport.substring(colon + 1)) ?? 0;
        if (host.isEmpty || port <= 0) return null;
        if (host.startsWith('[') && host.endsWith(']')) host = host.substring(1, host.length - 1);
        return ParsedLink(frag.isEmpty ? '$host:$port' : frag, 'Shadowsocks', 'NONE', host, port);
      } catch (_) {
        return null;
      }
    }
  }

  /// لینک ss:// که کل بدنهٔ آن Base64 است («ss://BASE64(method:pass@host:port)#name»)
  /// به فرمت استاندارد هسته («ss://BASE64(method:pass)@host:port#name») تبدیل می‌شود.
  /// هستهٔ اتصال فقط فرمت دوم را می‌فهمد؛ فرمت اول همواره شکست می‌خورد.
  String normalizeLink(String uri) {
    if (!uri.toLowerCase().startsWith('ss://')) return uri;
    try {
      var body = uri.substring(5);
      final hash = body.indexOf('#');
      final frag = hash >= 0 ? body.substring(hash + 1) : '';
      if (hash >= 0) body = body.substring(0, hash);
      var query = '';
      final qm = body.indexOf('?');
      if (qm >= 0) {
        query = body.substring(qm);
        body = body.substring(0, qm);
      }
      if (body.contains('@')) return uri; // از قبل فرمت استاندارد است
      final d = tryB64Decode(body);
      if (d == null) return uri;
      final at = d.lastIndexOf('@');
      if (at <= 0) return uri;
      final userinfo = d.substring(0, at);
      final hostport = d.substring(at + 1);
      if (userinfo.isEmpty || hostport.isEmpty || hostport.lastIndexOf(':') <= 0) return uri;
      // Base64 استاندارد (هسته فقط همین را decode می‌کند) + percent-encode تا
      // «/» یا «+» داخل userinfo توسط Uri.parse جداکنندهٔ مسیر خوانده نشود.
      final enc = Uri.encodeComponent(base64.encode(utf8.encode(userinfo)).replaceAll('=', ''));
      return 'ss://$enc@$hostport'
          '${query.isNotEmpty ? query : ''}'
          '${frag.isNotEmpty ? '#$frag' : ''}';
    } catch (_) {
      return uri;
    }
  }

  /// Subscription feeds are accepted only over HTTPS. This blocks cleartext
/// credentials and prevents an HTTP URL from being saved and fetched later.
bool isSecureSubscriptionUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.isNotEmpty;
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
        .where((e) => e.isNotEmpty && isSupportedLink(e) && !_isPlaceholder(e))
        .toList();
  }

  /// بعضی اشتراک‌ها اول لیست یک نود ساختگی (0.0.0.0) می‌گذارند تا نام/حجم را نشان دهند؛ سرور واقعی نیست
  bool _isPlaceholder(String u) => u.contains('@0.0.0.0:');

  // ───────────── اطلاعات اشتراک (سبک v2Box / ArasClient) ─────────────
  class SubMeta {
    final String title;
    final int used; // بایت (آپلود + دانلود)
    final int total; // بایت؛ ۰ = نامحدود/نامشخص
    final int expire; // ثانیهٔ یونیکس؛ ۰ = نامشخص
    final String announce;
    const SubMeta({this.title = '', this.used = 0, this.total = 0, this.expire = 0, this.announce = ''});
  }

  String _metaDecode(String v) {
    final t = v.trim();
    if (t.toLowerCase().startsWith('base64:')) {
      final d = tryB64Decode(t.substring(7).trim());
      if (d != null) return d.trim();
    }
    return t;
  }

  /// از هدرهای HTTP (`profile-title`، `subscription-userinfo`، `announce`) و در نبودشان از
  /// خط‌های توضیحی ابتدای متن (`# profile-title: …`) می‌خواند.
  SubMeta parseSubMeta(String body, String? Function(String name) header) {
    const keys = ['profile-title', 'subscription-userinfo', 'announce'];
    final found = <String, String>{};
    for (final k in keys) {
      final v = header(k);
      if (v != null && v.trim().isNotEmpty) found[k] = v;
    }
    final re = RegExp(r'^#\s*([A-Za-z\-]+)\s*:\s*(.+)$');
    for (final line in body.split(RegExp(r'[\r\n]+'))) {
      final m = re.firstMatch(line.trim());
      if (m == null) continue;
      final k = m.group(1)!.toLowerCase();
      if (keys.contains(k)) found.putIfAbsent(k, () => m.group(2)!);
    }
    var used = 0;
    var total = 0;
    var expire = 0;
    final info = found['subscription-userinfo'];
    if (info != null) {
      final vals = <String, int>{};
      for (final m in RegExp(r'(\w+)\s*=\s*(\d+)').allMatches(info)) {
        vals[m.group(1)!.toLowerCase()] = int.tryParse(m.group(2)!) ?? 0;
      }
      used = (vals['upload'] ?? 0) + (vals['download'] ?? 0);
      total = vals['total'] ?? 0;
      expire = vals['expire'] ?? 0;
    }
    return SubMeta(
      title: _metaDecode(found['profile-title'] ?? ''),
      used: used,
      total: total,
      expire: expire,
      announce: _metaDecode(found['announce'] ?? ''),
    );
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
  // کدهای دو حرفی:
  //  • با حروف بزرگ همیشه پذیرفته می‌شوند (DE / US / IT …)
  //  • با حروف کوچک فقط وقتی با یک کلمهٔ انگلیسی هم‌نام نباشند — وگرنه
  //    «in/it/at/us/am» به‌اشتباه پرچم می‌گرفتند.
  const Set<String> ambiguousLower = {'in', 'it', 'at', 'us', 'am'};
  for (final e in _countryWords.entries.where((e) => e.key.length == 2)) {
    if (norm.contains(' ${e.key.toUpperCase()} ')) return e.value;
    if (!ambiguousLower.contains(e.key) && low.contains(' ${e.key} ')) return e.value;
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
    bool blockAds = false; // مسدودساز تبلیغات/ردیاب‌ها (geosite:category-ads-all)
    bool bypassCn = false; // سایت‌ها و IPهای چین مستقیم
    bool bypassRu = false; // سایت‌ها و IPهای روسیه مستقیم
    bool blockQuic = false; // مسدود کردن UDP 443 تا QUIC به TCP برگردد
    bool bypassTorrent = false; // BitTorrent مستقیم (نیاز به sniffing)
    bool mixedSni = false; // حروف SNI به‌صورت تصادفی بزرگ/کوچک (ترفند TLS)
    String domainStrategy = 'IPIfNonMatch'; // AsIs / IPIfNonMatch / IPOnDemand
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
          'lan': bypassLan, 'irn': bypassIran, 'ads': blockAds, 'cn': bypassCn, 'ru': bypassRu, 'bq': blockQuic, 'bt': bypassTorrent, 'msni': mixedSni, 'ds': domainStrategy, 'log': logLevel,
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
      bypassLan = b('lan', bypassLan); bypassIran = b('irn', bypassIran); blockAds = b('ads', blockAds); bypassCn = b('cn', bypassCn); bypassRu = b('ru', bypassRu); blockQuic = b('bq', blockQuic); bypassTorrent = b('bt', bypassTorrent); mixedSni = b('msni', mixedSni); domainStrategy = s('ds', domainStrategy); logLevel = s('log', logLevel);
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
    bool autoFailover = true;  // اگر تونل تأیید نشد، خودکار سرور بعدی امتحان شود
    List<String> bypassApps = <String>[]; // بستهٔ برنامه‌هایی که از VPN مستثنی‌اند
    String chainUri = '';      // سرور واسطهٔ زنجیره (خالی = بدون زنجیره)
    String pingUrl = '';       // آدرس تست اتصال (خالی = پیش‌فرض)
    bool gridView = true;      // نمایش دو ستونهٔ سرورها (کارت‌های فشرده)
    bool autoTestAfterSync = false; // بعد از به‌روزرسانی اشتراک، خودکار پینگ بگیر
    bool autoRemoveDead = false;    // و سرورهای بی‌پاسخ را حذف کن
    int pingConcurrency = 6;        // تعداد پینگ همزمان
    // ── WARP ──
    String warpMode = 'chain'; // chain = روی سرور فعال | only = فقط WARP بدون سرور
    int warpMtu = 1280;        // MTU تونل WireGuard (۱۲۸۰ امن‌ترین، ۱۳۸۰/۱۴۲۰ سریع‌تر روی بعضی ISPها)
    bool warpAutoFix = true;   // وقتی تونل تأیید نشد، endpoint بعدی به‌طور خودکار امتحان شود

    Map<String, dynamic> toJson() => {
          'notif': notifications,
          'logs': saveLogs,
          'delay': delayMode,
          'auto': autoConnect,
          'fail': autoFailover,
          'apps': bypassApps,
          'chain': chainUri,
          'purl': pingUrl,
          'gv': gridView,
          'ats': autoTestAfterSync,
          'ard': autoRemoveDead,
          'pc': pingConcurrency,
          'wmode': warpMode,
          'wmtu': warpMtu,
          'wfix': warpAutoFix,
        };

    void loadJson(Map m) {
      notifications = m['notif'] is bool ? m['notif'] : notifications;
      saveLogs = m['logs'] is bool ? m['logs'] : saveLogs;
      delayMode = m['delay'] is int ? m['delay'] : delayMode;
      autoConnect = m['auto'] is bool ? m['auto'] : autoConnect;
      autoFailover = m['fail'] is bool ? m['fail'] : autoFailover;
      if (m['apps'] is List) bypassApps = [for (final e in m['apps'] as List) e.toString()];
      chainUri = (m['chain'] ?? '').toString();
      pingUrl = (m['purl'] ?? '').toString();
      gridView = m['gv'] is bool ? m['gv'] : gridView;
      autoTestAfterSync = m['ats'] is bool ? m['ats'] : autoTestAfterSync;
      autoRemoveDead = m['ard'] is bool ? m['ard'] : autoRemoveDead;
      pingConcurrency = m['pc'] is int ? (m['pc'] as int).clamp(1, 20).toInt() : pingConcurrency;
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
    int used;
    int total;
    int expire;
    String announce;
    SubRecord({
      required this.url,
      this.name = '',
      this.nodeCount = 0,
      this.lastSync,
      this.lastOk = true,
      this.used = 0,
      this.total = 0,
      this.expire = 0,
      this.announce = '',
    });

    Map<String, dynamic> toJson() =>
        {
          'u': url,
          'n': name,
          'c': nodeCount,
          'ls': lastSync?.millisecondsSinceEpoch,
          'ok': lastOk,
          'us': used,
          'tt': total,
          'ex': expire,
          'an': announce,
        };

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
        used: v['us'] is int ? v['us'] : 0,
        total: v['tt'] is int ? v['tt'] : 0,
        expire: v['ex'] is int ? v['ex'] : 0,
        announce: (v['an'] ?? '').toString(),
      );
    }
  }
