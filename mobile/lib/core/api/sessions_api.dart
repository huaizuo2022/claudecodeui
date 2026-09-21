import '../models/session.dart';
import 'api_client.dart';

class SessionsApi {
  SessionsApi(this._client);

  final ApiClient _client;

  /// `/api/providers/sessions/recent` → `{conversations, total, hasMore}`.
  Future<List<RecentSession>> recentSessions({int limit = 20, int offset = 0}) async {
    final body = await _client.getJson(
      'providers/sessions/recent',
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    if (body is! Map || body['conversations'] is! List) {
      throw ApiException(message: '最近会话响应格式异常');
    }
    return (body['conversations'] as List)
        .whereType<Map>()
        .map(RecentSession.fromJson)
        .toList(growable: false);
  }
}
