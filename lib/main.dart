// lib/main.dart — ورود اپ ZEUS، ناوبری و منوی کشویی
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/controller.dart';
import 'pages/apps_page.dart';
import 'pages/home_page.dart';
import 'pages/logs_page.dart';
import 'pages/servers_page.dart';
import 'pages/settings_page.dart';
import 'pages/subs_page.dart';
import 'ui/cyber.dart';
import 'ui/theme.dart';
import 'ui/transitions.dart';

const String kAppVersion = '2.5.0';

/// رنگ نوار ناوبری سیستم با تم فعلی هماهنگ می‌شود (هنگام شروع و هر بار تعویض تم)
void _applyChrome() {
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kSurface,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadFxLevel();
  await loadThemeIdx();
  _applyChrome();
  runApp(const ZeusApp());
}

class ZeusApp extends StatelessWidget {
  const ZeusApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: zeusThemeIdx,
        // رنگ‌ها getter هستند؛ با عوض شدن تم، کل درخت با key جدید دوباره ساخته می‌شود
        builder: (_, idx, __) {
          _applyChrome();
          return KeyedSubtree(key: ValueKey(idx), child: _app());
        },
      );

  Widget _app() {
    return MaterialApp(
      title: 'ZEUS VPN',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      // ✅ D1: یک پس‌زمینهٔ متحرک برای کل اپ، پشت Navigator.
      // صفحات شفاف‌اند و ZeusBackground داخل آن‌ها (enabled=false) فقط child را برمی‌گرداند.
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ZeusBackground(
              enabled: true,
              // نوار ناوبری پایین (سه‌دکمه‌ای/ژستی): محتوا بالای آن می‌ماند و پس‌زمینه زیرش ادامه دارد
              child: Builder(builder: (ctx2) {
                final bottom = MediaQuery.viewPaddingOf(ctx2).bottom;
                return Padding(
                  padding: EdgeInsets.only(bottom: bottom),
                  child: MediaQuery.removePadding(context: ctx2, removeBottom: true, child: child!),
                );
              }),
            ),
            // اسکن‌لاین و وینیت CRT روی کل برنامه (ورودی لمس را نمی‌گیرد)
            const CrtOverlay(),
            // ترمینال بوت؛ با لمس رد می‌شود و بعد از چند ثانیه محو می‌شود
            const Positioned.fill(child: BootOverlay(version: kAppVersion)),
          ],
        ),
      ),
      home: const ZeusShell(),
    );
  }

  ThemeData _buildTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = ColorScheme.dark(
      primary: kGreen,
      onPrimary: Colors.black,
      secondary: kBlue,
      surface: kSurface,
      onSurface: kText,
      error: kRed,
    );
    return base.copyWith(
      colorScheme: scheme,
      // ✅ شفاف تا پس‌زمینهٔ ریشه در همهٔ صفحات دیده شود
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: kSurface,
      dividerColor: kBorder,
      textTheme: base.textTheme.apply(bodyColor: kText, displayColor: kText),
      iconTheme: IconThemeData(color: kText),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: kText,
        elevation: 0,
        centerTitle: true,
      ),
      listTileTheme: ListTileThemeData(
        textColor: kText,
        iconColor: kGreen,
        subtitleTextStyle: TextStyle(color: kMuted, fontSize: 11),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kSurface2,
        hintStyle: TextStyle(color: kMuted, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kGreen)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kGreen,
          foregroundColor: Colors.black,
          shape: const BeveledRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(10), bottomRight: Radius.circular(10))),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: kGreen,
          side: BorderSide(color: kBorder),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: const BeveledRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(10), bottomRight: Radius.circular(10))),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: kGreen)),
      dialogTheme: DialogThemeData(
        backgroundColor: kSurface2,
        shape: BeveledRectangleBorder(
          borderRadius: BorderRadius.only(topLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
          side: BorderSide(color: kBorder),
        ),
        titleTextStyle: TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w800),
        contentTextStyle: TextStyle(color: kText, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: kSurface2,
        contentTextStyle: TextStyle(color: kText),
        shape: BeveledRectangleBorder(
          borderRadius: BorderRadius.only(topLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
          side: BorderSide(color: kBorder),
        ),
      ),
      // خط‌های جداکنندهٔ پیش‌فرض سفید بودند و با تم نئونی نمی‌خواندند
      dividerTheme: DividerThemeData(color: kBorder, thickness: 1, space: 1),
      drawerTheme: DrawerThemeData(backgroundColor: kSurface, scrimColor: Color(0xAA000000)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: kGreen),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? kGreen.withValues(alpha: 0.35) : kSurface2,
        ),
        trackOutlineColor: WidgetStatePropertyAll(kBorder),
      ),
      expansionTileTheme: ExpansionTileThemeData(textColor: kText, collapsedTextColor: kText),
    );
  }
}

