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
    if 'android:label=' in text:
        text = re.sub(
            r'android:label="[^"]*"',
            'android:label="ZEUS VPN"',
            text,
            count=1,
        )
    elif "<application" in text:
        text = text.replace("<application", '<application android:label="ZEUS VPN"', 1)
    if 'android:icon=' in text:
        text = re.sub(
            r'android:icon="[^"]*"',
            'android:icon="@drawable/zeus_app_icon"',
            text,
            count=1,
        )
    elif "<application" in text:
        text = text.replace(
            "<application",
            '<application android:icon="@drawable/zeus_app_icon"',
            1,
        )
    if "android:extractNativeLibs" not in text and "<application" in text:
        text = text.replace("<application", '<application android:extractNativeLibs="true"', 1)
    if text != original:
        with open(MANIFEST, "w", encoding="utf-8") as f:
            f.write(text)
        print("manifest patched")
    else:
        print("manifest already ok")

def patch_launcher_assets():
    drawable_dir = p("android", "app", "src", "main", "res", "drawable")
    os.makedirs(drawable_dir, exist_ok=True)

    icon_path = os.path.join(drawable_dir, "zeus_app_icon.xml")
    icon_xml = """<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="48dp"
    android:height="48dp"
    android:viewportWidth="48"
    android:viewportHeight="48">
    <path
        android:fillColor="#030308"
        android:pathData="M24,2 C36.15,2 46,11.85 46,24 C46,36.15 36.15,46 24,46 C11.85,46 2,36.15 2,24 C2,11.85 11.85,2 24,2 Z" />
    <path
        android:fillColor="#00000000"
        android:strokeColor="#00F0FF"
        android:strokeWidth="1.5"
        android:pathData="M24,2 C36.15,2 46,11.85 46,24 C46,36.15 36.15,46 24,46 C11.85,46 2,36.15 2,24 C2,11.85 11.85,2 24,2 Z" />
    <path
        android:fillColor="#00F0FF"
        android:pathData="M27,6 L12,27 L22,27 L19,42 L36,19 L26,19 Z" />
    <path
        android:fillColor="#FF007F"
        android:pathData="M29,7 L25,16 L28,16 L24,23 L33,15 L29,15 Z" />
</vector>
"""
    splash_path = os.path.join(drawable_dir, "launch_background.xml")
    splash_xml = """<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="#030308" />
    <item
        android:drawable="@drawable/zeus_app_icon"
        android:gravity="center" />
</layer-list>
"""
    for path, content in ((icon_path, icon_xml), (splash_path, splash_xml)):
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
    print("ZEUS launcher icon and dark splash assets patched")

def patch_gradle():
    path = GRADLE_KTS if os.path.exists(GRADLE_KTS) else GRADLE_GROOVY
    if not os.path.exists(path):
        print("ERROR: gradle file not found")
        sys.exit(1)
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    if "useLegacyPackaging" in text:
        print("gradle already ok")
    else:
        block = "    packaging {\n        jniLibs {\n            useLegacyPackaging = true\n        }\n    }\n"
        if "android {" in text:
            text = text.replace("android {", "android {\n" + block, 1)
        else:
            text += "\nandroid {\n" + block + "}\n"
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        print("gradle patched: " + path)

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

patch_manifest()
patch_launcher_assets()
patch_gradle()
clean_props()
print("ALL PATCHES DONE")
