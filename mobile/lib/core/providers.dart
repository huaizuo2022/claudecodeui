import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'config.dart';
import 'storage/prefs_store.dart';
import 'storage/secure_store.dart';

/// Build-time seed token, as a provider purely so tests can substitute it.
final bootstrapTokenProvider = Provider<String>((ref) => bootstrapToken);

/// Server address paired with the seed token above.
final bootstrapServerUrlProvider = Provider<String>((ref) => defaultServerUrl);

/// Overridden in `main()` once `SharedPreferences` has loaded.
final prefsStoreProvider = Provider<PrefsStore>(
  (ref) => throw UnimplementedError('prefsStoreProvider must be overridden'),
);

final secureStoreProvider = Provider<SecureStore>((ref) => KeychainSecureStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.close);
  return client;
});

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);
