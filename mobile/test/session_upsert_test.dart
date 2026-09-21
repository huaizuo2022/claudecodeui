import 'package:cloudcli_mobile/core/models/project.dart';
import 'package:cloudcli_mobile/features/sessions/session_upsert.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectSummary _project({
  String id = 'p1',
  String name = 'claudecodeui',
  List<SessionSummary>? sessions,
  int total = 0,
}) {
  return ProjectSummary(
    projectId: id,
    path: '/tmp/$name',
    displayName: name,
    fullPath: '/tmp/$name',
    isStarred: false,
    sessions: sessions ?? const [],
    totalSessions: total,
  );
}

SessionSummary _session({
  String id = 's1',
  String summary = '重构滚动',
  int count = 5,
  String last = '2026-09-21T10:00:00Z',
}) {
  return SessionSummary(
    id: id,
    provider: 'claude',
    summary: summary,
    messageCount: count,
    lastActivity: DateTime.parse(last),
  );
}

SessionUpserted _upsert({
  required String sessionId,
  String? providerSessionId,
  String summary = '新标题',
  int messageCount = 9,
  String? last = '2026-09-21T11:00:00Z',
  Map<String, dynamic>? project,
}) {
  return SessionUpserted.fromJson({
    'kind': 'session_upserted',
    'sessionId': sessionId,
    'providerSessionId': providerSessionId,
    'provider': 'claude',
    'session': {
      'id': sessionId,
      'summary': summary,
      'messageCount': messageCount,
      'lastActivity': last,
    },
    'project': project,
    'timestamp': '2026-09-21T11:00:00Z',
  });
}

void main() {
  test('updates an existing session row in place', () {
    final projects = [_project(sessions: [_session()], total: 3)];
    final next = applySessionUpserted(projects, _upsert(sessionId: 's1'));

    final session = next.first.sessions.first;
    expect(session.summary, '新标题');
    expect(session.messageCount, 9);
    expect(session.lastActivity.toUtc(), DateTime.parse('2026-09-21T11:00:00Z'));
    expect(next.first.totalSessions, 3, reason: 'update must not bump the total');
  });

  test('an empty incoming summary never blanks an existing title', () {
    final projects = [_project(sessions: [_session()], total: 3)];
    final next = applySessionUpserted(projects, _upsert(sessionId: 's1', summary: ''));

    expect(next.first.sessions.first.summary, '重构滚动');
  });

  test('messageCount of zero does not clobber a known count', () {
    final projects = [_project(sessions: [_session(count: 5)], total: 3)];
    final next = applySessionUpserted(projects, _upsert(sessionId: 's1', messageCount: 0));

    expect(next.first.sessions.first.messageCount, 5);
  });

  test('an unknown session in a known project is inserted and bumps total', () {
    final projects = [
      _project(sessions: [_session(id: 's1')], total: 1),
    ];
    final next = applySessionUpserted(
      projects,
      _upsert(
        sessionId: 'brand-new',
        project: {
          'projectId': 'p1',
          'path': '/tmp/claudecodeui',
          'displayName': 'claudecodeui',
        },
      ),
    );

    expect(next.first.sessions.length, 2);
    expect(next.first.sessions.first.id, 'brand-new');
    expect(next.first.totalSessions, 2);
  });

  test('an unknown session without project info is ignored', () {
    final projects = [
      _project(sessions: [_session(id: 's1')], total: 1),
    ];
    final next = applySessionUpserted(projects, _upsert(sessionId: 'brand-new'));

    expect(identical(next, projects), isTrue);
  });

  test('matches rows by the provider-native id alias', () {
    // The app id we know is 's1'; the server aliases it via providerSessionId.
    final projects = [_project(sessions: [_session(id: 's1')], total: 1)];
    final next = applySessionUpserted(
      projects,
      _upsert(sessionId: 'app-id-2', providerSessionId: 's1', summary: '别名更新'),
    );

    expect(next.first.sessions.length, 1, reason: 'alias row must not duplicate');
    expect(next.first.sessions.first.summary, '别名更新');
  });

  test('a brand-new project is created from the frame and pinned to the top', () {
    final projects = [_project(sessions: [_session()], total: 1)];
    final next = applySessionUpserted(
      projects,
      _upsert(
        sessionId: 's-new',
        project: {
          'projectId': 'p-new',
          'path': '/Users/shang/Dev/VelvetChat',
          'displayName': 'VelvetChat',
          'fullPath': '/Users/shang/Dev/VelvetChat',
          'isStarred': false,
        },
      ),
    );

    expect(next.length, 2);
    expect(next.first.projectId, 'p-new');
    expect(next.first.displayName, 'VelvetChat');
    expect(next.first.sessions.single.id, 's-new');
    expect(next.first.totalSessions, 1);
  });

  test('without project info it falls back to scanning loaded rows', () {
    final projects = [
      _project(id: 'p-x', sessions: [_session(id: 's1')], total: 1),
    ];
    final next = applySessionUpserted(projects, _upsert(sessionId: 's1'));

    expect(next.single.projectId, 'p-x');
    expect(next.single.sessions.first.summary, '新标题');
  });

  test('returns the same instance when nothing changed', () {
    final projects = [_project(sessions: [_session()], total: 1)];
    final next = applySessionUpserted(
      projects,
      _upsert(sessionId: 's1', summary: '重构滚动', messageCount: 5, last: '2026-09-21T10:00:00Z'),
    );

    expect(identical(next, projects), isTrue);
  });
}