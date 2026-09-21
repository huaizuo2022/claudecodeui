import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain-backed storage for the auth token.
///
/// The web client keeps the same value under `localStorage['auth-token']`,
/// which is also the key the app injects into the WebView fallback so both
/// halves of the app share one login.
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const authTokenKey = 'auth_token';

  Future<String?> readAuthToken() => _storage.read(key: authTokenKey);

  Future<void> writeAuthToken(String token) =>
      _storage.write(key: authTokenKey, value: token);

  Future<void> clearAuthToken() => _storage.delete(key: authTokenKey);
}
