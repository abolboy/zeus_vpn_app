# ZEUS VPN credential storage and migration

## What is encrypted

The app stores values that can contain authentication material in `flutter_secure_storage`:

| Key | Sensitive content |
|---|---|
| `subs_v2` | Subscription URLs, which can contain credentials or tokens |
| `nodes_cache` | Server share URIs, user identifiers, passwords, and subscription references |
| `sel` | The active server share URI |
| `warp_json` | WireGuard private key, peer details, Cloudflare token and device metadata |
| `settings_json` | Includes the optional chained-server URI and other connection settings |

Non-secret UI and protocol preferences such as `patt_json`, and the boolean WARP toggle, remain in SharedPreferences.

On Android, `flutter_secure_storage` uses Android Keystore-backed RSA-OAEP key wrapping and AES-GCM data encryption by default. The app enables crash-resilient migration backups and sets `resetOnError: false`, so a Keystore/decryption error is surfaced instead of silently resetting the encrypted store. The storage is device-bound; it is not a cloud sync service and does not export the Android Keystore key. Android Auto Backup is disabled so ciphertext is not restored without its original Keystore key.

## First-launch migration

The migration is automatic and idempotent:

1. Read an encrypted value first.
2. If it exists, use it and remove a remaining plaintext duplicate.
3. Otherwise read the legacy SharedPreferences value.
4. Write that value to secure storage.
5. Only after the secure write succeeds, remove the plaintext value.
6. If secure storage is unavailable or the write fails, keep the old value and report a warning. New writes do not fall back to plaintext.

The migration code is covered by tests for successful movement, failure retention, precedence of an already encrypted value, secure-only new writes, and deletion ordering.

## Reinstall and device transfer

Because the Android Keystore key belongs to the device/app installation, encrypted credentials are not a portable backup. With Android Auto Backup disabled, a reinstall or move to another phone may require re-adding subscription URLs and importing the WireGuard profile again. Keep the original client `.conf` in a separate encrypted password manager or secure offline location.

## Clipboard backup warning

The legacy `ZEUS-BACKUP` clipboard export contains subscription URLs. It is Base64-encoded JSON, not encrypted data. ZEUS now displays a warning and requires confirmation before copying it. Do not post this text in public issues, group chats, screenshots, or Git repositories.

A password-protected backup format is a separate feature and must not be confused with this legacy Base64 export.

## Android version requirement

This build uses `flutter_secure_storage 11.2.0` and is verified with Flutter 3.50.0 / Dart 3.13.0. The project targets Android API 24 or newer. The generated Android Gradle configuration is patched to enforce minSdk 24, and CI verifies the patch is present.
