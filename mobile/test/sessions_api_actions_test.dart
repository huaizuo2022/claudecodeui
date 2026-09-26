import 'dart:typed_data';

import 'package:cloudcli_mobile/core/api/api_client.dart';
import 'package:cloudcli_mobile/core/api/sessions_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.statusCode, this.responseBody);

  final int statusCode;
  final String responseBody;
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      responseBody,
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
  test('renameSession sends PUT request with summary', () async {
    final adapter = _CapturingAdapter(200, '{"success":true,"data":{}}');
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))..httpClientAdapter = adapter;
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    await api.renameSession('ses-1', '新会话名称');

    expect(adapter.lastOptions?.method, 'PUT');
    expect(adapter.lastOptions?.uri.toString(), 'http://test/api/providers/sessions/ses-1');
    expect(adapter.lastOptions?.data, {'summary': '新会话名称'});
  });

  test('getProviderSessionId returns provider sessionId from server', () async {
    final adapter = _CapturingAdapter(200, '{"success":true,"data":{"sessionId":"provider-native-id-456"}}');
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))..httpClientAdapter = adapter;
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    final providerId = await api.getProviderSessionId('ses-1');

    expect(providerId, 'provider-native-id-456');
    expect(adapter.lastOptions?.method, 'GET');
    expect(adapter.lastOptions?.uri.toString(), 'http://test/api/providers/sessions/ses-1/provider-id');
  });

  test('forkSession sends POST and returns CreatedSession', () async {
    final adapter = _CapturingAdapter(
      200,
      '{"success":true,"data":{"sessionId":"forked-id-789","provider":"claude","projectPath":"/repo"}}',
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))..httpClientAdapter = adapter;
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    final res = await api.forkSession('ses-1', title: 'Forked Title');

    expect(adapter.lastOptions?.method, 'POST');
    expect(adapter.lastOptions?.uri.toString(), 'http://test/api/providers/sessions/ses-1/fork');
    expect(adapter.lastOptions?.data, {'title': 'Forked Title'});
    expect(res.sessionId, 'forked-id-789');
    expect(res.provider, 'claude');
    expect(res.projectPath, '/repo');
  });

  test('deleteSession sends soft archive DELETE when hardDelete is false', () async {
    final adapter = _CapturingAdapter(200, '{"success":true,"data":{}}');
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))..httpClientAdapter = adapter;
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    await api.deleteSession('ses-1', hardDelete: false);

    expect(adapter.lastOptions?.method, 'DELETE');
    expect(adapter.lastOptions?.uri.toString(), 'http://test/api/providers/sessions/ses-1');
    expect(adapter.lastOptions?.queryParameters.isEmpty, isTrue);
  });

  test('deleteSession sends hard DELETE with force=true when hardDelete is true', () async {
    final adapter = _CapturingAdapter(200, '{"success":true,"data":{}}');
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))..httpClientAdapter = adapter;
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    await api.deleteSession('ses-1', hardDelete: true);

    expect(adapter.lastOptions?.method, 'DELETE');
    expect(adapter.lastOptions?.queryParameters, {'force': 'true'});
  });

  test('restoreSession sends POST to restore endpoint', () async {
    final adapter = _CapturingAdapter(200, '{"success":true,"data":{}}');
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))..httpClientAdapter = adapter;
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    await api.restoreSession('ses-1');

    expect(adapter.lastOptions?.method, 'POST');
    expect(adapter.lastOptions?.uri.toString(), 'http://test/api/providers/sessions/ses-1/restore');
  });

  test('toggleSessionStar posts to the session endpoint and returns the new state', () async {
    final adapter = _CapturingAdapter(200, '{"success":true,"data":{"isStarred":true}}');
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))..httpClientAdapter = adapter;
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    final starred = await api.toggleSessionStar('ses-1');

    expect(starred, isTrue);
    expect(adapter.lastOptions?.method, 'POST');
    expect(
      adapter.lastOptions?.uri.toString(),
      'http://test/api/providers/sessions/ses-1/toggle-star',
    );
  });

  test('toggleSessionStar rejects a response without a star state', () async {
    final adapter = _CapturingAdapter(200, '{"success":true,"data":{}}');
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))..httpClientAdapter = adapter;
    final api = SessionsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    await expectLater(api.toggleSessionStar('ses-1'), throwsA(isA<ApiException>()));
  });
}
