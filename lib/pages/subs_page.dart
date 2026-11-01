// متد ایمن برای دیکد کردن لینک‌های اشتراک Base64
String decodeSubscriptionData(String rawData) {
  try {
    // پاکسازی فاصله و اصلاح کاراکترهای URL-safe
    String normalized = rawData.trim().replaceAll('-', '+').replaceAll('_', '/');
    
    // افزودن پدینگ گم‌شده در صورت نیاز
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    
    Codec<String, String> stringToBase64 = utf8.fuse(base64);
    return stringToBase64.decode(normalized);
  } on FormatException catch (e) {
    // اگر متن دیکد شده خودش متن معمولی یا لینک مستقیم باشد
    return rawData;
  } catch (e) {
    return 'خطا در پردازش اطلاعات اشتراک';
  }
}
