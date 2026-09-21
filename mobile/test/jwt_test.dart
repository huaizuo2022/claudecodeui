import 'dart:convert';

import 'package:cloudcli_mobile/core/util/jwt.dart';
import 'package:flutter_test/flutter_test.dart';

String fakeJwt({required int iat, required int exp, String username = 'shang'}) {
  String encode(Map<String, dynamic> payload) =>
      base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}'
      '.${encode({'userId': 7, 'username': username, 'iat': iat, 'exp': exp})}'
      '.signature';
}

void main() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  group('decodeJwt', () {
    test('reads userId, username and expiry from a well-formed token', () {
      final token = fakeJwt(iat: now - 60, exp: now + 3600);
      final payload = decodeJwt(token);

      expect(payload, isNotNull);
      expect(payload!.userId, '7');
      expect(payload.username, 'shang');
      expect(payload.isExpired, isFalse);
      expect(payload.isPastHalfLife, isFalse);
    });

    test('flags an expired token', () {
      final payload = decodeJwt(fakeJwt(iat: now - 7200, exp: now - 60));
      expect(payload!.isExpired, isTrue);
    });

    test('mirrors the server half-life threshold (7-day token)', () {
      const sevenDays = 7 * 24 * 3600;
      final fresh = decodeJwt(fakeJwt(iat: now - 3600, exp: now + sevenDays - 3600));
      final stale = decodeJwt(fakeJwt(iat: now - sevenDays ~/ 2 - 60, exp: now + sevenDays ~/ 2 - 60));

      expect(fresh!.isPastHalfLife, isFalse);
      expect(stale!.isPastHalfLife, isTrue);
      expect(stale.isExpired, isFalse);
    });

    test('rejects anything that is not a three-part token', () {
      expect(decodeJwt(null), isNull);
      expect(decodeJwt(''), isNull);
      expect(decodeJwt('not-a-jwt'), isNull);
      expect(decodeJwt('a.b'), isNull);
      expect(decodeJwt('a.@@@.c'), isNull);
    });
  });
}
