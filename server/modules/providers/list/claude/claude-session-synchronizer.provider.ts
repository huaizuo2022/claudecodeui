import os from 'node:os';
import path from 'node:path';
import { readFile } from 'node:fs/promises';

import { sessionsDb } from '@/modules/database/index.js';
import {
  buildLookupMap,
  extractFirstValidJsonlData,
  findFilesRecursivelyCreatedAfter,
  isUntitledSessionName,
  normalizeSessionName,
  parseTimestampMillis,
  readFileTimestamps,
} from '@/shared/utils.js';
import type { IProviderSessionSynchronizer } from '@/shared/interfaces.js';

type ParsedSession = {
  sessionId: string;
  projectPath: string;
  sessionName?: string;
  /** Title last found in the transcript, recorded to detect a new rename. */
  providerTitle?: string;
  /** When the title was applied; the transcript's last write time. */
  sessionNameUpdatedAt?: string;
};

/**
 * Session indexer for Claude transcript artifacts.
 */
export class ClaudeSessionSynchronizer implements IProviderSessionSynchronizer {
  private readonly provider = 'claude' as const;
  private readonly claudeHome = path.join(os.homedir(), '.claude');

  /**
   * Returns true when a JSONL file is a subagent transcript or tool result
   * rather than a top-level session.
   *
   * Claude stores subagent transcripts under a `subagents/` directory and
   * tool results under a `tool-results/` directory, e.g.
   * `~/.claude/projects/<encoded-cwd>/<session-id>/subagents/agent-<id>.jsonl`.
   * Those files repeat the parent session's `sessionId`, so indexing them as
   * standalone sessions overwrites the parent row's `jsonl_path` and corrupts
   * the main session record. The recursive scan in `synchronize()` reaches
   * them, so both entry points must skip them.
   */
  private isSubagentTranscript(filePath: string): boolean {
    const pathParts = path.normalize(filePath).split(path.sep);
    return pathParts.includes('subagents') || pathParts.includes('tool-results');
  }

  /**
   * Scans ~/.claude/projects and upserts discovered sessions into DB.
   */
  async synchronize(since?: Date): Promise<number> {
    const nameMap = await buildLookupMap(path.join(this.claudeHome, 'history.jsonl'), 'sessionId', 'display');
    const files = await findFilesRecursivelyCreatedAfter(
      path.join(this.claudeHome, 'projects'),
      '.jsonl',
      since ?? null
    );

    let processed = 0;
    for (const filePath of files) {
      if (this.isSubagentTranscript(filePath)) {
        continue;
      }

      const timestamps = await readFileTimestamps(filePath);
      const parsed = await this.processSessionFile(filePath, nameMap, timestamps);
      if (!parsed) {
        continue;
      }

      await this.persistSession(parsed, filePath, timestamps);
      processed += 1;
    }

    return processed;
  }

  /**
   * Upserts one parsed session, recording the provider title baseline and the
   * time a rename was applied so a later sidebar rename can win on recency.
   */
  private async persistSession(
    parsed: ParsedSession,
    filePath: string,
    timestamps: { createdAt?: string; updatedAt?: string }
  ): Promise<string> {
    const sessionRowId = sessionsDb.createSession(
      parsed.sessionId,
      this.provider,
      parsed.projectPath,
      parsed.sessionName,
      timestamps.createdAt,
      timestamps.updatedAt,
      filePath
    );

    if (parsed.providerTitle) {
      sessionsDb.updateSessionProviderTitle(sessionRowId, parsed.providerTitle);
    }

    if (parsed.sessionName && parsed.sessionNameUpdatedAt) {
      sessionsDb.updateSessionCustomName(
        sessionRowId,
        parsed.sessionName,
        parsed.sessionNameUpdatedAt
      );
    }

    return sessionRowId;
  }

  /**
   * Parses and upserts one Claude session JSONL file.
   */
  async synchronizeFile(filePath: string): Promise<string | null> {
    if (!filePath.endsWith('.jsonl')) {
      return null;
    }
    if (this.isSubagentTranscript(filePath)) {
      return null;
    }

    const nameMap = await buildLookupMap(path.join(this.claudeHome, 'history.jsonl'), 'sessionId', 'display');
    const timestamps = await readFileTimestamps(filePath);
    const parsed = await this.processSessionFile(filePath, nameMap, timestamps);
    if (!parsed) {
      return null;
    }

    return this.persistSession(parsed, filePath, timestamps);
  }

