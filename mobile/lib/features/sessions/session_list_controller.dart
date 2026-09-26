import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/projects_api.dart';
import '../../core/api/sessions_api.dart';
import '../../core/models/project.dart';
import '../../core/models/session.dart';
import '../../core/providers.dart';
import '../../core/storage/cache_database.dart';
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
  Future<List<ProjectSummary>> build() async {
    final api = ProjectsApi(ref.watch(apiClientProvider));
    _api = api;
    final cacheDb = ref.watch(cacheDatabaseProvider);

    final socket = ref.watch(chatSocketProvider);
    socket.addListener(_onFrame);
    _listening = true;
    ref.onDispose(() {
      if (_listening) socket.removeListener(_onFrame);
    });

    final cached = await cacheDb.getProjects();
    if (cached.isNotEmpty) {
      unawaited(_syncFresh(api, cacheDb));
      return cached;
    }

    final fresh = await api.listProjects();
    await cacheDb.saveProjects(fresh);
    return fresh;
  }

  Future<void> _syncFresh(ProjectsApi api, CacheDatabase cacheDb) async {
    try {
      final fresh = await api.listProjects();
      await cacheDb.saveProjects(fresh);
      state = AsyncData(fresh);
    } catch (error) {
      _log.warn('background sync projects failed: $error');
    }
  }

  /// Pulls a fresh list from the server, keeping the current rows visible
  /// until the new page lands (no loading flash on pull-to-refresh).
  Future<void> refresh() async {
    final api = _api;
    if (api == null) return;
    final cacheDb = ref.read(cacheDatabaseProvider);
    try {
      final fresh = await api.listProjects();
      await cacheDb.saveProjects(fresh);
      state = AsyncData(fresh);
    } catch (error, st) {
      final current = state.value;
      if (current == null || current.isEmpty) {
        state = AsyncError(error, st);
      } else {
        _log.warn('refresh projects failed, keeping cached state: $error');
      }
    }
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
    unawaited(ref.read(cacheDatabaseProvider).updateProjectStar(projectId, nextStarred));

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
        unawaited(ref.read(cacheDatabaseProvider).updateProjectStar(projectId, serverStarred));
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
        unawaited(ref.read(cacheDatabaseProvider).updateProjectStar(projectId, previous.isStarred));
      }
    }
  }

  /// Creates a new project via `POST /api/projects/create-project`.
  Future<ProjectSummary> createProject({required String path, String? customName}) async {
    final api = _api;
    if (api == null) throw ApiException(message: 'API 未就绪');
    final created = await api.createProject(path: path, customName: customName);
    final current = state.value;
    if (current != null) {
      final next = [created, ...current];
      state = AsyncData(next);
      unawaited(ref.read(cacheDatabaseProvider).saveProjects(next));
    }
    return created;
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
        unawaited(ref.read(cacheDatabaseProvider).saveProjects(next));
      }
    } catch (error) {
      _log.warn('bad session_upserted frame: $error');
    }
  }
}

/// The segmented tabs from the web sidebar.
enum SidebarTab {
  conversations,
  projects,
  starred,
  running,
  archived,
}

class SidebarTabController extends Notifier<SidebarTab> {
  @override
  SidebarTab build() => SidebarTab.conversations;

  void selectTab(SidebarTab tab) => state = tab;
}

final sidebarTabProvider = NotifierProvider<SidebarTabController, SidebarTab>(
  SidebarTabController.new,
);

/// Client filter for the Conversations feed: `claude`/`codex`/`cursor`/
/// `opencode`, or null for "all clients". Tapping the active chip again
/// clears it, matching the web sidebar's filter bar.
class ProviderFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void toggle(String? provider) {
    if (provider == null || provider.isEmpty || state == provider) {
      state = null;
      return;
    }
    state = provider;
  }

  void clear() => state = null;
}

final providerFilterProvider =
    NotifierProvider<ProviderFilterController, String?>(
  ProviderFilterController.new,
);

/// State of paginated recent sessions with total count (mirroring web sidebar).
class RecentSessionsState {
  const RecentSessionsState({
    required this.conversations,
    required this.total,
    required this.hasMore,
    required this.isLoadingMore,
  });

  final List<RecentSession> conversations;
  final int total;
  final bool hasMore;
  final bool isLoadingMore;

  RecentSessionsState copyWith({
    List<RecentSession>? conversations,
    int? total,
    bool? hasMore,
    bool? isLoadingMore,
  }) =>
      RecentSessionsState(
        conversations: conversations ?? this.conversations,
        total: total ?? this.total,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );
}

