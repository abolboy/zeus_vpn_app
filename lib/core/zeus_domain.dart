/// Pure domain models, validation, and Xray configuration helpers for ZEUS VPN.
/// This library intentionally contains no widget state or platform side effects.
import 'dart:convert';

import 'package:flutter/material.dart';

class ServerNode {
  final String subTag;
  final String rawUri;
  final String displayName;
  final String baseUri;
  final String? subscriptionUrl;
  String pingText;
  Color pingColor;
  ServerNode({
    required this.subTag,
    required this.rawUri,
    required this.displayName,
    required this.baseUri,
    this.subscriptionUrl,
    this.pingText = '--',
    this.pingColor = Colors.grey,
  });
}

/// Keeps cached nodes only for feeds that failed in the current sync.
/// Fresh direct nodes always come from the user's current direct-link list.
List<ServerNode> mergeNodesForFailedSubscriptions({
  required List<ServerNode> freshNodes,
  required List<ServerNode> cachedNodes,
  required Set<String> failedSubscriptionUrls,
}) {
  final merged = List<ServerNode>.from(freshNodes);
  final seenUris = merged.map((node) => node.baseUri).toSet();

  for (final cached in cachedNodes) {
    final source = cached.subscriptionUrl;
    if (source != null &&
        failedSubscriptionUrls.contains(source) &&
        seenUris.add(cached.baseUri)) {
      merged.add(cached);
    }
  }
  return merged;
}

class Patt {
  String fp = 'chrome';
  String cs = '';
  String pcs = '';
  String vcn = '';
  String frag = 'none';
  String fragLen = '100-200';
  String fragInt = '10-20';
  bool noise = false;
  String noiseType = 'rand';
  String noisePacket = '10-20';
  String noiseDelay = '10-20';
  bool mux = false;
  String muxConc = '8';
  bool bypassLan = false;
  String logLevel = 'warning';
  String dnsMode = 'auto';
  String customDns = '1.1.1.1';
  bool reality = false;
  String pbk = '';
  String sid = '';
  String spx = '/';
  String flow = 'preserve';
  String alpn = 'preserve';
  String sni = '';
  String path = '/';
  String host = '';
  String headerType = 'none';
  String network = 'preserve';
}

/// Shows a safe, non-secret label for a subscription URL in the UI.
/// Credentials, path tokens, query values, and fragments are never displayed.
String subscriptionDisplayLabel(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return 'HTTPS subscription';

  final port = uri.hasPort && uri.port != 443 ? ':${uri.port}' : '';
  final path = uri.path.isEmpty || uri.path == '/' ? '' : '/•••';
  final hidden = <String>[
    if (uri.userInfo.isNotEmpty) 'credentials hidden',
    if (uri.hasQuery) 'query hidden',
    if (uri.hasFragment) 'fragment hidden',
  ];
  final hiddenText = hidden.join(' · ');
  final privacyNote = hidden.isEmpty ? '' : '  •  $hiddenText';
  return 'https://${uri.host}$port$path$privacyNote';
}

/// Redacts common credential-bearing values before diagnostic logs are shown.
String sanitizeCoreLogLine(String value) {
  final withoutShareUris = value.replaceAllMapped(
    RegExp(r'(https?|vless|trojan|vmess)://[^\s]+', caseSensitive: false),
    (match) {
      final scheme = match.group(1)?.toLowerCase();
      return scheme == 'http' || scheme == 'https'
          ? '[subscription URL redacted]'
          : '[share URI redacted]';
    },
  );
  return withoutShareUris.replaceAllMapped(
    RegExp(
      r'"?(password|secret[_-]?key|private[_-]?key|access[_-]?token|refresh[_-]?token|token|authorization)"?\s*[:=]\s*"?(?:Bearer\s+)?[^"\s,;}]+"?',
      caseSensitive: false,
    ),
    (match) {
      final field = match.group(1) ?? 'credential';
      return '$field=[redacted]';
    },
  );
}

