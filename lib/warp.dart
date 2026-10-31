  import 'dart:convert';
  import 'dart:io';
  import 'dart:math';
  import 'dart:typed_data';
  import 'package:dio/dio.dart';
  import 'package:dio/io.dart';
  import 'package:flutter/foundation.dart';

  // ============================================================
  //  X25519 (RFC 7748)
  //  همهٔ ورودی‌های modPow قبل از فراخوانی به [0, p) کاهش می‌یابند.
  // ============================================================
  final BigInt _p255 = (BigInt.one << 255) - BigInt.from(19);
  final BigInt _a24 = BigInt.from(121665);

  BigInt _le2int(Uint8List b) {
    BigInt r = BigInt.zero;
    for (int i = b.length - 1; i >= 0; i--) {
      r = (r << 8) | BigInt.from(b[i]);
    }
    return r;
  }

  Uint8List _int2le(BigInt v, int len) {
    final out = Uint8List(len);
    for (int i = 0; i < len; i++) {
      out[i] = (v & BigInt.from(255)).toInt();
      v = v >> 8;
    }
    return out;
  }

  Uint8List clampKey(Uint8List kIn) {
    final k = Uint8List.fromList(kIn);
    k[0] &= 248;
    k[31] &= 127;
    k[31] |= 64;
    return k;
  }

  Uint8List x25519(Uint8List kIn, Uint8List uIn) {
    final e = _le2int(clampKey(kIn));
    final u = (_le2int(uIn) & ((BigInt.one << 255) - BigInt.one)) % _p255;
    BigInt x1 = u, x2 = BigInt.one, z2 = BigInt.zero, x3 = u, z3 = BigInt.one;
    int swap = 0;
    for (int t = 254; t >= 0; t--) {
      final b = ((e >> t) & BigInt.one).toInt();
      if (swap != b) {
        final tx = x2; x2 = x3; x3 = tx;
        final tz = z2; z2 = z3; z3 = tz;
      }
      swap = b;
      final A = (x2 + z2) % _p255;
      final AA = A.modPow(BigInt.two, _p255);
      final B = (x2 - z2) % _p255;
      final BB = B.modPow(BigInt.two, _p255);
      final E = (AA - BB) % _p255;
      final C = (x3 + z3) % _p255;
      final D = (x3 - z3) % _p255;
      final DA = (D * A) % _p255;
      final CB = (C * B) % _p255;
      x3 = (DA + CB) % _p255;
      x3 = x3.modPow(BigInt.two, _p255);
      z3 = (DA - CB) % _p255;
      z3 = (x1 * z3.modPow(BigInt.two, _p255)) % _p255;
      x2 = (AA * BB) % _p255;
      z2 = (E * ((AA + _a24 * E) % _p255)) % _p255;
    }
    if (swap == 1) {
      final tx = x2; x2 = x3; x3 = tx;
      final tz = z2; z2 = z3; z3 = tz;
    }
    final inv = z2.modPow(_p255 - BigInt.two, _p255);
    return _int2le((x2 * inv) % _p255, 32);
  }

  class WarpKeys {
    final String priv;
    final String pub;
    const WarpKeys(this.priv, this.pub);
  }

  WarpKeys _genKeysSync(int _) {
    final rnd = Random.secure();
    final k = clampKey(Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256))));
    final pub = x25519(k, Uint8List(32)..[0] = 9);
    return WarpKeys(base64.encode(k), base64.encode(pub));
  }

  /// تولید کلید در isolate جدا → UI فریز نمی‌شود
  Future<WarpKeys> genWarpKeys() => compute(_genKeysSync, 0);

  // ============================================================
  //  Registration
  // ============================================================
  class WarpException implements Exception {
    final String message;
    const WarpException(this.message);
    @override
    String toString() => message;
  }

  const List<String> warpEndpoints = [
    'engage.cloudflareclient.com:2408',
    '188.114.97.1:2408',
    '188.114.96.1:2408',
    '162.159.195.1:2408',
    '188.114.98.224:4500',
    '162.159.192.1:2408',
  ];

  Future<Map<String, dynamic>> registerWarp(
    WarpKeys kp, {
    String endpoint = 'engage.cloudflareclient.com:2408',
    int? proxyPort,
    String? licenseKey,
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent': '1.1.1.1/6.81',
        'CF-Client-Version': 'a-6.81-2410012252.0',
        'Accept': 'application/json; charset=UTF-8',
        'Content-Type': 'application/json',
      },
    ));
    if (proxyPort != null) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort',
      );
    }

    Map<String, dynamic> d;
    try {
      final res = await dio.post('https://api.cloudflareclient.com/v0a2483/reg', data: {
        'key': kp.pub,
        'install_id': '',
        'fcm_token': '',
        'tos': DateTime.now().toUtc().toIso8601String(),
        'type': 'Android',
        'model': 'PC',
        'locale': 'en_US',
      });
      d = res.data is String ? jsonDecode(res.data as String) as Map<String, dynamic> : res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403) throw const WarpException('Cloudflare blocked this IP (403). Connect to a node first, then register.');
      if (code == 429) throw const WarpException('Rate limited (429). Try again in a few minutes.');
      throw WarpException(code != null ? 'HTTP $code' : 'Network: ${e.type.name}');
    } finally {
      dio.close(force: true);
    }

    if (licenseKey != null && licenseKey.isNotEmpty) {
      try {
        final id = d['id'] as String;
        final token = d['token'] as String;
        final dio2 = Dio(BaseOptions(headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}));
        await dio2.put('https://api.cloudflareclient.com/v0a2483/reg/$id/account', data: {'license': licenseKey});
        dio2.close();
      } catch (_) {}
    }

    try {
      final cfg = d['config'] as Map<String, dynamic>;
      final iface = cfg['interface'] as Map<String, dynamic>;
      final addrs = iface['addresses'] as Map<String, dynamic>;
      final v4 = addrs['v4'] as String?;
      final v6 = addrs['v6'] as String?;
      if (v4 == null || v4.isEmpty) throw const WarpException('No v4 address in response');

      final peer = (cfg['peers'] as List)[0] as Map<String, dynamic>;
      final peerPub = peer['public_key'] as String;

      String? cid = cfg['client_id'] as String?;
      if (cid == null || cid.isEmpty) {
        final ids = cfg['client_ids'];
        if (ids is List && ids.isNotEmpty) cid = ids[0] as String?;
      }
      if (cid == null || cid.isEmpty) throw const WarpException('No client_id in response');
      final reserved = base64.decode(base64.normalize(cid)).toList();
      if (reserved.length != 3) throw WarpException('Bad reserved length: ${reserved.length}');

      return {
        'tag': 'warp',
        'protocol': 'wireguard',
        'settings': {
          'secretKey': kp.priv,
          'address': [
            '$v4/32',
            if (v6 != null && v6.isNotEmpty) '$v6/128',
          ],
          'peers': [
            {
              'publicKey': peerPub,
              'endpoint': endpoint,
              'allowedIPs': ['0.0.0.0/0', '::/0'],
              'keepAlive': 25,
            }
          ],
          'reserved': reserved,
          'mtu': 1280,
          'noKernelTun': true,
          'domainStrategy': 'ForceIP',
        },
      };
    } on WarpException {
      rethrow;
    } catch (e) {
      throw WarpException('Unexpected response: ${e.toString().split('\n').first}');
    }
  }
