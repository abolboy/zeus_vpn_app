  // lib/ui/theme.dart — سیستم طراحی ZEUS (Neon-Green Dark)
  import 'package:flutter/material.dart';

  // ───────────── Palette ─────────────
  const Color kBg = Color(0xFF050807);
  const Color kSurface = Color(0xFF0B110E);
  const Color kSurface2 = Color(0xFF111A15);
  const Color kBorder = Color(0xFF1C2A22);
  const Color kGreen = Color(0xFF00FF88);
  const Color kGreenDim = Color(0xFF0D3B27);
  const Color kRed = Color(0xFFFF4D5E);
  const Color kAmber = Color(0xFFFFB800);
  const Color kBlue = Color(0xFF3FA9FF);
  const Color kText = Color(0xFFE8F5EE);
  const Color kMuted = Color(0xFF7E948A);

  ThemeData zeusTheme() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: kBg,
      colorScheme: const ColorScheme.dark(
        primary: kGreen,
        onPrimary: Colors.black,
        secondary: kGreen,
        surface: kSurface,
        onSurface: kText,
        error: kRed,
      ),
      textTheme: base.textTheme.apply(bodyColor: kText, displayColor: kText),
      dividerColor: kBorder,
      cardTheme: const CardThemeData(color: kSurface, elevation: 0, margin: EdgeInsets.zero),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kSurface2,
        isDense: true,
        labelStyle: const TextStyle(color: kMuted, fontSize: 13),
        hintStyle: const TextStyle(color: kMuted, fontSize: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGreen)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.black : kMuted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kGreen : kSurface2),
        trackOutlineColor: const WidgetStatePropertyAll(kBorder),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: kSurface2,
        contentTextStyle: TextStyle(color: kText),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: kSurface, surfaceTintColor: Colors.transparent),
      dialogTheme: const DialogThemeData(backgroundColor: kSurface, surfaceTintColor: Colors.transparent),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kGreen,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: kGreen,
          side: const BorderSide(color: kBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  // ───────────── Building blocks ─────────────

  /// کارت شیشه‌ای با حاشیهٔ سبز کم‌رنگ
  class GlassCard extends StatelessWidget {
    final Widget child;
    final EdgeInsets padding;
    final EdgeInsets margin;
    final Color? borderColor;
    final VoidCallback? onTap;
    const GlassCard({
      super.key,
      required this.child,
      this.padding = const EdgeInsets.all(14),
      this.margin = EdgeInsets.zero,
      this.borderColor,
      this.onTap,
    });
    @override
    Widget build(BuildContext context) {
      final card = Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor ?? kBorder),
        ),
        child: child,
      );
      if (onTap == null) return card;
      return InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: card);
    }
  }

  /// جعبهٔ آیکون سبز (مانند آیکون‌های سمت راست تایل‌ها در طرح)
  class NeonIconBox extends StatelessWidget {
    final IconData icon;
    final Color color;
    final double size;
    const NeonIconBox(this.icon, {super.key, this.color = kGreen, this.size = 40});
    @override
    Widget build(BuildContext context) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, color: color, size: size * 0.5),
        );
  }

  /// عنوان بخش (مثل «عمومی»، «امنیت»، «VPN»)
  class SectionLabel extends StatelessWidget {
    final String text;
    const SectionLabel(this.text, {super.key});
    @override
    Widget build(BuildContext context) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8, right: 4, left: 4),
          child: Text(text, style: const TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600)),
        );
  }

  /// تایل استاندارد: آیکون + عنوان + زیرعنوان + trailing
  class ZeusTile extends StatelessWidget {
    final IconData icon;
    final String title;
    final String? subtitle;
    final Widget? trailing;
    final VoidCallback? onTap;
    final Color iconColor;
    const ZeusTile({
      super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.trailing,
      this.onTap,
      this.iconColor = kGreen,
    });
    @override
    Widget build(BuildContext context) => GlassCard(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: onTap,
          child: Row(
            children: [
              NeonIconBox(icon, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: const TextStyle(color: kMuted, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              trailing ?? const Icon(Icons.chevron_left, color: kMuted),
            ],
          ),
        );
  }

  /// آمار کوچک (مثل «کل سرورها»، «کشورها»، «میانگین پینگ»)
  class StatBox extends StatelessWidget {
    final String value;
    final String label;
    final Color color;
    const StatBox({super.key, required this.value, required this.label, this.color = kText});
    @override
    Widget build(BuildContext context) => Expanded(
          child: GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(color: kMuted, fontSize: 11)),
              ],
            ),
          ),
        );
  }

  /// تب‌های قرصی (مثل «همه / پیشنهادی / پینگ کمتر / علاقه‌مندی‌ها»)
  class PillTabs extends StatelessWidget {
    final List<String> items;
    final int index;
    final ValueChanged<int> onChanged;
    const PillTabs({super.key, required this.items, required this.index, required this.onChanged});
    @override
    Widget build(BuildContext context) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(items.length, (i) {
              final sel = i == index;
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  label: Text(items[i], style: TextStyle(color: sel ? Colors.black : kText, fontSize: 12, fontWeight: FontWeight.w600)),
                  selected: sel,
                  onSelected: (_) => onChanged(i),
                  selectedColor: kGreen,
                  backgroundColor: kSurface2,
                  side: const BorderSide(color: kBorder),
                  showCheckmark: false,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              );
            }),
          ),
        );
  }

  /// بَج وضعیت (مثل «فعال» سبز یا «غیرفعال» قرمز)
  class StatusBadge extends StatelessWidget {
    final String text;
    final Color color;
    const StatusBadge(this.text, {super.key, this.color = kGreen});
    @override
    Widget build(BuildContext context) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
          child: Text(text, style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700)),
        );
  }

  /// هدر صفحه (عنوان وسط + دکمه‌های کنار)
  class ZeusHeader extends StatelessWidget implements PreferredSizeWidget {
    final String title;
    final Widget? leading;
    final List<Widget> actions;
    const ZeusHeader({super.key, required this.title, this.leading, this.actions = const []});
    @override
    Size get preferredSize => const Size.fromHeight(56);
    @override
    Widget build(BuildContext context) => AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leading: leading,
          title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          actions: actions,
        );
  }

  /// پس‌زمینهٔ گرادیان سبز تیره
  class ZeusBackground extends StatelessWidget {
    final Widget child;
    const ZeusBackground({super.key, required this.child});
    @override
    Widget build(BuildContext context) => Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.9),
              radius: 1.4,
              colors: [Color(0xFF0A2318), kBg],
            ),
          ),
          child: child,
        );
  }

  // ───────────── Format helpers ─────────────
  String fmtRate(num b) {
    if (b < 1024) return '${b.toStringAsFixed(0)} B/s';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB/s';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String fmtSize(num b) {
    if (b < 1024) return '${b.toStringAsFixed(0)} B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String fmtMbps(num bytesPerSec) => '${(bytesPerSec * 8 / 1e6).toStringAsFixed(1)} Mbps';

  Color pingColor(int ms) {
    if (ms < 0) return kRed;
    if (ms < 150) return kGreen;
    if (ms < 400) return kAmber;
    return kRed;
  }
