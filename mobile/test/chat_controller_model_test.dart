import 'package:cloudcli_mobile/core/api/models_api.dart';
import 'package:cloudcli_mobile/core/models/provider_model.dart';
import 'package:cloudcli_mobile/core/providers.dart';
import 'package:cloudcli_mobile/features/chat/chat_controller.dart';
import 'package:cloudcli_mobile/features/chat/chat_reducer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeModelsApi implements ModelsApi {
  String? lastSelectedModel;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<ProviderModelsCatalog> fetchProviderModels(String provider) async {
    return const ProviderModelsCatalog(
      provider: 'claude',
      defaultModel: 'claude-3-5-sonnet',
      options: [
        ProviderModelOption(
          value: 'claude-3-7-sonnet',
          label: 'Claude 3.7 Sonnet',
          description: 'High capability',
        ),
        ProviderModelOption(
          value: 'claude-3-5-sonnet',
          label: 'Claude 3.5 Sonnet',
          description: 'Previous gen',
        ),
      ],
    );
  }

  @override
  Future<SessionActiveModel> fetchSessionActiveModel(String provider, String sessionId) async {
    return const SessionActiveModel(
      provider: 'claude',
      sessionId: 'test-session',
      model: 'claude-3-7-sonnet',
      effort: 'high',
      source: 'session',
    );
  }

  @override
  Future<SessionActiveModel> setSessionActiveModel(
    String provider,
    String sessionId,
    String model,
  ) async {
    lastSelectedModel = model;
    return SessionActiveModel(
      provider: provider,
      sessionId: sessionId,
      model: model,
      source: 'session',
    );
  }

  @override
  Future<String?> fetchSessionTokenUsage(String sessionId) async {
    return '359M tokens';
  }
}

void main() {
  test('ChatState copyWith updates model and token usage fields', () {
    const initial = ChatState();
    final updated = initial.copyWith(
      provider: 'codex',
      currentModel: 'gpt-4o',
      currentModelLabel: 'GPT-4o',
      availableModels: const [
        ProviderModelOption(value: 'gpt-4o', label: 'GPT-4o'),
      ],
      tokenUsageText: '12.5K tokens',
    );

    expect(updated.provider, 'codex');
    expect(updated.currentModel, 'gpt-4o');
    expect(updated.currentModelLabel, 'GPT-4o');
    expect(updated.availableModels.length, 1);
    expect(updated.tokenUsageText, '12.5K tokens');
  });

  test('ChatController loads active model and token usage on initSession', () async {
    final fakeApi = _FakeModelsApi();
    final container = ProviderContainer(
      overrides: [
        modelsApiProvider.overrideWithValue(fakeApi),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(chatControllerProvider('test-session').notifier);
    controller.initSession(provider: 'claude');

    // Wait microtask and async operations
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(chatControllerProvider('test-session'));
    expect(state.currentModel, 'claude-3-7-sonnet');
    expect(state.currentModelLabel, 'Claude 3.7 Sonnet');
    expect(state.availableModels.length, 2);
    expect(state.tokenUsageText, '359M tokens');
  });

  test('ChatController selectModel updates state and invokes API', () async {
    final fakeApi = _FakeModelsApi();
    final container = ProviderContainer(
      overrides: [
        modelsApiProvider.overrideWithValue(fakeApi),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(chatControllerProvider('test-session').notifier);
    controller.initSession(provider: 'claude');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await controller.selectModel('claude-3-5-sonnet');

    final state = container.read(chatControllerProvider('test-session'));
    expect(state.currentModel, 'claude-3-5-sonnet');
    expect(state.currentModelLabel, 'Claude 3.5 Sonnet');
    expect(fakeApi.lastSelectedModel, 'claude-3-5-sonnet');
  });
}
