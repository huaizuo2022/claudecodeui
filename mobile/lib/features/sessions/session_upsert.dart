import '../../core/models/project.dart';

/// Sidebar deltas derived from one `session_upserted` frame, mirroring the
/// web's `upsertSessionIntoProject` semantics.
class SessionUpserted {
  SessionUpserted.fromJson(Map<dynamic, dynamic> raw)
      : sessionId = '${raw['sessionId'] ?? ''}',
        providerSessionId = raw['providerSessionId'] == null
            ? null
            : '${raw['providerSessionId']}',
        provider = '${raw['provider'] ?? ''}',
        summary = raw['session'] is Map ? '${(raw['session'] as Map)['summary'] ?? ''}' : '',
        messageCount = raw['session'] is Map && (raw['session'] as Map)['messageCount'] is num
            ? ((raw['session'] as Map)['messageCount'] as num).toInt()
            : 0,
        lastActivity = raw['session'] is Map
            ? parseServerDate((raw['session'] as Map)['lastActivity'])
            : null,
        project = raw['project'] is Map
            ? ProjectUpsertedInfo.fromJson(raw['project'] as Map<dynamic, dynamic>)
            : null {
    if (sessionId.trim().isEmpty) {
      throw ArgumentError('session_upserted without sessionId');
    }
  }

  final String sessionId;
  final String? providerSessionId;
  final String provider;
  final String summary;
  final int messageCount;
  final DateTime? lastActivity;
  final ProjectUpsertedInfo? project;

  /// The provider's native id aliases the app session id, so both have to
  /// match when looking up the row to update.
  Set<String> get aliasIds {
    final ids = <String>{};
    if (sessionId.trim().isNotEmpty) ids.add(sessionId.trim());
    if (providerSessionId != null && providerSessionId!.trim().isNotEmpty) {
      ids.add(providerSessionId!.trim());
    }
    return ids;
  }

  SessionSummary toSessionSummary() => SessionSummary(
        id: sessionId,
        provider: provider,
        summary: summary,
        messageCount: messageCount,
        lastActivity: lastActivity ?? DateTime.now(),
      );
}

class ProjectUpsertedInfo {
  ProjectUpsertedInfo.fromJson(Map<dynamic, dynamic> raw)
      : projectId = '${raw['projectId'] ?? ''}',
        path = (raw['path'] as String?) ?? '',
        fullPath = (raw['fullPath'] as String?) ?? (raw['path'] as String?) ?? '',
        displayName = (raw['displayName'] as String?) ?? '',
        isStarred = raw['isStarred'] == true;

  final String projectId;
  final String path;
  final String fullPath;
  final String displayName;
  final bool isStarred;
}

/// Applies one upsert to a project list, returning a new list (or the same
/// instance when nothing changed). Rules copied from the web client:
/// - session rows are matched by app id or provider-native id (aliases)
/// - an empty incoming summary never blanks an existing title (fresh sessions
///   broadcast an empty custom_name before the disk indexer fills it in)
/// - unknown sessions are inserted at the newest edge and bump `total`
/// - unknown projects are created from the event payload, project first
List<ProjectSummary> applySessionUpserted(
  List<ProjectSummary> projects,
  SessionUpserted upsert,
) {
  final projectInfo = upsert.project;
  final index = projectInfo == null
      ? _findProjectContaining(projects, upsert)
      : projects.indexWhere((candidate) => candidate.projectId == projectInfo.projectId);

  if (index < 0) {
    if (projectInfo == null) return projects;
    final fresh = ProjectSummary(
      projectId: projectInfo.projectId,
      path: projectInfo.path,
      displayName: projectInfo.displayName,
      fullPath: projectInfo.fullPath,
      isStarred: projectInfo.isStarred,
      sessions: [upsert.toSessionSummary()],
      totalSessions: 1,
    );
    return [fresh, ...projects];
  }

  final updated = _upsertIntoProject(projects[index], upsert);
  if (identical(updated, projects[index])) return projects;
  return [
    for (var i = 0; i < projects.length; i++)
      i == index ? updated : projects[i],
  ];
}

/// Without project info, fall back to scanning loaded rows for the aliases.
int _findProjectContaining(List<ProjectSummary> projects, SessionUpserted upsert) {
  for (var i = 0; i < projects.length; i++) {
    if (projects[i].sessions.any((session) => upsert.aliasIds.contains(session.id))) {
      return i;
    }
  }
  return -1;
}

ProjectSummary _upsertIntoProject(ProjectSummary project, SessionUpserted upsert) {
  final aliasIds = upsert.aliasIds;
  final normalized = upsert.toSessionSummary();

  final existingIndex = project.sessions.indexWhere((session) => aliasIds.contains(session.id));

  // Unknown session: newest edge first, total + 1 (mirrors the web counter).
  if (existingIndex < 0) {
    return ProjectSummary(
      projectId: project.projectId,
      path: project.path,
      displayName: project.displayName,
      fullPath: project.fullPath,
      isStarred: project.isStarred,
      sessions: [normalized, ...project.sessions],
      totalSessions: project.totalSessions + 1,
    );
  }

  var changed = false;
  final nextSessions = <SessionSummary>[];
  final hasTitle = normalized.summary.trim().isNotEmpty;

  for (var i = 0; i < project.sessions.length; i++) {
    final existing = project.sessions[i];

    if (i == existingIndex) {
      final merged = SessionSummary(
        id: existing.id,
        provider: normalized.provider.isNotEmpty ? normalized.provider : existing.provider,
        // An empty incoming summary must not blank a title we already have:
        // fresh sessions momentarily broadcast an empty custom_name.
        summary: hasTitle ? normalized.summary : existing.summary,
        messageCount: normalized.messageCount > 0 ? normalized.messageCount : existing.messageCount,
        // Prefer the shipped activity stamp; when the frame lacks one
        // (rare), keep what the row already shows.
        lastActivity: upsert.lastActivity ?? existing.lastActivity,
      );
      // Compare by epoch: the server sends UTC, the store holds local time,
      // and DateTime equality also compares the isUtc flag — the same moment
      // must count as unchanged.
      final lastChanged = merged.lastActivity.millisecondsSinceEpoch !=
          existing.lastActivity.millisecondsSinceEpoch;
      if (merged.summary != existing.summary ||
          merged.messageCount != existing.messageCount ||
          lastChanged ||
          merged.provider != existing.provider) {
        changed = true;
      }
      nextSessions.add(merged);
      continue;
    }

    // Duplicate alias row: the web client drops it on upsert.
    if (aliasIds.contains(existing.id)) {
      changed = true;
      continue;
    }

    nextSessions.add(existing);
  }

  if (!changed) return project;
  return ProjectSummary(
    projectId: project.projectId,
    path: project.path,
    displayName: project.displayName,
    fullPath: project.fullPath,
    isStarred: project.isStarred,
    sessions: nextSessions,
    totalSessions: project.totalSessions,
  );
}