  // lib/core/controller.dart — منطق مرکزی ZEUS (اتصال، اشتراک، پینگ، سرعت، WARP، لاگ)
  import 'dart:async';
  import 'dart:convert';
  import 'dart:io';
  import 'dart:math';

  import 'package:dio/dio.dart';
  import 'package:dio/io.dart';
  import 'package:flutter/foundation.dart';
  import 'package:flutter_v2ray_client/flutter_v2ray.dart';
  import 'package:shared_preferences/shared_preferences.dart';

  import '../warp.dart';
  import 'config_builder.dart';
  import 'models.dart';

  const String kPingUrl = 'https://www.gstatic.com/generate_204';
  const String kSpeedUrl = 'https://speed.cloudflare.com/__down?bytes=15000000';
  const List<String> kIpUrls = [
    'https://api.ipify.org?format=text',
    'https://icanhazip.com',
    'https://ifconfig.me/ip',
  ];

  enum ConnState { disconnected, connecting, connected, disconnecting }

  /// وضعیت واقعی تونل بعد از این‌که سرویس VPN بالا آمد
  enum TunnelState { idle, checking, ok, failed }

  class ZeusController extends ChangeNotifier {
    // ───────── singleton ─────────
    static final ZeusController I = ZeusController._();
    ZeusController._();

    // ───────── deps ─────────
    late final V2ray _v2ray = V2ray(onStatusChanged: _onStatus);
    final Dio _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
    /// Dio که از پروکسی محلی HTTP هسته رد می‌شود (برای تست سرعت/IP در حالت متصل)
    late final Dio _proxyDio = _makeProxyDio();

    // ───────── state ─────────
    bool ready = false;
    bool booted = false;
    ConnState conn = ConnState.disconnected;
    TunnelState tunnel = TunnelState.idle;
    bool busy = false;

    List<SubRecord> subs = [];
    List<ServerNode> nodes = [];
    String? selUri;
    final Patt patt = Patt();
    final AppSettings settings = AppSettings();
    WarpConfig? warp;
    bool warpOn = false;

    bool loadingSubs = false;
    bool pinging = false;
    /// سرورهایی که همین لحظه در حال سنجش‌اند (برای نشانگر «سنجش…» در لیست)
    final Set<String> pingingUris = {};
    bool testingSpeed = false;
    String speedResult = '';
    /// علت خوانای شکست آخرین تست سرعت (خالی = بدون خطا)
    String speedError = '';

    // traffic
    int upSpeed = 0, downSpeed = 0; // B/s
    int upTotal = 0, downTotal = 0; // bytes
    String duration = '00:00:00';
    final List<int> downHistory = List.filled(40, 0, growable: true);
    final List<int> upHistory = List.filled(40, 0, growable: true);
    String publicIp = '--';
    DateTime? connectedAt;
    // ✅ C1: سرعت از اختلاف حجم محاسبه می‌شود (فیلد سرعت پلاگین صفر می‌دهد)
    DateTime? _lastStatAt;
    int _lastUpTotal = 0, _lastDownTotal = 0;

    // logs
    final List<LogEntry> logs = [];
    static const int _maxLogs = 400;

    int _syncGen = 0;
    int _connGen = 0; // برای لغو پروب‌های اتصال قبلی
    Timer? _connectTimeout;
    CancelToken? _speedToken;

    // ───────── derived ─────────
    bool get connected => conn == ConnState.connected;
    bool get connecting => conn == ConnState.connecting;
    /// اتصال واقعاً کار می‌کند (سرویس بالا + تونل تأیید شده)
    bool get online => connected && tunnel == TunnelState.ok;
    bool get warpReady => warpOn && (warp?.isValid ?? false);
    ServerNode? get selected => selUri == null
        ? null
        : nodes.cast<ServerNode?>().firstWhere((n) => n!.rawUri == selUri, orElse: () => null);
    int get countryCount => nodes.map((n) => n.flag).toSet().length;
    int get avgPing {
      final ok = nodes.where((n) => n.pingMs >= 0).map((n) => n.pingMs).toList();
      if (ok.isEmpty) return -1;
      return ok.reduce((a, b) => a + b) ~/ ok.length;
    }

    ConfigBuilder get _builder => ConfigBuilder(patt: patt, warp: warp, warpOn: warpOn);

    // ───────── boot ─────────
    Future<void> boot() async {
      if (booted) return;
      booted = true;
      final p = await SharedPreferences.getInstance();
      _loadPrefs(p);
      log(LogKind.system, 'ZEUS starting…');
      try {
        await _v2ray.initialize(
          notificationIconResourceType: 'mipmap',
          notificationIconResourceName: 'ic_launcher',
        );
        ready = true;
        log(LogKind.core, 'Xray core initialized');
      } catch (e) {
        ready = false;
        log(LogKind.core, 'Core init failed: $e', LogLevel.error);
      }
      notifyListeners();
      if (subs.isNotEmpty) syncAll();
    }

    void _loadPrefs(SharedPreferences p) {
      final rawSubs = p.getString('subs_v2');
      if (rawSubs != null) {
        subs = (jsonDecode(rawSubs) as List).map(SubRecord.fromJson).whereType<SubRecord>().toList();
      } else {
        subs = (p.getStringList('subs') ?? []).map((u) => SubRecord(url: u)).toList();
      }
      selUri = p.getString('sel');
      warpOn = p.getBool('warp_on') ?? false;
      warp = WarpConfig.tryDecode(p.getString('warp_json'));
      try {
        final pj = p.getString('patt_json');
        if (pj != null) patt.loadJson(jsonDecode(pj) as Map);
        final sj = p.getString('settings_json');
        if (sj != null) settings.loadJson(jsonDecode(sj) as Map);
        final nc = p.getString('nodes_cache');
        if (nc != null) {
          nodes = (jsonDecode(nc) as List)
              .map((e) => ServerNode.fromJson(e as Map))
              .whereType<ServerNode>()
              .toList();
          // ✅ پینگ جلسهٔ قبل معتبر نیست؛ تا سنجش مجدد «تست‌نشده» نمایش داده شود
          for (final n in nodes) {
            n.pingMs = -2;
          }
        }
      } catch (e) {
        log(LogKind.system, 'Prefs load error: $e', LogLevel.warn);
      }
    }

    Future<SharedPreferences> get _p => SharedPreferences.getInstance();
    Future<void> savePatt() async => (await _p).setString('patt_json', jsonEncode(patt.toJson()));
    Future<void> saveSettings() async => (await _p).setString('settings_json', jsonEncode(settings.toJson()));
    Future<void> _saveSubs() async =>
        (await _p).setString('subs_v2', jsonEncode(subs.map((s) => s.toJson()).toList()));
    Future<void> _saveNodes() async =>
        (await _p).setString('nodes_cache', jsonEncode(nodes.map((n) => n.toJson()).toList()));
    Future<void> _saveSel() async {
      final p = await _p;
      selUri == null ? await p.remove('sel') : await p.setString('sel', selUri!);
    }
    Future<void> saveWarp() async {
      final p = await _p;
      await p.setBool('warp_on', warpOn);
      await p.setString('warp_json', warp?.encode() ?? '');
    }

    /// برای صفحاتی که فیلدهای patt/settings را مستقیم تغییر می‌دهند
    void refresh() => notifyListeners();

    // ───────── logs ─────────
    void log(LogKind kind, String text, [LogLevel level = LogLevel.info]) {
      if (!settings.saveLogs && level == LogLevel.info) return;
      logs.insert(0, LogEntry(kind, level, text));
      if (logs.length > _maxLogs) logs.removeRange(_maxLogs, logs.length);
      notifyListeners();
    }

    void clearLogs() {
      logs.clear();
      notifyListeners();
    }

    String exportLogs() =>
        logs.reversed.map((l) => '[${l.timeText}] [${l.levelText}] [${l.kind.name}] ${l.text}').join('\n');

    // ───────── status from core ─────────
    void _onStatus(V2RayStatus s) {
      final st = s.state.toUpperCase();
      final prev = conn;
      if (st == 'CONNECTED') {
        conn = ConnState.connected;
      } else if (st == 'CONNECTING' || st == 'CONNECT') {
        conn = ConnState.connecting;
      } else {
        conn = ConnState.disconnected;
      }
      if (conn == ConnState.connected && prev != ConnState.connected) {
        _connectTimeout?.cancel();
        connectedAt = DateTime.now();
        log(LogKind.connection, 'VPN service up — verifying tunnel…');
        _verifyTunnel(++_connGen); // به‌جای اعتماد به CONNECTED، تونل را واقعاً تست کن
      }
      if (conn == ConnState.disconnected && prev != ConnState.disconnected) {
        _connectTimeout?.cancel();
        _connGen++;
        _resetTraffic();
        log(LogKind.connection, 'Disconnected');
      }

      upTotal = s.upload;
      downTotal = s.download;

      // ✅ C1: سرعت = اختلاف حجم ÷ بازهٔ زمانی (مستقل از فیلد سرعت پلاگین)
      final now = DateTime.now();
      if (connected && _lastStatAt != null) {
        final dt = now.difference(_lastStatAt!).inMilliseconds;
        if (dt >= 400) {
          final du = s.upload - _lastUpTotal;
          final dd = s.download - _lastDownTotal;
          if (du >= 0 && dd >= 0) {
            upSpeed = (du * 1000 / dt).round();
            downSpeed = (dd * 1000 / dt).round();
          }
          _lastStatAt = now;
          _lastUpTotal = s.upload;
          _lastDownTotal = s.download;
        }
      } else {
        _lastStatAt = now;
        _lastUpTotal = s.upload;
        _lastDownTotal = s.download;
        upSpeed = s.uploadSpeed;
        downSpeed = s.downloadSpeed;
      }

      duration = connected ? s.duration : '00:00:00';
      if (connected) {
        downHistory
          ..add(downSpeed)
          ..removeAt(0);
        upHistory
          ..add(upSpeed)
          ..removeAt(0);
      }
      notifyListeners();
    }

    /// چند بار از داخل تونل به اینترنت می‌زند؛ موفق شد → IP را می‌گیرد
    Future<void> _verifyTunnel(int gen) async {
      tunnel = TunnelState.checking;
      publicIp = '…';
      notifyListeners();
      for (var i = 0; i < 4; i++) {
        await Future.delayed(Duration(milliseconds: 700 * (i + 1)));
        if (gen != _connGen || !connected) return;
        try {
          final d = await _v2ray.getConnectedServerDelay(url: kPingUrl);
          if (d >= 0) {
            tunnel = TunnelState.ok;
            final sel = selected;
            if (sel != null) sel.pingMs = d;
            log(LogKind.connection, 'Tunnel OK (${d}ms)');
            notifyListeners();
            _fetchIp(gen);
            return;
          }
        } catch (e) {
          log(LogKind.connection, 'Tunnel probe ${i + 1}: $e', LogLevel.warn);
        }
      }
      if (gen != _connGen || !connected) return;
      tunnel = TunnelState.failed;
      publicIp = '--';
      log(LogKind.connection, 'Tunnel verification failed — server may be dead/blocked', LogLevel.error);
      notifyListeners();
    }

    /// تست دستی مجدد تونل (برای دکمهٔ «بررسی مجدد» در صفحهٔ خانه)
    Future<void> recheckTunnel() async {
      if (!connected) return;
      await _verifyTunnel(++_connGen);
    }

    void _resetTraffic() {
      upSpeed = downSpeed = upTotal = downTotal = 0;
      _lastStatAt = null;
      _lastUpTotal = _lastDownTotal = 0;
      duration = '00:00:00';
      speedResult = '';
      speedError = '';
      publicIp = '--';
      connectedAt = null;
      tunnel = TunnelState.idle;
      for (var i = 0; i < downHistory.length; i++) {
        downHistory[i] = 0;
        upHistory[i] = 0;
      }
    }

    // ───────── connect / disconnect ─────────
    Future<String?> toggle() async {
      if (!ready) return 'هستهٔ اتصال آماده نیست';
      if (busy) return null;
      if (connected || connecting) {
        await disconnect();
        return null;
      }
      return connect();
    }

    Future<String?> connect() async {
      final warpOnly = selUri == null && warpReady;
      if (selUri == null && !warpOnly) return 'اول یک سرور انتخاب کنید';
      busy = true;
      notifyListeners();
      try {
        final ok = await _v2ray.requestPermission();
        if (!ok) throw Exception('مجوز VPN داده نشد');
        final cfg = warpOnly ? _builder.buildWarpOnly() : _builder.build(selUri!);
        final remark = warpOnly ? 'ZEUS • WARP' : (selected?.displayName ?? 'ZEUS');
        conn = ConnState.connecting;
        tunnel = TunnelState.idle;
        notifyListeners();
        log(LogKind.connection, 'Connecting to $remark');
        final feats = [
          if (patt.frag != 'none') 'fragment',
          if (warpReady) 'warp',
          if (patt.mux) 'mux',
        ].join(' ');
        log(LogKind.core, 'Loading config${feats.isEmpty ? '' : ' ($feats)'}');
        await _v2ray.startV2Ray(
          remark: remark,
          config: jsonEncode(cfg),
          proxyOnly: false,
          notificationDisconnectButtonName: 'قطع',
        );
        _connectTimeout?.cancel();
        _connectTimeout = Timer(const Duration(seconds: 20), () async {
          if (conn == ConnState.connecting) {
            log(LogKind.connection, 'Connect timeout', LogLevel.error);
            await disconnect();
          }
        });
        return null;
      } catch (e) {
        conn = ConnState.disconnected;
        log(LogKind.connection, 'Connect failed: $e', LogLevel.error);
        return 'اتصال ناموفق: $e';
      } finally {
        busy = false;
        notifyListeners();
      }
    }

    Future<void> disconnect() async {
      _connectTimeout?.cancel();
      _connGen++;
      busy = true;
      conn = ConnState.disconnecting;
      notifyListeners();
      try {
        await _v2ray.stopV2Ray();
      } catch (e) {
        log(LogKind.core, 'Stop error: $e', LogLevel.warn);
      }
      conn = ConnState.disconnected;
      _resetTraffic();
      busy = false;
      notifyListeners();
    }

    Future<String?> selectNode(ServerNode n, {bool reconnect = true}) async {
      selUri = n.rawUri;
      await _saveSel();
      notifyListeners();
      if (reconnect && (connected || connecting)) {
        await disconnect();
        return connect();
      }
      return null;
    }

    Future<void> toggleFavorite(ServerNode n) async {
      n.favorite = !n.favorite;
      await _saveNodes();
      notifyListeners();
    }

    // ───────── subscriptions ─────────
    Future<String?> addSub(String url) async {
      final u = url.trim();
      if (!u.startsWith('http')) return 'لینک معتبر نیست';
      if (subs.any((s) => s.url == u)) return 'این اشتراک قبلاً اضافه شده';
      subs.add(SubRecord(url: u, name: Uri.tryParse(u)?.host ?? ''));
      await _saveSubs();
      notifyListeners();
      await syncAll();
      return null;
    }

    Future<void> removeSub(SubRecord s) async {
      final idx = subs.indexOf(s);
      subs.remove(s);
      nodes.removeWhere((n) => n.subTag == 'S${idx + 1}');
      await _saveSubs();
      await _saveNodes();
      notifyListeners();
      if (subs.isNotEmpty) syncAll();
    }

    Future<List<String>> _fetchSub(String url) async {
      final r = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain, headers: {'User-Agent': 'v2rayNG/1.8.0'}),
      );
      return parseSubscriptionBody(r.data ?? '');
    }

    Future<String?> syncAll() async {
      if (subs.isEmpty || loadingSubs) return null;
      final gen = ++_syncGen;
      loadingSubs = true;
      notifyListeners();
      log(LogKind.system, 'Syncing ${subs.length} subscription(s)');

      final results = await Future.wait(subs.map((s) async {
        try {
          final list = await _fetchSub(s.url);
          s.lastOk = list.isNotEmpty;
          s.lastSync = DateTime.now();
          s.nodeCount = list.length;
          return list;
        } catch (e) {
          s.lastOk = false;
          log(LogKind.system, 'Sub failed (${s.name}): $e', LogLevel.warn);
          return <String>[];
        }
      }));
      if (gen != _syncGen) return null;

      final fresh = <ServerNode>[];
      for (var i = 0; i < subs.length; i++) {
        for (final uri in results[i]) {
          fresh.add(ServerNode.fromUri(uri, 'S${i + 1}'));
        }
      }
      loadingSubs = false;
      await _saveSubs();

      if (fresh.isEmpty) {
        notifyListeners();
        return 'هیچ سروری دریافت نشد؛ لیست قبلی حفظ شد';
      }
      // پینگ و علاقه‌مندی همین جلسه حفظ می‌شود
      final old = {for (final n in nodes) n.rawUri: n};
      for (final n in fresh) {
        final o = old[n.rawUri];
        if (o != null) {
          n.pingMs = o.pingMs;
          n.favorite = o.favorite;
        }
      }
      nodes = fresh;
      if (selUri != null && !nodes.any((n) => n.rawUri == selUri) && !connected && !connecting) {
        selUri = null;
        await _saveSel();
      }
      await _saveNodes();
      log(LogKind.system, 'Loaded ${nodes.length} servers');
      notifyListeners();
      final failed = subs.where((s) => !s.lastOk).length;
      return failed > 0 ? '$failed اشتراک دریافت نشد' : null;
    }

    // ───────── ping ─────────
    Future<int> _realDelay(ServerNode n) async {
      final cfg = _builder.buildForPing(n.rawUri);
      return _v2ray.getServerDelay(config: jsonEncode(cfg), url: kPingUrl);
    }

    Future<int> _tcpDelay(ServerNode n) async {
      if (n.host.isEmpty || n.port == 0) {
        log(LogKind.system, 'TCP ping skipped: no host/port parsed for ${n.displayName}', LogLevel.warn);
        return -1;
      }
      final sw = Stopwatch()..start();
      try {
        final s = await Socket.connect(n.host, n.port, timeout: const Duration(seconds: 5));
        s.destroy();
        return sw.elapsedMilliseconds;
      } catch (_) {
        return -1;
      }
    }

    Future<void> pingOne(ServerNode n) async {
      if (pingingUris.contains(n.rawUri)) return;
      pingingUris.add(n.rawUri);
      notifyListeners();
      int ms = -1;
      try {
        if (connected && n.rawUri == selUri) {
          // سرور فعال را از داخل تونل واقعی بسنج (TCP به خودِ سرور از داخل TUN timeout می‌دهد)
          ms = await _v2ray.getConnectedServerDelay(url: kPingUrl);
        } else if (connected || connecting || settings.delayMode == 1) {
          ms = await _tcpDelay(n);
        } else {
          ms = await _realDelay(n);
        }
      } catch (_) {
        ms = -1;
      } finally {
        pingingUris.remove(n.rawUri);
        n.pingMs = ms < 0 ? -1 : ms;
        notifyListeners();
      }
    }

    Future<void> pingAll() async {
      if (pinging || nodes.isEmpty) return;
      pinging = true;
      notifyListeners();
      final queue = List<ServerNode>.from(nodes);
      Future<void> worker() async {
        while (queue.isNotEmpty) {
          await pingOne(queue.removeAt(0));
        }
      }
      await Future.wait(List.generate(4, (_) => worker()));
      await _saveNodes();
      pinging = false;
      notifyListeners();
    }

    ServerNode? bestNode() {
      final ok = nodes.where((n) => n.pingMs >= 0).toList()
        ..sort((a, b) => a.pingMs.compareTo(b.pingMs));
      return ok.isEmpty ? null : ok.first;
    }

    // ───────── speed test / ip ─────────
    Dio _makeProxyDio() {
      final d = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 40),
      ));
      d.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final hc = HttpClient();
          hc.findProxy = (_) => 'PROXY 127.0.0.1:$kHttpPort';
          hc.badCertificateCallback = (_, __, ___) => false;
          return hc;
        },
      );
      return d;
    }

    static final RegExp _ipRe = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$|^[0-9a-fA-F:]{3,}$');

    /// IP عمومی: چند منبع + چند تلاش + fallback مستقیم از داخل TUN
    Future<void> _fetchIp(int gen) async {
      publicIp = '…';
      notifyListeners();
      for (var attempt = 0; attempt < 3; attempt++) {
        for (final url in kIpUrls) {
          if (gen != _connGen || !connected) return;
          final ip = await _tryIp(_proxyDio, url) ?? await _tryIp(_dio, url);
          if (ip != null) {
            publicIp = ip;
            log(LogKind.connection, 'Public IP: $ip');
            notifyListeners();
            return;
          }
        }
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
      if (gen != _connGen || !connected) return;
      publicIp = '--';
      log(LogKind.connection, 'Could not fetch public IP', LogLevel.warn);
      notifyListeners();
    }

    Future<String?> _tryIp(Dio d, String url) async {
      try {
        final r = await d.get<String>(url, options: Options(responseType: ResponseType.plain));
        final t = (r.data ?? '').trim();
        return _ipRe.hasMatch(t) ? t : null;
      } catch (_) {
        return null;
      }
    }

    Future<void> refreshIp() async {
      if (!connected) return;
      await _fetchIp(_connGen);
    }

    Future<void> speedTest() async {
      if (!connected || testingSpeed) return;
      testingSpeed = true;
      speedResult = '…';
      speedError = '';
      notifyListeners();
      _speedToken = CancelToken();
      final sw = Stopwatch()..start();
      try {
        final r = await _proxyDio.get<List<int>>(
          kSpeedUrl,
          options: Options(responseType: ResponseType.bytes),
          cancelToken: _speedToken,
        );
        sw.stop();
        final bytes = r.data?.length ?? 0;
        final mbps = bytes * 8 / (max(sw.elapsedMilliseconds, 1) / 1000) / 1e6;
        speedResult = '${mbps.toStringAsFixed(1)} Mbps';
        log(LogKind.connection, 'Speed test: $speedResult');
      } catch (e) {
        speedResult = 'ناموفق';
        // ✅ C2: علت واقعی به کاربر نشان داده می‌شود
        speedError = e is DioException
            ? switch (e.type) {
                DioExceptionType.connectionTimeout => 'اتصال به پروکسی محلی (127.0.0.1:$kHttpPort) برقرار نشد',
                DioExceptionType.receiveTimeout => 'دریافت داده بیش از ۴۰ ثانیه طول کشید',
                DioExceptionType.connectionError => 'خطای اتصال: ${e.message ?? 'نامشخص'}',
                DioExceptionType.badResponse => 'پاسخ نامعتبر: HTTP ${e.response?.statusCode}',
                DioExceptionType.cancel => 'لغو شد',
                _ => e.message ?? e.type.name,
              }
            : '$e';
        log(LogKind.connection, 'Speed test failed: $speedError', LogLevel.warn);
      } finally {
        testingSpeed = false;
        notifyListeners();
      }
    }

    // ───────── WARP ─────────
    Future<String?> warpRegister() async {
      if (busy) return null;
      busy = true;
      notifyListeners();
      try {
        warp = await registerWarp(
          proxyPort: connected ? kHttpPort : null,
          preferredEndpoint: warp?.endpoint,
        );
        await saveWarp();
        log(LogKind.system, 'WARP registered (${warp?.addressV4})');
        return null;
      } on WarpException catch (e) {
        log(LogKind.system, 'WARP: ${e.message}', LogLevel.error);
        return e.message;
      } catch (e) {
        log(LogKind.system, 'WARP error: $e', LogLevel.error);
        return 'خطای WARP: $e';
      } finally {
        busy = false;
        notifyListeners();
      }
    }

    Future<void> setWarpOn(bool v) async {
      warpOn = v;
      await saveWarp();
      notifyListeners();
    }

    Future<void> setWarpEndpoint(String ep) async {
      if (warp == null) return;
      warp = warp!.copyWith(endpoint: ep);
      await saveWarp();
      notifyListeners();
    }

    @override
    void dispose() {
      _connectTimeout?.cancel();
      _speedToken?.cancel();
      _dio.close(force: true);
      _proxyDio.close(force: true);
      super.dispose();
    }
  }
