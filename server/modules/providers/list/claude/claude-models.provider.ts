import { readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import Anthropic from '@anthropic-ai/sdk';

import { sessionsDb } from '@/modules/database/index.js';
import { providerCapabilitiesService } from '@/modules/providers/services/provider-capabilities.service.js';
import type {
  IProviderModels,
  ProviderCurrentActiveModel,
  ProviderModelOption,
  ProviderModelsDefinition,
} from '@/shared/index.js';
import {
  buildDefaultProviderCurrentActiveModel,
  isPlaceholderProviderModel,
  readObjectRecord,
  readOptionalString,
  stripAnsiSequences,
} from '@/shared/index.js';

/**
 * Ultracode is not one of the SDK's reasoning-effort levels. Selecting it runs the turn at
 * `xhigh` effort with standing dynamic-workflow orchestration, which the Claude runtime
 * translates into the session-scoped `ultracode` setting. It is therefore only offered on
 * models this catalog already marks as xhigh-capable.
 */
export const CLAUDE_ULTRACODE_EFFORT = 'ultracode';

const ULTRACODE_EFFORT_OPTION = {
  value: CLAUDE_ULTRACODE_EFFORT,
  description: 'Highest effort plus standing workflow orchestration.',
};

const CLAUDE_MODEL_LIST_TIMEOUT_MS = 5_000;
const CLAUDE_MODEL_LIST_CACHE_TTL_MS = 30_000;

type ClaudeModelCatalogConfig = {
  baseURL: string;
  apiKey?: string;
  authToken?: string;
  customHeaders?: string;
};

const readClaudeModelCatalogConfig = async (
  env: NodeJS.ProcessEnv,
  configDirectory?: string,
): Promise<ClaudeModelCatalogConfig | null> => {
  const configuredDirectory = configDirectory ?? readOptionalString(env.CLAUDE_CONFIG_DIR);
  const directory = configuredDirectory && path.isAbsolute(configuredDirectory)
    ? configuredDirectory : path.join(os.homedir(), '.claude');
  let settingsEnv: Record<string, unknown> = {};
  try {
    const settings = readObjectRecord(JSON.parse(await readFile(path.join(directory, 'settings.json'), 'utf8')));
    settingsEnv = readObjectRecord(settings?.env) ?? {};
  } catch {
    // A missing settings file still allows an environment-configured gateway.
  }
  const readEnv = (key: string) => readOptionalString(env[key]) ?? readOptionalString(settingsEnv[key]);
  const baseURL = readEnv('ANTHROPIC_BASE_URL');
  if (!baseURL) {
    return null;
  }
  return {
    baseURL,
    authToken: readEnv('ANTHROPIC_AUTH_TOKEN'),
    apiKey: readEnv('ANTHROPIC_API_KEY'),
    customHeaders: readEnv('ANTHROPIC_CUSTOM_HEADERS'),
  };
};

const parseClaudeGatewayModel = (value: unknown): ProviderModelOption | null => {
  const model = readObjectRecord(value);
  const id = readOptionalString(model?.id);
  if (!model || !id || model.supported_in_api === false || model.visibility === 'hide') {
    return null;
  }
  const supportedEfforts = providerCapabilitiesService.getProviderCapabilities('claude').effortLevels
    .filter((effort) => effort !== CLAUDE_ULTRACODE_EFFORT);
  const capability = readObjectRecord(readObjectRecord(model.capabilities)?.effort);
  const declared: unknown[] = Array.isArray(model.supported_reasoning_levels)
    ? model.supported_reasoning_levels.map((level: unknown) => readObjectRecord(level)?.effort)
    : Array.isArray(model.reasoning_levels) ? model.reasoning_levels
      : supportedEfforts.filter((level) => readObjectRecord(capability?.[level])?.supported === true);
  const levels = [...new Set(declared.map(readOptionalString)
    .filter((level): level is string => Boolean(level && supportedEfforts.includes(level))))];
  const defaultEffort = readOptionalString(model.default_reasoning_level);
  const effortValues: { value: string; description?: string }[] = levels.map((level) => ({ value: level }));
  if (levels.includes('xhigh')) {
    effortValues.push(ULTRACODE_EFFORT_OPTION);
  }
  const description = readOptionalString(model.description);
  return {
    value: id,
    label: readOptionalString(model.magpie_label) ?? readOptionalString(model.display_name) ?? id,
    ...(description ? { description } : {}),
    ...(effortValues.length > 0 ? {
      effort: {
        ...(defaultEffort && levels.includes(defaultEffort) ? { default: defaultEffort } : {}),
        values: effortValues,
      },
    } : {}),
  };
};

const readDiscoveredClaudeModels = async (
  config: ClaudeModelCatalogConfig,
  fetchModels: typeof fetch,
): Promise<ProviderModelOption[]> => {
  try {
    const url = new URL(config.baseURL);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      return [];
    }
    // The SDK appends /v1/models; accept gateways configured with or without /v1.
    url.pathname = url.pathname.replace(/\/+$/, '').replace(/\/v1$/, '');
    const defaultHeaders: Record<string, string | null> = {};
    for (const line of (config.customHeaders ?? '').split('\n')) {
      const colon = line.indexOf(':');
      if (colon > 0) {
        defaultHeaders[line.slice(0, colon).trim()] = line.slice(colon + 1).trim();
      }
    }
    // Explicit empty auth prevents SDK profile lookup for an unauthenticated
    // local gateway; null headers omit credentials instead of fabricating a key.
    if (!config.authToken && !config.apiKey) {
      defaultHeaders['x-api-key'] = null;
      defaultHeaders.Authorization ??= null;
    }
    const client = new Anthropic({
      baseURL: url.href.replace(/\/$/, ''),
      apiKey: config.authToken ? null : config.apiKey ?? '',
      authToken: config.authToken ?? null,
      defaultHeaders,
      fetch: fetchModels,
      fetchOptions: { redirect: 'error' },
      timeout: CLAUDE_MODEL_LIST_TIMEOUT_MS,
      maxRetries: 0,
      logLevel: 'off',
    });
    const signal = AbortSignal.timeout(CLAUDE_MODEL_LIST_TIMEOUT_MS);
    let page = await client.models.list({ limit: 1000 }, { signal });
    const options = new Map<string, ProviderModelOption>();
    const cursors = new Set<string>();
    for (;;) {
      if (!Array.isArray(page.data)) {
        return [];
      }
      for (const value of page.data) {
        const option = parseClaudeGatewayModel(value);
        if (option && !options.has(option.value)) {
          options.set(option.value, option);
        }
      }
      if (!page.hasNextPage()) {
        if (page.has_more === true) return [];
        return [...options.values()];
      }
      const cursor = readOptionalString(page.last_id);
      if (!cursor || cursors.has(cursor)) {
        return [];
      }
      cursors.add(cursor);
      page = await page.getNextPage();
    }
  } catch {
    // Failed or incomplete listings must not replace the working aliases.
    return [];
  }
};

