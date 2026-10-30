import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/zeus_domain.dart';
import 'warp.dart';

const Color cyan = Color(0xFFB7FF32);
const Color magenta = Color(0xFFFF4054);
const Color green = Color(0xFF00FF6A);
const Color amber = Color(0xFFFFB800);
const Color background = Color(0xFF020603);
const Color glass = Color(0xFF071009);
const FlutterSecureStorage secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

void main() => runApp(const ZeusApp());

class ZeusApp extends StatelessWidget {
  const ZeusApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZEUS VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'monospace',
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(primary: cyan, secondary: magenta, surface: glass),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF071109),
          labelStyle: const TextStyle(color: cyan, fontSize: 11),
          hintStyle: const TextStyle(color: Color(0xFF657084), fontSize: 11),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cyan.withValues(alpha: 0.22))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cyan, width: 1.3)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
          backgroundColor: cyan.withValues(alpha: 0.1),
          foregroundColor: cyan,
          side: BorderSide(color: cyan.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        )),
      ),
      home: const HomePage(),
    );
  }
}

class _SubscriptionSheet extends StatefulWidget {
  final List<String> subscriptions;
  final List<String> directUris;
  final String Function(String) displayName;
  final ValueChanged<String> onAddSubscription;
  final ValueChanged<String> onAddDirectUri;
  final ValueChanged<int> onRemoveSubscription;
  final ValueChanged<int> onRemoveDirectUri;
  final ValueChanged<String> onValidationError;
  final Future<bool> Function() onSave;

  const _SubscriptionSheet({
    required this.subscriptions,
    required this.directUris,
    required this.displayName,
    required this.onAddSubscription,
    required this.onAddDirectUri,
    required this.onRemoveSubscription,
    required this.onRemoveDirectUri,
    required this.onValidationError,
    required this.onSave,
  });

