// lib/pages/apps_page.dart — برنامه‌های مستثنی از VPN (Per-app routing)
//
// برنامه‌هایی که اینجا تیک می‌خورند ترافیکشان از تونل عبور نمی‌کند (مستقیم می‌روند).
// تغییر فقط در اتصال بعدی اعمال می‌شود.
import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';

import '../core/controller.dart';
import '../ui/theme.dart';

class AppsPage extends StatefulWidget {
  final VoidCallback onBack;
  const AppsPage({super.key, required this.onBack});
  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  final c = ZeusController.I;
  final _search = TextEditingController();
  List<AppInfo> _apps = const [];
  bool _loading = true;
  bool _system = false;
  String? _error;
  bool _hinted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await InstalledApps.getInstalledApps(excludeSystemApps: !_system, withIcon: true);
      if (!mounted) return;
      setState(() {
        _apps = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'خواندن فهرست برنامه‌ها ممکن نشد';
        _loading = false;
      });
    }
  }

  Set<String> get _selected => c.settings.bypassApps.toSet();

  void _toggle(String pkg) {
    final cur = c.settings.bypassApps;
    if (cur.contains(pkg)) {
      cur.remove(pkg);
    } else {
      cur.add(pkg);
    }
    c.saveSettings();
    c.refresh();
    setState(() {});
    if ((c.connected || c.connecting) && !_hinted) {
      _hinted = true;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تغییر در اتصال بعدی اعمال می‌شود')));
    }
  }

  List<AppInfo> get _visible {
    final q = _search.text.trim().toLowerCase();
    final sel = _selected;
    final list = _apps.where((a) => q.isEmpty || a.name.toLowerCase().contains(q) || a.packageName.toLowerCase().contains(q)).toList();
    // برنامه‌های انتخاب‌شده بالا (ترتیب نام حفظ می‌شود)
    return [...list.where((a) => sel.contains(a.packageName)), ...list.where((a) => !sel.contains(a.packageName))];
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    final list = _visible;
    return ZeusBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: ZeusHeader(
          title: 'برنامه‌های مستثنی',
          leading: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: widget.onBack),
          actions: [
            IconButton(
              tooltip: _system ? 'پنهان کردن برنامه‌های سیستمی' : 'نمایش برنامه‌های سیستمی',
              icon: Icon(_system ? Icons.visibility : Icons.visibility_off_outlined),
              onPressed: () {
                _system = !_system;
                _load();
              },
            ),
            IconButton(
              tooltip: 'پاک کردن انتخاب‌ها',
              icon: const Icon(Icons.clear_all),
              onPressed: sel.isEmpty
                  ? null
                  : () {
                      c.settings.bypassApps.clear();
                      c.saveSettings();
                      c.refresh();
                      setState(() {});
                    },
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: GlassCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    NeonIconBox(Icons.alt_route, color: kGreen, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        sel.isEmpty
                            ? 'همهٔ برنامه‌ها از VPN عبور می‌کنند. برنامه‌هایی که تیک بزنید مستقیم (بدون VPN) کار می‌کنند.'
                            : '${sel.length} برنامه بدون VPN کار می‌کنند؛ بقیه از تونل عبور می‌کنند.',
                        style: TextStyle(color: kMuted, fontSize: 12, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'جستجوی برنامه…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                ),
              ),
            ),
            Expanded(child: _body(list, sel)),
          ],
        ),
      ),
    );
  }

  Widget _body(List<AppInfo> list, Set<String> sel) {
    if (_loading) return Center(child: CircularProgressIndicator(color: kGreen));
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: kMuted)),
            const SizedBox(height: 12),
            NeonButton(label: 'تلاش دوباره', icon: Icons.refresh, onTap: _load),
          ],
        ),
      );
    }
    if (list.isEmpty) return Center(child: Text('برنامه‌ای پیدا نشد', style: TextStyle(color: kMuted)));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final a = list[i];
        final on = sel.contains(a.packageName);
        return GlassCard(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          borderColor: on ? kGreen.withValues(alpha: .6) : null,
          onTap: () => _toggle(a.packageName),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: a.icon == null
                    ? Icon(Icons.android, color: kMuted)
                    : Image.memory(a.icon!, gaplessPlayback: true, filterQuality: FilterQuality.medium),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(a.packageName,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: kMuted, fontSize: 10.5, fontFamily: kMono)),
                  ],
                ),
              ),
              Checkbox(value: on, activeColor: kGreen, checkColor: Colors.black, onChanged: (_) => _toggle(a.packageName)),
            ],
          ),
        );
      },
    );
  }
}
