import { readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import TOML from '@iarna/toml';

import type { IProviderModels } from '@/shared/interfaces.js';
import type {
  ProviderCurrentActiveModel,
  ProviderModelOption,
  ProviderModelsDefinition,
} from '@/shared/types.js';
import {
  buildDefaultProviderCurrentActiveModel,
  readObjectRecord,
  readOptionalString,
} from '@/shared/utils.js';

/** Curated Codex catalog shipped as immutable CloudCLI defaults. */
export const CODEX_PREDEFINED_MODELS: ProviderModelsDefinition = {
  // Chats run the bundled `@openai/codex` CLI, which takes model metadata from
  // its own bundled catalog (`codex debug models --bundled`), from a slug-prefix
  // match against that catalog, or (signed in to ChatGPT) from OpenAI's remote
  // catalog; anything else runs on fallback metadata. So every entry must be
  // one of the bundled catalog's exact slugs, which codex-models.test.ts checks.
  OPTIONS: [
    {
      value: 'gpt-6-astra',
      label: 'GPT-6 Astra',
      description: 'Our most capable model for complex, demanding work.',
      effort: {
        default: 'low',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
          { value: 'ultra' },
        ],
      },
    },
    {
      value: 'gpt-6.1-sol',
      label: 'GPT-6.1 Sol',
      description: 'Latest workhorse model for coding and everyday work.',
      effort: {
        default: 'low',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
          { value: 'ultra' },
        ],
      },
    },
    {
      value: 'gpt-6.1-terra',
      label: 'GPT-6.1 Terra',
      description: 'Balanced agentic coding model for everyday work.',
      effort: {
        default: 'low',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
          { value: 'ultra' },
        ],
      },
    },
    {
      value: 'gpt-6-sol',
      label: 'GPT-6 Sol',
      description: 'Workhorse model for coding and everyday work.',
      effort: {
        default: 'medium',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
          { value: 'ultra' },
        ],
      },
    },
    {
      value: 'gpt-6-luna',
      label: 'GPT-6 Luna',
      description: 'Fast and affordable model for easier tasks.',
      effort: {
        default: 'medium',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
        ],
      },
    },
    {
      value: 'gpt-5.6-sol',
      label: 'GPT-5.6 Sol',
      description: 'Latest frontier agentic coding model.',
      effort: {
        default: 'low',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
          { value: 'ultra' },
        ],
      },
    },
    {
      value: 'gpt-5.6-terra',
      label: 'GPT-5.6 Terra',
      description: 'Balanced agentic coding model for everyday work.',
      effort: {
        default: 'medium',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
          { value: 'ultra' },
        ],
      },
    },
    {
      value: 'gpt-5.6-luna',
      label: 'GPT-5.6 Luna',
      description: 'Fast and affordable agentic coding model.',
      effort: {
        default: 'medium',
        values: [
          { value: 'low' },
          { value: 'medium' },
          { value: 'high' },
          { value: 'xhigh' },
          { value: 'max' },
        ],
      },
    },
    {
      value: 'gpt-5.5',
      label: 'GPT-5.5',
      description: 'Frontier model for complex coding, research, and real-world work.',
      effort: {
        default: 'medium',
        values: [{ value: 'low' }, { value: 'medium' }, { value: 'high' }, { value: 'xhigh' }],
      },
    },
  ],
  DEFAULT: 'gpt-5.6-sol',
};

const CODEX_MODELS_TIMEOUT_MS = 5_000;
const CODEX_PROXY_MODELS_CACHE_TTL_MS = 30_000;

const readCodexConfig = async (codexHome: string): Promise<Record<string, unknown>> => {
  try {
    return readObjectRecord(TOML.parse(await readFile(path.join(codexHome, 'config.toml'), 'utf8'))) ?? {};
  } catch {
    return {};
  }
};

/** Keeps gateway routing prefixes and uses only effort metadata the source declares. */
const parseCodexModelOptions = (payload: unknown, source: 'catalog' | 'proxy'): ProviderModelOption[] => {
  const data = readObjectRecord(payload);
  const rows: unknown = source === 'catalog' ? data?.models : data?.data;
  if (!Array.isArray(rows)) {
    return [];
  }

  const options = new Map<string, ProviderModelOption>();
  for (const row of rows) {
    const model = readObjectRecord(row);
    const value = readOptionalString(source === 'catalog' ? model?.slug : model?.id);
    if (!model || !value || options.has(value)
      || model.supported_in_api === false || model.visibility === 'hide') {
      continue;
    }

    const levels: unknown[] = Array.isArray(model.supported_reasoning_levels)
      ? model.supported_reasoning_levels : [];
    const effortValues = [...new Set(levels.map((level) => (
      readOptionalString(readObjectRecord(level)?.effort)
    )).filter((level): level is string => Boolean(level)))];
    const defaultEffort = readOptionalString(model.default_reasoning_level);
    const description = readOptionalString(model.description);
    options.set(value, {
      value,
      label: readOptionalString(model.display_name) ?? readOptionalString(model.name) ?? value,
      ...(description ? { description } : {}),
      ...(effortValues.length > 0 ? {
        effort: {
          ...(defaultEffort && effortValues.includes(defaultEffort) ? { default: defaultEffort } : {}),
          values: effortValues.map((effort) => ({ value: effort })),
        },
      } : {}),
    });
  }
  return [...options.values()];
};

