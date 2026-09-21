import { useEffect, useState } from 'react';
import { MessageSquare } from 'lucide-react';
import { useTranslation } from 'react-i18next';

import { api } from '@/shared/api';
import { LLMProviderLogo } from '@/shared/ui';
import { formatCompactAge } from '@/modules/sidebar';
import type { RecentConversationListItem } from '@/shared/types';
import MobileMenuButton from '@/modules/project-workspace/MobileMenuButton';

type WorkspaceStateViewProps = {
  mode: 'loading' | 'empty';
  isMobile: boolean;
  onMenuClick: () => void;
  onOpenSession: (sessionId: string) => void;
};

type RecentConversationsApiPayload = {
  data?: {
    conversations?: RecentConversationListItem[];
    total?: number;
    hasMore?: boolean;
  };
};

/** Rendered by WorkspaceMain instead of the workspace while projects load or when none is selected. */
export default function WorkspaceStateView({
  mode,
  isMobile,
  onMenuClick,
  onOpenSession,
}: WorkspaceStateViewProps) {
  const { t } = useTranslation();
  const [recent, setRecent] = useState<RecentConversationListItem[]>([]);

  useEffect(() => {
    if (mode !== 'empty') {
      return;
    }

    let cancelled = false;
    (async () => {
      try {
        const response = await api.recentConversations({ limit: 10, offset: 0 });
        if (!response.ok || cancelled) {
          return;
        }
        const payload = (await response.json()) as RecentConversationsApiPayload;
        setRecent(Array.isArray(payload.data?.conversations) ? payload.data.conversations : []);
      } catch {
        // Keep the empty state usable even when the recent list cannot load.
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [mode]);

  const isLoading = mode === 'loading';

  return (
    <div className="flex h-full flex-col">
      {isMobile && (
        <div className="pwa-header-safe flex-shrink-0 border-b border-border/50 bg-background/80 p-2 backdrop-blur-sm sm:p-3">
          <MobileMenuButton onMenuClick={onMenuClick} compact />
        </div>
      )}

      {isLoading ? (
        <div className="flex flex-1 items-center justify-center">
          <div className="text-center text-muted-foreground">
            <div className="mx-auto mb-4 h-10 w-10">
              <div
                className="h-full w-full rounded-full border-[3px] border-muted border-t-primary"
                style={{
                  animation: 'spin 1s linear infinite',
                  WebkitAnimation: 'spin 1s linear infinite',
                  MozAnimation: 'spin 1s linear infinite',
                }}
              />
            </div>
            <h2 className="mb-1 text-lg font-semibold text-foreground">{t('mainContent.loading')}</h2>
            <p className="text-sm">{t('mainContent.settingUpWorkspace')}</p>
          </div>
        </div>
      ) : (
        <div className="flex flex-1 justify-center overflow-y-auto py-8">
          <div className="mx-auto w-full max-w-md px-6">
            {recent.length > 0 && (
              <div>
                <div className="mb-2 flex items-center justify-between px-1">
                  <h3 className="text-sm font-medium text-foreground">
                    {t('mainContent.recentSessions', '最近会话')}
                  </h3>
                </div>
                <div className="overflow-hidden rounded-xl border border-border/70 bg-card/50 shadow-sm">
                  {recent.map((session) => (
                    <button
                      key={`${session.provider}-${session.sessionId}`}
                      type="button"
                      onClick={() => onOpenSession(session.sessionId)}
                      className="group flex w-full items-center gap-3 border-b border-border/40 px-3.5 py-3 text-left transition-colors last:border-b-0 hover:bg-accent/60"
                    >
                      <span className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-lg bg-muted/60">
                        <LLMProviderLogo provider={session.provider} className="h-4 w-4" />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-sm font-normal text-foreground">
                          {session.sessionTitle || t('mainContent.untitledSession')}
                        </span>
                        <span className="mt-0.5 flex min-w-0 items-center gap-1.5 text-xs text-muted-foreground">
                          <span className="truncate">{session.projectDisplayName}</span>
                          {session.lastActivity && (
                            <>
                              <span aria-hidden>·</span>
                              <span className="flex-shrink-0 tabular-nums">
                                {formatCompactAge(session.lastActivity, new Date())}
                              </span>
                            </>
                          )}
                        </span>
                      </span>
                      <MessageSquare className="h-3.5 w-3.5 flex-shrink-0 text-muted-foreground/40 opacity-0 transition-opacity group-hover:opacity-100" />
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
