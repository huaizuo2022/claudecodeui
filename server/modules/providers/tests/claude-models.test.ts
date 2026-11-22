import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  ClaudeProviderModels,
  CLAUDE_PREDEFINED_MODELS,
  extractClaudeEventModel,
} from '@/modules/providers/list/claude/claude-models.provider.js';

test('Claude discovers gateway models and retains its predefined aliases', async () => {
  const calls: Array<{ url: string; authorization: string | null }> = [];
  const fetchModels: typeof fetch = async (input, init) => {
    calls.push({
      url: String(input instanceof Request ? input.url : input),
      authorization: new Headers(init?.headers).get('Authorization'),
    });
    return Response.json({
      data: [
        {
          id: 'gateway/sonnet',
          display_name: 'Sonnet',
          magpie_label: 'Sonnet · gateway',
          type: 'model',
          default_reasoning_level: 'high',
          supported_reasoning_levels: [{ effort: 'low' }, { effort: 'high' }, { effort: 'unsupported' }],
        },
        { id: 'gateway/another-model', display_name: 'Another model', type: 'model' },
        { id: 'gateway/chat-only', supported_in_api: false },
        { id: 'gateway/hidden', visibility: 'hide' },
        { id: 'sonnet', display_name: 'Gateway Sonnet Alias', type: 'model' },
      ],
      has_more: false,
    });
  };
  const adapter = new ClaudeProviderModels({
    env: { ANTHROPIC_BASE_URL: 'http://gateway.invalid/v1', ANTHROPIC_AUTH_TOKEN: 'test-token' },
    configDir: '/not-a-claude-home',
    fetch: fetchModels,
  });
  const catalog = await adapter.getSupportedModels();
  assert.deepEqual(calls, [{
    url: 'http://gateway.invalid/v1/models?limit=1000',
    authorization: 'Bearer test-token',
  }]);
  assert.ok(catalog.OPTIONS.some(({ value }) => value === 'gateway/sonnet'));
  assert.ok(catalog.OPTIONS.some(({ value }) => value === 'gateway/another-model'));
  assert.ok(!catalog.OPTIONS.some(({ value }) => value === 'gateway/chat-only'));
  assert.ok(!catalog.OPTIONS.some(({ value }) => value === 'gateway/hidden'));
  assert.equal(catalog.OPTIONS.find(({ value }) => value === 'sonnet')?.label, 'Sonnet');
  assert.equal(catalog.OPTIONS.find(({ value }) => value === 'gateway/sonnet')?.effort?.default, 'high');
  assert.deepEqual(
    catalog.OPTIONS.find(({ value }) => value === 'gateway/sonnet')?.effort?.values.map(({ value }) => value),
    ['low', 'high'],
  );
  for (const { value } of CLAUDE_PREDEFINED_MODELS.OPTIONS) {
    assert.ok(catalog.OPTIONS.some((option) => option.value === value));
  }
  assert.equal(catalog.DEFAULT, CLAUDE_PREDEFINED_MODELS.DEFAULT);
});

test('Claude uses process env before settings.json and falls back when the gateway is unavailable', async (context) => {
  const configDir = await mkdtemp(path.join(os.tmpdir(), 'claude-model-catalog-'));
  context.after(async () => rm(configDir, { recursive: true, force: true }));
  await writeFile(path.join(configDir, 'settings.json'), JSON.stringify({
    env: {
      ANTHROPIC_BASE_URL: 'http://settings.invalid/v1',
      ANTHROPIC_AUTH_TOKEN: 'settings-token',
    },
  }));
  const calls: Array<{ url: string; headers: Headers }> = [];
  const adapter = new ClaudeProviderModels({
    configDir,
    env: {
      CLAUDE_CONFIG_DIR: configDir,
      ANTHROPIC_BASE_URL: 'http://environment.invalid/v1',
      ANTHROPIC_AUTH_TOKEN: 'environment-token',
    },
    fetch: async (input, init) => {
      calls.push({ url: String(input), headers: new Headers(init?.headers) });
      throw new Error('gateway unavailable');
    },
  });

  assert.deepEqual(await adapter.getSupportedModels(), CLAUDE_PREDEFINED_MODELS);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'http://environment.invalid/v1/models?limit=1000');
  assert.equal(calls[0].headers.get('Authorization'), 'Bearer environment-token');
});