/// پوستهٔ اصلی: صفحهٔ خانه + منوی کشویی. صفحات دیگر با Navigator باز می‌شوند
/// تا دکمهٔ Back اندروید درست کار کند.
class ZeusShell extends StatefulWidget {
  const ZeusShell({super.key});
  @override
  State<ZeusShell> createState() => _ZeusShellState();
}

class _ZeusShellState extends State<ZeusShell> {
  final c = ZeusController.I;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _navigating = false; // جلوگیری از push دوبل با ضربهٔ سریع

  @override
  void initState() {
    super.initState();
    c.addListener(_syncFx);
    // بعد از تعویض تم، رنگ لهجهٔ پس‌زمینه (که از تم قبلی مانده) دوباره محاسبه شود
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFx());
    c.boot();
  }

  @override
  void dispose() {
    c.removeListener(_syncFx);
    super.dispose();
  }

  /// رنگ و سرعت پس‌زمینهٔ متحرک را با وضعیت واقعی اتصال هماهنگ می‌کند
  void _syncFx() {
    final Color col;
    if (c.connected && c.tunnel == TunnelState.ok) {
      col = kCyan;
    } else if (c.connected && c.tunnel == TunnelState.failed) {
      col = kRed;
    } else if (c.connected || c.connecting || c.conn == ConnState.disconnecting) {
      col = kAmber;
    } else {
      col = kMagenta;
    }
    zeusAccent.value = col;
    zeusActive.value = c.connected && c.tunnel == TunnelState.ok;
  }

  // ───────── navigation ─────────
  Future<void> _push(Widget page) async {
    if (_navigating || !mounted) return;
    _navigating = true;
    // قفل فقط برای ضربهٔ دوبل است. قبلاً تا «بسته‌شدن» صفحهٔ جدید باز می‌ماند و ناوبری تو‌در‌تو
    // (سرورها←اشتراک، تنظیمات←لاگ‌ها) را بی‌صدا نادیده می‌گرفت.
    Future.delayed(const Duration(milliseconds: 500), () => _navigating = false);
    await Navigator.of(context).pushZeus(page);
  }

  /// فقط وقتی route‌ای غیر از خانه روی استک باشد pop می‌کند (محافظ در برابر pop دوبل/ناخواسته)
  void _pop() {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  void _goServers() => _push(ServersPage(onBack: _pop, onGoSubs: _goSubs));
  void _goSubs() => _push(SubsPage(onBack: _pop));
  void _goLogs() => _push(LogsPage(onBack: _pop));
  void _goApps() => _push(AppsPage(onBack: _pop));
  void _goSettings() => _push(SettingsPage(onBack: _pop, onGoLogs: _goLogs, onGoApps: _goApps));

  void _openMenu() => _scaffoldKey.currentState?.openDrawer();

  Future<void> _checkUpdate() async {
    final msg = await c.checkUpdate(manual: true);
    if (!mounted || msg == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _fromMenu(VoidCallback go) {
    // بستن drawer فقط اگر واقعاً باز است (قبلاً pop بی‌قید می‌توانست صفحه را ببندد)
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState!.closeDrawer();
    }
    // بعد از بسته‌شدن drawer ناوبری کن تا دو انیمیشن متناقض هم‌زمان اجرا نشوند
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) go();
    });
  }

  Future<void> _about() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const NeonText('ZEUS VPN', size: 18),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('نسخه $kAppVersion', style: TextStyle(color: kMuted)),
            SizedBox(height: 8),
            Text('هسته: Xray  •  PattNG  •  Cloudflare WARP'),
            SizedBox(height: 8),
            Text('> matrix_hacker_edition --secure --no-logs',
                style: TextStyle(color: kGreen, fontFamily: kMono, fontSize: 11, letterSpacing: 1)),
            SizedBox(height: 8),
            Text('No logs. No limits. Your rules.',
                style: TextStyle(color: kGreen, fontSize: 12, letterSpacing: 1)),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('باشه'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      drawer: _drawer(),
      body: HomePage(
        onGoServers: _goServers,
        onGoSettings: _goSettings,
        onOpenMenu: _openMenu,
      ),
    );
  }

  // ───────── drawer ─────────
  Widget _drawer() {
    return Drawer(
      width: 290,
      shape: BeveledRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(22)),
        side: BorderSide(color: kBorder),
      ),
      child: ListenableBuilder(
        listenable: c,
        builder: (_, __) {
          final sel = c.selected;
          final Color statusColor;
          final String statusText;
          if (c.connected && c.tunnel == TunnelState.ok) {
            statusColor = kGreen;
            statusText = 'متصل';
          } else if (c.connected && c.tunnel == TunnelState.failed) {
            statusColor = kRed;
            statusText = 'تونل خراب';
          } else if (c.connected || c.connecting) {
            statusColor = kAmber;
            statusText = c.connecting ? 'در حال اتصال…' : 'تأیید تونل…';
          } else {
            statusColor = kMuted;
            statusText = 'قطع';
          }
          return SafeArea(
            child: Column(
              children: [
                // ───── header ─────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: kNeonGradient,
                          boxShadow: neonGlow(kGreen, blur: 14, alpha: .5),
                        ),
                        child: const Icon(Icons.bolt, color: Colors.black, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const NeonText('ZEUS VPN', size: 17),
                            Row(
                              children: [
                                PulseDot(color: statusColor, size: 5),
                                const SizedBox(width: 2),
                                Text(statusText, style: TextStyle(color: statusColor, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (sel != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      onTap: () => _fromMenu(_goServers),
                      child: Row(
                        children: [
                          Text(sel.flag, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(sel.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                          Text(sel.pingText, style: TextStyle(color: pingColor(sel.pingMs), fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                const Divider(height: 16),

                // ───── items ─────
                _item(Icons.home_outlined, 'خانه', () => _scaffoldKey.currentState?.closeDrawer()),
                _item(Icons.public, 'سرورها', () => _fromMenu(_goServers),
                    badge: c.nodes.isEmpty ? null : '${c.nodes.length}'),
                _item(Icons.link, 'اشتراک', () => _fromMenu(_goSubs),
                    badge: c.subs.isEmpty ? null : '${c.subs.length}'),
                _item(Icons.settings_outlined, 'تنظیمات', () => _fromMenu(_goSettings)),
                _item(Icons.article_outlined, 'لاگ‌ها', () => _fromMenu(_goLogs),
                    badge: c.logs.isEmpty ? null : '${c.logs.length}'),
                const Divider(height: 16),
                _item(Icons.system_update_alt, 'بررسی به‌روزرسانی', () => _fromMenu(_checkUpdate),
                    badge: c.update == null ? null : 'جدید'),
                _item(Icons.info_outline, 'درباره', () => _fromMenu(_about)),

                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(c.ready ? Icons.check_circle : Icons.error_outline,
                          size: 14, color: c.ready ? kGreen : kRed),
                      const SizedBox(width: 6),
                      Text(c.ready ? 'هسته آماده' : 'هسته آماده نیست',
                          style: TextStyle(color: c.ready ? kMuted : kRed, fontSize: 11)),
                      const Spacer(),
                      Text('v$kAppVersion', style: TextStyle(color: kMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _item(IconData icon, String title, VoidCallback onTap, {String? badge}) {
    return ListTile(
      leading: Icon(icon, color: kGreen),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: badge == null ? null : StatusBadge(badge, color: kGreen),
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }
}
