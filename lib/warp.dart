// lib/warp.dart
// ثبت‌نام Cloudflare WARP و ساخت outbound WireGuard برای Xray.
// وابستگی: فقط dart:io / dart:convert / dart:math (بدون پکیج خارجی)

import 'dart:convert';
import 'dart:io';
import 'dart:math';

// ───────────────────────── Endpoints ─────────────────────────

/// endpointهای شناخته‌شدهٔ WARP؛ IPهای در بازهٔ 162.159.192-195 و 188.114.96-99
/// روی پورت‌های جایگزین (۵۰۰/۸۹۴/۱۷۰۱/۴۵۰۰/۸۸۵۴/۸۸۸۶/۹۰۸) — چون روی بعضی ISPها
/// (مخصوصاً ایران) پورت ۲۴۰۸ مسدود یا محدود شده است. اولی پیش‌فرض است.
const List<String> kWarpEndpoints = <String>[
  'engage.cloudflareclient.com:2408',
  '162.159.192.1:2408',
  '162.159.193.10:2408',
  '162.159.195.1:2408',
  '188.114.96.1:2408',
  '188.114.97.1:2408',
  '162.159.192.1:500',
  '162.159.192.1:1701',
  '162.159.192.1:4500',
  '162.159.193.10:894',
  '162.159.192.23:8854',
  '162.159.192.123:8886',
  '188.114.96.183:908',
  '[2606:4700:d0::a29f:c001]:2408',
];

/// endpoint بعدی برای چرخش خودکار؛ اگر فعلی در لیست نبود، از اولین آی‌پی لیست شروع می‌شود
/// (دامنهٔ engage را رد می‌کند چون روی ISPهای سانسورگر معمولاً DNS آن دستکاری می‌شود).
String nextWarpEndpoint(String current) {
  var i = kWarpEndpoints.indexOf(current);
  if (i < 0) i = 0;
  for (var step = 0; step < kWarpEndpoints.length; step++) {
    i = (i + 1) % kWarpEndpoints.length;
    final cand = kWarpEndpoints[i];
    if (!cand.startsWith('engage.')) return cand; // دامنه را دور بزن
  }
  return kWarpEndpoints[1];
}

const String _kRegUrl = 'https://api.cloudflareclient.com/v0a2158/reg';

// ───────────────────────── Exception ─────────────────────────

class WarpException implements Exception {
  final String message;
  final int? statusCode;
  const WarpException(this.message, [this.statusCode]);
  @override
  String toString() => 'WarpException: $message';
}

// ───────────────────────── X25519 (RFC 7748) ─────────────────────────

final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
final BigInt _a24 = BigInt.from(121665);
final BigInt _mask8 = BigInt.from(0xff);

BigInt _decodeLE(List<int> b) {
  BigInt r = BigInt.zero;
  for (int i = b.length - 1; i >= 0; i--) {
    r = (r << 8) | BigInt.from(b[i] & 0xff);
  }
  return r;
}

List<int> _encodeLE(BigInt v) {
  final out = List<int>.filled(32, 0);
  for (int i = 0; i < 32; i++) {
    out[i] = (v & _mask8).toInt();
    v = v >> 8;
  }
  return out;
}

