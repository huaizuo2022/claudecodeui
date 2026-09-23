import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { Codex } from '@openai/codex-sdk';
import type { Thread, ThreadOptions } from '@openai/codex-sdk';

import { codexRuntime } from '@/modules/providers/list/codex/codex-runtime.provider.js';
import { clearCodexThreadLock } from '@/shared/index.js';
import type { ProviderRuntimeContext } from '@/shared/index.js';

for (const resumed of [false, true]) {
  for (const permissionMode of [undefined, 'default', 'unknown', 'acceptEdits', 'bypassPermissions']) {
    test(`Codex ${resumed ? 'resumes' : 'starts'} with supported permissions (${permissionMode ?? 'omitted'})`, async (t) => {
      let capturedOptions: ThreadOptions | undefined;
      let capturedPrompt: unknown;
      const messages: unknown[] = [];
      const thread = {
        id: 'native-thread',
        async runStreamed(prompt: unknown) {
          capturedPrompt = prompt;
          return { events: (async function* () {
            yield { type: 'thread.started', thread_id: 'native-thread' };
          })() };
        },
      } as unknown as Thread;

      const start = t.mock.method(Codex.prototype, 'startThread', (options?: ThreadOptions) => {
        capturedOptions = options;
        return thread;
      });
      const resume = t.mock.method(Codex.prototype, 'resumeThread', (id: string, options?: ThreadOptions) => {
        assert.equal(id, 'native-thread');
        capturedOptions = options;
        return thread;
      });
      const context: ProviderRuntimeContext = {
        resolveProviderSessionId: () => resumed ? 'native-thread' : null,
        resolveResumeModel: async () => 'test-model',
        getProviderModels: async () => ({ OPTIONS: [], DEFAULT: 'test-model' }),
        normalizeMessage: () => [],
        isProviderInstalled: async () => true,
      };

      await codexRuntime.run('hey there', {
        sessionId: resumed ? 'app-session' : undefined,
        permissionMode,
        cwd: process.cwd(),
      }, { isWebSocketWriter: true, send: (message) => messages.push(message) }, context);

      assert.equal(start.mock.callCount(), resumed ? 0 : 1);
      assert.equal(resume.mock.callCount(), resumed ? 1 : 0);
      assert.equal(capturedPrompt, 'hey there');
      assert.equal(capturedOptions?.sandboxMode, permissionMode === 'bypassPermissions' ? 'danger-full-access' : 'workspace-write');
      assert.equal(capturedOptions?.approvalPolicy, permissionMode === 'acceptEdits' || permissionMode === 'bypassPermissions' ? 'never' : 'on-request');
      assert.ok(messages.some((message: any) => message.kind === 'complete' && message.exitCode === 0));
      assert.ok(!messages.some((message: any) => message.kind === 'error'));
    });
  }
}

for (const command of ['', '  \n\t']) {
  test(`Codex supplies a prompt for an image-only turn (${JSON.stringify(command)})`, async (t) => {
    let capturedPrompt: unknown;
    const imagePath = path.join(process.cwd(), 'public', 'favicon.png');
    const thread = {
      id: 'native-thread',
      async runStreamed(prompt: unknown) {
        capturedPrompt = prompt;
        return { events: (async function* () {
          yield { type: 'thread.started', thread_id: 'native-thread' };
        })() };
      },
    } as unknown as Thread;

    t.mock.method(Codex.prototype, 'startThread', () => thread);
    const context: ProviderRuntimeContext = {
      resolveProviderSessionId: () => null,
      resolveResumeModel: async () => 'test-model',
      getProviderModels: async () => ({ OPTIONS: [], DEFAULT: 'test-model' }),
      normalizeMessage: () => [],
      isProviderInstalled: async () => true,
    };

    await codexRuntime.run(command, {
      cwd: process.cwd(),
      images: [{ path: imagePath, mimeType: 'image/png' }],
    }, { isWebSocketWriter: true, send: () => {} }, context);

    assert.deepEqual(capturedPrompt, [
      { type: 'text', text: 'Please analyze the attached image(s).' },
      { type: 'local_image', path: imagePath },
    ]);
  });
}

test('clearCodexThreadLock safely clears lock files and ignores invalid/missing ids', async () => {
  assert.equal(await clearCodexThreadLock(null), false);
  assert.equal(await clearCodexThreadLock(undefined), false);
  assert.equal(await clearCodexThreadLock(''), false);
  assert.equal(await clearCodexThreadLock('../relative-path'), false);
  assert.equal(await clearCodexThreadLock('.hidden-id'), false);

  const testThreadId = `test-thread-lock-${Date.now()}`;
  const lockDir = path.join(os.homedir(), '.codex', 'thread-writer-locks');
  await fs.mkdir(lockDir, { recursive: true });
  const lockFile = path.join(lockDir, `${testThreadId}.lock`);

  await fs.writeFile(lockFile, 'lock-content', 'utf-8');
  assert.equal(await clearCodexThreadLock(testThreadId), true);

  // File should no longer exist
  await assert.rejects(async () => {
    await fs.stat(lockFile);
  });
});

test('Codex automatically cleans up existing lock file before resumeThread', async (t) => {
  const testThreadId = `test-resume-cleanup-${Date.now()}`;
  const lockDir = path.join(os.homedir(), '.codex', 'thread-writer-locks');
  await fs.mkdir(lockDir, { recursive: true });
  const lockFile = path.join(lockDir, `${testThreadId}.lock`);
  await fs.writeFile(lockFile, '', 'utf-8');

  const thread = {
    id: testThreadId,
    async runStreamed() {
      return {
        events: (async function* () {
          yield { type: 'thread.started', thread_id: testThreadId };
        })(),
      };
    },
  } as unknown as Thread;

  t.mock.method(Codex.prototype, 'resumeThread', (id: string) => {
    assert.equal(id, testThreadId);
    return thread;
  });

  const context: ProviderRuntimeContext = {
    resolveProviderSessionId: () => testThreadId,
    resolveResumeModel: async () => 'test-model',
    getProviderModels: async () => ({ OPTIONS: [], DEFAULT: 'test-model' }),
    normalizeMessage: () => [],
    isProviderInstalled: async () => true,
  };

  const messages: unknown[] = [];
  await codexRuntime.run('test resume', {
    sessionId: 'test-app-session',
    cwd: process.cwd(),
  }, { isWebSocketWriter: true, send: (msg) => messages.push(msg) }, context);

  // The lock file should have been cleaned up before resume
  let lockExists = false;
  try {
    await fs.stat(lockFile);
    lockExists = true;
  } catch {
    lockExists = false;
  }
  assert.equal(lockExists, false);
});

