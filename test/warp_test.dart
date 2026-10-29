import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeus_vpn/warp.dart';

String _toHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List _fromHex(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    bytes[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return bytes;
}

void main() {
  group('WARP key derivation', () {
    test('X25519 matches the RFC 7748 Alice public-key vector', () {
      final alicePrivate = _fromHex(
        '77076d0a7318a57d3c16c17251b26645'
        'df4c2f87ebc0992ab177fba51db92c2a',
      );
      final basePoint = Uint8List(32)..[0] = 9;

      expect(
        _toHex(x25519(alicePrivate, basePoint)),
        '8520f0098930a754748b7ddcb43ef75a'
        '0dbf3a0d26381af4eba4a98eaa9b4e6a',
      );
    });

    test('generated WARP keys are valid 32-byte base64 values', () {
      final keys = genWarpKeys();

      expect(base64.decode(keys.priv), hasLength(32));
      expect(base64.decode(keys.pub), hasLength(32));
    });
  });
}
