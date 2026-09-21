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

  /// Message from the last failed action, shown on the configuration page.
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

/// Owns the session for the whole app.
///
/// This is a personal, single-user setup, so the goal is that the
/// configuration form is seen *once*: the token is kept in the Keychain and the
/// server refreshes it inline on every request, and the username/password are
/// remembered so an expired token is re-acquired silently instead of asking.
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

  /// Startup path: a usable stored token goes straight to the app shell; with
  /// no usable token the remembered credentials are used silently, and only a
  /// failure of *that* surfaces the configuration page.
  Future<void> restoreSession() async {
    final prefs = ref.read(prefsStoreProvider);
    final secure = ref.read(secureStoreProvider);
    final serverUrl = prefs.serverUrl;

    if (serverUrl == null || serverUrl.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }

    final token = await secure.readAuthToken();
    if (token != null && token.isNotEmpty) {
      final payload = decodeJwt(token);
      if (payload != null && !payload.isExpired) {
        final client = ref.read(apiClientProvider);
        client.configure(serverUrl: serverUrl, token: token);
        state = AuthState(
          status: AuthStatus.authenticated,
          serverUrl: serverUrl,
          token: token,
          user: AuthUser(id: payload.userId ?? '', username: payload.username ?? ''),
        );
        await _verifySession();
        return;
      }
      await secure.clearAuthToken();
    }

    final credentials = await secure.readCredentials();
    if (credentials == null) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        serverUrl: serverUrl,
        notice: '登录已失效，请重新配置一次',
      );
      return;
    }

    _log.info('no usable token; logging in silently');
    final ok = await _authenticate(
      serverUrl: serverUrl,
      username: credentials.username,
      password: credentials.password,
      silent: true,
      persistCredentials: false,
    );
    if (!ok) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        serverUrl: serverUrl,
        error: '自动登录失败，请检查服务器地址或网络',
      );
    }
  }

  /// Runs the configuration page's "test connection" action against a
  /// throwaway client so the shared client keeps pointing at the live server.
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
  }) {
    return _authenticate(
      serverUrl: serverUrl,
      username: username,
      password: password,
      silent: false,
      persistCredentials: true,
    );
  }

  Future<bool> _authenticate({
    required String serverUrl,
    required String username,
    required String password,
    required bool silent,
    required bool persistCredentials,
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

    if (!silent) {
      state = state.copyWith(busy: true, clearError: true, clearNotice: true);
    }

    final client = ref.read(apiClientProvider);
    client.clearToken();
    client.configure(serverUrl: normalized);

    try {
      final result = await ref.read(authApiProvider).login(
            username: username,
            password: password,
          );
      if (result.token.isEmpty) {
        throw ApiException(message: '服务器没有返回登录凭证');
      }
      final secure = ref.read(secureStoreProvider);
      await secure.writeAuthToken(result.token);
      if (persistCredentials) {
        await secure.writeCredentials(username: username, password: password);
      }
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
      _log.warn('login failed: ${error.message}');
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        busy: false,
        error: error.message,
        serverUrl: normalized,
      );
      return false;
    }
  }

  /// Confirms the stored user still exists. A 401 means the token died between
  /// the local expiry check and now, so the credentials get one silent retry.
  Future<void> _verifySession() async {
    try {
      final user = await ref.read(authApiProvider).me();
      state = state.copyWith(user: user);
    } on ApiException catch (error) {
      if (!error.isUnauthorized) {
        // Offline start is allowed; the session list shows its own retry state.
        _log.warn('could not verify session: ${error.message}');
        return;
      }
      await _recoverSession(notice: '登录状态已失效，正在自动重新登录');
    }
  }

  /// Deep-cleans the session: used by the settings page's explicit logout.
  Future<void> logout() async {
    state = state.copyWith(busy: true);
    await ref.read(secureStoreProvider).clearCredentials();
    await _clearSession();
  }

  Future<void> _recoverSession({String? notice}) async {
    final secure = ref.read(secureStoreProvider);
    final serverUrl = ref.read(prefsStoreProvider).serverUrl;
    final credentials = await secure.readCredentials();

    if (serverUrl == null || serverUrl.isEmpty || credentials == null) {
      await _clearSession(notice: notice);
      return;
    }

    final ok = await _authenticate(
      serverUrl: serverUrl,
      username: credentials.username,
      password: credentials.password,
      silent: true,
      persistCredentials: false,
    );
    if (!ok) await _clearSession(notice: notice);
  }

  Future<void> _clearSession({String? notice}) async {
    await ref.read(secureStoreProvider).clearAuthToken();
    ref.read(apiClientProvider).clearToken();
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
    _log.warn('server reported the session expired; trying a silent re-login');
    _recoverSession(notice: '登录已过期，正在自动重新登录');
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
