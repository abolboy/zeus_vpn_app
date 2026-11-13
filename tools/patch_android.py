#!/usr/bin/env python3
"""Patch the freshly generated `flutter create` android/ folder for the ZEUS VPN app:

1. AndroidManifest.xml -> add the permissions the VPN service needs
   (INTERNET / POST_NOTIFICATIONS / FOREGROUND_SERVICE[_SPECIAL_USE]),
   enable cleartext traffic and native-lib extraction.
2. app build.gradle(.kts) -> packaging { jniLibs.useLegacyPackaging = true }
   so the bundled Xray .so libraries are never stripped/compressed.
3. gradle.properties -> drop the obsolete enableUncompressedNativeLibs flag.
4. tools/icons/** -> copied over android/app/src/main/res (ZEUS launcher icon, adaptive + legacy).
5. Android Lint tasks (lintVital*, lintAnalyze*) are disabled: lint crashes on JDK 17 with
   NoSuchMethodError List.removeLast() while analysing plugin sources and is not needed to build the APK.

The script is idempotent: running it twice changes nothing the second time.
"""
import os
import shutil
import sys

MANIFEST = os.path.join("android", "app", "src", "main", "AndroidManifest.xml")
GRADLE_KTS = os.path.join("android", "app", "build.gradle.kts")
GRADLE_GROOVY = os.path.join("android", "app", "build.gradle")
PROPS = os.path.join("android", "gradle.properties")
ICONS_SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icons")
RES_DIR = os.path.join("android", "app", "src", "main", "res")
PERMS = [
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
]


def patch_manifest() -> None:
    if not os.path.exists(MANIFEST):
        sys.exit("ERROR: manifest not found: " + MANIFEST)
    with open(MANIFEST, encoding="utf-8") as f:
        text = f.read()
    original = text

    missing = [p for p in PERMS if p not in text]
    if missing and "<application" in text:
        insert = "".join(f'    <uses-permission android:name="{p}" />\n' for p in missing)
        text = text.replace("<application", insert + "    <application", 1)
    if "android:extractNativeLibs" not in text and "<application" in text:
        text = text.replace("<application", '<application android:extractNativeLibs="true"', 1)
    if "android:usesCleartextTraffic" not in text and "<application" in text:
        text = text.replace("<application", '<application android:usesCleartextTraffic="true"', 1)

    if text != original:
        with open(MANIFEST, "w", encoding="utf-8") as f:
            f.write(text)
    print("manifest patched" if text != original else "manifest already ok")


def patch_gradle() -> None:
    path = GRADLE_KTS if os.path.exists(GRADLE_KTS) else GRADLE_GROOVY
    if not os.path.exists(path):
        sys.exit("ERROR: gradle file not found")
    with open(path, encoding="utf-8") as f:
        text = f.read()

    block = (
        "    packaging {\n"
        "        jniLibs {\n"
        "            useLegacyPackaging = true\n"
        "        }\n"
        "    }\n"
    )
    if "useLegacyPackaging" in text:
        print("gradle already ok")
    elif "android {" in text:
        text = text.replace("android {", "android {\n" + block, 1)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        print("gradle patched: " + path)
    else:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text + "\nandroid {\n" + block + "}\n")
        print("gradle patched (appended): " + path)


def patch_props() -> None:
    if not os.path.exists(PROPS):
        print("props ok (missing)")
        return
    with open(PROPS, encoding="utf-8") as f:
        lines = f.readlines()
    kept = [l for l in lines if "enableUncompressedNativeLibs" not in l]
    if lines and len(kept) != len(lines):
        with open(PROPS, "w", encoding="utf-8") as f:
            f.write("".join(kept))
        print("props cleaned")
    else:
        print("props ok")


LINT_MARK = "ZEUS: lint-vital-off"


def patch_lint() -> None:
    """Disable Android Lint tasks in every module (the CI JDK makes lint crash on url_launcher)."""
    kts = os.path.join("android", "build.gradle.kts")
    groovy = os.path.join("android", "build.gradle")
    if os.path.isfile(kts):
        path = kts
        block = (
            "\n// " + LINT_MARK + "\n"
            "subprojects {\n"
            "    tasks.configureEach {\n"
            "        if (name.startsWith(\"lintVital\") || name.startsWith(\"lintAnalyze\") || name == \"lint\") {\n"
            "            enabled = false\n"
            "        }\n"
            "    }\n"
            "}\n"
        )
    elif os.path.isfile(groovy):
        path = groovy
        block = (
            "\n// " + LINT_MARK + "\n"
            "subprojects {\n"
            "    tasks.configureEach { t ->\n"
            "        if (t.name.startsWith('lintVital') || t.name.startsWith('lintAnalyze') || t.name == 'lint') {\n"
            "            t.enabled = false\n"
            "        }\n"
            "    }\n"
            "}\n"
        )
    else:
        print("lint: no root gradle file found, skipped")
        return
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if LINT_MARK in text:
        print("lint: already disabled")
        return
    with open(path, "a", encoding="utf-8") as f:
        f.write(block)
    print("lint tasks disabled in " + path)


def patch_icons() -> None:
    """Copy the ZEUS launcher icon resources over the default Flutter ones."""
    if not os.path.isdir(ICONS_SRC):
        print("icons: no tools/icons folder, skipped")
        return
    if not os.path.isdir(RES_DIR):
        sys.exit("ERROR: res folder not found: " + RES_DIR)
    count = 0
    for root, _dirs, files in os.walk(ICONS_SRC):
        rel = os.path.relpath(root, ICONS_SRC)
        dst_dir = RES_DIR if rel == "." else os.path.join(RES_DIR, rel)
        os.makedirs(dst_dir, exist_ok=True)
        for name in files:
            shutil.copy2(os.path.join(root, name), os.path.join(dst_dir, name))
            count += 1
    print(f"icons copied: {count} files")


if __name__ == "__main__":
    patch_manifest()
    patch_gradle()
    patch_props()
    patch_icons()
    patch_lint()
    print("ALL PATCHES DONE")