export const CLAUDE_PREDEFINED_MODELS: ProviderModelsDefinition = {
  OPTIONS: [
    {
      value: 'default',
      label: 'Default (recommended)',
      description: 'Use the recommended model for your Claude account and deployment.',
      effort: {
        default: 'high',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'max' },
        ],
      },
    },
    {
      value: 'best',
      label: 'Best available',
      description: 'Use Fable 5 when available, otherwise the latest Opus model.',
      effort: {
        default: 'high',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
          ULTRACODE_EFFORT_OPTION,
        ],
      },
    },
    {
      value: 'fable',
      label: 'Fable 5',
      description: 'Most capable Claude model for the hardest, longest-running tasks.',
      effort: {
        default: 'high',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
          ULTRACODE_EFFORT_OPTION,
        ],
      },
    },
    {
      value: 'sonnet',
      label: 'Sonnet',
      description: 'Latest Sonnet model for everyday coding tasks.',
      effort: {
        default: 'high',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
          ULTRACODE_EFFORT_OPTION,
        ],
      },
    },
    {
      value: 'sonnet[1m]',
      label: 'Sonnet (1M context)',
      description: 'Latest Sonnet model with a 1M context window.',
      effort: {
        default: 'high',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
          ULTRACODE_EFFORT_OPTION,
        ],
      },
    },
    {
      value: 'opus',
      label: 'Opus',
      description: 'Latest Opus model for complex reasoning and coding tasks.',
      effort: {
        default: 'high',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
          ULTRACODE_EFFORT_OPTION,
        ],
      },
    },
    {
      value: 'opus[1m]',
      label: 'Opus (1M context)',
      description: 'Latest Opus model with a 1M context window.',
      effort: {
        default: 'high',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
          ULTRACODE_EFFORT_OPTION,
        ],
      },
    },
    {
      value: 'haiku',
      label: 'Haiku',
      description: 'Fast and efficient Claude model for simple tasks.',
    },
    {
      value: 'opusplan',
      label: 'Opus Plan',
      description: 'Use Opus while planning, then switch to Sonnet for execution.',
      effort: {
        default: 'high',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
          ULTRACODE_EFFORT_OPTION,
        ],
      },
    },
  ],
  DEFAULT: 'default',
};

