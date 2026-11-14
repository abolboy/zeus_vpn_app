import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal interface so migration behavior can be tested without Android channels.
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android uses RSA-OAEP key wrapping and AES-GCM data encryption by default.
/// Migration backup makes cipher upgrades recoverable if the app is interrupted.
class PlatformSecureKeyValueStore implements SecureKeyValueStore {
  PlatformSecureKeyValueStore()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(migrateWithBackup: true),
        );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Moves old SharedPreferences values to encrypted platform storage.
///
/// Important ordering: encrypted write must succeed before the plaintext
/// legacy value is removed. A failed migration returns the old value for this
/// session and leaves it untouched so an update cannot destroy credentials.
class CredentialVault {
  CredentialVault({
    required SecureKeyValueStore storage,
    void Function(String key, Object error)? onMigrationError,
  })  : _storage = storage,
        _onMigrationError = onMigrationError;

  final SecureKeyValueStore _storage;
  final void Function(String key, Object error)? _onMigrationError;

  Future<void> _removeLegacy(SharedPreferences preferences, String key) async {
    if (!preferences.containsKey(key)) return;
    try {
      final removed = await preferences.remove(key);
      if (!removed) {
        throw StateError('Legacy preference "$key" could not be removed');
      }
    } catch (error) {
      _onMigrationError?.call(key, error);
    }
  }

  /// Read encrypted value, or migrate the same key from SharedPreferences.
  Future<String?> readAndMigrate(
    SharedPreferences preferences,
    String key,
  ) async {
    String? encryptedValue;
    try {
      encryptedValue = await _storage.read(key);
    } catch (error) {
      final legacyValue = preferences.getString(key);
      _onMigrationError?.call(key, error);
      if (legacyValue != null) return legacyValue;
      rethrow;
    }

    if (encryptedValue != null) {
      await _removeLegacy(preferences, key);
      return encryptedValue;
    }

    final legacyValue = preferences.getString(key);
    if (legacyValue == null) return null;

    try {
      await _storage.write(key, legacyValue);
      await _removeLegacy(preferences, key);
    } catch (error) {
      _onMigrationError?.call(key, error);
      // Keep the old value. Do not overwrite it with plaintext or delete it.
    }
    return legacyValue;
  }

  /// New values are written only to secure storage; never fall back to
  /// plaintext SharedPreferences when the Keystore is unavailable.
  Future<void> write(
    SharedPreferences preferences,
    String key,
    String value,
  ) async {
    await _storage.write(key, value);
    await _removeLegacy(preferences, key);
  }

  Future<void> delete(
    SharedPreferences preferences,
    String key,
  ) async {
    await _storage.delete(key);
    await _removeLegacy(preferences, key);
  }
}
