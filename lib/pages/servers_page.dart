// lib/pages/servers_page.dart — لیست سرورها با جستجو، فیلتر، آمار و انتخاب صریح
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/controller.dart';
import '../core/models.dart';
import '../ui/theme.dart';

class ServersPage extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onGoSubs;
  const ServersPage({super.key, required this.onBack, required this.onGoSubs});
  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  final c = ZeusController.I;
  final _search = TextEditingController();
  int _tab = 0; // 0 همه | 1 پیشنهادی | 2 پینگ کمتر | 3 علاقه‌مندی‌ها
  String _proto = 'همه';
  String _group = ''; // برچسب اشتراک (S1، S2… یا *other)؛ خالی = همه (وقتی اشتراکی نیست)
  bool _searchOpen = false;

  /// سروری که کاربر در این صفحه لمس کرده. تا دکمهٔ «اتصال» زده نشود،
  /// در حالت متصل هیچ تغییری در c.selUri داده نمی‌شود (اتصال فعلی دست‌نخورده می‌ماند).
  String? _pendingUri;
  bool _acting = false;

  static const _tabs = ['همه', 'پیشنهادی', 'پینگ کمتر', 'علاقه‌مندی‌ها'];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _removeDead() async {
    final n = c.deadCount;
    if (n == 0) {
      _snack('سرور بی‌پاسخی پیدا نشد (اول «پینگ همه» را بزنید)');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف سرورهای بی‌پاسخ'),
        content: Text('$n سرور که پینگ نداشتند از لیست حذف می‌شوند.\nعلاقه‌مندی‌ها و سرور انتخابی حفظ می‌شوند و با به‌روزرسانی اشتراک دوباره می‌آیند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await c.removeDeadNodes();
    _snack('$r سرور حذف شد');
  }

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: err ? kRed.withValues(alpha: 0.9) : kSurface2,
    ));
  }

  Future<void> _addSingleLinkDialog() async {
    final ctl = TextEditingController();
    final clipboard = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    if (isSupportedLink(clipboard)) ctl.text = clipboard;
    if (!mounted) {
      ctl.dispose();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('افزودن لینک تکی سرور'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctl,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontFamily: kMono, fontSize: 11.5),
            decoration: const InputDecoration(
              hintText: 'vless://…  یا  vmess://…  یا  trojan://…',
              helperText: 'یک لینک سرور وارد کن؛ اشتراک HTTPS لازم نیست',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('افزودن سرور'),
          ),
        ],
      ),
    );

    final value = ctl.text.trim();
    Future.delayed(const Duration(milliseconds: 400), ctl.dispose);
    if (confirmed != true || value.isEmpty) return;

    final error = await c.addSingleLink(value);
    if (!mounted) return;
    if (error != null) {
      _snack(error, err: true);
      return;
    }

    final normalized = normalizeLink(value);
    setState(() => _pendingUri = normalized);
    _snack('لینک تکی به فهرست سرورها اضافه شد؛ برای اتصال، دکمهٔ اتصال را بزن');
  }

  ServerNode? get _pending => _pendingUri == null
      ? null
      : c.nodes.cast<ServerNode?>().firstWhere((n) => n!.rawUri == _pendingUri, orElse: () => null);

  ServerNode? get _best => c.bestNode();

  /// نام قابل‌نمایش یک اشتراک بر اساس برچسبش (S1 ← اولین اشتراک)
  String _subName(String tag) {
    if (tag == 'M') return 'لینک تکی';
    final m = RegExp(r'^S(\d+)
    if (m != null) {
      final i = (int.tryParse(m.group(1)!) ?? 0) - 1;
      if (i >= 0 && i < c.subs.length) {
        final s = c.subs[i];
        if (s.name.isNotEmpty) return s.name;
        final host = Uri.tryParse(s.url)?.host ?? '';
        return host.isNotEmpty ? host : 'اشتراک ${i + 1}';
      }
    }
    return tag;
  }

  bool _isSubTag(String tag) {
    final m = RegExp(r'^S(\d+)$').firstMatch(tag);
    final i = m == null ? -1 : (int.tryParse(m.group(1)!) ?? 0) - 1;
    return i >= 0 && i < c.subs.length;
  }

  bool _inGroup(ServerNode n, String g) => g == '*other' ? !_isSubTag(n.subTag) : n.subTag == g;

  /// تب‌های اشتراک: هر اشتراک + («سایر» برای لینک‌های دستی)
  List<_TabItem> get _subTabs {
    if (c.subs.isEmpty) return const [];
    final out = <_TabItem>[];
    for (var i = 0; i < c.subs.length; i++) {
      final tag = 'S${i + 1}';
      out.add(_TabItem(tag, _subName(tag), c.nodes.where((e) => e.subTag == tag).length));
    }
    final other = c.nodes.where((e) => !_isSubTag(e.subTag)).length;
    if (other > 0) out.add(_TabItem('*other', 'سایر', other));
    return out;
  }

  void _onMenu(String v) {
    switch (v) {
      case 'refresh':
        if (!c.loadingSubs) _refresh();
      case 'ping':
        if (!c.pinging && c.nodes.isNotEmpty) c.pingAll();
      case 'clean':
        if (c.nodes.isNotEmpty) _removeDead();
      case 'view':
        c.settings.gridView = !c.settings.gridView;
        c.saveSettings();
        c.refresh();
    }
  }

  /// گروه‌ها برای فیلتر: (برچسب، متن). اولی «همه» است.
  List<MapEntry<String, String>> get _groups {
    final out = <MapEntry<String, String>>[const MapEntry('', 'همه اشتراک‌ها')];
    for (var i = 0; i < c.subs.length; i++) {
      final tag = 'S${i + 1}';
      final n = c.nodes.where((e) => e.subTag == tag).length;
      out.add(MapEntry(tag, '${_subName(tag)} ($n)'));
    }
    return out;
  }

  List<String> get _protocols {
    final set = <String>{'همه'};
    for (final n in c.nodes) {
      set.add(n.protocol);
    }
    return set.toList();
  }

  List<ServerNode> get _filtered {
    final q = _search.text.trim().toLowerCase();
    var list = c.nodes.where((n) {
      if (_proto != 'همه' && n.protocol != _proto) return false;
      // وقتی جستجو می‌کنی، نتیجه از همهٔ اشتراک‌هاست؛ وگرنه فقط تبِ انتخاب‌شده
      if (_group.isNotEmpty && q.isEmpty && !_inGroup(n, _group)) return false;
      if (q.isNotEmpty && !n.displayName.toLowerCase().contains(q) && !n.host.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();

    switch (_tab) {
      case 1: // پیشنهادی: REALITY/TLS با پینگ خوب یا تست‌نشده
        list = list
            .where((n) => n.security != 'NONE' && (n.pingMs == -2 || (n.pingMs >= 0 && n.pingMs < 400)))
            .toList();
        list.sort(_byPing);
        break;
      case 2:
        list = list.where((n) => n.pingMs >= 0).toList()..sort(_byPing);
        break;
      case 3:
        list = list.where((n) => n.favorite).toList();
        break;
    }
    return list;
  }

  int _byPing(ServerNode a, ServerNode b) {
    int k(ServerNode n) => n.pingMs < 0 ? 999999 : n.pingMs;
    return k(a).compareTo(k(b));
  }

  // ───────── actions ─────────

  /// لمس کارت = فقط انتخاب. در حالت قطع، انتخاب ذخیره می‌شود؛
  /// در حالت متصل، فقط به‌صورت «در انتظار» نگه داشته می‌شود تا اتصال فعلی نشکند.
  Future<void> _select(ServerNode n) async {
    if (!c.connected && !c.connecting) {
      await c.selectNode(n, reconnect: false);
    }
    if (!mounted) return;
    setState(() => _pendingUri = n.rawUri);
  }

  /// اتصال/اتصال مجدد صریح؛ فقط بعد از موفقیت به خانه برمی‌گردد.
  Future<void> _connectSelected() async {
    final n = _pending;
    if (n == null || _acting || c.busy) return;
    setState(() => _acting = true);
    try {
      if (c.connected || c.connecting) await c.disconnect();
      await c.selectNode(n, reconnect: false); // حالا که قطع شدیم، انتخاب واقعی
      final err = await c.connect();
      if (!mounted) return;
      if (err != null) {
        _snack(err, err: true);
      } else {
        _pendingUri = null; // نوار اتصال در بازدید بعدی تکرار نشود
        widget.onBack();
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _refresh() async {
    final msg = await c.syncAll();
    if (msg != null) _snack(msg, err: true);
  }

  // ───────── build ─────────
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (_, __) {
        // اگر بعد از به‌روزرسانی اشتراک، پروتکل یا اشتراکِ فیلترشده دیگر وجود نداشته باشد،
        // فیلتر به «همه» برمی‌گردد (قبلاً تبِ «همه» به‌صورت بصری انتخاب می‌شد ولی فیلتر
        // قدیمی باقی می‌ماند و لیست همیشه خالی با پیام «نتیجه‌ای یافت نشد» نمایش داده می‌شد)
        if (_proto != 'همه' && !_protocols.contains(_proto)) _proto = 'همه';
        // تب اشتراک: همیشه یکی انتخاب است (پیش‌فرض اولین اشتراک)؛ اگر دیگر وجود نداشت به اولی برمی‌گردد
        final tabs = _subTabs;
        if (tabs.isEmpty) {
          _group = '';
        } else if (!tabs.any((t) => t.key == _group)) {
          _group = tabs.first.key;
        }
        final list = _filtered;
        final avg = c.avgPing;
        final pending = _pending;
        return ZeusBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: ZeusHeader(
              title: 'سرورها',
              leading: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: widget.onBack),
              actions: [
                IconButton(
                  tooltip: 'جستجو',
                  icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
                  onPressed: () => setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) _search.clear();
                  }),
                ),
                PopupMenuButton<String>(
                  tooltip: 'افزودن سرور',
                  color: kSurface2,
                  icon: const Icon(Icons.add),
                  onSelected: (value) {
                    if (value == 'single') {
                      _addSingleLinkDialog();
                    } else if (value == 'subscription') {
                      widget.onGoSubs();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'single',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.link),
                        title: Text('لینک تکی سرور'),
                        subtitle: Text('VLESS / VMess / Trojan / SS'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'subscription',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.playlist_add),
                        title: Text('اشتراک HTTPS'),
                      ),
                    ),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: 'بیشتر',
                  color: kSurface2,
                  icon: const Icon(Icons.more_vert),
                  onSelected: _onMenu,
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'refresh', child: Text('به‌روزرسانی اشتراک‌ها')),
                    const PopupMenuItem(value: 'ping', child: Text('پینگ همه')),
                    const PopupMenuItem(value: 'clean', child: Text('حذف سرورهای بدون پینگ')),
                    PopupMenuItem(value: 'view', child: Text(c.settings.gridView ? 'نمایش لیستی' : 'نمایش شبکه‌ای (دو ستونه)')),
                  ],
                ),
              ],
            ),
            body: Column(
              children: [
                if (c.loadingSubs) LinearProgressIndicator(minHeight: 2, color: kGreen, backgroundColor: kBorder),
                if (_searchOpen || _search.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: TextField(
                      controller: _search,
                      autofocus: _searchOpen && _search.text.isEmpty,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'جستجوی سرور، کشور یا نام (در همهٔ اشتراک‌ها)',
                        prefixIcon: Icon(Icons.search, color: kMuted, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(Icons.close, color: kMuted, size: 18),
                          onPressed: () => setState(() {
                            _search.clear();
                            _searchOpen = false;
                          }),
                        ),
                      ),
                    ),
                  ),
                // تب‌های اشتراک (مثل PattNG): هر اشتراک یک تب با تعداد سرورهایش
                if (_subTabs.isNotEmpty)
                  _SubTabBar(
                    items: _subTabs,
                    selected: _group,
                    onSelect: (k) => setState(() => _group = k),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PillTabs(items: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      StatBox(
                        value: avg < 0 ? '--' : '${avg}ms',
                        label: 'میانگین پینگ',
                        color: avg < 0 ? kMuted : pingColor(avg),
                      ),
                      const SizedBox(width: 8),
                      StatBox(value: '${c.countryCount}', label: 'کشورها', color: kBlue),
                      const SizedBox(width: 8),
                      StatBox(value: '${c.nodes.length}', label: 'کل سرورها'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // نوار پیشرفت «پینگ همه» + شمارنده
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: c.pinging
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: c.pingTotal > 0 ? c.pingDone / c.pingTotal : null,
                                  minHeight: 4,
                                  backgroundColor: kBorder,
                                  color: kGreen,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'در حال سنجش ${c.pingDone}/${c.pingTotal}…',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: kMuted, fontFamily: kMono, fontSize: 10),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                // نشان بهترین سرور (با کوت‌ترین پینگ)
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: (!c.pinging && _best != null)
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: _bestChip(_best!),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 8),
                if (c.pingHint != null && !c.pinging)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: GlassCard(
                      borderColor: kAmber.withValues(alpha: .6),
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: kAmber, size: 22),
                          const SizedBox(width: 10),
                          Expanded(child: Text(c.pingHint!, style: const TextStyle(fontSize: 12, height: 1.5))),
                        ],
                      ),
                    ),
                  ),
                Expanded(child: _list(list)),
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: pending == null ? const SizedBox(width: double.infinity) : _connectBar(pending),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _connectBar(ServerNode n) {
    final reconnect = c.connected || c.connecting;
    final isCurrent = reconnect && n.rawUri == c.selUri;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: GlassCard(
          margin: EdgeInsets.zero,
          glow: true,
          borderColor: (reconnect ? kAmber : kGreen).withValues(alpha: .6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _flag(n, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(
                      isCurrent
                          ? 'همین سرور متصل است؛ می‌توانید دوباره وصل شوید'
                          : (reconnect ? 'اتصال فعلی قطع و با این سرور برقرار می‌شود' : 'آمادهٔ اتصال'),
                      style: TextStyle(color: kMuted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              NeonButton(
                label: reconnect ? 'اتصال مجدد' : 'اتصال',
                icon: _acting ? null : (reconnect ? Icons.sync : Icons.bolt),
                color: reconnect ? kAmber : kGreen,
                onTap: _acting || c.busy ? null : _connectSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(List<ServerNode> list) {
    if (c.loadingSubs && c.nodes.isEmpty) {
      return Center(child: CircularProgressIndicator(color: kGreen));
    }
    if (c.nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 48, color: kMuted),
            const SizedBox(height: 10),
            Text('هنوز سروری ندارید', style: TextStyle(color: kMuted)),
            const SizedBox(height: 12),
            NeonButton(
              label: 'افزودن لینک تکی',
              icon: Icons.link,
              onTap: _addSingleLinkDialog,
            ),
            const SizedBox(height: 8),
            NeonButton(
              label: 'افزودن اشتراک',
              icon: Icons.add_link,
              onTap: widget.onGoSubs,
            ),
          ],
        ),
      );
    }
    if (list.isEmpty) {
      return Center(
        child: Text(
          _tab == 3
              ? 'هنوز سروری را ستاره نکرده‌اید'
              : (_tab == 2 ? 'ابتدا «پینگ همه» را بزنید' : 'نتیجه‌ای یافت نشد'),
          style: TextStyle(color: kMuted),
        ),
      );
    }
    // وقتی بیش از یک اشتراک داریم و فیلتری انتخاب نشده، سرورها زیر عنوان هر اشتراک می‌آیند
    final entries = <Object>[];
    if (_search.text.trim().isNotEmpty && c.subs.length > 1) {
      final byTag = <String, List<ServerNode>>{};
      for (final n in list) {
        (byTag[n.subTag] ??= <ServerNode>[]).add(n);
      }
      final order = <String>[for (var i = 0; i < c.subs.length; i++) 'S${i + 1}'];
      final tags = <String>[...order.where(byTag.containsKey), ...byTag.keys.where((t) => !order.contains(t))];
      for (final t in tags) {
        entries.add(_GroupHeader(t, byTag[t]!.length));
        entries.addAll(byTag[t]!);
      }
    } else {
      entries.addAll(list);
    }
    // نمایش شبکه‌ای: هر ردیف دو کارت؛ عنوان اشتراک ردیف را می‌شکند
    final rows = <Object>[];
    if (c.settings.gridView) {
      List<ServerNode>? cur;
      for (final e in entries) {
        if (e is ServerNode) {
          if (cur == null || cur.length == 2) {
            cur = <ServerNode>[];
            rows.add(cur);
          }
          cur.add(e);
        } else {
          rows.add(e);
          cur = null;
        }
      }
    } else {
      rows.addAll(entries);
    }
    return RefreshIndicator(
      color: kGreen,
      backgroundColor: kSurface,
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final e = rows[i];
          if (e is List<ServerNode>) return _Appear(index: i, child: _gridRow(e));
          if (e is ServerNode) return _Appear(index: i, child: _tile(e));
          final h = e as _GroupHeader;
          return SectionLabel('${_subName(h.tag)} • ${h.count}', icon: Icons.folder_open_outlined);
        },
      ),
    );
  }

  /// نگه‌داشتن روی سرور: QR و کپی لینک برای اشتراک‌گذاری
  void _share(ServerNode n) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface2,
      isScrollControlled: true,
      shape: BeveledRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: kBorder),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(n.displayName, maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: QrImageView(data: n.rawUri, size: 220),
              ),
              const SizedBox(height: 14),
              NeonButton(
                label: 'کپی لینک',
                icon: Icons.copy,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: n.rawUri));
                  Navigator.pop(ctx);
                  _snack('لینک کپی شد');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(ServerNode n) => GestureDetector(onLongPress: () => _share(n), child: _tileCard(n));

  // ───────── نمایش شبکه‌ای (دو ستونه) ─────────
  /// IPv4 را مثل PattNG نیمه‌پنهان نشان می‌دهد (آخرین بخش ***)؛ دامنه کامل می‌ماند.
  /// اگر نام از قبل پرچم دارد (🇩🇪 …) دوباره اضافه نشود
  bool _startsWithFlag(String s) => RegExp(r'^[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true).hasMatch(s);

  String _maskedAddress(ServerNode n) {
    final m = RegExp(r'^(\d{1,3}\.\d{1,3}\.\d{1,3})\.\d{1,3}$').firstMatch(n.host);
    final h = m != null ? '${m.group(1)}.***' : n.host;
    return n.port > 0 ? '$h:${n.port}' : h;
  }

  String _transport(ServerNode n) {
    try {
      final u = n.rawUri;
      if (u.startsWith('vmess://')) {
        final j = jsonDecode(utf8.decode(base64.decode(base64.normalize(u.substring(8))))) as Map;
        return (j['net'] ?? 'tcp').toString().toLowerCase();
      }
      return (Uri.parse(u).queryParameters['type'] ?? 'tcp').toLowerCase();
    } catch (_) {
      return 'tcp';
    }
  }

  /// مثل «VLESS / xhttp / reality»؛ tcp و none نمایش داده نمی‌شوند
  String _kind(ServerNode n) {
    final tr = _transport(n);
    final sec = n.security.toLowerCase();
    return [n.protocol, if (tr != 'tcp') tr, if (sec.isNotEmpty && sec != 'none') sec].join(' / ');
  }

  Widget _gridRow(List<ServerNode> p) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _gridCard(p[0])),
              const SizedBox(width: 10),
              Expanded(child: p.length > 1 ? _gridCard(p[1]) : const SizedBox.shrink()),
            ],
          ),
        ),
      );

  Widget _gridCard(ServerNode n) {
    final sel = n.rawUri == c.selUri;
    final pend = !sel && n.rawUri == _pendingUri;
    final probing = c.pingingUris.contains(n.rawUri);
    final accent = sel ? kGreen : (pend ? kAmber : null);
    final name = n.displayName.isEmpty ? (n.host.isEmpty ? 'سرور بی‌نام' : n.host) : n.displayName;
    final ping = probing ? 'سنجش…' : (n.pingMs >= 0 ? '${n.pingMs}ms' : (n.pingMs == -1 ? 'timeout' : ''));
    final pc = probing ? kAmber : (n.pingMs == -2 ? kMuted : pingColor(n.pingMs));
    return GestureDetector(
      onLongPress: () => _share(n),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
        borderColor: accent?.withValues(alpha: .7),
        glow: sel || pend,
        onTap: () => _select(n),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (accent != null) Container(width: 3, margin: const EdgeInsetsDirectional.only(end: 8), color: accent),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          (n.flag.isEmpty || _startsWithFlag(name)) ? name : '${n.flag} $name',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, height: 1.3, color: sel ? kGreen : kText),
                        ),
                      ),
                      _cardMenu(n),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_maskedAddress(n),
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: kMuted, fontSize: 11, fontFamily: kMono)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_kind(n),
                            textDirection: TextDirection.ltr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: kAmber, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      if (ping.isNotEmpty)
                        Text(ping, style: TextStyle(color: pc, fontSize: 11.5, fontWeight: FontWeight.w800, fontFamily: kMono)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardMenu(ServerNode n) => SizedBox(
        width: 30,
        height: 30,
        child: PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          color: kSurface2,
          icon: Icon(Icons.more_vert, size: 18, color: kMuted),
          onSelected: (v) {
            switch (v) {
              case 'share':
                _share(n);
              case 'fav':
                c.toggleFavorite(n);
              case 'ping':
                c.pingOne(n);
              case 'chain':
                c.setChain(n.rawUri);
                _snack('به‌عنوان سرور واسطه (زنجیره) تنظیم شد');
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'share', child: Text('QR / کپی لینک')),
            PopupMenuItem(value: 'fav', child: Text(n.favorite ? 'حذف از علاقه‌مندی' : 'علاقه‌مندی')),
            const PopupMenuItem(value: 'ping', child: Text('پینگ این سرور')),
            const PopupMenuItem(value: 'chain', child: Text('سرور واسطه (زنجیره)')),
          ],
        ),
      );

  Widget _tileCard(ServerNode n) {
    final sel = n.rawUri == c.selUri; // سرور ذخیره‌شده/متصل
    final pend = !sel && n.rawUri == _pendingUri; // در انتظار اتصال مجدد
    final probing = c.pingingUris.contains(n.rawUri);
    final pc = n.pingMs == -2 ? kMuted : pingColor(n.pingMs);

    // وضعیت واقعی فقط برای سرور فعال
    Widget? status;
    if (sel && c.connected) {
      if (c.tunnel == TunnelState.ok) {
        status = Icon(Icons.check_circle, color: kGreen, size: 16);
      } else if (c.tunnel == TunnelState.failed) {
        status = const Icon(Icons.warning_amber_rounded, color: kRed, size: 16);
      } else {
        status = const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kAmber));
      }
    }

    final nameColor = sel ? kGreen : (pend ? kAmber : kText);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderColor: sel ? kGreen.withValues(alpha: 0.7) : (pend ? kAmber.withValues(alpha: .7) : null),
      glow: sel || pend,
      onTap: () => _select(n),
      child: Row(
        children: [
          _flag(n),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(n.displayName.isEmpty ? (n.host.isEmpty ? 'سرور بی‌نام' : n.host) : n.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: nameColor)),
                    ),
                    if (status != null) Padding(padding: const EdgeInsets.only(left: 6), child: status),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(n.subtitle.isEmpty ? '--' : n.subtitle, style: TextStyle(color: kMuted, fontSize: 11)),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: probing ? null : () => c.pingOne(n),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: probing
                            ? const Text('سنجش…',
                                style: TextStyle(color: kAmber, fontSize: 11, fontWeight: FontWeight.w600))
                            : Text.rich(
                                TextSpan(children: [
                                  TextSpan(
                                    text: 'Ping: ${n.pingText}${n.viaTcp && n.pingMs >= 0 ? ' (TCP)' : ''}',
                                    style: TextStyle(color: pc, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                  // جیتر و درصد نمونه‌های ناموفق از تست چندنمونه‌ای
                                  if (n.pingMs >= 0 && n.jitterMs > 0)
                                    TextSpan(
                                      text: ' ±${n.jitterMs}',
                                      style: TextStyle(color: kMuted, fontSize: 10, fontFamily: kMono),
                                    ),
                                  if (n.pingMs >= 0 && n.lossPct > 0)
                                    TextSpan(
                                      text: ' · ${n.lossPct}%',
                                      style: const TextStyle(color: kAmber, fontSize: 10, fontFamily: kMono),
                                    ),
                                ]),
                              ),
                      ),
                    ),
                    const Spacer(),
                    Text(_subName(n.subTag), style: TextStyle(color: kMuted, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _signal(n.pingMs),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => c.toggleFavorite(n),
            icon: Icon(n.favorite ? Icons.star : Icons.star_border, color: n.favorite ? kAmber : kMuted, size: 20),
          ),
        ],
      ),
    );
  }

  /// نشان «بهترین سرور» با کوتاه‌ترین پینگ — لمس = انتخاب
  Widget _bestChip(ServerNode n) => GlassCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onTap: () => _select(n),
        borderColor: kGreen.withValues(alpha: .5),
        glow: true,
        child: Row(
          children: [
            Text('⌁', style: TextStyle(color: kGreen, fontSize: 15, fontFamily: kMono)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('بهترین سرور: ${n.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            Text('${n.pingMs} ms',
                style: TextStyle(
                    color: pingColor(n.pingMs), fontFamily: kMono, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _flag(ServerNode n, {double size = 40}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kSurface2,
          shape: BoxShape.circle,
          border: Border.all(color: kBorder),
        ),
        child: n.flag.trim().isEmpty
            ? Icon(Icons.public, color: kMuted, size: size * .5)
            : Text(n.flag, style: TextStyle(fontSize: size * .5)),
      );

  Widget _signal(int ms) {
    final level = ms < 0 ? 0 : (ms < 150 ? 4 : (ms < 300 ? 3 : (ms < 600 ? 2 : 1)));
    final col = ms == -2 ? kMuted : pingColor(ms);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(
        4,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 3,
          height: 6 + i * 3.0,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: i < level ? col : kBorder,
            borderRadius: BorderRadius.circular(1),
            boxShadow: i < level ? [BoxShadow(color: col.withValues(alpha: .6), blurRadius: 4)] : null,
          ),
        ),
      ),
    );
  }
}