  @override
  State<_SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends State<_SubscriptionSheet> {
  late final TextEditingController _inputController;
  bool _saving = false;

  Future<void> _saveAndSync() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _addEntry() {
    final value = _inputController.text.trim();
    final parsed = Uri.tryParse(value);
    if (parsed == null || value.isEmpty) {
      widget.onValidationError(
        'Enter an HTTPS subscription URL or VLESS/Trojan/VMess link.',
      );
      return;
    }

    final scheme = parsed.scheme.toLowerCase();
    final isDirect = const ['vless', 'trojan', 'vmess'].contains(scheme);
    if (isDirect) {
      final validationError = directShareUriError(value);
      if (validationError != null) {
        widget.onValidationError(validationError);
        return;
      }
    } else if (scheme != 'https' || parsed.host.isEmpty) {
      widget.onValidationError(
        'Only HTTPS subscriptions or VLESS/Trojan/VMess links are supported.',
      );
      return;
    }

    if (isDirect) {
      if (widget.directUris.contains(value)) {
        widget.onValidationError('This server link is already added.');
        return;
      }
      widget.onAddDirectUri(value);
    } else {
      if (widget.subscriptions.contains(value)) {
        widget.onValidationError('This subscription is already added.');
        return;
      }
      widget.onAddSubscription(value);
    }

    _inputController.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasEntries =
        widget.subscriptions.isNotEmpty || widget.directUris.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: glass,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(
          top: BorderSide(color: magenta.withValues(alpha: 0.6), width: 2),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 54,
            height: 4,
            decoration: BoxDecoration(
              color: magenta.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'SUBSCRIPTIONS',
              style: TextStyle(
                color: magenta,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addEntry(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'HTTPS feed or single VLESS / Trojan / VMess link',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.2),
                        fontSize: 11,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Add subscription or server link',
                  icon: const Icon(Icons.add_circle, color: green, size: 26),
                  onPressed: _addEntry,
                ),
              ],
            ),
          ),
          Expanded(
            child: !hasEntries
                ? Center(
                    child: Text(
                      'EMPTY',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ...widget.subscriptions.asMap().entries.map((entry) {
                        final index = entry.key;
                        final value = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: cyan.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'SUB ${index + 1}',
                                style: const TextStyle(
                                  color: magenta,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  subscriptionDisplayLabel(value),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove subscription',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: magenta,
                                  size: 20,
                                ),
                                onPressed: () {
                                  widget.onRemoveSubscription(index);
                                  setState(() {});
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                      ...widget.directUris.asMap().entries.map((entry) {
                        final index = entry.key;
                        final value = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: green.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'NODE ${index + 1}',
                                style: const TextStyle(
                                  color: green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.displayName(value),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove server link',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: magenta,
                                  size: 20,
                                ),
                                onPressed: () {
                                  widget.onRemoveDirectUri(index);
                                  setState(() {});
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cyan.withValues(alpha: 0.1),
                  side: const BorderSide(color: cyan),
                ),
                onPressed: _saving ? null : _saveAndSync,
                child: Text(
                  _saving ? 'SAVING...' : 'SAVE & SYNC',
                  style: const TextStyle(
                    color: cyan,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 20),
    maxRedirects: 5,
  ));
  List<String> _subs = [];
  List<String> _directUris = [];
  List<ServerNode> _nodes = [];
  String? _selUri;
  final Patt _patt = Patt();
  bool _ready = false;
  bool _appInForeground = true;
  bool _loading = false;
  int _syncEpoch = 0;
  Future<void> _storageWriteQueue = Future<void>.value();
  int _activeTab = 0;
  bool _connected = false;
  bool _connecting = false;
  bool _busy = false;
  String? _activeRouteLabel;
  String? _activeRouteBaseUri;
  bool _activeRouteUsesWarp = false;
  bool _testingDelay = false;
  bool _warpOn = false;
  String? _warpJson;
  int _delayMode = 0;
  String _coreDelay = '';
  String _up = '0 B/s';
  String _down = '0 B/s';
  String _dur = '00:00:00';
  VoidCallback? _refreshNodes;
  late V2ray _v2ray;
  late AnimationController _timeCtl;
  late AnimationController _pulseCtl;
  late AnimationController _ringCtl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _timeCtl = AnimationController(vsync: this, duration: const Duration(seconds: 6));
    _pulseCtl = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _ringCtl = AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04).animate(CurvedAnimation(parent: _pulseCtl, curve: Curves.easeInOut));
    WidgetsBinding.instance.addObserver(this);
    _v2ray = V2ray(onStatusChanged: (V2RayStatus s) {
      if (mounted) {
        setState(() {
          final st = s.state.toString().toUpperCase();
          _connected = st == 'CONNECTED';
          _connecting = st == 'CONNECTING' || st == 'CONNECT';
          _up = _fmt(s.uploadSpeed);
          _down = _fmt(s.downloadSpeed);
          _dur = _connected ? s.duration : '00:00:00';
          if (!_connected && !_connecting) {
            _coreDelay = '';
            _activeRouteLabel = null;
            _activeRouteBaseUri = null;
            _activeRouteUsesWarp = false;
            if (_selUri != null &&
                !_nodes.any((node) => node.baseUri == _selUri)) {
              _selUri = _nodes.isEmpty ? null : _nodes.first.baseUri;
              if (_selUri != null) _saveSelection(_selUri!);
            }
          }
        });
        _syncMotionState();
      }
    });
    _syncMotionState();
    _boot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    _syncMotionState();
  }

  void _syncMotionState() {
    final shouldAnimate = _appInForeground && _activeTab == 0;
    if (shouldAnimate) {
      if (!_timeCtl.isAnimating) _timeCtl.repeat();
      if (!_ringCtl.isAnimating) _ringCtl.repeat();
      if (_connected) {
        if (!_pulseCtl.isAnimating) _pulseCtl.repeat(reverse: true);
      } else {
        _pulseCtl.stop();
      }
    } else {
      _timeCtl.stop();
      _ringCtl.stop();
      _pulseCtl.stop();
    }
  }

  void _setActiveTab(int index) {
    if (!mounted || index == _activeTab) return;
    setState(() => _activeTab = index);
    _syncMotionState();
  }

  Future<void> _boot() async {
    final p = await SharedPreferences.getInstance();
    final legacySubs = p.getStringList('subs') ?? [];
    final legacySelection = p.getString('sel');
    _warpOn = p.getBool('warp_on') ?? false;

    // Establish legacy fallbacks first. If one secure-storage operation fails
    // midway through migration, keep any values already loaded from secure
    // storage instead of resetting the whole in-memory state.
    _subs = legacySubs;
    _selUri = legacySelection;
    _warpJson = p.getString('warp_json');

    // Subscription URLs can contain bearer credentials, selected node URIs
    // contain server credentials, and WARP config contains a private key.
    // Migrate these values to Android Keystore-backed encrypted storage.
    try {
      final storedSubs = await secureStorage.read(key: 'subscriptions_json');
      if (storedSubs != null) {
        _subs = List<String>.from(jsonDecode(storedSubs) as List);
      } else {
        _subs = legacySubs;
        if (_subs.isNotEmpty) {
          await secureStorage.write(key: 'subscriptions_json', value: jsonEncode(_subs));
        }
      }
      await p.remove('subs');

      final storedDirectUris = await secureStorage.read(key: 'direct_server_uris');
      if (storedDirectUris != null) {
        _directUris = List<String>.from(jsonDecode(storedDirectUris) as List);
      } else {
        _directUris = [];
      }

      final storedSelection = await secureStorage.read(key: 'selected_node_uri');
      _selUri = storedSelection ?? legacySelection;
      if (storedSelection == null && legacySelection != null && legacySelection.isNotEmpty) {
        await secureStorage.write(key: 'selected_node_uri', value: legacySelection);
      }
      await p.remove('sel');

      final storedWarp = await secureStorage.read(key: 'warp_json');
      if (storedWarp != null) {
        _warpJson = storedWarp;
      } else {
        final legacyWarp = p.getString('warp_json');
        _warpJson = legacyWarp;
        if (legacyWarp != null && legacyWarp.isNotEmpty) {
          await secureStorage.write(key: 'warp_json', value: legacyWarp);
        }
      }
      await p.remove('warp_json');
    } catch (_) {
      // Keep the legacy fallbacks and any secure values already loaded.
      // Do not erase legacy values when migration cannot complete.
      _snack('Secure storage unavailable; private settings migration needs attention.', err: true);
    }
    if (_warpJson != null && _warpJson!.isEmpty) _warpJson = null;
    _loadPatt(p);
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
    if (!coreOk) _snack('Core failed to initialize.', err: true);
    if (_subs.isNotEmpty || _directUris.isNotEmpty) _syncAll();
  }

  void _loadPatt(SharedPreferences p) {
    final savedFingerprint = p.getString('p_fp') ?? 'chrome';
    _patt.fp = const ['chrome', 'firefox', 'safari', 'randomized', 'randomizednoalpn'].contains(savedFingerprint) ? savedFingerprint : 'chrome';
    _patt.cs = p.getString('p_cs') ?? '';
    _patt.pcs = p.getString('p_pcs') ?? '';
    _patt.vcn = p.getString('p_vcn') ?? '';
    _patt.frag = p.getString('p_frag') ?? 'none';
    _patt.fragLen = p.getString('p_fl') ?? '100-200';
    _patt.fragInt = p.getString('p_fi') ?? '10-20';
    _patt.noise = p.getBool('p_noise') ?? false;
    _patt.noiseType = p.getString('p_nt') ?? 'rand';
    _patt.noisePacket = p.getString('p_np') ?? '10-20';
    _patt.noiseDelay = p.getString('p_nd') ?? '10-20';
    _patt.mux = p.getBool('p_mux') ?? false;
    _patt.muxConc = p.getString('p_mc') ?? '8';
    _patt.bypassLan = p.getBool('p_lan') ?? false;
    _patt.logLevel = p.getString('p_log') ?? 'warning';
    _patt.dnsMode = p.getString('p_dns') ?? 'auto';
    _patt.customDns = p.getString('p_dnsc') ?? '1.1.1.1';
    _patt.reality = p.getBool('p_real') ?? false;
    _patt.pbk = p.getString('p_pbk') ?? '';
    _patt.sid = p.getString('p_sid') ?? '';
    _patt.spx = p.getString('p_spx') ?? '/';
    _patt.flow = p.getString('p_flow') ?? 'preserve';
    _patt.alpn = p.getString('p_alpn') ?? 'preserve';
    _patt.sni = p.getString('p_sni') ?? '';
    _patt.path = p.getString('p_path') ?? '/';
    _patt.host = p.getString('p_host') ?? '';
    _patt.headerType = p.getString('p_ht') ?? 'none';
    final savedNetwork = p.getString('p_net');
    final networkSettingsVersion = p.getBool('p_net_v2') ?? false;
    // Older builds displayed TCP as the default but treated it as "preserve".
    // Migrate that legacy value once so imported WS/gRPC links keep their transport.
    _patt.network = savedNetwork == null
        ? 'preserve'
        : (savedNetwork == 'tcp' && !networkSettingsVersion ? 'preserve' : savedNetwork);
  }

  Future<void> _savePatt() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('p_fp', _patt.fp);
    await p.setString('p_cs', _patt.cs);
    await p.setString('p_pcs', _patt.pcs);
    await p.setString('p_vcn', _patt.vcn);
    await p.setString('p_frag', _patt.frag);
    await p.setString('p_fl', _patt.fragLen);
    await p.setString('p_fi', _patt.fragInt);
    await p.setBool('p_noise', _patt.noise);
    await p.setString('p_nt', _patt.noiseType);
    await p.setString('p_np', _patt.noisePacket);
    await p.setString('p_nd', _patt.noiseDelay);
    await p.setBool('p_mux', _patt.mux);
    await p.setString('p_mc', _patt.muxConc);
    await p.setBool('p_lan', _patt.bypassLan);
    await p.setString('p_log', _patt.logLevel);
    await p.setString('p_dns', _patt.dnsMode);
    await p.setString('p_dnsc', _patt.customDns);
    await p.setBool('p_real', _patt.reality);
    await p.setString('p_pbk', _patt.pbk);
    await p.setString('p_sid', _patt.sid);
    await p.setString('p_spx', _patt.spx);
    await p.setString('p_flow', _patt.flow);
    await p.setString('p_alpn', _patt.alpn);
    await p.setString('p_sni', _patt.sni);
    await p.setString('p_path', _patt.path);
    await p.setString('p_host', _patt.host);
    await p.setString('p_ht', _patt.headerType);
    await p.setString('p_net', _patt.network);
    await p.setBool('p_net_v2', true);
  }

  Future<void> _saveWarp() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('warp_on', _warpOn);
      final value = _warpJson ?? '';
      if (value.isEmpty) {
        await secureStorage.delete(key: 'warp_json');
      } else {
        await secureStorage.write(key: 'warp_json', value: value);
      }
      // Remove any legacy plaintext copy only after secure storage succeeds.
      await p.remove('warp_json');
    } catch (_) {
      _snack('Could not securely save WARP settings.', err: true);
    }
  }

  Future<bool> _queueSecureWrite({
    required String key,
    required String value,
    String? legacyPreferenceKey,
    required String errorMessage,
  }) {
    final result = Completer<bool>();
    _storageWriteQueue = _storageWriteQueue.then((_) async {
      try {
        await secureStorage.write(key: key, value: value);
        if (legacyPreferenceKey != null) {
          final preferences = await SharedPreferences.getInstance();
          await preferences.remove(legacyPreferenceKey);
        }
        result.complete(true);
      } catch (_) {
        if (mounted) _snack(errorMessage, err: true);
        result.complete(false);
      }
    });
    return result.future;
  }

  Future<bool> _saveDirectUris() {
    // Capture the exact state at enqueue time; later edits cannot change this write.
    final snapshot = List<String>.from(_directUris);
    return _queueSecureWrite(
      key: 'direct_server_uris',
      value: jsonEncode(snapshot),
      errorMessage: 'Could not securely save direct server links.',
    );
  }

  Future<bool> _saveSubscriptions() {
    final snapshot = List<String>.from(_subs);
    return _queueSecureWrite(
      key: 'subscriptions_json',
      value: jsonEncode(snapshot),
      legacyPreferenceKey: 'subs',
      errorMessage: 'Could not securely save subscription URLs.',
    );
  }

  Future<void> _saveSelection(String uri) async {
    try {
      await secureStorage.write(key: 'selected_node_uri', value: uri);
      final p = await SharedPreferences.getInstance();
      await p.remove('sel');
    } catch (_) {
      _snack('Could not securely save the selected server.', err: true);
    }
  }

  String _fmt(int bps) {
    if (bps < 1024) return '$bps B/s';
    if (bps < 1048576) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / 1048576).toStringAsFixed(1)} MB/s';
  }

  int _ms(ServerNode n) => int.tryParse(n.pingText.replaceAll(' ms', '').trim()) ?? 999999;

  Map<String, dynamic>? _vmess(String uri) {
    if (directShareUriError(uri) != null) return null;
    try {
      final b = uri.substring('vmess://'.length).split('#').first.trim();
      List<int> bytes;
      try {
        bytes = base64.decode(base64.normalize(b));
      } catch (_) {
        bytes = base64Url.decode(base64Url.normalize(b));
      }
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
    } catch (_) {
      return null;
    }
  }

  MapEntry<String, int>? _hostPort(String uri) {
    try {
      if (uri.startsWith('vmess://')) {
        final j = _vmess(uri);
        if (j == null) return null;
        return MapEntry(j['add'].toString(), int.tryParse(j['port'].toString()) ?? 0);
      }
      final u = Uri.parse(uri);
      return MapEntry(u.host, u.port);
    } catch (_) {
      return null;
    }
  }

  String _name(String uri) {
    try {
      if (uri.startsWith('vmess://')) {
        final j = _vmess(uri);
        if (j != null) {
          final ps = (j['ps'] ?? '').toString();
          return ps.isNotEmpty ? ps : '${j['add']}:${j['port']}';
        }
      }
      final u = Uri.parse(uri);
      if (u.fragment.isNotEmpty) return Uri.decodeComponent(u.fragment);
      return '${u.host}:${u.port}';
    } catch (_) {
      return 'Node';
    }
  }

  String _injectQuery(String uri) => applyPattQuery(uri, _patt);

  String _injectCore(String config) {
    final json = jsonDecode(config) as Map<String, dynamic>;
    final outs = json['outbounds'] as List?;
    if (outs == null || outs.isEmpty) {
      throw const FormatException('Core configuration has no outbounds.');
    }
    final main = outs[0] as Map<String, dynamic>;
    json['log'] = {'loglevel': _patt.logLevel};
    if (_patt.dnsMode == 'doh') {
      json['dns'] = {'servers': ['https+local://1.1.1.1/dns-query', 'https+local://8.8.8.8/dns-query']};
    } else if (_patt.dnsMode == 'custom' && _patt.customDns.isNotEmpty) {
      json['dns'] = {'servers': _patt.customDns.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()};
    }
    if (_warpOn && _warpJson != null && _warpJson!.isNotEmpty) {
      final w = jsonDecode(_warpJson!) as Map<String, dynamic>;
      withWarpOnlyOutbound(json, w, bypassLan: _patt.bypassLan);
      return jsonEncode(json);
    }
    if (_patt.mux) main['mux'] = {'enabled': true, 'concurrency': int.tryParse(_patt.muxConc) ?? 8};
    if (_patt.frag != 'none' || _patt.noise) {
      final fs = <String, dynamic>{};
      if (_patt.frag != 'none') {
        fs['fragment'] = {'packets': _patt.frag.startsWith('tlshello') ? 'tlshello' : _patt.frag, 'length': _patt.fragLen, 'interval': _patt.fragInt};
      }
      if (_patt.noise) fs['noises'] = [{'type': _patt.noiseType, 'packet': _patt.noisePacket, 'delay': _patt.noiseDelay}];
      final stream = (main['streamSettings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final sock = (stream['sockopt'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      sock['dialerProxy'] = 'zeus-frag';
      stream['sockopt'] = sock;
      main['streamSettings'] = stream;
      outs.add({'tag': 'zeus-frag', 'protocol': 'freedom', 'settings': fs});
    }
    json['outbounds'] = outs;
    if (_patt.bypassLan) withLanBypass(json);
    return jsonEncode(json);

  }
  Future<void> _syncAll() async {
    if (!mounted) return;
    final syncEpoch = ++_syncEpoch;

    if (_subs.isEmpty && _directUris.isEmpty) {
      setState(() {
        _nodes = [];
        _selUri = null;
        _loading = false;
      });
      _refreshNodes?.call();
      return;
    }

    // Work from a stable snapshot while the user can still edit subscriptions.
    final subscriptions = List<String>.from(_subs);
    final directUris = List<String>.from(_directUris);
    final previousSelection = _selUri;
    setState(() {
      _loading = true;
    });

    final foundNodes = <ServerNode>[];
    final seenNodeUris = <String>{};
    for (var i = 0; i < directUris.length; i++) {
      final raw = directUris[i];
      if (directShareUriError(raw) != null || !seenNodeUris.add(raw)) continue;
      foundNodes.add(ServerNode(subTag: 'DIRECT', rawUri: raw.startsWith('vmess://') ? raw : _injectQuery(raw), baseUri: raw, displayName: '[DIRECT] ${_name(raw)}'));
    }
    final failedSubscriptionUrls = <String>{};

    for (var i = 0; i < subscriptions.length; i++) {
      final tag = 'SUB-${i + 1}';
      try {
        final subscriptionUri = Uri.tryParse(subscriptions[i]);
        if (subscriptionUri == null ||
            subscriptionUri.scheme != 'https' ||
            subscriptionUri.host.isEmpty) {
          failedSubscriptionUrls.add(subscriptions[i]);
          continue;
        }
        final response = await _dio.get<ResponseBody>(
          subscriptionUri.toString(),
          options: Options(
            headers: {'User-Agent': 'v2rayNG/1.8.5'},
            responseType: ResponseType.stream,
            // Do not let the HTTP adapter follow a redirect to a cleartext URL.
            // Subscription credentials may be embedded in the URL itself.
            followRedirects: false,
          ),
        );
        final responseBody = response.data;
        if (responseBody == null) {
          failedSubscriptionUrls.add(subscriptions[i]);
          continue;
        }
        // Redirects are intentionally not followed. This rejects HTTPS-to-HTTP
        // downgrade redirects before the client requests the destination.
        final statusCode = response.statusCode;
        if (statusCode == null || statusCode < 200 || statusCode >= 300) {
          await responseBody.stream.drain<void>();
          failedSubscriptionUrls.add(subscriptions[i]);
          continue;
        }
        if (response.realUri.scheme != 'https') {
          await responseBody.stream.drain<void>();
          failedSubscriptionUrls.add(subscriptions[i]);
          continue;
        }

        // Bound memory use even when a subscription endpoint returns a huge body.
        const maxSubscriptionBytes = 10 * 1024 * 1024;
        final bodyBytes = BytesBuilder(copy: false);
        var receivedBytes = 0;
        await for (final chunk in responseBody.stream) {
          receivedBytes += chunk.length;
          if (receivedBytes > maxSubscriptionBytes) {
            throw const FormatException('Subscription response exceeds 10 MiB.');
          }
          bodyBytes.add(chunk);
        }
        var body = utf8.decode(bodyBytes.takeBytes()).trim();
        final compact = body.replaceAll(RegExp(r'\s'), '');
        try {
          body = utf8.decode(base64.decode(base64.normalize(compact)));
        } catch (_) {
          try {
            body = utf8.decode(base64Url.decode(base64Url.normalize(compact)));
          } catch (_) {
            // A plain-text subscription is valid too; parse it below.
          }
        }

        for (final raw in body.split('\n').map((line) => line.trim())) {
          if (raw.startsWith('vless://') ||
              raw.startsWith('trojan://') ||
              raw.startsWith('vmess://')) {
            if (directShareUriError(raw) != null) continue;
            final link = raw.startsWith('vmess://') ? raw : _injectQuery(raw);
            if (!seenNodeUris.add(raw)) continue;
            foundNodes.add(ServerNode(
              subTag: tag,
              rawUri: link,
              baseUri: raw,
              subscriptionUrl: subscriptions[i],
              displayName: '[$tag] ${_name(raw)}',
            ));
          }
        }
      } catch (_) {
        failedSubscriptionUrls.add(subscriptions[i]);
      }
    }

    if (!mounted || syncEpoch != _syncEpoch) return;
    final failedSubscriptions = failedSubscriptionUrls.length;

    // A total outage must not erase working cached profiles from the feeds
    // that failed. Keep current direct links and only retain cache entries
    // whose source URL is still configured; removed feeds are not resurrected.
    if (subscriptions.isNotEmpty && failedSubscriptions == subscriptions.length) {
      final mergedNodes = mergeNodesForFailedSubscriptions(
        freshNodes: foundNodes,
        cachedNodes: _nodes,
        failedSubscriptionUrls: failedSubscriptionUrls,
      );
      setState(() {
        _nodes = mergedNodes;
        if ((_connected || _connecting) && previousSelection != null) {
          _selUri = previousSelection;
        } else if (previousSelection != null &&
            _nodes.any((node) => node.baseUri == previousSelection)) {
          _selUri = previousSelection;
        } else if (_nodes.isNotEmpty) {
          _selUri = _nodes.first.baseUri;
        } else {
          _selUri = null;
        }
        _loading = false;
      });
      _refreshNodes?.call();
      if (mergedNodes.isNotEmpty) _pingAll();
      _snack(
        mergedNodes.length > foundNodes.length
            ? 'All feeds are unavailable. Keeping cached nodes from configured feeds.'
            : 'Unable to load any subscription feeds.',
        err: true,
      );
      return;
    }

    // Even when some feeds succeed, retain cached profiles from the
    // specific feeds that failed. Healthy feeds are fully refreshed and
    // removed feeds are never reintroduced from cache.
    final mergedNodes = mergeNodesForFailedSubscriptions(
      freshNodes: foundNodes,
      cachedNodes: _nodes,
      failedSubscriptionUrls: failedSubscriptionUrls,
    );
    setState(() {
      _nodes = mergedNodes;
      if ((_connected || _connecting) && previousSelection != null) {
        _selUri = previousSelection;
      } else if (previousSelection != null &&
          _nodes.any((node) => node.baseUri == previousSelection)) {
        _selUri = previousSelection;
      } else if (_nodes.isNotEmpty) {
        _selUri = _nodes.first.baseUri;
      } else {
        _selUri = null;
      }
      _loading = false;
    });
    _refreshNodes?.call();

    if (mergedNodes.isNotEmpty) {
      _pingAll();
    }

    if (failedSubscriptions > 0) {
      _snack(
        'Loaded nodes, but $failedSubscriptions subscription(s) failed.',
        err: true,
      );
    } else if (foundNodes.isEmpty) {
      _snack('No supported nodes found in the subscriptions.', err: true);
    }
  }
  Future<void> _pingAll() async {
    if (!mounted || _nodes.isEmpty) return;
    final c = _delayMode == 1 ? 4 : 20;
    final q = List<ServerNode>.from(_nodes);
    await Future.wait(List.generate(c, (_) async {
      while (mounted && q.isNotEmpty) {
        final n = q.removeAt(0);
        await _pingOne(n);
      }
    }));
  }

  Future<void> _pingOne(ServerNode n) async {
    if (!mounted) return;
    if (_delayMode == 1) {
      try {
        final parser = V2ray.parseFromURL(n.rawUri);
        final ms = await _v2ray.getServerDelay(config: parser.getFullConfiguration());
        if (!mounted) return;
        if (ms <= 0) throw Exception('timeout');
        if (mounted) {
          setState(() {
            n.pingText = '$ms ms';
            n.pingColor = ms < 200 ? green : (ms < 500 ? amber : magenta);
          });
          _refreshNodes?.call();
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            n.pingText = 'TIMEOUT';
            n.pingColor = magenta;
          });
          _refreshNodes?.call();
        }
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
      if (mounted) {
        setState(() {
          final p = sw.elapsedMilliseconds;
          n.pingText = '$p ms';
          n.pingColor = p < 200 ? green : (p < 500 ? amber : magenta);
        });
        _refreshNodes?.call();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          n.pingText = 'TIMEOUT';
          n.pingColor = magenta;
        });
        _refreshNodes?.call();
      }
    }
  }

