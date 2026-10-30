import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cryptography/cryptography.dart';

/// Ensures a WireGuard interface address has exactly one CIDR suffix.
/// Cloudflare responses may already include the prefix.
String normalizeWarpInterfaceAddress(String address, int prefixLength) {
  final value = address.trim();
  if (value.isEmpty) return value;
  return value.contains('/') ? value : '$value/$prefixLength';
}

class WarpKeys {
  final String priv;
  final String pub;
  WarpKeys(this.priv, this.pub);
}

Future<WarpKeys> genWarpKeys() async {
  final algorithm = X25519();
  final keyPair = await algorithm.newKeyPair();
  try {
    final privateKey = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    if (privateKey.length != 32 || publicKey.bytes.length != 32) {
      throw StateError('X25519 must return 32-byte private and public keys.');
    }
    return WarpKeys(
      base64.encode(privateKey),
      base64.encode(publicKey.bytes),
    );
  } finally {
    keyPair.destroy();
  }
}

Future<Map<String, dynamic>?> registerWarp(WarpKeys kp) async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'User-Agent': 'okhttp/3.12.1', 'Content-Type': 'application/json'},
  ));
  try {
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
    final interfaceAddresses = iface['addresses'] as Map<String, dynamic>;
    final addr = interfaceAddresses['v4'] as String;
    final addresses = <String>[normalizeWarpInterfaceAddress(addr, 32)];
    final addrV6 = interfaceAddresses['v6'] as String?;
    if (addrV6 != null && addrV6.trim().isNotEmpty) {
      addresses.add(normalizeWarpInterfaceAddress(addrV6, 128));
    }
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
        'address': addresses,
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
  } finally {
    dio.close(force: true);
  }
}
