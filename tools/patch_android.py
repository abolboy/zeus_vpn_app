  import os
  import sys

  MANIFEST = os.path.join("android", "app", "src", "main", "AndroidManifest.xml")
  GRADLE_KTS = os.path.join("android", "app", "build.gradle.kts")
  GRADLE_GROOVY = os.path.join("android", "app", "build.gradle")
  PROPS = os.path.join("android", "gradle.properties")
  PERMS = ["android.permission.INTERNET", "android.permission.POST_NOTIFICATIONS", "android.permission.FOREGROUND_SERVICE", "android.permission.FOREGROUND_SERVICE_SPECIAL_USE"]

  # ---------- Manifest ----------
  if not os.path.exists(MANIFEST): sys.exit("ERROR: manifest not found: " + MANIFEST)
  text = open(MANIFEST, encoding="utf-8").read()
  original = text
  insert = "".join('    <uses-permission android:name="' + p + '" />\n' for p in PERMS if p not in text)
  if insert and "<application" in text: text = text.replace("<application", insert + "    <application", 1)
  if "android:extractNativeLibs" not in text and "<application" in text: text = text.replace("<application", '<application android:extractNativeLibs="true"', 1)
  if "android:usesCleartextTraffic" not in text and "<application" in text: text = text.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
  if text != original: open(MANIFEST, "w", encoding="utf-8").write(text)
  print("manifest patched" if text != original else "manifest already ok")

  # ---------- Gradle ----------
  path = GRADLE_KTS if os.path.exists(GRADLE_KTS) else GRADLE_GROOVY
  if not os.path.exists(path): sys.exit("ERROR: gradle file not found")
  text = open(path, encoding="utf-8").read()
  block = "    packaging {\n        jniLibs {\n            useLegacyPackaging = true\n        }\n    }\n"
  if "useLegacyPackaging" in text: print("gradle already ok")
  elif "android {" in text: text = text.replace("android {", "android {\n" + block, 1); open(path, "w", encoding="utf-8").write(text); print("gradle patched: " + path)
  else: text = text + "\nandroid {\n" + block + "}\n"; open(path, "w", encoding="utf-8").write(text); print("gradle patched (appended): " + path)

  # ---------- gradle.properties ----------
  lines = open(PROPS, encoding="utf-8").readlines() if os.path.exists(PROPS) else []
  kept = [l for l in lines if "enableUncompressedNativeLibs" not in l]
  if lines and len(kept) != len(lines): open(PROPS, "w", encoding="utf-8").write("".join(kept)); print("props cleaned")
  else: print("props ok")

  print("ALL PATCHES DONE")
