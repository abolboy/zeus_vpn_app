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
  final u = _le2int(uIn) % _p255;
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
    z3 = z3.modPow(BigInt.two, _p255);
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

Future<Map<String, dynamic>?> registerWarp(WarpKeys kp) async {
  try {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'User-Agent': 'okhttp/3.12.1', 'Content-Type': 'application/json'},
    ));
    final res = await dio.post('https://api.cloudflareclient.com/v0a2158/reg', data: {
      'key': kp.pub,
      'install_id': '',
      'fcm_token': '',
      'locale': 'en_US',
      'type': 'Android',
      'model': 'Pixel',
      'tz': 'UTC',
    });
    final d = res.data as Map<String, dynamic>;
    final cfg = d['config'] as Map<String, dynamic>;
    final iface = cfg['interface'] as Map<String, dynamic>;
    final addr = (iface['addresses'] as Map<String, dynamic>)['v4'] as String;
    final peer = (cfg['peers'] as List)[0] as Map<String, dynamic>;
    final peerPub = peer['public_key'] as String;
    final ep = peer['endpoint'] as Map<String, dynamic>;
    String endpoint = (ep['v4'] as String?) ?? '';
    if (endpoint.isEmpty) endpoint = '${ep['host']}:2408';
    List<int> reserved = [];
    try {
      final cid = cfg['client_ids'];
      if (cid is List && cid.isNotEmpty) {
        reserved = base64.decode(cid[0] as String).toList();
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
  } catch (_) {
    return null;
  }
}
