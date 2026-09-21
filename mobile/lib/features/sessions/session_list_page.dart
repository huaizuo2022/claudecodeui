import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/models/project.dart';
import '../../core/util/time.dart';
import 'session_list_controller.dart';

class SessionListPage extends ConsumerWidget {
  const SessionListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);
    final rows = ref.watch(filteredSessionRowsProvider);
    final projects = projectsAsync.value ?? const <ProjectSummary>[];
    final selectedProjectId = ref.watch(selectedProjectIdProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _LargeTitle(
              onAdd: () => _notYet(context, '新建会话'),
            ),
            _SearchField(
              onChanged: (value) =>
                  ref.read(sessionSearchQueryProvider.notifier).update(value),
            ),
            if (projects.isNotEmpty)
              _ProjectChips(
                projects: projects,
                selectedProjectId: selectedProjectId,
                onSelect: (id) => ref.read(selectedProjectIdProvider.notifier).select(id),
              ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.accent,
                backgroundColor: AppColors.surface2,
                onRefresh: () async => ref.refresh(projectsProvider.future),
                child: projectsAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  ),
                  error: (error, _) => _ErrorState(
                    message: '$error',
                    onRetry: () => ref.invalidate(projectsProvider),
                  ),
                  data: (_) {
                    if (rows.isEmpty) {
                      return _EmptyState(
                        hasProjects: projects.isNotEmpty,
                        onRefresh: () => ref.invalidate(projectsProvider),
                      );
                    }
                    return _SessionList(rows: rows);
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

class _ProjectChips extends StatelessWidget {
  const _ProjectChips({
    required this.projects,
    required this.selectedProjectId,
    required this.onSelect,
  });

  final List<ProjectSummary> projects;
  final String? selectedProjectId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: projects.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _Chip(
              label: '全部',
              selected: selectedProjectId == null,
              onTap: () => onSelect(null),
            );
          }
          final project = projects[index - 1];
          return _Chip(
            label: project.displayName.isEmpty ? project.path : project.displayName,
            selected: selectedProjectId == project.projectId,
            onTap: () => onSelect(project.projectId),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.surface2,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: selected ? AppColors.accent.withValues(alpha: 0.42) : AppColors.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: selected ? const Color(0xFFC6CDFF) : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.rows});

  final List<SessionRow> rows;

  @override
  Widget build(BuildContext context) {
    final items = <_ListEntry>[];
    String? currentSection;
    for (final row in rows) {
      final label = sectionLabel(row.session.lastActivity);
      if (label != currentSection) {
        currentSection = label;
        items.add(_ListEntry.header(label));
      }
      items.add(_ListEntry.row(row));
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final entry = items[index];
        final header = entry.header;
        if (header != null) return _SectionHeader(label: header);
        return _SessionRowTile(row: entry.row!);
      },
    );
  }
}

class _ListEntry {
  _ListEntry.header(this.header) : row = null;
  _ListEntry.row(this.row) : header = null;

  final String? header;
  final SessionRow? row;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

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

class _SessionRowTile extends StatelessWidget {
  const _SessionRowTile({required this.row});

  final SessionRow row;

  @override
  Widget build(BuildContext context) {
    final session = row.session;
    final providerColor = _providerColor(session.provider);
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('聊天页在 M3 接入')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: providerColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: providerColor.withValues(alpha: 0.28)),
              ),
              alignment: Alignment.center,
              child: Text(
                _providerInitial(session.provider),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: providerColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.summary.isEmpty ? '(未命名会话)' : session.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    [
                      row.project.displayName.isEmpty
                          ? row.project.path
                          : row.project.displayName,
                      '${session.messageCount} 条',
                      relativeTime(session.lastActivity),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.text3),
                  ),
                ],
              ),
            ),
          ],
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
  const _EmptyState({required this.hasProjects, required this.onRefresh});

  final bool hasProjects;
  final VoidCallback onRefresh;

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
            hasProjects ? '还没有匹配的会话' : '服务器上还没有项目',
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
        const SizedBox(height: 18),
        Center(
          child: TextButton(onPressed: onRefresh, child: const Text('立即刷新')),
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