  /**
   * Extracts session metadata from one Claude JSONL session file.
   */
  private async processSessionFile(
    filePath: string,
    nameMap: Map<string, string>,
    timestamps: { createdAt?: string; updatedAt?: string }
  ): Promise<ParsedSession | null> {
    const parsed = await extractFirstValidJsonlData(filePath, (rawData) => {
      const data = rawData as Record<string, unknown>;
      const sessionId = typeof data.sessionId === 'string' ? data.sessionId : undefined;
      const projectPath = typeof data.cwd === 'string' ? data.cwd : undefined;

      if (!sessionId || !projectPath) {
        return null;
      }

      return {
        sessionId,
        projectPath,
      };
    });

    if (!parsed) {
      return null;
    }

    // App-created sessions are keyed by an app id, so disk-discovered provider
    // ids must be resolved through the provider-id mapping first.
    const existingSession = sessionsDb.getSessionByProviderSessionId(parsed.sessionId)
      ?? sessionsDb.getSessionById(parsed.sessionId);
    const existingSessionName = existingSession?.custom_name;

    // App-created sessions take their name from the first CloudCLI message and
    // keep it; provider-side titles must not rename a conversation the app
    // itself named.
    const appCreatedSession =
      existingSession !== null &&
      existingSession !== undefined &&
      existingSession.session_id !== existingSession.provider_session_id;
    if (
      appCreatedSession &&
      existingSessionName &&
      !isUntitledSessionName(existingSessionName)
    ) {
      return {
        ...parsed,
        sessionName: normalizeSessionName(existingSessionName, 'Untitled Claude Session'),
      };
    }

    const providerTitle = await this.extractSessionTitle(filePath, parsed.sessionId);
    const providerTitleValue = providerTitle?.title;
    // Only an explicit `custom-title` is a user rename comparable to a sidebar
    // rename. ai-title/last-prompt are automatic and must not overwrite one.
    const providerTitleChanged =
      Boolean(providerTitle?.manual) && providerTitleValue !== existingSession?.provider_title;

    // `custom-title` events carry no timestamp, so the transcript's last write
    // is the closest evidence of when the rename happened.
    const existingNameUpdatedAt = parseTimestampMillis(existingSession?.custom_name_updated_at);
    const fileUpdatedAt = parseTimestampMillis(timestamps.updatedAt);
    const providerRenameIsNewer =
      !existingSessionName ||
      isUntitledSessionName(existingSessionName) ||
      !existingNameUpdatedAt ||
      fileUpdatedAt > existingNameUpdatedAt;

    let sessionName =
      existingSessionName && !isUntitledSessionName(existingSessionName)
        ? existingSessionName
        : undefined;
    let sessionNameUpdatedAt: string | undefined;

    if (providerTitle?.manual && providerTitleChanged && providerRenameIsNewer) {
      sessionName = providerTitle.title;
      sessionNameUpdatedAt = timestamps.updatedAt;
    }

    if (!sessionName) {
      sessionName = providerTitleValue ?? nameMap.get(parsed.sessionId);
    }

    return {
      ...parsed,
      sessionName: normalizeSessionName(sessionName, 'Untitled Claude Session'),
      providerTitle: providerTitleValue,
      sessionNameUpdatedAt,
    };
  }

  /**
   * Returns the best available title for one session from its transcript.
   *
   * Scans forward keeping the last match of each event type, then prefers
   * `custom-title` (a manual `/rename`) over `ai-title` over `last-prompt`.
   * Claude writes `custom-title` immediately before `ai-title`, so a reverse
   * scan that returns its first hit would always lose the manual rename.
   *
   * Returns undefined on a missing or unreadable file so sync can continue.
   */
  private async extractSessionTitle(
    filePath: string,
    sessionId: string
  ): Promise<{ title: string; manual: boolean } | undefined> {
    try {
      const content = await readFile(filePath, 'utf8');
      const lines = content.split(/\r?\n/);

      let foundCustomTitle: string | undefined;
      let foundAiTitle: string | undefined;
      let foundLastPrompt: string | undefined;

      for (let index = 0; index < lines.length; index += 1) {
        const line = lines[index]?.trim();
        if (!line) {
          continue;
        }

        let parsed: unknown;
        try {
          parsed = JSON.parse(line);
        } catch {
          continue;
        }

        const data = parsed as Record<string, unknown>;
        const eventType = typeof data.type === 'string' ? data.type : undefined;
        const eventSessionId = typeof data.sessionId === 'string' ? data.sessionId : undefined;

        if (eventSessionId !== sessionId) {
          continue;
        }

        if (eventType === 'custom-title') {
          const title = typeof data.customTitle === 'string' ? data.customTitle : undefined;
          if (title?.trim()) {
            foundCustomTitle = title;
          }
        } else if (eventType === 'ai-title') {
          const title = typeof data.aiTitle === 'string' ? data.aiTitle : undefined;
          if (title?.trim()) {
            foundAiTitle = title;
          }
        } else if (eventType === 'last-prompt') {
          const prompt = typeof data.lastPrompt === 'string' ? data.lastPrompt : undefined;
          if (prompt?.trim()) {
            foundLastPrompt = prompt;
          }
        }
      }

      if (foundCustomTitle) {
        return { title: foundCustomTitle, manual: true };
      }

      const fallbackTitle = foundAiTitle || foundLastPrompt;
      return fallbackTitle ? { title: fallbackTitle, manual: false } : undefined;
    } catch {
      // Ignore missing/unreadable files so sync can continue.
    }

    return undefined;
  }
}
