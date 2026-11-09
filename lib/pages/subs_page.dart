// lib/pages/subs_page.dart — مدیریت اشتراک‌ها
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/controller.dart';
import '../core/models.dart';
import '../ui/theme.dart';

class SubsPage extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback? onGoFree;
  const SubsPage({super.key, required this.onBack, this.onGoFree});
  @override
  State<SubsPage> createState() => _SubsPageState();
}

class _SubsPageState extends State<SubsPage> {
  final c = ZeusController.I;

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: err ? kRed.withValues(alpha: 0.9) : kSurface2,
    ));
  }

  Future<void> _add(String url) async {
    final err = await c.addSub(url);
    if (err != null) {
      _snack(err, err: true);
    } else {
      _snack('اشتراک اضافه شد');
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = (data?.text ?? '').trim();
    if (t.isEmpty) {
      _snack('کلیپ‌بورد خالی است', err: true);
      return;
    }
    if (!t.startsWith('http')) {
      _snack('متن کلیپ‌بورد لینک اشتراک نیست', err: true);
      return;
    }
    await _add(t);
  }

  Future<void> _manualDialog() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('وارد کردن لینک اشتراک'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: 'https://…'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('انصراف', style: TextStyle(color: kMuted))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('افزودن')),
        ],
      ),
    );
    // dispose فوری هنگام انیمیشن بستن دیالوگ خطای «used after disposed» می‌دهد
    Future.delayed(const Duration(milliseconds: 400), ctl.dispose);
    if (url != null && url.trim().isNotEmpty) await _add(url);
  }

  Future<void> _refresh() async {
    final msg = await c.syncAll();
    if (!mounted) return;
    if (msg != null) {
      _snack(msg, err: true);
    } else {
      _snack('به‌روزرسانی انجام شد');
    }
  }

  Future<void> _confirmRemove(SubRecord s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف اشتراک'),
        content: Text('«${s.name.isEmpty ? s.url : s.name}» حذف شود؟ سرورهای آن از لیست پاک می‌شوند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('انصراف', style: TextStyle(color: kMuted))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) await c.removeSub(s);
  }

  String _ago(DateTime? t) {
    if (t == null) return 'هنوز همگام نشده';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'همین الان';
    if (d.inHours < 1) return '${d.inMinutes} دقیقه پیش';
    if (d.inDays < 1) return '${d.inHours} ساعت پیش';
    return '${d.inDays} روز پیش';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (_, __) {
        final active = c.subs.isNotEmpty;
        final okCount = c.subs.where((s) => s.lastOk).length;
        DateTime? last;
        for (final s in c.subs) {
          if (s.lastSync != null && (last == null || s.lastSync!.isAfter(last))) last = s.lastSync;
        }
        return ZeusBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: ZeusHeader(
              title: 'اشتراک',
              leading: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: widget.onBack),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                // ───── کارت وضعیت ─────
                GlassCard(
                  borderColor: active ? kGreen.withValues(alpha: 0.35) : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('وضعیت اشتراک', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                          StatusBadge(active ? 'فعال' : 'خالی', color: active ? kGreen : kMuted),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active ? '${c.subs.length} اشتراک • $okCount سالم' : 'هنوز اشتراکی اضافه نشده',
                        style: TextStyle(color: kMuted, fontSize: 12),
                      ),
                      const Divider(height: 22),
                      Row(
                        children: [
                          Expanded(child: _kv('سرورها', '${c.nodes.length}')),
                          Expanded(child: _kv('آخرین همگام‌سازی', _ago(last))),
                        ],
                      ),
                    ],
                  ),
                ),

                const SectionLabel('مدیریت اشتراک'),
                ZeusTile(
                  icon: Icons.content_paste_go,
                  title: 'چسباندن از کلیپ‌بورد',
                  subtitle: 'لینک کپی‌شده را اضافه می‌کند',
                  onTap: c.loadingSubs ? null : _pasteFromClipboard,
                ),
                ZeusTile(
                  icon: Icons.edit_note,
                  title: 'وارد کردن دستی لینک',
                  subtitle: 'Paste subscription link',
                  onTap: c.loadingSubs ? null : _manualDialog,
                ),
                ZeusTile(
                  icon: Icons.sync,
                  title: 'به‌روزرسانی اشتراک',
                  subtitle: 'به‌روزرسانی سرورها و تنظیمات',
                  trailing: c.loadingSubs
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kGreen))
                      : Icon(Icons.chevron_left, color: kMuted),
                  onTap: (c.loadingSubs || c.subs.isEmpty) ? null : _refresh,
                ),
                if (widget.onGoFree != null)
                  ZeusTile(
                    icon: Icons.card_giftcard,
                    title: 'پروفایل‌های رایگان',
                    subtitle: 'فهرست پیشنهادی اشتراک‌های عمومی (با هشدار پیش از افزودن)',
                    onTap: widget.onGoFree,
                  ),
                ZeusTile(
                  icon: Icons.backup_outlined,
                  title: 'پشتیبان‌گیری (کپی)',
                  subtitle: 'اشتراک‌ها و تنظیمات PattNG در یک متن',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: c.exportBackup()));
                    _snack('پشتیبان کپی شد؛ آن را جایی امن نگه دارید');
                  },
                ),
                ZeusTile(
                  icon: Icons.restore,
                  title: 'بازیابی از کلیپ‌بورد',
                  subtitle: 'متنی که با ZEUS-BACKUP شروع می‌شود',
                  onTap: _restore,
                ),
                ZeusTile(
                  icon: Icons.ios_share,
                  title: 'کپی همهٔ لینک‌ها (TXT)',
                  subtitle: 'هر سرور در یک خط، برای اشتراک‌گذاری',
                  onTap: c.nodes.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: c.exportLinks()));
                          _snack('${c.nodes.length} لینک کپی شد');
                        },
                ),

                if (c.subs.isNotEmpty) ...[
                  const SectionLabel('اشتراک‌های شما'),
                  ...c.subs.asMap().entries.map((e) => _subTile(e.key, e.value)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: TextStyle(color: kMuted, fontSize: 11)),
          const SizedBox(height: 3),
          Text(v, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kGreen)),
        ],
      );

  Future<void> _restore() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final err = await c.importBackup(data?.text ?? '');
    _snack(err ?? 'پشتیبان بازیابی شد', err: err != null);
  }

  /// حجم مصرفی و انقضا (از هدر `subscription-userinfo` یا توضیح ابتدای اشتراک)
  Widget _metaLine(SubRecord s) {
    final parts = <String>[];
    if (s.total > 0) parts.add('${fmtSize(s.used)} از ${fmtSize(s.total)}');
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (s.expire > 0) {
      final left = DateTime.fromMillisecondsSinceEpoch(s.expire * 1000).difference(DateTime.now()).inDays;
      parts.add(s.expire * 1000 < nowMs ? 'منقضی شده' : '$left روز مانده');
    }
    final frac = s.total > 0 ? (s.used / s.total).clamp(0.0, 1.0).toDouble() : 0.0;
    final warn = frac > .9 || (s.expire > 0 && s.expire * 1000 < nowMs);
    final col = warn ? kRed : kGreen;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: frac, minHeight: 4, color: col, backgroundColor: kBorder),
            ),
          const SizedBox(height: 3),
          Text(parts.join(' • '), style: TextStyle(color: col, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _subTile(int i, SubRecord s) {
    final title = s.name.isEmpty ? (Uri.tryParse(s.url)?.host ?? s.url) : s.name;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (s.lastOk ? kGreen : kRed).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('S${i + 1}', style: TextStyle(color: s.lastOk ? kGreen : kRed, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  s.lastOk ? '${s.nodeCount} سرور • ${_ago(s.lastSync)}' : 'دریافت ناموفق • ${_ago(s.lastSync)}',
                  style: TextStyle(color: s.lastOk ? kMuted : kRed, fontSize: 11),
                ),
                if (s.total > 0 || s.expire > 0) _metaLine(s),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'کپی لینک',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: s.url));
              _snack('لینک کپی شد');
            },
            icon: Icon(Icons.copy, color: kMuted, size: 18),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'حذف',
            onPressed: () => _confirmRemove(s),
            icon: const Icon(Icons.delete_outline, color: kRed, size: 20),
          ),
        ],
      ),
    );
  }
}
