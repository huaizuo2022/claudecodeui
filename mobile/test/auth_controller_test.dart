import 'dart:convert';

import 'package:cloudcli_mobile/core/api/api_client.dart';
import 'package:cloudcli_mobile/core/api/auth_api.dart';
import 'package:cloudcli_mobile/core/models/auth.dart';
import 'package:cloudcli_mobile/core/providers.dart';
import 'package:cloudcli_mobile/core/storage/prefs_store.dart';
import 'package:cloudcli_mobile/core/storage/secure_store.dart';
import 'package:cloudcli_mobile/features/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _serverUrl = 'http://10.0.0.5:3001';

String _jwt({required int iat, required int exp}) {
  String encode(Map<String, dynamic> payload) =>
      base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}'
      '.${encode({'userId': 1, 'username': 'shang', 'iat': iat, 'exp': exp})}'
      '.sig';
}

String _validToken() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return _jwt(iat: now - 60, exp: now + 7 * 24 * 3600);
}

String _expiredToken() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return _jwt(iat: now - 8 * 24 * 3600, exp: now - 3600);
}

class _MemorySecureStore implements SecureStore {
  String? token;
  String? username;
  String? password;

  @override
  Future<String?> readAuthToken() async => token;

  @override
  Future<void> writeAuthToken(String value) async => token = value;

  @override
  Future<void> clearAuthToken() async => token = null;

  @override
  Future<StoredCredentials?> readCredentials() async {
    if (username == null || password == null) return null;
    return StoredCredentials(username: username!, password: password!);
  }

  @override
  Future<void> writeCredentials({required String username, required String password}) async {
    this.username = username;
    this.password = password;
  }

  @override
  Future<void> clearCredentials() async {
    username = null;
    password = null;
  }
}

class _FakeAuthApi extends AuthApi {
  _FakeAuthApi({this.loginSucceeds = true}) : super(ApiClient());

  bool loginSucceeds;
  int loginCalls = 0;
  int meCalls = 0;
  bool meUnauthorized = false;

  @override
  Future<LoginResult> login({required String username, required String password}) async {
    loginCalls += 1;
    if (!loginSucceeds) {
      throw ApiException(message: '用户名或密码错误', statusCode: 401);
    }
    return LoginResult(token: _validToken(), user: AuthUser(id: '1', username: username));
  }

  @override
  Future<AuthUser> me() async {
    meCalls += 1;
    if (meUnauthorized) {
      throw ApiException(message: '会话已过期', statusCode: 401);
    }
    return const AuthUser(id: '1', username: 'shang');
  }

  @override
  Future<ServerAuthStatus> status() async => const ServerAuthStatus(needsSetup: false);

  @override
  Future<void> refresh() async {}
}

Future<({ProviderContainer container, _MemorySecureStore secure, _FakeAuthApi api})>
    _boot({
  String? serverUrl = _serverUrl,
  String? token,
  String? username,
  String? password,
  bool loginSucceeds = true,
  String seedToken = '',
  String seedServerUrl = _serverUrl,
}) async {
  SharedPreferences.setMockInitialValues(
    serverUrl == null ? {} : {'server_url': serverUrl},
  );
  final prefs = await SharedPreferences.getInstance();
  final secure = _MemorySecureStore()
    ..token = token
    ..username = username
    ..password = password;
  final api = _FakeAuthApi(loginSucceeds: loginSucceeds);

  final container = ProviderContainer(
    overrides: [
      prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
      secureStoreProvider.overrideWithValue(secure),
      authApiProvider.overrideWithValue(api),
      bootstrapTokenProvider.overrideWithValue(seedToken),
      bootstrapServerUrlProvider.overrideWithValue(seedServerUrl),
    ],
  );
  addTearDown(container.dispose);
  container.read(authControllerProvider);
  await pumpEventQueue();
  return (container: container, secure: secure, api: api);
}

void main() {
  test('no token but remembered credentials: logs in silently, no UI needed', () async {
    final ctx = await _boot(username: 'shang', password: 'pw');

    expect(ctx.container.read(authControllerProvider).status, AuthStatus.authenticated);
    expect(ctx.api.loginCalls, 1);
    expect(ctx.secure.token, isNotNull);
  });

  test('a valid stored token is used as-is', () async {
    final ctx = await _boot(token: _validToken());

    expect(ctx.container.read(authControllerProvider).status, AuthStatus.authenticated);
    expect(ctx.api.loginCalls, 0);
    expect(ctx.api.meCalls, 1);
  });

  test('an expired token falls back to the remembered credentials', () async {
    final ctx = await _boot(token: _expiredToken(), username: 'shang', password: 'pw');

    expect(ctx.container.read(authControllerProvider).status, AuthStatus.authenticated);
    expect(ctx.api.loginCalls, 1);
  });

  test('a wrong remembered password surfaces the configuration page', () async {
    final ctx = await _boot(username: 'shang', password: 'stale', loginSucceeds: false);

    final state = ctx.container.read(authControllerProvider);
    expect(state.status, AuthStatus.unauthenticated);
    expect(state.error, isNotNull);
  });

  test('no token and no credentials surfaces the configuration page', () async {
    final ctx = await _boot();

    final state = ctx.container.read(authControllerProvider);
    expect(state.status, AuthStatus.unauthenticated);
    expect(ctx.api.loginCalls, 0);
  });

  test('a build-time seed token opens straight into the app', () async {
    final seed = _validToken();
    final ctx = await _boot(serverUrl: null, seedToken: seed);

    final state = ctx.container.read(authControllerProvider);
    expect(state.status, AuthStatus.authenticated);
    expect(ctx.api.loginCalls, 0);
    expect(ctx.secure.token, seed);
    expect(state.serverUrl, _serverUrl);
  });

  test('an expired seed is ignored and the configuration page shows', () async {
    final ctx = await _boot(serverUrl: null, seedToken: _expiredToken());

    expect(
      ctx.container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(ctx.secure.token, isNull);
  });

  test('login remembers the credentials, logout forgets them', () async {
    final ctx = await _boot(serverUrl: null);

    await ctx.container.read(authControllerProvider.notifier).login(
          serverUrl: _serverUrl,
          username: 'shang',
          password: 'pw',
        );
    expect(ctx.container.read(authControllerProvider).status, AuthStatus.authenticated);
    expect(ctx.secure.username, 'shang');
    expect(ctx.secure.password, 'pw');

    await ctx.container.read(authControllerProvider.notifier).logout();
    final state = ctx.container.read(authControllerProvider);
    expect(state.status, AuthStatus.unauthenticated);
    expect(ctx.secure.token, isNull);
    expect(ctx.secure.username, isNull);
    expect(ctx.secure.password, isNull);
  });

  test('a server-side expiry recovers by itself instead of asking again', () async {
    final ctx = await _boot(token: _validToken(), username: 'shang', password: 'pw');
    expect(ctx.api.loginCalls, 0);

    ctx.container.read(apiClientProvider).onSessionExpired?.call();
    await pumpEventQueue();

    expect(ctx.container.read(authControllerProvider).status, AuthStatus.authenticated);
    expect(ctx.api.loginCalls, 1);
  });
}
