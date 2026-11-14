// lib/core/controller.dart — منطق مرکزی ZEUS (اتصال، اشتراک، پینگ حرفه‌ای، تست سرعت، WARP، لاگ)
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
import 'clash_import.dart';
import 'free_servers.dart';
import 'models.dart';
import 'updater.dart';

const String kPingUrl = 'https://www.gstatic.com/generate_204';
const String kSpeedDownUrl = 'https://speed.cloudflare.com/__down?bytes=30000000';
const String kSpeedUpUrl = 'https://speed.cloudflare.com/__up';
const List<String> kIpUrls = [
  'https://api.ipify.org?format=text',
  'https://icanhazip.com',
  'https://ifconfig.me/ip',
];

enum ConnState { disconnected, connecting, connected, disconnecting }

/// وضعیت واقعی تونل بعد از این‌که سرویس VPN بالا آمد
enum TunnelState { idle, checking, ok, failed }

/// فازهای تست سرعت حرفه‌ای (پینگ → دانلود → آپلود → نتیجه)
enum SpeedPhase { idle, ping, download, upload, done, failed }

/// خطای خوانا برای فازهای تست سرعت
class SpeedFail implements Exception {
  final String message;
  const SpeedFail(this.message);
  @override
  String toString() => message;
}

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
  /// شمارندهٔ پیشرفت «پینگ همه» برای نوار پیشرفت
  int pingDone = 0;
  int pingTotal = 0;

  // ── تست سرعت حرفه‌ای ──
  SpeedPhase speedPhase = SpeedPhase.idle;
  double speedProgress = 0; // ۰..۱ در فاز جاری
  double speedTtfbMs = -1; // پینگ سرور تست (میانهٔ ۳ نمونه)
  double speedDownMbps = 0;
  double speedUpMbps = 0; // ۰ یعنی آپلود سنجیده نشد
  double speedLiveMbps = 0; // سرعت لحظه‌ای برای نمایش زنده
  final List<double> speedSamples = []; // نمونه‌های لحظه‌ای برای نمودار زنده
  String speedResult = '';
  /// علت خوانای شکست آخرین تست سرعت (خالی = بدون خطا)
  String speedError = '';
  bool _speedBusy = false;
  Uint8List? _upBuf;

  bool get testingSpeed =>
      speedPhase == SpeedPhase.ping ||
      speedPhase == SpeedPhase.download ||
      speedPhase == SpeedPhase.upload;

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
  bool _stopping = false; // بعد از «قطع» دستی، رویدادهای دیرهنگام هسته نادیده گرفته می‌شوند
  Timer? _stopGrace;
  CancelToken? _speedToken;
  bool _warpAutoTried = false; // چرخش خودکار endpoint فقط یک‌بار در هر اتصال

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

  ConfigBuilder get _builder => ConfigBuilder(
        patt: patt,
        warp: warp,
        warpOn: warpOn,
        warpMtu: settings.warpMtu,
        chainUri: settings.chainUri.isEmpty ? null : settings.chainUri,
      );

  // ───────── boot ─────────
  Future<void> boot() async {
    if (booted) return;
    booted = true;
    final p = await SharedPreferences.getInstance();
    _loadPrefs(p);
    await _seedFreeSubs(p);
    log(LogKind.system, 'ZEUS starting…');
    await _initCore();
    unawaited(_detectRunningTunnel());
    if (subs.isNotEmpty) {
      syncAll().then((_) {
        if (settings.autoConnect && !connected && !connecting) quickConnect();
      });
    } else if (settings.autoConnect && nodes.isNotEmpty) {
      quickConnect();
    }
    // بررسی بی‌صدای نسخهٔ جدید (چند ثانیه بعد، تا شروع اپ کند نشود)
    Future.delayed(const Duration(seconds: 6), () => checkUpdate());
  }

  /// اشتراک‌های داخلی («سرورهای رایگان») را یک‌بار به‌ازای هر آدرس اضافه می‌کند؛
  /// اگر کاربر حذفشان کند دوباره اضافه نمی‌شوند.
  Future<void> _seedFreeSubs(SharedPreferences p) async {
    // اشتراک داخلیِ بازنشسته («سرورهای رایگان» نسخه‌های قبلی) از لیست کاربر پاک می‌شود
    final before0 = subs.length;
    subs.removeWhere((s) => kRetiredFreeSubscriptions.contains(s.url) && !kFreeSubscriptions.contains(s.url));
    if (subs.length != before0) {
      nodes = [];
      selUri = null;
      await _saveSubs();
      await _saveNodes();
      await _saveSel();
      await p.remove('free_seeded_urls');
      log(LogKind.system, 'Retired built-in free subscription removed');
    }
    if (kFreeSubscriptions.isEmpty) return;
    final seeded = (p.getStringList('free_seeded_urls') ?? <String>[]).toSet();
    final before = seeded.length;
    var added = false;
    for (final u in kFreeSubscriptions) {
      if (seeded.contains(u)) continue;
      seeded.add(u);
      if (!subs.any((s) => s.url == u)) {
        subs.add(SubRecord(url: u, name: kFreeSubName));
        added = true;
      }
    }
    if (seeded.length != before) await p.setStringList('free_seeded_urls', seeded.toList());
    if (added) {
      await _saveSubs();
      log(LogKind.system, 'Built-in free subscription added');
    }
  }

  Future<void> _initCore() async {
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
  }

  void _loadPrefs(SharedPreferences p) {
    try {
      final rawSubs = p.getString('subs_v2');
      if (rawSubs != null) {
        subs = (jsonDecode(rawSubs) as List).map(SubRecord.fromJson).whereType<SubRecord>().toList();
      } else {
        subs = (p.getStringList('subs') ?? []).map((u) => SubRecord(url: u)).toList();
      }
    } catch (e) {
      // داده‌ٔ خراب نباید جلوی بالا آمدن اپ را بگیرد
      subs = [];
      log(LogKind.system, 'Subs load error: $e', LogLevel.warn);
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
    // بعد از «قطع» دستی، رویدادهای دیرهنگامِ CONNECTING/CONNECTED از هسته نباید صفحه را دوباره به
    // «در حال اتصال» ببرند (علت رفتار «انگار دوباره وصل می‌شود، بعد خطا می‌دهد»)
    if (_stopping && (st == 'CONNECTED' || st == 'CONNECTING' || st == 'CONNECT')) return;
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
        // ⚠️ سقف زمانی اجباری: اگر هسته روی تونل مرده گیر کند، بدون این timeout
        // وضعیت برای همیشه «checking» می‌ماند و WARP-autofix/failover هرگز اجرا نمی‌شوند.
        final d = await _v2ray
            .getConnectedServerDelay(url: pingUrl)
            .timeout(const Duration(seconds: 8), onTimeout: () => -1);
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
    // ✅ WARP: اگر WARP فعال است و تونل تأیید نشد، به احتمال زیاد endpoint روی این ISP
    // مسدود است؛ یک‌بار به‌طور خودکار endpoint بعدی امتحان و اتصال از نو برقرار می‌شود.
    if (settings.warpAutoFix &&
        warpReady &&
        warp!.isCloudflareRegistered &&
        !_warpAutoTried) {
      _warpAutoTried = true;
      final next = nextWarpEndpoint(warp!.endpoint);
      if (next != warp!.endpoint) {
        warp = warp!.copyWith(endpoint: next);
        await saveWarp();
        log(LogKind.connection, 'WARP endpoint rotated → $next — reconnecting…', LogLevel.warn);
        await disconnect();
        await connect();
      }
    }
    // ✅ Failover: اگر هنوز تونل تأیید نشده، تا ۲ بار سرور بعدیِ سالم‌تر را خودکار امتحان کن
    if (settings.autoFailover && _failoverTries < 2 && gen == _connGen && connected && tunnel == TunnelState.failed) {
      final alt = _nextFailoverNode();
      if (alt != null) {
        _failoverTries++;
        log(LogKind.connection, 'Auto-failover → ${alt.displayName}', LogLevel.warn);
        await selectNode(alt, auto: true);
      }
    }
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
    speedPhase = SpeedPhase.idle;
    speedProgress = 0;
    speedTtfbMs = -1;
    speedDownMbps = speedUpMbps = speedLiveMbps = 0;
    speedSamples.clear();
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
    if (busy) return null;
    if (!ready) {
      await _initCore(); // یک بار دیگر تلاش
      if (!ready) return 'هستهٔ اتصال آماده نیست';
    }
    if (connected || connecting) {
      await disconnect();
      return null;
    }
    _failoverTries = 0;
    _failoverTried.clear();
    return connect();
  }

  Future<String?> connect() async {
    // حالت «فقط WARP»: با فعال بودن WARP و انتخاب کاربر، اتصال مستقیم WARP برقرار می‌شود
    // (بدون سرور). اگر سروری انتخاب نشده باشد هم WARP تنها گزینه است.
    final warpOnly = warpReady && (selUri == null || settings.warpMode == 'only');
    if (selUri == null && !warpReady) return 'اول یک سرور انتخاب کنید';
    busy = true;
    _stopping = false;
    _stopGrace?.cancel();
    _warpAutoTried = false;
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
      if (warpOnly && selUri != null) {
        log(LogKind.connection, 'WARP-only mode: selected server is bypassed');
      }
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
        // برنامه‌های مستثنی از VPN (Per-app routing)
        blockedApps: settings.bypassApps.isEmpty ? null : List<String>.of(settings.bypassApps),
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
    _stopping = true;
    _stopGrace?.cancel();
    _speedToken?.cancel();
    _connGen++;
    busy = true;
    conn = ConnState.disconnecting;
    notifyListeners();
    try {
      await _v2ray.stopV2Ray();
    } catch (e) {
      log(LogKind.core, 'Stop error: $e', LogLevel.warn);
    }
    // چند ثانیه رویدادهای اتصالِ دیرهنگام را نادیده بگیر، بعد دوباره به هسته اعتماد کن
    _stopGrace = Timer(const Duration(seconds: 4), () => _stopping = false);
    conn = ConnState.disconnected;
    _resetTraffic();
    busy = false;
    notifyListeners();
  }

  Future<String?> selectNode(ServerNode n, {bool reconnect = true, bool auto = false}) async {
    if (!auto) {
      _failoverTries = 0;
      _failoverTried.clear();
    }
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
    if (!isSecureSubscriptionUrl(u)) return 'فقط لینک اشتراک HTTPS معتبر پذیرفته می‌شود';
    if (subs.any((s) => s.url == u)) return 'این اشتراک قبلاً اضافه شده';
    subs.add(SubRecord(url: u, name: Uri.tryParse(u)?.host ?? ''));
    await _saveSubs();
    notifyListeners();
    return syncAll();
  }

  /// Adds one share URI directly to the local server list without creating a subscription.
  /// Manual nodes use the M tag and are preserved when subscription feeds refresh.
  Future<String?> addSingleLink(String value) async {
    final uri = value.trim();
    if (uri.isEmpty || !isSupportedLink(uri)) {
      return 'لینک باید یکی از فرمت‌های VLESS، VMess، Trojan، Shadowsocks یا SOCKS باشد';
    }

    late final ServerNode node;
    try {
      node = ServerNode.fromUri(uri, 'M');
      if (node.protocol == '?' || node.host.isEmpty || node.port < 1) {
        return 'ساختار لینک سرور کامل یا معتبر نیست';
      }

      // Parse through the same Xray config builder used for a real connection.
      _builder.build(node.rawUri);
    } catch (error) {
      log(
        LogKind.system,
        'Manual server link rejected (${error.runtimeType})',
        LogLevel.warn,
      );
      return 'این لینک برای هستهٔ فعلی ZEUS معتبر یا پشتیبانی‌شده نیست';
    }

    if (nodes.any((existing) => existing.rawUri == node.rawUri)) {
      return 'این سرور قبلاً به فهرست اضافه شده است';
    }

    nodes.add(node);
    try {
      await _saveNodes();
    } catch (error) {
      nodes.removeWhere((existing) => existing.rawUri == node.rawUri);
      log(
        LogKind.system,
        'Manual server could not be saved: $error',
        LogLevel.error,
      );
      return 'ذخیرهٔ سرور ناموفق بود؛ دوباره تلاش کن';
    }

    notifyListeners();
    log(LogKind.system, 'Manual server added (${node.protocol})');
    return null;
  }

  /// افزودن اشتراک از فهرست «رایگان» با نام دلخواه
  /// بعد از به‌روزرسانی: پینگ همه، و در صورت فعال بودن، حذف سرورهای بی‌پاسخ
  Future<void> _postSyncPipeline() async {
    await pingAll();
    if (settings.autoRemoveDead) await removeDeadNodes();
  }

  Future<String?> addFreeSub(String url, String name) async {
    final u = url.trim();
    if (!isSecureSubscriptionUrl(u)) return 'لینک اشتراک باید HTTPS معتبر باشد';
    if (subs.any((s) => s.url == u)) return 'این اشتراک قبلاً اضافه شده';
    subs.add(SubRecord(url: u, name: name));
    await _saveSubs();
    notifyListeners();
    return syncAll();
  }

  Future<void> removeSub(SubRecord s) async {
    final idx = subs.indexOf(s);
    if (idx < 0) return;
    subs.removeAt(idx);
    nodes.removeWhere((n) => n.subTag == 'S${idx + 1}');
    // برچسب سرورهای اشتراک‌های بعدی یکی کم می‌شود تا با ترتیب جدید هم‌خوان بماند
    for (final n in nodes) {
      final k = int.tryParse(n.subTag.substring(1));
      if (k != null && k > idx + 1) n.subTag = 'S${k - 1}';
    }
    // اگر سرورِ انتخاب‌شده متعلق به همین اشتراک بود و اتصالی هم برقرار نیست،
    // selUri نباید به سروری حذف‌شده اشاره کند (وگرنه «اتصال» به سرور حذف‌شده انجام می‌شود)
    if (selUri != null &&
        !nodes.any((n) => n.rawUri == selUri) &&
        !connected &&
        !connecting) {
      selUri = null;
      await _saveSel();
    }
    await _saveSubs();
    await _saveNodes();
    notifyListeners();
    if (subs.isNotEmpty) syncAll();
  }

  Future<_SubFetch> _fetchSub(String url) async {
    if (!isSecureSubscriptionUrl(url)) {
      throw const FormatException('Only HTTPS subscription URLs are allowed');
    }
    final r = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: false,
        headers: {'User-Agent': 'v2rayNG/1.8.0'},
      ),
    );
    if (r.realUri.scheme.toLowerCase() != 'https') {
      throw const FormatException('Subscription response did not remain on HTTPS');
    }
    final body = r.data ?? '';
    final meta = parseSubMeta(body, (k) => r.headers.value(k));
    // اشتراک فرمت Clash / Clash.Meta (YAML با کلید proxies:)
    if (looksLikeClash(body)) {
      final c = parseClash(body);
      if (c.unsupported > 0) {
        log(LogKind.system, 'Clash subscription: ${c.unsupported} proxy type(s) not supported by this core were skipped', LogLevel.warn);
      }
      return _SubFetch(c.links, meta);
    }
    return _SubFetch(parseSubscriptionBody(body), meta);
  }

  /// متن اعلان‌های فعال (از هدر/توضیح اشتراک‌ها)
  List<String> get announcements => [
        for (final s in subs)
          if (s.announce.trim().isNotEmpty) s.announce.trim(),
      ];

  /// همهٔ لینک‌های فعلی در یک متن (هر خط یک سرور) برای اشتراک‌گذاری
  String exportLinks() => nodes.map((n) => n.rawUri).join('\n');

  Future<String?> syncAll() async {
    if (subs.isEmpty || loadingSubs) return null;
    final gen = ++_syncGen;
    // اگر هنگام دریافت، اشتراکی اضافه/حذف شد، ایندکس‌ها به‌هم نریزد
    final snapshot = List<SubRecord>.of(subs);
    loadingSubs = true;
    notifyListeners();
    log(LogKind.system, 'Syncing ${snapshot.length} subscription(s)');

    try {
      final results = await Future.wait(snapshot.map((s) async {
        try {
          final f = await _fetchSub(s.url);
          final list = f.links;
          s.lastOk = list.isNotEmpty;
          s.lastSync = DateTime.now();
          s.nodeCount = list.length;
          s.used = f.meta.used;
          s.total = f.meta.total;
          s.expire = f.meta.expire;
          s.announce = f.meta.announce;
          if (s.name.isEmpty && f.meta.title.isNotEmpty) s.name = f.meta.title;
          return list;
        } catch (e) {
          s.lastOk = false;
          log(LogKind.system, 'Sub failed (${s.name}): $e', LogLevel.warn);
          return <String>[];
        }
      }));
      if (gen != _syncGen) return null;

      final fresh = <ServerNode>[];
      for (var i = 0; i < snapshot.length; i++) {
        final idx = subs.indexOf(snapshot[i]);
        if (idx < 0) continue; // وسط دریافت حذف شده
        for (final uri in results[i]) {
          fresh.add(ServerNode.fromUri(uri, 'S${idx + 1}'));
        }
      }
      loadingSubs = false;
      await _saveSubs();

      if (fresh.isEmpty) {
        notifyListeners();
        return 'هیچ سروری دریافت نشد؛ لیست قبلی حفظ شد';
      }
      // Keep local single-link imports alongside subscription-provided servers.
      // A feed refresh must never silently remove a manually added server.
      final old = {for (final n in nodes) n.rawUri: n};
      final manual = nodes.where((n) => n.subTag == 'M').toList();
      for (final n in fresh) {
        final o = old[n.rawUri];
        if (o != null) {
          n.pingMs = o.pingMs;
          n.jitterMs = o.jitterMs;
          n.lossPct = o.lossPct;
          n.viaTcp = o.viaTcp;
          n.favorite = o.favorite;
        }
      }
      final freshUris = fresh.map((n) => n.rawUri).toSet();
      for (final n in manual) {
        if (freshUris.add(n.rawUri)) fresh.add(n);
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
      if (settings.autoTestAfterSync) unawaited(_postSyncPipeline());
      return failed > 0 ? '$failed اشتراک دریافت نشد' : null;
    } finally {
      // هر خطای پیش‌بینی‌نشده‌ای نباید loadingSubs را برای همیشه true نگه دارد
      if (loadingSubs) {
        loadingSubs = false;
        notifyListeners();
      }
    }
  }

  // ───────── ping (چندنمونه‌ای حرفه‌ای) ─────────
  int _realFailLogged = 0;

  /// آدرس تست اتصال (قابل‌تنظیم؛ پیش‌فرض gstatic)
  String get pingUrl => settings.pingUrl.trim().startsWith('http') ? settings.pingUrl.trim() : kPingUrl;

  // ───────── تشخیص VPN فعال و راهنمای پینگ ─────────
  bool vpnInterfaceActive = false; // رابط tun/ppp روی گوشی (VPN خودمان یا برنامهٔ دیگر)
  String? pingHint; // دلیل محتمل وقتی هیچ سروری پینگ نداد

  Future<void> _detectVpnInterface() async {
    try {
      final list = await NetworkInterface.list(includeLoopback: false, includeLinkLocal: false);
      vpnInterfaceActive = list.any((i) {
        final n = i.name.toLowerCase();
        return n.startsWith('tun') || n.startsWith('ppp') || n.startsWith('wg') || n.startsWith('tap');
      });
    } catch (_) {
      vpnInterfaceActive = false;
    }
  }

  // ───────── تعویض خودکار سرور (Failover) ─────────
  int _failoverTries = 0;
  final Set<String> _failoverTried = <String>{};

  ServerNode? _nextFailoverNode() {
    if (selUri != null) _failoverTried.add(selUri!);
    final cands = nodes.where((n) => !_failoverTried.contains(n.rawUri)).toList();
    if (cands.isEmpty) return null;
    final good = cands.where((n) => n.pingMs >= 0).toList()..sort((a, b) => a.pingMs.compareTo(b.pingMs));
    if (good.isNotEmpty) return good.first;
    final untested = cands.where((n) => n.pingMs == -2).toList();
    return untested.isEmpty ? null : untested.first;
  }

  /// اگر برنامه بعد از راه‌اندازی دوباره می‌بیند که تونلِ خودش هنوز زنده است (مثلاً بعد از بستن برنامه
  /// از لیست اخیر)، وضعیت را هماهنگ می‌کند تا دکمهٔ قطع/پینگ درست کار کند.
  Future<void> _detectRunningTunnel() async {
    if (connected || connecting) return;
    try {
      final d = await _v2ray.getConnectedServerDelay(url: pingUrl).timeout(const Duration(seconds: 4));
      if (d >= 0 && !connected && !connecting) {
        conn = ConnState.connected;
        connectedAt = DateTime.now();
        log(LogKind.connection, 'Existing tunnel detected (${d}ms) — state synced');
        final gen = ++_connGen;
        notifyListeners();
        unawaited(_verifyTunnel(gen));
      }
    } catch (_) {}
  }

  // ───────── به‌روزرسانی برنامه ─────────
  UpdateInfo? update;
  bool checkingUpdate = false;

  /// نسخهٔ جدید را از GitHub می‌پرسد. پیام برای کاربر برمی‌گرداند (null = فقط بی‌صدا انجام شد).
  Future<String?> checkUpdate({bool manual = false}) async {
    if (checkingUpdate) return null;
    if (kBuildNumber <= 0) return manual ? 'بررسی به‌روزرسانی فقط در نسخهٔ ساخته‌شده توسط CI فعال است' : null;
    checkingUpdate = true;
    notifyListeners();
    try {
      update = await checkForUpdate(_dio);
      if (update != null) return manual ? 'نسخهٔ جدید آماده است (بیلد ${update!.build})' : null;
      return manual ? 'نسخهٔ شما به‌روز است' : null;
    } catch (e) {
      log(LogKind.system, 'Update check failed: $e', LogLevel.warn);
      return manual ? 'بررسی به‌روزرسانی ناموفق بود' : null;
    } finally {
      checkingUpdate = false;
      notifyListeners();
    }
  }

  // ───────── اتصال هوشمند ─────────
  /// اگر پینگی نیست «پینگ همه» می‌زند، سریع‌ترین سرور را انتخاب می‌کند و وصل می‌شود.
  /// پیام اطلاع/خطا برمی‌گرداند؛ null یعنی موفق.
  Future<String?> quickConnect() async {
    if (busy || pinging) return null;
    _failoverTries = 0;
    _failoverTried.clear();
    if (nodes.isEmpty) return 'هنوز سروری ندارید؛ از منو «اشتراک» را اضافه کنید';
    if (nodes.every((n) => n.pingMs < 0)) await pingAll();
    final best = bestNode();
    if (best == null) return 'هیچ سروری پاسخ نداد؛ اینترنت را بررسی کنید';
    if (connected && selUri == best.rawUri) return 'همین حالا به سریع‌ترین سرور وصل هستید';
    if (connected || connecting) return selectNode(best); // سرور را عوض و دوباره وصل می‌کند
    await selectNode(best, reconnect: false);
    return connect();
  }

  // ───────── پشتیبان‌گیری / بازیابی ─────────
  /// اشتراک‌ها و تنظیمات PattNG در یک متن (برای کپی و انتقال به گوشی دیگر)
  String exportBackup() {
    final m = {
      'v': 1,
      'subs': [for (final s in subs) {'u': s.url, 'n': s.name}],
      'patt': patt.toJson(),
    };
    return 'ZEUS-BACKUP:${base64Url.encode(utf8.encode(jsonEncode(m)))}';
  }

  /// null = موفق؛ در غیر این صورت پیام خطا
  Future<String?> importBackup(String text) async {
    final t = text.trim();
    if (!t.startsWith('ZEUS-BACKUP:')) return 'متن پشتیبان معتبر نیست';
    try {
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(t.substring('ZEUS-BACKUP:'.length))))) as Map;
      for (final e in (j['subs'] as List? ?? const [])) {
        if (e is! Map) continue;
        final u = (e['u'] ?? '').toString();
        if (!u.startsWith('http') || subs.any((s) => s.url == u)) continue;
        subs.add(SubRecord(url: u, name: (e['n'] ?? '').toString()));
      }
      if (j['patt'] is Map) {
        patt.loadJson(j['patt'] as Map);
        await savePatt();
      }
      await _saveSubs();
      notifyListeners();
      if (subs.isNotEmpty) await syncAll();
      return null;
    } catch (e) {
      log(LogKind.system, 'Backup import failed: $e', LogLevel.warn);
      return 'پشتیبان خراب است یا قابل خواندن نیست';
    }
  }

  /// پینگ واقعی از طریق هستهٔ Xray. هستهٔ بومی درخواست‌ها را پشت‌سرهم اجرا می‌کند؛ اگر یک سرور
  /// گیر کند بقیه منتظر می‌مانند، پس برای هر سرور سقف زمانی می‌گذاریم تا لیست به‌خطا/قفل نیفتد.
  Future<int> _realDelay(ServerNode n) async {
    final cfg = _builder.buildForPing(n.rawUri);
    final ms = await _v2ray
        .getServerDelay(config: jsonEncode(cfg), url: pingUrl)
        .timeout(const Duration(seconds: 12), onTimeout: () => -2);
    if (ms < 0 && _realFailLogged < 8) {
      _realFailLogged++;
      log(LogKind.core, 'Real delay failed: ${n.displayName} (${n.host}:${n.port}) → ${ms == -2 ? 'timeout' : 'core returned $ms'}',
          LogLevel.warn);
    }
    return ms;
  }

  Future<int> _tcpDelay(ServerNode n) async {
    if (n.host.isEmpty || n.port == 0) {
      log(LogKind.system, 'TCP ping skipped: no host/port parsed for ${n.displayName}', LogLevel.warn);
      return -1;
    }
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(n.host, n.port, timeout: const Duration(seconds: 3));
      s.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  /// سه نمونهٔ TCP → میانه (پینگ پایدارتر از تک‌نمونه) + جیتر (میانگین فاصله از میانه)
  /// + درصد نمونه‌های ناموفق (شبیه packet-loss).
  Future<void> _tcpProbe(ServerNode n) async {
    final samples = <int>[];
    var fails = 0;
    for (var i = 0; i < 3; i++) {
      final ms = await _tcpDelay(n);
      if (ms >= 0) {
        samples.add(ms);
      } else {
        fails++;
      }
      if (i < 2) await Future.delayed(const Duration(milliseconds: 120));
    }
    if (samples.isEmpty) {
      n.pingMs = -1;
      n.jitterMs = 0;
      n.lossPct = 100;
      return;
    }
    samples.sort();
    final med = samples[samples.length ~/ 2];
    final dev = samples.map((s) => (s - med).abs()).reduce((a, b) => a + b) / samples.length;
    n.pingMs = med;
    n.jitterMs = dev.round();
    n.lossPct = (fails * 100) ~/ 3;
  }

  Future<void> pingOne(ServerNode n) async {
    if (pingingUris.contains(n.rawUri)) return;
    pingingUris.add(n.rawUri);
    notifyListeners();
    try {
      if (connected && n.rawUri == selUri) {
        // سرور فعال را از داخل تونل واقعی بسنج (TCP به خودِ سرور از داخل TUN timeout می‌دهد)
        // ⚠️ سقف زمانی: بدون آن، اگر هسته جواب ندهد «سنجش…» برای همیشه می‌ماند
        // و pingAll/quickConnect چون pinging=true است قفل می‌شود.
        final ms = await _v2ray
            .getConnectedServerDelay(url: pingUrl)
            .timeout(const Duration(seconds: 8), onTimeout: () => -1);
        n.pingMs = ms < 0 ? -1 : ms;
        n.jitterMs = 0;
        n.lossPct = 0;
      } else if (connected || connecting || settings.delayMode == 1) {
        await _tcpProbe(n);
      } else {
        final ms = await _realDelay(n);
        if (ms >= 0) {
          n.pingMs = ms;
          n.jitterMs = 0;
          n.lossPct = 0;
          n.viaTcp = false;
        } else {
          // پینگ هسته جواب نداد: حداقل دسترسی‌پذیری TCP را بسنج تا «timeout» کاذب نشان داده نشود
          await _tcpProbe(n);
          n.viaTcp = n.pingMs >= 0;
        }
      }
    } catch (e) {
      if (_realFailLogged < 8) {
        _realFailLogged++;
        log(LogKind.core, 'Ping error: ${n.displayName} → $e', LogLevel.warn);
      }
      n.pingMs = -1;
      n.jitterMs = 0;
      n.lossPct = 100;
    } finally {
      pingingUris.remove(n.rawUri);
      notifyListeners();
    }
  }

  Future<void> pingAll() async {
    if (pinging || nodes.isEmpty) return;
    pinging = true;
    pingDone = 0;
    pingTotal = nodes.length;
    _realFailLogged = 0;
    pingHint = null;
    await _detectVpnInterface();
    notifyListeners();
    try {
      final queue = List<ServerNode>.from(nodes);
      // حالت «واقعی» سنگین‌تر است (هر سرور یک نمونهٔ Xray می‌سازد)؛ همزمانی کمتر
      final base = settings.pingConcurrency.clamp(2, 16).toInt();
      final workers = (!connected && !connecting && settings.delayMode == 0) ? min(base, 4) : base;
      Future<void> worker() async {
        while (queue.isNotEmpty) {
          await pingOne(queue.removeAt(0));
          pingDone++;
        }
      }
      await Future.wait(List.generate(workers, (_) => worker()));
      await _saveNodes();
      if (nodes.isNotEmpty && nodes.every((n) => n.pingMs < 0)) {
        pingHint = (vpnInterfaceActive && !connected)
            ? 'یک VPN روی گوشی فعال است (شاید اتصال قبلی ZEUS یا برنامهٔ دیگر)؛ آن را قطع کنید و دوباره پینگ بگیرید'
            : 'هیچ سروری پاسخ نداد؛ اینترنت/فیلترینگ را بررسی کنید و اگر لازم شد روش پینگ را روی TCP بگذارید';
        log(LogKind.core, 'All pings failed. vpnInterface=$vpnInterfaceActive connected=$connected', LogLevel.warn);
      }
    } finally {
      pinging = false;
      notifyListeners();
    }
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

  static final RegExp _ipRe = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$|^(?=.*:)[0-9a-fA-F:.]{3,45}$');

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
    if (!connected || _speedBusy) return;
    _speedBusy = true;
    speedPhase = SpeedPhase.ping;
    speedProgress = 0;
    speedTtfbMs = -1;
    speedDownMbps = 0;
    speedUpMbps = 0;
    speedLiveMbps = 0;
    speedSamples.clear();
    speedResult = '';
    speedError = '';
    _speedToken = CancelToken();
    notifyListeners();
    final gen = _connGen;
    try {
      // فاز ۱ — پینگ سرور تست (میانهٔ ۳ نمونه TTFB)
      speedTtfbMs = await _measureTtfb();
      if (gen != _connGen) return;

      // فاز ۲ — دانلود استریمی (بدون timeout سقف ثابت؛ پنجرهٔ ۱۲ ثانیه‌ای با گرم‌کردن)
      speedPhase = SpeedPhase.download;
      speedProgress = 0;
      speedLiveMbps = 0;
      notifyListeners();
      speedDownMbps = await _downloadTest();
      if (gen != _connGen) return;
      if (speedDownMbps <= 0) {
        throw const SpeedFail('دریافت داده از سرور تست ممکن نشد؛ اتصال یا DNS را بررسی کنید');
      }

      // فاز ۳ — آپلود (شکستش غیرمرگبار است؛ فقط دانلود نمایش داده می‌شود)
      speedPhase = SpeedPhase.upload;
      speedProgress = 0;
      speedLiveMbps = 0;
      notifyListeners();
      try {
        speedUpMbps = await _uploadTest();
      } catch (e) {
        speedUpMbps = 0;
        log(LogKind.connection, 'Upload phase skipped: $e', LogLevel.warn);
      }
      if (gen != _connGen) return;

      speedPhase = SpeedPhase.done;
      speedProgress = 1;
      speedLiveMbps = 0;
      String f(double v) => v.toStringAsFixed(v >= 100 ? 0 : 1);
      speedResult =
          '↓ ${f(speedDownMbps)}${speedUpMbps > 0 ? '  ·  ↑ ${f(speedUpMbps)}' : ''} Mbps';
      log(LogKind.connection,
          'Speed: ↓${f(speedDownMbps)} ↑${f(speedUpMbps)} Mbps · ping ${speedTtfbMs.round()}ms');
    } on SpeedFail catch (e) {
      if (gen != _connGen) return;
      speedPhase = SpeedPhase.failed;
      speedError = e.message;
      log(LogKind.connection, 'Speed test failed: ${e.message}', LogLevel.warn);
    } on DioException catch (e) {
      if (gen != _connGen) return;
      speedPhase = SpeedPhase.failed;
      speedError = switch (e.type) {
        DioExceptionType.cancel => 'تست لغو شد',
        DioExceptionType.connectionTimeout => 'اتصال به پروکسی محلی (127.0.0.1:$kHttpPort) برقرار نشد؛ یک‌بار قطع/وصل کنید',
        DioExceptionType.receiveTimeout => 'پاسخی از سرور تست دریافت نشد',
        DioExceptionType.connectionError => 'خطای اتصال: ${e.message ?? 'نامشخص'}',
        DioExceptionType.badResponse => 'پاسخ نامعتبر: HTTP ${e.response?.statusCode}',
        _ => e.message ?? e.type.name,
      };
      log(LogKind.connection, 'Speed test failed: $speedError', LogLevel.warn);
    } catch (e) {
      if (gen != _connGen) return;
      speedPhase = SpeedPhase.failed;
      speedError = '$e';
      log(LogKind.connection, 'Speed test failed: $e', LogLevel.warn);
    } finally {
      if (speedPhase == SpeedPhase.ping ||
          speedPhase == SpeedPhase.download ||
          speedPhase == SpeedPhase.upload) {
        speedPhase = SpeedPhase.failed;
      }
      _speedBusy = false;
      notifyListeners();
    }
  }

  /// لغو تست سرعت در حال اجرا
  void cancelSpeedTest() => _speedToken?.cancel();

  /// نمرهٔ کیفیت بر اساس سرعت دانلود
  String get speedGrade {
    final v = speedDownMbps;
    if (v <= 0) return '';
    if (v >= 30) return 'عالی';
    if (v >= 10) return 'خوب';
    if (v >= 4) return 'متوسط';
    return 'ضعیف';
  }

  /// پروکسی محلی؛ اگر پاسخگو نبود، مستقیم — وقتی VPN روشن است، ترافیک مستقیم هم
  /// از TUN (و در نتیجه تونل) عبور می‌کند.
  Future<T> _viaTunnel<T>(Future<T> Function(Dio dio) run) async {
    try {
      return await run(_proxyDio);
    } on DioException catch (e) {
      final proxyDead =
          e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError;
      if (!proxyDead) rethrow;
      log(LogKind.connection, 'Local proxy unreachable — retrying direct (still inside TUN)', LogLevel.warn);
      return run(_dio);
    }
  }

  /// میانهٔ ۳ نمونهٔ TTFB روی endpoint تست
  Future<double> _measureTtfb() async {
    final samples = <double>[];
    for (var i = 0; i < 3; i++) {
      try {
        final sw = Stopwatch()..start();
        await _proxyDio.get<List<int>>(
          'https://speed.cloudflare.com/__down?bytes=1',
          options: Options(responseType: ResponseType.bytes),
          cancelToken: _speedToken,
        );
        sw.stop();
        samples.add(sw.elapsedMilliseconds.toDouble());
      } catch (_) {
        // نمونهٔ ناموفق نادیده گرفته می‌شود
      }
    }
    if (samples.isEmpty) return -1;
    samples.sort();
    return samples[samples.length ~/ 2];
  }

  static const int _kDownWindowMs = 12000;
  static const int _kUpWindowMs = 10000;

  /// دانلود استریمی: بدون بافر کامل در حافظه؛ ۰٫۸ ثانیهٔ اول گرم‌کردن است و کنار گذاشته
  /// می‌شود، نمونه‌های لحظه‌ای هر ۰٫۵ ثانیه برای نمودار زنده ثبت و با CancelToken
  /// بعد از پنجرهٔ ۱۲ ثانیه‌ای قطع می‌شود (پس روی اینترنت کند هم «ناموفق» نمی‌دهد).
  /// هر فاز توکن مخصوص خودش را دارد؛ لغوِ کاربر (`_speedToken`) به آن منتقل می‌شود.
  /// قبلاً تایمر ۱۲ ثانیه‌ایِ دانلود همان توکن مشترک را لغو می‌کرد و آپلود همیشه فوراً لغو می‌شد.
  CancelToken _phaseToken() {
    final t = CancelToken();
    _speedToken?.whenCancel.then((_) {
      if (!t.isCancelled) t.cancel();
    });
    return t;
  }

  Future<double> _downloadTest() {
    return _viaTunnel<double>((dio) async {
      final token = _phaseToken();
      final sw = Stopwatch()..start();
      var bytes = 0;
      var warmed = false;
      var warmupMs = 0, warmupBytes = 0;
      var lastSampleMs = 0, sampleBytes = 0;
      var stopped = false;
      final timer = Timer(const Duration(milliseconds: _kDownWindowMs), () {
        stopped = true;
        if (!token.isCancelled) token.cancel();
      });
      try {
        final r = await dio.get<ResponseBody>(
          kSpeedDownUrl,
          options: Options(
            responseType: ResponseType.stream,
            headers: {'Accept-Encoding': 'identity'},
          ),
          cancelToken: token,
        );
        await for (final chunk in r.data!.stream) {
          bytes += chunk.length;
          final t = sw.elapsedMilliseconds;
          if (!warmed && t >= 800) {
            warmed = true;
            warmupMs = t;
            warmupBytes = bytes;
            lastSampleMs = t;
          }
          if (warmed) {
            sampleBytes += chunk.length;
            if (t - lastSampleMs >= 500) {
              speedLiveMbps = sampleBytes * 8 / ((t - lastSampleMs) / 1000) / 1e6;
              speedSamples.add(speedLiveMbps);
              if (speedSamples.length > 64) speedSamples.removeAt(0);
              speedDownMbps = (bytes - warmupBytes) * 8 / ((t - warmupMs) / 1000) / 1e6;
              sampleBytes = 0;
              lastSampleMs = t;
              speedProgress = min(1.0, t / _kDownWindowMs);
              notifyListeners();
            }
          }
          if (stopped) break;
        }
      } on DioException catch (e) {
        if (!stopped || e.type != DioExceptionType.cancel) rethrow;
      } finally {
        timer.cancel();
      }
      sw.stop();
      final durMs = sw.elapsedMilliseconds - warmupMs;
      if (warmed && durMs > 1500 && bytes > warmupBytes) {
        return (bytes - warmupBytes) * 8 / (durMs / 1000) / 1e6;
      }
      if (bytes > 0 && sw.elapsedMilliseconds > 0) {
        return bytes * 8 / (sw.elapsedMilliseconds / 1000) / 1e6;
      }
      return 0;
    });
  }

  Uint8List _makeUploadBuffer() {
    final rnd = Random();
    final b = Uint8List(6 * 1024 * 1024);
    for (var i = 0; i < b.length; i++) {
      b[i] = rnd.nextInt(256);
    }
    return b;
  }

  /// آپلود ۶ مگابایت تصادفی با پنجرهٔ ۱۰ ثانیه‌ای؛ سرعت از onSendProgress حساب می‌شود.
  Future<double> _uploadTest() {
    return _viaTunnel<double>((dio) async {
      final token = _phaseToken();
      _upBuf ??= _makeUploadBuffer();
      final sw = Stopwatch()..start();
      var sent = 0;
      var warmed = false;
      var warmupMs = 0, warmupBytes = 0;
      var lastSampleMs = 0, lastCount = 0;
      var stopped = false;
      final timer = Timer(const Duration(milliseconds: _kUpWindowMs), () {
        stopped = true;
        if (!token.isCancelled) token.cancel();
      });
      try {
        await dio.post<void>(
          kSpeedUpUrl,
          data: _upBuf,
          options: Options(headers: {'Content-Type': 'application/octet-stream'}),
          cancelToken: token,
          onSendProgress: (count, _) {
            sent = count;
            final t = sw.elapsedMilliseconds;
            if (!warmed && t >= 600) {
              warmed = true;
              warmupMs = t;
              warmupBytes = count;
              lastSampleMs = t;
              lastCount = count;
            }
            if (warmed && t - lastSampleMs >= 500) {
              final delta = count - lastCount;
              if (delta > 0) {
                speedLiveMbps = delta * 8 / ((t - lastSampleMs) / 1000) / 1e6;
                speedSamples.add(speedLiveMbps);
                if (speedSamples.length > 64) speedSamples.removeAt(0);
                speedUpMbps = (count - warmupBytes) * 8 / ((t - warmupMs) / 1000) / 1e6;
                speedProgress = min(1.0, t / _kUpWindowMs);
                notifyListeners();
              }
              lastSampleMs = t;
              lastCount = count;
            }
          },
        );
      } on DioException catch (e) {
        if (!stopped || e.type != DioExceptionType.cancel) rethrow;
      } finally {
        timer.cancel();
      }
      sw.stop();
      final durMs = sw.elapsedMilliseconds - warmupMs;
      if (warmed && durMs > 1500 && sent > warmupBytes) {
        return (sent - warmupBytes) * 8 / (durMs / 1000) / 1e6;
      }
      if (sent > 0 && sw.elapsedMilliseconds > 0) {
        return sent * 8 / (sw.elapsedMilliseconds / 1000) / 1e6;
      }
      return 0;
    });
  }

  // ───────── WARP ─────────
  Future<String?> warpRegister() async {
    if (busy) return null;
    busy = true;
    notifyListeners();
    try {
      WarpConfig? cfg;
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          cfg = await registerWarp(
            proxyPort: connected ? kHttpPort : null,
            preferredEndpoint:
                warp?.isCloudflareRegistered == true ? warp!.endpoint : null,
          );
          break;
        } on WarpException catch (e) {
          // خطاهای شبکه‌ای (نه رد شدن توسط سرور) یک‌بار دیگر با فاصلهٔ کوتاه تلاش می‌شوند
          if (attempt == 1 && e.statusCode == null) {
            log(LogKind.system, 'WARP register retry: ${e.message}', LogLevel.warn);
            await Future.delayed(const Duration(milliseconds: 900));
            continue;
          }
          rethrow;
        }
      }
      if (cfg == null) return 'ثبت‌نام WARP ناموفق بود';
      warp = cfg;
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

  /// کانفیگ WireGuard (فرمت wgcf) را به‌جای ثبت‌نام خودکار وارد می‌کند. null = موفق
  Future<String?> importWarpConf(String text) async {
    try {
      final imported = parseWireGuardConf(text);
      warp = imported;
      warpOn = true;
      if (imported.interfaceMtu != null &&
          const [1280, 1380, 1420].contains(imported.interfaceMtu)) {
        settings.warpMtu = imported.interfaceMtu!;
        await saveSettings();
      }
      await saveWarp();
      log(LogKind.system, 'WireGuard profile imported (${warp?.addressV4})');
      notifyListeners();
      return null;
    } on FormatException catch (e) {
      return e.message;
    } catch (_) {
      return 'کانفیگ قابل خواندن نیست';
    }
  }

  /// سرور واسطهٔ زنجیره (رشتهٔ خالی = غیرفعال)
  Future<void> setChain(String uri) async {
    settings.chainUri = uri;
    await saveSettings();
    notifyListeners();
  }

  /// تعداد سرورهای بی‌پاسخ (پینگ‌شده و timeout) که حذف‌شدنی‌اند؛ علاقه‌مندی‌ها و سرور انتخابی حفظ می‌شوند
  int get deadCount => nodes.where((n) => n.pingMs == -1 && !n.favorite && n.rawUri != selUri).length;

  Future<int> removeDeadNodes() async {
    final before = nodes.length;
    nodes.removeWhere((n) => n.pingMs == -1 && !n.favorite && n.rawUri != selUri);
    final removed = before - nodes.length;
    if (removed > 0) {
      await _saveNodes();
      notifyListeners();
    }
    return removed;
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

  Future<void> setWarpMode(String m) async {
    settings.warpMode = m == 'only' ? 'only' : 'chain';
    await saveSettings();
    notifyListeners();
  }

  Future<void> setWarpMtu(int v) async {
    settings.warpMtu = const [1280, 1380, 1420].contains(v) ? v : 1280;
    await saveSettings();
    notifyListeners();
  }

  Future<void> setWarpAutoFix(bool v) async {
    settings.warpAutoFix = v;
    await saveSettings();
    notifyListeners();
  }

  @override
  void dispose() {
    _connectTimeout?.cancel();
    _stopGrace?.cancel();
    _speedToken?.cancel();
    _dio.close(force: true);
    _proxyDio.close(force: true);
    super.dispose();
  }
}

class _SubFetch {
  final List<String> links;
  final SubMeta meta;
  const _SubFetch(this.links, this.meta);
}
