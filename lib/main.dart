import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:flutter_v2ray_client/model/v2ray_status.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const List<String> LAN_SUBNETS = [
  '10.0.0.0/8',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '127.0.0.0/8',
  '169.254.0.0/16',
  '224.0.0.0/4',
];

void main() {
  runApp(const ZeusVpnApp());
}

class ZeusVpnApp extends StatelessWidget {
  const ZeusVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZEUS VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050505),
      ),
      home: const VpnHomePage(),
    );
  }
}

class ServerNode {
  final String subTag;
  final String rawUri;
  final String displayName;
  String pingText;
  Color pingColor;

  ServerNode({
    required this.subTag,
    required this.rawUri,
    required this.displayName,
    this.pingText = '--',
    this.pingColor = Colors.grey,
  });
}

class PattSettings {
  String fingerprint;
  String fragment;
  String fragLength;
  String fragInterval;
  bool enableNoise;
  String noiseType;
  String noisePacket;
  String noiseDelay;
  String cipherSuites;
  bool allowInsecure;
  bool enableIPv6;
  bool enableMux;
  String muxConcurrency;
  bool enableReality;
  String realityPublicKey;
  String realityShortId;
  String realitySpiderX;
  String flow;
  String alpn;
  String sni;
  String path;
  String host;
  String headerType;
  String network;
  String dnsMode;
  String customDns;
  bool bypassLan;
  bool proxyOnly;
  String logLevel;

  PattSettings({
    this.fingerprint = 'unsafe',
    this.fragment = 'tlshello',
    this.fragLength = '100-200',
    this.fragInterval = '10-20',
    this.enableNoise = false,
    this.noiseType = 'rand',
    this.noisePacket = '10-20',
    this.noiseDelay = '10-20',
    this.cipherSuites = '',
    this.allowInsecure = false,
    this.enableIPv6 = false,
    this.enableMux = false,
    this.muxConcurrency = '8',
    this.enableReality = false,
    this.realityPublicKey = '',
    this.realityShortId = '',
    this.realitySpiderX = '/',
    this.flow = 'xtls-rprx-vision',
    this.alpn = 'h2,http/1.1',
    this.sni = '',
    this.path = '/',
    this.host = '',
    this.headerType = 'none',
    this.network = 'tcp',
    this.dnsMode = 'auto',
    this.customDns = '1.1.1.1',
    this.bypassLan = false,
    this.proxyOnly = false,
    this.logLevel = 'warning',
  });
}

class VpnHomePage extends StatefulWidget {
  const VpnHomePage({super.key});

  @override
  State<VpnHomePage> createState() => _VpnHomePageState();
}

