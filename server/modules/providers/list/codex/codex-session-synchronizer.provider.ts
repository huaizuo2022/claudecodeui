import os from 'node:os';
import path from 'node:path';
import { createReadStream } from 'node:fs';
import { readFile } from 'node:fs/promises';
import readline from 'node:readline';

import { sessionsDb } from '@/modules/database/index.js';
import {
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
  /** Provider-side rename time, present when the name came from the index. */
  sessionNameUpdatedAt?: string;
};

/** One thread name and its rename time from `~/.codex/session_index.jsonl`. */
type CodexIndexEntry = {
  name: string;
  updatedAt?: string;
};

/**
 * Session indexer for Codex transcript artifacts.
 */
export class CodexSessionSynchronizer implements IProviderSessionSynchronizer {
  private readonly provider = 'codex' as const;
  private readonly codexHome = path.join(os.homedir(), '.codex');

  /**
   * Scans ~/.codex/sessions and upserts discovered sessions into DB.
   */
  async synchronize(since?: Date): Promise<number> {
    const nameMap = await this.readSessionIndex();
    const files = await findFilesRecursivelyCreatedAfter(
      path.join(this.codexHome, 'sessions'),
      '.jsonl',
      since ?? null
    );

    let processed = 0;
    for (const filePath of files) {
      const parsed = await this.processSessionFile(filePath, nameMap);
      if (!parsed) {
        continue;
      }

      await this.persistSession(parsed, filePath);
      processed += 1;
    }

    return processed;
  }

  /**
   * Parses and upserts one Codex session JSONL file.
   */
  async synchronizeFile(filePath: string): Promise<string | null> {
    if (!filePath.endsWith('.jsonl')) {
      return null;
    }

    const nameMap = await this.readSessionIndex();
    const parsed = await this.processSessionFile(filePath, nameMap);
    if (!parsed) {
      return null;
    }

    return this.persistSession(parsed, filePath);
  }

