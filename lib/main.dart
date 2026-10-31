  // ============================================================
  //  ZEUS VPN — PATCHED CORE LOGIC
  //  متدهای زیر را در _HomePageState جایگزین نسخه‌های فعلی کنید.
  //  تغییرات Patt: پیش‌فرض flow='keep' و alpn='' (مقدار خود نود حفظ شود)
  // ============================================================

  // ---------- Patt defaults (در کلاس Patt) ----------
  //   String flow = 'keep';
  //   String alpn = '';
  // و در _loadPatt:
  //   _patt.flow = p.getString('p_flow') ?? 'keep';
  //   _patt.alpn = p.getString('p_alpn') ?? '';

  static const String _kNodeCache = 'nodes_cache_v1';

  // ---------- BOOT: لود کش نودها قبل از سینک (فیکس #3) ----------
  Future<void> _boot() async {
    final p = await SharedPreferences.getInstance();
    _subs = p.getStringList('subs') ?? [];
    _selUri = p.getString('sel');
    _warpOn = p.getBool('warp_on') ?? false;
    _warpJson = p.getString('warp_json');
    if (_warpJson != null && _warpJson!.isEmpty) _warpJson = null;
    _loadPatt(p);
    _loadNodeCache(p);

    var coreOk = true;
    try {
      await _v2ray.initialize(
        notificationIconResourceType: "mipmap",
        notificationIconResourceName: "ic_launcher",
      );
    } catch (_) {
      coreOk = false;
    }
    if (!mounted) return;
    setState(() => _ready = coreOk);
    if (!coreOk) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _snack('Core failed to initialize.', err: true));
    }
    if (_subs.isNotEmpty) _syncAll();
  }

  void _loadNodeCache(SharedPreferences p) {
    try {
      final raw = p.getString(_kNodeCache);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _nodes = list.map((m) {
        final base = m['b'] as String;
        final tag = m['t'] as String;
        return ServerNode(subTag: tag, rawUri: _linkFor(base), baseUri: base, displayName: '[$tag] ${_name(base)}');
      }).toList();
      if (_selUri != null && !_nodes.any((n) => n.baseUri == _selUri) && _nodes.isNotEmpty) {
        _selUri = _nodes.first.baseUri;
      }
    } catch (_) {}
  }

  Future<void> _saveNodeCache() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNodeCache, jsonEncode(_nodes.map((n) => {'t': n.subTag, 'b': n.baseUri}).toList()));
  }

  /// لینک نهایی از baseUri همیشه در لحظه ساخته می‌شود (فیکس #4)
  String _linkFor(String base) => base.startsWith('vmess://') ? base : _injectQuery(base);

  // ---------- INJECT QUERY (فیکس #1, #2, #16) ----------
  String _injectQuery(String uri) {
    try {
      final u = Uri.parse(uri);
      final q = Map<String, String>.from(u.queryParameters);
      if (_patt.reality && _patt.pbk.isNotEmpty) {
        q['security'] = 'reality';
        q['pbk'] = _patt.pbk;
        if (_patt.sid.isNotEmpty) q['sid'] = _patt.sid;
        if (_patt.spx.isNotEmpty) q['spx'] = _patt.spx;
      }
      final secNow = q['security'] ?? 'none';
      final netNow = _patt.network != 'tcp' ? _patt.network : (q['type'] ?? 'tcp');

      // Fingerprint: 'unsafe' = حفظ مقدار نود، ولی TLS/REALITY بدون fp → chrome
      if (_patt.fp != 'unsafe') {
        q['fp'] = _patt.fp;
      } else if ((secNow == 'tls' || secNow == 'reality') && (q['fp'] ?? '').isEmpty) {
        q['fp'] = 'chrome';
      }

      // Flow: فقط وقتی کاربر صراحتاً خواسته؛ 'keep' = مقدار خود نود
      if (_patt.flow != 'keep') {
        final ok = u.scheme == 'vless' && netNow == 'tcp' && (secNow == 'tls' || secNow == 'reality') && _patt.flow != 'none';
        if (ok) {
          q['flow'] = _patt.flow;
        } else {
          q.remove('flow');
        }
      } else if (netNow != 'tcp') {
        q.remove('flow'); // flow فقط روی TCP معتبر است
      }

      // ALPN: خالی = مقدار نود. برای ws/httpupgrade هرگز h2 تزریق نکن.
      if (_patt.alpn.isNotEmpty) {
        final wsLike = netNow == 'ws' || netNow == 'httpupgrade';
        if (wsLike) {
          q['alpn'] = 'http/1.1';
        } else if (netNow == 'grpc') {
          q['alpn'] = 'h2';
        } else {
          q['alpn'] = _patt.alpn;
        }
      }

      if (_patt.sni.isNotEmpty) q['sni'] = _patt.sni;
      if (_patt.path.isNotEmpty && _patt.path != '/') q['path'] = _patt.path;
      if (_patt.host.isNotEmpty) q['host'] = _patt.host;
      if (_patt.headerType != 'none') q['headerType'] = _patt.headerType;
      if (_patt.network.isNotEmpty && _patt.network != 'tcp') q['type'] = _patt.network;
      return u.replace(queryParameters: q).toString();
    } catch (_) {
      return uri;
    }
  }

  // ---------- INJECT CORE (فیکس #5, #6, #7, #8) ----------
  /// اگر هستهٔ باندل‌شده finalmask را نمی‌شناسد این را false کنید.
  static const bool _coreHasFinalmask = true;

  void _applyTlsExtras(Map<String, dynamic> main) {
    final stream = main['streamSettings'] as Map<String, dynamic>?;
    if (stream == null || stream['security'] != 'tls') return;
    final tls = (stream['tlsSettings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    if (_patt.cs.isNotEmpty) tls['cipherSuites'] = _patt.cs;
    if (_patt.pcs.isNotEmpty) tls['pinnedPeerCertificateChainSha256'] = [_patt.pcs];
    if (_patt.vcn.isNotEmpty) tls['verifyPeerCertInNames'] = [_patt.vcn];
    stream['tlsSettings'] = tls;
  }

  Map<String, dynamic> _fragmentMask(bool reality) => {
    'type': 'fragment',
    'settings': {
      'packets': reality ? '1-3' : _patt.frag,
      'lengths': [_range(_patt.fragLen, '100-200', min: 1)],
      'delays': [_range(_patt.fragInt, '10-20')],
    },
  };

  Map<String, dynamic> _noiseMask() => {
    'type': 'noise',
    'settings': {
      'reset': '30-60',
      'noise': [
        {_patt.noiseType == 'rand' ? 'rand' : 'str': _range(_patt.noisePacket, '10-20', min: 1), 'delay': _range(_patt.noiseDelay, '10-20')},
      ],
    },
  };

  void _applyFinalmask(Map<String, dynamic> ob, {bool tcp = true, bool udp = true}) {
    final stream = (ob['streamSettings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final fm = (stream['finalmask'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    if (tcp && _patt.frag != 'none') {
      final l = (fm['tcp'] as List?) ?? <dynamic>[];
      l.insert(0, _fragmentMask(stream['security'] == 'reality'));
      fm['tcp'] = l;
    }
    if (udp && _patt.noise) {
      final l = (fm['udp'] as List?) ?? <dynamic>[];
      l.add(_noiseMask());
      fm['udp'] = l;
    }
    if (fm.isNotEmpty) {
      stream['finalmask'] = fm;
      ob['streamSettings'] = stream;
    }
  }

  /// Fallback برای هسته‌های قدیمی: fragment با freedom + dialerProxy
  void _applyLegacyFragment(Map<String, dynamic> main, List outs) {
    if (_patt.frag == 'none') return;
    final stream = (main['streamSettings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final sockopt = (stream['sockopt'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    sockopt['dialerProxy'] = 'fragment';
    stream['sockopt'] = sockopt;
    main['streamSettings'] = stream;
    outs.removeWhere((o) => o is Map && o['tag'] == 'fragment');
    outs.add({
      'tag': 'fragment',
      'protocol': 'freedom',
      'settings': {
        'fragment': {
          'packets': stream['security'] == 'reality' ? '1-3' : 'tlshello',
          'length': _range(_patt.fragLen, '100-200', min: 1),
          'interval': _range(_patt.fragInt, '10-20'),
        },
        if (_patt.noise) 'noises': [{'type': 'rand', 'packet': _range(_patt.noisePacket, '10-20', min: 1), 'delay': _range(_patt.noiseDelay, '10-20')}],
      },
      'streamSettings': {'sockopt': {'tcpNoDelay': true}},
    });
  }

  String _injectCore(String config) {
    try {
      final json = jsonDecode(config) as Map<String, dynamic>;
      final outs = json['outbounds'] as List?;
      if (outs == null || outs.isEmpty) return config;
      var main = outs[0] as Map<String, dynamic>;
      json['log'] = {'loglevel': _patt.logLevel};

      // DNS: DoH باید از داخل پروکسی برود (https:// نه https+local://)
      if (_patt.dnsMode == 'doh') {
        json['dns'] = {'servers': ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query'], 'queryStrategy': 'UseIP'};
      } else if (_patt.dnsMode == 'custom' && _patt.customDns.isNotEmpty) {
        json['dns'] = {'servers': _patt.customDns.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()};
      }

      final warpActive = _warpOn && _warpJson != null && _warpJson!.isNotEmpty;
      if (warpActive) {
        final w = jsonDecode(_warpJson!) as Map<String, dynamic>;
        w['tag'] = (main['tag'] ?? 'proxy').toString();
        outs[0] = w;
        main = w;
        // WARP = WireGuard/UDP → فقط noise معنی دارد (فیکس #6)
        if (_coreHasFinalmask) _applyFinalmask(main, tcp: false, udp: true);
      } else {
        _applyTlsExtras(main);
        final hasFlow = RegExp(r'"flow":"xtls').hasMatch(jsonEncode(main['settings'] ?? <String, dynamic>{}));
        if (_patt.mux && !hasFlow) main['mux'] = {'enabled': true, 'concurrency': int.tryParse(_patt.muxConc) ?? 8};
        if (_coreHasFinalmask) {
          _applyFinalmask(main);
        } else {
          _applyLegacyFragment(main, outs);
        }
      }

      if (_patt.bypassLan) _addLanBypass(json, outs);
      json['outbounds'] = outs;
      return jsonEncode(json);
    } catch (_) {
      return config;
    }
  }

  // ---------- SYNC (فیکس #3, #14): موازی، بدون پاک‌کردن نودها، با کش ----------
  Future<void> _syncAll() async {
    final gen = ++_syncGen;
    if (_subs.isEmpty) {
      setState(() {
        _loading = false;
        _nodes = [];
        _selUri = null;
      });
      _saveNodeCache();
      _refreshNodes?.call();
      return;
    }
    final prev = _selUri;
    setState(() => _loading = true);

    final results = await Future.wait(List.generate(_subs.length, (i) => _fetchSub(_subs[i], 'SUB-${i + 1}')));
    if (!mounted || gen != _syncGen) return;

    final got = results.expand((e) => e).toList();
    final okCount = results.where((e) => e.isNotEmpty).length;

    setState(() {
      if (got.isNotEmpty) {
        _nodes = got;
      } else if (_nodes.isNotEmpty) {
        // شبکه قطع است؛ نودهای کش‌شده را نگه دار تا کاربر بتواند وصل شود
        WidgetsBinding.instance.addPostFrameCallback((_) => _snack('Sync failed — using cached nodes', err: true));
      }
      if (prev != null && _nodes.any((n) => n.baseUri == prev)) {
        _selUri = prev;
      } else if (_nodes.isNotEmpty) {
        _selUri = _nodes.first.baseUri;
      } else {
        _selUri = null;
      }
      _loading = false;
    });
    if (got.isNotEmpty) {
      _saveNodeCache();
      if (okCount < _subs.length) _snack('${_subs.length - okCount} sub(s) failed', err: true);
    }
    _refreshNodes?.call();
    _pingAll();
  }

  Future<List<ServerNode>> _fetchSub(String url, String tag) async {
    final out = <ServerNode>[];
    try {
      final res = await _dio.get(url, options: Options(headers: {'User-Agent': 'v2rayNG/1.8.5'}, responseType: ResponseType.plain));
      String body = res.data.toString().trim();
      final compact = body.replaceAll(RegExp(r'\s'), '');
      try {
        body = utf8.decode(base64.decode(base64.normalize(compact)));
      } catch (_) {
        try {
          body = utf8.decode(base64Url.decode(base64Url.normalize(compact)));
        } catch (_) {}
      }
      for (final raw in body.split(RegExp(r'\r?\n')).map((e) => e.trim())) {
        if (raw.startsWith('vless://') || raw.startsWith('trojan://') || raw.startsWith('vmess://')) {
          out.add(ServerNode(subTag: tag, rawUri: _linkFor(raw), baseUri: raw, displayName: '[$tag] ${_name(raw)}'));
        }
      }
    } catch (_) {}
    return out;
  }

  // ---------- PING ONE (فیکس #9): تست REAL با همان کانفیگ اتصال ----------
  Future<void> _pingOne(ServerNode n) async {
    void setPing(String text, Color c) {
      if (!mounted) return;
      setState(() {
        n.pingText = text;
        n.pingColor = c;
      });
      _refreshNodes?.call();
    }
    Color colorOf(int ms) => ms < 200 ? GREEN : (ms < 500 ? AMBER : MAGENTA);

    if (_delayMode == 1) {
      try {
        final parser = V2ray.parseFromURL(_linkFor(n.baseUri));
        final ms = await _v2ray.getServerDelay(config: _injectCore(parser.getFullConfiguration()));
        if (ms <= 0) throw Exception('timeout');
        setPing('$ms ms', colorOf(ms));
      } catch (_) {
        setPing('TIMEOUT', MAGENTA);
      }
      return;
    }
    try {
      final hp = _hostPort(n.rawUri);
      if (hp == null || hp.value == 0) throw Exception('no port');
      final sw = Stopwatch()..start();
      final s = await Socket.connect(hp.key, hp.value, timeout: const Duration(seconds: 3));
      sw.stop();
      s.destroy();
      setPing('${sw.elapsedMilliseconds} ms', colorOf(sw.elapsedMilliseconds));
    } catch (_) {
      setPing('TIMEOUT', MAGENTA);
    }
  }

  // ---------- TOGGLE (فیکس #4, #11) ----------
  Future<void> _toggle() async {
    if (!_ready) {
      _snack('Core is initializing...', err: true);
      return;
    }
    if (_busy) return;
    _busy = true;
    try {
      if (_connected || _connecting) {
        await _v2ray.stopV2Ray(); // در حالت CONNECTING هم قابل لغو است
        return;
      }
      final idx = _nodes.indexWhere((n) => n.baseUri == _selUri);
      if (idx < 0) {
        _snack(_loading ? 'Syncing nodes, wait...' : 'First select a node.', err: true);
        return;
      }
      final ok = await _v2ray.requestPermission();
      if (!ok) {
        _snack('VPN permission denied.', err: true);
        return;
      }
      // لینک همیشه از baseUri با تنظیمات فعلی ساخته می‌شود — نه نسخه‌ی کهنه‌ی زمان سینک
      final parser = V2ray.parseFromURL(_linkFor(_nodes[idx].baseUri));
      final config = _injectCore(parser.getFullConfiguration());
      await _v2ray.startV2Ray(remark: parser.remark, config: config, proxyOnly: false);
    } catch (e) {
      final msg = e.toString().split('\n').first;
      _snack('Core error: ${msg.length > 90 ? msg.substring(0, 90) : msg}', err: true);
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timeCtl.dispose();
    _pulseCtl.dispose();
    _ringCtl.dispose();
    _dio.close(force: true);
    super.dispose();
  }
// 1) در _openPatt: انتهای showModalBottomSheet(...) اضافه کنید:
).then((_) { if (mounted) setState(() {}); });

// 2) دراپ‌داون FLOW:
_dd('FLOW', ['keep', 'xtls-rprx-vision', 'none'], _patt.flow, ...)

// 3) دراپ‌داون ALPN ('' یعنی مقدار خود نود — اول لیست باشد):
_dd('ALPN (empty = keep node value)', ['', 'h2,http/1.1', 'h2', 'http/1.1'], _patt.alpn, ...)

// 4) FRAGMENT: اجازه دهید packets هم انتخاب شود
_dd('FRAGMENT', ['tlshello', '1-1', '1-2', '1-3', 'none'], _patt.frag, ...)