/// Returns a user-facing validation error for a direct VLESS, Trojan, or
/// VMess share URI. This is intentionally local and does not connect to hosts.
String? directShareUriError(String value) {
  final raw = value.trim();
  if (raw.length > 65536) {
    return 'The server link is too large (maximum 64 KiB).';
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || raw.isEmpty) {
    return 'Enter a valid VLESS, Trojan, or VMess link.';
  }

  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'vless' || scheme == 'trojan') {
    if (uri.host.isEmpty || !uri.hasPort || uri.port < 1 || uri.port > 65535) {
      return 'The server address or port is invalid.';
    }
    if (uri.userInfo.trim().isEmpty) {
      return scheme == 'vless'
          ? 'The VLESS user ID is missing.'
          : 'The Trojan password is missing.';
    }
    return null;
  }

  if (scheme == 'vmess') {
    final encoded = raw.substring('vmess://'.length).split('#').first.trim();
    if (encoded.isEmpty) return 'The VMess profile is empty.';
    try {
      List<int> bytes;
      try {
        bytes = base64.decode(base64.normalize(encoded));
      } catch (_) {
        bytes = base64Url.decode(base64Url.normalize(encoded));
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return 'The VMess profile is not valid JSON.';
      final host = (decoded['add'] ?? '').toString().trim();
      final port = int.tryParse((decoded['port'] ?? '').toString()) ?? 0;
      final id = (decoded['id'] ?? '').toString().trim();
      if (host.isEmpty || port < 1 || port > 65535 || id.isEmpty) {
        return 'The VMess profile needs a server, valid port, and user ID.';
      }
      return null;
    } catch (_) {
      return 'The VMess profile could not be decoded.';
    }
  }

  return 'Only VLESS, Trojan, and VMess links are supported here.';
}

/// Validates the stored WireGuard profile before it is injected into Xray.
String? warpConfigurationError(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Register a WARP device before enabling WARP.';
  }
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map || decoded['protocol'] != 'wireguard') {
      return 'The saved WARP profile is not a WireGuard outbound.';
    }
    final settings = decoded['settings'];
    if (settings is! Map) return 'The saved WARP profile has no settings.';

    bool validKey(String key) {
      try {
        final bytes = base64.decode(base64.normalize(key));
        return bytes.length == 32;
      } catch (_) {
        try {
          final bytes = base64Url.decode(base64Url.normalize(key));
          return bytes.length == 32;
        } catch (_) {
          return false;
        }
      }
    }

    final privateKey = (settings['secretKey'] ?? '').toString().trim();
    if (!validKey(privateKey)) {
      return 'The saved WARP private key is invalid. Register WARP again.';
    }

    final addresses = settings['address'];
    if (addresses is! List ||
        addresses.isEmpty ||
        addresses.any((item) => item is! String || item.trim().isEmpty)) {
      return 'The saved WARP profile has no valid interface address.';
    }

    final peers = settings['peers'];
    if (peers is! List || peers.isEmpty || peers.first is! Map) {
      return 'The saved WARP profile has no WireGuard peer.';
    }
    final peer = peers.first as Map;
    final publicKey = (peer['publicKey'] ?? '').toString().trim();
    if (!validKey(publicKey)) {
      return 'The saved WARP peer public key is invalid.';
    }
    final endpoint = (peer['endpoint'] ?? '').toString().trim();
    final endpointUri = Uri.tryParse('udp://$endpoint');
    if (endpointUri == null ||
        endpointUri.host.isEmpty ||
        !endpointUri.hasPort ||
        endpointUri.port < 1 ||
        endpointUri.port > 65535) {
      return 'The saved WARP peer endpoint is invalid.';
    }
    final allowedIPs = peer['allowedIPs'];
    if (allowedIPs is! List ||
        allowedIPs.isEmpty ||
        allowedIPs.any((item) => item is! String || item.trim().isEmpty)) {
      return 'The saved WARP peer has no allowed IP ranges.';
    }
    return null;
  } catch (_) {
    return 'The saved WARP profile is damaged. Register WARP again.';
  }
}

