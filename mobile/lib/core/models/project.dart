/// Subset of `/api/projects` the mobile list needs.
///
/// The endpoint returns a bare array of these (no `{success, data}` wrapper),
/// each carrying its own page of sessions.
class ProjectSummary {
  const ProjectSummary({
    required this.projectId,
    required this.path,
    required this.displayName,
    required this.fullPath,
    required this.isStarred,
    required this.sessions,
    required this.totalSessions,
  });

  final String projectId;
  final String path;
  final String displayName;
  final String fullPath;
  final bool isStarred;
  final List<SessionSummary> sessions;

  /// Total sessions the project has, which can exceed [sessions].
  final int totalSessions;

  factory ProjectSummary.fromJson(Map<dynamic, dynamic> json) {
    final rawSessions = json['sessions'];
    final rawMeta = json['sessionMeta'];
    return ProjectSummary(
      projectId: '${json['projectId']}',
      path: (json['path'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
      fullPath: (json['fullPath'] as String?) ?? '',
      isStarred: json['isStarred'] == true,
      sessions: rawSessions is List
          ? rawSessions
              .whereType<Map>()
              .map(SessionSummary.fromJson)
              .toList(growable: false)
          : const [],
      totalSessions: rawMeta is Map && rawMeta['total'] is num
          ? (rawMeta['total'] as num).toInt()
          : (rawSessions is List ? rawSessions.length : 0),
    );
  }
}

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.provider,
    required this.summary,
    required this.messageCount,
    required this.lastActivity,
  });

  final String id;
  final String provider;
  final String summary;
  final int messageCount;
  final DateTime lastActivity;

  factory SessionSummary.fromJson(Map<dynamic, dynamic> json) {
    return SessionSummary(
      id: '${json['id']}',
      provider: (json['provider'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      messageCount: json['messageCount'] is num ? (json['messageCount'] as num).toInt() : 0,
      lastActivity: parseServerDate(json['lastActivity']) ?? DateTime.now(),
    );
  }
}

/// The server mixes ISO strings with SQLite `YYYY-MM-DD HH:MM:SS` stamps, so
/// both shapes have to parse.
DateTime? parseServerDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final direct = DateTime.tryParse(value);
  if (direct != null) return direct.toLocal();
  final normalized = value.contains('T') ? value : value.replaceFirst(' ', 'T');
  final withZone = normalized.endsWith('Z') ? normalized : '${normalized}Z';
  return DateTime.tryParse(withZone)?.toLocal();
}
