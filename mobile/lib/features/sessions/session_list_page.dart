import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/models/project.dart';
import '../../core/models/session.dart';
import '../../core/util/time.dart';
import 'session_list_controller.dart';

/// Home screen: a "最近会话" block like the web home page, followed by the
/// project list with expandable sessions, like the web sidebar.
class SessionListPage extends ConsumerWidget {
  const SessionListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);
    final recentAsync = ref.watch(recentSessionsProvider);
    final loading = projectsAsync.isLoading || recentAsync.isLoading;
    final error = projectsAsync.hasError ? projectsAsync.error : recentAsync.error;

    return Scaffold(
      backgroundColor: AppColors.bg,
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
                color: AppColors.accent,
                backgroundColor: AppColors.surface2,
                onRefresh: () => ref.read(homeRefreshProvider)(),
                child: Builder(
                  builder: (context) {
                    if (loading && !projectsAsync.hasValue && !recentAsync.hasValue) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppColors.accent),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '会话',
              style: TextStyle(
                fontSize: AppTextSizes.pageTitle,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
          Material(
            color: AppColors.surface2,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onAdd,
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.add, size: 19, color: AppColors.text),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 11, right: 8),
              child: Icon(Icons.search, size: 16, color: AppColors.text3),
            ),
            Expanded(
              child: TextField(
                onChanged: onChanged,
                style: const TextStyle(fontSize: 14.5, color: AppColors.text),
                decoration: const InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: '搜索会话、项目',
                  hintStyle: TextStyle(fontSize: 14.5, color: AppColors.text3),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: AppColors.text3,
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
    final providerColor = _providerColor(session.provider);
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.text3),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('聊天页在 M3 接入')),
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
    final project = entry.project;
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, size: 18, color: AppColors.text2),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    project.displayName.isEmpty ? project.path : project.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${project.totalSessions}',
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
                const SizedBox(width: 6),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: AppColors.text3,
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
    final providerColor = _providerColor(session.provider);
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('聊天页在 M3 接入')),
        );
      },
      child: Padding(
        padding: EdgeInsets.only(left: indent ? 44 : 16, right: 16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              _ProviderMark(provider: session.provider, color: providerColor, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.summary.isEmpty ? '(未命名会话)' : session.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: AppColors.text2),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (session.messageCount > 0) '${session.messageCount} 条',
                        relativeTime(session.lastActivity),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.text3),
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

Color _providerColor(String provider) {
  switch (provider) {
    case 'claude':
      return AppColors.claude;
    case 'codex':
      return AppColors.codex;
    case 'cursor':
      return AppColors.cursor;
    default:
      return AppColors.text2;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAnyData});

  final bool hasAnyData;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.chat_bubble_outline, size: 34, color: AppColors.text3),
        const SizedBox(height: 14),
        Center(
          child: Text(
            hasAnyData ? '没有匹配的会话' : '服务器上还没有项目',
            style: const TextStyle(fontSize: 15, color: AppColors.text2),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            '下拉可以刷新',
            style: TextStyle(fontSize: 12.5, color: AppColors.text3),
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 110),
        const Icon(Icons.cloud_off_outlined, size: 34, color: AppColors.danger),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.text2),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: AppColors.surface3),
            child: const Text('重试'),
          ),
        ),
      ],
    );
  }
}
