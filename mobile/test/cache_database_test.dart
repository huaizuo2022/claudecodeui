import 'package:cloudcli_mobile/core/models/chat_message.dart';
import 'package:cloudcli_mobile/core/models/project.dart';
import 'package:cloudcli_mobile/core/models/session.dart';
import 'package:cloudcli_mobile/core/storage/cache_database.dart';
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
    await cacheDb.close();
  });

  test('saves and retrieves cached projects with sessions', () async {
    final projects = [
      ProjectSummary(
        projectId: 'p1',
        path: '/path/p1',
        displayName: 'Project 1',
        fullPath: '/full/path/p1',
        isStarred: true,
        isArchived: false,
        sessions: [
          SessionSummary(
            id: 's1',
            provider: 'claude',
            summary: 'Session 1',
            messageCount: 5,
            lastActivity: DateTime(2026, 9, 22, 10, 0),
          ),
        ],
        totalSessions: 1,
      ),
      ProjectSummary(
        projectId: 'p2',
        path: '/path/p2',
        displayName: 'Project 2',
        fullPath: '/full/path/p2',
        isStarred: false,
        isArchived: false,
        sessions: const [],
        totalSessions: 0,
      ),
    ];

    await cacheDb.saveProjects(projects);
    final loaded = await cacheDb.getProjects();

    expect(loaded.length, 2);
    expect(loaded[0].projectId, 'p1');
    expect(loaded[0].displayName, 'Project 1');
    expect(loaded[0].isStarred, true);
    expect(loaded[0].sessions.length, 1);
    expect(loaded[0].sessions[0].id, 's1');
    expect(loaded[0].sessions[0].summary, 'Session 1');
    expect(loaded[1].projectId, 'p2');
    expect(loaded[1].isStarred, false);
  });

  test('updates project star status in cache', () async {
    final projects = [
      ProjectSummary(
        projectId: 'p1',
        path: '/path/p1',
        displayName: 'Project 1',
        fullPath: '/full/path/p1',
        isStarred: false,
        sessions: const [],
        totalSessions: 0,
      ),
    ];

    await cacheDb.saveProjects(projects);
    await cacheDb.updateProjectStar('p1', true);

    final loaded = await cacheDb.getProjects();
    expect(loaded[0].isStarred, true);
  });

  test('saves and retrieves recent sessions and pagination meta', () async {
    final recent = [
      RecentSession(
        sessionId: 's1',
        provider: 'claude',
        projectId: 'p1',
        projectDisplayName: 'Project 1',
        sessionTitle: 'Recent 1',
        lastActivity: DateTime(2026, 9, 22, 10, 0),
        isProjectStarred: true,
      ),
      RecentSession(
        sessionId: 's2',
        provider: 'codex',
        projectId: null,
        projectDisplayName: '',
        sessionTitle: 'Recent 2',
        lastActivity: null,
        isProjectStarred: false,
      ),
    ];

    await cacheDb.saveRecentSessions(recent, total: 42, hasMore: true);
    final page = await cacheDb.getRecentSessions();

    expect(page.total, 42);
    expect(page.hasMore, true);
    expect(page.conversations.length, 2);
    expect(page.conversations[0].sessionId, 's1');
    expect(page.conversations[0].sessionTitle, 'Recent 1');
    expect(page.conversations[0].isProjectStarred, true);
    expect(page.conversations[1].sessionId, 's2');
  });

  test('saves and retrieves chat messages for a session', () async {
    final messages = [
      ChatMessage(
        id: 'm1',
        kind: 'text',
        timestamp: '2026-09-22T10:00:00Z',
        sessionId: 's1',
        role: 'user',
        content: 'Hello offline',
      ),
      ChatMessage(
        id: 'm2',
        kind: 'text',
        timestamp: '2026-09-22T10:00:05Z',
        sessionId: 's1',
        role: 'assistant',
        content: 'I am cached offline',
      ),
    ];

    await cacheDb.saveMessages('s1', messages);
    final loaded = await cacheDb.getMessages('s1');

    expect(loaded.length, 2);
    expect(loaded[0].id, 'm1');
    expect(loaded[0].content, 'Hello offline');
    expect(loaded[1].id, 'm2');
    expect(loaded[1].content, 'I am cached offline');
  });

  test('clearAll removes all cached records', () async {
    await cacheDb.saveProjects([
      ProjectSummary(
        projectId: 'p1',
        path: '/p1',
        displayName: 'P1',
        fullPath: '/p1',
        isStarred: false,
        sessions: const [],
        totalSessions: 0,
      )
    ]);
    await cacheDb.saveRecentSessions([
      RecentSession(
        sessionId: 's1',
        provider: 'claude',
        projectId: 'p1',
        projectDisplayName: 'P1',
        sessionTitle: 'S1',
        lastActivity: null,
        isProjectStarred: false,
      )
    ]);

    await cacheDb.clearAll();

    expect(await cacheDb.getProjects(), isEmpty);
    final recent = await cacheDb.getRecentSessions();
    expect(recent.conversations, isEmpty);
  });
}
