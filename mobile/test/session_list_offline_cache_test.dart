import 'package:cloudcli_mobile/app/theme/app_theme.dart';
import 'package:cloudcli_mobile/core/api/api_client.dart';
import 'package:cloudcli_mobile/core/models/project.dart';
import 'package:cloudcli_mobile/core/models/session.dart';
import 'package:cloudcli_mobile/core/providers.dart';
import 'package:cloudcli_mobile/core/storage/cache_database.dart';
import 'package:cloudcli_mobile/features/sessions/session_list_controller.dart';
import 'package:cloudcli_mobile/features/sessions/session_list_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late CacheDatabase cacheDb;
  late Database ffiDb;

  setUp(() async {
    ffiDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    cacheDb = CacheDatabase();
    await cacheDb.init(customDb: ffiDb);
  });

  tearDown(() async {
    if (cacheDb.isInitialized) {
      await cacheDb.close();
    }
  });

  test('ProjectsController serves cached projects when network fails', () async {
    // 1. Prepopulate SQLite cache with a project
    await cacheDb.saveProjects([
      ProjectSummary(
        projectId: 'offline-proj-1',
        path: '/offline/path',
        displayName: 'Offline Project',
        fullPath: '/offline/full/path',
        isStarred: true,
        sessions: const [],
        totalSessions: 0,
      ),
    ]);

    // 2. Mock ApiClient that always fails (simulating network outage)
    final failingClient = _FailingApiClient();

    final container = ProviderContainer(
      overrides: [
        cacheDatabaseProvider.overrideWithValue(cacheDb),
        apiClientProvider.overrideWithValue(failingClient),
      ],
    );
    addTearDown(container.dispose);

    // 3. Read projectsProvider
    final projects = await container.read(projectsProvider.future);

    expect(projects.length, 1);
    expect(projects.first.projectId, 'offline-proj-1');
    expect(projects.first.displayName, 'Offline Project');
  });

  test('RecentSessionsNotifier serves cached sessions when network fails', () async {
    // 1. Prepopulate SQLite cache with recent session
    await cacheDb.saveRecentSessions([
      RecentSession(
        sessionId: 'offline-ses-1',
        provider: 'claude',
        projectId: 'offline-proj-1',
        projectDisplayName: 'Offline Project',
        sessionTitle: 'Offline Conversation',
        lastActivity: DateTime(2026, 9, 22, 10, 0),
        isProjectStarred: true,
        isStarred: false,
      ),
    ], total: 1, hasMore: false);

    final failingClient = _FailingApiClient();

    final container = ProviderContainer(
      overrides: [
        cacheDatabaseProvider.overrideWithValue(cacheDb),
        apiClientProvider.overrideWithValue(failingClient),
      ],
    );
    addTearDown(container.dispose);

    final recentState = await container.read(recentSessionsStateProvider.future);

    expect(recentState.conversations.length, 1);
    expect(recentState.conversations.first.sessionId, 'offline-ses-1');
    expect(recentState.conversations.first.sessionTitle, 'Offline Conversation');
  });

  testWidgets('SessionListPage renders cached data and offline banner when offline',
      (tester) async {
    final memDb = _MemoryCacheDatabase();
    await memDb.saveProjects([
      const ProjectSummary(
        projectId: 'offline-p1',
        path: '/offline/p1',
        displayName: 'Cached Offline Project',
        fullPath: '/offline/p1',
        isStarred: true,
        sessions: [],
        totalSessions: 0,
      ),
    ]);
    await memDb.saveRecentSessions([
      RecentSession(
        sessionId: 'offline-s1',
        provider: 'claude',
        projectId: 'offline-p1',
        projectDisplayName: 'Cached Offline Project',
        sessionTitle: 'Cached Offline Chat',
        lastActivity: DateTime(2026, 9, 22, 10, 0),
        isProjectStarred: true,
        isStarred: false,
      ),
    ], total: 1, hasMore: false);

    final failingClient = _FailingApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cacheDatabaseProvider.overrideWithValue(memDb),
          apiClientProvider.overrideWithValue(failingClient),
          socketConnectedProvider.overrideWithValue(false),
          runningSessionsProvider.overrideWith((ref) async => []),
          archivedProjectsProvider.overrideWith((ref) async => []),
          archivedSessionsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const SessionListPage(),
        ),
      ),
    );

    // Let Riverpod and cache loaders settle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify: The screen should display cached conversation without crashing into error state
    expect(find.text('Cached Offline Chat'), findsOneWidget);
    // Verify: The offline notice banner should be visible
    expect(find.text('离线模式（已加载本地缓存）'), findsOneWidget);
  });
}

class _MemoryCacheDatabase extends CacheDatabase {
  List<ProjectSummary> _projects = [];
  List<RecentSession> _recent = [];
  int _total = 0;
  bool _hasMore = false;

  @override
  bool get isInitialized => true;

  @override
  Future<void> saveProjects(List<ProjectSummary> projects) async {
    _projects = List.from(projects);
  }

  @override
  Future<List<ProjectSummary>> getProjects() async => List.from(_projects);

  @override
  Future<void> saveRecentSessions(List<RecentSession> sessions, {int? total, bool? hasMore}) async {
    _recent = List.from(sessions);
    if (total != null) _total = total;
    if (hasMore != null) _hasMore = hasMore;
  }

  @override
  Future<RecentSessionsPage> getRecentSessions({String? provider}) async {
    final filtered = (provider == null || provider.isEmpty)
        ? _recent
        : _recent.where((s) => s.provider == provider).toList();
    return RecentSessionsPage(
      conversations: List.from(filtered),
      total: (provider == null || provider.isEmpty) ? _total : filtered.length,
      hasMore: (provider == null || provider.isEmpty) ? _hasMore : false,
    );
  }

  @override
  Future<void> updateProjectStar(String projectId, bool isStarred) async {
    final idx = _projects.indexWhere((p) => p.projectId == projectId);
    if (idx != -1) {
      final p = _projects[idx];
      _projects[idx] = ProjectSummary(
        projectId: p.projectId,
        path: p.path,
        displayName: p.displayName,
        fullPath: p.fullPath,
        isStarred: isStarred,
        isArchived: p.isArchived,
        sessions: p.sessions,
        totalSessions: p.totalSessions,
      );
    }
  }

  @override
  Future<void> close() async {}
}

class _FailingApiClient extends ApiClient {
  _FailingApiClient() : super(dio: Dio());

  @override
  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) async {
    throw ApiUnreachableException();
  }
}