export const findClaudeModelOption = (model: string | undefined | null): ProviderModelOption | null => {
  const normalizedModel = typeof model === 'string' ? model.trim() : '';
  if (!normalizedModel) {
    return null;
  }

  return CLAUDE_PREDEFINED_MODELS.OPTIONS.find((option) => option.value === normalizedModel) ?? null;
};
type ClaudeInitEvent = {
  sessionId?: string;
  session_id?: string;
  type?: string;
  subtype?: string;
  model?: string;
  message?: {
    content?: unknown;
    model?: string;
  };
};

/** Exported for tests. */
export const extractClaudeEventModel = (event: ClaudeInitEvent, sessionId: string): string | null => {
  const eventSessionId = event.sessionId ?? event.session_id;
  if (eventSessionId && eventSessionId !== sessionId) {
    return null;
  }

  const contentModel = extractClaudeModelFromMessageContent(event.message?.content);
  if (contentModel) {
    return contentModel;
  }

  const directModel = event.model?.trim();
  if (directModel && !isPlaceholderProviderModel(directModel)) {
    return directModel;
  }

  const messageModel = event.message?.model?.trim();
  return messageModel && !isPlaceholderProviderModel(messageModel) ? messageModel : null;
};

const extractTaggedContent = (content: string, tagName: string): string | null => {
  const escapedTagName = tagName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = new RegExp(`<${escapedTagName}>([\\s\\S]*?)<\\/${escapedTagName}>`).exec(content);
  return match ? match[1] : null;
};

const extractClaudeModelFromTextContent = (content: string): string | null => {
  const localCommandStdout = extractTaggedContent(content, 'local-command-stdout');
  if (localCommandStdout !== null) {
    const cleanedStdout = stripAnsiSequences(localCommandStdout).replace(/\s+/g, ' ').trim();
    const changedModel = /(?:set|changed|switched)\s+model\s+to\s+(.+?)\.?$/i.exec(cleanedStdout);
    const stdoutModel = changedModel?.[1]?.trim();
    // A placeholder stdout hit must not shadow a real <model> tag further down.
    if (stdoutModel && !isPlaceholderProviderModel(stdoutModel)) {
      return stdoutModel;
    }
  }

  const modelTag = extractTaggedContent(content, 'model')?.trim();
  return modelTag && !isPlaceholderProviderModel(modelTag) ? modelTag : null;
};

