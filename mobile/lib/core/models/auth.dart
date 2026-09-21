/// Models returned by the auth endpoints.
///
/// The server is deliberately loose here: `/api/auth/login` answers with a bare
/// `{success, user, token}` (no `data` wrapper) and `/api/auth/user` answers
/// with `{user}`.
class AuthUser {
  const AuthUser({required this.id, required this.username});

  final String id;
  final String username;

  factory AuthUser.fromJson(Map<dynamic, dynamic> json) => AuthUser(
        id: '${json['id']}',
        username: (json['username'] as String?) ?? '',
      );
}

/// The unauthenticated liveness probe `/api/auth/status` answers with.
///
/// Named [ServerAuthStatus] so it never collides with the app's own
/// local session status enum.
class ServerAuthStatus {
  const ServerAuthStatus({required this.needsSetup});

  /// True when the server has no user yet and must be registered through the
  /// web UI first.
  final bool needsSetup;

  factory ServerAuthStatus.fromJson(Map<dynamic, dynamic> json) =>
      ServerAuthStatus(needsSetup: json['needsSetup'] == true);
}

class LoginResult {
  const LoginResult({required this.token, required this.user});

  final String token;
  final AuthUser user;

  factory LoginResult.fromJson(Map<dynamic, dynamic> json) {
    final rawUser = json['user'];
    return LoginResult(
      token: (json['token'] as String?) ?? '',
      user: rawUser is Map
          ? AuthUser.fromJson(rawUser)
          : const AuthUser(id: '', username: ''),
    );
  }
}
