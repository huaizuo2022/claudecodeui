import 'dart:typed_data';

import 'package:cloudcli_mobile/core/api/api_client.dart';
import 'package:cloudcli_mobile/core/api/projects_api.dart';
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
    capturedPaths.add(options.uri.path);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  final List<String> capturedPaths = [];

  @override
  void close({bool force = false}) {}
}

void main() {
  test('toggle-star posts to the project endpoint and returns the new state', () async {
    final adapter = _CannedAdapter(200, '{"success":true,"isStarred":true}');
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))..httpClientAdapter = adapter;
    final api = ProjectsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    final starred = await api.toggleStar('p-1');

    expect(starred, isTrue);
    expect(adapter.capturedPaths.single, '/api/projects/p-1/toggle-star');
  });

  test('toggle-star surfaces a server error', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
      ..httpClientAdapter = _CannedAdapter(
        404,
        '{"success":false,"error":{"code":"PROJECT_NOT_FOUND","message":"Project not found"}}',
      );
    final api = ProjectsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    await expectLater(api.toggleStar('missing'), throwsA(isA<ApiException>()));
  });

  test('toggle-star rejects an unexpected shape', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
      ..httpClientAdapter = _CannedAdapter(200, '[]');
    final api = ProjectsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    await expectLater(api.toggleStar('p-1'), throwsA(isA<ApiException>()));
  });
}