/// ضرب اسکالر X25519: خروجی ۳۲ بایت
List<int> x25519(List<int> scalar, List<int> uBytes) {
  if (scalar.length != 32 || uBytes.length != 32) {
    throw ArgumentError('x25519 inputs must be 32 bytes');
  }
  final k = List<int>.from(scalar);
  k[0] &= 248;
  k[31] &= 127;
  k[31] |= 64;

  final u = List<int>.from(uBytes);
  u[31] &= 127;

  final BigInt kInt = _decodeLE(k);
  final BigInt x1 = _decodeLE(u) % _p;

  BigInt x2 = BigInt.one;
  BigInt z2 = BigInt.zero;
  BigInt x3 = x1;
  BigInt z3 = BigInt.one;
  int swap = 0;

  for (int t = 254; t >= 0; t--) {
    final int kt = ((kInt >> t) & BigInt.one).toInt();
    swap ^= kt;
    if (swap == 1) {
      BigInt tmp = x2; x2 = x3; x3 = tmp;
      tmp = z2; z2 = z3; z3 = tmp;
    }
    swap = kt;

    final BigInt a = (x2 + z2) % _p;
    final BigInt aa = (a * a) % _p;
    final BigInt b = (x2 - z2) % _p;
    final BigInt bb = (b * b) % _p;
    final BigInt e = (aa - bb) % _p;
    final BigInt c = (x3 + z3) % _p;
    final BigInt d = (x3 - z3) % _p;
    final BigInt da = (d * a) % _p;
    final BigInt cb = (c * b) % _p;

    final BigInt s1 = (da + cb) % _p;
    x3 = (s1 * s1) % _p;
    final BigInt s2 = (da - cb) % _p;
    z3 = (x1 * ((s2 * s2) % _p)) % _p;
    x2 = (aa * bb) % _p;
    z2 = (e * ((aa + (_a24 * e)) % _p)) % _p;
  }

  if (swap == 1) {
    BigInt tmp = x2; x2 = x3; x3 = tmp;
    tmp = z2; z2 = z3; z3 = tmp;
  }

  final BigInt inv = z2.modPow(_p - BigInt.two, _p);
  return _encodeLE((x2 * inv) % _p);
}

/// جفت‌کلید WireGuard (base64)
class WarpKeyPair {
  final String privateKey;
  final String publicKey;
  const WarpKeyPair(this.privateKey, this.publicKey);
}

/// تولید کلید؛ همگام است و می‌تواند داخل compute() اجرا شود.
WarpKeyPair generateWarpKeyPair([Object? _]) {
  final rnd = Random.secure();
  final priv = List<int>.generate(32, (_) => rnd.nextInt(256));
  priv[0] &= 248;
  priv[31] &= 127;
  priv[31] |= 64;
  final base = List<int>.filled(32, 0);
  base[0] = 9;
  final pub = x25519(priv, base);
  return WarpKeyPair(base64Encode(priv), base64Encode(pub));
}

// ───────────────────────── Config model ─────────────────────────

class WarpConfig {
  final String privateKey;
  final String publicKey;
  final String peerPublicKey;
  final String preSharedKey;
  final String addressV4;
  final String addressV6;
  final String endpoint;
  final List<int> reserved;
  final List<String> allowedIPs;
  final List<String> dnsServers;
  final int keepAlive;
  final int? interfaceMtu;
  final String deviceId;
  final String token;
  final String registeredAt;

  const WarpConfig({
    required this.privateKey,
    required this.publicKey,
    required this.peerPublicKey,
    required this.addressV4,
    required this.addressV6,
    required this.endpoint,
    required this.reserved,
    required this.deviceId,
    required this.token,
    required this.registeredAt,
    this.preSharedKey = '',
    this.allowedIPs = const <String>[],
    this.dnsServers = const <String>[],
    this.keepAlive = 25,
    this.interfaceMtu,
  });

  bool get isCloudflareRegistered => deviceId.isNotEmpty && token.isNotEmpty;

  WarpConfig copyWith({String? endpoint}) => WarpConfig(
        privateKey: privateKey,
        publicKey: publicKey,
        peerPublicKey: peerPublicKey,
        preSharedKey: preSharedKey,
        addressV4: addressV4,
        addressV6: addressV6,
        endpoint: endpoint ?? this.endpoint,
        reserved: reserved,
        allowedIPs: List<String>.unmodifiable(allowedIPs),
        dnsServers: List<String>.unmodifiable(dnsServers),
        keepAlive: keepAlive,
        interfaceMtu: interfaceMtu,
        deviceId: deviceId,
        token: token,
        registeredAt: registeredAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'privateKey': privateKey,
        'publicKey': publicKey,
        'peerPublicKey': peerPublicKey,
        'preSharedKey': preSharedKey,
        'addressV4': addressV4,
        'addressV6': addressV6,
        'endpoint': endpoint,
        'reserved': reserved,
        'allowedIPs': allowedIPs,
        'dnsServers': dnsServers,
        'keepAlive': keepAlive,
        'interfaceMtu': interfaceMtu,
        'deviceId': deviceId,
        'token': token,
        'registeredAt': registeredAt,
      };

