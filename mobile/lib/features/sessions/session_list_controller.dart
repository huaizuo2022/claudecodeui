import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/projects_api.dart';
import '../../core/api/sessions_api.dart';
import '../../core/models/project.dart';
import '../../core/models/session.dart';
import '../../core/providers.dart';

/// Projects with their sessions, mirroring the web sidebar.
final projectsProvider = FutureProvider<List<ProjectSummary>>((ref) async {
  final api = ProjectsApi(ref.watch(apiClientProvider));
  return api.listProjects();
});

/// "最近会话" block, mirroring the web home screen.
final recentSessionsProvider = FutureProvider<List<RecentSession>>((ref) async {
  final api = SessionsApi(ref.watch(apiClientProvider));
  return api.recentSessions(limit: 20);
});

/// Projects the user expanded. Newly loaded projects start collapsed.
class ExpandedProjectsController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void toggle(String projectId) => state = state.contains(projectId)
      ? ({...state}..remove(projectId))
      : {...state, projectId};
}

final expandedProjectsProvider =
    NotifierProvider<ExpandedProjectsController, Set<String>>(
  ExpandedProjectsController.new,
);

class SessionSearchController extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;
}

final sessionSearchQueryProvider =
    NotifierProvider<SessionSearchController, String>(SessionSearchController.new);

String _normalize(String value) => value.trim().toLowerCase();

/// Recent rows filtered by the search box.
final filteredRecentSessionsProvider = Provider<List<RecentSession>>((ref) {
  final query = _normalize(ref.watch(sessionSearchQueryProvider));
  final sessions = ref.watch(recentSessionsProvider).value ?? const <RecentSession>[];
  if (query.isEmpty) return sessions;
  return sessions
      .where((session) =>
          session.displayTitle.toLowerCase().contains(query) ||
          session.projectDisplayName.toLowerCase().contains(query))
      .toList(growable: false);
});

class VisibleProject {
  const VisibleProject({required this.project, required this.sessions});

  final ProjectSummary project;
  final List<SessionSummary> sessions;
}

/// Projects with session rows filtered by the search box. Empty projects stay
/// visible (they are destinations too) unless a query is active.
final visibleProjectsProvider = Provider<List<VisibleProject>>((ref) {
  final query = _normalize(ref.watch(sessionSearchQueryProvider));
  final projects = ref.watch(projectsProvider).value ?? const <ProjectSummary>[];
  return projects.map((project) {
    final sessions = query.isEmpty
        ? project.sessions
        : project.sessions
            .where((session) =>
                session.summary.toLowerCase().contains(query) ||
                project.displayName.toLowerCase().contains(query))
            .toList(growable: false);
    return VisibleProject(project: project, sessions: sessions);
  }).toList(growable: false);
});

/// Refreshes both home blocks at once (pull-to-refresh).
final homeRefreshProvider = Provider<Future<void> Function()>((ref) => () async {
  ref.invalidate(recentSessionsProvider);
  ref.invalidate(projectsProvider);
  await Future.wait([
    ref.read(recentSessionsProvider.future),
    ref.read(projectsProvider.future),
  ]);
});
