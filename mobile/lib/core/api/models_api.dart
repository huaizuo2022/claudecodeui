import '../models/provider_model.dart';
import 'api_client.dart';

String formatTokenUsage(num value) {
  if (value <= 0) return '0 tokens';
  if (value >= 10000000) {
    return '${(value / 1000000).toStringAsFixed(0)}M tokens';
  }
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M tokens';
  }
  if (value >= 10000) {
    return '${(value ~/ 1000)}K tokens';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K tokens';
  }
  return '$value tokens';
}

class ProviderModelsCatalog {
  const ProviderModelsCatalog({
    required this.provider,
    required this.defaultModel,
    required this.options,
  });

  final String provider;
  final String defaultModel;
  final List<ProviderModelOption> options;
}

class ModelsApi {
  ModelsApi(this._client);

  final ApiClient _client;

  /// `GET /api/providers/:provider/models`
  Future<ProviderModelsCatalog> fetchProviderModels(String provider) async {
    final normalized = provider.trim().toLowerCase();
    final body = await _client.getJson('providers/$normalized/models');
    if (body is! Map) {
      throw ApiException(message: '模型列表响应格式异常');
    }

    final modelsMap = body['models'] is Map ? body['models'] as Map : const {};
    final defaultModel = (modelsMap['DEFAULT'] as String?) ?? '';
    final optionsList = modelsMap['OPTIONS'] is List ? modelsMap['OPTIONS'] as List : const [];

    final options = optionsList
        .whereType<Map>()
        .map(ProviderModelOption.fromJson)
        .toList(growable: false);

    return ProviderModelsCatalog(
      provider: (body['provider'] as String?) ?? normalized,
      defaultModel: defaultModel,
      options: options,
    );
  }

  /// `GET /api/providers/:provider/sessions/:sessionId/active-model`
  Future<SessionActiveModel> fetchSessionActiveModel(
    String provider,
    String sessionId,
  ) async {
    final normalized = provider.trim().toLowerCase();
    final body = await _client.getJson(
      'providers/$normalized/sessions/$sessionId/active-model',
    );
    if (body is! Map) {
      throw ApiException(message: '会话当前模型响应格式异常');
    }
    return SessionActiveModel.fromJson(body);
  }

  /// `POST /api/providers/:provider/sessions/:sessionId/active-model`
  Future<SessionActiveModel> setSessionActiveModel(
    String provider,
    String sessionId,
    String model,
  ) async {
    final normalized = provider.trim().toLowerCase();
    final body = await _client.postJson(
      'providers/$normalized/sessions/$sessionId/active-model',
      data: {'model': model},
    );
    if (body is! Map) {
      throw ApiException(message: '更新会话模型响应格式异常');
    }
    return SessionActiveModel.fromJson(body);
  }

  /// `GET /api/providers/sessions/:sessionId/token-usage`
  Future<String?> fetchSessionTokenUsage(String sessionId) async {
    try {
      final body = await _client.getJson('providers/sessions/$sessionId/token-usage');
      if (body is! Map) return null;
      final used = body['used'];
      if (used is num) {
        return formatTokenUsage(used);
      }
      return null;
    } catch (_) {
      // Token usage is informative; silently return null on error
      return null;
    }
  }
}