/// Checks advanced settings against the selected share profile before the
/// native core is started. This prevents obviously incompatible overrides.
String? pattConfigurationError(String serverUri, Patt patt) {
  final uri = Uri.tryParse(serverUri);
  if (uri == null || directShareUriError(serverUri) != null) {
    return 'The selected server profile is incomplete or invalid.';
  }

  final scheme = uri.scheme.toLowerCase();
  final query = uri.queryParameters;
  final transport = patt.network != 'preserve' && patt.network.isNotEmpty
      ? patt.network
      : (query['type'] ?? 'tcp');
  final security = patt.reality ? 'reality' : (query['security'] ?? 'none');

  if (security == 'reality') {
    if (scheme != 'vless') {
      return 'REALITY security is supported here only with VLESS profiles.';
    }
    if (transport != 'tcp') {
      return 'REALITY requires TCP transport. Change NETWORK to TCP or PRESERVE.';
    }
    final publicKey = patt.pbk.trim().isNotEmpty
        ? patt.pbk.trim()
        : (query['pbk'] ?? '').trim();
    final serverName = patt.sni.trim().isNotEmpty
        ? patt.sni.trim()
        : (query['sni'] ?? '').trim();
    if (publicKey.isEmpty) return 'REALITY public key (PBK) is required.';
    if (serverName.isEmpty) return 'REALITY server name (SNI) is required.';
    try {
      List<int> decoded;
      try {
        decoded = base64.decode(base64.normalize(publicKey));
      } catch (_) {
        decoded = base64Url.decode(base64Url.normalize(publicKey));
      }
      if (decoded.length != 32) {
        return 'REALITY public key must decode to exactly 32 bytes.';
      }
    } catch (_) {
      return 'REALITY public key must be valid Base64/Base64URL.';
    }
    final shortId = patt.sid.trim().isNotEmpty
        ? patt.sid.trim()
        : (query['sid'] ?? '').trim();
    if (shortId.isNotEmpty &&
        (!RegExp(r'^[0-9a-fA-F]{2,16}$').hasMatch(shortId) ||
            shortId.length.isOdd)) {
      return 'REALITY short ID must be an even-length hexadecimal value (up to 16 characters).';
    }
  }

  if (patt.flow == 'xtls-rprx-vision' &&
      (scheme != 'vless' ||
          transport != 'tcp' ||
          (security != 'tls' && security != 'reality'))) {
    return 'Vision flow requires VLESS over TCP with TLS or REALITY security.';
  }

  bool validRange(String value) {
    final match = RegExp(r'^(\d{1,5})-(\d{1,5})$').firstMatch(value.trim());
    if (match == null) return false;
    final low = int.tryParse(match.group(1)!) ?? 0;
    final high = int.tryParse(match.group(2)!) ?? 0;
    return low > 0 && high >= low;
  }

  if (patt.frag != 'none' &&
      (!validRange(patt.fragLen) || !validRange(patt.fragInt))) {
    return 'Fragment length and interval must be valid ranges such as 100-200.';
  }
  if (patt.noise) {
    if (!validRange(patt.noiseDelay)) {
      return 'Noise delay must be a valid range such as 10-20.';
    }

    final payload = patt.noisePacket.trim();
    bool validPayload = false;
    switch (patt.noiseType) {
      case 'rand':
        validPayload = validRange(payload);
        break;
      case 'str':
        validPayload = payload.isNotEmpty && utf8.encode(payload).length <= 1024;
        break;
      case 'hex':
        validPayload = payload.isNotEmpty &&
            payload.length.isEven &&
            payload.length <= 2048 &&
            RegExp(r'^[0-9a-fA-F]+$').hasMatch(payload);
        break;
      case 'base64':
        if (payload.isNotEmpty && payload.length <= 2048) {
          try {
            final decoded = base64.decode(base64.normalize(payload));
            validPayload = decoded.isNotEmpty && decoded.length <= 1024;
          } catch (_) {
            try {
              final decoded = base64Url.decode(base64Url.normalize(payload));
              validPayload = decoded.isNotEmpty && decoded.length <= 1024;
            } catch (_) {
              validPayload = false;
            }
          }
        }
        break;
      default:
        validPayload = false;
    }

    if (!validPayload) {
      return switch (patt.noiseType) {
        'rand' => 'Random noise packet must be a valid range such as 10-20.',
        'str' => 'String noise payload must contain 1–1024 UTF-8 bytes.',
        'hex' => 'Hex noise payload must contain an even number of hexadecimal characters.',
        'base64' => 'Base64 noise payload must decode to 1–1024 bytes.',
        _ => 'Unsupported noise type.',
      };
    }
  }
  if (patt.mux) {
    final concurrency = int.tryParse(patt.muxConc) ?? 0;
    if (concurrency < 1 || concurrency > 1024) {
      return 'MUX concurrency must be between 1 and 1024.';
    }
  }
  if (patt.dnsMode == 'custom' &&
      patt.customDns.split(',').every((server) => server.trim().isEmpty)) {
    return 'Enter at least one custom DNS server.';
  }
  return null;
}

