import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/messages_api.dart';
import 'config.dart';
import 'storage/prefs_store.dart';
import 'storage/secure_store.dart';
import 'ws/chat_socket.dart';

/// Build-time seed token, as a provider purely so tests can substitute it.
final bootstrapTokenProvider = Provider<String>((ref) => bootstrapToken);

/// Server address paired with the seed token above.
final bootstrapServerUrlProvider = Provider<String>((ref) => defaultServerUrl);

/// Overridden in `main()` once `SharedPreferences` have loaded.
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

final messagesApiProvider = Provider<MessagesApi>(
  (ref) => MessagesApi(ref.watch(apiClientProvider)),
);

/// The app's single chat websocket. Kept as a plain provider: its lifecycle is
/// driven by the auth state (connect on login, close on logout).
final chatSocketProvider = Provider<ChatSocket>((ref) {
  final socket = ChatSocket();
  ref.onDispose(socket.close);
  return socket;
});

/// Connection state as a provider so widgets (chat strip, list states) can
/// react to drops without touching the socket directly.
final socketStateProvider = StreamProvider<SocketConnectionState>(
  (ref) => ref.watch(chatSocketProvider).states,
);

final socketConnectedProvider = Provider<bool>(
  (ref) => ref.watch(socketStateProvider).value == SocketConnectionState.connected,
);
