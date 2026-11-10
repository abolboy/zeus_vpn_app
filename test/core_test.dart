import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeus_vpn/core/clash_import.dart';
import 'package:zeus_vpn/core/free_profiles.dart';
import 'package:zeus_vpn/core/models.dart';
import 'package:zeus_vpn/warp.dart';

List<int> _hex(String s) => [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];
String _toHex(List<int> b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('subscription parsing', () {
    const plain = 'vless://u@h.example:443?security=tls#A\ntrojan://p@h2.example:443#B\nhttp://ignored.example';

    test('plain text', () => expect(parseSubscriptionBody(plain).length, 2));
    test('base64', () => expect(parseSubscriptionBody(base64Encode(utf8.encode(plain))).length, 2));
    test('empty', () => expect(parseSubscriptionBody('  '), isEmpty));
  });

  group('link parsing', () {
    test('vless reality', () {
      final p = ParsedLink.parse('vless://u@h.example:443?security=reality#Node%20A');
      expect(p.protocol, 'VLESS');
      expect(p.security, 'REALITY');
      expect(p.host, 'h.example');
      expect(p.port, 443);
      expect(p.name, 'Node A');
    });

    test('vmess', () {
      final j = base64Encode(utf8.encode(jsonEncode({'ps': 'X', 'add': '1.2.3.4', 'port': '443', 'tls': 'tls'})));
      final p = ParsedLink.parse('vmess://$j');
      expect(p.protocol, 'VMess');
      expect(p.security, 'TLS');
      expect(p.host, '1.2.3.4');
      expect(p.port, 443);
      expect(p.name, 'X');
    });
  });

  group('flagFromName', () {
    test('emoji in name', () => expect(flagFromName('🇩🇪 Berlin'), '🇩🇪'));
    test('long country word', () => expect(flagFromName('Germany Frankfurt 01'), '🇩🇪'));
    test('uppercase code', () => expect(flagFromName('US-East 01'), '🇺🇸'));
    test('english words are not countries', () => expect(flagFromName('Fast server in it at home'), '🌐'));
  });

  group('settings models', () {
    test('Patt.resetDefaults really resets', () {
      final p = Patt()
        ..mux = true
        ..frag = '1-3'
        ..sni = 'example.com';
      p.resetDefaults();
      expect(p.mux, false);
      expect(p.frag, 'none');
      expect(p.sni, '');
    });

    test('AppSettings keeps the per-app list and failover flag', () {
      final s = AppSettings()
        ..bypassApps = ['a.b', 'c.d']
        ..autoFailover = false;
      final t = AppSettings()..loadJson(s.toJson());
      expect(t.bypassApps, ['a.b', 'c.d']);
      expect(t.autoFailover, false);
    });

    test('Patt keeps blockAds and AppSettings keeps chain uri', () {
      final p = Patt()..blockAds = true;
      final q = Patt()..loadJson(p.toJson());
      expect(q.blockAds, true);
      final s = AppSettings()..chainUri = 'vless://u@h.example:443#A';
      final t = AppSettings()..loadJson(s.toJson());
      expect(t.chainUri, 'vless://u@h.example:443#A');
    });

    test('Patt keeps China/Russia bypass and AppSettings keeps ping url', () {
      final p = Patt()
        ..bypassCn = true
        ..bypassRu = true;
      final q = Patt()..loadJson(p.toJson());
      expect(q.bypassCn, true);
      expect(q.bypassRu, true);
      final s = AppSettings()..pingUrl = 'https://example.com/generate_204';
      final t = AppSettings()..loadJson(s.toJson());
      expect(t.pingUrl, 'https://example.com/generate_204');
    });

    test('Patt keeps the new routing/TLS flags', () {
      final p = Patt()
        ..blockQuic = true
        ..bypassTorrent = true
        ..mixedSni = true
        ..domainStrategy = 'IPOnDemand';
      final q = Patt()..loadJson(p.toJson());
      expect(q.blockQuic, true);
      expect(q.bypassTorrent, true);
      expect(q.mixedSni, true);
      expect(q.domainStrategy, 'IPOnDemand');
    });

    test('free profile catalog is well formed', () {
      expect(kBuiltinFreeProfiles.length, 3);
      for (final f in kBuiltinFreeProfiles) {
        expect(f.url, startsWith('https://'));
        expect(f.title, isNotEmpty);
      }
    });

    test('AppSettings keeps the grid view flag', () {
      final s = AppSettings()..gridView = false;
      final t = AppSettings()..loadJson(s.toJson());
      expect(t.gridView, false);
    });

    test('SubRecord accepts legacy string format', () {
      expect(SubRecord.fromJson('https://a.example')?.url, 'https://a.example');
    });
  });

  group('WARP', () {
    test('X25519 matches RFC 7748 section 5.2 vector', () {
      final out = x25519(
        _hex('a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4'),
        _hex('e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c'),
      );
      expect(_toHex(out), 'c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552');
    });

    test('public key derivation matches RFC 7748 section 6.1 (Alice)', () {
      final base = List<int>.filled(32, 0)..[0] = 9;
      final pub = x25519(_hex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a'), base);
      expect(_toHex(pub), '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a');
    });

    test('generated key pair is consistent', () {
      final kp = generateWarpKeyPair();
      final priv = base64Decode(kp.privateKey);
      final base = List<int>.filled(32, 0)..[0] = 9;
      expect(priv.length, 32);
      expect(base64Encode(x25519(priv, base)), kp.publicKey);
    });

    test('WireGuard conf import', () {
      final priv = base64Encode(List<int>.filled(32, 7));
      final peer = base64Encode(List<int>.filled(32, 9));
      final cfg = parseWireGuardConf('[Interface]\nPrivateKey = $priv\nAddress = 172.16.0.2/32, 2606:4700:110:8a36::1/128\n\n'
          '[Peer]\nPublicKey = $peer\nEndpoint = engage.cloudflareclient.com:2408\n');
      expect(cfg.addressV4, '172.16.0.2/32');
      expect(cfg.addressV6, '2606:4700:110:8a36::1/128');
      expect(cfg.endpoint, 'engage.cloudflareclient.com:2408');
      expect(cfg.reserved, [0, 0, 0]);
      expect(base64Decode(cfg.publicKey).length, 32);
      expect(() => parseWireGuardConf('[Interface]\nAddress = 1.2.3.4/32'), throwsFormatException);
    });

    test('config round-trip and xray outbound', () {
      final cfg = WarpConfig(
        privateKey: 'k',
        publicKey: 'p',
        peerPublicKey: 'peer',
        addressV4: '172.16.0.2/32',
        addressV6: '',
        endpoint: 'engage.cloudflareclient.com:2408',
        reserved: [1, 2, 3],
        deviceId: 'd',
        token: 't',
        registeredAt: 'now',
      );
      final back = WarpConfig.tryDecode(cfg.encode());
      expect(back?.isValid, true);
      final out = back!.toXrayOutbound(tag: 'warp');
      expect(out['protocol'], 'wireguard');
      expect((out['settings'] as Map)['reserved'], [1, 2, 3]);
    });

    test('old raw-outbound format is rejected (user must re-register)', () {
      expect(WarpConfig.tryDecode('{"protocol":"wireguard"}')?.isValid, isNot(true));
    });
  });

  group('subscription meta & built-in servers', () {
    test('reads title, userinfo and announce from comment lines', () {
      const body = '# profile-title: Test\n# subscription-userinfo: upload=10; download=20; total=100; expire=1893456000\n'
          '# announce: hello\nvless://u@h.example:443#A';
      final m = parseSubMeta(body, (_) => null);
      expect(m.title, 'Test');
      expect(m.used, 30);
      expect(m.total, 100);
      expect(m.expire, 1893456000);
      expect(m.announce, 'hello');
    });

    test('HTTP header wins and base64: prefix is decoded', () {
      final m = parseSubMeta('# profile-title: Body', (k) => k == 'profile-title' ? 'base64:${base64Encode(utf8.encode('Hello'))}' : null);
      expect(m.title, 'Hello');
    });

    test('0.0.0.0 placeholder node is dropped', () {
      expect(parseSubscriptionBody('vless://0000@0.0.0.0:1?x=1#info\nvless://u@h.example:443#A').length, 1);
    });
  });

  group('regressions v2.9.1', () {
    test('ss:// full-base64 link is parsed and normalized', () {
      // base64("aes-256-gcm:secret@1.2.3.4:8388") - the whole-body-base64 format
      const full = 'ss://YWVzLTI1Ni1nY206c2VjcmV0QDEuMi4zLjQ6ODM4OA==#TestNode';
      final p = ParsedLink.parse(full);
      expect(p.protocol, 'Shadowsocks');
      expect(p.host, '1.2.3.4');
      expect(p.port, 8388);
      expect(p.name, 'TestNode');

      final n = ServerNode.fromUri(full, 'S1');
      // rawUri must be converted to the userinfo format the core understands
      expect(n.rawUri.startsWith('ss://'), isTrue);
      expect(n.rawUri.contains('@1.2.3.4:8388'), isTrue);
      final reparsed = ParsedLink.parse(n.rawUri);
      expect(reparsed.host, '1.2.3.4');
      expect(reparsed.port, 8388);
      expect(n.port, 8388);
    });

    test('ss:// standard link stays untouched', () {
      // base64("aes-256-gcm:secret") = YWVzLTI1Ni1nY206c2VjcmV0
      const std = 'ss://YWVzLTI1Ni1nY206c2VjcmV0@1.2.3.4:8388#A';
      expect(normalizeLink(std), std);
      final p = ParsedLink.parse(std);
      expect(p.host, '1.2.3.4');
      expect(p.port, 8388);
    });

    test('non-ss links pass through normalizeLink unchanged', () {
      const v = 'vless://u@h.example:443?security=tls#A';
      expect(normalizeLink(v), v);
    });

    test('lowercase unambiguous country codes get flags', () {
      expect(flagFromName('de-01'), '🇩🇪');
      expect(flagFromName('sg premium'), '🇸🇬');
      // ambiguous english words must NOT match in lowercase
      expect(flagFromName('server us east'), '🌐');
      expect(flagFromName('Fast server in it at home'), '🌐');
      // uppercase always matches
      expect(flagFromName('US-East 01'), '🇺🇸');
    });
  });

  group('Clash subscription import', () {
    const yamlText = '''
proxies:
  - name: "A"
    type: vless
    server: example.com
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    network: ws
    tls: true
    servername: example.com
    ws-opts:
      path: /ws
      headers:
        Host: example.com
  - {name: T, type: trojan, server: t.example.com, port: 443, password: pw, sni: t.example.com}
  - {name: S, type: ss, server: 1.2.3.4, port: 8388, cipher: aes-256-gcm, password: pw}
  - {name: H, type: hysteria2, server: h.example.com, port: 443, password: x}
''';

    test('detects and converts supported proxies, counts the rest', () {
      expect(looksLikeClash(yamlText), isTrue);
      final r = parseClash(yamlText);
      expect(r.links.length, 3);
      expect(r.unsupported, 1);
      expect(r.links[0], startsWith('vless://11111111-1111-1111-1111-111111111111@example.com:443?'));
      expect(r.links[0], contains('security=tls'));
      expect(r.links[0], contains('type=ws'));
      expect(r.links[0], contains('path=%2Fws'));
      expect(r.links[1], startsWith('trojan://pw@t.example.com:443?'));
      expect(r.links[2], startsWith('ss://'));
      expect(r.links[2], contains('@1.2.3.4:8388'));
    });

    test('plain subscription is not mistaken for Clash', () {
      expect(looksLikeClash('vless://u@h.example:443#A'), isFalse);
    });
  });
}
