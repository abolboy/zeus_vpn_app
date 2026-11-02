// lib/pages/logs_page.dart — نمایش لاگ‌های اتصال / هسته / سیستم
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/controller.dart';
import '../core/models.dart';
import '../ui/theme.dart';

class LogsPage extends StatefulWidget {
  final VoidCallback onBack;
  const LogsPage({super.key, required this.onBack});
  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final c = ZeusController.I;
  int _tab = 0; // 0 همه | 1 اتصال | 2 هسته | 3 سیستم
  bool _onlyProblems = false;

  static const _tabs = ['همه', 'اتصال', 'هسته', 'سیستم'];

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: kSurface2));
  }

  LogKind? get _kind {
    switch (_tab) {
      case 1:
        return LogKind.connection;
      case 2:
        return LogKind.core;
      case 3:
        return LogKind.system;
    }
    return null;
  }

  List<LogEntry> get _filtered => c.logs.where((l) {
        if (_kind != null && l.kind != _kind) return false;
        if (_onlyProblems && l.level == LogLevel.info) return false;
        return true;
      }).toList();

  Color _levelColor(LogLevel l) {
    switch (l) {
      case LogLevel.error:
        return kRed;
      case LogLevel.warn:
        return kAmber;
      default:
        return kGreen;
    }
  }

  IconData _kindIcon(LogKind k) {
    switch (k) {
      case LogKind.connection:
        return Icons.swap_vert;
      case LogKind.core:
        return Icons.memory;
      default:
        return Icons.settings_suggest_outlined;
    }
  }

  Future<void> _copyAll() async {
    final list = _filtered;
    if (list.isEmpty) {
      _snack('لاگی برای کپی وجود ندارد');
      return;
    }
    final text = list.reversed
        .map((l) => '[${l.timeText}] [${l.levelText}] [${l.kind.name}] ${l.text}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    _snack('${list.length} رکورد کپی شد');
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پاک‌کردن لاگ‌ها'),
        content: const Text('همهٔ رکوردها حذف شوند؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف', style: TextStyle(color: kMuted))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('پاک کن'),
          ),
        ],
      ),
    );
    if (ok == true) c.clearLogs();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (_, __) {
        final list = _filtered;
        final errors = c.logs.where((l) => l.level == LogLevel.error).length;
        final warns = c.logs.where((l) => l.level == LogLevel.warn).length;
        return ZeusBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: ZeusHeader(
              title: 'لاگ‌ها',
              leading: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: widget.onBack),
              actions: [
                IconButton(tooltip: 'کپی همه', icon: const Icon(Icons.copy_all), onPressed: _copyAll),
                IconButton(
                  tooltip: 'پاک‌کردن',
                  icon: const Icon(Icons.delete_sweep_outlined, color: kRed),
                  onPressed: c.logs.isEmpty ? null : _confirmClear,
                ),
              ],
            ),
            body: Column(
              children: [
                // ───── آمار ─────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Row(
                    children: [
                      StatBox(value: '${c.logs.length}', label: 'کل'),
                      const SizedBox(width: 8),
                      StatBox(value: '$warns', label: 'هشدار', color: warns == 0 ? kMuted : kAmber),
                      const SizedBox(width: 8),
                      StatBox(value: '$errors', label: 'خطا', color: errors == 0 ? kMuted : kRed),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PillTabs(items: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_outlined, size: 16, color: kMuted),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('فقط هشدارها و خطاها', style: TextStyle(fontSize: 12, color: kMuted))),
                      Switch(
                        value: _onlyProblems,
                        activeColor: kAmber,
                        onChanged: (v) => setState(() => _onlyProblems = v),
                      ),
                    ],
                  ),
                ),
                if (!c.settings.saveLogs)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 14, color: kAmber),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text('«ذخیرهٔ لاگ» در تنظیمات خاموش است؛ فقط هشدار و خطا ثبت می‌شود',
                              style: TextStyle(fontSize: 11, color: kAmber)),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: _list(list)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _list(List<LogEntry> list) {
    if (list.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 48, color: kMuted),
            SizedBox(height: 10),
            Text('لاگی وجود ندارد', style: TextStyle(color: kMuted)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: list.length,
      itemBuilder: (_, i) => _row(list[i]),
    );
  }

  Widget _row(LogEntry l) {
    final col = _levelColor(l.level);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderColor: l.level == LogLevel.error ? kRed.withValues(alpha: 0.5) : null,
      onTap: () {
        Clipboard.setData(ClipboardData(text: '[${l.timeText}] ${l.text}'));
        _snack('کپی شد');
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(_kindIcon(l.kind), size: 16, color: col),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(l.timeText,
                        style: const TextStyle(color: kMuted, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()])),
                    const SizedBox(width: 8),
                    StatusBadge(l.levelText, color: col),
                    const SizedBox(width: 6),
                    Text(l.kind.name, style: const TextStyle(color: kMuted, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l.text,
                  textDirection: _isLatin(l.text) ? TextDirection.ltr : TextDirection.rtl,
                  style: const TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static bool _isLatin(String s) => !RegExp(r'[\u0600-\u06FF]').hasMatch(s);
}
