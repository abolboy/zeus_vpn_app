  // lib/pages/servers_page.dart — لیست سرورها با جستجو، فیلتر و آمار
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
        if (q.isNotEmpty && !n.displayName.toLowerCase().contains(q) && !n.host.toLowerCase().contains(q)) return false;
        return true;
      }).toList();

      switch (_tab) {
        case 1: // پیشنهادی: REALITY/TLS با پینگ خوب یا تست‌نشده
          list = list.where((n) => n.security != 'NONE' && (n.pingMs == -2 || (n.pingMs >= 0 && n.pingMs < 400))).toList();
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

    Future<void> _select(ServerNode n) async {
      final wasConnected = c.connected || c.connecting;
      final err = await c.selectNode(n);
      if (err != null) {
        _snack(err, err: true);
      } else if (!wasConnected) {
        widget.onBack();
      }
    }

    Future<void> _refresh() async {
      final msg = await c.syncAll();
      if (msg != null) _snack(msg, err: true);
    }

    @override
    Widget build(BuildContext context) {
      return ListenableBuilder(
        listenable: c,
        builder: (_, __) {
          final list = _filtered;
          final avg = c.avgPing;
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
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kGreen))
                        : const Icon(Icons.network_check),
                  ),
                  IconButton(
                    tooltip: 'به‌روزرسانی',
                    onPressed: c.loadingSubs ? null : _refresh,
                    icon: c.loadingSubs
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kGreen))
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
                        prefixIcon: const Icon(Icons.search, color: kMuted, size: 20),
                        suffixIcon: _search.text.isEmpty
                            ? const Icon(Icons.tune, color: kMuted, size: 18)
                            : IconButton(
                                icon: const Icon(Icons.close, color: kMuted, size: 18),
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
                        StatBox(value: avg < 0 ? '--' : '${avg}ms', label: 'میانگین پینگ', color: avg < 0 ? kMuted : pingColor(avg)),
                        const SizedBox(width: 8),
                        StatBox(value: '${c.countryCount}', label: 'کشورها'),
                        const SizedBox(width: 8),
                        StatBox(value: '${c.nodes.length}', label: 'کل سرورها'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillTabs(
                      items: _protocols,
                      index: _protocols.indexOf(_proto).clamp(0, _protocols.length - 1),
                      onChanged: (i) => setState(() => _proto = _protocols[i]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _list(list)),
                ],
              ),
            ),
          );
        },
      );
    }

    Widget _list(List<ServerNode> list) {
      if (c.loadingSubs && c.nodes.isEmpty) {
        return const Center(child: CircularProgressIndicator(color: kGreen));
      }
      if (c.nodes.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.dns_outlined, size: 48, color: kMuted),
              const SizedBox(height: 10),
              const Text('هنوز سروری ندارید', style: TextStyle(color: kMuted)),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: widget.onGoSubs, icon: const Icon(Icons.add_link), label: const Text('افزودن اشتراک')),
            ],
          ),
        );
      }
      if (list.isEmpty) {
        return Center(
          child: Text(
            _tab == 3 ? 'هنوز سروری را ستاره نکرده‌اید' : (_tab == 2 ? 'ابتدا «پینگ همه» را بزنید' : 'نتیجه‌ای یافت نشد'),
            style: const TextStyle(color: kMuted),
          ),
        );
      }
      return RefreshIndicator(
        color: kGreen,
        backgroundColor: kSurface,
        onRefresh: _refresh,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: list.length,
          itemBuilder: (_, i) => _tile(list[i]),
        ),
      );
    }

    Widget _tile(ServerNode n) {
      final sel = n.rawUri == c.selUri;
      final pc = n.pingMs == -2 ? kMuted : pingColor(n.pingMs);
      return GlassCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        borderColor: sel ? kGreen.withValues(alpha: 0.6) : null,
        onTap: () => _select(n),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: kSurface2, shape: BoxShape.circle, border: Border.all(color: kBorder)),
              child: Text(n.flag, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(n.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: sel ? kGreen : kText)),
                      ),
                      if (sel && c.connected)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.check_circle, color: kGreen, size: 16),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(n.subtitle, style: const TextStyle(color: kMuted, fontSize: 11)),
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: () => c.pingOne(n),
                        child: Text('Ping: ${n.pingText}', style: TextStyle(color: pc, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                      const Spacer(),
                      Text(n.subTag, style: const TextStyle(color: kMuted, fontSize: 10)),
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

    Widget _signal(int ms) {
      final level = ms == -2 ? 0 : (ms < 0 ? 0 : (ms < 150 ? 4 : (ms < 300 ? 3 : (ms < 600 ? 2 : 1))));
      final col = ms == -2 ? kMuted : pingColor(ms);
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) => Container(
          width: 3,
          height: 6 + i * 3.0,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: i < level ? col : kBorder,
            borderRadius: BorderRadius.circular(1),
          ),
        )),
      );
    }
  }