class RecentSessionsNotifier extends AsyncNotifier<RecentSessionsState> {
  static const _pageSize = 40;
  static const _log = Logger('recent_sessions');
  SessionsApi? _api;

  @override
  Future<RecentSessionsState> build() async {
    final api = SessionsApi(ref.watch(apiClientProvider));
    _api = api;
    final cacheDb = ref.watch(cacheDatabaseProvider);
    // Watching the client filter rebuilds this notifier (fresh page fetch)
    // whenever the user taps a provider chip, matching the web's refetch.
    final providerFilter = ref.watch(providerFilterProvider);

    final cached = await cacheDb.getRecentSessions(provider: providerFilter);
    if (cached.conversations.isNotEmpty) {
      final cachedState = RecentSessionsState(
        conversations: cached.conversations,
        total: cached.total,
        hasMore: cached.hasMore,
        isLoadingMore: false,
      );
      unawaited(_syncFresh(api, cacheDb));
      return cachedState;
    }

    final page = await api.recentSessionsPage(
      limit: _pageSize,
      offset: 0,
      provider: providerFilter,
    );
    // Only the unfiltered feed overwrites the on-disk cache; a filtered
    // page would clobber the full list the next offline load needs.
    if (providerFilter == null) {
      await cacheDb.saveRecentSessions(
        page.conversations,
        total: page.total,
        hasMore: page.hasMore,
      );
    }
    return RecentSessionsState(
      conversations: page.conversations,
      total: page.total,
      hasMore: page.hasMore,
      isLoadingMore: false,
    );
  }

  Future<void> _syncFresh(SessionsApi api, CacheDatabase cacheDb) async {
    try {
      final providerFilter = ref.read(providerFilterProvider);
      final page = await api.recentSessionsPage(
        limit: _pageSize,
        offset: 0,
        provider: providerFilter,
      );
      if (providerFilter == null) {
        await cacheDb.saveRecentSessions(
          page.conversations,
          total: page.total,
          hasMore: page.hasMore,
        );
      }
      state = AsyncData(RecentSessionsState(
        conversations: page.conversations,
        total: page.total,
        hasMore: page.hasMore,
        isLoadingMore: false,
      ));
    } catch (e) {
      _log.warn('background sync recent sessions failed: $e');
    }
  }

  Future<void> refresh() async {
    final api = _api;
    if (api == null) return;
    final cacheDb = ref.read(cacheDatabaseProvider);
    final providerFilter = ref.read(providerFilterProvider);
    final current = state.value;
    try {
      final page = await api.recentSessionsPage(
        limit: _pageSize,
        offset: 0,
        provider: providerFilter,
      );
      if (providerFilter == null) {
        await cacheDb.saveRecentSessions(
          page.conversations,
          total: page.total,
          hasMore: page.hasMore,
        );
      }
      state = AsyncData(RecentSessionsState(
        conversations: page.conversations,
        total: page.total,
        hasMore: page.hasMore,
        isLoadingMore: false,
      ));
    } catch (e, st) {
      if (current == null) {
        state = AsyncError(e, st);
      } else {
        _log.warn('refresh recent sessions failed, keeping current state: $e');
      }
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    final api = _api;
    if (api == null || current == null || !current.hasMore || current.isLoadingMore) {
      return;
    }
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await api.recentSessionsPage(
        limit: _pageSize,
        offset: current.conversations.length,
        provider: ref.read(providerFilterProvider),
      );
      state = AsyncData(current.copyWith(
        conversations: [...current.conversations, ...page.conversations],
        total: page.total,
        hasMore: page.hasMore,
        isLoadingMore: false,
      ));
    } catch (_) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }
}

final recentSessionsStateProvider =
    AsyncNotifierProvider<RecentSessionsNotifier, RecentSessionsState>(
  RecentSessionsNotifier.new,
);

final recentSessionsProvider = Provider<AsyncValue<List<RecentSession>>>((ref) {
  final state = ref.watch(recentSessionsStateProvider);
  return state.whenData((s) => s.conversations);
});

/// Running sessions for the Activity/Running tab and badge count.
final runningSessionsProvider = FutureProvider<List<RunningSessionInfo>>((ref) async {
  final api = SessionsApi(ref.watch(apiClientProvider));
  return api.runningSessions();
});

/// Archived projects for the Archived tab.
final archivedProjectsProvider = FutureProvider<List<ProjectSummary>>((ref) async {
  final api = ProjectsApi(ref.watch(apiClientProvider));
  return api.archivedProjects();
});

