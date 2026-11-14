import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zeus_vpn/core/credential_vault.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const key = 'zeus_keystore_migration_integration_test';
  const initialValue = 'legacy-vless://private-subscription-token';
  const updatedValue = 'new-encrypted-wireguard-profile';

  testWidgets('Android Keystore encrypts, migrates, updates and deletes credentials',
      (_) async {
    final preferences = await SharedPreferences.getInstance();
    final secureStore = PlatformSecureKeyValueStore();
    final vault = CredentialVault(storage: secureStore);

    await secureStore.delete(key);
    await preferences.remove(key);

    // Simulate the plaintext value left by a pre-Keystore app version.
    await preferences.setString(key, initialValue);
    expect(preferences.getString(key), initialValue);

    final migrated = await vault.readAndMigrate(preferences, key);

    expect(migrated, initialValue);
    expect(await secureStore.read(key), initialValue);
    expect(
      preferences.getString(key),
      isNull,
      reason: 'Plaintext must be removed only after Android Keystore write succeeds.',
    );

    // New values must remain in secure storage only.
    await vault.write(preferences, key, updatedValue);
    expect(await secureStore.read(key), updatedValue);
    expect(preferences.getString(key), isNull);

    // Delete the encrypted value explicitly and verify it is gone.
    await vault.delete(preferences, key);
    expect(await secureStore.read(key), isNull);
    expect(preferences.getString(key), isNull);
  });
}
