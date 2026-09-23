import 'dart:typed_data';

import 'package:cloudcli_mobile/core/api/api_client.dart';
import 'package:cloudcli_mobile/core/api/sessions_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;

  /// Last request URI, so tests can assert which query parameters rode along.
  Uri? lastUri;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUri = options.uri;
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
  test('recentSessionsPage parses total, hasMore, and conversations', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
      ..httpClientAdapter = _CannedAdapter(
        200,
        '{"success":true,"data":{"conversations":['
            '{"sessionId":"s1","provider":"claude","projectId":"p1",'
            '"projectDisplayName":"claudecodeui","sessionTitle":"测试对话",'
            '"lastActivity":"2026-09-21T01:41:56.891Z"}'
            '],"total":1492,"hasMore":true}}',
      );
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    final page = await api.recentSessionsPage(limit: 40, offset: 0);

    expect(page.total, 1492);
    expect(page.hasMore, isTrue);
    expect(page.conversations.length, 1);
    expect(page.conversations.first.displayTitle, '测试对话');
  });

  test('runningSessions parses active running sessions', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
      ..httpClientAdapter = _CannedAdapter(
        200,
        '{"success":true,"data":{"sessions":['
            '{"sessionId":"s-run-1","provider":"claude","startedAt":1726900000,"lastSeq":12}'
            ']}}',
      );
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    final running = await api.runningSessions();

    expect(running.length, 1);
    expect(running.first.sessionId, 's-run-1');
    expect(running.first.provider, 'claude');
    expect(running.first.lastSeq, 12);
  });

  test('archivedSessions parses archived sessions list', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
      ..httpClientAdapter = _CannedAdapter(
        200,
        '{"success":true,"data":{"sessions":['
            '{"sessionId":"s-arch-1","provider":"codex","sessionTitle":"已归档",'
            '"projectDisplayName":"legacy-proj","isProjectArchived":true}'
            ']}}',
      );
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    final archived = await api.archivedSessions();

    expect(archived.length, 1);
    expect(archived.first.sessionId, 's-arch-1');
    expect(archived.first.displayTitle, '已归档');
    expect(archived.first.isProjectArchived, isTrue);
  });

  test('recentSessionsPage sends provider filter as a query parameter', () async {
    final adapter = _CannedAdapter(
      200,
      '{"success":true,"data":{"conversations":[],"total":0,"hasMore":false}}',
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
      ..httpClientAdapter = adapter;
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    await api.recentSessionsPage(limit: 40, offset: 0, provider: 'codex');

    final uri = adapter.lastUri;
    expect(uri, isNotNull);
    expect(uri!.queryParameters['provider'], 'codex');
    expect(uri.queryParameters['limit'], '40');
  });

  test('recentSessionsPage omits provider when the filter is null', () async {
    final adapter = _CannedAdapter(
      200,
      '{"success":true,"data":{"conversations":[],"total":0,"hasMore":false}}',
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
      ..httpClientAdapter = adapter;
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    await api.recentSessionsPage(limit: 40, offset: 0);

    final uri = adapter.lastUri;
    expect(uri, isNotNull);
    expect(uri!.queryParameters.containsKey('provider'), isFalse);
  });
}
