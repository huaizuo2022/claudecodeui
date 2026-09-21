import 'dart:typed_data';

import 'package:cloudcli_mobile/core/api/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves one canned response so the error-shape handling can be tested without
/// a server.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.statusCode, this.body, {this.extraHeaders = const {}});

  final int statusCode;
  final String body;
  final Map<String, String> extraHeaders;
  final List<Uri> requestedUris = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUris.add(options.uri);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        for (final entry in extraHeaders.entries) entry.key: [entry.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _clientReturning(int statusCode, String body) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
    ..httpClientAdapter = _CannedAdapter(statusCode, body);
  return ApiClient(dio: dio)..configure(serverUrl: 'http://test');
}

void main() {
  group('normalizeServerUrl', () {
    test('defaults to http and strips trailing slashes', () {
      expect(ApiClient.normalizeServerUrl('192.168.1.20:3001'), 'http://192.168.1.20:3001');
      expect(ApiClient.normalizeServerUrl('192.168.1.20:3001/'), 'http://192.168.1.20:3001');
      expect(ApiClient.normalizeServerUrl('  10.0.0.2:3001//  '), 'http://10.0.0.2:3001');
    });

    test('keeps an explicit scheme and sub-path', () {
      expect(
        ApiClient.normalizeServerUrl('https://cli.example.com'),
        'https://cli.example.com',
      );
      expect(
        ApiClient.normalizeServerUrl('http://example.com/cloudcli/'),
        'http://example.com/cloudcli',
      );
    });
  });

  group('unwrap', () {
    test('unwraps the {success, data} envelope', () {
      expect(ApiClient.unwrap({'success': true, 'data': {'a': 1}}), {'a': 1});
    });

    test('passes bare payloads through', () {
      final list = [
        {'projectId': 'p1'}
      ];
      expect(ApiClient.unwrap(list), list);
      expect(ApiClient.unwrap({'needsSetup': false}), {'needsSetup': false});
    });
  });

  group('request url', () {
    test('paths are appended under /api/, not merged into it', () async {
      final adapter = _CannedAdapter(200, '{"user":{"id":1,"username":"shang"}}');
      final dio = Dio(BaseOptions())..httpClientAdapter = adapter;
      final client = ApiClient(dio: dio)
        ..configure(serverUrl: 'https://claude.huaizuo2029.cn', token: 't');

      await client.getJson('auth/user');
      await client.getJson('projects', query: {'skipSynchronization': '1'});

      expect(
        adapter.requestedUris.map((uri) => uri.path).toList(),
        ['/api/auth/user', '/api/projects'],
      );
      expect(adapter.requestedUris.last.query, 'skipSynchronization=1');
    });
  });

  group('error shapes', () {
    test('reads the service-layer nested error object', () async {
      final client = _clientReturning(
        401,
        '{"success":false,"error":{"code":"AUTH_INVALID_CREDENTIALS",'
            '"message":"Invalid username or password"}}',
      );

      await expectLater(
        client.postJson('auth/login', data: const {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Invalid username or password')
              .having((e) => e.code, 'code', 'AUTH_INVALID_CREDENTIALS')
              .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue),
        ),
      );
    });

    test('reads the middleware flat error string', () async {
      final client = _clientReturning(
        401,
        '{"error":"Access denied. No token provided.","code":"AUTH_TOKEN_INVALID"}',
      );

      await expectLater(
        client.getJson('projects'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Access denied. No token provided.')
              .having((e) => e.code, 'code', 'AUTH_TOKEN_INVALID'),
        ),
      );
    });

    test('refreshes the token when the server returns one inline', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
        ..httpClientAdapter = _CannedAdapter(
          200,
          '{"success":true,"data":{"ok":true}}',
          extraHeaders: const {'x-refreshed-token': 'new-token'},
        );
      final client = ApiClient(dio: dio)
        ..configure(serverUrl: 'http://test', token: 'old');
      String? refreshed;
      client.onTokenRefreshed = (token) => refreshed = token;

      await client.getJson('auth/user');

      expect(refreshed, 'new-token');
      expect(client.token, 'new-token');
    });
  });

  group('webSocketUrl', () {
    test('is null until both server and token are known', () {
      final client = ApiClient();
      expect(client.webSocketUrl, isNull);

      client.configure(serverUrl: 'http://10.0.0.5:3001');
      expect(client.webSocketUrl, isNull);

      client.configure(token: 'tok');
      expect(client.webSocketUrl, 'ws://10.0.0.5:3001/ws?token=tok');
    });

    test('upgrades to wss and keeps a sub-path', () {
      final client = ApiClient()
        ..configure(serverUrl: 'https://example.com/cloudcli', token: 'tok');
      expect(client.webSocketUrl, 'wss://example.com/cloudcli/ws?token=tok');
    });
  });
}
