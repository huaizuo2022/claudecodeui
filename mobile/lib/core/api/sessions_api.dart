import '../models/session.dart';
import 'api_client.dart';

/// Result of allocating a brand-new app session.
class CreatedSession {
  const CreatedSession({required this.sessionId, required this.provider, required this.projectPath});

  final String sessionId;
  final String provider;
  final String projectPath;

  factory CreatedSession.fromJson(Map<dynamic, dynamic> json) => CreatedSession(
        sessionId: '${json['sessionId']}',
        provider: (json['provider'] as String?) ?? '',
        projectPath: (json['projectPath'] as String?) ?? '',
      );
}

class SessionsApi {
  SessionsApi(this._client);

  final ApiClient _client;

  /// `/api/providers/sessions/recent` → `{conversations, total, hasMore}`.
  Future<RecentSessionsPage> recentSessionsPage({int limit = 40, int offset = 0}) async {
    final body = await _client.getJson(
      'providers/sessions/recent',
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    if (body is! Map || body['conversations'] is! List) {
      throw ApiException(message: '最近会话响应格式异常');
    }
    return RecentSessionsPage.fromJson(body);
  }

  /// `/api/providers/sessions/recent` → `{conversations, total, hasMore}`.
  Future<List<RecentSession>> recentSessions({int limit = 20, int offset = 0}) async {
    final page = await recentSessionsPage(limit: limit, offset: offset);
    return page.conversations;
  }

  /// `/api/providers/sessions/running` → `{sessions: [...]}`.
  Future<List<RunningSessionInfo>> runningSessions() async {
    final body = await _client.getJson('providers/sessions/running');
    if (body is! Map || body['sessions'] is! List) {
      return const [];
    }
    return (body['sessions'] as List)
        .whereType<Map>()
        .map(RunningSessionInfo.fromJson)
        .toList(growable: false);
  }

  /// `/api/providers/sessions/archived` → `{sessions: [...]}`.
  Future<List<ArchivedSessionItem>> archivedSessions() async {
    final body = await _client.getJson('providers/sessions/archived');
    if (body is! Map || body['sessions'] is! List) {
      return const [];
    }
    return (body['sessions'] as List)
        .whereType<Map>()
        .map(ArchivedSessionItem.fromJson)
        .toList(growable: false);
  }

  /// Allocates a session before the first message; `chat.send` refuses to
  /// start without one (`SESSION_NOT_FOUND`).
  Future<CreatedSession> createSession({
    required String provider,
    required String projectPath,
    String initialMessage = '',
  }) async {
    final body = await _client.postJson(
      'providers/sessions',
      data: {
        'provider': provider,
        'projectPath': projectPath,
        'initialMessage': initialMessage,
      },
    );
    if (body is! Map) throw ApiException(message: '创建会话响应格式异常');
    return CreatedSession.fromJson(body);
  }
}
