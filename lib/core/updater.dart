// lib/core/updater.dart — بررسی نسخهٔ جدید از GitHub Releases
//
// شمارهٔ بیلد هنگام ساخت در CI با --dart-define=BUILD_NUMBER=<run_number> داخل اپ می‌رود.
// اگر این مقدار صفر باشد (بیلد محلی)، بررسی به‌روزرسانی غیرفعال است.
import 'package:dio/dio.dart';

const int kBuildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);
const String kRepo = 'abolboy/zeus_vpn_app';

class UpdateInfo {
  final int build;
  final String version; // مثلاً 2.4.0 (اگر از نام فایل پیدا شود)
  final String url; // لینک مستقیم APK مناسب یا صفحهٔ انتشار
  const UpdateInfo({required this.build, required this.version, required this.url});
}

/// null یعنی نسخهٔ جدیدی نیست. در خطای شبکه استثنا پرتاب می‌شود تا بالادست پیام مناسب بدهد.
Future<UpdateInfo?> checkForUpdate(Dio dio) async {
  if (kBuildNumber <= 0) return null;
  final r = await dio.get<dynamic>(
    'https://api.github.com/repos/$kRepo/releases/latest',
    options: Options(
      headers: {'Accept': 'application/vnd.github+json'},
      responseType: ResponseType.json,
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 12),
    ),
  );
  final data = r.data;
  if (data is! Map) return null;
  final tag = (data['tag_name'] ?? '').toString();
  final m = RegExp(r'^build-(\d+)').firstMatch(tag);
  if (m == null) return null;
  final build = int.tryParse(m.group(1)!) ?? 0;
  if (build <= kBuildNumber) return null;

  var url = (data['html_url'] ?? 'https://github.com/$kRepo/releases').toString();
  var version = '';
  final assets = data['assets'];
  if (assets is List) {
    for (final a in assets) {
      if (a is! Map) continue;
      final name = (a['name'] ?? '').toString();
      if (name.contains('arm64')) {
        url = (a['browser_download_url'] ?? url).toString();
        final v = RegExp(r'v(\d+\.\d+\.\d+)').firstMatch(name);
        if (v != null) version = v.group(1)!;
        break;
      }
    }
  }
  return UpdateInfo(build: build, version: version, url: url);
}