  /// Measures the selected profile with the embedded Xray core.
  /// Live upload/download rates continue to come from V2ray status callbacks.
  Future<void> _testCoreDelay() async {
    if (!mounted || _testingDelay) return;
    final index = _nodes.indexWhere((node) => node.baseUri == _selUri);
    if (!_connected && index < 0) {
      _snack('Select and sync a server before testing core latency.', err: true);
      return;
    }

    setState(() {
      _testingDelay = true;
      _coreDelay = '...';
    });
    try {
      final milliseconds = _connected
          ? await _v2ray.getConnectedServerDelay()
          : await _v2ray.getServerDelay(
              config: _injectCore(
                V2ray.parseFromURL(_nodes[index].rawUri)
                    .getFullConfiguration(),
              ),
            );
      if (!mounted) return;
      if (milliseconds <= 0) {
        setState(() => _coreDelay = 'TIMEOUT');
      } else {
        setState(() => _coreDelay = '$milliseconds ms');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _coreDelay = 'FAILED');
    } finally {
      if (mounted) setState(() => _testingDelay = false);
    }
  }

  Future<void> _toggle() async {
    if (!_ready) {
      _snack('Core is initializing...', err: true);
      return;
    }
    if (_busy) return;
    if (_connecting) {
      _snack('Already connecting, wait...');
      return;
    }
    _busy = true;
    try {
      if (_connected) {
        await _v2ray.stopV2Ray();
      } else {
        if (_warpOn) {
          final warpError = warpConfigurationError(_warpJson);
          if (warpError != null) {
            _snack(warpError, err: true);
            return;
          }
        }
        final idx = _nodes.indexWhere((n) => n.baseUri == _selUri);
        if (idx < 0) {
          _snack(_loading ? 'Syncing nodes, wait...' : 'First select a node.', err: true);
          return;
        }
        final profileError = _warpOn
            ? null
            : pattConfigurationError(_nodes[idx].rawUri, _patt);
        if (profileError != null) {
          _snack(profileError, err: true);
          return;
        }
        final ok = await _v2ray.requestPermission();
        if (!mounted) return;
        if (!ok) {
          _snack('VPN permission denied.', err: true);
          return;
        }
        final selectedNode = _nodes[idx];
        final parser = V2ray.parseFromURL(selectedNode.rawUri);
        final config = _injectCore(parser.getFullConfiguration());
        _activeRouteLabel = _warpOn
            ? 'Cloudflare WARP tunnel'
            : selectedNode.displayName;
        _activeRouteBaseUri = selectedNode.baseUri;
        _activeRouteUsesWarp = _warpOn;
        await _v2ray.startV2Ray(remark: parser.remark, config: config, proxyOnly: false);
      }
    } catch (_) {
      if (!_connected && !_connecting) {
        _activeRouteLabel = null;
        _activeRouteBaseUri = null;
        _activeRouteUsesWarp = false;
      }
      _snack('Core error, try again.', err: true);
    } finally {
      _busy = false;
    }
  }

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(color: Colors.white)), backgroundColor: err ? magenta : green, behavior: SnackBarBehavior.floating));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncEpoch++;
    _timeCtl.dispose();
    _pulseCtl.dispose();
    _ringCtl.dispose();
    _dio.close(force: true);
    super.dispose();
  }

  Widget _pill(IconData ic, String label, Color c, VoidCallback on) {
    return GestureDetector(onTap: on, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, color: c, size: 14),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
      ]),
    ));
  }

  Widget _dd(String label, List<String> items, String cur, void Function(String) on) {
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.bold)),
      DropdownButtonFormField<String>(
        key: ValueKey('dd_$label'),
        initialValue: items.contains(cur) ? cur : items.first,
        dropdownColor: glass,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(filled: true, fillColor: Colors.white.withValues(alpha: 0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        items: items.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) {
          if (v != null) on(v);
        },
      ),
    ]));
  }

  Widget _tf(String label, String cur, void Function(String) on) {
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: TextFormField(
      key: ValueKey('tf_$label'),
      initialValue: cur,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10), filled: true, fillColor: Colors.white.withValues(alpha: 0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
      onChanged: on,
    ));
  }

  Widget _sw(String label, bool val, void Function(bool) on) {
    return SwitchListTile(key: ValueKey('sw_$label'), contentPadding: EdgeInsets.zero, title: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)), value: val, onChanged: on);
  }

  void _openNodes() {
    String q = '';
    String tag = 'ALL';
    int sort = 0;
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setMs) {
      _refreshNodes = () { if (ctx.mounted) setMs(() {}); };
      var vis = _nodes.where((n) => (tag == 'ALL' || n.subTag == tag) && (q.isEmpty || n.displayName.toLowerCase().contains(q.toLowerCase()))).toList();
      if (sort == 1) vis.sort((a, b) => _ms(a).compareTo(_ms(b)));
      if (sort == 2) vis.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      final tags = <String>['ALL', ..._nodes.map((e) => e.subTag).toSet()];
      return Container(height: MediaQuery.of(ctx).size.height * 0.9, decoration: BoxDecoration(color: glass, borderRadius: const BorderRadius.vertical(top: Radius.circular(22)), border: Border(top: BorderSide(color: cyan.withValues(alpha: 0.6), width: 2))), child: Column(children: [
        const SizedBox(height: 12),
        Container(width: 54, height: 4, decoration: BoxDecoration(color: cyan.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(children: [
          const Icon(Icons.dns, color: cyan, size: 18),
          const SizedBox(width: 8),
          const Text('NODE CENTER', style: TextStyle(color: cyan, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 3)),
          const SizedBox(width: 8),
          Text('${vis.length}/${_nodes.length}', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Wrap(spacing: 8, runSpacing: 8, children: [
          _pill(Icons.refresh, 'SYNC', cyan, _syncAll),
          _pill(Icons.network_ping, 'PING ALL', green, _pingAll),
          _pill(Icons.sort, sort == 0 ? 'SORT: AUTO' : (sort == 1 ? 'SORT: PING' : 'SORT: NAME'), amber, () => setMs(() => sort = (sort + 1) % 3)),
          _pill(Icons.timer_outlined, _delayMode == 0 ? 'DELAY: TCP' : 'DELAY: REAL', magenta, () => setMs(() => _delayMode = _delayMode == 0 ? 1 : 0)),
        ])),
        const SizedBox(height: 10),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(style: const TextStyle(color: Colors.white, fontSize: 13), onChanged: (v) => setMs(() => q = v), decoration: InputDecoration(hintText: 'SEARCH NODE...', hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12), prefixIcon: const Icon(Icons.search, color: cyan, size: 18), filled: true, fillColor: Colors.white.withValues(alpha: 0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))))),
        const SizedBox(height: 10),
        SizedBox(height: 34, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: tags.map((t) {
          final on = tag == t;
          return Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(onTap: () => setMs(() => tag = t), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), decoration: BoxDecoration(color: on ? cyan.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(20), border: Border.all(color: on ? cyan : Colors.white.withValues(alpha: 0.1))), child: Text(t, style: TextStyle(color: on ? cyan : Colors.white.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.bold)))));
        }).toList())),
        Expanded(child: vis.isEmpty ? Center(child: Text('NO NODES', style: TextStyle(color: Colors.white.withValues(alpha: 0.3)))) : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), itemCount: vis.length, itemBuilder: (ctx, i) {
          final n = vis[i];
          final sel = n.baseUri == _selUri;
          return GestureDetector(onTap: () {
            if (_connected || _connecting) {
              _snack('Disconnect the current tunnel before changing its server.', err: true);
              return;
            }
            setState(() => _selUri = n.baseUri);
            _saveSelection(n.baseUri);
            setMs(() {});
            Navigator.pop(ctx);
          }, child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: sel ? cyan.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(12), border: Border.all(color: sel ? cyan : Colors.white.withValues(alpha: 0.06))), child: Row(children: [
            Icon(n.rawUri.startsWith('vless://') ? Icons.bolt_rounded : (n.rawUri.startsWith('trojan://') ? Icons.shield_rounded : Icons.memory_rounded), color: n.rawUri.startsWith('vless://') ? cyan : (n.rawUri.startsWith('trojan://') ? magenta : amber), size: 18),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.displayName, style: TextStyle(color: sel ? Colors.white : Colors.white70, fontSize: 13, fontWeight: sel ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(n.subTag, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 9, fontWeight: FontWeight.bold)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: n.pingColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: n.pingColor.withValues(alpha: 0.5))), child: Text(n.pingText, style: TextStyle(color: n.pingColor, fontSize: 10, fontWeight: FontWeight.bold))),
            if (sel) ...[const SizedBox(width: 8), const Icon(Icons.check_circle, color: green, size: 18)],
          ])));
        })),
      ]));
    })).then((_) {
      _refreshNodes = null;
      if (mounted) setState(() {});
    });
  }

  void _openSubs() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final bottomInset = media.viewInsets.bottom;
        final availableHeight =
            (media.size.height - bottomInset).clamp(0.0, media.size.height).toDouble();

        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SizedBox(
            height: availableHeight * 0.82,
            child: _SubscriptionSheet(
              subscriptions: _subs,
              directUris: _directUris,
              displayName: _name,
              onAddSubscription: (value) {
                if (!mounted) return;
                setState(() => _subs.add(value));
                _saveSubscriptions();
              },
              onAddDirectUri: (value) {
                if (!mounted) return;
                setState(() => _directUris.add(value));
                _saveDirectUris();
              },
              onRemoveSubscription: (index) {
                if (!mounted || index < 0 || index >= _subs.length) return;
                setState(() => _subs.removeAt(index));
                _saveSubscriptions();
              },
              onRemoveDirectUri: (index) {
                if (!mounted || index < 0 || index >= _directUris.length) return;
                setState(() => _directUris.removeAt(index));
                _saveDirectUris();
              },
              onValidationError: (message) => _snack(message, err: true),
              onSave: () async {
                // Earlier add/remove writes are serialized ahead of these final snapshots.
                final subscriptionsSaved = await _saveSubscriptions();
                final directUrisSaved = await _saveDirectUris();
                if (!mounted || !ctx.mounted || !subscriptionsSaved || !directUrisSaved) {
                  return false;
                }
                Navigator.of(ctx).pop();
                await _syncAll();
                return true;
              },
            ),
          ),
        );
      },
    );
  }

  void _openPatt() {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setMs) {
      return Container(height: MediaQuery.of(ctx).size.height * 0.85, decoration: BoxDecoration(color: glass, borderRadius: const BorderRadius.vertical(top: Radius.circular(22)), border: Border(top: BorderSide(color: green.withValues(alpha: 0.6), width: 2))), child: Column(children: [
        const SizedBox(height: 12),
        Container(width: 54, height: 4, decoration: BoxDecoration(color: green.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8))),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('PATT-NG CORE', style: TextStyle(color: green, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 3))),
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
          if (_connected || _connecting)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cyan.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cyan.withValues(alpha: 0.35)),
              ),
              child: const Text(
                'LIVE SESSION: edits here are saved for the next connection. The running tunnel is not reconfigured until you disconnect and reconnect.',
                style: TextStyle(color: cyan, fontSize: 10, height: 1.45),
              ),
            ),
          if (_warpOn)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: amber.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: amber.withValues(alpha: 0.35)),
              ),
              child: const Text(
                'WARP-ONLY MODE: select a valid profile to provide the local core layout, but its VLESS/Trojan/VMess server outbound is replaced by WARP. This is not WARP-plus-proxy chaining. Server transport, REALITY, Vision, fragmentation, noise and MUX overrides are ignored; DNS, log level and optional LAN bypass still apply.',
                style: TextStyle(color: amber, fontSize: 10, height: 1.45),
              ),
            ),
          _sw('WARP (Cloudflare WireGuard)', _warpOn, (v) {
            setMs(() => _warpOn = v);
            _saveWarp();
          }),
          if (_warpJson != null) const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('WARP device: REGISTERED', style: TextStyle(color: green, fontSize: 10, fontWeight: FontWeight.bold))),
          if (_warpOn && _warpJson == null) Padding(padding: const EdgeInsets.only(bottom: 14), child: SizedBox(width: double.infinity, height: 44, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: cyan.withValues(alpha: 0.1), side: const BorderSide(color: cyan)), onPressed: () async {
            _snack('Registering WARP device...');
            final kp = await genWarpKeys();
            final out = await registerWarp(kp);
            if (!mounted) return;
            if (out == null) {
              _snack('WARP registration failed!', err: true);
            } else {
              setState(() => _warpJson = jsonEncode(out));
              _saveWarp();
              _snack('WARP registered!');
            }
            setMs(() {});
          }, child: const Text('REGISTER WARP DEVICE', style: TextStyle(color: cyan, fontWeight: FontWeight.bold, letterSpacing: 1))))),
          _dd('FINGERPRINT', ['chrome', 'firefox', 'safari', 'randomized', 'randomizednoalpn'], _patt.fp, (v) {
            setMs(() => _patt.fp = v);
            _savePatt();
          }),
          _tf('CIPHER SUITES', _patt.cs, (v) {
            _patt.cs = v;
            _savePatt();
          }),
          _tf('CERTIFICATE SHA-256 PIN (PCS)', _patt.pcs, (v) {
            _patt.pcs = v;
            _savePatt();
          }),
          _tf('VERIFY CERTIFICATE NAME (VCN)', _patt.vcn, (v) {
            _patt.vcn = v;
            _savePatt();
          }),
          _dd('FRAGMENT', ['tlshello', 'none'], _patt.frag, (v) {
            setMs(() => _patt.frag = v);
            _savePatt();
          }),
          if (_patt.frag != 'none') ...[
            _tf('FRAG LENGTH', _patt.fragLen, (v) {
              _patt.fragLen = v;
              _savePatt();
            }),
            _tf('FRAG INTERVAL', _patt.fragInt, (v) {
              _patt.fragInt = v;
              _savePatt();
            }),
          ],
          _sw('NOISE', _patt.noise, (v) {
            setMs(() => _patt.noise = v);
            _savePatt();
          }),
          if (_patt.noise) ...[
            _dd('NOISE TYPE', ['rand', 'base64', 'str', 'hex'], _patt.noiseType, (v) {
              setMs(() => _patt.noiseType = v);
              _savePatt();
            }),
            _tf(
              _patt.noiseType == 'rand' ? 'NOISE LENGTH RANGE' : 'NOISE PAYLOAD',
              _patt.noisePacket,
              (v) {
              _patt.noisePacket = v;
              _savePatt();
            }),
            _tf('NOISE DELAY', _patt.noiseDelay, (v) {
              _patt.noiseDelay = v;
              _savePatt();
            }),
          ],
          _sw('MUX', _patt.mux, (v) {
            setMs(() => _patt.mux = v);
            _savePatt();
          }),
          if (_patt.mux) _tf('MUX CONCURRENCY', _patt.muxConc, (v) {
            _patt.muxConc = v;
            _savePatt();
          }),
          _sw('BYPASS LAN', _patt.bypassLan, (v) {
            setMs(() => _patt.bypassLan = v);
            _savePatt();
          }),
          _dd('LOG LEVEL', ['debug', 'info', 'warning', 'error', 'none'], _patt.logLevel, (v) {
            setMs(() => _patt.logLevel = v);
            _savePatt();
          }),
          _dd('DNS', ['auto', 'doh', 'custom'], _patt.dnsMode, (v) {
            setMs(() => _patt.dnsMode = v);
            _savePatt();
          }),
          if (_patt.dnsMode == 'custom') _tf('CUSTOM DNS', _patt.customDns, (v) {
            _patt.customDns = v;
            _savePatt();
          }),
          _sw('FORCE REALITY OVERRIDE', _patt.reality, (v) {
            setMs(() => _patt.reality = v);
            _savePatt();
          }),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'OFF preserves the security mode in the imported profile. ON forces REALITY and requires a compatible VLESS/TCP profile with PBK and SNI.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.42),
                fontSize: 9,
                height: 1.4,
              ),
            ),
          ),
          if (_patt.reality) ...[
            _tf('PBK', _patt.pbk, (v) {
              _patt.pbk = v;
              _savePatt();
            }),
            _tf('SID', _patt.sid, (v) {
              _patt.sid = v;
              _savePatt();
            }),
            _tf('SPX', _patt.spx, (v) {
              _patt.spx = v;
              _savePatt();
            }),
          ],
          _dd('FLOW', ['preserve', 'xtls-rprx-vision', 'none'], _patt.flow, (v) {
            setMs(() => _patt.flow = v);
            _savePatt();
          }),
          _dd('ALPN', ['preserve', 'h2,http/1.1', 'h2', 'http/1.1', 'none'], _patt.alpn, (v) {
            setMs(() => _patt.alpn = v);
            _savePatt();
          }),
          _dd('NETWORK', ['preserve', 'tcp', 'ws', 'grpc', 'http', 'kcp', 'quic', 'httpupgrade', 'splithttp'], _patt.network, (v) {
            setMs(() => _patt.network = v);
            _savePatt();
          }),
          _tf('SNI', _patt.sni, (v) {
            _patt.sni = v;
            _savePatt();
          }),
          _tf('PATH', _patt.path, (v) {
            _patt.path = v;
            _savePatt();
          }),
          _tf('HOST', _patt.host, (v) {
            _patt.host = v;
            _savePatt();
          }),
        ])),
        Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: green.withValues(alpha: 0.1), side: const BorderSide(color: green)), onPressed: () {
          Navigator.pop(ctx);
          _syncAll();
        }, child: const Text('APPLY & SYNC', style: TextStyle(color: green, fontWeight: FontWeight.bold, letterSpacing: 2))))),
      ]));
    }));
  }


  Future<void> _openCoreLogs() async {
    try {
      final initialLogs = await _v2ray.getLogs();
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (sheetContext) {
          var search = '';
          var currentLogs = List<String>.from(initialLogs);
          var busy = false;
          final sheetHeight = MediaQuery.of(sheetContext).size.height * 0.82;

          return StatefulBuilder(builder: (ctx, setSheetState) {
            final filtered = currentLogs
                .map(sanitizeCoreLogLine)
                .where((line) => search.isEmpty ||
                    line.toLowerCase().contains(search.toLowerCase()))
                .toList(growable: false);

            Future<void> refresh() async {
              if (busy) return;
              setSheetState(() => busy = true);
              try {
                final latest = await _v2ray.getLogs();
                if (!ctx.mounted) return;
                setSheetState(() => currentLogs = List<String>.from(latest));
              } catch (_) {
                if (ctx.mounted) _snack('Could not refresh core logs.', err: true);
              } finally {
                if (ctx.mounted) setSheetState(() => busy = false);
              }
            }

            Future<void> clear() async {
              if (busy) return;
              final confirmed = await showDialog<bool>(
                context: ctx,
                builder: (dialogContext) => AlertDialog(
                  backgroundColor: glass,
                  title: const Text('Clear core logs?'),
                  content: const Text(
                    'This clears the diagnostic buffer on this device. It does not change VPN settings.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('CANCEL'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('CLEAR', style: TextStyle(color: magenta)),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !ctx.mounted) return;
              setSheetState(() => busy = true);
              try {
                final cleared = await _v2ray.clearLogs();
                if (!ctx.mounted) return;
                if (cleared) {
                  setSheetState(() => currentLogs = []);
                } else {
                  _snack('The core log buffer could not be cleared.', err: true);
                }
              } catch (_) {
                if (ctx.mounted) _snack('Could not clear core logs.', err: true);
              } finally {
                if (ctx.mounted) setSheetState(() => busy = false);
              }
            }

            return Container(
              height: sheetHeight,
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              decoration: BoxDecoration(
                color: glass,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                border: Border(top: BorderSide(color: magenta.withValues(alpha: 0.65), width: 2)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 52,
                    height: 4,
                    decoration: BoxDecoration(
                      color: magenta.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.terminal_rounded, color: magenta),
                        const SizedBox(width: 9),
                        const Expanded(
                          child: Text(
                            'CORE LOGS',
                            style: TextStyle(
                              color: magenta,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        Text(
                          '${filtered.length}/${currentLogs.length}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 9),
                        ),
                        IconButton(
                          tooltip: 'Refresh logs',
                          onPressed: busy ? null : refresh,
                          icon: Icon(Icons.refresh_rounded, color: busy ? Colors.grey : cyan),
                        ),
                        IconButton(
                          tooltip: 'Clear logs',
                          onPressed: busy || currentLogs.isEmpty ? null : clear,
                          icon: const Icon(Icons.delete_sweep_rounded, color: magenta),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      onChanged: (value) => setSheetState(() => search = value.trim()),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'FILTER LOG MESSAGES...',
                        prefixIcon: const Icon(Icons.search_rounded, color: cyan, size: 18),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.04),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 9, 16, 8),
                    child: Text(
                      'Sensitive-looking share URIs and common key fields are redacted. Logs may still contain server addresses; avoid sharing screenshots.',
                      style: TextStyle(color: amber.withValues(alpha: 0.8), fontSize: 9, height: 1.35),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              currentLogs.isEmpty ? 'NO CORE LOGS YET' : 'NO MATCHING LOGS',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: SelectableText(
                                filtered[index],
                                style: TextStyle(
                                  color: filtered[index].contains('[redacted]')
                                      ? amber
                                      : const Color(0xFFB8C6D8),
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            );
          });
        },
      );
    } catch (_) {
      if (mounted) _snack('Could not load core logs on this device.', err: true);
    }
  }

  Widget _screenHeader(String eyebrow, String title, Color accent, {String? meta}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 7),
      child: Row(children: [
        Container(width: 3, height: 34, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4), boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 10)])),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(eyebrow.toUpperCase(), style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 3),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
        ])),
        if (meta != null) Text(meta, style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 9)),
      ]),
    );
  }

  Widget _neonPanel(Widget child, {Color accent = cyan, VoidCallback? onTap}) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xE6071009),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.055), blurRadius: 18)],
      ),
      child: child,
    );
    return onTap == null ? card : Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(9), child: card));
  }

  Widget _quickAction(IconData icon, String title, String subtitle, Color accent, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: _neonPanel(Row(children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: accent.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(12), border: Border.all(color: accent.withValues(alpha: 0.3))), child: Icon(icon, color: accent)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 10)),
      ])),
      Icon(Icons.chevron_right_rounded, color: accent),
    ]), accent: accent, onTap: onTap),
  );

  Widget _dashboard(String name, String ping, Color pingColor) {
    final accent = _connected ? green : (_connecting ? amber : cyan);
    return SingleChildScrollView(
      key: const ValueKey('dash'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _neonPanel(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.terminal_rounded, color: green, size: 15),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'LIVE SYSTEM MONITOR',
                  style: TextStyle(
                    color: green,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              Text(
                'READ-ONLY',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 8,
                  letterSpacing: 1,
                ),
              ),
            ]),
            Divider(height: 18, color: green.withValues(alpha: 0.18)),
            Text(
              'zeus@android:~\$ tunnel --status',
              style: TextStyle(
                color: cyan.withValues(alpha: 0.85),
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _terminalLine('VPN CORE', _ready ? 'INITIALIZED' : 'BOOTING', _ready ? green : amber),
            _terminalLine(
              'TUNNEL',
              _connected ? 'ESTABLISHED' : (_connecting ? 'NEGOTIATING' : 'IDLE'),
              _connected ? green : (_connecting ? amber : magenta),
            ),
            _terminalLine('NODE POOL', '${_nodes.length} REGISTERED', cyan),
            _terminalLine('FEED SOURCES', '${_subs.length} CONFIGURED', green),
          ]),
          accent: green,
        ),
        const SizedBox(height: 10),
        _neonPanel(Column(children: [
          Row(children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: accent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.8), blurRadius: 8)])),
            const SizedBox(width: 8),
            Expanded(child: Text(_connected ? 'SECURE TUNNEL ACTIVE' : (_connecting ? 'ESTABLISHING TUNNEL' : 'SYSTEM STANDBY'), style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.4))),
            Text(_ready ? 'CORE READY' : 'BOOTING', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8)),
          ]),
          const SizedBox(height: 20),
          GestureDetector(onTap: _toggle, child: ScaleTransition(
            scale: _connected ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
            child: SizedBox(width: 198, height: 198, child: Stack(alignment: Alignment.center, children: [
              RotationTransition(turns: _ringCtl, child: Container(width: 190, height: 190, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: accent.withValues(alpha: 0.35)), gradient: SweepGradient(colors: [accent.withValues(alpha: 0.0), accent, magenta, accent.withValues(alpha: 0.0)])))),
              Container(width: 166, height: 166, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF050811), border: Border.all(color: accent, width: 1.6), boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.2), blurRadius: 26, spreadRadius: 3)]), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_connected ? Icons.shield_rounded : (_connecting ? Icons.hourglass_top_rounded : Icons.power_settings_new_rounded), color: accent, size: 42),
                const SizedBox(height: 9),
                Text(_connected ? 'CONNECTED' : (_connecting ? 'CONNECTING' : 'INITIATE'), style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.8)),
                const SizedBox(height: 5),
                Text(_connected ? _dur : 'SECURE LINK', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 9)),
              ])),
            ])),
          )),
          const SizedBox(height: 14),
          Text('TAP THE CORE TO CONTROL THE TUNNEL', style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 9, letterSpacing: 1.2)),
        ]), accent: accent),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(child: _neonPanel(_stat('UPLOAD', _up, Icons.north_east_rounded, magenta), accent: magenta)),
          const SizedBox(width: 8),
          Expanded(child: _neonPanel(_stat('DOWNLOAD', _down, Icons.south_west_rounded, cyan), accent: cyan)),
          const SizedBox(width: 8),
          Expanded(child: _neonPanel(_stat('CORE RTT', _testingDelay ? '...' : (_coreDelay.isEmpty ? 'TEST' : _coreDelay), Icons.network_ping_rounded, green), accent: green, onTap: _testingDelay ? null : _testCoreDelay)),
        ]),
        const SizedBox(height: 20),
        _screenHeader(
          _connected || _connecting ? 'RUNNING TUNNEL' : 'NEXT CONNECTION',
          (_connected || _connecting)
              ? (_activeRouteUsesWarp ? 'Cloudflare WARP' : 'Connected server')
              : (_warpOn ? 'Cloudflare WARP' : 'Selected server'),
          ((_connected || _connecting) ? _activeRouteUsesWarp : _warpOn)
              ? green
              : cyan,
          meta: (_connected || _connecting)
              ? 'LIVE SESSION'
              : (_warpOn ? 'WARP-ONLY EGRESS' : '${_nodes.length} NODES'),
        ),
        _neonPanel(Row(children: [
          Icon(
            ((_connected || _connecting) ? _activeRouteUsesWarp : _warpOn)
                ? Icons.cloud_done_rounded
                : Icons.dns_rounded,
            color: ((_connected || _connecting) ? _activeRouteUsesWarp : _warpOn)
                ? green
                : cyan,
            size: 25,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              (_connected || _connecting)
                  ? (_activeRouteLabel ?? 'Active tunnel')
                  : (_warpOn ? 'Cloudflare WARP tunnel' : name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              (_connected || _connecting)
                  ? (_activeRouteUsesWarp
                      ? 'WARP is carrying the current session'
                      : 'Current VPN session — disconnect to change server')
                  : (_warpOn
                      ? 'WARP will replace the selected server outbound'
                      : (_selUri == null
                          ? 'No server selected — add a feed'
                          : 'Tap to open node control center')),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 10,
              ),
            ),
          ])),
          if (!((_connected || _connecting) ? _activeRouteUsesWarp : _warpOn) && ping != '--')
            Text(ping, style: TextStyle(color: pingColor, fontWeight: FontWeight.w900, fontSize: 10)),
        ]), accent: ((_connected || _connecting) ? _activeRouteUsesWarp : _warpOn) ? green : cyan, onTap: () => _setActiveTab(1)),
        const SizedBox(height: 20),
        _screenHeader('QUICK ACCESS', 'Terminal operations', magenta),
        _quickAction(Icons.hub_rounded, 'Node control center', 'Search, latency and server selection', cyan, () => _setActiveTab(1)),
        _quickAction(Icons.rss_feed_rounded, 'Subscription manager', '${_subs.length} secure feed(s) configured', magenta, () => _setActiveTab(2)),
        _quickAction(Icons.memory_rounded, 'PATT-NG / WARP lab', 'Fingerprint, DNS and tunnel parameters', green, () => _setActiveTab(3)),
        Wrap(spacing: 7, runSpacing: 7, children: [
          _pill(Icons.fingerprint_rounded, 'FP: ${_patt.fp.toUpperCase()}', magenta, _openPatt),
          _pill(Icons.alt_route_rounded, 'NET: ${_patt.network.toUpperCase()}', cyan, _openPatt),
          _pill(
            Icons.cloud_outlined,
            'WARP: ${(_connected || _connecting) ? (_activeRouteUsesWarp ? 'ACTIVE' : 'OFF') : (_warpOn ? 'NEXT ON' : 'OFF')}',
            green,
            _openPatt,
          ),
        ]),
      ]),
    );
  }

  Widget _networkScreen() {
    return SingleChildScrollView(
      key: const ValueKey('nodes'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _screenHeader('NETWORK INTELLIGENCE', 'Node control center', cyan, meta: '${_nodes.length} FOUND'),
        _quickAction(Icons.manage_search_rounded, 'Open full node center', 'Search, filter and sort imported nodes', magenta, _openNodes),
        _quickAction(Icons.sync_rounded, 'Sync nodes', _loading ? 'Sync in progress' : 'Refresh secure feeds', cyan, _loading ? () {} : _syncAll),
        _quickAction(Icons.network_ping_rounded, 'Probe latency', 'Check node response', green, _pingAll),
        _neonPanel(Row(children: [
          const Icon(Icons.timer_outlined, color: magenta),
          const SizedBox(width: 9),
          Expanded(child: Text(_delayMode == 0 ? 'TCP handshake latency mode' : 'Core-based latency mode', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10))),
          TextButton(onPressed: () => setState(() => _delayMode = _delayMode == 0 ? 1 : 0), child: Text(_delayMode == 0 ? 'TCP' : 'REAL', style: const TextStyle(color: magenta))),
        ]), accent: magenta),
        const SizedBox(height: 14),
        if (_nodes.isEmpty)
          _neonPanel(Column(children: [
            const Icon(Icons.radar_rounded, color: amber, size: 38),
            const SizedBox(height: 10),
            const Text('NO NODES DETECTED', style: TextStyle(color: amber, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Text(_subs.isEmpty ? 'Add an HTTPS subscription to populate this list.' : 'Sync subscriptions and verify the feed URLs.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: () => _setActiveTab(2), child: const Text('MANAGE FEEDS')),
          ]), accent: amber)
        else
          ..._nodes.map((node) {
            final selected = node.baseUri == _selUri;
            final tint = selected ? green : cyan;
            return Padding(padding: const EdgeInsets.only(bottom: 9), child: _neonPanel(Row(children: [
              Icon(selected ? Icons.check_circle_rounded : Icons.dns_rounded, color: tint, size: 23),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(node.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? green : Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
                const SizedBox(height: 4),
                Text('${node.subTag} • ${_hostPort(node.baseUri)?.key ?? 'unknown host'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 9)),
              ])),
              const SizedBox(width: 7),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(node.pingText, style: TextStyle(color: node.pingColor, fontSize: 10, fontWeight: FontWeight.w900)),
                Text(selected ? 'SELECTED' : 'SELECT', style: TextStyle(color: tint, fontSize: 8)),
              ]),
            ]), accent: tint, onTap: () {
              if (_connected || _connecting) {
                _snack('Disconnect the current tunnel before changing its server.', err: true);
                return;
              }
              setState(() => _selUri = node.baseUri);
              _saveSelection(node.baseUri);
              _snack('Selected ${node.displayName}');
            }));
          }),
      ]),
    );
  }

  Widget _feedsScreen() {
    return SingleChildScrollView(
      key: const ValueKey('feeds'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _screenHeader('FEED CONTROL', 'Subscriptions', magenta, meta: '${_subs.length} FEEDS'),
        _neonPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('SECURE IMPORT PIPELINE', style: TextStyle(color: magenta, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
          const SizedBox(height: 8),
          Text('Feeds must use HTTPS. Subscription links may contain access credentials, so treat them like passwords.', style: TextStyle(color: Colors.white.withValues(alpha: 0.58), fontSize: 11, height: 1.5)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ElevatedButton.icon(onPressed: _openSubs, icon: const Icon(Icons.add_link_rounded), label: const Text('MANAGE FEEDS'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: _loading ? null : _syncAll, icon: const Icon(Icons.sync_rounded), label: const Text('SYNC NOW'), style: OutlinedButton.styleFrom(foregroundColor: cyan, side: BorderSide(color: cyan.withValues(alpha: 0.5))))),
          ]),
        ]), accent: magenta),
        const SizedBox(height: 18),
        _screenHeader('CONFIGURED SOURCES', 'Feed inventory', cyan),
        if (_subs.isEmpty)
          _neonPanel(Column(children: [
            const Icon(Icons.rss_feed_rounded, color: amber, size: 34),
            const SizedBox(height: 9),
            const Text('NO FEEDS CONFIGURED', style: TextStyle(color: amber, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Add a trusted subscription URL to import server profiles.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9DA6B8), fontSize: 11)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _openSubs, child: const Text('ADD FIRST FEED')),
          ]), accent: amber)
        else
          ..._subs.asMap().entries.map((entry) => Padding(padding: const EdgeInsets.only(bottom: 9), child: _neonPanel(Row(children: [
            const Icon(Icons.rss_feed_rounded, color: magenta, size: 22),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('FEED ${entry.key + 1}', style: const TextStyle(color: cyan, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              const SizedBox(height: 5),
              Text(subscriptionDisplayLabel(entry.value), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 10)),
            ])),
            Icon(Icons.lock_outline_rounded, color: green.withValues(alpha: 0.8), size: 17),
          ]), accent: cyan))),
        const SizedBox(height: 10),
        _neonPanel(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.security_rounded, color: amber, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text('Only import feeds you trust. Avoid exposing subscription URLs in screenshots or logs.', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 10, height: 1.5))),
        ]), accent: amber),
      ]),
    );
  }

  Widget _toolsScreen() {
    return SingleChildScrollView(
      key: const ValueKey('tools'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _screenHeader('ENGINE ROOM', 'PATT-NG & WARP', green, meta: 'ADVANCED'),
        _neonPanel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.memory_rounded, color: green, size: 28),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PATT-NG CORE SETTINGS', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
              SizedBox(height: 5),
              Text('Fingerprint, transport, DNS and packet options', style: TextStyle(color: Color(0xFF9DA6B8), fontSize: 10)),
            ])),
          ]),
          const SizedBox(height: 13),
          Wrap(spacing: 7, runSpacing: 7, children: [
            _chip('FP', _patt.fp.toUpperCase(), magenta),
            _chip('NET', _patt.network.toUpperCase(), cyan),
            _chip('FRAG', _patt.frag.toUpperCase(), amber),
            _chip('DNS', _patt.dnsMode.toUpperCase(), green),
          ]),
          const SizedBox(height: 13),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _openPatt, icon: const Icon(Icons.settings_ethernet_rounded), label: const Text('OPEN ADVANCED LAB'))),
        ]), accent: green),
        const SizedBox(height: 10),
        _neonPanel(Row(children: [
          const Icon(Icons.cloud_sync_rounded, color: cyan, size: 27),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('CLOUDFLARE WARP', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
              (_connected || _connecting)
                  ? (_activeRouteUsesWarp
                      ? 'WARP is carrying the live session.'
                      : 'WARP is off in the live session; next connection: ${_warpOn ? 'ON' : 'OFF'}.')
                  : (_warpOn
                      ? 'WARP-only egress is configured for the next connection.'
                      : (_warpJson != null
                          ? 'WARP registration is ready; enabling it switches to WARP-only mode.'
                          : 'No WARP registration detected')),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 10),
            ),
          ])),
          Text(
            (_connected || _connecting)
                ? (_activeRouteUsesWarp ? 'ACTIVE' : 'INACTIVE')
                : (_warpOn ? 'NEXT: ON' : 'OFF'),
            style: TextStyle(
              color: ((_connected || _connecting) ? _activeRouteUsesWarp : _warpOn)
                  ? green
                  : amber,
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ]), accent: cyan),
        const SizedBox(height: 10),
        _quickAction(Icons.tune_rounded, 'Edit engine parameters', 'Open the full PATT-NG configuration', green, _openPatt),
        _quickAction(Icons.dns_rounded, 'Server inventory', 'Review nodes and latency', cyan, () => _setActiveTab(1)),
        _screenHeader('DEVICE STATUS', 'Diagnostics', amber),
        _quickAction(Icons.terminal_rounded, 'Core log console', 'Search, refresh and clear recent Xray diagnostics', magenta, _openCoreLogs),
        _neonPanel(Column(children: [
          _diagnosticRow('VPN CORE', _ready ? 'INITIALIZED' : 'STARTING / ERROR', _ready ? green : amber),
          const Divider(color: Color(0x22FFFFFF), height: 22),
          _diagnosticRow('SERVER INVENTORY', '${_nodes.length} NODE(S)', cyan),
          const Divider(color: Color(0x22FFFFFF), height: 22),
          _diagnosticRow('SUBSCRIPTION FEEDS', '${_subs.length} CONFIGURED', magenta),
          const Divider(color: Color(0x22FFFFFF), height: 22),
          _diagnosticRow('TUNNEL STATE', _connected ? 'CONNECTED' : (_connecting ? 'CONNECTING' : 'DISCONNECTED'), _connected ? green : (_connecting ? amber : cyan)),
        ]), accent: amber),
        const SizedBox(height: 14),
        Text('ZEUS VPN • CYBERPUNK INTERFACE • VERIFICATION REQUIRED', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 8, letterSpacing: 1)),
      ]),
    );
  }

  Widget _terminalLine(String label, String value, Color tint) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
          child: Text(
            '[$label]',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
        ),
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: tint,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ]),
    );
  }

  Widget _diagnosticRow(String label, String value, Color accent) => Row(children: [
    Expanded(child: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8))),
    const SizedBox(width: 10),
    Flexible(child: Text(value, textAlign: TextAlign.end, style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w900))),
  ]);

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _activeTab == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _setActiveTab(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: selected ? cyan.withValues(alpha: 0.11) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? cyan.withValues(alpha: 0.42) : Colors.transparent,
                ),
                boxShadow: selected
                    ? [BoxShadow(color: cyan.withValues(alpha: 0.08), blurRadius: 14)]
                    : const [],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 19, color: selected ? cyan : const Color(0xFF657084)),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? cyan : const Color(0xFF657084),
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: selected ? 13 : 3,
                    height: 2,
                    decoration: BoxDecoration(
                      color: selected ? cyan : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: selected
                          ? [BoxShadow(color: cyan.withValues(alpha: 0.8), blurRadius: 6)]
                          : const [],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String selName = 'TAP TO SELECT';
    String selPing = '--';
    Color selPingC = Colors.grey;
    if (_connected || _connecting) {
      selName = _activeRouteLabel ?? 'ACTIVE TUNNEL';
      final activeNode = _nodes.where((node) => node.baseUri == _activeRouteBaseUri);
      if (activeNode.isNotEmpty) {
        selPing = activeNode.first.pingText;
        selPingC = activeNode.first.pingColor;
      }
    } else if (_loading) {
      selName = 'SYNCING...';
    } else if (_selUri != null && _nodes.isNotEmpty) {
      final selectedNode = _nodes.where((node) => node.baseUri == _selUri);
      if (selectedNode.isNotEmpty) {
        selName = selectedNode.first.displayName;
        selPing = selectedNode.first.pingText;
        selPingC = selectedNode.first.pingColor;
      }
    }
    return Scaffold(
      backgroundColor: background,
      body: Stack(children: [
        Positioned.fill(child: AnimatedBuilder(animation: _timeCtl, builder: (ctx, _) => CustomPaint(painter: _CyberP(_timeCtl.value)))),
        Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(animation: _timeCtl, builder: (ctx, _) => CustomPaint(painter: _ScanP(_timeCtl.value))))),
        SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 9), child: Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: cyan.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(13), border: Border.all(color: cyan.withValues(alpha: 0.5)), boxShadow: [BoxShadow(color: cyan.withValues(alpha: 0.1), blurRadius: 18)]), child: const Icon(Icons.bolt_rounded, color: cyan, size: 26)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ZEUS VPN', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 3.2, shadows: [Shadow(color: cyan, blurRadius: 12)])),
              const SizedBox(height: 3),
              Text('SECURE SHELL  //  CORE MONITOR', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8, letterSpacing: 1.3)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7), decoration: BoxDecoration(color: (_ready ? green : amber).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(9), border: Border.all(color: (_ready ? green : amber).withValues(alpha: 0.35))), child: Row(children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: _ready ? green : amber, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(_ready ? 'READY' : 'BOOTING', style: TextStyle(color: _ready ? green : amber, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.7)),
            ])),
          ])),
          Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 20), color: cyan.withValues(alpha: 0.16)),
          Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 240), child: switch (_activeTab) {
            1 => _networkScreen(),
            2 => _feedsScreen(),
            3 => _toolsScreen(),
            _ => _dashboard(selName, selPing, selPingC),
          })),
        ])),
      ]),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xF2061009),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cyan.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: cyan.withValues(alpha: 0.07),
                blurRadius: 24,
                offset: const Offset(0, -5),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _navItem(0, Icons.grid_view_rounded, 'HOME'),
              _navItem(1, Icons.hub_rounded, 'NODES'),
              _navItem(2, Icons.rss_feed_rounded, 'FEEDS'),
              _navItem(3, Icons.memory_rounded, 'LAB'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String t, String v, IconData i, Color c) => Column(children: [
    Icon(i, color: c, size: 16),
    const SizedBox(height: 4),
    Text(v, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold)),
  ]);

  Widget _chip(String t, String v, Color c) => Column(children: [
    Text(v, style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.bold)),
    Text(t, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 8)),
  ]);
}