/// Applies optional PATT-NG overrides without silently replacing fields
/// already present in an imported share URI.
String applyPattQuery(String uri, Patt patt) {
  try {
    final u = Uri.parse(uri);
    final q = Map<String, String>.from(u.queryParameters);
    q['fp'] = patt.fp;
    if (patt.cs.isNotEmpty) q['cs'] = patt.cs;
    if (patt.pcs.isNotEmpty) q['pcs'] = patt.pcs;
    if (patt.vcn.isNotEmpty) q['vcn'] = patt.vcn;
    // flutter_v2ray_client 3.5.0 removed allowInsecure; never carry an
    // obsolete TLS-verification bypass into the effective share URI.
    q.remove('allowInsecure');
    if (patt.reality) {
      q['security'] = 'reality';
      if (patt.pbk.trim().isNotEmpty) q['pbk'] = patt.pbk.trim();
      if (patt.sid.trim().isNotEmpty) q['sid'] = patt.sid.trim();
      if (patt.spx.trim().isNotEmpty && patt.spx.trim() != '/') {
        q['spx'] = patt.spx.trim();
      }
    }
    final netNow = patt.network != 'preserve' ? patt.network : (q['type'] ?? 'tcp');
    final secNow = q['security'] ?? 'none';
    if (u.scheme == 'vless' && netNow == 'tcp' && (secNow == 'tls' || secNow == 'reality')) {
      if (patt.flow == 'xtls-rprx-vision') {
        q['flow'] = patt.flow;
      } else if (patt.flow == 'none') {
        q.remove('flow');
      }
    } else {
      // Flow is only valid for VLESS over TCP with TLS or REALITY.
      q.remove('flow');
    }
    if (patt.alpn == 'none') {
      q.remove('alpn');
    } else if (patt.alpn.isNotEmpty && patt.alpn != 'preserve') {
      q['alpn'] = patt.alpn;
    }
    if (patt.sni.isNotEmpty) q['sni'] = patt.sni;
    if (patt.path.isNotEmpty && patt.path != '/') q['path'] = patt.path;
    if (patt.host.isNotEmpty) q['host'] = patt.host;
    if (patt.headerType != 'none') q['headerType'] = patt.headerType;
    if (patt.network.isNotEmpty && patt.network != 'preserve') q['type'] = patt.network;
    return u.replace(queryParameters: q).toString();
  } catch (_) {
    return uri;
  }
}

/// Adds a LAN-bypass outbound and prepends its rule without discarding
/// routing rules imported from the selected profile.
Map<String, dynamic> withLanBypass(Map<String, dynamic> config) {
  final outbounds = config['outbounds'];
  if (outbounds is! List) {
    throw const FormatException('Core configuration has no outbound list.');
  }

  final routing = config['routing'] is Map
      ? Map<String, dynamic>.from(config['routing'] as Map)
      : <String, dynamic>{};
  final rules = routing['rules'] is List
      ? List<dynamic>.from(routing['rules'] as List)
      : <dynamic>[];

  final validLanRuleIndex = rules.indexWhere((rule) {
    if (rule is! Map || rule['type'] != 'field') return false;
    final ips = rule['ip'];
    final tag = rule['outboundTag'];
    if (ips is! List ||
        !ips.contains('geoip:private') ||
        tag is! String) {
      return false;
    }
    return outbounds.any(
      (item) => item is Map &&
          item['tag'] == tag &&
          item['protocol'] == 'freedom',
    );
  });

  if (validLanRuleIndex >= 0) {
    // A LAN rule must precede catch-all or proxy rules to take effect.
    final lanRule = rules.removeAt(validLanRuleIndex);
    rules.insert(0, lanRule);
  } else {
    var directTag = 'zeus-lan-bypass';
    while (outbounds.any(
      (item) => item is Map && item['tag'] == directTag,
    )) {
      directTag = '${directTag}_';
    }
    outbounds.add({'tag': directTag, 'protocol': 'freedom'});
    rules.insert(0, {
      'type': 'field',
      'ip': ['geoip:private'],
      'outboundTag': directTag,
    });
  }

  routing.putIfAbsent('domainStrategy', () => 'AsIs');
  routing['rules'] = rules;
  config['routing'] = routing;
  return config;
}

/// Replaces all profile outbounds and profile-specific routing rules with
/// WARP-only egress, optionally retaining an explicit LAN direct route.
Map<String, dynamic> withWarpOnlyOutbound(
  Map<String, dynamic> config,
  Map<String, dynamic> warpOutbound, {
  required bool bypassLan,
}) {
  config['outbounds'] = [Map<String, dynamic>.from(warpOutbound)];
  // Imported rules may reference the selected proxy, block, or direct tags.
  // Those outbounds no longer exist in WARP-only mode.
  config.remove('routing');
  if (bypassLan) withLanBypass(config);
  return config;
}