/// ورود پلکانی آیتم‌های لیست (فقط یک‌بار؛ در rebuildهای بعدی تکرار نمی‌شود)
class _Appear extends StatelessWidget {
  final int index;
  final Widget child;
  const _Appear({required this.index, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 260 + index.clamp(0, 8).toInt() * 45),
        curve: Curves.easeOutCubic,
        builder: (_, v, w) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: w),
        ),
        child: child,
      );
}

class _GroupHeader {
  final String tag;
  final int count;
  const _GroupHeader(this.tag, this.count);
}

class _TabItem {
  final String key;
  final String label;
  final int count;
  const _TabItem(this.key, this.label, this.count);
}

/// نوار تب‌های اشتراک؛ قرص گرد با تب‌های قابل‌پیمایش و نشان تعداد (مثل PattNG)
class _SubTabBar extends StatelessWidget {
  final List<_TabItem> items;
  final String selected;
  final ValueChanged<String> onSelect;
  const _SubTabBar({required this.items, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kSurface2.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final t in items)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(t.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: t.key == selected ? kGreen.withValues(alpha: .16) : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: t.key == selected ? kGreen.withValues(alpha: .55) : Colors.transparent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          t.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.key == selected ? kGreen : kMuted,
                            fontWeight: t.key == selected ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: t.key == selected ? kGreen : kMuted.withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${t.count}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            fontFamily: kMono,
                            color: t.key == selected ? Colors.black : kText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
).firstMatch(tag);
    if (m != null) {
      final i = (int.tryParse(m.group(1)!) ?? 0) - 1;
      if (i >= 0 && i < c.subs.length) {
        final s = c.subs[i];
        if (s.name.isNotEmpty) return s.name;
        final host = Uri.tryParse(s.url)?.host ?? '';
        return host.isNotEmpty ? host : 'اشتراک ${i + 1}';
      }
    }
    return tag;
  }

