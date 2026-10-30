# Android release signing

The repository must not contain an Android signing keystore or a base64 export of one.

The CI workflow currently builds a **debug verification APK** for automated analysis and testing. It intentionally does not publish a release APK. Before enabling public release builds:

1. Generate a dedicated Android upload/release keystore locally.
2. Store its base64 contents and credentials in GitHub Actions secrets (never in Git files).
3. Add a release-only Gradle signing configuration that reads those secrets at build time.
4. Verify the signing certificate fingerprint and retain an offline backup of the keystore.
5. Test upgrade installation from the currently distributed APK before changing the signing identity.

A keystore that has been committed to a public repository must be treated as exposed. Removing it from the current branch does not remove it from Git history or existing clones. If the old key signed APKs already installed by users, replacing it can prevent in-place upgrades; plan the migration before distributing a newly signed build.
