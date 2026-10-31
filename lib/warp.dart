  // lib/warp.dart
  // ثبت‌نام Cloudflare WARP و ساخت outbound WireGuard برای Xray.
  // وابستگی: فقط dart:io / dart:convert / dart:math (بدون پکیج خارجی)

  import 'dart:convert';
  import 'dart:io';
  import 'dart:math';

  // ───────────────────────── Endpoints ─────────────────────────

  /// endpointهای شناخته‌شدهٔ WARP (اولی پیش‌فرض است)
  const List<String> kWarpEndpoints = <String>[
    'engage.cloudflareclient.com:2408',
    '162.159.192.1:2408',
    '162.159.195.1:2408',
    '188.114.96.1:2408',
    '188.114.97.1:2408',
    '162.159.192.1:500',
    '162.159.192.1:1701',
    '162.159.192.1:4500',
    '[2606:4700:d0::a29f:c001]:2408',
  ];

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
    final String privateKey;      // کلید خصوصی ما (base64)
    final String publicKey;       // کلید عمومی ما (base64)
    final String peerPublicKey;   // کلید عمومی Cloudflare
    final String addressV4;       // مثل 172.16.0.2/32
    final String addressV6;       // مثل 2606:4700:110:...:/128 (ممکن است خالی باشد)
    final String endpoint;        // host:port
    final List<int> reserved;     // ۳ بایت
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
    });

    WarpConfig copyWith({String? endpoint}) => WarpConfig(
          privateKey: privateKey,
          publicKey: publicKey,
          peerPublicKey: peerPublicKey,
          addressV4: addressV4,
          addressV6: addressV6,
          endpoint: endpoint ?? this.endpoint,
          reserved: reserved,
          deviceId: deviceId,
          token: token,
          registeredAt: registeredAt,
        );

    Map<String, dynamic> toJson() => <String, dynamic>{
          'privateKey': privateKey,
          'publicKey': publicKey,
          'peerPublicKey': peerPublicKey,
          'addressV4': addressV4,
          'addressV6': addressV6,
          'endpoint': endpoint,
          'reserved': reserved,
          'deviceId': deviceId,
          'token': token,
          'registeredAt': registeredAt,
        };

    factory WarpConfig.fromJson(Map<String, dynamic> j) => WarpConfig(
          privateKey: (j['privateKey'] ?? '') as String,
          publicKey: (j['publicKey'] ?? '') as String,
          peerPublicKey: (j['peerPublicKey'] ?? '') as String,
          addressV4: (j['addressV4'] ?? '172.16.0.2/32') as String,
          addressV6: (j['addressV6'] ?? '') as String,
          endpoint: (j['endpoint'] ?? kWarpEndpoints.first) as String,
          reserved: ((j['reserved'] as List?) ?? const [0, 0, 0])
              .map((e) => (e as num).toInt())
              .toList(),
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

    bool get isValid =>
        privateKey.isNotEmpty && peerPublicKey.isNotEmpty && addressV4.isNotEmpty;

    /// outbound آمادهٔ Xray (پروتکل wireguard)
    Map<String, dynamic> toXrayOutbound({
      String tag = 'warp',
      String? endpointOverride,
      int mtu = 1280,
      int workers = 2,
      bool includeV6 = true,
    }) {
      final addrs = <String>[addressV4];
      if (includeV6 && addressV6.isNotEmpty) addrs.add(addressV6);
      return <String, dynamic>{
        'tag': tag,
        'protocol': 'wireguard',
        'settings': <String, dynamic>{
          'secretKey': privateKey,
          'address': addrs,
          'peers': <Map<String, dynamic>>[
            <String, dynamic>{
              'publicKey': peerPublicKey,
              'endpoint': endpointOverride ?? endpoint,
              'keepAlive': 25,
            },
          ],
          'reserved': reserved,
          'mtu': mtu,
          'workers': workers,
          'domainStrategy': includeV6 && addressV6.isNotEmpty
              ? 'ForceIPv4v6'
              : 'ForceIPv4',
        },
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
        throw WarpException(
            'Cloudflare درخواست را رد کرد (403). IP شما مسدود است؛ با VPN/پروکسی دیگر تلاش کنید.', 403);
      }
      if (code == 429) {
        throw WarpException('تعداد درخواست زیاد است (429). چند دقیقه بعد دوباره تلاش کنید.', 429);
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
