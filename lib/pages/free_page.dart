// lib/pages/free_page.dart — پروفایل‌های رایگان (انتخابی، با هشدار پیش از افزودن)
import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/free_profiles.dart';
import '../ui/theme.dart';

class FreePage extends StatefulWidget {
  final VoidCallback onBack;
  const FreePage({super.key, required this.onBack});
  @override
  State<FreePage> createState() => _FreePageState();
}

class _FreePageState extends State<FreePage> {
  final c = ZeusController.I;
  String? _busyUrl;

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: err ? kRed.withValues(alpha: .9) : null,
    ));
  }

  Future<void> _add(FreeProfile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(f.title),
        content: const SingleChildScrollView(child: Text(kFreeConsent, style: TextStyle(height: 1.7, fontSize: 13))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('می‌پذیرم و اضافه کن')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyUrl = f.url);
    final err = await c.addFreeSub(f.url, f.title);
    if (!mounted) return;
    setState(() => _busyUrl = null);
    _snack(err ?? '«${f.title}» اضافه شد', err: err != null);
  }

  @override
  Widget build(BuildContext context) {
    return ZeusBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: ZeusHeader(
          title: 'پروفایل‌های رایگان',
          leading: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: widget.onBack),
        ),
        body: ListenableBuilder(
          listenable: c,
          builder: (_, __) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              GlassCard(
                borderColor: kAmber.withValues(alpha: .6),
                padding: const EdgeInsets.all(12),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: kAmber, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'این سرورها را افراد ثالث منتشر می‌کنند و ضمانتی ندارند. فقط برای مواقع اضطراری و کارهای غیرحساس استفاده کنید.',
                        style: TextStyle(fontSize: 12.5, height: 1.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const SectionLabel('فهرست پیشنهادی', icon: Icons.card_giftcard),
              for (final f in kBuiltinFreeProfiles) _tile(f),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(FreeProfile f) {
    final added = c.subs.any((s) => s.url == f.url);
    final busy = _busyUrl == f.url;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          NeonIconBox(Icons.card_giftcard, color: kGreen, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text(f.note, style: TextStyle(color: kMuted, fontSize: 11.5, height: 1.4)),
                const SizedBox(height: 4),
                Text(f.tags.join(' • '), style: TextStyle(color: kGreen, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kGreen))
          else if (added)
            StatusBadge('اضافه شده', color: kGreen)
          else
            NeonButton(label: 'افزودن', icon: Icons.add, onTap: () => _add(f)),
        ],
      ),
    );
  }
}
