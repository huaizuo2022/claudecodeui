import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credentials remembered so the app can log itself back in without showing a
/// form again. This is a single-user, self-hosted app: the token expires after
/// 7 idle days, and past that the stored password is what keeps the login
/// screen from ever coming back.
class StoredCredentials {
  const StoredCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

/// Secret storage seam, so tests can swap in an in-memory implementation.
abstract interface class SecureStore {
  Future<String?> readAuthToken();
  Future<void> writeAuthToken(String token);
  Future<void> clearAuthToken();

  Future<StoredCredentials?> readCredentials();
  Future<void> writeCredentials({required String username, required String password});
  Future<void> clearCredentials();
}

/// Keychain-backed implementation.
///
/// The web client keeps the token under `localStorage['auth-token']`, which is
/// also the key the app injects into the WebView fallback so both halves of the
/// app share one login.
class KeychainSecureStore implements SecureStore {
  KeychainSecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const authTokenKey = 'auth_token';
  static const _usernameKey = 'auth_username';
  static const _passwordKey = 'auth_password';

  @override
  Future<String?> readAuthToken() => _storage.read(key: authTokenKey);

  @override
  Future<void> writeAuthToken(String token) =>
      _storage.write(key: authTokenKey, value: token);

  @override
  Future<void> clearAuthToken() => _storage.delete(key: authTokenKey);

  @override
  Future<StoredCredentials?> readCredentials() async {
    final username = await _storage.read(key: _usernameKey);
    final password = await _storage.read(key: _passwordKey);
    if (username == null || username.isEmpty || password == null || password.isEmpty) {
      return null;
    }
    return StoredCredentials(username: username, password: password);
  }

  @override
  Future<void> writeCredentials({required String username, required String password}) async {
    await _storage.write(key: _usernameKey, value: username);
    await _storage.write(key: _passwordKey, value: password);
  }

  @override
  Future<void> clearCredentials() async {
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
  }
}
