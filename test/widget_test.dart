import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:zeus_vpn/main.dart';

void main() {
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

}