class _VpnHomePageState extends State<VpnHomePage> with TickerProviderStateMixin {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 10),
  ));

  List<String> _subUrls = [];
  List<ServerNode> _allNodes = [];
  String? _selectedNodeUri;

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isConnected = false;
  bool _isTestingSpeed = false;
  String _speedTestResult = '';

  PattSettings _pattSettings = PattSettings();

  String _uploadSpeed = '0 B/s';
  String _downloadSpeed = '0 B/s';
  String _duration = '00:00:00';
  String _status = 'DISCONNECTED';

  VoidCallback? _nodeUpdateCb;

  final Color neonCyan = const Color(0xFF00F0FF);
  final Color neonMagenta = const Color(0xFFFF007F);
  final Color neonGreen = const Color(0xFF00FF88);
  final Color darkBg = const Color(0xFF050505);

  late V2ray _v2ray;
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _v2ray = V2ray(
      onStatusChanged: (V2RayStatus status) {
        if (mounted) {
          setState(() {
            _status = status.state;
            _isConnected = (status.state == 'CONNECTED');

            _uploadSpeed = _formatSpeed(status.uploadSpeed);
            _downloadSpeed = _formatSpeed(status.downloadSpeed);
            _duration = status.duration ?? '00:00:00';

            if (!_isConnected) {
              _speedTestResult = '';
              _uploadSpeed = '0 B/s';
              _downloadSpeed = '0 B/s';
              _duration = '00:00:00';
            }
          });
        }
      },
    );
    _initV2Ray();
    _loadSavedData();
  }

  Future<void> _initV2Ray() async {
    await _v2ray.initialize(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    );
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  String _formatSpeed(int? bytesPerSecond) {
    final int bps = bytesPerSecond ?? 0;
    if (bps < 1024) return '$bps B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  int _pingMs(ServerNode n) {
    final String t = n.pingText.replaceAll(' ms', '').trim();
    return int.tryParse(t) ?? 999999;
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    _subUrls = prefs.getStringList('subUrls') ?? [];
    _selectedNodeUri = prefs.getString('selectedUri');

    _pattSettings.fingerprint = prefs.getString('patt_fp') ?? 'unsafe';
    _pattSettings.fragment = prefs.getString('patt_frag') ?? 'tlshello';
    _pattSettings.fragLength = prefs.getString('patt_fraglen') ?? '100-200';
    _pattSettings.fragInterval = prefs.getString('patt_fragint') ?? '10-20';
    _pattSettings.enableNoise = prefs.getBool('patt_noise') ?? false;
    _pattSettings.noiseType = prefs.getString('patt_ntype') ?? 'rand';
    _pattSettings.noisePacket = prefs.getString('patt_npacket') ?? '10-20';
    _pattSettings.noiseDelay = prefs.getString('patt_ndelay') ?? '10-20';
    _pattSettings.cipherSuites = prefs.getString('patt_cs') ?? '';
    _pattSettings.allowInsecure = prefs.getBool('patt_insecure') ?? false;
    _pattSettings.enableIPv6 = prefs.getBool('patt_ipv6') ?? false;
    _pattSettings.enableMux = prefs.getBool('patt_mux') ?? false;
    _pattSettings.muxConcurrency = prefs.getString('patt_muxc') ?? '8';
    _pattSettings.enableReality = prefs.getBool('patt_reality') ?? false;
    _pattSettings.realityPublicKey = prefs.getString('patt_pbk') ?? '';
    _pattSettings.realityShortId = prefs.getString('patt_sid') ?? '';
    _pattSettings.realitySpiderX = prefs.getString('patt_spx') ?? '/';
    _pattSettings.flow = prefs.getString('patt_flow') ?? 'xtls-rprx-vision';
    _pattSettings.alpn = prefs.getString('patt_alpn') ?? 'h2,http/1.1';
    _pattSettings.sni = prefs.getString('patt_sni') ?? '';
    _pattSettings.path = prefs.getString('patt_path') ?? '/';
    _pattSettings.host = prefs.getString('patt_host') ?? '';
    _pattSettings.headerType = prefs.getString('patt_header') ?? 'none';
    _pattSettings.network = prefs.getString('patt_network') ?? 'tcp';
    _pattSettings.dnsMode = prefs.getString('patt_dns') ?? 'auto';
    _pattSettings.customDns = prefs.getString('patt_dnsc') ?? '1.1.1.1';
    _pattSettings.bypassLan = prefs.getBool('patt_lan') ?? false;
    _pattSettings.proxyOnly = prefs.getBool('patt_proxyonly') ?? false;
    _pattSettings.logLevel = prefs.getString('patt_log') ?? 'warning';

    if (_subUrls.isNotEmpty) {
      _fetchAllConfigs();
    }
  }

  Future<void> _saveSubs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('subUrls', _subUrls);
  }

  Future<void> _saveSelected() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedNodeUri == null) {
      await prefs.remove('selectedUri');
    } else {
      await prefs.setString('selectedUri', _selectedNodeUri!);
    }
  }

  Future<void> _savePattSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('patt_fp', _pattSettings.fingerprint);
    await prefs.setString('patt_frag', _pattSettings.fragment);
    await prefs.setString('patt_fraglen', _pattSettings.fragLength);
    await prefs.setString('patt_fragint', _pattSettings.fragInterval);
    await prefs.setBool('patt_noise', _pattSettings.enableNoise);
    await prefs.setString('patt_ntype', _pattSettings.noiseType);
    await prefs.setString('patt_npacket', _pattSettings.noisePacket);
    await prefs.setString('patt_ndelay', _pattSettings.noiseDelay);
    await prefs.setString('patt_cs', _pattSettings.cipherSuites);
    await prefs.setBool('patt_insecure', _pattSettings.allowInsecure);
    await prefs.setBool('patt_ipv6', _pattSettings.enableIPv6);
    await prefs.setBool('patt_mux', _pattSettings.enableMux);
    await prefs.setString('patt_muxc', _pattSettings.muxConcurrency);
    await prefs.setBool('patt_reality', _pattSettings.enableReality);
    await prefs.setString('patt_pbk', _pattSettings.realityPublicKey);
    await prefs.setString('patt_sid', _pattSettings.realityShortId);
    await prefs.setString('patt_spx', _pattSettings.realitySpiderX);
    await prefs.setString('patt_flow', _pattSettings.flow);
    await prefs.setString('patt_alpn', _pattSettings.alpn);
    await prefs.setString('patt_sni', _pattSettings.sni);
    await prefs.setString('patt_path', _pattSettings.path);
    await prefs.setString('patt_host', _pattSettings.host);
    await prefs.setString('patt_header', _pattSettings.headerType);
    await prefs.setString('patt_network', _pattSettings.network);
    await prefs.setString('patt_dns', _pattSettings.dnsMode);
    await prefs.setString('patt_dnsc', _pattSettings.customDns);
    await prefs.setBool('patt_lan', _pattSettings.bypassLan);
    await prefs.setBool('patt_proxyonly', _pattSettings.proxyOnly);
    await prefs.setString('patt_log', _pattSettings.logLevel);
  }

  String _extractName(String uriStr) {
    try {
      final uri = Uri.parse(uriStr);
      if (uri.fragment.isNotEmpty) return Uri.decodeComponent(uri.fragment);
      return '${uri.host}:${uri.port}';
    } catch (_) {
      return 'Unknown Server';
    }
  }

  String _nodeTransport(ServerNode n) {
    try {
      final q = Uri.parse(n.rawUri).queryParameters;
      return q['type'] ?? 'tcp';
    } catch (_) {
      return 'tcp';
    }
  }

  String _nodeSecurity(ServerNode n) {
    try {
      final q = Uri.parse(n.rawUri).queryParameters;
      return q['security'] ?? 'none';
    } catch (_) {
      return 'none';
    }
  }

  IconData _nodeIcon(ServerNode n) {
    if (n.rawUri.startsWith('vless://')) return Icons.bolt_rounded;
    if (n.rawUri.startsWith('trojan://')) return Icons.shield_rounded;
    return Icons.memory_rounded;
  }

  Color _nodeColor(ServerNode n) {
    if (n.rawUri.startsWith('vless://')) return neonCyan;
    if (n.rawUri.startsWith('trojan://')) return neonMagenta;
    return Colors.orange;
  }

  String _applyPattNGSettings(String configUri) {
    try {
      final uri = Uri.parse(configUri);
      Map<String, String> queryParams = Map.from(uri.queryParameters);

      queryParams['fp'] = _pattSettings.fingerprint;

      if (_pattSettings.cipherSuites.isNotEmpty) {
        queryParams['cs'] = _pattSettings.cipherSuites;
      }
      if (_pattSettings.allowInsecure) {
        queryParams['allowInsecure'] = '1';
      }
      if (_pattSettings.enableReality) {
        queryParams['security'] = 'reality';
        queryParams['pbk'] = _pattSettings.realityPublicKey;
        queryParams['sid'] = _pattSettings.realityShortId;
        queryParams['spx'] = _pattSettings.realitySpiderX;
      }

      if (uri.scheme == 'vless' &&
          _pattSettings.network == 'tcp' &&
          _pattSettings.flow.isNotEmpty &&
          _pattSettings.flow != 'none') {
        queryParams['flow'] = _pattSettings.flow;
      } else {
        queryParams.remove('flow');
      }

      if (_pattSettings.alpn.isNotEmpty) {
        queryParams['alpn'] = _pattSettings.alpn;
      }
      if (_pattSettings.sni.isNotEmpty) {
        queryParams['sni'] = _pattSettings.sni;
      }
      if (_pattSettings.path.isNotEmpty && _pattSettings.path != '/') {
        queryParams['path'] = _pattSettings.path;
      }
      if (_pattSettings.host.isNotEmpty) {
        queryParams['host'] = _pattSettings.host;
      }
      if (_pattSettings.headerType != 'none') {
        queryParams['headerType'] = _pattSettings.headerType;
      }
      if (_pattSettings.network.isNotEmpty && _pattSettings.network != 'tcp') {
        queryParams['type'] = _pattSettings.network;
      }

      return uri.replace(queryParameters: queryParams).toString();
    } catch (_) {
      return configUri;
    }
  }

  String _applyCoreSettings(String config) {
    try {
      final Map<String, dynamic> json = jsonDecode(config) as Map<String, dynamic>;
      final List? outs = json['outbounds'] as List?;
      if (outs == null || outs.isEmpty) return config;
      final Map<String, dynamic> mainOut = outs[0] as Map<String, dynamic>;

      json['log'] = {'loglevel': _pattSettings.logLevel};

      if (_pattSettings.dnsMode == 'doh') {
        json['dns'] = {
          'servers': [
            'https+local://1.1.1.1/dns-query',
            'https+local://8.8.8.8/dns-query',
          ]
        };
      } else if (_pattSettings.dnsMode == 'custom' && _pattSettings.customDns.isNotEmpty) {
        json['dns'] = {
          'servers': _pattSettings.customDns
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
        };
      }

      if (_pattSettings.enableMux) {
        mainOut['mux'] = {
          'enabled': true,
          'concurrency': int.tryParse(_pattSettings.muxConcurrency) ?? 8,
        };
      }

      final bool needProxyOut =
          _pattSettings.fragment != 'none' || _pattSettings.enableNoise;
      if (needProxyOut) {
        final Map<String, dynamic> fsettings = <String, dynamic>{};
        if (_pattSettings.fragment != 'none') {
          fsettings['fragment'] = {
            'packets': _pattSettings.fragment.startsWith('tlshello')
                ? 'tlshello'
                : _pattSettings.fragment,
            'length': _pattSettings.fragLength,
            'interval': _pattSettings.fragInterval,
          };
        }
        if (_pattSettings.enableNoise) {
          fsettings['noise'] = {
            'type': _pattSettings.noiseType,
            'packet': _pattSettings.noisePacket,
            'delay': _pattSettings.noiseDelay,
          };
        }
        final Map<String, dynamic> stream =
            (mainOut['streamSettings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        final Map<String, dynamic> sockopt =
            (stream['sockopt'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        sockopt['dialerProxy'] = 'zeus-fragment';
        stream['sockopt'] = sockopt;
        mainOut['streamSettings'] = stream;
        outs.add(<String, dynamic>{
          'tag': 'zeus-fragment',
          'protocol': 'freedom',
          'settings': fsettings,
        });
      }

      json['outbounds'] = outs;
      return jsonEncode(json);
    } catch (_) {
      return config;
    }
  }

  Future<void> _fetchAllConfigs() async {
    if (_subUrls.isEmpty) return;

    String? previousSelection = _selectedNodeUri;

    setState(() {
      _isLoading = true;
      _allNodes = [];
    });

    List<ServerNode> fetchedNodes = [];

    for (int i = 0; i < _subUrls.length; i++) {
      String url = _subUrls[i];
      String subTag = 'SUB-${i + 1}';
      try {
        final response = await _dio.get(
          url,
          options: Options(headers: {'User-Agent': 'v2rayNG/1.8.5'}),
        );

        String body = response.data.toString().trim();
        try {
          body = utf8.decode(base64.decode(base64.normalize(body)));
        } catch (_) {}

        final links = body
            .split('\n')
            .map((e) => e.trim())
            .where((e) =>
                e.startsWith('vless://') ||
                e.startsWith('trojan://') ||
                e.startsWith('vmess://'))
            .map((link) =>
                link.startsWith('vmess://') ? link : _applyPattNGSettings(link))
            .toList();

        for (String link in links) {
          fetchedNodes.add(ServerNode(
            subTag: subTag,
            rawUri: link,
            displayName: '[$subTag] ${_extractName(link)}',
          ));
        }
      } catch (e) {
        debugPrint('sub fetch error ($subTag): $e');
      }
    }

    setState(() {
      _allNodes = fetchedNodes;

      if (previousSelection != null &&
          _allNodes.any((n) => n.rawUri == previousSelection)) {
        _selectedNodeUri = previousSelection;
      } else if (_allNodes.isNotEmpty) {
        _selectedNodeUri = _allNodes.first.rawUri;
      } else {
        _selectedNodeUri = null;
      }
    });
    _nodeUpdateCb?.call();

    _testAllLatencies();

    setState(() => _isLoading = false);
    _nodeUpdateCb?.call();
  }

  Future<void> _testAllLatencies() async {
    const int concurrency = 20;
    final List<ServerNode> queue = List<ServerNode>.from(_allNodes);
    await Future.wait(List.generate(concurrency, (_) async {
      while (queue.isNotEmpty) {
        final ServerNode node = queue.removeAt(0);
        await _pingSingleServer(node);
      }
    }));
  }

  Future<void> _pingSingleServer(ServerNode node) async {
    try {
      final uri = Uri.parse(node.rawUri);
      if (uri.port == 0) {
        if (mounted) {
          setState(() {
            node.pingText = 'TIMEOUT';
            node.pingColor = neonMagenta;
          });
          _nodeUpdateCb?.call();
        }
        return;
      }
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect(
        uri.host,
        uri.port,
        timeout: const Duration(seconds: 3),
      );
      stopwatch.stop();
      socket.destroy();
      if (mounted) {
        setState(() {
          node.pingText = '${stopwatch.elapsedMilliseconds} ms';
          int p = stopwatch.elapsedMilliseconds;
          node.pingColor =
              p < 200 ? neonGreen : (p < 500 ? Colors.orange : neonMagenta);
        });
        _nodeUpdateCb?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          node.pingText = 'TIMEOUT';
          node.pingColor = neonMagenta;
        });
        _nodeUpdateCb?.call();
      }
    }
  }

  Future<void> _runSpeedTest() async {
    setState(() {
      _isTestingSpeed = true;
      _speedTestResult = 'TESTING...';
    });
    try {
      final stopwatch = Stopwatch()..start();
      final response = await _dio.get(
        'https://speed.cloudflare.com/__down?bytes=10000000',
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      stopwatch.stop();
      double seconds = stopwatch.elapsedMilliseconds / 1000.0;
      if (seconds == 0) seconds = 0.1;
      double bytes = response.data.length.toDouble();
      double speedMbps = (bytes * 8) / (seconds * 1024 * 1024);
      setState(() {
        _speedTestResult = '${speedMbps.toStringAsFixed(1)} Mbps';
      });
    } catch (e) {
      setState(() {
        _speedTestResult = 'FAILED';
      });
    } finally {
      setState(() => _isTestingSpeed = false);
    }
  }

  Future<void> _toggleConnection() async {
    if (!_isInitialized) {
      _showSnackBar('Core is initializing...', isError: true);
      return;
    }
    if (_isConnected) {
      await _v2ray.stopV2Ray();
      return;
    }
    if (_selectedNodeUri == null) {
      _showSnackBar('Please select a server first.', isError: true);
      return;
    }

    if (!_pattSettings.proxyOnly) {
      final hasPermission = await _v2ray.requestPermission();
      if (!hasPermission) {
        _showSnackBar('VPN permission denied.', isError: true);
        return;
      }
    }

    final parser = V2ray.parseFromURL(_selectedNodeUri!);
    final String config = _applyCoreSettings(parser.getFullConfiguration());
    await _v2ray.startV2Ray(
      remark: parser.remark,
      config: config,
      blockedApps: null,
      bypassSubnets: _pattSettings.bypassLan ? LAN_SUBNETS : null,
      proxyOnly: _pattSettings.proxyOnly,
    );
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError ? neonMagenta : neonGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showServerListModal() {
    String query = '';
    String filterTag = 'ALL';
    int sortMode = 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            _nodeUpdateCb = () => setModalState(() {});

            List<ServerNode> visible = _allNodes.where((n) {
              final okTag = filterTag == 'ALL' || n.subTag == filterTag;
              final okQ = query.isEmpty ||
                  n.displayName.toLowerCase().contains(query.toLowerCase());
              return okTag && okQ;
            }).toList();

            if (sortMode == 1) {
              visible.sort((a, b) => _pingMs(a).compareTo(_pingMs(b)));
            } else if (sortMode == 2) {
              visible.sort((a, b) => a.displayName
                  .toLowerCase()
                  .compareTo(b.displayName.toLowerCase()));
            }

            final List<String> tags = [
              'ALL',
              ..._allNodes.map((e) => e.subTag).toSet().toList(),
            ];

            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0F),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(top: BorderSide(color: neonCyan.withValues(alpha: 0.5), width: 2)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(width: 50, height: 4, decoration: BoxDecoration(color: neonCyan.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: Row(
                      children: [
                        Icon(Icons.dns, color: neonCyan, size: 18),
                        const SizedBox(width: 8),
                        Text('NODE CENTER', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: neonCyan, letterSpacing: 2)),
                        const SizedBox(width: 8),
                        Text('${visible.length}/${_allNodes.length}', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Sort',
                          icon: Icon(Icons.sort, color: neonMagenta, size: 20),
                          onPressed: () {
                            setModalState(() {
                              sortMode = (sortMode + 1) % 3;
                            });
                            _showSnackBar(sortMode == 0 ? 'Sort: Default' : (sortMode == 1 ? 'Sort: Best Ping' : 'Sort: Name'));
                          },
                        ),
                        IconButton(
                          tooltip: 'Ping all',
                          icon: Icon(Icons.network_ping, color: neonGreen, size: 20),
                          onPressed: _testAllLatencies,
                        ),
                        IconButton(
                          tooltip: 'Sync subs',
                          icon: Icon(Icons.refresh, color: neonCyan, size: 20),
                          onPressed: _fetchAllConfigs,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      onChanged: (v) => setModalState(() => query = v),
                      decoration: InputDecoration(
                        hintText: 'SEARCH NODE...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
                        prefixIcon: Icon(Icons.search, color: neonCyan, size: 18),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      children: tags.map((tag) {
                        final bool on = filterTag == tag;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setModalState(() => filterTag = tag),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: on ? neonCyan.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: on ? neonCyan : Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: Text(tag, style: TextStyle(color: on ? neonCyan : Colors.white.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: visible.isEmpty
                        ? Center(child: Text('NO NODES FOUND', style: TextStyle(color: Colors.white.withValues(alpha: 0.3))))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final node = visible[index];
                              final isSelected = node.rawUri == _selectedNodeUri;
                              final bool showHeader = sortMode == 0 &&
                                  (index == 0 || visible[index - 1].subTag != node.subTag);

                              return Column(
                                children: [
                                  if (showHeader)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                                      child: Row(
                                        children: [
                                          Icon(Icons.layers, size: 12, color: neonMagenta),
                                          const SizedBox(width: 6),
                                          Text(node.subTag, style: TextStyle(color: neonMagenta, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                          const SizedBox(width: 6),
                                          Text('(${_allNodes.where((e) => e.subTag == node.subTag).length})', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 9)),
                                          const Expanded(child: Divider(color: Colors.white12, height: 4)),
                                        ],
                                      ),
                                    ),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedNodeUri = node.rawUri;
                                      });
                                      _saveSelected();
                                      setModalState(() {});
                                      Navigator.pop(context);
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isSelected ? neonCyan.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.03),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: isSelected ? neonCyan : Colors.white.withValues(alpha: 0.06)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(_nodeIcon(node), color: _nodeColor(node), size: 18),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  node.displayName,
                                                  style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 13),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 3),
                                                Row(
                                                  children: [
                                                    Text(_nodeTransport(node).toUpperCase(), style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 9, fontWeight: FontWeight.bold)),
                                                    const SizedBox(width: 6),
                                                    Text(_nodeSecurity(node).toUpperCase(), style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 9, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: node.pingColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: node.pingColor.withValues(alpha: 0.5)),
                                            ),
                                            child: Text(node.pingText, style: TextStyle(color: node.pingColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                          if (isSelected) ...[
                                            const SizedBox(width: 8),
                                            Icon(Icons.check_circle, color: neonGreen, size: 18),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      _nodeUpdateCb = null;
      if (mounted) setState(() {});
    });
  }

  void _showSubscriptionManager() {
    TextEditingController newSubController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0F),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(top: BorderSide(color: neonCyan.withValues(alpha: 0.5), width: 2)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(width: 50, height: 4, decoration: BoxDecoration(color: neonCyan.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 15),
                  Text('SUBSCRIPTION MANAGER', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: neonCyan, letterSpacing: 2)),
                  const SizedBox(height: 15),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              border: Border.all(color: neonMagenta.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: TextField(
                              controller: newSubController,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              decoration: InputDecoration(
                                hintText: 'PASTE NEW SUB LINK (https://...)',
                                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 11),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () {
                            final String val = newSubController.text.trim();
                            if (!val.startsWith('http://') && !val.startsWith('https://')) {
                              _showSnackBar('Invalid URL! Must start with https://', isError: true);
                              return;
                            }
                            if (_subUrls.contains(val)) {
                              _showSnackBar('This sub is already added!', isError: true);
                              return;
                            }
                            setState(() => _subUrls.add(val));
                            _saveSubs();
                            newSubController.clear();
                            setModalState(() {});
                            _showSnackBar('Sub added. Press SAVE & SYNC.');
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: neonGreen.withValues(alpha: 0.1),
                              border: Border.all(color: neonGreen.withValues(alpha: 0.5)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.add, color: Color(0xFF00FF88), size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 15),

                  Expanded(
                    child: _subUrls.isEmpty
                        ? Center(child: Text('NO SUBSCRIPTIONS ADDED', style: TextStyle(color: Colors.white.withValues(alpha: 0.3))))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            itemCount: _subUrls.length,
                            itemBuilder: (context, index) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: neonCyan.withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(color: neonMagenta.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                      child: Text('S${index + 1}', style: TextStyle(color: neonMagenta, fontSize: 9, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.link, color: neonCyan, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _subUrls[index],
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Sync this sub',
                                      icon: Icon(Icons.sync, color: neonCyan, size: 18),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _fetchAllConfigs();
                                      },
                                    ),
                                    IconButton(
                                      tooltip: 'Delete',
                                      icon: Icon(Icons.delete_outline, color: neonMagenta, size: 20),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            backgroundColor: const Color(0xFF0A0A0F),
                                            title: const Text('DELETE SUB?', style: TextStyle(color: Color(0xFF00F0FF), fontSize: 15, fontWeight: FontWeight.bold)),
                                            content: Text(_subUrls[index], style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(c),
                                                child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  setState(() => _subUrls.removeAt(index));
                                                  _saveSubs();
                                                  setModalState(() {});
                                                  Navigator.pop(c);
                                                  _showSnackBar('Sub removed.');
                                                },
                                                child: const Text('DELETE', style: TextStyle(color: Color(0xFFFF007F), fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(15),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: neonCyan.withValues(alpha: 0.1),
                          side: const BorderSide(color: Color(0xFF00F0FF)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _fetchAllConfigs();
                        },
                        child: const Text('SAVE & SYNC ALL', style: TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold, letterSpacing: 2)),
                      ),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showPattSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0F),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(top: BorderSide(color: neonCyan.withValues(alpha: 0.5), width: 2)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(width: 50, height: 4, decoration: BoxDecoration(color: neonCyan.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 15),
                  Text('PATT-NG FULL SETTINGS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: neonCyan, letterSpacing: 2)),
                  const SizedBox(height: 10),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _buildSectionHeader('TLS / ANTI-CENSORSHIP'),
                        _buildDropdown('FINGERPRINT', ['unsafe', 'chrome', 'firefox', 'safari', 'randomized', 'randomizednoalpn'], _pattSettings.fingerprint, (val) {
                          setModalState(() => _pattSettings.fingerprint = val);
                          _savePattSettings();
                        }),
                        _buildTextField('CIPHER SUITES', 'e.g., real_firefox_cipherSuites', _pattSettings.cipherSuites, (val) {
                          _pattSettings.cipherSuites = val;
                          _savePattSettings();
                        }),
                        _buildSwitch('ALLOW INSECURE', 'Unencrypted VLESS/Trojan (PattNG)', _pattSettings.allowInsecure, (val) {
                          setModalState(() => _pattSettings.allowInsecure = val);
                          _savePattSettings();
                        }),

                        _buildSectionHeader('FRAGMENT / NOISE'),
                        _buildDropdown('FRAGMENTATION', ['tlshello', 'none'], _pattSettings.fragment, (val) {
                          setModalState(() => _pattSettings.fragment = val);
                          _savePattSettings();
                        }),
                        if (_pattSettings.fragment != 'none') ...[
                          _buildTextField('FRAGMENT LENGTH', '100-200', _pattSettings.fragLength, (val) {
                            _pattSettings.fragLength = val;
                            _savePattSettings();
                          }),
                          _buildTextField('FRAGMENT INTERVAL', '10-20', _pattSettings.fragInterval, (val) {
                            _pattSettings.fragInterval = val;
                            _savePattSettings();
                          }),
                        ],
                        _buildSwitch('ENABLE NOISE', 'UDP noise padding', _pattSettings.enableNoise, (val) {
                          setModalState(() => _pattSettings.enableNoise = val);
                          _savePattSettings();
                        }),
                        if (_pattSettings.enableNoise) ...[
                          _buildDropdown('NOISE TYPE', ['rand', 'base64', 'str', 'hex'], _pattSettings.noiseType, (val) {
                            setModalState(() => _pattSettings.noiseType = val);
                            _savePattSettings();
                          }),
                          _buildTextField('NOISE PACKET', '10-20', _pattSettings.noisePacket, (val) {
                            _pattSettings.noisePacket = val;
                            _savePattSettings();
                          }),
                          _buildTextField('NOISE DELAY', '10-20', _pattSettings.noiseDelay, (val) {
                            _pattSettings.noiseDelay = val;
                            _savePattSettings();
                          }),
                        ],

                        _buildSectionHeader('CORE / ROUTING'),
                        _buildSwitch('ENABLE MUX', 'Multiplexing', _pattSettings.enableMux, (val) {
                          setModalState(() => _pattSettings.enableMux = val);
                          _savePattSettings();
                        }),
                        if (_pattSettings.enableMux)
                          _buildTextField('MUX CONCURRENCY', '8', _pattSettings.muxConcurrency, (val) {
                            _pattSettings.muxConcurrency = val;
                            _savePattSettings();
                          }),
                        _buildSwitch('BYPASS LAN', 'Direct traffic for local networks', _pattSettings.bypassLan, (val) {
                          setModalState(() => _pattSettings.bypassLan = val);
                          _savePattSettings();
                        }),
                        _buildSwitch('PROXY ONLY MODE', 'No VPN tunnel (local proxy only)', _pattSettings.proxyOnly, (val) {
                          setModalState(() => _pattSettings.proxyOnly = val);
                          _savePattSettings();
                        }),
                        _buildDropdown('LOG LEVEL', ['debug', 'info', 'warning', 'error',
