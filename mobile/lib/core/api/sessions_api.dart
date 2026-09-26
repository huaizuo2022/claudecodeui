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
  ///
  /// [provider] narrows the feed to one client (`claude`/`codex`/`cursor`/
  /// `opencode`); omitted/null means "all clients".
  Future<RecentSessionsPage> recentSessionsPage({
    int limit = 40,
    int offset = 0,
    String? provider,
  }) async {
    final body = await _client.getJson(
      'providers/sessions/recent',
      query: {
        'limit': '$limit',
        'offset': '$offset',
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      },
    );
    if (body is! Map || body['conversations'] is! List) {
      throw ApiException(message: '最近会话响应格式异常');
    }
    return RecentSessionsPage.fromJson(body);
  }

  /// `/api/providers/sessions/recent` → `{conversations, total, hasMore}`.
  Future<List<RecentSession>> recentSessions({
    int limit = 20,
    int offset = 0,
    String? provider,
  }) async {
    final page = await recentSessionsPage(limit: limit, offset: offset, provider: provider);
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

  /// `PUT /api/providers/sessions/:sessionId` → renames session.
  Future<void> renameSession(String sessionId, String summary) async {
    await _client.putJson(
      'providers/sessions/$sessionId',
      data: {'summary': summary},
    );
  }

  /// `GET /api/providers/sessions/:sessionId/provider-id` → gets provider session ID.
  Future<String> getProviderSessionId(String sessionId) async {
    try {
      final body = await _client.getJson('providers/sessions/$sessionId/provider-id');
      if (body is Map && body['sessionId'] is String && (body['sessionId'] as String).isNotEmpty) {
        return body['sessionId'] as String;
      }
    } catch (_) {}
    return sessionId;
  }

  /// `POST /api/providers/sessions/:sessionId/fork` → forks session into a new copy.
  Future<CreatedSession> forkSession(
    String sessionId, {
    String? title,
    String? upToAnchorId,
  }) async {
    final body = await _client.postJson(
      'providers/sessions/$sessionId/fork',
      data: {
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        if (upToAnchorId != null && upToAnchorId.isNotEmpty) 'upToAnchorId': upToAnchorId,
      },
    );
    if (body is! Map) {
      throw ApiException(message: '分叉会话响应格式异常');
    }
    final data = (body['data'] is Map) ? body['data'] as Map : body;
    return CreatedSession(
      sessionId: '${data['sessionId'] ?? ''}',
      provider: (data['provider'] as String?) ?? '',
      projectPath: (data['projectPath'] as String?) ?? '',
    );
  }

  /// `DELETE /api/providers/sessions/:sessionId` → archives or hard deletes session.
  Future<void> deleteSession(String sessionId, {bool hardDelete = false}) async {
    await _client.deleteJson(
      'providers/sessions/$sessionId',
      query: hardDelete ? {'force': 'true'} : null,
    );
  }

  /// `POST /api/providers/sessions/:sessionId/restore` → restores an archived session.
  Future<void> restoreSession(String sessionId) async {
    await _client.postJson('providers/sessions/$sessionId/restore');
  }
}

