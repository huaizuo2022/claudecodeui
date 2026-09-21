import 'dart:typed_data';

import 'package:cloudcli_mobile/core/api/api_client.dart';
import 'package:cloudcli_mobile/core/api/sessions_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('recent sessions parses the {conversations} envelope', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
      ..httpClientAdapter = _CannedAdapter(
        200,
        '{"success":true,"data":{"conversations":['
            '{"sessionId":"0199","provider":"claude","projectId":"p1",'
            '"projectDisplayName":"claudecodeui","sessionTitle":"重构会话页",'
            '"lastActivity":"2026-09-21T01:41:56.891Z"},'
            '{"sessionId":"abc","provider":"codex","projectId":null,'
            '"projectDisplayName":"","sessionTitle":"01a0bf25-2f80-7932-ae86-f46c1d31541d",'
            '"lastActivity":"2026-09-20 15:15:49"}'
            '],"total":2,"hasMore":false}}',
      );
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    final sessions = await api.recentSessions();

    expect(sessions.length, 2);
    expect(sessions.first.displayTitle, '重构会话页');
    expect(sessions.first.projectDisplayName, 'claudecodeui');
    expect(sessions.last.displayTitle, '(未命名会话)');
    expect(sessions.last.lastActivity, isNotNull);
  });

  test('recent sessions rejects an unexpected shape', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
      ..httpClientAdapter = _CannedAdapter(200, '{"success":true,"data":{"unexpected":1}}');
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    await expectLater(api.recentSessions(), throwsA(isA<ApiException>()));
  });

  test('a string body is decoded before unwrapping', () {
    expect(
      ApiClient.unwrap('{"success":true,"data":{"ok":true}}'),
      {'ok': true},
    );
    expect(ApiClient.unwrap('[1,2]'), [1, 2]);
    expect(ApiClient.unwrap('not json'), 'not json');
  });
}
