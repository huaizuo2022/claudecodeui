import { useMemo, useState } from 'react';
import ReactDOM from 'react-dom';
import { Folder, MessageSquarePlus, Search, X } from 'lucide-react';
import { useTranslation } from 'react-i18next';

import type { Project } from '@/shared/types';

type NewSessionProjectPickerProps = {
  projects: Project[];
  onSelect: (project: Project) => void;
  onClose: () => void;
};

/** Rendered by SidebarContent as a modal to pick a project and start a fresh session in it. */
export default function NewSessionProjectPicker({
  projects,
  onSelect,
  onClose,
}: NewSessionProjectPickerProps) {
  const { t } = useTranslation('sidebar');
  const [filter, setFilter] = useState('');

  const filteredProjects = useMemo(() => {
    const query = filter.trim().toLowerCase();
    if (!query) {
      return projects;
    }
    return projects.filter((project) => {
      const name = project.displayName.toLowerCase();
      const path = (project.fullPath || project.path || '').toLowerCase();
      return name.includes(query) || path.includes(query);
    });
  }, [filter, projects]);

  return ReactDOM.createPortal(
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 p-4 backdrop-blur-sm sm:items-center"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={t('sessions.newSession')}
        className="flex max-h-[80vh] w-full max-w-md flex-col overflow-hidden rounded-xl border border-border bg-card shadow-2xl"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-border px-4 py-3">
          <div className="flex items-center gap-2">
            <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10 text-primary">
              <MessageSquarePlus className="h-4 w-4" />
            </span>
            <h2 className="text-base font-semibold text-foreground">{t('sessions.newSession')}</h2>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label={t('actions.cancel')}
            className="flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="relative border-b border-border/60 px-4 py-2.5">
          <Search className="pointer-events-none absolute left-7 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground/60" />
          <input
            type="text"
            autoFocus
            value={filter}
            onChange={(event) => setFilter(event.target.value)}
            placeholder={t('projects.searchPlaceholder')}
            className="w-full rounded-lg border border-border/70 bg-background py-2 pl-9 pr-3 text-sm text-foreground outline-none transition-all placeholder:text-muted-foreground/50 focus:border-primary/50 focus:ring-1 focus:ring-primary/30"
          />
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto p-2">
          {filteredProjects.length === 0 ? (
            <div className="flex flex-col items-center gap-2 px-4 py-10 text-center">
              <Folder className="h-8 w-8 text-muted-foreground/40" />
              <p className="text-sm text-muted-foreground">
                {t('projects.noProjects', 'No projects found')}
              </p>
            </div>
          ) : (
            filteredProjects.map((project) => (
              <button
                key={project.projectId}
                type="button"
                onClick={() => onSelect(project)}
                className="group flex w-full items-center gap-2.5 rounded-lg px-2.5 py-2.5 text-left transition-colors hover:bg-accent/70"
              >
                <span className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-lg border border-border/60 bg-muted/45 text-muted-foreground group-hover:text-foreground">
                  <Folder className="h-4 w-4" />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-normal text-foreground">
                    {project.displayName}
                  </span>
                  {project.fullPath && (
                    <span className="block truncate text-[11px] text-muted-foreground/70">
                      {project.fullPath}
                    </span>
                  )}
                </span>
                <MessageSquarePlus className="h-3.5 w-3.5 flex-shrink-0 text-muted-foreground/40 opacity-0 transition-opacity group-hover:opacity-100" />
              </button>
            ))
          )}
        </div>
      </div>
    </div>,
    document.body,
  );
}
