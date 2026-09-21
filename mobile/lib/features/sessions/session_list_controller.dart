import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
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

  /// Per-project toggle sequence: only the newest in-flight request may write
  /// back, so rapid taps on the same star never resurrect a stale response.
  final Map<String, int> _starToggleSequences = {};

  /// Completes with the error message when a star toggle fails, or `null` on
  /// success. A fresh `toggleStar` call replaces the previous future so the UI
  /// can always await the latest outcome.
  Completer<String?>? _starErrorCompleter;

  /// The outcome of the most recent star toggle, for toast-style reporting.
  Future<String?> get lastStarError =>
      (_starErrorCompleter ??= Completer<String?>()).future;

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

  /// Optimistic star toggle, mirroring the web sidebar: the row flips
  /// immediately, the server call follows, and a failure rolls the star back
  /// and surfaces the error. Later responses are ignored once a newer toggle
  /// for the same project is in flight (last tap wins).
  Future<void> toggleStar(String projectId) async {
    final api = _api;
    final current = state.value;
    if (api == null || current == null) return;

    final index = current.indexWhere((project) => project.projectId == projectId);
    if (index == -1) return;

    final previous = current[index];
    final nextStarred = !previous.isStarred;
    state = AsyncData([...current]..[index] = _withStar(previous, nextStarred));

    // Per-project sequence: only the newest in-flight request may write back,
    // so rapid taps on the same star never resurrect a stale response.
    final sequence = (_starToggleSequences[projectId] ?? 0) + 1;
    _starToggleSequences[projectId] = sequence;
    // A fresh toggle replaces the pending outcome so the UI always awaits the
    // latest one. `lastStarError` is recreated lazily on the next read.
    _starErrorCompleter?.complete(null);
    _starErrorCompleter = null;
    try {
      final serverStarred = await api.toggleStar(projectId);
      if (_starToggleSequences[projectId] != sequence) return;
      if (serverStarred == previous.isStarred) return;
      final latest = state.value;
      if (latest == null) return;
      final latestIndex = latest.indexWhere((project) => project.projectId == projectId);
      if (latestIndex != -1) {
        state = AsyncData(
          [...latest]..[latestIndex] = _withStar(latest[latestIndex], serverStarred),
        );
      }
    } on ApiException catch (error) {
      // Sequence guard first: a newer toggle already took over this project,
      // so this failure belongs to an abandoned request.
      if (_starToggleSequences[projectId] != sequence) return;
      (_starErrorCompleter ??= Completer<String?>()).complete(error.message);
      final latest = state.value;
      if (latest == null) return;
      final latestIndex = latest.indexWhere((project) => project.projectId == projectId);
      if (latestIndex != -1) {
        state = AsyncData(
          [...latest]..[latestIndex] = _withStar(latest[latestIndex], previous.isStarred),
        );
      }
    }
  }

  ProjectSummary _withStar(ProjectSummary project, bool isStarred) => ProjectSummary(
        projectId: project.projectId,
        path: project.path,
        displayName: project.displayName,
        fullPath: project.fullPath,
        isStarred: isStarred,
        sessions: project.sessions,
        totalSessions: project.totalSessions,
      );

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
/// live (the web does the same — only the sidebar listens to upserts). Star
/// state is overlaid from [projectsProvider] so a toggle in either block
/// reflects in both instantly.
final recentSessionsProvider = FutureProvider<List<RecentSession>>((ref) async {
  final api = SessionsApi(ref.watch(apiClientProvider));
  return api.recentSessions(limit: 20);
});

/// Recent rows with the owning project's (possibly optimistic) star state
/// folded in — the server only sends `isProjectStarred` for its own snapshot.
final recentSessionsWithStarProvider = Provider<List<RecentSession>>((ref) {
  final sessions = ref.watch(recentSessionsProvider).value ?? const <RecentSession>[];
  final projects = ref.watch(projectsProvider).value ?? const <ProjectSummary>[];
  if (projects.isEmpty) return sessions;
  final starByProjectId = {
    for (final project in projects) project.projectId: project.isStarred,
  };
  return sessions
      .map((session) {
        final projectId = session.projectId;
        if (projectId == null || !starByProjectId.containsKey(projectId)) {
          return session;
        }
        final starred = starByProjectId[projectId]!;
        if (starred == session.isProjectStarred) return session;
        return RecentSession(
          sessionId: session.sessionId,
          provider: session.provider,
          projectId: session.projectId,
          projectDisplayName: session.projectDisplayName,
          sessionTitle: session.sessionTitle,
          lastActivity: session.lastActivity,
          isProjectStarred: starred,
        );
      })
      .toList(growable: false);
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
  final sessions = ref.watch(recentSessionsWithStarProvider);
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
/// visible (they are destinations too) unless a query is active. Starred
/// projects float to the top, matching the web sidebar's `sortProjects`.
final visibleProjectsProvider = Provider<List<VisibleProject>>((ref) {
  final query = _normalize(ref.watch(sessionSearchQueryProvider));
  final projects = ref.watch(projectsProvider).value ?? const <ProjectSummary>[];
  final visible = projects.map((project) {
    final sessions = query.isEmpty
        ? project.sessions
        : project.sessions
            .where((session) =>
                session.summary.toLowerCase().contains(query) ||
                project.displayName.toLowerCase().contains(query))
            .toList(growable: false);
    return VisibleProject(project: project, sessions: sessions);
  }).toList(growable: false);
  visible.sort((a, b) {
    if (a.project.isStarred != b.project.isStarred) {
      return a.project.isStarred ? -1 : 1;
    }
    return 0;
  });
  return visible;
});

/// Refreshes both home blocks at once (pull-to-refresh).
final homeRefreshProvider = Provider<Future<void> Function()>((ref) => () async {
  ref.invalidate(recentSessionsProvider);
  await ref.read(projectsProvider.notifier).refresh();
  await ref.read(recentSessionsProvider.future);
});