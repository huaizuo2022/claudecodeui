import 'project.dart';

/// Row of `/api/providers/sessions/recent` — the same list the web home screen
/// shows under "最近会话".
class RecentSession {
  const RecentSession({
    required this.sessionId,
    required this.provider,
    required this.projectId,
    required this.projectDisplayName,
    required this.sessionTitle,
    required this.lastActivity,
  });

  final String sessionId;
  final String provider;
  final String? projectId;
  final String projectDisplayName;
  final String sessionTitle;

  /// Null when the session has no activity stamp.
  final DateTime? lastActivity;

  factory RecentSession.fromJson(Map<dynamic, dynamic> json) => RecentSession(
        sessionId: '${json['sessionId']}',
        provider: (json['provider'] as String?) ?? '',
        projectId: json['projectId'] == null ? null : '${json['projectId']}',
        projectDisplayName: (json['projectDisplayName'] as String?) ?? '',
        sessionTitle: (json['sessionTitle'] as String?) ?? '',
        lastActivity: parseServerDate(json['lastActivity']),
      );

  /// The service falls back to the raw session id when no custom name exists,
  /// which renders as a UUID. Treat that as "no title".
  String get displayTitle {
    final uuidLike = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (sessionTitle.isEmpty || uuidLike.hasMatch(sessionTitle)) return '(未命名会话)';
    return sessionTitle;
  }
}
