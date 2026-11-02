# ZEUS VPN

<div align="center">

**Cyberpunk Neon VPN Client for Android — Xray core • PattNG • Cloudflare WARP**

</div>

---

## ✨ امکانات

- **هستهٔ Xray** از طریق پلاگین `flutter_v2ray_client` — VLESS / VMess / Trojan / Shadowsocks / SOCKS
- **PattNG**: Fragment (tlshello)، Noise (UDP)، Mux، کنترل Fingerprint/uTLS، SNI/ALPN، REALITY و cipher suites
- **Cloudflare WARP** با ثبت‌نام مستقیم از اپ (X25519 خالص Dart بدون پکیج خارجی) و زنجیرهٔ WARP↔Node
- **تأیید واقعی تونل**: بعد از CONNECTED، عبور ترافیک سنجیده می‌شود (نه فقط وضعیت سرویس)
- **پینگ هوشمند**: واقعی از طریق هسته یا TCP سریع + تست سرعت از داخل تونل (پروکسی HTTP محلی)
- **اشتراک‌ها**: چند اشتراک با Base64 خودکار، کش سرورها، علاقه‌مندی‌ها و فیلتر/جستجو
- **لاگ‌ها**: اتصال / هسته / سیستم با فیلتر هشدار-خطا و کپی سریع
- رابط کاربری فارسی (RTL) با تم Cyberpunk Neon، پس‌زمینهٔ متحرک و ترنزیشن بدون هم‌پوشانی

## 🏗 معماری

```
lib/
├── main.dart              # ورود اپ، تم، ZeusShell و منوی کشویی
├── core/
│   ├── controller.dart    # ZeusController (ChangeNotifier): اتصال، اشتراک، پینگ، سرعت، WARP، لاگ
│   ├── config_builder.dart# ساخت کانفیگ Xray از لینک + PattNG + WARP
│   └── models.dart        # مدل‌ها، پارسر لینک/اشتراک، پرچم کشورها
├── pages/                 # HomePage / ServersPage / SubsPage / SettingsPage / LogsPage
├── ui/                    # theme.dart (پالت و ویجت‌های نئونی) + transitions.dart
└── warp.dart              # ثبت‌نام Cloudflare WARP + ساخت outbound WireGuard
```

## 🚀 بیلد

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

بیلد CI در `.github/workflows/build.yml` انجام می‌شود: پوشهٔ `android/` با `flutter create`
ساخته، با `tools/patch_android.py` پچ می‌شود و APKهای split برای
`arm64-v8a` / `armeabi-v7a` / `x86_64` در GitHub Releases منتشر می‌شوند.

### امضای Release (اختیاری)

برای امضای release، این Secretها را در ریپو تنظیم کنید:

| Secret | توضیح |
|---|---|
| `KEYSTORE_B64` | فایل keystore به‌صورت Base64 |
| `KEYSTORE_PASSWORD` | رمز keystore |
| `KEY_ALIAS` | نام alias |
| `KEY_PASSWORD` | رمز کلید |

بدون این Secretها، بیلد با امضای debug انجام می‌شود.

## ⚙️ پیش‌نیازها

- Flutter ≥ 3.27 (Dart ≥ 3.6)
- Android minSdk 21 (توسط قالب پیش‌فرض برآورده می‌شود)

## آپدیت بدون حذف نسخهٔ قبلی
آپدیت فقط وقتی کار می‌کند که همهٔ نسخه‌ها با یک کلید امضا شوند. یک‌بار `bash tools/make_keystore.sh` را اجرا کنید (JDK لازم است؛
روی گوشی با Termux: `pkg install openjdk-17`) و چهار Secret خروجی را در GitHub بسازید. نسخه‌ای که قبلاً با کلید debug نصب شده،
فقط همین یک بار باید حذف شود.