const extractClaudeModelFromMessageContent = (content: unknown): string | null => {
  if (typeof content === 'string') {
    return extractClaudeModelFromTextContent(content);
  }

  if (!Array.isArray(content)) {
    return null;
  }

  for (const part of content) {
    if (!part || typeof part !== 'object' || !('text' in part) || typeof part.text !== 'string') {
      continue;
    }

    // extractClaudeModelFromTextContent rejects placeholders, so a placeholder
    // part yields null here and a later part can still supply the real model.
    const model = extractClaudeModelFromTextContent(part.text);
    if (model) {
      return model;
    }
  }

  return null;
};

const readClaudeSessionModelFromJsonl = async (
  sessionId: string,
  jsonlPath: string,
): Promise<ProviderCurrentActiveModel | null> => {
  const content = await readFile(jsonlPath, 'utf8');
  const lines = content
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  for (let index = lines.length - 1; index >= 0; index -= 1) {
    try {
      const event = JSON.parse(lines[index]) as ClaudeInitEvent;
      const model = extractClaudeEventModel(event, sessionId);
      if (model) {
        return { model };
      }
    } catch {
      // Skip malformed JSONL lines that can happen during concurrent writes.
    }
  }

  return null;
};

export class ClaudeProviderModels implements IProviderModels {
  /** Recent gateway catalog; settings are read on every call so config changes apply immediately. */
  private cachedGatewayCatalog: {
    key: string;
    expiresAt: number;
    options: Promise<ProviderModelOption[]>;
  } | null = null;

  constructor(private readonly dependencies: {
    env?: NodeJS.ProcessEnv;
    configDir?: string;
    fetch?: typeof fetch;
    now?: () => number;
  } = {}) {}

  private getModelCatalogConfig(): Promise<ClaudeModelCatalogConfig | null> {
    return readClaudeModelCatalogConfig(this.dependencies.env ?? process.env, this.dependencies.configDir);
  }

  private async readGatewayCatalog(
    config: ClaudeModelCatalogConfig | null,
  ): Promise<ProviderModelOption[]> {
    if (!config) {
      return [];
    }

    const key = JSON.stringify(config);
    const now = this.dependencies.now ?? Date.now;
    if (this.cachedGatewayCatalog?.key === key && now() < this.cachedGatewayCatalog.expiresAt) {
      return this.cachedGatewayCatalog.options;
    }

    const options = readDiscoveredClaudeModels(config, this.dependencies.fetch ?? fetch)
      .catch(() => [] as ProviderModelOption[]);
    this.cachedGatewayCatalog = {
      key,
      expiresAt: now() + CLAUDE_MODEL_LIST_CACHE_TTL_MS,
      options,
    };
    return options;
  }

  async getSupportedModels(): Promise<ProviderModelsDefinition> {
    const config = await this.getModelCatalogConfig();
    const discovered = await this.readGatewayCatalog(config);
    if (discovered.length === 0) {
      return CLAUDE_PREDEFINED_MODELS;
    }
    const aliases = new Set(CLAUDE_PREDEFINED_MODELS.OPTIONS.map(({ value }) => value));
    return {
      OPTIONS: [
        ...discovered.filter(({ value }) => !aliases.has(value)),
        ...CLAUDE_PREDEFINED_MODELS.OPTIONS,
      ],
      DEFAULT: CLAUDE_PREDEFINED_MODELS.DEFAULT,
    };
  }

  async getCurrentActiveModel(sessionId?: string): Promise<ProviderCurrentActiveModel> {
    if (!sessionId?.trim()) {
      return buildDefaultProviderCurrentActiveModel(await this.getSupportedModels());
    }

    try {
      const jsonlPath = sessionsDb.getSessionById(sessionId)?.jsonl_path;
      const activeModel = jsonlPath
        ? await readClaudeSessionModelFromJsonl(sessionId, jsonlPath)
        : null;
      if (activeModel?.model) {
        return activeModel;
      }
    } catch {
      // Fall through to the provider default when the session-backed lookup fails.
    }

    return buildDefaultProviderCurrentActiveModel(await this.getSupportedModels());
  }
}
