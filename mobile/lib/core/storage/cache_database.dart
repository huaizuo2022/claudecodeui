import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/chat_message.dart';
import '../models/project.dart';
import '../models/session.dart';

/// SQLite local persistent cache for offline-first capabilities.
///
/// Caches projects, recent sessions, and conversation messages locally so that
/// the user can immediately open and browse them even with no network connection.
class CacheDatabase {
  CacheDatabase({Database? db}) : _db = db;

  Database? _db;

  static const String dbName = 'cloudcli_cache.db';
  static const int dbVersion = 1;

  Database get db {
    final d = _db;
    if (d == null) {
      throw StateError('CacheDatabase has not been initialized. Call init() first.');
    }
    return d;
  }

  bool get isInitialized => _db != null;

  /// Initializes the SQLite database.
  /// If [customDb] is provided, uses it directly (e.g. in-memory database for tests).
  Future<void> init({Database? customDb, String? customPath}) async {
    if (_db != null) return;
    if (customDb != null) {
      _db = customDb;
      await _createTables(_db!);
      return;
    }

    final databasePath = customPath ?? p.join(await getDatabasesPath(), dbName);
    _db = await openDatabase(
      databasePath,
      version: dbVersion,
      onCreate: (db, version) async {
        await _createTables(db);
      },
    );
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_projects (
        project_id TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        display_name TEXT NOT NULL,
        full_path TEXT NOT NULL,
        is_starred INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        total_sessions INTEGER NOT NULL DEFAULT 0,
        sessions_json TEXT NOT NULL DEFAULT '[]',
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_recent_sessions (
        session_id TEXT PRIMARY KEY,
        provider TEXT NOT NULL,
        project_id TEXT,
        project_display_name TEXT NOT NULL,
        session_title TEXT NOT NULL,
        last_activity TEXT,
        is_project_starred INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        role TEXT,
        content TEXT,
        timestamp TEXT NOT NULL,
        raw_json TEXT NOT NULL,
        seq_order INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cached_messages_session 
      ON cached_messages(session_id, seq_order)
    ''');
  }

  // ── Projects Cache ────────────────────────────────────────────────────────

  /// Saves the complete list of projects to SQLite.
  Future<void> saveProjects(List<ProjectSummary> projects) async {
    if (!isInitialized) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete('cached_projects');
      final batch = txn.batch();
      for (final project in projects) {
        final sessionsJson = jsonEncode(project.sessions.map((s) => s.toJson()).toList());
        batch.insert(
          'cached_projects',
          {
            'project_id': project.projectId,
            'path': project.path,
            'display_name': project.displayName,
            'full_path': project.fullPath,
            'is_starred': project.isStarred ? 1 : 0,
            'is_archived': project.isArchived ? 1 : 0,
            'total_sessions': project.totalSessions,
            'sessions_json': sessionsJson,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Retrieves all cached projects.
  Future<List<ProjectSummary>> getProjects() async {
    if (!isInitialized) return const [];
    final rows = await db.query(
      'cached_projects',
      orderBy: 'is_starred DESC, updated_at DESC',
    );

    return rows.map((row) {
      final rawSessions = jsonDecode(row['sessions_json'] as String? ?? '[]');
      final sessions = rawSessions is List
          ? rawSessions
              .whereType<Map>()
              .map(SessionSummary.fromJson)
              .toList(growable: false)
          : const <SessionSummary>[];

      return ProjectSummary(
        projectId: row['project_id'] as String,
        path: row['path'] as String,
        displayName: row['display_name'] as String,
        fullPath: row['full_path'] as String,
        isStarred: (row['is_starred'] as int? ?? 0) == 1,
        isArchived: (row['is_archived'] as int? ?? 0) == 1,
        sessions: sessions,
        totalSessions: row['total_sessions'] as int? ?? sessions.length,
      );
    }).toList(growable: false);
  }

  /// Updates the star status of a project in local cache.
  Future<void> updateProjectStar(String projectId, bool isStarred) async {
    if (!isInitialized) return;
    final starredInt = isStarred ? 1 : 0;
    await db.transaction((txn) async {
      await txn.update(
        'cached_projects',
        {'is_starred': starredInt},
        where: 'project_id = ?',
        whereArgs: [projectId],
      );
      await txn.update(
        'cached_recent_sessions',
        {'is_project_starred': starredInt},
        where: 'project_id = ?',
        whereArgs: [projectId],
      );
    });
  }

  // ── Recent Sessions Cache ──────────────────────────────────────────────────

  /// Saves the first page or snapshot of recent sessions.
  Future<void> saveRecentSessions(
    List<RecentSession> sessions, {
    int? total,
    bool? hasMore,
  }) async {
    if (!isInitialized) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete('cached_recent_sessions');
      final batch = txn.batch();
      for (var i = 0; i < sessions.length; i++) {
        final session = sessions[i];
        batch.insert(
          'cached_recent_sessions',
          {
            'session_id': session.sessionId,
            'provider': session.provider,
            'project_id': session.projectId,
            'project_display_name': session.projectDisplayName,
            'session_title': session.sessionTitle,
            'last_activity': session.lastActivity?.toIso8601String(),
            'is_project_starred': session.isProjectStarred ? 1 : 0,
            'sort_order': i,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (total != null) {
        batch.insert(
          'cached_meta',
          {'key': 'recent_total', 'value': total.toString()},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (hasMore != null) {
        batch.insert(
          'cached_meta',
          {'key': 'recent_has_more', 'value': hasMore ? '1' : '0'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    });
  }

  /// Retrieves cached recent sessions page.
  ///
  /// [provider] narrows cached rows to one client (`claude`/`codex`/`cursor`/
  /// `opencode`) when the device is offline; omitted/null reads all rows.
  Future<RecentSessionsPage> getRecentSessions({String? provider}) async {
    if (!isInitialized) {
      return const RecentSessionsPage(conversations: [], total: 0, hasMore: false);
    }
    final rows = await db.query(
      'cached_recent_sessions',
      orderBy: 'sort_order ASC',
      where: (provider != null && provider.isNotEmpty) ? 'provider = ?' : null,
      whereArgs: (provider != null && provider.isNotEmpty) ? [provider] : null,
    );

    final conversations = rows.map((row) {
      return RecentSession(
        sessionId: row['session_id'] as String,
        provider: row['provider'] as String,
        projectId: row['project_id'] as String?,
        projectDisplayName: row['project_display_name'] as String,
        sessionTitle: row['session_title'] as String,
        lastActivity: parseServerDate(row['last_activity']),
        isProjectStarred: (row['is_project_starred'] as int? ?? 0) == 1,
      );
    }).toList(growable: false);

    final metaRows = await db.query('cached_meta');
    final metaMap = {for (final m in metaRows) m['key'] as String: m['value'] as String};
    final total = int.tryParse(metaMap['recent_total'] ?? '') ?? conversations.length;
    final hasMore = metaMap['recent_has_more'] == '1';

    return RecentSessionsPage(
      conversations: conversations,
      total: total,
      hasMore: hasMore,
    );
  }

  /// Upserts a single recent session into cache.
  Future<void> upsertRecentSession(RecentSession session) async {
    if (!isInitialized) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'cached_recent_sessions',
      {
        'session_id': session.sessionId,
        'provider': session.provider,
        'project_id': session.projectId,
        'project_display_name': session.projectDisplayName,
        'session_title': session.sessionTitle,
        'last_activity': session.lastActivity?.toIso8601String(),
        'is_project_starred': session.isProjectStarred ? 1 : 0,
        'sort_order': 0, // Put at top if new
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Messages Cache ────────────────────────────────────────────────────────

  /// Saves or updates messages for a specific session.
  Future<void> saveMessages(String sessionId, List<ChatMessage> messages) async {
    if (!isInitialized || messages.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (var i = 0; i < messages.length; i++) {
        final msg = messages[i];
        batch.insert(
          'cached_messages',
          {
            'id': msg.id,
            'session_id': sessionId,
            'kind': msg.kind,
            'role': msg.role,
            'content': msg.content,
            'timestamp': msg.timestamp,
            'raw_json': jsonEncode(msg.toJson()),
            'seq_order': i,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Retrieves cached messages for a session.
  Future<List<ChatMessage>> getMessages(String sessionId) async {
    if (!isInitialized) return const [];
    final rows = await db.query(
      'cached_messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'seq_order ASC, timestamp ASC',
    );

    return rows.map((row) {
      try {
        final raw = jsonDecode(row['raw_json'] as String) as Map<dynamic, dynamic>;
        return ChatMessage.fromJson(raw);
      } catch (_) {
        return ChatMessage(
          id: row['id'] as String,
          kind: row['kind'] as String,
          timestamp: row['timestamp'] as String,
          sessionId: sessionId,
          role: row['role'] as String?,
          content: row['content'] as String?,
        );
      }
    }).toList(growable: false);
  }

  // ── Maintenance ───────────────────────────────────────────────────────────

  /// Clears all cached data (e.g. on logout or server switch).
  Future<void> clearAll() async {
    if (!isInitialized) return;
    await db.transaction((txn) async {
      await txn.delete('cached_projects');
      await txn.delete('cached_recent_sessions');
      await txn.delete('cached_meta');
      await txn.delete('cached_messages');
    });
  }

  /// Closes the database connection.
  Future<void> close() async {
    final d = _db;
    if (d != null) {
      await d.close();
      _db = null;
    }
  }
}
