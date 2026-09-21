import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/projects_api.dart';
import '../../core/api/sessions_api.dart';
import '../../core/models/project.dart';
import '../../core/models/session.dart';
import '../../core/providers.dart';
import '../../core/util/logger.dart';
import 'session_upsert.dart';

/// Projects with their sessions, mirroring the web sidebar.
///
/// Unlike the web's static fetch, this one stays subscribed to the app socket
/// while the home screen exists: every `session_upserted` frame updates the
/// list in place (new sessions appear, counts and titles move, brand-new
/// projects pin themselves to the top), exactly like the web client's sidebar.
final projectsProvider = AsyncNotifierProvider<ProjectsController, List<ProjectSummary>>(
  ProjectsController.new,
);

class ProjectsController extends AsyncNotifier<List<ProjectSummary>> {
  static const _log = Logger('projects');

  ProjectsApi? _api;
  bool _listening = false;

  @override
  Future<List<ProjectSummary>> build() {
    final api = ProjectsApi(ref.watch(apiClientProvider));
    _api = api;

    final socket = ref.watch(chatSocketProvider);
    socket.addListener(_onFrame);
    _listening = true;
    ref.onDispose(() {
      if (_listening) socket.removeListener(_onFrame);
    });

    return api.listProjects();
  }

  /// Pulls a fresh list from the server, keeping the current rows visible
  /// until the new page lands (no loading flash on pull-to-refresh).
  Future<void> refresh() async {
    final api = _api;
    if (api == null) return;
    state = await AsyncValue.guard(() => api.listProjects());
  }

  void _onFrame(Map<dynamic, dynamic> frame) {
    if (frame['kind'] != 'session_upserted') return;
    try {
      final upsert = SessionUpserted.fromJson(frame);
      final current = state.value ?? const <ProjectSummary>[];
      final next = applySessionUpserted(current, upsert);
      if (!identical(next, current)) {
        state = AsyncData(next);
      }
    } catch (error) {
      _log.warn('bad session_upserted frame: $error');
    }
  }
}

/// "最近会话" block, mirroring the web home screen. Refreshed on pull, not
/// live (the web does the same — only the sidebar listens to upserts).
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
  await ref.read(projectsProvider.notifier).refresh();
  await ref.read(recentSessionsProvider.future);
});