#!/usr/bin/env python3
"""Patch Flutter-generated Android files for ZEUS VPN.

The patch is idempotent. It enforces a branded app label, disables Android
Auto Backup and cleartext HTTP, preserves native Xray library packaging,
adds the ZEUS launcher resources, and isolates debug installs from releases.
"""
import os
import re
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


def _set_application_attribute(text: str, name: str, value: str) -> str:
    pattern = re.compile(r'android:' + re.escape(name) + r'="[^"]*"')
    replacement = f'android:{name}="{value}"'
    if pattern.search(text):
        return pattern.sub(replacement, text, count=1)
    if "<application" not in text:
        sys.exit("ERROR: application element not found in Android manifest")
    return text.replace("<application", f"<application {replacement}", 1)


def patch_manifest() -> None:
    if not os.path.exists(MANIFEST):
        sys.exit("ERROR: manifest not found: " + MANIFEST)
    with open(MANIFEST, encoding="utf-8") as f:
        text = f.read()
    original = text

    missing = [permission for permission in PERMS if permission not in text]
    if missing and "<application" in text:
        insert = "".join(
            f'    <uses-permission android:name="{permission}" />\n'
            for permission in missing
        )
        text = text.replace("<application", insert + "    <application", 1)

    text = _set_application_attribute(text, "label", "ZEUS VPN")
    text = _set_application_attribute(text, "allowBackup", "false")
    text = _set_application_attribute(text, "usesCleartextTraffic", "false")
    if "android:extractNativeLibs" not in text and "<application" in text:
        text = text.replace(
            "<application",
            '<application android:extractNativeLibs="true"',
            1,
        )

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


def patch_min_sdk() -> None:
    """Keep app minimum Android API aligned with flutter_secure_storage v11+."""
    path = GRADLE_KTS if os.path.exists(GRADLE_KTS) else GRADLE_GROOVY
    if not os.path.exists(path):
        sys.exit("ERROR: gradle file not found")
    with open(path, encoding="utf-8") as f:
        text = f.read()

    if path.endswith(".kts"):
        expected = "minSdk = maxOf(flutter.minSdkVersion, 24)"
        candidates = (
            ("minSdk = flutter.minSdkVersion", expected),
            ("minSdk = 21", expected),
            ("minSdk = 23", expected),
        )
    else:
        expected = "minSdkVersion Math.max(flutter.minSdkVersion, 24)"
        candidates = (
            ("minSdkVersion flutter.minSdkVersion", expected),
            ("minSdkVersion 21", expected),
            ("minSdkVersion 23", expected),
        )

    if expected in text:
        print("minimum Android SDK already set to API 24 or higher")
        return
    for old, replacement in candidates:
        if old in text:
            text = text.replace(old, replacement, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            print("minimum Android SDK raised to API 24")
            return
    sys.exit("ERROR: unable to safely identify Android minSdk declaration")


def patch_debug_application_id() -> None:
    path = GRADLE_KTS if os.path.exists(GRADLE_KTS) else GRADLE_GROOVY
    if not os.path.exists(path):
        sys.exit("ERROR: gradle file not found")
    with open(path, encoding="utf-8") as f:
        text = f.read()

    expected = (
        'applicationIdSuffix = ".debug"'
        if path.endswith(".kts")
        else 'applicationIdSuffix ".debug"'
    )
    if expected in text:
        print("debug application ID suffix already ok")
        return
    if "applicationIdSuffix" in text:
        sys.exit("ERROR: unexpected applicationIdSuffix already exists")

    match = re.search(r"(?m)^([ \t]*)buildTypes\s*\{", text)
    if match is None:
        sys.exit("ERROR: buildTypes block not found")

    indent = match.group(1)
    if path.endswith(".kts"):
        block = (
            '\n' + indent + '    getByName("debug") {\n'
            + indent + '        applicationIdSuffix = ".debug"\n'
            + indent + '    }\n'
        )
    else:
        block = (
            '\n' + indent + '    debug {\n'
            + indent + '        applicationIdSuffix ".debug"\n'
            + indent + '    }\n'
        )
    text = text[:match.end()] + block + text[match.end():]
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("debug application ID suffix configured")


def patch_props() -> None:
    if not os.path.exists(PROPS):
        print("props ok (missing)")
        return
    with open(PROPS, encoding="utf-8") as f:
        lines = f.readlines()
    kept = [line for line in lines if "enableUncompressedNativeLibs" not in line]
    if len(kept) != len(lines):
        with open(PROPS, "w", encoding="utf-8") as f:
            f.write("".join(kept))
        print("props cleaned")
    else:
        print("props ok")


LINT_MARK = "ZEUS: lint-vital-off"


def patch_lint() -> None:
    """Disable the Android Lint tasks known to crash on the JDK 17 CI runner."""
    kts = os.path.join("android", "build.gradle.kts")
    groovy = os.path.join("android", "build.gradle")
    if os.path.isfile(kts):
        path = kts
        block = (
            "\n// " + LINT_MARK + "\n"
            "subprojects {\n"
            "    tasks.configureEach {\n"
            '        if (name.startsWith("lintVital") || name.startsWith("lintAnalyze") || name == "lint") {\n'
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
    """Copy the ZEUS launcher icon resources over Flutter defaults."""
    if not os.path.isdir(ICONS_SRC):
        print("icons: no tools/icons folder, skipped")
        return
    if not os.path.isdir(RES_DIR):
        sys.exit("ERROR: res folder not found: " + RES_DIR)
    count = 0
    for root, _dirs, files in os.walk(ICONS_SRC):
        rel = os.path.relpath(root, ICONS_SRC)
        destination = RES_DIR if rel == "." else os.path.join(RES_DIR, rel)
        os.makedirs(destination, exist_ok=True)
        for name in files:
            shutil.copy2(os.path.join(root, name), os.path.join(destination, name))
            count += 1
    print(f"icons copied: {count} files")


if __name__ == "__main__":
    patch_manifest()
    patch_gradle()
    patch_props()
    patch_icons()
    patch_lint()
    patch_min_sdk()
    patch_debug_application_id()
    print("ALL PATCHES DONE")
