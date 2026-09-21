import 'package:cloudcli_mobile/core/api/api_client.dart';
import 'package:cloudcli_mobile/core/providers.dart';
import 'package:cloudcli_mobile/features/chat/chat_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// End-to-end through the real server: create a scratch session, open the chat
/// controller (websocket subscribe), send one message, and wait for the run to
/// stream and complete. Run with:
///
///   ./run-local.sh test integration_test/chat_e2e_test.dart -d <device> \
///     --dart-define=E2E_SERVER=... --dart-define=E2E_TOKEN=...
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final server = const String.fromEnvironment('E2E_SERVER');
  final token = const String.fromEnvironment('E2E_TOKEN');

  testWidgets('chat send streams and completes through the real server', (
    tester,
  ) async {
    expect(server, isNotEmpty, reason: 'E2E_SERVER define missing');
    expect(token, isNotEmpty, reason: 'E2E_TOKEN define missing');

    final client = ApiClient()..configure(serverUrl: server, token: token);
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    addTearDown(client.close);

    final created = await client.postJson('providers/sessions', data: {
      'provider': 'claude',
      'projectPath': '/Users/shang/Dev/claudecodeui',
      'initialMessage': '',
    });
    final sessionId = created is Map ? '${created['sessionId']}' : '';
    expect(sessionId, isNotEmpty);
    addTearDown(() async {
      // Archive the scratch session so it does not pollute the list.
      try {
        await client.deleteJson('providers/sessions/$sessionId');
      } catch (_) {}
    });

    final controller = container.read(chatControllerProvider(sessionId).notifier);
    container.listen(chatControllerProvider(sessionId), (_, __) {});
    await tester.pump(const Duration(milliseconds: 300));

    final sent = await controller.send('只用一个字回复：好');
    expect(sent, isTrue);

    final deadline = DateTime.now().add(const Duration(seconds: 120));
    var sawUserRow = false;
    var sawAssistantText = false;
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 500));
      final state = container.read(chatControllerProvider(sessionId));
      sawUserRow |= state.messages.any((message) => message.isUser);
      sawAssistantText |= state.messages.any(
        (message) => !message.isUser && (message.content ?? '').contains('好'),
      );
      if (!state.isProcessing && sawUserRow && sawAssistantText) break;
    }

    final state = container.read(chatControllerProvider(sessionId));
    expect(sawUserRow, isTrue, reason: 'optimistic user row missing');
    expect(sawAssistantText, isTrue, reason: 'assistant answer never streamed in');
    expect(state.isProcessing, isFalse, reason: 'run never completed');
    expect(state.pendingPermissions, isEmpty);
  });
}