class _CyberP extends CustomPainter {
  final double t;
  _CyberP(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    // Low-contrast terminal grid.
    final grid = Paint()
      ..color = cyan.withValues(alpha: 0.025)
      ..strokeWidth = 0.6;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Decorative binary rain; it does not represent network traffic or logs.
    final columns = (size.width / 32).ceil();
    for (var column = 0; column < columns; column++) {
      final random = Random(column * 97 + 11);
      final bits = List.generate(12, (_) => random.nextBool() ? '1' : '0')
          .join('\n');
      final alpha = 0.025 + 0.035 * (0.5 + 0.5 * sin(t * 2 * pi + column));
      final painter = TextPainter(
        text: TextSpan(
          text: bits,
          style: TextStyle(
            color: green.withValues(alpha: alpha),
            fontSize: 9,
            height: 1.35,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final travel = (t * size.height * 0.7 + column * 71) %
          (size.height + 220);
      painter.paint(canvas, Offset(column * 32.0 + 5, travel - 110));
    }
  }

  @override
  bool shouldRepaint(_CyberP old) => old.t != t;
}

class _ScanP extends CustomPainter {
  final double t;
  _ScanP(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final y = t * size.height;
    canvas.drawRect(Rect.fromLTWH(0, y - 30, size.width, 30), Paint()..color = cyan.withValues(alpha: 0.05));
    canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), Paint()..color = cyan.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(_ScanP old) => old.t != t;
}
