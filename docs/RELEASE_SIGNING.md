# ZEUS VPN release signing procedure

## Why release signing is gated

A keystore export was previously committed to this public repository's history. Removing the file from the latest tree does not remove historical copies. The currently configured GitHub Actions secret may or may not use the same certificate; its identity must be checked rather than assumed.

A recent CI execution showed that signing secrets were configured and a release APK was built. That does not establish which certificate was used or whether it matches the historical exposed key.

## Before enabling a release

1. Obtain the current intended release keystore from its secure offline source. Do not retrieve or recreate signing material from a public repository history.
2. Inspect the signing certificate locally:
   ```sh
   keytool -list -v -keystore /secure/path/zeus-release.jks -alias YOUR_ALIAS
   ```
3. Compare the SHA-256 fingerprint with the certificate on a previously distributed APK and with the historical exposed signing identity. Do not rotate until the upgrade impact is understood.
4. If a new key is required, document the migration decision. Android may reject an in-place update when the signing identity changes.
5. Back up the approved keystore offline in at least two protected locations.
6. Add the keystore and credentials as the four GitHub Actions secrets documented in the README.
7. Add the approved certificate fingerprint as the repository variable `ANDROID_RELEASE_CERT_SHA256`.
8. Run the workflow manually with `publish_release=true` only after the preceding checks are complete.

The release workflow fails closed if any secret is missing or if the actual certificate fingerprint differs from the pinned repository variable.

## Never

- Commit a keystore, Base64 keystore export, signing properties file, private key, or password to Git.
- Use Android's public/default debug keystore for a production release.
- Publish a release merely because a build succeeded.
- Rotate a signing key without testing the update path for installed users.
