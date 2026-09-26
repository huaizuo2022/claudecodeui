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
    required this.isProjectStarred,
    required this.isStarred,
  });

  final String sessionId;
  final String provider;
  final String? projectId;
  final String projectDisplayName;
  final String sessionTitle;

  /// Null when the session has no activity stamp.
  final DateTime? lastActivity;

  /// Whether the owning project is starred; false when the session has no
  /// project. Display-only: it marks every conversation of that project, so the
  /// star a user taps on a row is [isStarred] instead.
  final bool isProjectStarred;

  /// Whether this conversation itself is starred. This is the per-row star the
  /// "加星" tab lists, so starring one conversation leaves its siblings alone.
  final bool isStarred;

  factory RecentSession.fromJson(Map<dynamic, dynamic> json) => RecentSession(
        sessionId: '${json['sessionId']}',
        provider: (json['provider'] as String?) ?? '',
        projectId: json['projectId'] == null ? null : '${json['projectId']}',
        projectDisplayName: (json['projectDisplayName'] as String?) ?? '',
        sessionTitle: (json['sessionTitle'] as String?) ?? '',
        lastActivity: parseServerDate(json['lastActivity']),
        isProjectStarred: json['isProjectStarred'] == true,
        isStarred: json['isStarred'] == true,
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'provider': provider,
        'projectId': projectId,
        'projectDisplayName': projectDisplayName,
        'sessionTitle': sessionTitle,
        'lastActivity': lastActivity?.toIso8601String(),
        'isProjectStarred': isProjectStarred,
        'isStarred': isStarred,
      };

  /// A copy carrying a new session star. Only the star moves, so the nullable
  /// `lastActivity` needs no "was it passed?" sentinel.
  RecentSession copyWithStar(bool nextStarred) => RecentSession(
        sessionId: sessionId,
        provider: provider,
        projectId: projectId,
        projectDisplayName: projectDisplayName,
        sessionTitle: sessionTitle,
        lastActivity: lastActivity,
        isProjectStarred: isProjectStarred,
        isStarred: nextStarred,
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

/// Paginated result of `/api/providers/sessions/recent`.
class RecentSessionsPage {
  const RecentSessionsPage({
    required this.conversations,
    required this.total,
    required this.hasMore,
  });

  final List<RecentSession> conversations;
  final int total;
  final bool hasMore;

  factory RecentSessionsPage.fromJson(Map<dynamic, dynamic> json) => RecentSessionsPage(
        conversations: (json['conversations'] as List? ?? const [])
            .whereType<Map>()
            .map(RecentSession.fromJson)
            .toList(growable: false),
        total: (json['total'] as num?)?.toInt() ?? 0,
        hasMore: json['hasMore'] == true,
      );
}

/// Active running session info from `/api/providers/sessions/running`.
class RunningSessionInfo {
  const RunningSessionInfo({
    required this.sessionId,
    required this.provider,
    required this.startedAt,
    required this.lastSeq,
  });

  final String sessionId;
  final String provider;
  final int startedAt;
  final int lastSeq;

  factory RunningSessionInfo.fromJson(Map<dynamic, dynamic> json) => RunningSessionInfo(
        sessionId: '${json['sessionId'] ?? ''}',
        provider: (json['provider'] as String?) ?? '',
        startedAt: (json['startedAt'] as num?)?.toInt() ?? 0,
        lastSeq: (json['lastSeq'] as num?)?.toInt() ?? 0,
      );
}

/// Archived session item from `/api/providers/sessions/archived`.
class ArchivedSessionItem {
  const ArchivedSessionItem({
    required this.sessionId,
    required this.provider,
    required this.projectId,
    required this.projectPath,
    required this.projectDisplayName,
    required this.sessionTitle,
    required this.lastActivity,
    required this.isProjectArchived,
  });

  final String sessionId;
  final String provider;
  final String? projectId;
  final String? projectPath;
  final String projectDisplayName;
  final String sessionTitle;
  final DateTime? lastActivity;
  final bool isProjectArchived;

  factory ArchivedSessionItem.fromJson(Map<dynamic, dynamic> json) => ArchivedSessionItem(
        sessionId: '${json['sessionId'] ?? ''}',
        provider: (json['provider'] as String?) ?? '',
        projectId: json['projectId'] == null ? null : '${json['projectId']}',
        projectPath: json['projectPath'] as String?,
        projectDisplayName: (json['projectDisplayName'] as String?) ?? '',
        sessionTitle: (json['sessionTitle'] as String?) ?? '',
        lastActivity: parseServerDate(json['lastActivity']),
        isProjectArchived: json['isProjectArchived'] == true,
      );

  String get displayTitle {
    final uuidLike = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (sessionTitle.isEmpty || uuidLike.hasMatch(sessionTitle)) return '(未命名会话)';
    return sessionTitle;
  }
}
