import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/projects_api.dart';
import '../../core/models/project.dart';
import '../../core/providers.dart';

/// Project + session snapshot for the list page.
///
/// M2 layers the websocket deltas (`session_upserted`) and per-project paging
/// on top of this; the page already reads the same shape either way.
final projectsProvider = FutureProvider<List<ProjectSummary>>((ref) async {
  final api = ProjectsApi(ref.watch(apiClientProvider));
  return api.listProjects();
});

/// One flattened row per session, newest first — the shape the list renders.
class SessionRow {
  const SessionRow({required this.project, required this.session});

  final ProjectSummary project;
  final SessionSummary session;
}

final sessionRowsProvider = Provider<List<SessionRow>>((ref) {
  final projects = ref.watch(projectsProvider).value ?? const <ProjectSummary>[];
  final rows = <SessionRow>[
    for (final project in projects)
      for (final session in project.sessions) SessionRow(project: project, session: session),
  ];
  rows.sort((a, b) => b.session.lastActivity.compareTo(a.session.lastActivity));
  return rows;
});

/// Project filter selection; null means "全部".
class SelectedProjectController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? projectId) => state = projectId;
}

final selectedProjectIdProvider =
    NotifierProvider<SelectedProjectController, String?>(SelectedProjectController.new);

/// Case-insensitive filter across session summary and project name.
class SessionSearchController extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;
}

final sessionSearchQueryProvider =
    NotifierProvider<SessionSearchController, String>(SessionSearchController.new);

final filteredSessionRowsProvider = Provider<List<SessionRow>>((ref) {
  final rows = ref.watch(sessionRowsProvider);
  final query = ref.watch(sessionSearchQueryProvider).trim().toLowerCase();
  final projectId = ref.watch(selectedProjectIdProvider);
  return rows.where((row) {
    if (projectId != null && row.project.projectId != projectId) return false;
    if (query.isEmpty) return true;
    return row.session.summary.toLowerCase().contains(query) ||
        row.project.displayName.toLowerCase().contains(query);
  }).toList(growable: false);
});
