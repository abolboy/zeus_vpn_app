import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zeus_vpn/core/credential_vault.dart';
import 'package:zeus_vpn/core/clash_import.dart';
import 'package:zeus_vpn/core/config_builder.dart';
import 'package:zeus_vpn/core/free_profiles.dart';
import 'package:zeus_vpn/core/models.dart';
import 'package:zeus_vpn/warp.dart';

List<int> _hex(String s) => [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];
String _toHex(List<int> b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};
  bool failReads = false;
  bool failWrites = false;
  bool failDeletes = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('simulated secure read failure');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('simulated secure write failure');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes) throw StateError('simulated secure delete failure');
    values.remove(key);
  }
}

void main() {
  group('credential vault migration', () {
    test('writes encrypted value before removing legacy plaintext', () async {
      SharedPreferences.setMockInitialValues({'subs_v2': 'legacy-subscription-secret'});
      final preferences = await SharedPreferences.getInstance();
      final secure = _MemorySecureKeyValueStore();
      final vault = CredentialVault(storage: secure);

      final value = await vault.readAndMigrate(preferences, 'subs_v2');

      expect(value, 'legacy-subscription-secret');
      expect(secure.values['subs_v2'], 'legacy-subscription-secret');
      expect(preferences.getString('subs_v2'), isNull);
    });

    test('retains plaintext when secure migration write fails', () async {
      SharedPreferences.setMockInitialValues({'warp_json': 'legacy-private-key-json'});
      final preferences = await SharedPreferences.getInstance();
      final secure = _MemorySecureKeyValueStore()..failWrites = true;
      final vault = CredentialVault(storage: secure);

      final value = await vault.readAndMigrate(preferences, 'warp_json');

      expect(value, 'legacy-private-key-json');
      expect(preferences.getString('warp_json'), 'legacy-private-key-json');
      expect(secure.values.containsKey('warp_json'), isFalse);
    });

    test('secure read failure falls back to legacy value without deleting it', () async {
      SharedPreferences.setMockInitialValues({'warp_json': 'legacy-profile'});
      final preferences = await SharedPreferences.getInstance();
      final secure = _MemorySecureKeyValueStore()..failReads = true;
      final vault = CredentialVault(storage: secure);

      expect(await vault.readAndMigrate(preferences, 'warp_json'), 'legacy-profile');
      expect(preferences.getString('warp_json'), 'legacy-profile');
      expect(secure.values.containsKey('warp_json'), isFalse);
    });

    test('encrypted value takes precedence and removes old duplicate', () async {
      SharedPreferences.setMockInitialValues({'sel': 'old-server-uri'});
      final preferences = await SharedPreferences.getInstance();
      final secure = _MemorySecureKeyValueStore()
        ..values['sel'] = 'encrypted-server-uri';
      final vault = CredentialVault(storage: secure);

      expect(await vault.readAndMigrate(preferences, 'sel'), 'encrypted-server-uri');
      expect(preferences.getString('sel'), isNull);
    });

    test('new writes go only to secure storage and deletion happens there first', () async {
      SharedPreferences.setMockInitialValues({'nodes_cache': 'old-cache'});
      final preferences = await SharedPreferences.getInstance();
      final secure = _MemorySecureKeyValueStore();
      final vault = CredentialVault(storage: secure);

      await vault.write(preferences, 'nodes_cache', 'new-server-cache');
      expect(secure.values['nodes_cache'], 'new-server-cache');
      expect(preferences.getString('nodes_cache'), isNull);

      await vault.delete(preferences, 'nodes_cache');
      expect(secure.values.containsKey('nodes_cache'), isFalse);
      expect(preferences.getString('nodes_cache'), isNull);
    });

    test('failed secure writes never delete the existing legacy value', () async {
      SharedPreferences.setMockInitialValues({'settings_json': 'legacy-settings'});
      final preferences = await SharedPreferences.getInstance();
      final secure = _MemorySecureKeyValueStore()..failWrites = true;
      final vault = CredentialVault(storage: secure);

      await expectLater(
        vault.write(preferences, 'settings_json', 'new-settings'),
        throwsStateError,
      );
      expect(preferences.getString('settings_json'), 'legacy-settings');
    });
  });

  group('sensitive log redaction', () {
    test('hides share URIs and query-bearing subscription URLs', () {
      const input =
          'Sub failed: vless://123e4567-e89b-12d3-a456-426614174000@vpn.example:443?security=tls '
          'while requesting https://feed.example/sub?token=secret-value';
      final output = redactSensitiveLogText(input);

      expect(output, isNot(contains('123e4567-e89b-12d3-a456-426614174000')));
      expect(output, isNot(contains('secret-value')));
      expect(output, contains('vpn.example'));
      expect(output, contains('feed.example'));
      expect(output, contains('[REDACTED]'));
    });

    test('redacts plain and JSON credential fields plus Bearer and Basic headers', () {
      const input =
          'PrivateKey = U0VDUkVUS0VZ AccessToken: abc.def.ghi '
          'Authorization: Bearer token-value '
          '{"privateKey":"json-private-value","preSharedKey":"json-psk-value"} '
          'Authorization: Basic dXNlcjpwYXNzd29yZA==';
      final output = redactSensitiveLogText(input);

      for (final secret in [
        'U0VDUkVUS0VZ',
        'abc.def.ghi',
        'token-value',
        'json-private-value',
        'json-psk-value',
        'dXNlcjpwYXNzd29yZA==',
      ]) {
        expect(output, isNot(contains(secret)), reason: 'Leaked $secret');
      }
      expect(output, contains('[REDACTED]'));
    });
  });

  group('subscription URL security', () {
    test('accepts HTTPS URLs, including non-default ports and query tokens', () {
      expect(
        isSecureSubscriptionUrl('https://feed.example:8443/sub?token=abc'),
        isTrue,
      );
    });

    test('rejects cleartext, non-HTTP, relative, and hostless URLs', () {
      expect(isSecureSubscriptionUrl('http://feed.example/sub'), isFalse);
      expect(isSecureSubscriptionUrl('ftp://feed.example/sub'), isFalse);
      expect(isSecureSubscriptionUrl('/relative/sub'), isFalse);
      expect(isSecureSubscriptionUrl('https:///sub'), isFalse);
      expect(isSecureSubscriptionUrl('  '), isFalse);
    });
  });

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

    test('WireGuard conf import preserves a standard AWS-style profile', () {
      final priv = base64Encode(List<int>.filled(32, 7));
      final peer = base64Encode(List<int>.filled(32, 9));
      final psk = base64Encode(List<int>.filled(32, 11));
      final cfg = parseWireGuardConf(
        '[Interface]\n'
        'PrivateKey = $priv\n'
        'Address = 10.8.0.2/32, fd00::2/128\n'
        'DNS = 1.1.1.1, 2606:4700:4700::1111\n'
        'MTU = 1420\n\n'
        '[Peer]\n'
        'PublicKey = $peer\n'
        'PresharedKey = $psk\n'
        'AllowedIPs = 10.8.0.0/24, 0.0.0.0/0, ::/0\n'
        'Endpoint = 203.0.113.7:51820\n'
        'PersistentKeepalive = 25\n',
      );

      expect(cfg.addressV4, '10.8.0.2/32');
      expect(cfg.addressV6, 'fd00::2/128');
      expect(cfg.endpoint, '203.0.113.7:51820');
      expect(cfg.allowedIPs, ['10.8.0.0/24', '0.0.0.0/0', '::/0']);
      expect(cfg.preSharedKey, psk);
      expect(cfg.keepAlive, 25);
      expect(cfg.dnsServers, ['1.1.1.1', '2606:4700:4700::1111']);
      expect(cfg.interfaceMtu, 1420);
      expect(cfg.isCloudflareRegistered, isFalse);
      expect(cfg.reserved, [0, 0, 0]);
      expect(base64Decode(cfg.publicKey).length, 32);

      final outbound = cfg.toXrayOutbound();
      final settings = outbound['settings'] as Map;
      final peerSettings = (settings['peers'] as List).single as Map;
      expect(outbound['protocol'], 'wireguard');
      expect(peerSettings['allowedIPs'], cfg.allowedIPs);
      expect(peerSettings['preSharedKey'], psk);
      expect(peerSettings['keepAlive'], 25);
      expect(settings['remoteDNS'], cfg.dnsServers);

      expect(
        () => parseWireGuardConf('[Interface]\nPrivateKey = $priv\nAddress = 1.2.3.4/32\n[Peer]\nPublicKey = $peer\n'),
        throwsFormatException,
        reason: 'An absent endpoint must never silently switch to a Cloudflare endpoint.',
      );
      expect(() => parseWireGuardConf('[Interface]\nAddress = 1.2.3.4/32'), throwsFormatException);
      expect(
        () => parseWireGuardConf(
          '[Interface]\nPrivateKey = $priv\nAddress = 10.8.0.2/32\n'
          '[Peer]\nPublicKey = $peer\nEndpoint = 203.0.113.7:51820\n'
          '[Peer]\nPublicKey = $peer\nEndpoint = 203.0.113.8:51820\n',
        ),
        throwsFormatException,
      );
    });

    test('config round-trip and Xray outbound retains WireGuard peer fields', () {
      final privateKey = base64Encode(List<int>.filled(32, 7));
      final publicKey = base64Encode(List<int>.filled(32, 8));
      final peerKey = base64Encode(List<int>.filled(32, 9));
      final psk = base64Encode(List<int>.filled(32, 10));
      final cfg = WarpConfig(
        privateKey: privateKey,
        publicKey: publicKey,
        peerPublicKey: peerKey,
        preSharedKey: psk,
        addressV4: '172.16.0.2/32',
        addressV6: '',
        endpoint: '203.0.113.7:51820',
        reserved: [1, 2, 3],
        allowedIPs: const ['10.20.0.0/16'],
        dnsServers: const ['10.20.0.2'],
        keepAlive: 15,
        interfaceMtu: 1380,
        deviceId: 'device-id',
        token: 'token',
        registeredAt: 'now',
      );
      final back = WarpConfig.tryDecode(cfg.encode());
      expect(back?.isValid, true);
      expect(back?.isCloudflareRegistered, true);
      expect(back?.preSharedKey, psk);
      expect(back?.allowedIPs, ['10.20.0.0/16']);
      expect(back?.dnsServers, ['10.20.0.2']);
      expect(back?.keepAlive, 15);

      final out = back!.toXrayOutbound(tag: 'wireguard', mtu: 1280);
      final settings = out['settings'] as Map;
      final peer = (settings['peers'] as List).single as Map;
      expect(out['protocol'], 'wireguard');
      expect(settings['reserved'], [1, 2, 3]);
      expect(settings['mtu'], 1280, reason: 'The app MTU selection remains the active override.');
      expect(peer['preSharedKey'], psk);
      expect(peer['allowedIPs'], ['10.20.0.0/16']);
      expect(peer['keepAlive'], 15);
    });

    test('WireGuard-only mode routes the Xray proxy through the imported peer', () {
      final privateKey = base64Encode(List<int>.filled(32, 1));
      final publicKey = base64Encode(List<int>.filled(32, 2));
      final peerKey = base64Encode(List<int>.filled(32, 3));
      final psk = base64Encode(List<int>.filled(32, 4));
      final profile = WarpConfig(
        privateKey: privateKey,
        publicKey: publicKey,
        peerPublicKey: peerKey,
        preSharedKey: psk,
        addressV4: '10.8.0.2/32',
        addressV6: '',
        endpoint: '203.0.113.8:51820',
        reserved: const [0, 0, 0],
        allowedIPs: const ['0.0.0.0/0'],
        dnsServers: const ['1.1.1.1'],
        keepAlive: 25,
        deviceId: '',
        token: '',
        registeredAt: 'imported',
      );

      final config = ConfigBuilder(
        patt: Patt(),
        warp: profile,
        warpOn: true,
        warpMtu: 1420,
      ).buildWarpOnly();

      final outbounds = (config['outbounds'] as List).cast<Map>();
      final wireGuard = outbounds.firstWhere((outbound) => outbound['tag'] == 'proxy');
      final settings = wireGuard['settings'] as Map;
      final peers = (settings['peers'] as List).cast<Map>();
      final peer = peers.single;

      expect(wireGuard['protocol'], 'wireguard');
      expect(settings['secretKey'], privateKey);
      expect(settings['mtu'], 1420);
      expect(settings['remoteDNS'], ['1.1.1.1']);
      expect(peer['publicKey'], peerKey);
      expect(peer['preSharedKey'], psk);
      expect(peer['allowedIPs'], ['0.0.0.0/0']);
      expect(peer['endpoint'], '203.0.113.8:51820');
      expect(peer['keepAlive'], 25);

      final rules = ((config['routing'] as Map)['rules'] as List).cast<Map>();
      expect(rules.last['outboundTag'], 'proxy');
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
