  // ============================================================
  //  CONFIG BUILDING — TLS extras / Fragment / Noise
  //  جایگزین کامل از _applyTlsExtras تا _applyLegacyFragment
  // ============================================================

  /// cs / pcs / vcn پارامتر share-link نیستند؛ باید مستقیم در tlsSettings بروند
  void _applyTlsExtras(Map<String, dynamic> main) {
    final stream = main['streamSettings'] as Map<String, dynamic>?;
    if (stream == null || stream['security'] != 'tls') return;
    final tls = (stream['tlsSettings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    if (_patt.cs.isNotEmpty) tls['cipherSuites'] = _patt.cs;
    if (_patt.pcs.isNotEmpty) tls['pinnedPeerCertificateChainSha256'] = [_patt.pcs];
    if (_patt.vcn.isNotEmpty) tls['verifyPeerCertInNames'] = [_patt.vcn];
    stream['tlsSettings'] = tls;
  }

  /// بلوک fragment برای finalmask (Xray >= 25.10)
  Map<String, dynamic> _fragmentMask(bool reality) {
    return {
      'type': 'fragment',
      'settings': {
        'packets': reality ? '1-3' : _patt.frag,
        'lengths': [_range(_patt.fragLen, '100-200', min: 1)],
        'delays': [_range(_patt.fragInt, '10-20')],
      },
    };
  }

  /// بلوک noise برای finalmask (Xray >= 25.10)
  /// 'rand' = بازهٔ عددی (طول بایت‌های تصادفی)، 'str' = رشتهٔ ثابت
  Map<String, dynamic> _noiseMask() {
    final isStr = _patt.noiseType == 'str';
    final entry = <String, dynamic>{
      if (isStr) 'str': _patt.noisePacket else 'rand': _range(_patt.noisePacket, '10-20', min: 1),
      'delay': _range(_patt.noiseDelay, '10-20'),
    };
    return {
      'type': 'noise',
      'settings': {
        'reset': '30-60',
        'noise': [entry],
      },
    };
  }

  /// اعمال finalmask روی یک outbound
  /// tcp=false برای WARP (WireGuard فقط UDP است)
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

  /// Fallback برای هسته‌های قدیمی (Xray < 25.10):
  /// outbound اصلی از طریق sockopt.dialerProxy به یک freedom با fragment/noises وصل می‌شود
  void _applyLegacyFragment(Map<String, dynamic> main, List outs) {
    if (_patt.frag == 'none' && !_patt.noise) return;

    final stream = (main['streamSettings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final sockopt = (stream['sockopt'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    sockopt['dialerProxy'] = 'fragment';
    stream['sockopt'] = sockopt;
    main['streamSettings'] = stream;

    final isStr = _patt.noiseType == 'str';
    final settings = <String, dynamic>{};

    if (_patt.frag != 'none') {
      settings['fragment'] = {
        'packets': stream['security'] == 'reality' ? '1-3' : _patt.frag,
        'length': _range(_patt.fragLen, '100-200', min: 1),
        'interval': _range(_patt.fragInt, '10-20'),
      };
    }

    if (_patt.noise) {
      settings['noises'] = [
        {
          'type': isStr ? 'str' : 'rand',
          'packet': isStr ? _patt.noisePacket : _range(_patt.noisePacket, '10-20', min: 1),
          'delay': _range(_patt.noiseDelay, '10-20'),
        }
      ];
    }

    outs.removeWhere((o) => o is Map && o['tag'] == 'fragment');
    outs.add({
      'tag': 'fragment',
      'protocol': 'freedom',
      'settings': settings,
      'streamSettings': {
        'sockopt': {'tcpNoDelay': true},
      },
    });
  }
