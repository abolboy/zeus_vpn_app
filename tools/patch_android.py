import os
import sys

def p(*parts):
    return os.path.join(os.getcwd(), *parts)

MANIFEST = p("android", "app", "src", "main", "AndroidManifest.xml")
GRADLE_KTS = p("android", "app", "build.gradle.kts")
GRADLE_GROOVY = p("android", "app", "build.gradle")
PROPS = p("android", "gradle.properties")

PERMS = [
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
]

def patch_manifest():
    if not os.path.exists(MANIFEST):
        print("ERROR: manifest not found: " + MANIFEST)
        sys.exit(1)
    with open(MANIFEST, "r", encoding="utf-8") as f:
        text = f.read()
    original = text
    insert = ""
    for perm in PERMS:
        if perm not in text:
            insert += '    <uses-permission android:name="' + perm + '" />\n'
    if insert and "<application" in text:
        text = text.replace("<application", insert + "    <application", 1)
    if "android:extractNativeLibs" not in text and "<application" in text:
        text = text.replace("<application", '<application android:extractNativeLibs="true"', 1)
    if text != original:
        with open(MANIFEST, "w", encoding="utf-8") as f:
            f.write(text)
        print("manifest patched")
    else:
        print("manifest already ok")

def patch_gradle():
    path = GRADLE_KTS if os.path.exists(GRADLE_KTS) else GRADLE_GROOVY
    if not os.path.exists(path):
        print("ERROR: gradle file not found")
        sys.exit(1)
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    if "useLegacyPackaging" in text:
        print("gradle already ok")
        return
    block = "    packaging {\n        jniLibs {\n            useLegacyPackaging = true\n        }\n    }\n"
    if "android {" in text:
        text = text.replace("android {", "android {\n" + block, 1)
    else:
        text += "\nandroid {\n" + block + "}\n"
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("gradle patched: " + path)

def patch_props():
    line = "android.bundle.enableUncompressedNativeLibs = false\n"
    if not os.path.exists(PROPS):
        with open(PROPS, "w", encoding="utf-8") as f:
            f.write("org.gradle.jvmargs=-Xmx4G\n" + line)
        print("props created")
        return
    with open(PROPS, "r", encoding="utf-8") as f:
        text = f.read()
    if "enableUncompressedNativeLibs" in text:
        print("props already ok")
        return
    if not text.endswith("\n"):
        text += "\n"
    text += line
    with open(PROPS, "w", encoding="utf-8") as f:
        f.write(text)
    print("props patched")

patch_manifest()
patch_gradle()
patch_props()
print("ALL PATCHES DONE")
