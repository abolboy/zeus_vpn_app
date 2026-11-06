// lib/pages/servers_page.dart — لیست سرورها با جستجو، فیلتر، آمار و انتخاب صریح
import 'package:flutter/material.dart';

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
  String _group = ''; // برچسب اشتراک (S1، S2…)؛ خالی = همهٔ اشتراک‌ها

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

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: err ? kRed.withValues(alpha: 0.9) : kSurface2,
    ));
  }

  ServerNode? get _pending => _pendingUri == null
      ? null
      : c.nodes.cast<ServerNode?>().firstWhere((n) => n!.rawUri == _pendingUri, orElse: () => null);

  ServerNode? get _best => c.bestNode();

  /// نام قابل‌نمایش یک اشتراک بر اساس برچسبش (S1 ← اولین اشتراک)
  String _subName(String tag) {
    final m = RegExp(r'^S(\d+)$').firstMatch(tag);
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
      if (_group.isNotEmpty && n.subTag != _group) return false;
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
                  tooltip: 'پینگ همه',
                  onPressed: c.pinging || c.nodes.isEmpty ? null : c.pingAll,
                  icon: c.pinging
                      ? SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kGreen))
                      : const Icon(Icons.network_check),
                ),
                IconButton(
                  tooltip: 'به‌روزرسانی',
                  onPressed: c.loadingSubs ? null : _refresh,
                  icon: c.loadingSubs
                      ? SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kGreen))
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'جستجوی سرور، کشور یا نام',
                      prefixIcon: Icon(Icons.search, color: kMuted, size: 20),
                      suffixIcon: _search.text.isEmpty
                          ? Icon(Icons.tune, color: kMuted, size: 18)
                          : IconButton(
                              icon: Icon(Icons.close, color: kMuted, size: 18),
                              onPressed: () => setState(_search.clear),
                            ),
                    ),
                  ),
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
                // دسته‌بندی بر اساس اشتراک (وقتی بیش از یک اشتراک داریم)
                if (c.subs.length > 1) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillTabs(
                      items: [for (final g in _groups) g.value],
                      index: _groups.indexWhere((g) => g.key == _group).clamp(0, _groups.length - 1).toInt(),
                      onChanged: (i) => setState(() => _group = _groups[i].key),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PillTabs(
                    items: _protocols,
                    index: _protocols.indexOf(_proto).clamp(0, _protocols.length - 1).toInt(),
                    onChanged: (i) => setState(() => _proto = _protocols[i]),
                  ),
                ),
                const SizedBox(height: 8),
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
    if (_group.isEmpty && c.subs.length > 1) {
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
    return RefreshIndicator(
      color: kGreen,
      backgroundColor: kSurface,
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: entries.length,
        itemBuilder: (_, i) {
          final e = entries[i];
          if (e is ServerNode) return _Appear(index: i, child: _tile(e));
          final h = e as _GroupHeader;
          return SectionLabel('${_subName(h.tag)} • ${h.count}', icon: Icons.folder_open_outlined);
        },
      ),
    );
  }

  Widget _tile(ServerNode n) {
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
                                    text: 'Ping: ${n.pingText}',
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
