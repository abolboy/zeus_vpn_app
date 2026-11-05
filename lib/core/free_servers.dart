// lib/core/free_servers.dart — اشتراک‌های داخلی برنامه
//
// فعلاً هیچ اشتراک داخلی وجود ندارد. اگر روزی خواستید، آدرسش را در kFreeSubscriptions بگذارید؛
// در اولین اجرا خودکار اضافه و همگام می‌شود (و اگر کاربر حذفش کند دوباره اضافه نمی‌شود).
const List<String> kFreeSubscriptions = <String>[];

const String kFreeSubName = 'سرورهای رایگان';

/// آدرس‌های اشتراک داخلیِ نسخه‌های قبلی؛ در اولین اجرای این نسخه از لیست کاربر پاک می‌شوند
const List<String> kRetiredFreeSubscriptions = <String>[
  'https://raw.githubusercontent.com/abolboy/zeus_vpn_app/main/free_servers.txt',
];
