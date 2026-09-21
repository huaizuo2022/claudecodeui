import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/messages_api.dart';
import 'config.dart';
import 'storage/prefs_store.dart';
import 'storage/secure_store.dart';
import 'ws/chat_socket.dart' show ChatSocket, SocketConnectionState;

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
/// react to drops. Mirrors the socket's current value through a callback —
/// a broadcast stream would drop the initial state for late listeners.
class SocketStateController extends Notifier<SocketConnectionState> {
  @override
  SocketConnectionState build() {
    final socket = ref.watch(chatSocketProvider);
    socket.onStateChanged = (next) {
      if (state != next) state = next;
    };
    ref.onDispose(() {
      if (socket.onStateChanged != null) socket.onStateChanged = null;
    });
    return socket.state;
  }
}

final socketStateProvider =
    NotifierProvider<SocketStateController, SocketConnectionState>(
  SocketStateController.new,
);

final socketConnectedProvider = Provider<bool>(
  (ref) => ref.watch(socketStateProvider) == SocketConnectionState.connected,
);
