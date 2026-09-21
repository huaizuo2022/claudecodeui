import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/auth_api.dart';
import '../../core/models/auth.dart';
import '../../core/providers.dart';
import '../../core/util/jwt.dart';
import '../../core/util/logger.dart';

enum AuthStatus { bootstrapping, unauthenticated, authenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.bootstrapping,
    this.user,
    this.serverUrl,
    this.token,
    this.busy = false,
    this.error,
    this.notice,
  });

  final AuthStatus status;
  final AuthUser? user;
  final String? serverUrl;
  final String? token;

  /// A login or probe is in flight.
  final bool busy;

  /// Message from the last failed action, shown on the login page.
  final String? error;

  /// Message shown once on arrival, e.g. "登录已过期".
  final String? notice;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? serverUrl,
    String? token,
    bool? busy,
    String? error,
    String? notice,
    bool clearError = false,
    bool clearNotice = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      serverUrl: serverUrl ?? this.serverUrl,
      token: token ?? this.token,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }
}

/// Owns the session for the whole app: restores a stored token at startup,
/// performs login, and reacts to the server's expiry/refresh signals.
class AuthController extends Notifier<AuthState> {
  static const _log = Logger('auth');

  @override
  AuthState build() {
    final client = ref.read(apiClientProvider);
    client.onTokenRefreshed = _persistRefreshedToken;
    client.onSessionExpired = _handleSessionExpired;
    Future.microtask(restoreSession);
    return const AuthState();
  }

  /// Startup path: a usable stored token goes straight to the app shell, and
  /// the server is asked in the background to confirm the user still exists.
  Future<void> restoreSession() async {
    final prefs = ref.read(prefsStoreProvider);
    final secure = ref.read(secureStoreProvider);
    final serverUrl = prefs.serverUrl;
    final token = await secure.readAuthToken();

    if (serverUrl == null || serverUrl.isEmpty || token == null || token.isEmpty) {
      state = AuthState(status: AuthStatus.unauthenticated, serverUrl: serverUrl);
      return;
    }

    final payload = decodeJwt(token);
    if (payload == null || payload.isExpired) {
      await secure.clearAuthToken();
      state = AuthState(
        status: AuthStatus.unauthenticated,
        serverUrl: serverUrl,
        notice: payload == null ? '登录信息无法识别，请重新登录' : '登录已过期，请重新登录',
      );
      return;
    }

    final client = ref.read(apiClientProvider);
    client.configure(serverUrl: serverUrl, token: token);
    state = AuthState(
      status: AuthStatus.authenticated,
      serverUrl: serverUrl,
      token: token,
      user: AuthUser(id: payload.userId ?? '', username: payload.username ?? ''),
    );

    try {
      final user = await ref.read(authApiProvider).me();
      state = state.copyWith(user: user);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _clearSession(notice: '登录状态已失效，请重新登录');
      } else {
        // Offline start is allowed; the session list shows its own retry state.
        _log.warn('could not verify session: ${error.message}');
      }
    }
  }

  /// Runs the login page's "test connection" action against a throwaway client
  /// so the shared client keeps pointing at the configured server.
  Future<ServerAuthStatus> probe(String serverUrl) async {
    final probe = ApiClient();
    try {
      probe.configure(serverUrl: serverUrl);
      return await AuthApi(probe).status();
    } finally {
      probe.close();
    }
  }

  Future<bool> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final normalized = ApiClient.normalizeServerUrl(serverUrl);
    if (normalized.isEmpty) {
      state = state.copyWith(error: '请填写服务器地址', clearNotice: true);
      return false;
    }
    if (username.isEmpty || password.isEmpty) {
      state = state.copyWith(error: '请填写用户名和密码', clearNotice: true);
      return false;
    }

    state = state.copyWith(busy: true, clearError: true, clearNotice: true);
    final client = ref.read(apiClientProvider);
    client.clearToken();
    client.configure(serverUrl: normalized);

    try {
      final result = await AuthApi(client).login(username: username, password: password);
      if (result.token.isEmpty) {
        throw ApiException(message: '服务器没有返回登录凭证');
      }
      await ref.read(secureStoreProvider).writeAuthToken(result.token);
      await ref.read(prefsStoreProvider).setServerUrl(normalized);
      client.configure(serverUrl: normalized, token: result.token);
      state = AuthState(
        status: AuthStatus.authenticated,
        serverUrl: normalized,
        token: result.token,
        user: result.user,
      );
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        busy: false,
        error: error.message,
        serverUrl: normalized,
      );
      return false;
    }
  }

  Future<void> logout({String? notice}) async {
    state = state.copyWith(busy: true);
    await _clearSession(notice: notice);
  }

  Future<void> _clearSession({String? notice}) async {
    await ref.read(secureStoreProvider).clearAuthToken();
    final client = ref.read(apiClientProvider);
    client.clearToken();
    state = AuthState(
      status: AuthStatus.unauthenticated,
      serverUrl: ref.read(prefsStoreProvider).serverUrl,
      notice: notice,
    );
  }

  void clearNotice() {
    if (state.notice != null) state = state.copyWith(clearNotice: true);
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  void _persistRefreshedToken(String token) {
    ref.read(secureStoreProvider).writeAuthToken(token);
    if (state.isAuthenticated) state = state.copyWith(token: token);
  }

  void _handleSessionExpired() {
    if (state.status == AuthStatus.unauthenticated) return;
    _log.warn('server reported the session expired');
    _clearSession(notice: '登录状态已失效，请重新登录');
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Convenience for widgets that only need to know whether to show the shell.
final isAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider).isAuthenticated,
);
