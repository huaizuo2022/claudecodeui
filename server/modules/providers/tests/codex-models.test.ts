import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import type { AddressInfo } from 'node:net';
import type { TestContext } from 'node:test';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  CodexProviderModels,
  CODEX_PREDEFINED_MODELS,
} from '@/modules/providers/list/codex/codex-models.provider.js';

const require = createRequire(import.meta.url);

const findCodexModel = (value: string) =>
  CODEX_PREDEFINED_MODELS.OPTIONS.find((option) => option.value === value);

/**
 * Runs the Codex CLI that chats spawn, with a throwaway CODEX_HOME so no user
 * config or login is read. The SDK spawns the native binary of the
 * `@openai/codex-<platform>` package installed next to the `@openai/codex` it
 * resolves; that package's own launcher, resolved the same way, runs it too.
 */
const runChatCodexCli = async (args: string[]): Promise<string> => {
  const sdkRequire = createRequire(import.meta.resolve('@openai/codex-sdk'));
  const packageJsonPath = sdkRequire.resolve('@openai/codex/package.json');
  const { bin } = sdkRequire('@openai/codex/package.json') as { bin: { codex: string } };
  const codexHome = await mkdtemp(path.join(os.tmpdir(), 'cloudcli-codex-models-'));
  try {
    return execFileSync(process.execPath, [path.join(path.dirname(packageJsonPath), bin.codex), ...args], {
      encoding: 'utf8',
      env: { ...process.env, CODEX_HOME: codexHome },
      // Piped, not inherited: the CLI warns on stderr that it skips its helper
      // binaries under a temp CODEX_HOME, which these commands do not need.
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 30_000,
    });
  } finally {
    await rm(codexHome, { recursive: true, force: true });
  }
};

test('lists GPT-6 Sol and GPT-6 Luna with the effort levels the Codex CLI accepts', () => {
  const sol = findCodexModel('gpt-6-sol');
  assert.equal(sol?.label, 'GPT-6 Sol');
  assert.equal(sol?.effort?.default, 'medium');
  assert.deepEqual(
    sol?.effort?.values.map((effort) => effort.value),
    ['low', 'medium', 'high', 'xhigh', 'max', 'ultra'],
  );

  const luna = findCodexModel('gpt-6-luna');
  assert.equal(luna?.label, 'GPT-6 Luna');
  assert.equal(luna?.effort?.default, 'medium');
  assert.deepEqual(
    luna?.effort?.values.map((effort) => effort.value),
    ['low', 'medium', 'high', 'xhigh', 'max'],
  );
});

test('lists GPT-6.1 Sol and GPT-6.1 Terra with the effort levels the Codex CLI accepts', () => {
  const sol = findCodexModel('gpt-6.1-sol');
  assert.equal(sol?.label, 'GPT-6.1 Sol');
  assert.equal(sol?.effort?.default, 'low');
  assert.deepEqual(
    sol?.effort?.values.map((effort) => effort.value),
    ['low', 'medium', 'high', 'xhigh', 'max', 'ultra'],
  );

  const terra = findCodexModel('gpt-6.1-terra');
  assert.equal(terra?.label, 'GPT-6.1 Terra');
  assert.equal(terra?.effort?.default, 'low');
  assert.deepEqual(
    terra?.effort?.values.map((effort) => effort.value),
    ['low', 'medium', 'high', 'xhigh', 'max', 'ultra'],
  );
});

test('lists only models the bundled Codex CLI has metadata for', async () => {
  // Any other model still runs, but on fallback metadata: the CLI warns "Model
  // metadata ... not found" (the chat never shows it), sends no default effort
  // and leaves tools such as apply_patch out. Codex 0.158.0 dropped gpt-5.4
  // from its bundled catalog. The CLI also matches a model by slug prefix,
  // which hands it another model's metadata, so each entry must be a slug.
  const { models } = JSON.parse(await runChatCodexCli(['debug', 'models', '--bundled'])) as {
    models: Array<{ slug: string }>;
  };
  const bundledSlugs = new Set(models.map((model) => model.slug));
  assert.deepEqual(
    CODEX_PREDEFINED_MODELS.OPTIONS
      .map((option) => option.value)
      .filter((value) => !bundledSlugs.has(value)),
    [],
  );
});

