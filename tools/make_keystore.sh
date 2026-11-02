#!/usr/bin/env bash
# یک‌بار اجرا کنید تا کلید امضای ثابت برای اپ ساخته شود.
# بدون کلید ثابت، هر بیلد CI یک امضای debug تازه می‌گیرد و اندروید اجازهٔ آپدیت روی نسخهٔ قبلی را نمی‌دهد.
set -euo pipefail
read -rsp "رمز keystore (حداقل ۶ کاراکتر): " PASS; echo
keytool -genkeypair -v -keystore zeus.jks -alias zeus -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" -dname "CN=ZEUS VPN"
echo
echo "در GitHub → Settings → Secrets and variables → Actions این ۴ مقدار را بسازید:"
echo "  KEYSTORE_PASSWORD = (همان رمز)    KEY_PASSWORD = (همان رمز)    KEY_ALIAS = zeus"
echo "  KEYSTORE_B64 = خروجی دستور زیر:"
base64 -w0 zeus.jks 2>/dev/null || base64 zeus.jks | tr -d '\n'
echo
echo "فایل zeus.jks را جای امن نگه دارید و هرگز در ریپو کامیت نکنید؛ اگر گم شود دیگر نمی‌توانید آپدیت بدهید."