/** Provider registry adapter for configured Codex catalogs, gateways, and active config. */
export class CodexProviderModels implements IProviderModels {
  /** Coalesces gateway reads; config and local catalog files are always read fresh. */
  private proxyModelsCache: {
    key: string;
    expiresAt: number;
    options: Promise<ProviderModelOption[]>;
  } | null = null;

  /** Registry defaults use the CLI's home; focused tests supply isolated files and transport. */
  constructor(private readonly dependencies: {
    codexHome?: string;
    fetch?: typeof fetch;
    now?: () => number;
  } = {}) {}

  private getCodexHome(): string {
    return this.dependencies.codexHome
      ?? readOptionalString(process.env.CODEX_HOME)
      ?? path.join(os.homedir(), '.codex');
  }

  private async readCatalogFile(catalogPath: string, codexHome: string): Promise<ProviderModelOption[]> {
    try {
      // Codex resolves relative config paths against the directory containing config.toml.
      const content = await readFile(path.resolve(codexHome, catalogPath), 'utf8');
      return parseCodexModelOptions(JSON.parse(content), 'catalog');
    } catch {
      return [];
    }
  }

  private async readProxyModels(config: Record<string, unknown>): Promise<ProviderModelOption[]> {
    const providerName = readOptionalString(config.model_provider) ?? 'openai';
    const provider = readObjectRecord(readObjectRecord(config.model_providers)?.[providerName]);
    const baseUrl = readOptionalString(provider?.base_url)
      ?? (providerName === 'openai' ? readOptionalString(config.openai_base_url) : undefined);
    if (!baseUrl) {
      return [];
    }

    try {
      const url = new URL(baseUrl);
      if (url.protocol !== 'http:' && url.protocol !== 'https:') {
        return [];
      }
      url.pathname = `${url.pathname.replace(/\/+$/, '')}/models`;
      url.hash = '';

      const headers = new Headers();
      for (const [name, value] of Object.entries(readObjectRecord(provider?.http_headers) ?? {})) {
        if (typeof value === 'string') {
          headers.set(name, value);
        }
      }
      for (const [name, envName] of Object.entries(readObjectRecord(provider?.env_http_headers) ?? {})) {
        const value = typeof envName === 'string' ? readOptionalString(process.env[envName]) : undefined;
        if (value) {
          headers.set(name, value);
        }
      }
      const envKey = readOptionalString(provider?.env_key);
      const token = (envKey ? readOptionalString(process.env[envKey]) : undefined)
        ?? readOptionalString(provider?.experimental_bearer_token);
      if (token) {
        headers.set('Authorization', `Bearer ${token}`);
      }

      const key = JSON.stringify([url.href, [...headers.entries()]]);
      const now = this.dependencies.now ?? Date.now;
      if (this.proxyModelsCache?.key === key && now() < this.proxyModelsCache.expiresAt) {
        return this.proxyModelsCache.options;
      }
      const options = (this.dependencies.fetch ?? fetch)(url, {
        headers,
        // Do not forward configured gateway headers to a redirect target.
        redirect: 'error',
        signal: AbortSignal.timeout(CODEX_MODELS_TIMEOUT_MS),
      }).then(async (response) => (
        response.ok ? parseCodexModelOptions(await response.json(), 'proxy') : []
      )).catch(() => [] as ProviderModelOption[]);
      this.proxyModelsCache = { key, expiresAt: now() + CODEX_PROXY_MODELS_CACHE_TTL_MS, options };
      return options;
    } catch {
      // A missing or incompatible models endpoint must not block the picker.
      return [];
    }
  }

  async getSupportedModels(): Promise<ProviderModelsDefinition> {
    const codexHome = this.getCodexHome();
    const config = await readCodexConfig(codexHome);
    const catalogPath = readOptionalString(config.model_catalog_json);
    let options = catalogPath ? await this.readCatalogFile(catalogPath, codexHome) : [];
    if (options.length === 0) {
      options = await this.readProxyModels(config);
    }
    if (options.length === 0) {
      return CODEX_PREDEFINED_MODELS;
    }

    const configuredModel = readOptionalString(config.model);
    return {
      OPTIONS: options,
      DEFAULT: options.find((option) => option.value === configuredModel)?.value ?? options[0].value,
    };
  }

  async getCurrentActiveModel(): Promise<ProviderCurrentActiveModel> {
    const config = await readCodexConfig(this.getCodexHome());
    const model = readOptionalString(config.model);
    return model
      ? { model, source: 'provider' }
      : { ...buildDefaultProviderCurrentActiveModel(await this.getSupportedModels()), source: 'default' };
  }
}
