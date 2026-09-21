import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/models/project.dart';
import '../../core/models/session.dart';
import '../../core/util/time.dart';
import '../chat/chat_page.dart';
import 'session_list_controller.dart';

/// Home screen: a "最近会话" block like the web home page, followed by the
/// project list with expandable sessions, like the web sidebar.
class SessionListPage extends ConsumerWidget {
  SessionListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final projectsAsync = ref.watch(projectsProvider);
    final recentAsync = ref.watch(recentSessionsProvider);
    final loading = projectsAsync.isLoading || recentAsync.isLoading;
    final error = projectsAsync.hasError ? projectsAsync.error : recentAsync.error;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _LargeTitle(onAdd: () => _notYet(context, '新建会话')),
            _SearchField(
              onChanged: (value) =>
                  ref.read(sessionSearchQueryProvider.notifier).update(value),
            ),
            Expanded(
              child: RefreshIndicator(
                color: palette.accent,
                backgroundColor: palette.surface2,
                onRefresh: () => ref.read(homeRefreshProvider)(),
                child: Builder(
                  builder: (context) {
                    if (loading && !projectsAsync.hasValue && !recentAsync.hasValue) {
                      return Center(
                        child: CircularProgressIndicator(color: palette.accent),
                      );
                    }
                    if (error != null &&
                        !projectsAsync.hasValue &&
                        !recentAsync.hasValue) {
                      return _ErrorState(
                        message: '$error',
                        onRetry: () => ref.invalidate(projectsProvider),
                      );
                    }
                    return _HomeList(
                      hasAnyData: projectsAsync.hasValue || recentAsync.hasValue,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _notYet(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what 还没接上，下一个里程碑补')),
    );
  }
}

class _HomeList extends ConsumerWidget {
  const _HomeList({required this.hasAnyData});

  final bool hasAnyData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(filteredRecentSessionsProvider);
    final projects = ref.watch(visibleProjectsProvider);
    final expanded = ref.watch(expandedProjectsProvider);

    if (recent.isEmpty && projects.isEmpty) {
      return _EmptyState(hasAnyData: hasAnyData);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (recent.isNotEmpty) ...[
          const _SectionHeader('最近会话'),
          for (final session in recent) _RecentSessionTile(session: session),
        ],
        if (projects.isNotEmpty) ...[
          const _SectionHeader('项目'),
          for (final entry in projects)
            _ProjectGroup(
              entry: entry,
              expanded: expanded.contains(entry.project.projectId),
              onToggle: () => ref
                  .read(expandedProjectsProvider.notifier)
                  .toggle(entry.project.projectId),
            ),
        ],
      ],
    );
  }
}

class _LargeTitle extends StatelessWidget {
  const _LargeTitle({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 6, 18, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '会话',
              style: TextStyle(
                fontSize: AppTextSizes.pageTitle,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
            ),
          ),
          Material(
            color: palette.surface2,
            shape: CircleBorder(),
            child: InkWell(
              customBorder: CircleBorder(),
              onTap: onAdd,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.add, size: 19, color: palette.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: palette.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Padding(
              padding: EdgeInsets.only(left: 11, right: 8),
              child: Icon(Icons.search, size: 16, color: palette.text3),
            ),
            Expanded(
              child: TextField(
                onChanged: onChanged,
                style: TextStyle(fontSize: 14.5, color: palette.text),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: '搜索会话、项目',
                  hintStyle: TextStyle(fontSize: 14.5, color: palette.text3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: palette.text3,
        ),
      ),
    );
  }
}

class _RecentSessionTile extends StatelessWidget {
  const _RecentSessionTile({required this.session});

  final RecentSession session;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final providerColor = _providerColor(session.provider, palette);
    final meta = [
      if (session.projectDisplayName.isNotEmpty) session.projectDisplayName,
      if (session.lastActivity != null) relativeTime(session.lastActivity!),
    ].join(' · ');

    return InkWell(
      onTap: () => _openChat(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _ProviderMark(provider: session.provider, color: providerColor),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: palette.text,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: palette.text3),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openChat(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          sessionId: session.sessionId,
          title: session.displayTitle,
          subtitle: session.projectDisplayName.isNotEmpty
              ? session.projectDisplayName
              : session.provider,
        ),
      ),
    );
  }
}

class _ProjectGroup extends StatelessWidget {
  const _ProjectGroup({
    required this.entry,
    required this.expanded,
    required this.onToggle,
  });

  final VisibleProject entry;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final project = entry.project;
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 18, color: palette.text2),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    project.displayName.isEmpty ? project.path : project.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '${project.totalSessions}',
                  style: TextStyle(fontSize: 12, color: palette.text3),
                ),
                SizedBox(width: 6),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: palette.text3,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          for (final session in entry.sessions)
            _ProjectSessionTile(
              session: session,
              indent: true,
            ),
      ],
    );
  }
}

class _ProjectSessionTile extends StatelessWidget {
  const _ProjectSessionTile({required this.session, required this.indent});

  final SessionSummary session;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final providerColor = _providerColor(session.provider, palette);
    return InkWell(
      onTap: () => _openChat(context),
      child: Padding(
        padding: EdgeInsets.only(left: indent ? 44 : 16, right: 16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              _ProviderMark(provider: session.provider, color: providerColor, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.summary.isEmpty ? '(未命名会话)' : session.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: palette.text2),
                    ),
                    SizedBox(height: 3),
                    Text(
                      [
                        if (session.messageCount > 0) '${session.messageCount} 条',
                        relativeTime(session.lastActivity),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: palette.text3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openChat(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          sessionId: session.id,
          title: session.summary,
          subtitle: session.provider,
        ),
      ),
    );
  }
}

class _ProviderMark extends StatelessWidget {
  const _ProviderMark({required this.provider, required this.color, this.size = 30});

  final String provider;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.33),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      alignment: Alignment.center,
      child: Text(
        _providerInitial(provider),
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

String _providerInitial(String provider) {
  switch (provider) {
    case 'claude':
      return 'C';
    case 'codex':
      return 'X';
    case 'cursor':
      return 'U';
    case 'opencode':
      return 'O';
    default:
      return provider.isEmpty ? '?' : provider[0].toUpperCase();
  }
}

Color _providerColor(String provider, AppPalette palette) {
  switch (provider) {
    case 'claude':
      return palette.claude;
    case 'codex':
      return palette.codex;
    case 'cursor':
      return palette.cursor;
    default:
      return palette.text2;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAnyData});

  final bool hasAnyData;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListView(
      physics: AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: 120),
        Icon(Icons.chat_bubble_outline, size: 34, color: palette.text3),
        SizedBox(height: 14),
        Center(
          child: Text(
            hasAnyData ? '没有匹配的会话' : '服务器上还没有项目',
            style: TextStyle(fontSize: 15, color: palette.text2),
          ),
        ),
        SizedBox(height: 8),
        Center(
          child: Text(
            '下拉可以刷新',
            style: TextStyle(fontSize: 12.5, color: palette.text3),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListView(
      physics: AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: 110),
        Icon(Icons.cloud_off_outlined, size: 34, color: palette.danger),
        SizedBox(height: 14),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: palette.text2),
          ),
        ),
        SizedBox(height: 16),
        Center(
          child: FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: palette.surface3),
            child: const Text('重试'),
          ),
        ),
      ],
    );
  }
}
