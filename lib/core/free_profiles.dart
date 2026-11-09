// lib/core/free_profiles.dart — فهرست پیشنهادی «پروفایل‌های رایگان» (انتخابی؛ کاربر خودش اضافه می‌کند)
//
// این‌ها اشتراک‌های عمومی‌ای هستند که افراد/گروه‌های ثالث منتشر می‌کنند (همان منابعی که برنامهٔ Hiddify
// در بخش «رایگان» پیشنهاد می‌دهد). ZEUS هیچ کنترلی روی محتوا و صاحب سرورها ندارد؛ پس هیچ‌کدام به‌صورت
// خودکار اضافه نمی‌شوند و هر بار پیش از افزودن، هشدار نمایش داده می‌شود.
class FreeProfile {
  final String title;
  final String url;
  final List<String> tags;
  final String note;
  const FreeProfile({required this.title, required this.url, required this.tags, required this.note});
}

const String kFreeConsent = 'این اشتراک را افراد یا گروه‌های ثالث جمع‌آوری و منتشر می‌کنند و ZEUS هیچ کنترلی روی آن‌ها ندارد.\n\n'
    '• صاحب سرور می‌تواند ببیند به چه آدرس‌هایی وصل می‌شوید و ترافیک رمزنشده را بخواند؛ برای ورود به حساب‌ها، بانک و اطلاعات حساس استفاده نکنید.\n'
    '• هیچ ضمانتی برای کارکرد و پایداری وجود ندارد؛ بیشتر برای مواقع اضطراری مناسب است.\n'
    '• برای امنیت بیشتر می‌توانید «WARP روی سرور» را در تنظیمات روشن کنید.\n\n'
    'با ادامه، مسئولیت استفاده با خودتان است.';

const List<FreeProfile> kBuiltinFreeProfiles = <FreeProfile>[
  FreeProfile(
    title: 'Patterniha',
    url: 'https://raw.githubusercontent.com/patterniha/Free-Configs/refs/heads/main/configs.txt',
    tags: ['عمومی', 'ایران'],
    note: 'کانفیگ‌های عمومی جمع‌آوری‌شده',
  ),
  FreeProfile(
    title: 'Anonymous 𝕏',
    url: 'https://raw.githubusercontent.com/4n0nymou3/multi-proxy-config-fetcher/refs/heads/main/configs/proxy',
    tags: ['عمومی', 'ایران'],
    note: 'ترکیب چند پروتکل؛ بخشی ممکن است با این هسته سازگار نباشد',
  ),
  FreeProfile(
    title: 'Mahsa Free Config',
    url: 'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/refs/heads/main/mci/sub_1',
    tags: ['عمومی', 'ایران'],
    note: 'اشتراک عمومی پروژهٔ MahsaFreeConfig',
  ),
];