  bool _isSubTag(String tag) {
    final m = RegExp(r'^S(\d+)$').firstMatch(tag);
    final i = m == null ? -1 : (int.tryParse(m.group(1)!) ?? 0) - 1;
    return i >= 0 && i < c.subs.length;
  }

  bool _inGroup(ServerNode n, String g) => g == '*other' ? !_isSubTag(n.subTag) : n.subTag == g;

  /// تب‌های اشتراک: هر اشتراک + («سایر» برای لینک‌های دستی)
  List<_TabItem> get _subTabs {
    if (c.subs.isEmpty) return const [];
    final out = <_TabItem>[];
    for (var i = 0; i < c.subs.length; i++) {
      final tag = 'S${i + 1}';
      out.add(_TabItem(tag, _subName(tag), c.nodes.where((e) => e.subTag == tag).length));
    }
    final other = c.nodes.where((e) => !_isSubTag(e.subTag)).length;
    if (other > 0) out.add(_TabItem('*other', 'سایر', other));
    return out;
  }

  void _onMenu(String v) {
    switch (v) {
      case 'refresh':
        if (!c.loadingSubs) _refresh();
      case 'ping':
        if (!c.pinging && c.nodes.isNotEmpty) c.pingAll();
      case 'clean':
        if (c.nodes.isNotEmpty) _removeDead();
      case 'view':
        c.settings.gridView = !c.settings.gridView;
        c.saveSettings();
        c.refresh();
    }
  }