  factory WarpConfig.fromJson(Map<String, dynamic> j) => WarpConfig(
        privateKey: (j['privateKey'] ?? '') as String,
        publicKey: (j['publicKey'] ?? '') as String,
        peerPublicKey: (j['peerPublicKey'] ?? '') as String,
        preSharedKey: (j['preSharedKey'] ?? '') as String,
        addressV4: (j['addressV4'] ?? '172.16.0.2/32') as String,
        addressV6: (j['addressV6'] ?? '') as String,
        endpoint: (j['endpoint'] ?? kWarpEndpoints.first) as String,
        reserved: ((j['reserved'] as List?) ?? const [0, 0, 0])
            .map((e) => (e as num).toInt())
            .toList(),
        allowedIPs: ((j['allowedIPs'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
        dnsServers: ((j['dnsServers'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
        keepAlive: j['keepAlive'] is num ? (j['keepAlive'] as num).toInt() : 25,
        interfaceMtu: j['interfaceMtu'] is num
            ? (j['interfaceMtu'] as num).toInt()
            : null,
        deviceId: (j['deviceId'] ?? '') as String,
        token: (j['token'] ?? '') as String,
        registeredAt: (j['registeredAt'] ?? '') as String,
      );

  String encode() => jsonEncode(toJson());

  static WarpConfig? tryDecode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final j = jsonDecode(s);
      if (j is Map<String, dynamic>) return WarpConfig.fromJson(j);
    } catch (_) {}
    return null;
  }

  static bool _validKey(String value) {
    try {
      return base64.decode(base64.normalize(value)).length == 32;
    } catch (_) {
      try {
        return base64Url.decode(base64Url.normalize(value)).length == 32;
      } catch (_) {
        return false;
      }
    }
  }

  static bool _validCidr(String value) {
    final parts = value.split('/');
    if (parts.length != 2) return false;
    final address = InternetAddress.tryParse(parts[0]);
    final prefix = int.tryParse(parts[1]);
    if (address == null || prefix == null) return false;
    final maxPrefix = address.type == InternetAddressType.IPv4 ? 32 : 128;
    return prefix >= 0 && prefix <= maxPrefix;
  }

  static bool _validEndpoint(String value) {
    final uri = Uri.tryParse('udp://$value');
    return uri != null &&
        uri.host.isNotEmpty &&
        uri.hasPort &&
        uri.port >= 1 &&
        uri.port <= 65535;
  }

  bool get isValid =>
      _validKey(privateKey) &&
      _validKey(peerPublicKey) &&
      (preSharedKey.isEmpty || _validKey(preSharedKey)) &&
      _validCidr(addressV4) &&
      (addressV6.isEmpty || _validCidr(addressV6)) &&
      _validEndpoint(endpoint) &&
      reserved.length == 3 &&
      reserved.every((value) => value >= 0 && value <= 255) &&
      (allowedIPs.isEmpty || allowedIPs.every(_validCidr)) &&
      keepAlive >= 0 &&
      keepAlive <= 65535;

  /// تبدیل تنظیمات استاندارد WireGuard به outbound در هستهٔ Xray.
  Map<String, dynamic> toXrayOutbound({
    String tag = 'warp',
    String? endpointOverride,
    int mtu = 1280,
    int workers = 2,
    bool includeV6 = true,
  }) {
    final addrs = <String>[addressV4];
    if (includeV6 && addressV6.isNotEmpty) addrs.add(addressV6);
    final peer = <String, dynamic>{
      'publicKey': peerPublicKey,
      'endpoint': endpointOverride ?? endpoint,
      'keepAlive': keepAlive,
      'allowedIPs': allowedIPs.isEmpty
          ? <String>[
              '0.0.0.0/0',
              if (includeV6 && addressV6.isNotEmpty) '::/0',
            ]
          : List<String>.of(allowedIPs),
      if (preSharedKey.isNotEmpty) 'preSharedKey': preSharedKey,
    };
    final settings = <String, dynamic>{
      'secretKey': privateKey,
      'address': addrs,
      'peers': <Map<String, dynamic>>[peer],
      'reserved': reserved,
      'mtu': mtu,
      'workers': workers,
      if (dnsServers.isNotEmpty) 'remoteDNS': List<String>.of(dnsServers),
      'domainStrategy': includeV6 && addressV6.isNotEmpty
          ? 'ForceIPv4v6'
          : 'ForceIPv4',
    };
    return <String, dynamic>{
      'tag': tag,
      'protocol': 'wireguard',
      'settings': settings,
    };
  }
}

// ───────────────────────── Register ─────────────────────────

String _tosNow() {
  final iso = DateTime.now().toUtc().toIso8601String(); // 2026-10-31T06:50:00.123456Z
  return '${iso.substring(0, 23)}Z';
}

/// ثبت‌نام در WARP.
/// [proxyPort]: اگر مقدار داشته باشد، درخواست از 127.0.0.1:port (پروکسی محلی HTTP) عبور می‌کند.
/// [preferredEndpoint]: endpoint دلخواه؛ در غیر این صورت از پاسخ سرور یا kWarpEndpoints[0].
Future<WarpConfig> registerWarp({
  int? proxyPort,
  String? preferredEndpoint,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final keys = generateWarpKeyPair();

  final client = HttpClient()
    ..connectionTimeout = timeout
    ..userAgent = 'okhttp/3.12.1';
  if (proxyPort != null && proxyPort > 0) {
    client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
  }

  try {
    final req = await client.postUrl(Uri.parse(_kRegUrl)).timeout(timeout);
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=UTF-8');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set('CF-Client-Version', 'a-6.3-2158');
    req.write(jsonEncode(<String, dynamic>{
      'key': keys.publicKey,
      'install_id': '',
      'fcm_token': '',
      'tos': _tosNow(),
      'model': 'PC',
      'serial_number': '',
      'locale': 'en_US',
    }));

    final resp = await req.close().timeout(timeout);
    final body = await resp.transform(utf8.decoder).join();
    final code = resp.statusCode;

    if (code == 403) {
      throw const WarpException(
          'Cloudflare درخواست را رد کرد (403). IP شما مسدود است؛ با VPN/پروکسی دیگر تلاش کنید.', 403);
    }
    if (code == 429) {
      throw const WarpException('تعداد درخواست زیاد است (429). چند دقیقه بعد دوباره تلاش کنید.', 429);
    }
    if (code < 200 || code >= 300) {
      throw WarpException('خطای سرور WARP ($code): ${body.length > 200 ? body.substring(0, 200) : body}', code);
    }

    final dynamic root = jsonDecode(body);
    if (root is! Map<String, dynamic>) throw const WarpException('پاسخ نامعتبر از سرور');
    final Map<String, dynamic> result =
        (root['result'] is Map<String, dynamic>) ? root['result'] as Map<String, dynamic> : root;

    final Map<String, dynamic> config =
        (result['config'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final Map<String, dynamic> iface =
        (config['interface'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final Map<String, dynamic> addrs =
        (iface['addresses'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final List peers = (config['peers'] as List?) ?? const [];
    final Map<String, dynamic> peer0 =
        peers.isNotEmpty ? (peers.first as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final Map<String, dynamic> peerEp =
        (peer0['endpoint'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

    final String peerPub = (peer0['public_key'] ?? '') as String;
    if (peerPub.isEmpty) throw const WarpException('کلید عمومی peer در پاسخ نبود');

    String v4 = (addrs['v4'] ?? '') as String;
    String v6 = (addrs['v6'] ?? '') as String;
    if (v4.isEmpty) throw const WarpException('آدرس IPv4 در پاسخ نبود');
    if (!v4.contains('/')) v4 = '$v4/32';
    if (v6.isNotEmpty && !v6.contains('/')) v6 = '$v6/128';

    // reserved از client_id (۳ بایت base64)
    List<int> reserved = const [0, 0, 0];
    final String clientId = (config['client_id'] ?? '') as String;
    if (clientId.isNotEmpty) {
      try {
        final bytes = base64Decode(clientId);
        if (bytes.length == 3) reserved = List<int>.from(bytes);
      } catch (_) {}
    }

    final String serverEp = (peerEp['host'] ?? '') as String;
    final String endpoint = (preferredEndpoint != null && preferredEndpoint.isNotEmpty)
        ? preferredEndpoint
        : (serverEp.isNotEmpty ? serverEp : kWarpEndpoints.first);

    return WarpConfig(
      privateKey: keys.privateKey,
      publicKey: keys.publicKey,
      peerPublicKey: peerPub,
      addressV4: v4,
      addressV6: v6,
      endpoint: endpoint,
      reserved: reserved,
      deviceId: (result['id'] ?? '') as String,
      token: (result['token'] ?? '') as String,
      registeredAt: DateTime.now().toUtc().toIso8601String(),
    );
  } on WarpException {
    rethrow;
  } on SocketException catch (e) {
    throw WarpException('اتصال به سرور WARP برقرار نشد: ${e.message}');
  } on HttpException catch (e) {
    throw WarpException('خطای HTTP: ${e.message}');
  } on FormatException {
    throw const WarpException('پاسخ سرور WARP قابل‌خواندن نبود');
  } catch (e) {
    throw WarpException('ثبت‌نام WARP ناموفق: $e');
  } finally {
    client.close(force: true);
  }
}

/// Parse one standard WireGuard client configuration into the Xray profile model.
/// Multiple peers are rejected explicitly because the current app exposes one active
/// WireGuard peer per profile rather than silently merging different peers.
WarpConfig parseWireGuardConf(String text) {
  final iface = <String, String>{};
  final peer = <String, String>{};
  var section = '';
  var peerCount = 0;

  for (final raw in text.split(RegExp(r'[\r\n]+'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      section = line.substring(1, line.length - 1).trim().toLowerCase();
      if (section == 'peer') {
        peerCount++;
        if (peerCount > 1) {
          throw const FormatException(
            'این نسخه از برنامه در هر پروفایل فقط یک بخش [Peer] را پشتیبانی می‌کند',
          );
        }
      }
      if (section != 'interface' && section != 'peer') {
        throw FormatException('بخش [$section] در پروفایل پشتیبانی نمی‌شود');
      }
      continue;
    }
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    final key = line.substring(0, separator).trim().toLowerCase();
    final value = line.substring(separator + 1).trim();
    if (section == 'interface') {
      iface[key] = value;
    } else if (section == 'peer') {
      peer[key] = value;
    }
  }

  List<int>? decodeKey(String value) {
    try {
      return base64.decode(base64.normalize(value));
    } catch (_) {
      try {
        return base64Url.decode(base64Url.normalize(value));
      } catch (_) {
        return null;
      }
    }
  }

  bool validKey(String value) => decodeKey(value)?.length == 32;

  bool validCidr(String value) {
    final parts = value.split('/');
    if (parts.length != 2) return false;
    final address = InternetAddress.tryParse(parts[0].trim());
    final prefix = int.tryParse(parts[1].trim());
    if (address == null || prefix == null) return false;
    final maxPrefix = address.type == InternetAddressType.IPv4 ? 32 : 128;
    return prefix >= 0 && prefix <= maxPrefix;
  }

  final privateKey = iface['privatekey'] ?? '';
  if (!validKey(privateKey)) {
    throw const FormatException(
      'PrivateKey معتبر نیست؛ باید یک کلید Base64 با ۳۲ بایت باشد',
    );
  }
  final peerPublicKey = peer['publickey'] ?? '';
  if (!validKey(peerPublicKey)) {
    throw const FormatException(
      'PublicKey بخش [Peer] معتبر نیست؛ باید یک کلید Base64 با ۳۲ بایت باشد',
    );
  }

  final preSharedKey = (peer['presharedkey'] ?? '').trim();
  if (preSharedKey.isNotEmpty && !validKey(preSharedKey)) {
    throw const FormatException('PresharedKey معتبر نیست؛ باید یک کلید Base64 با ۳۲ بایت باشد');
  }

  var addressV4 = '';
  var addressV6 = '';
  for (final rawAddress in (iface['address'] ?? '').split(',')) {
    var address = rawAddress.trim();
    if (address.isEmpty) continue;
    final parsed = InternetAddress.tryParse(address.split('/').first);
    if (parsed == null) {
      throw FormatException('آدرس Interface نامعتبر است: $address');
    }
    if (!address.contains('/')) {
      address += parsed.type == InternetAddressType.IPv4 ? '/32' : '/128';
    }
    if (!validCidr(address)) {
      throw FormatException('طول پیشوند آدرس نامعتبر است: $address');
    }
    if (parsed.type == InternetAddressType.IPv4 && addressV4.isEmpty) {
      addressV4 = address;
    } else if (parsed.type == InternetAddressType.IPv6 && addressV6.isEmpty) {
      addressV6 = address;
    }
  }
  if (addressV4.isEmpty) {
    throw const FormatException('آدرس IPv4 در بخش [Interface] پیدا نشد');
  }

  final endpoint = (peer['endpoint'] ?? '').trim();
  if (endpoint.isEmpty) {
    throw const FormatException('Endpoint بخش [Peer] الزامی است؛ مقصد پیش‌فرض Cloudflare اعمال نمی‌شود');
  }
  final endpointUri = Uri.tryParse('udp://$endpoint');
  if (endpointUri == null ||
      endpointUri.host.isEmpty ||
      !endpointUri.hasPort ||
      endpointUri.port < 1 ||
      endpointUri.port > 65535) {
    throw const FormatException('Endpoint باید به‌شکل host:port یا [IPv6]:port باشد');
  }

  final allowedIPs = (peer['allowedips'] ?? '')
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  if (allowedIPs.any((value) => !validCidr(value))) {
    throw const FormatException('AllowedIPs باید شامل آدرس‌های معتبر CIDR باشد');
  }

  final keepAliveText = (peer['persistentkeepalive'] ?? '').trim();
  final keepAlive = keepAliveText.isEmpty ? 0 : int.tryParse(keepAliveText);
  if (keepAlive == null || keepAlive < 0 || keepAlive > 65535) {
    throw const FormatException('PersistentKeepalive باید عددی بین 0 تا 65535 باشد');
  }

  final mtuText = (iface['mtu'] ?? '').trim();
  final interfaceMtu = mtuText.isEmpty ? null : int.tryParse(mtuText);
  if (mtuText.isNotEmpty &&
      (interfaceMtu == null || interfaceMtu < 576 || interfaceMtu > 9000)) {
    throw const FormatException('MTU باید عددی بین 576 تا 9000 باشد');
  }

  final dnsServers = (iface['dns'] ?? '')
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  if (dnsServers.any((value) => InternetAddress.tryParse(value) == null)) {
    throw const FormatException(
      'DNS باید فقط شامل آدرس‌های IPv4 یا IPv6 باشد؛ Xray remoteDNS نام دامنه را قبول نمی‌کند',
    );
  }

  var reserved = <int>[0, 0, 0];
  final reservedText = (iface['reserved'] ?? peer['reserved'] ?? '').trim();
  if (reservedText.isNotEmpty) {
    final parts = reservedText
        .replaceAll(RegExp(r'[\[\]\s]'), '')
        .split(',')
        .map(int.tryParse)
        .toList();
    if (parts.length != 3 ||
        parts.any((value) => value == null || value < 0 || value > 255)) {
      throw const FormatException('Reserved باید دقیقاً سه عدد بین 0 تا 255 باشد');
    }
    reserved = [for (final value in parts) value!];
  }

  final base = List<int>.filled(32, 0)..[0] = 9;
  final publicKey = base64Encode(x25519(decodeKey(privateKey)!, base));
  return WarpConfig(
    privateKey: privateKey,
    publicKey: publicKey,
    peerPublicKey: peerPublicKey,
    preSharedKey: preSharedKey,
    addressV4: addressV4,
    addressV6: addressV6,
    endpoint: endpoint,
    reserved: reserved,
    allowedIPs: allowedIPs,
    dnsServers: dnsServers,
    keepAlive: keepAlive,
    interfaceMtu: interfaceMtu,
    deviceId: '',
    token: '',
    registeredAt: 'imported',
  );
}
