  import os
  import re
  import sys

  def p(*parts):
      return os.path.join(os.getcwd(), *parts)

  MANIFEST = p("android", "app", "src", "main", "AndroidManifest.xml")
  GRADLE_KTS = p("android", "app", "build.gradle.kts")
  GRADLE_GROOVY = p("android", "app", "build.gradle")
  PROPS = p("android", "gradle.properties")

  PERMS = [
      "android.permission.INTERNET",
      "android.permission.ACCESS_NETWORK_STATE",
      "android.permission.POST_NOTIFICATIONS",
      "android.permission.FOREGROUND_SERVICE",
      "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
      "android.permission.RECEIVE_BOOT_COMPLETED",
  ]

  # attribute هایی که باید روی <application> باشند
  APP_ATTRS = {
      "android:usesCleartextTraffic": "true",   # فیکس: ساب‌های http:// روی Android 9+
      "android:extractNativeLibs": "true",      # هسته v2ray نیاز به .so استخراج‌شده دارد
  }

  def fail(msg):
      print("ERROR: " + msg)
      sys.exit(1)

  def read(path):
      with open(path, "r", encoding="utf-8") as f:
          return f.read()

  def write(path, text):
      with open(path, "w", encoding="utf-8") as f:
          f.write(text)

  def patch_manifest():
      if not os.path.exists(MANIFEST):
          fail("manifest not found: " + MANIFEST)
      text = read(MANIFEST)
      original = text

      # 1) permissions
      insert = ""
      for perm in PERMS:
          if perm not in text:
              insert += '    <uses-permission android:name="%s" />\n' % perm
      m = re.search(r"<application\b", text)
      if not m:
          fail("<application> tag not found in manifest")
      if insert:
          text = text[:m.start()] + insert + "    " + text[m.start():]

      # 2) application attributes (فقط اگر وجود ندارند)
      m = re.search(r"<application\b", text)
      attrs = ""
      for k, v in APP_ATTRS.items():
          if k not in text:
              attrs += ' %s="%s"' % (k, v)
      if attrs:
          text = text[:m.end()] + attrs + text[m.end():]

      if text != original:
          write(MANIFEST, text)
          print("manifest patched")
      else:
          print("manifest already ok")

  def patch_gradle():
      path = GRADLE_KTS if os.path.exists(GRADLE_KTS) else GRADLE_GROOVY
      if not os.path.exists(path):
          fail("gradle file not found")
      is_kts = path.endswith(".kts")
      text = read(path)
      original = text

      # 1) useLegacyPackaging
      if "useLegacyPackaging" not in text:
          block = (
              "    packaging {\n"
              "        jniLibs {\n"
              "            useLegacyPackaging = true\n"
              "        }\n"
              "    }\n"
          )
          if "android {" in text:
              text = text.replace("android {", "android {\n" + block, 1)
          else:
              text += "\nandroid {\n" + block + "}\n"

      # 2) minSdk حداقل 21 (نیاز هسته v2ray)
      if is_kts:
          text = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 21", text)
      else:
          text = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 21", text)

      # 3) فقط ABI های لازم → APK کوچک‌تر و بدون کرش روی x86
      if "abiFilters" not in text:
          if is_kts:
              ndk = '        ndk {\n            abiFilters += listOf("arm64-v8a", "armeabi-v7a")\n        }\n'
          else:
              ndk = '        ndk {\n            abiFilters "arm64-v8a", "armeabi-v7a"\n        }\n'
          text = re.sub(r"(defaultConfig\s*\{\n)", r"\1" + ndk.replace("\\", "\\\\"), text, count=1)

      if text != original:
          write(path, text)
          print("gradle patched: " + path)
      else:
          print("gradle already ok")

  def clean_props():
      if not os.path.exists(PROPS):
          print("props not found, skip")
          return
      with open(PROPS, "r", encoding="utf-8") as f:
          lines = f.readlines()
      kept = [ln for ln in lines if "enableUncompressedNativeLibs" not in ln]
      if len(kept) != len(lines):
          with open(PROPS, "w", encoding="utf-8") as f:
              f.writelines(kept)
          print("props cleaned")
      else:
          print("props ok")

  if __name__ == "__main__":
      patch_manifest()
      patch_gradle()
      clean_props()
      print("ALL PATCHES DONE")