  /// گروه‌ها برای فیلتر: (برچسب، متن). اولی «همه» است.
  List<MapEntry<String, String>> get _groups {
    final out = <MapEntry<String, String>>[const MapEntry('', 'همه اشتراک‌ها')];
    for (var i = 0; i < c.subs.length; i++) {
      final tag = 'S${i + 1}';
      final n = c.nodes.where((e) => e.subTag == tag).length;
      out.add(MapEntry(tag, '${_subName(tag)} ($n)'));
    }
    return out;
  }

  List<String> get _protocols {
    final set = <String>{'همه'};
    for (final n in c.nodes) {
      set.add(n.protocol);
    }
    return set.toList();
  }

  List<ServerNode> get _filtered {
    final q = _search.text.trim().toLowerCase();
    var list = c.nodes.where((n) {
      if (_proto != 'همه' && n.protocol != _proto) return false;
      // وقتی جستجو می‌کنی، نتیجه از همهٔ اشتراک‌هاست؛ وگرنه فقط تبِ انتخاب‌شده
      if (_group.isNotEmpty && q.isEmpty && !_inGroup(n, _group)) return false;
      if (q.isNotEmpty && !n.displayName.toLowerCase().contains(q) && !n.host.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();

    switch (_tab) {
      case 1: // پیشنهادی: REALITY/TLS با پینگ خوب یا تست‌نشده
        list = list
            .where((n) => n.security != 'NONE' && (n.pingMs == -2 || (n.pingMs >= 0 && n.pingMs < 400)))
            .toList();
        list.sort(_byPing);
        break;
      case 2:
        list = list.where((n) => n.pingMs >= 0).toList()..sort(_byPing);
        break;
      case 3:
        list = list.where((n) => n.favorite).toList();
        break;
    }
    return list;
  }

  int _byPing(ServerNode a, ServerNode b) {
    int k(ServerNode n) => n.pingMs < 0 ? 999999 : n.pingMs;
    return k(a).compareTo(k(b));
  }

  // ───────── actions ─────────

  /// لمس کارت = فقط انتخاب. در حالت قطع، انتخاب ذخیره می‌شود؛
  /// در حالت متصل، فقط به‌صورت «در انتظار» نگه داشته می‌شود تا اتصال فعلی نشکند.
  Future<void> _select(ServerNode n) async {
    if (!c.connected && !c.connecting) {
      await c.selectNode(n, reconnect: false);
    }
    if (!mounted) return;
    setState(() => _pendingUri = n.rawUri);
  }

  /// اتصال/اتصال مجدد صریح؛ فقط بعد از موفقیت به خانه برمی‌گردد.
  Future<void> _connectSelected() async {
    final n = _pending;
    if (n == null || _acting || c.busy) return;
    setState(() => _acting = true);
    try {
      if (c.connected || c.connecting) await c.disconnect();
      await c.selectNode(n, reconnect: false); // حالا که قطع شدیم، انتخاب واقعی
      final err = await c.connect();
      if (!mounted) return;
      if (err != null) {
        _snack(err, err: true);
      } else {
        _pendingUri = null; // نوار اتصال در بازدید بعدی تکرار نشود
        widget.onBack();
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _refresh() async {
    final msg = await c.syncAll();
    if (msg != null) _snack(msg, err: true);
  }

  // ───────── build ─────────
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (_, __) {
        // اگر بعد از به‌روزرسانی اشتراک، پروتکل یا اشتراکِ فیلترشده دیگر وجود نداشته باشد،
        // فیلتر به «همه» برمی‌گردد (قبلاً تبِ «همه» به‌صورت بصری انتخاب می‌شد ولی فیلتر
        // قدیمی باقی می‌ماند و لیست همیشه خالی با پیام «نتیجه‌ای یافت نشد» نمایش داده می‌شد)
        if (_proto != 'همه' && !_protocols.contains(_proto)) _proto = 'همه';
        // تب اشتراک: همیشه یکی انتخاب است (پیش‌فرض اولین اشتراک)؛ اگر دیگر وجود نداشت به اولی برمی‌گردد
        final tabs = _subTabs;
        if (tabs.isEmpty) {
          _group = '';
        } else if (!tabs.any((t) => t.key == _group)) {
          _group = tabs.first.key;
        }
        final list = _filtered;
        final avg = c.avgPing;
        final pending = _pending;
        return ZeusBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: ZeusHeader(
              title: 'سرورها',
              leading: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: widget.onBack),
              actions: [
                IconButton(
                  tooltip: 'جستجو',
                  icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
                  onPressed: () => setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) _search.clear();
                  }),
                ),
                IconButton(
                  tooltip: 'افزودن اشتراک',
                  icon: const Icon(Icons.add),
                  onPressed: widget.onGoSubs,
                ),
                PopupMenuButton<String>(
                  tooltip: 'بیشتر',
                  color: kSurface2,
                  icon: const Icon(Icons.more_vert),
                  onSelected: _onMenu,
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'refresh', child: Text('به‌روزرسانی اشتراک‌ها')),
                    const PopupMenuItem(value: 'ping', child: Text('پینگ همه')),
                    const PopupMenuItem(value: 'clean', child: Text('حذف سرورهای بدون پینگ')),
                    PopupMenuItem(value: 'view', child: Text(c.settings.gridView ? 'نمایش لیستی' : 'نمایش شبکه‌ای (دو ستونه)')),
                  ],
                ),
              ],
            ),
            body: Column(
              children: [
                if (c.loadingSubs) LinearProgressIndicator(minHeight: 2, color: kGreen, backgroundColor: kBorder),
                if (_searchOpen || _search.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: TextField(
                      controller: _search,
                      autofocus: _searchOpen && _search.text.isEmpty,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'جستجوی سرور، کشور یا نام (در همهٔ اشتراک‌ها)',
                        prefixIcon: Icon(Icons.search, color: kMuted, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(Icons.close, color: kMuted, size: 18),
                          onPressed: () => setState(() {
                            _search.clear();
                            _searchOpen = false;
                          }),
                        ),
                      ),
                    ),
                  ),
                // تب‌های اشتراک (مثل PattNG): هر اشتراک یک تب با تعداد سرورهایش
                if (_subTabs.isNotEmpty)
                  _SubTabBar(
                    items: _subTabs,
                    selected: _group,
                    onSelect: (k) => setState(() => _group = k),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PillTabs(items: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      StatBox(
                        value: avg < 0 ? '--' : '${avg}ms',
                        label: 'میانگین پینگ',
                        color: avg < 0 ? kMuted : pingColor(avg),
                      ),
                      const SizedBox(width: 8),
                      StatBox(value: '${c.countryCount}', label: 'کشورها', color: kBlue),
                      const SizedBox(width: 8),
                      StatBox(value: '${c.nodes.length}', label: 'کل سرورها'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // نوار پیشرفت «پینگ همه» + شمارنده
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: c.pinging
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: c.pingTotal > 0 ? c.pingDone / c.pingTotal : null,
                                  minHeight: 4,
                                  backgroundColor: kBorder,
                                  color: kGreen,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'در حال سنجش ${c.pingDone}/${c.pingTotal}…',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: kMuted, fontFamily: kMono, fontSize: 10),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                // نشان بهترین سرور (با کوت‌ترین پینگ)
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: (!c.pinging && _best != null)
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: _bestChip(_best!),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 8),
                if (c.pingHint != null && !c.pinging)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: GlassCard(
                      borderColor: kAmber.withValues(alpha: .6),
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: kAmber, size: 22),
                          const SizedBox(width: 10),
                          Expanded(child: Text(c.pingHint!, style: const TextStyle(fontSize: 12, height: 1.5))),
                        ],
                      ),
                    ),
                  ),
                Expanded(child: _list(list)),
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: pending == null ? const SizedBox(width: double.infinity) : _connectBar(pending),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _connectBar(ServerNode n) {
    final reconnect = c.connected || c.connecting;
    final isCurrent = reconnect && n.rawUri == c.selUri;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: GlassCard(
          margin: EdgeInsets.zero,
          glow: true,
          borderColor: (reconnect ? kAmber : kGreen).withValues(alpha: .6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _flag(n, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(
                      isCurrent
                          ? 'همین سرور متصل است؛ می‌توانید دوباره وصل شوید'
                          : (reconnect ? 'اتصال فعلی قطع و با این سرور برقرار می‌شود' : 'آمادهٔ اتصال'),
                      style: TextStyle(color: kMuted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              NeonButton(
                label: reconnect ? 'اتصال مجدد' : 'اتصال',
                icon: _acting ? null : (reconnect ? Icons.sync : Icons.bolt),
                color: reconnect ? kAmber : kGreen,
                onTap: _acting || c.busy ? null : _connectSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(List<ServerNode> list) {
    if (c.loadingSubs && c.nodes.isEmpty) {
      return Center(child: CircularProgressIndicator(color: kGreen));
    }
    if (c.nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 48, color: kMuted),
            const SizedBox(height: 10),
            Text('هنوز سروری ندارید', style: TextStyle(color: kMuted)),
            const SizedBox(height: 12),
            NeonButton(label: 'افزودن اشتراک', icon: Icons.add_link, onTap: widget.onGoSubs),
          ],
        ),
      );
    }
    if (list.isEmpty) {
      return Center(
        child: Text(
          _tab == 3
              ? 'هنوز سروری را ستاره نکرده‌اید'
              : (_tab == 2 ? 'ابتدا «پینگ همه» را بزنید' : 'نتیجه‌ای یافت نشد'),
          style: TextStyle(color: kMuted),
        ),
      );
    }
    // وقتی بیش از یک اشتراک داریم و فیلتری انتخاب نشده، سرورها زیر عنوان هر اشتراک می‌آیند
    final entries = <Object>[];
    if (_search.text.trim().isNotEmpty && c.subs.length > 1) {
      final byTag = <String, List<ServerNode>>{};
      for (final n in list) {
        (byTag[n.subTag] ??= <ServerNode>[]).add(n);
      }
      final order = <String>[for (var i = 0; i < c.subs.length; i++) 'S${i + 1}'];
      final tags = <String>[...order.where(byTag.containsKey), ...byTag.keys.where((t) => !order.contains(t))];
      for (final t in tags) {
        entries.add(_GroupHeader(t, byTag[t]!.length));
        entries.addAll(byTag[t]!);
      }
    } else {
      entries.addAll(list);
    }
    // نمایش شبکه‌ای: هر ردیف دو کارت؛ عنوان اشتراک ردیف را می‌شکند
    final rows = <Object>[];
    if (c.settings.gridView) {
      List<ServerNode>? cur;
      for (final e in entries) {
        if (e is ServerNode) {
          if (cur == null || cur.length == 2) {
            cur = <ServerNode>[];
            rows.add(cur);
          }
          cur.add(e);
        } else {
          rows.add(e);
          cur = null;
        }
      }
    } else {
      rows.addAll(entries);
    }
    return RefreshIndicator(
      color: kGreen,
      backgroundColor: kSurface,
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final e = rows[i];
          if (e is List<ServerNode>) return _Appear(index: i, child: _gridRow(e));
          if (e is ServerNode) return _Appear(index: i, child: _tile(e));
          final h = e as _GroupHeader;
          return SectionLabel('${_subName(h.tag)} • ${h.count}', icon: Icons.folder_open_outlined);
        },
      ),
    );
  }

  /// نگه‌داشتن روی سرور: QR و کپی لینک برای اشتراک‌گذاری
  void _share(ServerNode n) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface2,
      isScrollControlled: true,
      shape: BeveledRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: kBorder),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(n.displayName, maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: QrImageView(data: n.rawUri, size: 220),
              ),
              const SizedBox(height: 14),
              NeonButton(
                label: 'کپی لینک',
                icon: Icons.copy,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: n.rawUri));
                  Navigator.pop(ctx);
                  _snack('لینک کپی شد');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(ServerNode n) => GestureDetector(onLongPress: () => _share(n), child: _tileCard(n));

  // ───────── نمایش شبکه‌ای (دو ستونه) ─────────
  /// IPv4 را مثل PattNG نیمه‌پنهان نشان می‌دهد (آخرین بخش ***)؛ دامنه کامل می‌ماند.
  /// اگر نام از قبل پرچم دارد (🇩🇪 …) دوباره اضافه نشود
  bool _startsWithFlag(String s) => RegExp(r'^[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true).hasMatch(s);

  String _maskedAddress(ServerNode n) {
    final m = RegExp(r'^(\d{1,3}\.\d{1,3}\.\d{1,3})\.\d{1,3}$').firstMatch(n.host);
    final h = m != null ? '${m.group(1)}.***' : n.host;
    return n.port > 0 ? '$h:${n.port}' : h;
  }

  String _transport(ServerNode n) {
    try {
      final u = n.rawUri;
      if (u.startsWith('vmess://')) {
        final j = jsonDecode(utf8.decode(base64.decode(base64.normalize(u.substring(8))))) as Map;
        return (j['net'] ?? 'tcp').toString().toLowerCase();
      }
      return (Uri.parse(u).queryParameters['type'] ?? 'tcp').toLowerCase();
    } catch (_) {
      return 'tcp';
    }
  }

  /// مثل «VLESS / xhttp / reality»؛ tcp و none نمایش داده نمی‌شوند
  String _kind(ServerNode n) {
    final tr = _transport(n);
    final sec = n.security.toLowerCase();
    return [n.protocol, if (tr != 'tcp') tr, if (sec.isNotEmpty && sec != 'none') sec].join(' / ');
  }

  Widget _gridRow(List<ServerNode> p) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _gridCard(p[0])),
              const SizedBox(width: 10),
              Expanded(child: p.length > 1 ? _gridCard(p[1]) : const SizedBox.shrink()),
            ],
          ),
        ),
      );

  Widget _gridCard(ServerNode n) {
    final sel = n.rawUri == c.selUri;
    final pend = !sel && n.rawUri == _pendingUri;
    final probing = c.pingingUris.contains(n.rawUri);
    final accent = sel ? kGreen : (pend ? kAmber : null);
    final name = n.displayName.isEmpty ? (n.host.isEmpty ? 'سرور بی‌نام' : n.host) : n.displayName;
    final ping = probing ? 'سنجش…' : (n.pingMs >= 0 ? '${n.pingMs}ms' : (n.pingMs == -1 ? 'timeout' : ''));
    final pc = probing ? kAmber : (n.pingMs == -2 ? kMuted : pingColor(n.pingMs));
    return GestureDetector(
      onLongPress: () => _share(n),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
        borderColor: accent?.withValues(alpha: .7),
        glow: sel || pend,
        onTap: () => _select(n),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (accent != null) Container(width: 3, margin: const EdgeInsetsDirectional.only(end: 8), color: accent),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          (n.flag.isEmpty || _startsWithFlag(name)) ? name : '${n.flag} $name',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, height: 1.3, color: sel ? kGreen : kText),
                        ),
                      ),
                      _cardMenu(n),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_maskedAddress(n),
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: kMuted, fontSize: 11, fontFamily: kMono)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_kind(n),
                            textDirection: TextDirection.ltr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: kAmber, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      if (ping.isNotEmpty)
                        Text(ping, style: TextStyle(color: pc, fontSize: 11.5, fontWeight: FontWeight.w800, fontFamily: kMono)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardMenu(ServerNode n) => SizedBox(
        width: 30,
        height: 30,
        child: PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          color: kSurface2,
          icon: Icon(Icons.more_vert, size: 18, color: kMuted),
          onSelected: (v) {
            switch (v) {
              case 'share':
                _share(n);
              case 'fav':
                c.toggleFavorite(n);
              case 'ping':
                c.pingOne(n);
              case 'chain':
                c.setChain(n.rawUri);
                _snack('به‌عنوان سرور واسطه (زنجیره) تنظیم شد');
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'share', child: Text('QR / کپی لینک')),
            PopupMenuItem(value: 'fav', child: Text(n.favorite ? 'حذف از علاقه‌مندی' : 'علاقه‌مندی')),
            const PopupMenuItem(value: 'ping', child: Text('پینگ این سرور')),
            const PopupMenuItem(value: 'chain', child: Text('سرور واسطه (زنجیره)')),
          ],
        ),
      );

  Widget _tileCard(ServerNode n) {
    final sel = n.rawUri == c.selUri; // سرور ذخیره‌شده/متصل
    final pend = !sel && n.rawUri == _pendingUri; // در انتظار اتصال مجدد
    final probing = c.pingingUris.contains(n.rawUri);
    final pc = n.pingMs == -2 ? kMuted : pingColor(n.pingMs);

    // وضعیت واقعی فقط برای سرور فعال
    Widget? status;
    if (sel && c.connected) {
      if (c.tunnel == TunnelState.ok) {
        status = Icon(Icons.check_circle, color: kGreen, size: 16);
      } else if (c.tunnel == TunnelState.failed) {
        status = const Icon(Icons.warning_amber_rounded, color: kRed, size: 16);
      } else {
        status = const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kAmber));
      }
    }

    final nameColor = sel ? kGreen : (pend ? kAmber : kText);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderColor: sel ? kGreen.withValues(alpha: 0.7) : (pend ? kAmber.withValues(alpha: .7) : null),
      glow: sel || pend,
      onTap: () => _select(n),
      child: Row(
        children: [
          _flag(n),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(n.displayName.isEmpty ? (n.host.isEmpty ? 'سرور بی‌نام' : n.host) : n.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: nameColor)),
                    ),
                    if (status != null) Padding(padding: const EdgeInsets.only(left: 6), child: status),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(n.subtitle.isEmpty ? '--' : n.subtitle, style: TextStyle(color: kMuted, fontSize: 11)),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: probing ? null : () => c.pingOne(n),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: probing
                            ? const Text('سنجش…',
                                style: TextStyle(color: kAmber, fontSize: 11, fontWeight: FontWeight.w600))
                            : Text.rich(
                                TextSpan(children: [
                                  TextSpan(
                                    text: 'Ping: ${n.pingText}${n.viaTcp && n.pingMs >= 0 ? ' (TCP)' : ''}',
                                    style: TextStyle(color: pc, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                  // جیتر و درصد نمونه‌های ناموفق از تست چندنمونه‌ای
                                  if (n.pingMs >= 0 && n.jitterMs > 0)
                                    TextSpan(
                                      text: ' ±${n.jitterMs}',
                                      style: TextStyle(color: kMuted, fontSize: 10, fontFamily: kMono),
                                    ),
                                  if (n.pingMs >= 0 && n.lossPct > 0)
                                    TextSpan(
                                      text: ' · ${n.lossPct}%',
                                      style: const TextStyle(color: kAmber, fontSize: 10, fontFamily: kMono),
                                    ),
                                ]),
                              ),
                      ),
                    ),
                    const Spacer(),
                    Text(n.subTag, style: TextStyle(color: kMuted, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _signal(n.pingMs),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => c.toggleFavorite(n),
            icon: Icon(n.favorite ? Icons.star : Icons.star_border, color: n.favorite ? kAmber : kMuted, size: 20),
          ),
        ],
      ),
    );
  }

  /// نشان «بهترین سرور» با کوتاه‌ترین پینگ — لمس = انتخاب
  Widget _bestChip(ServerNode n) => GlassCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onTap: () => _select(n),
        borderColor: kGreen.withValues(alpha: .5),
        glow: true,
        child: Row(
          children: [
            Text('⌁', style: TextStyle(color: kGreen, fontSize: 15, fontFamily: kMono)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('بهترین سرور: ${n.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            Text('${n.pingMs} ms',
                style: TextStyle(
                    color: pingColor(n.pingMs), fontFamily: kMono, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _flag(ServerNode n, {double size = 40}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kSurface2,
          shape: BoxShape.circle,
          border: Border.all(color: kBorder),
        ),
        child: n.flag.trim().isEmpty
            ? Icon(Icons.public, color: kMuted, size: size * .5)
            : Text(n.flag, style: TextStyle(fontSize: size * .5)),
      );

  Widget _signal(int ms) {
    final level = ms < 0 ? 0 : (ms < 150 ? 4 : (ms < 300 ? 3 : (ms < 600 ? 2 : 1)));
    final col = ms == -2 ? kMuted : pingColor(ms);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(
        4,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 3,
          height: 6 + i * 3.0,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: i < level ? col : kBorder,
            borderRadius: BorderRadius.circular(1),
            boxShadow: i < level ? [BoxShadow(color: col.withValues(alpha: .6), blurRadius: 4)] : null,
          ),
        ),
      ),
    );
  }
}

