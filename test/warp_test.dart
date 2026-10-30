import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeus_vpn/warp.dart';

String _toHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

List<int> _fromHex(String hex) {
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return bytes;
}

void main() {
  group('WARP interface addresses', () {
    test('does not duplicate an existing IPv4 prefix', () {
      expect(normalizeWarpInterfaceAddress('172.16.0.2/32', 32), '172.16.0.2/32');
    });

    test('adds missing IPv4 and IPv6 prefixes', () {
      expect(normalizeWarpInterfaceAddress('172.16.0.2', 32), '172.16.0.2/32');
      expect(normalizeWarpInterfaceAddress('2606:4700:110:abcd::1', 128), '2606:4700:110:abcd::1/128');
    });
  });

  group('WARP key derivation', () {
    test('X25519 matches the RFC 7748 Alice public-key vector', () async {
      final alicePrivate = _fromHex(
        '77076d0a7318a57d3c16c17251b26645'
        'df4c2f87ebc0992ab177fba51db92c2a',
      );
      final algorithm = X25519();
      final keyPair = await algorithm.newKeyPairFromSeed(alicePrivate);
      try {
        final publicKey = await keyPair.extractPublicKey();
        expect(
          _toHex(publicKey.bytes),
          '8520f0098930a754748b7ddcb43ef75a'
          '0dbf3a0d26381af4eba4a98eaa9b4e6a',
        );
      } finally {
        keyPair.destroy();
      }
    });

    test('generated WARP keys are valid 32-byte base64 values', () async {
      final keys = await genWarpKeys();
      expect(base64.decode(keys.priv), hasLength(32));
      expect(base64.decode(keys.pub), hasLength(32));
    });
  });
}
