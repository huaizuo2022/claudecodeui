import 'package:cloudcli_mobile/core/api/api_client.dart';
import 'package:cloudcli_mobile/core/models/chat_message.dart';
import 'package:cloudcli_mobile/core/providers.dart';
import 'package:cloudcli_mobile/core/storage/cache_database.dart';
import 'package:cloudcli_mobile/features/chat/chat_controller.dart';
import 'package:dio/dio.dart';
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
    await cacheDb.close();
  });

  test('ChatController loads cached messages when offline/network fails', () async {
    // 1. Prepopulate SQLite cache with messages for session 'test-s1'
    await cacheDb.saveMessages('test-s1', [
      ChatMessage(
        id: 'msg-1',
        kind: 'text',
        timestamp: '2026-09-22T10:00:00Z',
        sessionId: 'test-s1',
        role: 'user',
        content: 'Offline question from user',
      ),
      ChatMessage(
        id: 'msg-2',
        kind: 'text',
        timestamp: '2026-09-22T10:00:05Z',
        sessionId: 'test-s1',
        role: 'assistant',
        content: 'Offline answer from assistant',
      ),
    ]);

    final failingClient = _FailingApiClient();

    final container = ProviderContainer(
      overrides: [
        cacheDatabaseProvider.overrideWithValue(cacheDb),
        apiClientProvider.overrideWithValue(failingClient),
      ],
    );
    addTearDown(container.dispose);

    // Listen to chatControllerProvider for 'test-s1' so autoDispose doesn't dispose it
    final sub = container.listen(chatControllerProvider('test-s1'), (prev, next) {});
    addTearDown(sub.close);

    // Allow microtasks in build() to execute
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(chatControllerProvider('test-s1'));

    expect(state.historyLoaded, true);
    expect(state.messages.length, 2);
    expect(state.messages[0].id, 'msg-1');
    expect(state.messages[0].content, 'Offline question from user');
    expect(state.messages[1].id, 'msg-2');
    expect(state.messages[1].content, 'Offline answer from assistant');
  });
}

class _FailingApiClient extends ApiClient {
  _FailingApiClient() : super(dio: Dio());

  @override
  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) async {
    throw ApiUnreachableException();
  }
}