test('defaults Codex chats to a model the picker lists', () => {
  assert.ok(
    CODEX_PREDEFINED_MODELS.OPTIONS.some((option) => option.value === CODEX_PREDEFINED_MODELS.DEFAULT),
    `DEFAULT ${CODEX_PREDEFINED_MODELS.DEFAULT} is not a listed Codex model`,
  );
});

test('reads the configured model catalog and its model metadata', async (context: TestContext) => {
  const codexHome = await mkdtemp(path.join(os.tmpdir(), 'cloudcli-codex-model-catalog-'));
  context.after(async () => rm(codexHome, { recursive: true, force: true }));
  await mkdir(path.join(codexHome, 'catalogs'));
  await writeFile(path.join(codexHome, 'config.toml'), [
    'model = "zode/sonnet"',
    'model_catalog_json = "catalogs/models.json"',
    'model_provider = "magpie"',
    '[model_providers.magpie]',
    'base_url = "http://127.0.0.1:1/v1"',
  ].join('\n'));
  await writeFile(path.join(codexHome, 'catalogs', 'models.json'), JSON.stringify({
    models: [
      {
        slug: 'zode/sonnet',
        display_name: 'Sonnet · zode',
        supported_in_api: true,
        visibility: 'list',
        default_reasoning_level: 'high',
        supported_reasoning_levels: [{ effort: 'low' }, { effort: 'high' }],
      },
      { slug: 'zode/duplicate', display_name: 'Earlier entry' },
      { slug: 'zode/duplicate', display_name: 'Later entry' },
      { slug: 'zode/chat-only', supported_in_api: false },
      { slug: 'zode/hidden', visibility: 'hide' },
    ],
  }));

  let proxyRequests = 0;
  const adapter = new CodexProviderModels({
    codexHome,
    fetch: async () => { proxyRequests += 1; throw new Error('catalog takes priority'); },
  });
  const models = await adapter.getSupportedModels();
  assert.equal(models.DEFAULT, 'zode/sonnet');
  assert.deepEqual(models.OPTIONS.map((option) => option.value), ['zode/sonnet', 'zode/duplicate']);
  assert.equal(models.OPTIONS[0].label, 'Sonnet · zode');
  assert.equal(models.OPTIONS[0].effort?.default, 'high');
  assert.deepEqual(models.OPTIONS[0].effort?.values.map(({ value }) => value), ['low', 'high']);
  assert.equal(models.OPTIONS[1].label, 'Earlier entry');
  assert.equal(proxyRequests, 0);

  // A changed default and an updated absolute-path catalog take effect on the
  // same adapter immediately, without waiting for the gateway cache to expire.
  const catalogPath = path.join(codexHome, 'catalogs', 'models.json');
  await writeFile(path.join(codexHome, 'config.toml'), [
    'model = "other/sonnet"',
    `model_catalog_json = ${JSON.stringify(catalogPath)}`,
  ].join('\n'));
  await writeFile(catalogPath, JSON.stringify({ models: [
    { slug: 'zode/sonnet' },
    { slug: 'other/sonnet', default_reasoning_level: 'max', supported_reasoning_levels: [{ effort: 'low' }] },
    null,
    { slug: ' ' },
  ] }));
  const updated = await adapter.getSupportedModels();
  assert.deepEqual(updated.OPTIONS.map(({ value }) => value), ['zode/sonnet', 'other/sonnet']);
  assert.equal(updated.DEFAULT, 'other/sonnet');
  assert.equal(updated.OPTIONS[1].effort?.default, undefined);
  assert.equal((await adapter.getCurrentActiveModel()).model, 'other/sonnet');
});

