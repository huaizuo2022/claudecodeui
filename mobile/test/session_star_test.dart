import 'package:cloudcli_mobile/core/api/api_client.dart';
import 'package:cloudcli_mobile/core/models/project.dart';
import 'package:cloudcli_mobile/core/models/session.dart';
import 'package:cloudcli_mobile/core/providers.dart';
import 'package:cloudcli_mobile/core/storage/cache_database.dart';
import 'package:cloudcli_mobile/features/sessions/session_list_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The star on a row marks that one conversation. A starred *project* must not
/// drag its siblings along — that is what made one tap look like "add one star,
/// get nineteen".
RecentSession _row({
  required String sessionId,
  bool isProjectStarred = false,
  bool isStarred = false,
}) =>
    RecentSession(
      sessionId: sessionId,
      provider: 'claude',
      projectId: 'proj-1',
      projectDisplayName: 'Demo Project',
      sessionTitle: 'Conversation $sessionId',
      lastActivity: DateTime(2026, 9, 22, 10, 0),
      isProjectStarred: isProjectStarred,
      isStarred: isStarred,
    );

class _MemoryCacheDatabase extends CacheDatabase {
  _MemoryCacheDatabase(this._recent);
  List<RecentSession> _recent;
  final List<({String sessionId, bool isStarred})> starWrites = [];

  @override
  bool get isInitialized => true;

  @override
  Future<void> saveProjects(List<ProjectSummary> projects) async {}

  @override
  Future<List<ProjectSummary>> getProjects() async => const [];

  @override
  Future<RecentSessionsPage> getRecentSessions({String? provider}) async =>
      RecentSessionsPage(conversations: List.from(_recent), total: _recent.length, hasMore: false);

  @override
  Future<void> saveRecentSessions(
    List<RecentSession> sessions, {
    int? total,
    bool? hasMore,
  }) async {
    _recent = List.from(sessions);
  }

  @override
  Future<void> updateRecentSessionStar(String sessionId, bool isStarred) async {
    starWrites.add((sessionId: sessionId, isStarred: isStarred));
    final index = _recent.indexWhere((s) => s.sessionId == sessionId);
    if (index != -1) _recent[index] = _recent[index].copyWithStar(isStarred);
  }

  @override
  Future<void> close() async {}
}

/// Answers `POST .../toggle-star`; everything else fails so a test that
/// accidentally reaches the network fails loudly.
class _FakeSessionsApiClient extends ApiClient {
  _FakeSessionsApiClient({this.starredAnswer, this.failPost = false})
      : super(dio: Dio());

  final bool? starredAnswer;
  final bool failPost;
  final List<String> postedPaths = [];

  @override
  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) async {
    throw ApiUnreachableException();
  }

  @override
  Future<dynamic> postJson(String path, {Object? data}) async {
    postedPaths.add(path);
    if (failPost) {
      throw ApiException(message: '服务器开小差了', statusCode: 500);
    }
    return {'isStarred': starredAnswer ?? true};
  }
}

ProviderContainer _container({
  required CacheDatabase cache,
  required ApiClient client,
}) =>
    ProviderContainer(
      overrides: [
        cacheDatabaseProvider.overrideWithValue(cache),
        apiClientProvider.overrideWithValue(client),
      ],
    );

void main() {
  test('a starred project alone does not fill the starred tab', () async {
    final cache = _MemoryCacheDatabase([
      _row(sessionId: 's1', isProjectStarred: true),
      _row(sessionId: 's2', isProjectStarred: true),
    ]);
    final container = _container(cache: cache, client: _FakeSessionsApiClient());
    addTearDown(container.dispose);

    await container.read(recentSessionsStateProvider.future);

    expect(container.read(starredSessionsProvider), isEmpty);
    expect(container.read(starredSessionsCountProvider), 0);
  });

  test('only the conversation the user starred lands in the starred tab', () async {
    final cache = _MemoryCacheDatabase([
      _row(sessionId: 's1'),
      _row(sessionId: 's2', isStarred: true),
      _row(sessionId: 's3'),
    ]);
    final container = _container(cache: cache, client: _FakeSessionsApiClient());
    addTearDown(container.dispose);

    await container.read(recentSessionsStateProvider.future);

    final starred = container.read(starredSessionsProvider);
    expect(starred.map((s) => s.sessionId), ['s2']);
    expect(container.read(starredSessionsCountProvider), 1);
  });

  test('toggling a session star flips it optimistically and persists it', () async {
    final cache = _MemoryCacheDatabase([_row(sessionId: 's1'), _row(sessionId: 's2')]);
    final client = _FakeSessionsApiClient(starredAnswer: true);
    final container = _container(cache: cache, client: client);
    addTearDown(container.dispose);
    await container.read(recentSessionsStateProvider.future);

    final notifier = container.read(recentSessionsStateProvider.notifier);
    final pending = notifier.toggleSessionStar('s1');

    // The row flips before the server answers.
    final optimistic = container.read(recentSessionsStateProvider).value!.conversations;
    expect(optimistic.firstWhere((s) => s.sessionId == 's1').isStarred, isTrue);
    expect(container.read(starredSessionsProvider).map((s) => s.sessionId), ['s1']);

    await pending;

    expect(client.postedPaths.single, 'providers/sessions/s1/toggle-star');
    expect(cache.starWrites.last, (sessionId: 's1', isStarred: true));
    expect(container.read(starredSessionsProvider).map((s) => s.sessionId), ['s1']);
    expect(await notifier.lastStarError, isNull);
  });

  test('a failed toggle rolls the star back and reports the error', () async {
    final cache = _MemoryCacheDatabase([_row(sessionId: 's1')]);
    final client = _FakeSessionsApiClient(failPost: true);
    final container = _container(cache: cache, client: client);
    addTearDown(container.dispose);
    await container.read(recentSessionsStateProvider.future);

    final notifier = container.read(recentSessionsStateProvider.notifier);
    final pending = notifier.toggleSessionStar('s1');
    final error = await notifier.lastStarError;
    await pending;

    expect(error, '服务器开小差了');
    expect(container.read(recentSessionsStateProvider).value!.conversations.single.isStarred, isFalse);
    expect(container.read(starredSessionsProvider), isEmpty);
    expect(cache.starWrites.last, (sessionId: 's1', isStarred: false));
  });

  test('unstarring an already starred conversation removes it from the tab', () async {
    final cache = _MemoryCacheDatabase([_row(sessionId: 's1', isStarred: true)]);
    final client = _FakeSessionsApiClient(starredAnswer: false);
    final container = _container(cache: cache, client: client);
    addTearDown(container.dispose);
    await container.read(recentSessionsStateProvider.future);
    expect(container.read(starredSessionsCountProvider), 1);

    await container.read(recentSessionsStateProvider.notifier).toggleSessionStar('s1');

    expect(container.read(starredSessionsCountProvider), 0);
    expect(cache.starWrites.last, (sessionId: 's1', isStarred: false));
  });
}
