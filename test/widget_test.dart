import 'package:flutter_test/flutter_test.dart';
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
}
