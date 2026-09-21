import 'dart:convert';

/// The subset of the auth token's payload the client reasons about.
///
/// The server signs a 7-day JWT and auto-refreshes it through the
/// `X-Refreshed-Token` response header once the token passes half its lifetime.
/// The client mirrors that threshold so it can refresh before the WebSocket
/// upgrade (which does not auto-refresh) is attempted.
class JwtPayload {
  const JwtPayload({this.expiresAt, this.issuedAt, this.userId, this.username});

  final DateTime? expiresAt;
  final DateTime? issuedAt;
  final String? userId;
  final String? username;

  bool get isExpired {
    final exp = expiresAt;
    return exp != null && DateTime.now().isAfter(exp);
  }

  bool get isPastHalfLife {
    final exp = expiresAt;
    final iat = issuedAt;
    if (exp == null || iat == null) return false;
    final halfLife = exp.difference(iat) ~/ 2;
    return DateTime.now().isAfter(iat.add(halfLife));
  }
}

/// Decodes a JWT payload without verifying the signature. Returns null for
/// anything that is not a well-formed three-part token.
JwtPayload? decodeJwt(String? token) {
  if (token == null || token.isEmpty) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;

  try {
    final normalized = base64Url.normalize(parts[1]);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (decoded is! Map) return null;

    DateTime? fromSeconds(Object? value) {
      if (value is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);
    }

    return JwtPayload(
      expiresAt: fromSeconds(decoded['exp']),
      issuedAt: fromSeconds(decoded['iat']),
      userId: decoded['userId']?.toString(),
      username: decoded['username'] as String?,
    );
  } catch (_) {
    return null;
  }
}
