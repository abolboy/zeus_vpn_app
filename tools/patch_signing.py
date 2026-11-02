#!/usr/bin/env python3
"""Wire the release keystore (android/key.properties + android/app/zeus.jks)
into the app-level gradle file created by `flutter create`.

Adds:
  * a header that loads key.properties
  * a signingConfigs.release block
  * signingConfig = release for the release build type

Idempotent: exits early when key.properties is already referenced.
"""
import os
import re
import sys

KTS = os.path.join("android", "app", "build.gradle.kts")
GROOVY = os.path.join("android", "app", "build.gradle")
path = KTS if os.path.exists(KTS) else GROOVY
if not os.path.exists(path):
    sys.exit("ERROR: gradle file not found")
with open(path, encoding="utf-8") as f:
    s = f.read()
if "key.properties" in s:
    print("signing already configured")
    sys.exit(0)
is_kts = path.endswith(".kts")

# ---------- header (load key.properties) ----------
imports_kts = "import java.util.Properties\nimport java.io.FileInputStream\n"
head_kts = (
    'val keystoreProperties = Properties()\n'
    'val keystorePropertiesFile = rootProject.file("key.properties")\n'
    'if (keystorePropertiesFile.exists()) {\n'
    '    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n'
    '}\n'
)
head_groovy = (
    'def keystoreProperties = new Properties()\n'
    'def keystorePropertiesFile = rootProject.file("key.properties")\n'
    'if (keystorePropertiesFile.exists()) {\n'
    '    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n'
    '}\n'
)

# ---------- signingConfigs block ----------
sign_kts = (
    '    signingConfigs {\n'
    '        create("release") {\n'
    '            keyAlias = keystoreProperties["keyAlias"] as String?\n'
    '            keyPassword = keystoreProperties["keyPassword"] as String?\n'
    '            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }\n'
    '            storePassword = keystoreProperties["storePassword"] as String?\n'
    '        }\n'
    '    }\n'
)
sign_groovy = (
    '    signingConfigs {\n'
    '        release {\n'
    '            keyAlias keystoreProperties["keyAlias"]\n'
    '            keyPassword keystoreProperties["keyPassword"]\n'
    '            storeFile keystoreProperties["storeFile"] ? file(keystoreProperties["storeFile"]) : null\n'
    '            storePassword keystoreProperties["storePassword"]\n'
    '        }\n'
    '    }\n'
)

head = head_kts if is_kts else head_groovy
sign = sign_kts if is_kts else sign_groovy
pat = (
    r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)'
    if is_kts
    else r'signingConfig\s+signingConfigs\.debug'
)
rep = (
    'signingConfig = signingConfigs.getByName("release")'
    if is_kts
    else 'signingConfig signingConfigs.release'
)

if "android {" not in s:
    sys.exit("ERROR: 'android {' block not found in " + path)
# `plugins {}` باید اولین بلاک فایل بماند؛ پس کد خواندن key.properties درست قبل از android { می‌آید
s = s.replace("android {", head + "\nandroid {\n" + sign, 1)
if is_kts:
    s = imports_kts + s
s, n = re.subn(pat, rep, s)
if n == 0:
    print("::warning::debug signingConfig line not found; release build may use debug key")
with open(path, "w", encoding="utf-8") as f:
    f.write(s)
print("signing configured in " + path)
