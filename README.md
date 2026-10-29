# ZEUS VPN

A Flutter/Android VPN client prototype using `flutter_v2ray_client`, subscription feeds, VLESS/Trojan/VMess links, optional Cloudflare WARP registration, and a configurable PATT-NG interface.

## Current status

- The current work is isolated on the `audit/hardening-2026-10-29` branch and in [draft pull request #2](https://github.com/abolboy/zeus_vpn_app/pull/2).
- CI performs Dart analysis, unit tests, and a **debug verification APK** build. A successful CI build does not prove that VPN traffic, Android background behavior, WARP registration, or all server protocols work on a physical device.
- The main branch has not been modified by the audit branch.
- Release publishing is intentionally disabled until release signing is moved to a dedicated, protected key and the upgrade path for existing installations is confirmed.

## Features in the current prototype

- VLESS, Trojan, and VMess subscription-link parsing
- Subscription refresh, node selection, TCP reachability checks, and core-based delay checks
- V2Ray client connection state and traffic statistics
- Optional WARP device registration and configuration injection
- PATT-NG configuration controls for selected transport and TLS-related settings
- Local settings persistence

## Security notes

- Subscription URLs must use HTTPS. A feed may contain access credentials; avoid sharing them publicly.
- Subscription URLs, selected server URI, and WARP configuration are migrated to Android Keystore-backed encrypted storage. If secure storage is unavailable during migration, the app retains legacy local values and reports a warning rather than deleting them.
- `ci/keystore.b64` was removed from the current audit branch and ignored for future commits. The public repository history may still contain the old file; removing it from the latest tree does not revoke it or remove it from old clones.
- Do not treat a debug APK as a release build. Do not publish a new signing identity until existing installation upgrade compatibility has been assessed.

## Build and verify

The CI workflow recreates Android project scaffolding from Flutter, applies `tools/patch_android.py`, resolves packages, then runs:

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

The generated APK is uploaded as a workflow artifact for verification only.

## Known limitations before production

- Physical-device validation is still required for connect/disconnect, network changes, Android foreground-service behavior, battery use, DNS/routing, and recovery after process termination.
- WARP API registration is an external integration and must be tested against current Cloudflare behavior; successful registration alone does not verify tunnel traffic.
- Release signing, signing-key rotation, a reproducible release pipeline, and a full upgrade test remain outstanding.
- A security review should verify every PATT-NG field against the exact core version embedded by the dependency before presenting those controls as universally supported.

## Contributing

Keep fixes isolated in a branch, require CI to pass, and do not commit keystores, subscription tokens, server URIs, private keys, or generated signing files.