test('Claude can list a gateway with no configured authentication', async (context) => {
  const configDir = await mkdtemp(path.join(os.tmpdir(), 'claude-model-auth-'));
  context.after(async () => rm(configDir, { recursive: true, force: true }));
  await writeFile(path.join(configDir, 'settings.json'), JSON.stringify({
    env: { ANTHROPIC_BASE_URL: 'http://settings.invalid' },
  }));
  const requests: Headers[] = [];
  const adapter = new ClaudeProviderModels({
    env: { CLAUDE_CONFIG_DIR: configDir },
    fetch: async (_input, init) => {
      requests.push(new Headers(init?.headers));
      return Response.json({
        data: [{ id: 'settings/model', display_name: 'Settings model', type: 'model' }],
        has_more: false,
      });
    },
  });
  const catalog = await adapter.getSupportedModels();
  assert.ok(catalog.OPTIONS.some(({ value }) => value === 'settings/model'));
  assert.equal(requests.length, 1);
  assert.equal(requests[0].get('Authorization'), null);
  assert.equal(requests[0].get('x-api-key'), null);
});

test('Claude refreshes changed settings and gateway models without waiting for the cache', async (context) => {
  const configDir = await mkdtemp(path.join(os.tmpdir(), 'claude-model-refresh-'));
  context.after(async () => rm(configDir, { recursive: true, force: true }));
  const settingsPath = path.join(configDir, 'settings.json');
  await writeFile(settingsPath, JSON.stringify({ env: { ANTHROPIC_BASE_URL: 'http://first.invalid' } }));
  let now = 1;
  let requests = 0;
  const adapter = new ClaudeProviderModels({
    configDir,
    env: {},
    now: () => now,
    fetch: async (input) => {
      requests += 1;
      const url = new URL(String(input));
      const host = url.hostname;
      return Response.json({
        data: [{ id: `${host}/model`, display_name: host, type: 'model' }],
        has_more: false,
      });
    },
  });
  assert.ok((await adapter.getSupportedModels()).OPTIONS.some(({ value }) => value === 'first.invalid/model'));
  await writeFile(settingsPath, JSON.stringify({ env: { ANTHROPIC_BASE_URL: 'http://second.invalid' } }));
  const updated = await adapter.getSupportedModels();
  assert.ok(updated.OPTIONS.some(({ value }) => value === 'second.invalid/model'));
  assert.ok(!updated.OPTIONS.some(({ value }) => value === 'first.invalid/model'));
  assert.equal(requests, 2);
  now += 31_000;
  await adapter.getSupportedModels();
  assert.equal(requests, 3);
});

test('Claude reads every catalog page and deduplicates routed models', async () => {
  const requests: string[] = [];
  const adapter = new ClaudeProviderModels({
    configDir: '/not-a-claude-home',
    env: { ANTHROPIC_BASE_URL: 'http://gateway.invalid/company/v1/' },
    fetch: async (input) => {
      const url = new URL(String(input));
      requests.push(url.href);
      return Response.json(url.searchParams.has('after_id') ? {
        data: [
          { id: 'gateway/first' },
          { id: 'gateway/second', supported_reasoning_levels: [{ effort: 'xhigh' }, { effort: 'ultra' }] },
        ],
        has_more: false,
        last_id: 'gateway/second',
      } : {
        data: [{ id: 'gateway/first' }],
        has_more: true,
        last_id: 'gateway/first',
      });
    },
  });
  const catalog = await adapter.getSupportedModels();
  assert.equal(requests.length, 2);
  assert.equal(new URL(requests[0]).pathname, '/company/v1/models');
  assert.equal(new URL(requests[1]).searchParams.get('after_id'), 'gateway/first');
  assert.equal(catalog.OPTIONS.filter(({ value }) => value === 'gateway/first').length, 1);
  assert.deepEqual(catalog.OPTIONS.find(({ value }) => value === 'gateway/second')?.effort?.values.map(({ value }) => value), ['xhigh', 'ultracode']);
});

