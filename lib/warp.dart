import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';

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

Uint8List x25519(Uint8List kIn, Uint8List uIn) {
  final k = Uint8List.fromList(kIn);
  k[0] &= 248;
  k[31] &= 127;
  k[31] |= 64;
  final e = _le2int(k);
  final u = (_le2int(uIn) & ((BigInt.one << 255) - BigInt.one)) % _p255;
  BigInt x1 = u, x2 = BigInt.one, z2 = BigInt.zero, x3 = u, z3 = BigInt.one;
  int swap = 0;
  for (int t = 254; t >= 0; t--) {
    final b = ((e >> t) & BigInt.one).toInt();
    if (swap != b) {
      BigInt tx = x2; x2 = x3; x3 = tx;
      BigInt tz = z2; z2 = z3; z3 = tz;
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
    BigInt tx = x2; x2 = x3; x3 = tx;
    BigInt tz = z2; z2 = z3; z3 = tz;
  }
  final inv = z2.modPow(_p255 - BigInt.two, _p255);
  return _int2le((x2 * inv) % _p255, 32);
}

class WarpKeys {
  final String priv;
  final String pub;
  WarpKeys(this.priv, this.pub);
}

WarpKeys genWarpKeys() {
  final rnd = Random.secure();
  final k = Uint8List(32);
  for (int i = 0; i < 32; i++) {
    k[i] = rnd.nextInt(256);
  }
  final pub = x25519(k, Uint8List(32)..[0] = 9);
  return WarpKeys(base64.encode(k), base64.encode(pub));
}

String warpLastError = '';

Future<Map<String, dynamic>?> registerWarp(WarpKeys kp) async {
  warpLastError = '';
  try {
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
    final res = await dio.post('https://api.cloudflareclient.com/v0a2483/reg', data: {
      'key': kp.pub,
      'install_id': '',
      'fcm_token': '',
      'tos': DateTime.now().toUtc().toIso8601String(),
      'type': 'Android',
      'model': 'PC',
      'locale': 'en_US',
    });
    final d = res.data as Map<String, dynamic>;
    final cfg = d['config'] as Map<String, dynamic>;
    final iface = cfg['interface'] as Map<String, dynamic>;
    final addr = (iface['addresses'] as Map<String, dynamic>)['v4'] as String;
    final peer = (cfg['peers'] as List)[0] as Map<String, dynamic>;
    final peerPub = peer['public_key'] as String;
    final ep = peer['endpoint'] as Map<String, dynamic>;
    // Cloudflare returns v4 as "IP:0"; the real WireGuard port comes from "host" (2408).
    final hostStr = (ep['host'] as String?) ?? '';
    final hostName = hostStr.contains(':') ? hostStr.substring(0, hostStr.lastIndexOf(':')) : hostStr;
    var port = hostStr.contains(':') ? (int.tryParse(hostStr.substring(hostStr.lastIndexOf(':') + 1)) ?? 2408) : 2408;
    if (port == 0) port = 2408;
    final v4Str = (ep['v4'] as String?) ?? '';
    final v4Ip = v4Str.contains(':') ? v4Str.substring(0, v4Str.lastIndexOf(':')) : v4Str;
    final epHost = v4Ip.isNotEmpty ? v4Ip : (hostName.isNotEmpty ? hostName : 'engage.cloudflareclient.com');
    final endpoint = '$epHost:$port';
    List<int> reserved = [];
    try {
      // Cloudflare returns a single base64 string in "client_id" (3 bytes).
      String? cid = cfg['client_id'] as String?;
      if (cid == null || cid.isEmpty) {
        final ids = cfg['client_ids'];
        if (ids is List && ids.isNotEmpty) cid = ids[0] as String?;
      }
      if (cid != null && cid.isNotEmpty) {
        reserved = base64.decode(base64.normalize(cid)).toList();
      }
    } catch (_) {}
    return {
      'tag': 'warp',
      'protocol': 'wireguard',
      'settings': {
        'secretKey': kp.priv,
        'address': ['$addr/32'],
        'peers': [
          {'publicKey': peerPub, 'endpoint': endpoint, 'allowedIPs': ['0.0.0.0/0', '::/0']}
        ],
        if (reserved.isNotEmpty) 'reserved': reserved,
        'mtu': 1280,
        'noKernelTun': true,
      },
    };
  } on DioException catch (e) {
    final code = e.response?.statusCode;
    warpLastError = code != null ? 'HTTP $code' : e.type.name;
    return null;
  } catch (_) {
    warpLastError = 'unexpected response';
    return null;
  }
}