/// Archived sessions for the Archived tab.
final archivedSessionsProvider = FutureProvider<List<ArchivedSessionItem>>((ref) async {
  final api = SessionsApi(ref.watch(apiClientProvider));
  return api.archivedSessions();
});

/// Recent rows with the owning project's (possibly optimistic) star state
/// folded in — the server only sends `isProjectStarred` for its own snapshot.
final recentSessionsWithStarProvider = Provider<List<RecentSession>>((ref) {
  final state = ref.watch(recentSessionsStateProvider).value;
  final sessions = state?.conversations ?? const <RecentSession>[];
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

/// Recent sessions whose project is starred, mirroring web sidebar's starred mode.
final starredSessionsProvider = Provider<List<RecentSession>>((ref) {
  final sessions = ref.watch(recentSessionsWithStarProvider);
  return sessions.where((s) => s.isProjectStarred).toList(growable: false);
});

/// Count of starred sessions (for the tab badge).
final starredSessionsCountProvider = Provider<int>((ref) {
  return ref.watch(starredSessionsProvider).length;
});

/// Starred sessions filtered by the search box.
final filteredStarredSessionsProvider = Provider<List<RecentSession>>((ref) {
  final query = _normalize(ref.watch(sessionSearchQueryProvider));
  final sessions = ref.watch(starredSessionsProvider);
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

/// Refreshes home blocks at once (pull-to-refresh or header button).
final homeRefreshProvider = Provider<Future<void> Function()>((ref) => () async {
  await Future.wait([
    ref.read(recentSessionsStateProvider.notifier).refresh(),
    ref.read(projectsProvider.notifier).refresh(),
  ]);
  ref.invalidate(runningSessionsProvider);
  ref.invalidate(archivedProjectsProvider);
  ref.invalidate(archivedSessionsProvider);
});

/// The session currently open on the chat screen, shared across providers and
/// widgets. Deliberately a plain mutable value, not a provider: it is only
/// consulted inside socket-frame handlers, and maintaining it as a provider
/// would require writes from widget life-cycles (initState/dispose) and
/// provider onDispose hooks, which Riverpod forbids. Opening a chat page sets
/// it; the page's ChatController releases it when the page unmounts.
String? activeViewedSessionId;

/// Sessions with a pending "needs attention" amber dot, mirroring the web
/// sidebar's `attentionSessionIds`: a session gets the dot when socket
/// activity for it arrives while the user is not viewing it, and loses it the
/// moment it is opened. Background progress keeps re-marking it afterwards.
class AttentionSessionsController extends Notifier<Set<String>> {
  bool _listening = false;

  @override
  Set<String> build() {
    final socket = ref.watch(chatSocketProvider);
    socket.addListener(_onFrame);
    _listening = true;
    ref.onDispose(() {
      if (_listening) socket.removeListener(_onFrame);
    });
    return const <String>{};
  }

  /// Kinds that never carry "new content the user should look at" — lifecycle
  /// and permission bookkeeping. Copied from the web's handleEvent allowlist.
  static const _ignoredKinds = {
    'chat_subscribed',
    'loading_progress',
    'session_upserted',
    'status',
    'stream_end',
    'permission_resolved',
    'permission_cancelled',
    'websocket_reconnected',
  };

  void _onFrame(Map<dynamic, dynamic> frame) {
    final kind = frame['kind'] as String?;
    if (kind == null || kind == 'socket_connected') return;
    final sid = frame['sessionId'] is String
        ? (frame['sessionId'] as String).trim()
        : '';
    if (sid.isEmpty) return;

    if (kind == 'session_upserted') {
      // The viewed session's upsert reloads its transcript in place; only
      // background progress needs a dot.
      if (sid != activeViewedSessionId) {
        markAttention(sid);
      }
      return;
    }
    if (_ignoredKinds.contains(kind)) return;
    if (sid != activeViewedSessionId) {
      markAttention(sid);
    }
  }

  /// Marks a session as needing attention unless it is the one being viewed.
  void markAttention(String sessionId) {
    final sid = sessionId.trim();
    if (sid.isEmpty || sid == activeViewedSessionId) return;
    if (state.contains(sid)) return;
    state = {...state, sid};
  }

  /// Removes the attention dot for a session the user just opened.
  void clearAttention(String sessionId) {
    final sid = sessionId.trim();
    if (sid.isEmpty || !state.contains(sid)) return;
    state = {...state}..remove(sid);
  }
}

final attentionSessionsProvider =
    NotifierProvider<AttentionSessionsController, Set<String>>(
  AttentionSessionsController.new,
);