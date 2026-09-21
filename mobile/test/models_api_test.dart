import 'dart:typed_data';

import 'package:cloudcli_mobile/core/api/api_client.dart';
import 'package:cloudcli_mobile/core/api/models_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.statusCode, this.body, {this.onRequest});

  final int statusCode;
  final String body;
  final void Function(RequestOptions)? onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onRequest?.call(options);
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
  group('formatTokenUsage', () {
    test('formats millions, thousands and small numbers correctly', () {
      expect(formatTokenUsage(0), '0 tokens');
      expect(formatTokenUsage(-10), '0 tokens');
      expect(formatTokenUsage(500), '500 tokens');
      expect(formatTokenUsage(3500), '3.5K tokens');
      expect(formatTokenUsage(45000), '45K tokens');
      expect(formatTokenUsage(1200000), '1.2M tokens');
      expect(formatTokenUsage(359000000), '359M tokens');
    });
  });

  group('ModelsApi', () {
    test('fetchProviderModels parses catalog options and default model', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test/api/'))
        ..httpClientAdapter = _CannedAdapter(
          200,
          '{"success":true,"data":{"provider":"claude","models":{'
              '"DEFAULT":"claude-3-5-sonnet-20241022",'
              '"OPTIONS":['
              '{"value":"claude-3-7-sonnet-20250219","label":"Claude 3.7 Sonnet","description":"Flagship model","isCustom":false},'
              '{"value":"custom-model-1","label":"My Fine Tune","description":"Custom model","isCustom":true}'
              ']}}}',
        );

      final api = ModelsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));
      final catalog = await api.fetchProviderModels('claude');

      expect(catalog.provider, 'claude');
      expect(catalog.defaultModel, 'claude-3-5-sonnet-20241022');
      expect(catalog.options.length, 2);
      expect(catalog.options[0].value, 'claude-3-7-sonnet-20250219');
      expect(catalog.options[0].label, 'Claude 3.7 Sonnet');
      expect(catalog.options[0].isCustom, false);
      expect(catalog.options[1].isCustom, true);
    });

    test('fetchSessionActiveModel parses active model and effort', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test/api/'))
        ..httpClientAdapter = _CannedAdapter(
          200,
          '{"success":true,"data":{"provider":"claude","sessionId":"ses-123","model":"claude-3-7-sonnet-20250219","effort":"high","source":"session"}}',
        );

      final api = ModelsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));
      final active = await api.fetchSessionActiveModel('claude', 'ses-123');

      expect(active.provider, 'claude');
      expect(active.sessionId, 'ses-123');
      expect(active.model, 'claude-3-7-sonnet-20250219');
      expect(active.effort, 'high');
      expect(active.source, 'session');
    });

    test('setSessionActiveModel sends model payload to server', () async {
      RequestOptions? recorded;
      final dio = Dio(BaseOptions(baseUrl: 'http://test/api/'))
        ..httpClientAdapter = _CannedAdapter(
          200,
          '{"success":true,"data":{"provider":"claude","sessionId":"ses-123","model":"claude-3-7-sonnet-20250219","effort":null,"source":"session"}}',
          onRequest: (req) => recorded = req,
        );

      final api = ModelsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));
      final active = await api.setSessionActiveModel('claude', 'ses-123', 'claude-3-7-sonnet-20250219');

      expect(active.model, 'claude-3-7-sonnet-20250219');
      expect(recorded, isNotNull);
      expect(recorded!.method, 'POST');
      expect(recorded!.path, 'providers/claude/sessions/ses-123/active-model');
      expect(recorded!.data, {'model': 'claude-3-7-sonnet-20250219'});
    });

    test('fetchSessionTokenUsage formats used tokens', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test/api/'))
        ..httpClientAdapter = _CannedAdapter(
          200,
          '{"success":true,"data":{"used":359123456,"inputTokens":350000000,"outputTokens":9123456}}',
        );

      final api = ModelsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));
      final tokenText = await api.fetchSessionTokenUsage('ses-123');

      expect(tokenText, '359M tokens');
    });
  });
}