test('Claude preserves API-key and custom headers from user settings', async (context) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'claude-model-headers-'));
  context.after(() => rm(directory, { recursive: true, force: true }));
  await writeFile(path.join(directory, 'settings.json'), JSON.stringify({ env: {
    ANTHROPIC_BASE_URL: 'http://gateway.invalid',
    ANTHROPIC_API_KEY: 'fixture-key',
    ANTHROPIC_CUSTOM_HEADERS: 'X-Tenant: fixture-tenant',
  } }));
  const requests: Headers[] = [];
  const adapter = new ClaudeProviderModels({
    env: { CLAUDE_CONFIG_DIR: directory },
    fetch: async (_input, init) => {
      requests.push(new Headers(init?.headers));
      return Response.json({ data: [{ id: 'gateway/model' }], has_more: false });
    },
  });
  assert.ok((await adapter.getSupportedModels()).OPTIONS.some(({ value }) => value === 'gateway/model'));
  assert.equal(requests[0].get('x-api-key'), 'fixture-key');
  assert.equal(requests[0].get('Authorization'), null);
  assert.equal(requests[0].get('X-Tenant'), 'fixture-tenant');
});

test('Claude uses predefined aliases without a gateway or after incomplete listings', async (context) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'claude-model-fallback-'));
  context.after(() => rm(directory, { recursive: true, force: true }));
  let calls = 0;
  const noGateway = new ClaudeProviderModels({
    configDir: directory,
    env: {},
    fetch: async () => { calls += 1; return Response.json({ data: [] }); },
  });
  assert.deepEqual(await noGateway.getSupportedModels(), CLAUDE_PREDEFINED_MODELS);
  await writeFile(path.join(directory, 'settings.json'), 'invalid json');
  assert.deepEqual(await noGateway.getSupportedModels(), CLAUDE_PREDEFINED_MODELS);
  assert.equal(calls, 0);

  for (const payload of [{ data: [] }, { data: {} }, { data: [null, { id: 123 }] }, {
    data: [{ id: 'gateway/first' }], has_more: true, last_id: 'repeated',
  }]) {
    const adapter = new ClaudeProviderModels({
      configDir: directory,
      env: { ANTHROPIC_BASE_URL: 'http://gateway.invalid' },
      fetch: async () => Response.json(payload),
    });
    assert.deepEqual(await adapter.getSupportedModels(), CLAUDE_PREDEFINED_MODELS);
  }
});

const SESSION_ID = 'session-1';

test('ignores the <synthetic> placeholder Claude Code stamps on synthesized rows', () => {
  assert.equal(
    extractClaudeEventModel(
      { sessionId: SESSION_ID, message: { model: '<synthetic>' } },
      SESSION_ID,
    ),
    null,
  );
  assert.equal(
    extractClaudeEventModel({ sessionId: SESSION_ID, model: '<synthetic>' }, SESSION_ID),
    null,
  );
});

test('still surfaces real model ids from message and event fields', () => {
  assert.equal(
    extractClaudeEventModel(
      { sessionId: SESSION_ID, message: { model: 'claude-sonnet-5' } },
      SESSION_ID,
    ),
    'claude-sonnet-5',
  );
  assert.equal(
    extractClaudeEventModel({ sessionId: SESSION_ID, model: 'opus' }, SESSION_ID),
    'opus',
  );
});

test('skips a placeholder content part so a later real model tag still wins', () => {
  assert.equal(
    extractClaudeEventModel(
      {
        sessionId: SESSION_ID,
        message: {
          content: [
            { text: '<model><synthetic></model>' },
            { text: '<model>claude-sonnet-5</model>' },
          ],
        },
      },
      SESSION_ID,
    ),
    'claude-sonnet-5',
  );
});

test('a placeholder stdout hit does not shadow a real <model> tag in the same text', () => {
  const text = '<local-command-stdout>Set model to <synthetic></local-command-stdout>'
    + '<model>claude-sonnet-5</model>';
  assert.equal(
    extractClaudeEventModel(
      { sessionId: SESSION_ID, message: { content: text } },
      SESSION_ID,
    ),
    'claude-sonnet-5',
  );
  assert.equal(
    extractClaudeEventModel(
      { sessionId: SESSION_ID, message: { content: [{ text }] } },
      SESSION_ID,
    ),
    'claude-sonnet-5',
  );
});

test('falls back to the message model when every content hit is a placeholder', () => {
  assert.equal(
    extractClaudeEventModel(
      {
        sessionId: SESSION_ID,
        message: {
          content: '<model><synthetic></model>',
          model: 'claude-sonnet-5',
        },
      },
      SESSION_ID,
    ),
    'claude-sonnet-5',
  );
});