  /**
   * Upserts one parsed session and records when its provider-side name was
   * last changed, so a later sidebar rename can win on recency.
   */
  private async persistSession(parsed: ParsedSession, filePath: string): Promise<string> {
    const timestamps = await readFileTimestamps(filePath);
    const sessionRowId = sessionsDb.createSession(
      parsed.sessionId,
      this.provider,
      parsed.projectPath,
      parsed.sessionName,
      timestamps.createdAt,
      timestamps.updatedAt,
      filePath
    );

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
   * Reads Codex's append-only session index. Renames append another line for
   * the same id, so the last entry is the current name.
   */
  private async readSessionIndex(): Promise<Map<string, CodexIndexEntry>> {
    const entries = new Map<string, CodexIndexEntry>();

    try {
      const fileStream = createReadStream(path.join(this.codexHome, 'session_index.jsonl'));
      const lineReader = readline.createInterface({ input: fileStream, crlfDelay: Infinity });

      for await (const line of lineReader) {
        const trimmed = line.trim();
        if (!trimmed) {
          continue;
        }

        let parsed: Record<string, unknown>;
        try {
          parsed = JSON.parse(trimmed) as Record<string, unknown>;
        } catch {
          // A half-written line must not hide the names that follow it.
          continue;
        }

        const id = typeof parsed.id === 'string' ? parsed.id : '';
        const name = typeof parsed.thread_name === 'string' ? parsed.thread_name.trim() : '';
        if (!id || !name) {
          continue;
        }

        entries.set(id, {
          name,
          updatedAt: typeof parsed.updated_at === 'string' ? parsed.updated_at : undefined,
        });
      }
    } catch {
      // A missing or unreadable index just means no provider-side names.
    }

    return entries;
  }

  /**
   * Extracts session metadata from one Codex JSONL session file.
   */
  private async processSessionFile(
    filePath: string,
    nameMap: Map<string, CodexIndexEntry>
  ): Promise<ParsedSession | null> {
    const parsed = await extractFirstValidJsonlData(filePath, (rawData) => {
      const data = rawData as Record<string, unknown>;
      const payload = data.payload as Record<string, unknown> | undefined;
      const sessionId = typeof payload?.id === 'string' ? payload.id : undefined;
      const projectPath = typeof payload?.cwd === 'string' ? payload.cwd : undefined;

      if (!sessionId || !projectPath) {
        return null;
      }

      return {
        sessionId,
        projectPath,
        isSubagent: payload ? this.isSubagentSessionMeta(payload) : false,
      };
    });

    if (!parsed || parsed.isSubagent) {
      return null;
    }

    // A thread a session was edited off is left on disk on purpose, but it is
    // nobody's conversation any more. Re-indexing it would add a sidebar entry
    // for the version the user edited away from — and for a session that was
    // itself discovered from disk, whose app id is its original thread id, it
    // would hand the row back to that thread.
    if (sessionsDb.isProviderSessionSuperseded(parsed.sessionId, this.provider)) {
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
        sessionName: normalizeSessionName(existingSessionName, 'Untitled Codex Session'),
      };
    }

    // A disk-discovered session's name comes from Codex's index, but a sidebar
    // rename may be newer. Compare the two rename times so whichever happened
    // last wins instead of one source always overwriting the other.
    const indexEntry = nameMap.get(parsed.sessionId);
    const existingNameUpdatedAt = parseTimestampMillis(existingSession?.custom_name_updated_at);
    const indexNameUpdatedAt = parseTimestampMillis(indexEntry?.updatedAt);
    const indexIsNewer =
      indexEntry !== undefined &&
      (!existingSessionName ||
        isUntitledSessionName(existingSessionName) ||
        !existingNameUpdatedAt ||
        indexNameUpdatedAt > existingNameUpdatedAt);

    if (indexEntry && indexIsNewer) {
      return {
        ...parsed,
        sessionName: normalizeSessionName(indexEntry.name, 'Untitled Codex Session'),
        sessionNameUpdatedAt: indexEntry.updatedAt,
      };
    }

    if (existingSessionName && !isUntitledSessionName(existingSessionName)) {
      return {
        ...parsed,
        sessionName: normalizeSessionName(existingSessionName, 'Untitled Codex Session'),
      };
    }

    const fallbackName = await this.extractLastAgentMessageFromEnd(filePath);
    return {
      ...parsed,
      sessionName: normalizeSessionName(fallbackName, 'Untitled Codex Session'),
    };
  }

  /**
   * Returns true when a session_meta payload belongs to a Codex sub-agent
   * thread (Codex >=0.144 collaboration spawn_agent, review, compact, etc.).
   * Sub-agent rollouts live in the same sessions tree as user sessions, so
   * they must be skipped here to stay out of the sidebar — the Codex
   * equivalent of the Claude synchronizer's subagent transcript skip.
   * Top-level sessions carry thread_source "user" and a string source
   * ("exec"/"cli"); sub-agents carry thread_source "subagent" and an object
   * source keyed by "subagent".
   */
  private isSubagentSessionMeta(payload: Record<string, unknown>): boolean {
    if (payload.thread_source === 'subagent') {
      return true;
    }

    const source = payload.source;
    return typeof source === 'object' && source !== null && 'subagent' in source;
  }

  private async extractLastAgentMessageFromEnd(filePath: string): Promise<string | undefined> {
    try {
      const content = await readFile(filePath, 'utf8');
      const lines = content.split(/\r?\n/);

      for (let index = lines.length - 1; index >= 0; index -= 1) {
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
        const payload = data.payload as Record<string, unknown> | undefined;
        const payloadType = typeof payload?.type === 'string' ? payload.type : undefined;
        const lastAgentMessage = typeof payload?.last_agent_message === 'string'
          ? payload.last_agent_message
          : undefined;

        if (eventType === 'event_msg' && payloadType === 'task_complete' && lastAgentMessage?.trim()) {
          return lastAgentMessage;
        }
      }
    } catch {
      // Ignore missing/unreadable files so sync can continue.
    }

    return undefined;
  }
}
