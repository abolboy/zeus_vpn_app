// اصلاحیه برای مدیریت ایمن وضعیت اتصال و جلوگیری از فریز شدن UI
Future<void> toggleConnection(String configData) async {
  try {
    isLoading.value = true;
    errorMessage.value = '';

    // فراخوانی امن کانال ارتباطی نیتیو
    final result = await platform.invokeMethod('startVpn', {'config': configData});
    
    if (result == true) {
      isConnected.value = true;
    } else {
      errorMessage.value = 'خطا در راه‌اندازی سرویس VPN';
      isConnected.value = false;
    }
  } on PlatformException catch (e) {
    errorMessage.value = 'خطای پلتفرم: ${e.message}';
    isConnected.value = false;
  } catch (e) {
    errorMessage.value = 'خطای ناشناخته: $e';
    isConnected.value = false;
  } finally {
    isLoading.value = تمام شدن عملیات; // اطمینان از خارج شدن از حالت لودینگ
    isLoading.value = false;
  }
}
