import '../models/auth.dart';
import 'api_client.dart';

class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  /// Unauthenticated probe used by the login page's "test connection" action.
  Future<ServerAuthStatus> status() async {
    final body = await _client.getJson('auth/status');
    if (body is! Map) throw ApiException(message: '服务器返回了意外的响应');
    return ServerAuthStatus.fromJson(body);
  }

  Future<LoginResult> login({required String username, required String password}) async {
    final body = await _client.postJson(
      'auth/login',
      data: {'username': username, 'password': password},
    );
    if (body is! Map) throw ApiException(message: '服务器返回了意外的响应');
    return LoginResult.fromJson(body);
  }

  Future<AuthUser> me() async {
    final body = await _client.getJson('auth/user');
    if (body is Map && body['user'] is Map) {
      return AuthUser.fromJson(body['user'] as Map);
    }
    throw ApiException(message: '无法读取当前用户');
  }

  /// Explicit refresh; the steady-state path is the `X-Refreshed-Token`
  /// response header the interceptor already handles.
  Future<void> refresh() => _client.postJson('auth/refresh');
}