test('discovers proxy models, keeps complete ids, and caches the request briefly', async (context: TestContext) => {
  const codexHome = await mkdtemp(path.join(os.tmpdir(), 'cloudcli-codex-proxy-models-'));
  context.after(async () => rm(codexHome, { recursive: true, force: true }));
  let requests = 0;
  const server = createServer((request, response) => {
    requests += 1;
    assert.equal(request.url, '/v1/models');
    assert.equal(request.headers.authorization, 'Bearer test-token');
    assert.equal(request.headers['x-magpie-client'], 'codex');
    response.setHeader('content-type', 'application/json');
    response.end(JSON.stringify({
      data: [
        { id: 'zode/claude-sonnet-5-5' },
        { id: 'aiclaude360/gpt-6-astra', name: 'Astra' },
        { id: 'zode/claude-sonnet-5-5' },
      ],
    }));
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  context.after(async () => new Promise<void>((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  }));
  const baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}/v1`;
  await writeFile(path.join(codexHome, 'config.toml'), [
    'model = "zode/claude-sonnet-5-5"',
    'model_provider = "magpie"',
    '[model_providers.magpie]',
    `base_url = "${baseUrl}"`,
    'experimental_bearer_token = "test-token"',
    '[model_providers.magpie.http_headers]',
    'X-Magpie-Client = "codex"',
    'Authorization = "Bearer explicit-token"',
  ].join('\n'));
  let now = 1;
  const adapter = new CodexProviderModels({ codexHome, now: () => now });

  const models = await adapter.getSupportedModels();
  assert.equal(models.DEFAULT, 'zode/claude-sonnet-5-5');
  assert.deepEqual(models.OPTIONS.map(({ value }) => value), [
    'zode/claude-sonnet-5-5',
    'aiclaude360/gpt-6-astra',
  ]);
  assert.equal(models.OPTIONS[1].label, 'Astra');
  assert.equal((await adapter.getSupportedModels()).OPTIONS.length, 2);
  assert.equal(requests, 1);

  now += 31_000;
  await adapter.getSupportedModels();
  assert.equal(requests, 2);
});

test('uses CODEX_HOME for both the catalog and active model without rewriting config', async (context) => {
  const codexHome = await mkdtemp(path.join(os.tmpdir(), 'cloudcli-codex-home-'));
  const originalHome = process.env.CODEX_HOME;
  context.after(async () => {
    if (originalHome === undefined) delete process.env.CODEX_HOME;
    else process.env.CODEX_HOME = originalHome;
    await rm(codexHome, { recursive: true, force: true });
  });
  process.env.CODEX_HOME = codexHome;
  const config = 'model = "gateway/current"\nmodel_catalog_json = "models.json"\n';
  await writeFile(path.join(codexHome, 'config.toml'), config);
  await writeFile(path.join(codexHome, 'models.json'), JSON.stringify({ models: [
    { slug: 'gateway/first' }, { slug: 'gateway/current' },
  ] }));
  const adapter = new CodexProviderModels();
  assert.equal((await adapter.getSupportedModels()).DEFAULT, 'gateway/current');
  assert.deepEqual(await adapter.getCurrentActiveModel(), { model: 'gateway/current', source: 'provider' });
  assert.equal(await readFile(path.join(codexHome, 'config.toml'), 'utf8'), config);
});

test('queries the selected provider when the file catalog is missing, invalid, or empty', async (context) => {
  const codexHome = await mkdtemp(path.join(os.tmpdir(), 'cloudcli-codex-catalog-fallback-'));
  context.after(async () => rm(codexHome, { recursive: true, force: true }));
  await writeFile(path.join(codexHome, 'config.toml'), [
    'model = "gateway/no-longer-listed"',
    'model_catalog_json = "models.json"',
    'model_provider = "gateway"',
    '[model_providers.other]',
    'base_url = "http://unused.invalid/v1"',
    '[model_providers.gateway]',
    'base_url = "http://gateway.invalid/custom/v1/?api-version=test"',
    'experimental_bearer_token = "test-model-key"',
    '[model_providers.gateway.http_headers]',
    'X-Magpie-Client = "codex"',
  ].join('\n'));
  let requests = 0;
  const fetchModels: typeof fetch = async (url, init) => {
    requests += 1;
    assert.equal(String(url), 'http://gateway.invalid/custom/v1/models?api-version=test');
    assert.equal(new Headers(init?.headers).get('Authorization'), 'Bearer test-model-key');
    assert.equal(new Headers(init?.headers).get('X-Magpie-Client'), 'codex');
    assert.equal(init?.redirect, 'error');
    assert.ok(init?.signal instanceof AbortSignal);
    return Response.json({ data: [{ id: 'gateway/first' }, { id: 'other/first' }] });
  };
  for (const contents of [null, '{broken', '{"models":[]}', '{"models":[null,{"slug":" "}]}']) {
    if (contents !== null) {
      await writeFile(path.join(codexHome, 'models.json'), contents);
    }
    const adapter = new CodexProviderModels({ codexHome, fetch: fetchModels });
    const models = await adapter.getSupportedModels();
    assert.equal(models.DEFAULT, 'gateway/first');
    assert.deepEqual(models.OPTIONS.map(({ value }) => value), ['gateway/first', 'other/first']);
    assert.equal(models.OPTIONS[0].effort, undefined);
  }
  assert.equal(requests, 4);
});

test('falls back to bundled models when the configured model sources are unavailable', async (context) => {
  const codexHome = await mkdtemp(path.join(os.tmpdir(), 'cloudcli-codex-fallback-'));
  context.after(async () => rm(codexHome, { recursive: true, force: true }));
  const adapter = new CodexProviderModels({ codexHome });
  assert.deepEqual(await adapter.getSupportedModels(), CODEX_PREDEFINED_MODELS);
  assert.equal((await adapter.getCurrentActiveModel()).model, CODEX_PREDEFINED_MODELS.DEFAULT);
  await writeFile(path.join(codexHome, 'config.toml'), 'invalid [ toml');
  assert.deepEqual(await adapter.getSupportedModels(), CODEX_PREDEFINED_MODELS);

  await writeFile(path.join(codexHome, 'config.toml'), [
    'model_provider = "gateway"',
    '[model_providers.gateway]',
    'base_url = "http://gateway.invalid/v1"',
  ].join('\n'));
  const failingFetches: Array<[string, typeof fetch]> = [
    ['unreachable', async () => { throw new Error('unreachable'); }],
    ['HTTP error', async () => new Response('', { status: 503 })],
    ['invalid JSON', async () => new Response('not json')],
    ['empty list', async () => Response.json({ data: [] })],
    ['invalid entries', async () => Response.json({ data: [null, { id: 123 }, { id: ' ' }] })],
    ['wrong shape', async () => Response.json({ data: {} })],
    ['aborted', async () => { throw new DOMException('Timed out', 'TimeoutError'); }],
  ];
  for (const [name, fetchModels] of failingFetches) {
    await context.test(name, async () => {
      const fallback = new CodexProviderModels({ codexHome, fetch: fetchModels });
      assert.deepEqual(await fallback.getSupportedModels(), CODEX_PREDEFINED_MODELS);
    });
  }
});

test('bundles a Codex CLI new enough to know the GPT-6.1 Sol and Terra models', () => {
  // The GPT-6.1 models entered the CLI's bundled catalog in 0.160.0. An older
  // CLI still sends the request, but on fallback metadata: it warns
  // "Model metadata ... not found" and quietly drops `ultra` to a lower tier.
  const { version } = require('@openai/codex/package.json') as { version: string };
  const [major, minor] = version.split('.').map(Number);
  assert.ok(major > 0 || minor >= 160, `bundled @openai/codex ${version} predates 0.160.0`);
});

test('bundles a Codex CLI new enough to know the GPT-6 Sol and Luna models', () => {
  // Codex only ships metadata for gpt-6-sol / gpt-6-luna from 0.155.0 on. An
  // older CLI still sends the request, but on fallback metadata: it warns
  // "Model metadata ... not found" and quietly drops `ultra` to `medium`.
  const { version } = require('@openai/codex/package.json') as { version: string };
  const [major, minor] = version.split('.').map(Number);
  assert.ok(major > 0 || minor >= 155, `bundled @openai/codex ${version} predates 0.155.0`);
});
