import 'package:cloudcli_mobile/core/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

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
