# ZEUS VPN

ZEUS VPN is a Flutter Android VPN client built on `flutter_v2ray_client` and Xray. The current application supports VLESS, VMess, Trojan, Shadowsocks, SOCKS, subscription feeds, Cloudflare WARP, and configurable PATT-NG options.

## Current verification status

- Pull requests and pushes to `main` run Dart analysis, unit/widget tests, and a debug APK build.
- The debug APK uses the `.debug` application-ID suffix and can be installed beside a release build without replacing its app data.
- CI uploads the debug APK as a short-lived verification artifact. It is not a production release.
- Automatic APK publishing on every push is disabled. A public release now requires a manual workflow dispatch, all signing secrets, and a pinned signing-certificate fingerprint.
- A successful CI run does not prove real-world VPN traffic, recovery after network changes, WARP behavior, physical-device background service behavior, or upgrade compatibility.

## Security baseline

- Subscription URLs are accepted only over HTTPS. HTTP redirects are disabled for subscription downloads.
- Individual VLESS, VMess, Trojan, Shadowsocks and SOCKS share links can be added directly from the server list without creating an HTTPS subscription. Manually added servers are stored with the server cache and remain present after subscription refreshes.
- Standard single-peer WireGuard `.conf` profiles can be imported. The app preserves the Interface address, DNS, supported MTU, Peer endpoint, public key, optional preshared key, AllowedIPs, and PersistentKeepalive when generating the Xray WireGuard outbound.
- Imported WireGuard profiles are not treated as Cloudflare WARP registrations: Cloudflare endpoint rotation is disabled for them, so an AWS endpoint is never silently replaced with a Cloudflare endpoint.
- The current importer intentionally rejects configurations with multiple `[Peer]` sections. Import a client profile with one server peer per app profile.
- Android cleartext traffic is disabled in the generated manifest.
- Android Auto Backup is disabled. This avoids restoring app data that may depend on device-local cryptographic keys.
- Signing material must never be committed. The workflow checks tracked files for keystores and password-bearing signing files.
- A keystore export was previously committed to repository history. The currently configured GitHub Actions signing secret must be verified by certificate fingerprint before it is used for another public release. The existence of signing secrets alone does not prove that the active signing identity is safe or compatible with installed copies.
- Do not rotate the release key blindly. First compare the current certificate identity with the historical exposed key and decide whether existing installs must continue receiving in-place updates.

## Build locally

Requires Flutter stable and JDK 17.

```sh
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
```

For a local release build, configure the same dedicated signing identity used by the intended distribution channel. Never use a default debug keystore for a public release.

## Controlled GitHub release

The `Build and Verify ZEUS VPN` workflow only publishes when manually dispatched with `publish_release=true`.

Configure these GitHub Actions secrets:

| Secret | Purpose |
|---|---|
| `KEYSTORE_B64` | Base64-encoded Android keystore |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Release key alias |
| `KEY_PASSWORD` | Release key password |

Also configure the repository variable `ANDROID_RELEASE_CERT_SHA256` with the approved certificate SHA-256 fingerprint, without colons or with colons (both formats are accepted). The release job compares the certificate inside the keystore with this pinned value and stops if they differ or if the value is missing.

See [docs/RELEASE_SIGNING.md](docs/RELEASE_SIGNING.md) before creating or rotating a release key.

## Important production checks still required

- Physical-device testing of connect/disconnect, traffic routing, DNS, IPv4/IPv6, sleep/resume, mobile-network changes, and battery use.
- Real traffic validation for every supported protocol and advanced transport option against the exact embedded Xray version.
- WARP registration and tunnel validation against current Cloudflare behavior.
- AWS WireGuard client-profile validation against the actual server peer, firewall/security-group UDP port, forwarding/NAT policy, and the exact AllowedIPs required by the intended split- or full-tunnel design.
- Release certificate continuity and upgrade testing on a device that has the previously distributed APK installed.
- A verified encrypted export/import process before promising seamless credential migration between devices.

