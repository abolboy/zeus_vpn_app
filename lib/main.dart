  // lib/main.dart — ورود اپ ZEUS، ناوبری و منوی کشویی
  import 'package:flutter/material.dart';
  import 'package:flutter/services.dart';

  import 'core/controller.dart';
  import 'pages/home_page.dart';
  import 'pages/logs_page.dart';
  import 'pages/servers_page.dart';
  import 'pages/settings_page.dart';
  import 'pages/subs_page.dart';
  import 'ui/theme.dart';

  const String kAppVersion = '2.0.0';

  void main() {
    WidgetsFlutterBinding.ensureInitialized();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: kSurface,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    runApp(const ZeusApp());
  }

  class ZeusApp extends StatelessWidget {
    const ZeusApp({super.key});

    @override
    Widget build(BuildContext context) {
      return MaterialApp(
        title: 'ZEUS VPN',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        // راست‌چین کل اپ بدون نیاز به flutter_localizations
        builder: (ctx, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const ZeusShell(),
      );
    }

    ThemeData _buildTheme() {
      final base = ThemeData.dark(useMaterial3: true);
      const scheme = ColorScheme.dark(
        primary: kGreen,
        onPrimary: Colors.black,
        secondary: kBlue,
        surface: kSurface,
        onSurface: kText,
        error: kRed,
      );
      return base.copyWith(
        colorScheme: scheme,
        scaffoldBackgroundColor: kSurface,
        canvasColor: kSurface,
        dividerColor: kBorder,
        textTheme: base.textTheme.apply(bodyColor: kText, displayColor: kText),
        iconTheme: const IconThemeData(color: kText),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: kText,
          elevation: 0,
          centerTitle: true,
        ),
        listTileTheme: const ListTileThemeData(
          textColor: kText,
          iconColor: kGreen,
          subtitleTextStyle: TextStyle(color: kMuted, fontSize: 11),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kSurface2,
          hintStyle: const TextStyle(color: kMuted, fontSize: 13),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kGreen)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kGreen,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kGreen,
            side: const BorderSide(color: kBorder),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: kGreen)),
        dialogTheme: DialogThemeData(
          backgroundColor: kSurface2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          titleTextStyle: const TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w700),
          contentTextStyle: const TextStyle(color: kText, fontSize: 14),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: kSurface2,
          contentTextStyle: const TextStyle(color: kText),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        drawerTheme: const DrawerThemeData(backgroundColor: kSurface, scrimColor: Color(0x99000000)),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: kGreen),
        switchTheme: SwitchThemeData(
          trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? kGreen.withValues(alpha: 0.35) : kSurface2,
          ),
          trackOutlineColor: const WidgetStatePropertyAll(kBorder),
        ),
        expansionTileTheme: const ExpansionTileThemeData(textColor: kText, collapsedTextColor: kText),
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

    @override
    void initState() {
      super.initState();
      c.boot();
    }

    // ───────── navigation ─────────
    Future<void> _push(Widget page) async {
      await Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          transitionsBuilder: (_, anim, __, child) {
            final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curve,
              child: SlideTransition(
                position: Tween(begin: const Offset(-0.06, 0), end: Offset.zero).animate(curve),
                child: child,
              ),
            );
          },
        ),
      );
    }

    void _pop() {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    }

    void _goServers() => _push(ServersPage(onBack: _pop, onGoSubs: _goSubs));
    void _goSubs() => _push(SubsPage(onBack: _pop));
    void _goLogs() => _push(LogsPage(onBack: _pop));
    void _goSettings() => _push(SettingsPage(onBack: _pop, onGoLogs: _goLogs));

    void _openMenu() => _scaffoldKey.currentState?.openDrawer();

    void _fromMenu(VoidCallback go) {
      Navigator.of(context).pop(); // بستن drawer
      go();
    }

    Future<void> _about() async {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ZEUS VPN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('نسخه $kAppVersion', style: const TextStyle(color: kMuted)),
              const SizedBox(height: 8),
              const Text('هسته: Xray  •  PattNG  •  Cloudflare WARP'),
              const SizedBox(height: 8),
              const Text('No logs. No limits. Your rules.', style: TextStyle(color: kGreen, fontSize: 12, letterSpacing: 1)),
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
        backgroundColor: kSurface,
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
        child: ListenableBuilder(
          listenable: c,
          builder: (_, __) {
            final sel = c.selected;
            final statusColor = c.connected ? kGreen : (c.connecting ? kAmber : kMuted);
            final statusText = c.connected ? 'متصل' : (c.connecting ? 'در حال اتصال…' : 'قطع');
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
                            gradient: const LinearGradient(colors: [kGreen, Color(0xFF8AFFC9)]),
                            boxShadow: [BoxShadow(color: kGreen.withValues(alpha: 0.35), blurRadius: 16)],
                          ),
                          child: const Icon(Icons.bolt, color: Colors.black, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ZEUS VPN',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                              Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 6),
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
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                            Text(sel.pingText, style: TextStyle(color: pingColor(sel.pingMs), fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  const Divider(height: 16),

                  // ───── items ─────
                  _item(Icons.home_outlined, 'خانه', () => Navigator.of(context).pop()),
                  _item(Icons.public, 'سرورها', () => _fromMenu(_goServers),
                      badge: c.nodes.isEmpty ? null : '${c.nodes.length}'),
                  _item(Icons.link, 'اشتراک', () => _fromMenu(_goSubs),
                      badge: c.subs.isEmpty ? null : '${c.subs.length}'),
                  _item(Icons.settings_outlined, 'تنظیمات', () => _fromMenu(_goSettings)),
                  _item(Icons.article_outlined, 'لاگ‌ها', () => _fromMenu(_goLogs),
                      badge: c.logs.isEmpty ? null : '${c.logs.length}'),
                  const Divider(height: 16),
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
                        Text('v$kAppVersion', style: const TextStyle(color: kMuted, fontSize: 11)),
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