/// ورود پلکانی آیتم‌های لیست (فقط یک‌بار؛ در rebuildهای بعدی تکرار نمی‌شود)
class _Appear extends StatelessWidget {
  final int index;
  final Widget child;
  const _Appear({required this.index, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 260 + index.clamp(0, 8).toInt() * 45),
        curve: Curves.easeOutCubic,
        builder: (_, v, w) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: w),
        ),
        child: child,
      );
}

class _GroupHeader {
  final String tag;
  final int count;
  const _GroupHeader(this.tag, this.count);
}

class _TabItem {
  final String key;
  final String label;
  final int count;
  const _TabItem(this.key, this.label, this.count);
}

/// نوار تب‌های اشتراک؛ قرص گرد با تب‌های قابل‌پیمایش و نشان تعداد (مثل PattNG)
class _SubTabBar extends StatelessWidget {
  final List<_TabItem> items;
  final String selected;
  final ValueChanged<String> onSelect;
  const _SubTabBar({required this.items, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kSurface2.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final t in items)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(t.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: t.key == selected ? kGreen.withValues(alpha: .16) : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: t.key == selected ? kGreen.withValues(alpha: .55) : Colors.transparent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          t.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.key == selected ? kGreen : kMuted,
                            fontWeight: t.key == selected ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: t.key == selected ? kGreen : kMuted.withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${t.count}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            fontFamily: kMono,
                            color: t.key == selected ? Colors.black : kText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
