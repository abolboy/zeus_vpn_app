import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:zeus_vpn/main.dart';

void main() {
  test('sanitizes credential-bearing values from core logs', () {
    final safe = sanitizeCoreLogLine(
      'failed vless://user:secret@example.com:443 token=super-secret',
    );
    expect(safe, isNot(contains('user:secret')));
    expect(safe, isNot(contains('super-secret')));
    expect(safe, contains('[share URI redacted]'));
    expect(safe, contains('token=[redacted]'));
  });

  group('WARP profile validation', () {
    test('accepts a complete WireGuard profile', () {
      final key = base64.encode(List<int>.filled(32, 9));
      final config = jsonEncode({
        'protocol': 'wireguard',
        'settings': {
          'secretKey': key,
          'address': ['172.16.0.2/32'],
          'peers': [
            {
              'publicKey': key,
              'endpoint': '162.159.192.1:2408',
              'allowedIPs': ['0.0.0.0/0', '::/0'],
            },
          ],
        },
      });
      expect(warpConfigurationError(config), isNull);
    });

    test('rejects malformed or incomplete WireGuard profiles', () {
      expect(warpConfigurationError(null), isNotNull);
      expect(warpConfigurationError('{broken-json'), isNotNull);
      expect(
        warpConfigurationError(jsonEncode({
          'protocol': 'wireguard',
          'settings': {
            'secretKey': 'bad-key',
            'address': ['172.16.0.2/32'],
            'peers': [],
          },
        })),
        isNotNull,
      );
    });
  });

  group('PATT-NG preflight validation', () {
    test('requires valid VLESS TCP REALITY parameters', () {
      final key = base64Url.encode(List<int>.filled(32, 7));
      final validLink =
          'vless://11111111-1111-4111-8111-111111111111@example.com:443'
          '?security=tls&type=tcp&sni=example.com&pbk=$key';
      final patt = Patt()..reality = true;
      expect(pattConfigurationError(validLink, patt), isNull);

      expect(
        pattConfigurationError(
          'trojan://secret@example.com:443?security=tls',
          patt,
        ),
        isNotNull,
      );
      expect(
        pattConfigurationError(
          'vless://11111111-1111-4111-8111-111111111111@example.com:443'
          '?security=tls&type=ws&sni=example.com&pbk=$key',
          patt,
        ),
        isNotNull,
      );
    });

    test('rejects Vision flow on incompatible transport or security', () {
      final patt = Patt()..flow = 'xtls-rprx-vision';
      expect(
        pattConfigurationError(
          'vless://11111111-1111-4111-8111-111111111111@example.com:443'
          '?security=none&type=tcp',
          patt,
        ),
        isNotNull,
      );
    });

    test('validates fragmentation and MUX values before connecting', () {
      final badFragment = Patt()
        ..frag = 'tlshello'
        ..fragLen = '200-100';
      expect(
        pattConfigurationError(
          'vless://11111111-1111-4111-8111-111111111111@example.com:443',
          badFragment,
        ),
        isNotNull,
      );

      final badMux = Patt()
        ..mux = true
        ..muxConc = '0';
      expect(
        pattConfigurationError(
          'vless://11111111-1111-4111-8111-111111111111@example.com:443',
          badMux,
        ),
        isNotNull,
      );
    });
  });

  group('subscription URL display privacy', () {
    test('hides path tokens, credentials, query values and fragments', () {
      const source =
          'https://alice:secret@example.com/private-token?access=top-secret#frag';
      final label = subscriptionDisplayLabel(source);
      expect(label, contains('https://example.com/•••'));
      expect(label, contains('credentials hidden'));
      expect(label, contains('query hidden'));
      expect(label, contains('fragment hidden'));
      expect(label, isNot(contains('alice')));
      expect(label, isNot(contains('secret')));
      expect(label, isNot(contains('private-token')));
      expect(label, isNot(contains('top-secret')));
    });
  });

  group('direct share URI validation', () {
    test('accepts a complete VLESS link', () {
      expect(
        directShareUriError(
          'vless://11111111-1111-4111-8111-111111111111@example.com:443?security=tls',
        ),
        isNull,
      );
    });

    test('accepts a complete Trojan link', () {
      expect(directShareUriError('trojan://secret@example.com:443'), isNull);
    });

    test('rejects missing host, port, or credentials', () {
      expect(directShareUriError('vless://user@:443'), isNotNull);
      expect(directShareUriError('vless://user@example.com'), isNotNull);
      expect(directShareUriError('trojan://@example.com:443'), isNotNull);
    });

    test('accepts a decoded VMess profile and rejects malformed payloads', () {
      final profile = base64.encode(utf8.encode(jsonEncode({
        'add': 'node.example.com',
        'port': '443',
        'id': '11111111-1111-4111-8111-111111111111',
      })));
      expect(directShareUriError('vmess://$profile#test'), isNull);
      expect(directShareUriError('vmess://not-base64-json'), isNotNull);
    });
  });

  test('ServerNode keeps source and effective URIs separate', () {
    const sourceUri = 'vless://user@example.com:443?security=tls#source';
    const effectiveUri = 'vless://user@example.com:443?security=tls&fp=chrome#source';

    final node = ServerNode(
      subTag: 'SUB-1',
      rawUri: effectiveUri,
      baseUri: sourceUri,
      displayName: '[SUB-1] source',
    );

    expect(node.baseUri, sourceUri);
    expect(node.rawUri, effectiveUri);
    expect(node.displayName, '[SUB-1] source');
  });
  test('TLS certificate pin parameters are represented in generated config', () {
    const link = 'vless://11111111-1111-4111-8111-111111111111@example.com:443'
        '?encryption=none&security=tls&sni=example.com&fp=chrome'
        '&pcs=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA%3D&vcn=example.com#pin-test';
    final config = jsonDecode(V2ray.parseFromURL(link).getFullConfiguration());

    bool hasKey(dynamic value, String key) {
      if (value is Map) {
        if (value.containsKey(key)) return true;
        return value.values.any((item) => hasKey(item, key));
      }
      if (value is List) return value.any((item) => hasKey(item, key));
      return false;
    }

    expect(hasKey(config, 'pinnedPeerCertSha256'), isTrue);
    expect(hasKey(config, 'verifyPeerCertByName'), isTrue);
  });

  test('PATT defaults preserve imported flow and ALPN while removing TLS bypass', () {
    const link = 'vless://11111111-1111-4111-8111-111111111111@example.com:443'
        '?security=tls&flow=xtls-rprx-vision&alpn=h2&allowInsecure=1#preserve-test';
    final effective = Uri.parse(applyPattQuery(link, Patt()));

    expect(effective.queryParameters['flow'], 'xtls-rprx-vision');
    expect(effective.queryParameters['alpn'], 'h2');
    expect(effective.queryParameters.containsKey('allowInsecure'), isFalse);
  });

  test('explicit none overrides remove inherited flow and ALPN', () {
    const link = 'vless://11111111-1111-4111-8111-111111111111@example.com:443'
        '?security=tls&flow=xtls-rprx-vision&alpn=h2#remove-test';
    final patt = Patt()
      ..flow = 'none'
      ..alpn = 'none';
    final effective = Uri.parse(applyPattQuery(link, patt));

    expect(effective.queryParameters.containsKey('flow'), isFalse);
    expect(effective.queryParameters.containsKey('alpn'), isFalse);
  });

  test('network preserve keeps an imported transport', () {
    const link = 'vless://11111111-1111-4111-8111-111111111111@example.com:443'
        '?security=tls&type=ws&path=%2Fsocket#network-preserve';
    final effective = Uri.parse(applyPattQuery(link, Patt()));

    expect(effective.queryParameters['type'], 'ws');
  });

  test('explicit TCP selection overrides an imported WebSocket transport', () {
    const link = 'vless://11111111-1111-4111-8111-111111111111@example.com:443'
        '?security=tls&type=ws&path=%2Fsocket#network-override';
    final patt = Patt()..network = 'tcp';
    final effective = Uri.parse(applyPattQuery(link, patt));

    expect(effective.queryParameters['type'], 'tcp');
  });

  test('flow is not injected into VLESS without TLS or REALITY', () {
    const link = 'vless://11111111-1111-4111-8111-111111111111@example.com:443'
        '?security=none#no-flow-test';
    final patt = Patt()..flow = 'xtls-rprx-vision';
    final effective = Uri.parse(applyPattQuery(link, patt));

    expect(effective.queryParameters.containsKey('flow'), isFalse);
  });

}
