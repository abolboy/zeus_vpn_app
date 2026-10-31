  name: Build ZEUS VPN

  on:
    push:
      branches: [main]
    workflow_dispatch:

  permissions:
    contents: write

  jobs:
    build:
      runs-on: ubuntu-latest
      timeout-minutes: 40

      steps:
        - name: Checkout
          uses: actions/checkout@v4

        - name: Setup Java
          uses: actions/setup-java@v4
          with:
            distribution: temurin
            java-version: "17"

        - name: Setup Flutter
          uses: subosito/flutter-action@v2
          with:
            channel: stable
            cache: true

        - name: Create Android folder
          run: flutter create --platforms=android --project-name zeus_vpn --org ir.zeus .

        - name: Patch Android files
          run: python3 tools/patch_android.py

        - name: Pub get
          run: flutter pub get

        - name: Analyze
          run: flutter analyze --no-fatal-infos --no-fatal-warnings

        - name: Setup signing
          env:
            KEYSTORE_B64: ${{ secrets.KEYSTORE_B64 }}
            KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
            KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
            KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
          run: |
            set -euo pipefail
            if [ -z "${KEYSTORE_B64:-}" ]; then
              echo "No KEYSTORE_B64 secret -> building with debug signing"
              exit 0
            fi
            echo "$KEYSTORE_B64" | base64 -d > android/app/zeus.jks
            cat > android/key.properties <<EOF
            storePassword=$KEYSTORE_PASSWORD
            keyPassword=$KEY_PASSWORD
            keyAlias=$KEY_ALIAS
            storeFile=zeus.jks
            EOF
            python3 - <<'PY'
            import re, os
            kts = "android/app/build.gradle.kts"
            groovy = "android/app/build.gradle"
            path = kts if os.path.exists(kts) else groovy
            s = open(path, encoding="utf-8").read()
            if "key.properties" in s:
                print("signing already configured"); raise SystemExit
            if path.endswith(".kts"):
                head = (
                  'import java.util.Properties\n'
                  'import java.io.FileInputStream\n'
                  'val keystoreProperties = Properties()\n'
                  'val keystorePropertiesFile = rootProject.file("key.properties")\n'
                  'if (keystorePropertiesFile.exists()) {\n'
                  '    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n'
                  '}\n'
                )
                signing = (
                  '    signingConfigs {\n'
                  '        create("release") {\n'
                  '            keyAlias = keystoreProperties["keyAlias"] as String?\n'
                  '            keyPassword = keystoreProperties["keyPassword"] as String?\n'
                  '            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }\n'
                  '            storePassword = keystoreProperties["storePassword"] as String?\n'
                  '        }\n'
                  '    }\n'
                )
                s = head + s
                s = s.replace("android {", "android {\n" + signing, 1)
                s = re.sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                           'signingConfig = signingConfigs.getByName("release")', s)
            else:
                head = (
                  'def keystoreProperties = new Properties()\n'
                  'def keystorePropertiesFile = rootProject.file("key.properties")\n'
                  'if (keystorePropertiesFile.exists()) {\n'
                  '    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n'
                  '}\n'
                )
                signing = (
                  '    signingConfigs {\n'
                  '        release {\n'
                  '            keyAlias keystoreProperties["keyAlias"]\n'
                  '            keyPassword keystoreProperties["keyPassword"]\n'
                  '            storeFile keystoreProperties["storeFile"] ? file(keystoreProperties["storeFile"]) : null\n'
                  '            storePassword keystoreProperties["storePassword"]\n'
                  '        }\n'
                  '    }\n'
                )
                s = head + s
                s = s.replace("android {", "android {\n" + signing, 1)
                s = re.sub(r'signingConfig\s+signingConfigs\.debug', 'signingConfig signingConfigs.release', s)
            open(path, "w", encoding="utf-8").write(s)
            print("signing configured in", path)
            PY

        - name: Build APK
          run: flutter build apk --release --split-per-abi

        - name: Upload artifacts
          uses: actions/upload-artifact@v4
          with:
            name: zeus-vpn-apks
            path: build/app/outputs/flutter-apk/*.apk
            if-no-files-found: error

        - name: Publish to Releases
          if: github.event_name == 'push' || github.event_name == 'workflow_dispatch'
          env:
            GH_TOKEN: ${{ github.token }}
          run: |
            set -euo pipefail
            TAG="build-${{ github.run_number }}-${{ github.run_attempt }}"
            gh release create "$TAG" \
              build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
              build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk \
              --title "ZEUS VPN Build ${{ github.run_number }}" \
              --generate-notes
