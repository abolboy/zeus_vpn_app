# ZEUS VPN

A Flutter/Android VPN client prototype using `flutter_v2ray_client`, subscription feeds, VLESS/Trojan/VMess links, optional Cloudflare WARP registration, and a configurable PATT-NG interface.

## Current status

- The current consolidated work is isolated on `design/zeus-neon-command-center-2026-10-30` and tracked by [draft pull request #3](https://github.com/abolboy/zeus_vpn_app/pull/3). The prior audited baseline is preserved on `backup/pre-ui-overhaul-2026-10-30`.
- CI performs Dart analysis, unit tests, an Android emulator regression test, and a **debug verification APK** build. The debug variant has a `.debug` application-ID suffix so it can be installed alongside a release installation without uninstalling it or sharing its app data. A successful CI build does not prove that VPN traffic, Android background behavior, WARP registration, or all server protocols work on a physical device.
- The main branch has not been modified by the audit branch.
- Release publishing is intentionally disabled until release signing is moved to a dedicated, protected key and the upgrade path for existing installations is confirmed.

## Features in the current prototype

- VLESS, Trojan, and VMess subscription-link parsing
- Subscription refresh, node selection, TCP reachability checks, and core-based delay checks
- V2Ray client connection state and traffic statistics
- Optional Cloudflare WARP-only egress mode. When enabled, it replaces the selected proxy outbound; it is not currently chained with a selected VLESS/Trojan/VMess server.
- Optional WARP device registration and configuration injection
- PATT-NG configuration controls for selected transport and TLS-related settings
- Local settings persistence

## Security notes

- Subscription URLs must use HTTPS. A feed may contain access credentials; avoid sharing them publicly.
- Subscription URLs, selected server URI, and WARP configuration are migrated to Android Keystore-backed encrypted storage. If secure storage is unavailable during migration, the app retains legacy local values and reports a warning rather than deleting them.
- Android Auto Backup is disabled because encrypted secure-storage preferences cannot be safely restored without the original device's Android Keystore key. Users should treat reinstalling or device migration as a credential re-entry event until an explicit encrypted export/import flow exists.
- `ci/keystore.b64` was removed from the current audit branch and ignored for future commits. The old workflow used that public keystore (or generated a default Android debug keystore) to sign release APKs, including published Build 67 and Build 68. Treat that signing identity as compromised. The key remains in Git history and old clones unless history is rewritten, and published APKs remain available until explicitly retired. Removing the file from the latest tree does not revoke the key.
- Do not treat a debug APK as a release build. Do not publish a new signing identity until existing installation upgrade compatibility has been assessed. Rotating the signing key can prevent in-place updates of installed copies; decide whether to preserve compatibility or distribute a separately identified clean install.

## Build and verify

The CI workflow recreates Android project scaffolding from Flutter, applies `tools/patch_android.py`, resolves packages, then runs:

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

The generated APK is uploaded as a workflow artifact for verification only. It uses a separate `.debug` application ID; it is not a release update and cannot be used to validate release signing or in-place upgrades.

## Known limitations before production

- Physical-device validation is still required for connect/disconnect, network changes, Android foreground-service behavior, battery use, DNS/routing, and recovery after process termination.
- WARP API registration is an external integration and must be tested against current Cloudflare behavior; successful registration alone does not verify tunnel traffic.
- Release signing, signing-key rotation, a reproducible release pipeline, and a full upgrade test remain outstanding.
- Direct VLESS/Trojan/VMess inputs are validated locally before being saved; subscription URL secrets are masked in the visible feed inventory.
- The Tools workspace includes a searchable Xray log console with subscription/share-URI and common credential redaction, plus explicit confirmation before clearing the local diagnostic buffer.
- WARP key generation uses the maintained `cryptography` X25519 API and is tested with RFC 7748 vectors.
- Animated dashboard effects pause when the app is backgrounded or another workspace is selected.
- This repository currently ships a single Xray/V2Ray core through `flutter_v2ray_client 3.5.0`; it is not a multi-engine client yet. Sing-box is a separate architecture/licensing decision and is not silently bundled.
- A security review should verify every PATT-NG field against the exact core version embedded by the dependency before presenting those controls as universally supported.

## Contributing

Keep fixes isolated in a branch, require CI to pass, and do not commit keystores, subscription tokens, server URIs, private keys, or generated signing files.
