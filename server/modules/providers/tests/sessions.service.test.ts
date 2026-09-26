import assert from 'node:assert/strict';
import { appendFile, mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { closeConnection, initializeDatabase, projectsDb, sessionsDb } from '@/modules/database/index.js';
import { sessionsService } from '@/modules/providers/services/sessions.service.js';

async function withIsolatedDatabase(runTest: () => void | Promise<void>): Promise<void> {
  const previousDatabasePath = process.env.DATABASE_PATH;
  const tempDirectory = await mkdtemp(path.join(os.tmpdir(), 'sessions-service-db-'));

  closeConnection();
  process.env.DATABASE_PATH = path.join(tempDirectory, 'auth.db');
  await initializeDatabase();

  try {
    await runTest();
  } finally {
    closeConnection();
    if (previousDatabasePath === undefined) {
      delete process.env.DATABASE_PATH;
    } else {
      process.env.DATABASE_PATH = previousDatabasePath;
    }
    await rm(tempDirectory, { recursive: true, force: true });
  }
}

test('provider session id returns the mapped native id', { concurrency: false }, async () => {
  await withIsolatedDatabase(() => {
    sessionsDb.createAppSession('app-session-id', 'codex', '/tmp/session-id-copy-project');
    sessionsDb.assignProviderSessionId('app-session-id', 'codex-native-session-id');

    assert.equal(sessionsService.getProviderSessionId('app-session-id'), 'codex-native-session-id');
  });
});

test('app session names use at most four whole words from the initial message', { concurrency: false }, async () => {
  await withIsolatedDatabase(() => {
    const result = sessionsService.createAppSession(
      'codex',
      '/tmp/session-name-project',
      '  supercalifragilisticexpialidocious\nsecond   third fourth fifth  ',
    );

    assert.equal(result.sessionName, 'supercalifragilisticexpialidocious second third fourth');
    assert.equal(
      sessionsDb.getSessionById(result.sessionId)?.custom_name,
      'supercalifragilisticexpialidocious second third fourth',
    );
  });
});

test('app sessions without message text receive a stable fallback name', { concurrency: false }, async () => {
  await withIsolatedDatabase(() => {
    const result = sessionsService.createAppSession('claude', '/tmp/attachment-only-project', '  \n ');

    assert.equal(result.sessionName, 'Untitled Session');
    assert.equal(sessionsDb.getSessionById(result.sessionId)?.custom_name, 'Untitled Session');
  });
});

test('provider session id is unavailable until the provider assigns one', { concurrency: false }, async () => {
  await withIsolatedDatabase(() => {
    sessionsDb.createAppSession('pending-app-session', 'claude', '/tmp/session-id-copy-project');

    assert.throws(
      () => sessionsService.getProviderSessionId('pending-app-session'),
      (error: unknown) => {
        const typedError = error as { code?: string; statusCode?: number };
        return typedError.code === 'PROVIDER_SESSION_ID_NOT_AVAILABLE' && typedError.statusCode === 409;
      },
    );
  });
});

test('provider session id reports a missing app session', { concurrency: false }, async () => {
  await withIsolatedDatabase(() => {
    assert.throws(
      () => sessionsService.getProviderSessionId('missing-session'),
      (error: unknown) => {
        const typedError = error as { code?: string; statusCode?: number };
        return typedError.code === 'SESSION_NOT_FOUND' && typedError.statusCode === 404;
      },
    );
  });
});

test('recent sessions map project metadata and preserve database pagination', { concurrency: false }, async () => {
  await withIsolatedDatabase(() => {
    sessionsDb.createSession(
      'older-session',
      'claude',
      '/tmp/recent-project',
      'Older conversation',
      '2026-08-01T08:00:00.000Z',
      '2026-08-01T09:00:00.000Z',
    );
    sessionsDb.createSession(
      'newer-session',
      'codex',
      '/tmp/recent-project',
      'Newer conversation',
      '2026-08-01T10:00:00.000Z',
      '2026-08-01T11:00:00.000Z',
    );
    projectsDb.updateCustomProjectName('/tmp/recent-project', 'Recent Project');

    const project = projectsDb.getProjectPath('/tmp/recent-project');
    const page = sessionsService.listRecentSessions(1, 0);

    assert.deepEqual(page, {
      conversations: [{
        sessionId: 'newer-session',
        provider: 'codex',
        projectId: project?.project_id ?? null,
        projectDisplayName: 'Recent Project',
        sessionTitle: 'Newer conversation',
        lastActivity: '2026-08-01T11:00:00.000Z',
        isProjectStarred: false,
        isStarred: false,
      }],
      total: 2,
      hasMore: true,
    });
  });
});

test('session stars are per conversation, not per project', { concurrency: false }, async () => {
  await withIsolatedDatabase(() => {
    // Two conversations of one project: starring either one must leave the
    // other alone. The project star is a separate flag and stays false here.
    sessionsDb.createSession(
      'sibling-one',
      'claude',
      '/tmp/star-scope-project',
      'First conversation',
      '2026-08-01T08:00:00.000Z',
      '2026-08-01T09:00:00.000Z',
    );
    sessionsDb.createSession(
      'sibling-two',
      'claude',
      '/tmp/star-scope-project',
      'Second conversation',
      '2026-08-01T10:00:00.000Z',
      '2026-08-01T11:00:00.000Z',
    );

    assert.deepEqual(sessionsService.toggleSessionStar('sibling-one'), { isStarred: true });

    const page = sessionsService.listRecentSessions(40, 0);
    const starred = page.conversations
      .filter((conversation) => conversation.isStarred)
      .map((conversation) => conversation.sessionId);
    assert.deepEqual(starred, ['sibling-one']);
    assert.equal(page.conversations.every((c) => c.isProjectStarred === false), true);
  });
});

test('toggling a session star twice returns to unstarred', { concurrency: false }, async () => {
  await withIsolatedDatabase(() => {
    sessionsDb.createSession(
      'toggle-twice',
      'claude',
      '/tmp/star-toggle-project',
      'Toggle me',
      '2026-08-01T08:00:00.000Z',
      '2026-08-01T09:00:00.000Z',
    );

    assert.deepEqual(sessionsService.toggleSessionStar('toggle-twice'), { isStarred: true });
    assert.deepEqual(sessionsService.toggleSessionStar('toggle-twice'), { isStarred: false });
    assert.equal(sessionsDb.getSessionById('toggle-twice')?.isStarred, 0);
  });
});

test('toggling a star on an unknown session reports SESSION_NOT_FOUND', { concurrency: false }, async () => {
  await withIsolatedDatabase(() => {
    assert.throws(
      () => sessionsService.toggleSessionStar('missing-session'),
      (error: unknown) => {
        const typedError = error as { code?: string; statusCode?: number };
        return typedError.code === 'SESSION_NOT_FOUND' && typedError.statusCode === 404;
      },
    );
  });
});

test('recent sessions can be narrowed to one provider client', { concurrency: false }, async () => {
  await withIsolatedDatabase(() => {
    sessionsDb.createSession(
      'claude-session',
      'claude',
      '/tmp/provider-filter-project',
      'Claude conversation',
      '2026-08-01T08:00:00.000Z',
      '2026-08-01T09:00:00.000Z',
    );
    sessionsDb.createSession(
      'codex-session',
      'codex',
      '/tmp/provider-filter-project',
      'Codex conversation',
      '2026-08-01T10:00:00.000Z',
      '2026-08-01T11:00:00.000Z',
    );
    sessionsDb.createSession(
      'cursor-session',
      'cursor',
      '/tmp/provider-filter-project',
      'Cursor conversation',
      '2026-08-01T12:00:00.000Z',
      '2026-08-01T13:00:00.000Z',
    );

    const claudePage = sessionsService.listRecentSessions(40, 0, 'claude');
    assert.deepEqual(
      claudePage.conversations.map((conversation) => conversation.sessionId),
      ['claude-session'],
    );
    assert.equal(claudePage.total, 1);
    assert.equal(claudePage.hasMore, false);

    // Absent filter keeps every client in the feed.
    const allPage = sessionsService.listRecentSessions(40, 0);
    assert.equal(allPage.total, 3);
    assert.deepEqual(
      allPage.conversations.map((conversation) => conversation.sessionId),
      ['cursor-session', 'codex-session', 'claude-session'],
    );
  });
});

/** One Claude transcript row of user or assistant text, linked by uuid chain. */
function claudeTextRow(
  sessionId: string,
  role: 'user' | 'assistant',
  text: string,
  ordinal: number,
): Record<string, unknown> {
  return {
    type: role,
    uuid: `row-${ordinal}`,
    parentUuid: ordinal === 0 ? null : `row-${ordinal - 1}`,
    timestamp: new Date(Date.UTC(2026, 0, 1, 0, 0, ordinal)).toISOString(),
    sessionId,
    message: { role, content: [{ type: 'text', text }] },
  };
}

test('history pages are sliced from the cached full transcript and see appended rows', { concurrency: false }, async () => {
  const transcriptDirectory = await mkdtemp(path.join(os.tmpdir(), 'sessions-service-history-'));
  const sessionId = 'claude-history-cache-session';
  const transcriptPath = path.join(transcriptDirectory, `${sessionId}.jsonl`);

  try {
    await withIsolatedDatabase(async () => {
      const rows = [
        claudeTextRow(sessionId, 'user', 'one', 0),
        claudeTextRow(sessionId, 'assistant', 'reply one', 1),
        claudeTextRow(sessionId, 'user', 'two', 2),
        claudeTextRow(sessionId, 'assistant', 'reply two', 3),
      ];
      await writeFile(transcriptPath, `${rows.map((row) => JSON.stringify(row)).join('\n')}\n`, 'utf8');
      sessionsDb.createSession(
        sessionId,
        'claude',
        '/tmp/history-cache-project',
        'History cache conversation',
        '2026-01-01T00:00:00.000Z',
        '2026-01-01T00:00:10.000Z',
        transcriptPath,
      );

      const page = await sessionsService.fetchHistory(sessionId, { limit: 2, offset: 0 });
      assert.equal(page.total, 4);
      assert.equal(page.hasMore, true);
      assert.deepEqual(page.messages.map((message) => message.content), ['two', 'reply two']);

      // A row appended after the page was cached must appear on the next read.
      await appendFile(
        transcriptPath,
        `${JSON.stringify(claudeTextRow(sessionId, 'user', 'three', 4))}\n`,
        'utf8',
      );
      const refreshed = await sessionsService.fetchHistory(sessionId, { limit: 2, offset: 0 });
      assert.equal(refreshed.total, 5);
      assert.deepEqual(refreshed.messages.map((message) => message.content), ['reply two', 'three']);

      // An older page keeps the tail-offset contract while served from cache.
      const older = await sessionsService.fetchHistory(sessionId, { limit: 2, offset: 2 });
      assert.deepEqual(older.messages.map((message) => message.content), ['reply one', 'two']);
      assert.equal(older.hasMore, true);
    });
  } finally {
    await rm(transcriptDirectory, { recursive: true, force: true });
  }
});
