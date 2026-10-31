  import os
  import re
  import sys

  KTS = os.path.join("android", "app", "build.gradle.kts")
  GROOVY = os.path.join("android", "app", "build.gradle")
  path = KTS if os.path.exists(KTS) else GROOVY
  if not os.path.exists(path): sys.exit("ERROR: gradle file not found")
  s = open(path, encoding="utf-8").read()
  if "key.properties" in s: print("signing already configured"); sys.exit(0)
  is_kts = path.endswith(".kts")

  # ---------- header (load key.properties) ----------
  head_kts = 'import java.util.Properties\nimport java.io.FileInputStream\nval keystoreProperties = Properties()\nval keystorePropertiesFile = rootProject.file("key.properties")\nif (keystorePropertiesFile.exists()) {\n    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n}\n'
  head_groovy = 'def keystoreProperties = new Properties()\ndef keystorePropertiesFile = rootProject.file("key.properties")\nif (keystorePropertiesFile.exists()) {\n    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n}\n'

  # ---------- signingConfigs block ----------
  sign_kts = '    signingConfigs {\n        create("release") {\n            keyAlias = keystoreProperties["keyAlias"] as String?\n            keyPassword = keystoreProperties["keyPassword"] as String?\n            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }\n            storePassword = keystoreProperties["storePassword"] as String?\n        }\n    }\n'
  sign_groovy = '    signingConfigs {\n        release {\n            keyAlias keystoreProperties["keyAlias"]\n            keyPassword keystoreProperties["keyPassword"]\n            storeFile keystoreProperties["storeFile"] ? file(keystoreProperties["storeFile"]) : null\n            storePassword keystoreProperties["storePassword"]\n        }\n    }\n'

  head = head_kts if is_kts else head_groovy
  sign = sign_kts if is_kts else sign_groovy
  pat = r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)' if is_kts else r'signingConfig\s+signingConfigs\.debug'
  rep = 'signingConfig = signingConfigs.getByName("release")' if is_kts else 'signingConfig signingConfigs.release'

  s = head + s
  if "android {" not in s: sys.exit("ERROR: 'android {' block not found in " + path)
  s = s.replace("android {", "android {\n" + sign, 1)
  s, n = re.subn(pat, rep, s)
  if n == 0: print("::warning::debug signingConfig line not found; release build may use debug key")
  open(path, "w", encoding="utf-8").write(s)
  print("signing configured in " + path)
