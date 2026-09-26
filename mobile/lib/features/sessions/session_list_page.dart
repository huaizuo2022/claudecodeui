import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/api/projects_api.dart';
import '../../core/api/sessions_api.dart';
import '../../core/models/project.dart';
import '../../core/models/session.dart';
import '../../core/providers.dart';
import '../../core/util/time.dart';
import '../chat/chat_page.dart';
import '../settings/settings_page.dart';
import 'create_project_sheet.dart';
import 'create_session_sheet.dart';
import 'project_actions_sheet.dart';
import 'session_actions_sheet.dart';
import 'session_list_controller.dart';

/// Home screen mirroring the web sidebar (Figure 2): CloudCLI header with
/// quick actions, 4-way segmented tabs (对话, 项目, 运行中, 归档), search bar, and
/// corresponding content views.
class SessionListPage extends ConsumerStatefulWidget {
  const SessionListPage({super.key});

  @override
  ConsumerState<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends ConsumerState<SessionListPage> {
  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await ref.read(homeRefreshProvider)();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final activeTab = ref.watch(sidebarTabProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final recentAsync = ref.watch(recentSessionsStateProvider);
    final runningAsync = ref.watch(runningSessionsProvider);

    final starredCount = ref.watch(starredSessionsCountProvider);
    final runningCount = runningAsync.value?.length ?? 0;
    final loading = projectsAsync.isLoading || recentAsync.isLoading;
    final hasAnyData = projectsAsync.hasValue || recentAsync.hasValue;
    final socketConnected = ref.watch(socketConnectedProvider);
    final error = projectsAsync.hasError
        ? projectsAsync.error
        : (recentAsync.hasError ? recentAsync.error : null);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _SidebarHeader(
              isRefreshing: _isRefreshing,
              onRefresh: _handleRefresh,
              onNewSession: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: AppPalette.of(context).bgElevated,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (_) => const CreateSessionSheet(),
              ),
              onCreateProject: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: AppPalette.of(context).bgElevated,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (_) => const CreateProjectSheet(),
              ),
              onOpenSettings: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
            ),
            _SidebarSegmentedTabs(
              activeTab: activeTab,
              starredCount: starredCount,
              runningCount: runningCount,
              onTabSelected: (tab) =>
                  ref.read(sidebarTabProvider.notifier).selectTab(tab),
            ),
            _SidebarSearchBar(
              activeTab: activeTab,
              onChanged: (value) =>
                  ref.read(sessionSearchQueryProvider.notifier).update(value),
            ),
            if (activeTab == SidebarTab.conversations)
              const _ProviderFilterBar(),
            if (hasAnyData && (error != null || !socketConnected))
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.line),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 14,
                      color: palette.text3,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '离线模式（已加载本地缓存）',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.text3,
                        ),
                      ),
                    ),
                    if (_isRefreshing)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.accent,
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: _handleRefresh,
                        child: Text(
                          '重试',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                color: palette.accent,
                backgroundColor: palette.surface2,
                onRefresh: _handleRefresh,
                child: Builder(
                  builder: (context) {
                    if (loading && !hasAnyData) {
                      return Center(
                        child: CircularProgressIndicator(color: palette.accent),
                      );
                    }
                    if (error != null && !hasAnyData) {
                      return _ErrorState(
                        message: '$error',
                        onRetry: _handleRefresh,
                      );
                    }
                    return switch (activeTab) {
                      SidebarTab.conversations => const _ConversationsTabView(),
                      SidebarTab.projects => const _ProjectsTabView(),
                      SidebarTab.starred => const _StarredTabView(),
                      SidebarTab.running => const _RunningSessionsTabView(),
                      SidebarTab.archived => const _ArchivedTabView(),
                    };
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header matching Figure 2
// ---------------------------------------------------------------------------

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.isRefreshing,
    required this.onRefresh,
    required this.onNewSession,
    required this.onCreateProject,
    required this.onOpenSettings,
  });

  final bool isRefreshing;
  final VoidCallback onRefresh;
  final VoidCallback onNewSession;
  final VoidCallback onCreateProject;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Text(
            'CloudCLI',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: palette.text,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          // Action Buttons
          // 1. New Chat (Blue primary button)
          Material(
            color: palette.accent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onNewSession,
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Icon(Icons.add_comment_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 2. Refresh Button
          Material(
            color: palette.surface2,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onRefresh,
              child: SizedBox(
                width: 32,
                height: 32,
                child: isRefreshing
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.text2,
                          ),
                        ),
                      )
                    : Icon(Icons.refresh_rounded, size: 17, color: palette.text2),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 3. New Project Button
          Material(
            color: palette.surface2,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onCreateProject,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(Icons.create_new_folder_outlined, size: 17, color: palette.text2),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 4. Settings Button
          Material(
            color: palette.surface2,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onOpenSettings,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(Icons.settings_outlined, size: 17, color: palette.text2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Segmented Tabs: 对话 / 项目 / 加星 / 运行中 / 归档
// ---------------------------------------------------------------------------

class _SidebarSegmentedTabs extends StatelessWidget {
  const _SidebarSegmentedTabs({
    required this.activeTab,
    required this.starredCount,
    required this.runningCount,
    required this.onTabSelected,
  });

  final SidebarTab activeTab;
  final int starredCount;
  final int runningCount;
  final ValueChanged<SidebarTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: palette.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            _TabItem(
              title: '对话',
              icon: Icons.chat_bubble_outline_rounded,
              isActive: activeTab == SidebarTab.conversations,
              onTap: () => onTabSelected(SidebarTab.conversations),
            ),
            _TabItem(
              title: '项目',
              icon: Icons.folder_outlined,
              isActive: activeTab == SidebarTab.projects,
              onTap: () => onTabSelected(SidebarTab.projects),
            ),
            _TabItem(
              title: null,
              icon: activeTab == SidebarTab.starred || starredCount > 0
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              iconColor: activeTab == SidebarTab.starred || starredCount > 0
                  ? palette.warn
                  : null,
              badgeCount: starredCount,
              badgeColor: palette.warn,
              isActive: activeTab == SidebarTab.starred,
              onTap: () => onTabSelected(SidebarTab.starred),
            ),
            _TabItem(
              title: null,
              icon: Icons.show_chart_rounded,
              badgeCount: runningCount,
              badgeColor: palette.ok,
              iconColor: activeTab == SidebarTab.running || runningCount > 0
                  ? palette.ok
                  : null,
              isActive: activeTab == SidebarTab.running,
              onTap: () => onTabSelected(SidebarTab.running),
            ),
            _TabItem(
              title: null,
              icon: Icons.archive_outlined,
              isActive: activeTab == SidebarTab.archived,
              onTap: () => onTabSelected(SidebarTab.archived),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.title,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.iconColor,
    this.badgeCount = 0,
    this.badgeColor,
  });

  final String? title;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final Color? iconColor;
  final int badgeCount;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isIconOnly = title == null;

    return Expanded(
      flex: isIconOnly ? 1 : 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: double.infinity,
          decoration: BoxDecoration(
            color: isActive ? palette.bgElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isActive
                        ? (iconColor ?? palette.text)
                        : (iconColor ?? palette.text3),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      top: -6,
                      right: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: badgeColor ?? palette.accent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (title != null) ...[
                const SizedBox(width: 5),
                Text(
                  title!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? palette.text : palette.text3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search Bar with Dynamic Placeholder
// ---------------------------------------------------------------------------

class _SidebarSearchBar extends StatefulWidget {
  const _SidebarSearchBar({
    required this.activeTab,
    required this.onChanged,
  });

  final SidebarTab activeTab;
  final ValueChanged<String> onChanged;

  @override
  State<_SidebarSearchBar> createState() => _SidebarSearchBarState();
}

class _SidebarSearchBarState extends State<_SidebarSearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _placeholderForTab(SidebarTab tab) => switch (tab) {
        SidebarTab.conversations => '搜索对话内容...',
        SidebarTab.projects => '搜索项目...',
        SidebarTab.starred => '搜索加星会话...',
        SidebarTab.running => '搜索运行中会话...',
        SidebarTab.archived => '搜索归档项目或会话...',
      };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final placeholder = _placeholderForTab(widget.activeTab);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: palette.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 11, right: 8),
              child: Icon(Icons.search, size: 16, color: palette.text3),
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: widget.onChanged,
                style: TextStyle(fontSize: 14, color: palette.text),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: placeholder,
                  hintStyle: TextStyle(fontSize: 14, color: palette.text3),
                ),
              ),
            ),
            if (_controller.text.isNotEmpty)
              IconButton(
                icon: Icon(Icons.clear, size: 16, color: palette.text3),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Conversations Tab: Recent conversations (with count badge & infinite scroll)
// ---------------------------------------------------------------------------

class _ConversationsTabView extends ConsumerStatefulWidget {
  const _ConversationsTabView();

  @override
  ConsumerState<_ConversationsTabView> createState() => _ConversationsTabViewState();
}

class _ConversationsTabViewState extends ConsumerState<_ConversationsTabView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= 200) {
      ref.read(recentSessionsStateProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final recentState = ref.watch(recentSessionsStateProvider).value;
    final filtered = ref.watch(filteredRecentSessionsProvider);
    final total = recentState?.total ?? filtered.length;
    final isLoadingMore = recentState?.isLoadingMore ?? false;

    if (filtered.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 100),
          _EmptyPlaceholder(
            icon: Icons.chat_bubble_outline_rounded,
            title: '没有匹配的对话',
            subtitle: '点击顶栏右上角「+」创建新会话',
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: filtered.length + 1 + (isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent conversations',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.text2,
                  ),
                ),
                Text(
                  '$total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: palette.text3,
                  ),
                ),
              ],
            ),
          );
        }

        if (index > filtered.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: palette.accent),
              ),
            ),
          );
        }

        final session = filtered[index - 1];
        return _RecentSessionRow(session: session);
      },
    );
  }
}

class _RecentSessionRow extends ConsumerWidget {
  const _RecentSessionRow({required this.session});

  final RecentSession session;

  void _showActionMenu(BuildContext context, WidgetRef ref) {
    SessionActionsSheet.show(
      context,
      sessionId: session.sessionId,
      title: session.displayTitle,
      provider: session.provider,
      projectId: session.projectId,
      projectDisplayName: session.projectDisplayName,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    // Amber "needs attention" dot, same semantics as the web sidebar: it shows
    // only while socket activity arrived for this session with the user not
    // looking at it, and opening the session clears it.
    final showAttentionDot = ref.watch(attentionSessionsProvider).contains(session.sessionId);

    return InkWell(
      onTap: () => _openChat(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            // Status Dot (fixed slot keeps rows aligned with or without it)
            SizedBox(
              width: 17,
              height: 7,
              child: showAttentionDot
                  ? Container(
                      decoration: BoxDecoration(
                        color: palette.warn,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
            // Provider Logo
            _ProviderLogoIcon(provider: session.provider, size: 28),
            const SizedBox(width: 11),
            // Title & Meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (session.projectDisplayName.isNotEmpty) ...[
                        Flexible(
                          child: Text(
                            session.projectDisplayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: palette.text3),
                          ),
                        ),
                        if (session.isProjectStarred) ...[
                          const SizedBox(width: 3),
                          Icon(Icons.star_rounded, size: 13, color: palette.warn),
                        ],
                        if (session.lastActivity != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            '· ${relativeTime(session.lastActivity!)}',
                            style: TextStyle(fontSize: 12, color: palette.text3),
                          ),
                        ],
                      ] else if (session.lastActivity != null) ...[
                        Text(
                          relativeTime(session.lastActivity!),
                          style: TextStyle(fontSize: 12, color: palette.text3),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Session star: marks this one conversation, unlike the project
            // star shown next to the project name.
            _SessionStarButton(session: session),
            // More actions (···)
            IconButton(
              icon: Icon(Icons.more_horiz_rounded, size: 20, color: palette.text3),
              onPressed: () => _showActionMenu(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _openChat(BuildContext context, WidgetRef ref) {
    ref.read(attentionSessionsProvider.notifier).clearAttention(session.sessionId);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          sessionId: session.sessionId,
          title: session.displayTitle,
          subtitle: session.projectDisplayName.isNotEmpty
              ? session.projectDisplayName
              : session.provider,
          provider: session.provider,
        ),
      ),
    ).then((_) {
      ref.read(homeRefreshProvider)();
    });
  }
}

/// The star a row shows and taps: it flips this conversation's own star, so
/// starring one row leaves its siblings alone.
class _SessionStarButton extends ConsumerWidget {
  const _SessionStarButton({required this.session});

  final RecentSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final isStarred = session.isStarred;
    return IconButton(
      icon: Icon(
        isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
        size: 19,
        color: isStarred ? palette.warn : palette.text3,
      ),
      tooltip: isStarred ? '取消加星' : '加星',
      onPressed: () {
        final messenger = ScaffoldMessenger.of(context);
        final notifier = ref.read(recentSessionsStateProvider.notifier);
        notifier.toggleSessionStar(session.sessionId);
        notifier.lastStarError.then((message) {
          if (message == null) return;
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        });
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Projects Tab: Projects list with star pinning & expandable sessions
// ---------------------------------------------------------------------------

class _ProjectsTabView extends ConsumerWidget {
  const _ProjectsTabView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final projects = ref.watch(visibleProjectsProvider);
    final expanded = ref.watch(expandedProjectsProvider);

    if (projects.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          _EmptyPlaceholder(
            icon: Icons.folder_open_rounded,
            title: '未找到项目',
            subtitle: '点击下方按钮快速添加新项目',
            actionText: '新建项目',
            onAction: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: palette.bgElevated,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const CreateProjectSheet(),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Projects',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.text2,
                ),
              ),
              Text(
                '${projects.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: palette.text3,
                ),
              ),
            ],
          ),
        ),
        for (final entry in projects)
          _ProjectGroup(
            entry: entry,
            expanded: expanded.contains(entry.project.projectId),
            onToggle: () => ref
                .read(expandedProjectsProvider.notifier)
                .toggle(entry.project.projectId),
          ),
      ],
    );
  }
}

class _ProjectGroup extends ConsumerWidget {
  const _ProjectGroup({
    required this.entry,
    required this.expanded,
    required this.onToggle,
  });

  final VisibleProject entry;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final project = entry.project;

    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 19, color: palette.text2),
                const SizedBox(width: 10),
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
                const SizedBox(width: 8),
                _StarButton(
                  isStarred: project.isStarred,
                  onTap: () => ref
                      .read(projectsProvider.notifier)
                      .toggleStar(project.projectId),
                ),
                IconButton(
                  icon: Icon(Icons.more_horiz_rounded, size: 18, color: palette.text3),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: '项目操作',
                  onPressed: () => ProjectActionsSheet.show(context, project: project),
                ),
                const SizedBox(width: 4),
                Text(
                  '${project.totalSessions}',
                  style: TextStyle(fontSize: 12, color: palette.text3),
                ),
                const SizedBox(width: 6),
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
              project: entry.project,
              indent: true,
            ),
      ],
    );
  }
}

class _StarButton extends ConsumerWidget {
  const _StarButton({required this.isStarred, required this.onTap});

  final bool isStarred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final messenger = ScaffoldMessenger.of(context);
        onTap();
        ref.read(projectsProvider.notifier).lastStarError.then((message) {
          if (message == null) return;
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        });
      },
      child: Icon(
        isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
        size: 19,
        color: isStarred ? palette.warn : palette.text3,
      ),
    );
  }
}

class _ProjectSessionTile extends ConsumerWidget {
  const _ProjectSessionTile({
    required this.session,
    required this.project,
    required this.indent,
  });

  final SessionSummary session;
  final ProjectSummary project;
  final bool indent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final showAttentionDot = ref.watch(attentionSessionsProvider).contains(session.id);
    return InkWell(
      onTap: () => _openChat(context, ref),
      child: Padding(
        padding: EdgeInsets.only(left: indent ? 44 : 16, right: 12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              if (showAttentionDot)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: palette.warn,
                    shape: BoxShape.circle,
                  ),
                ),
              _ProviderLogoIcon(provider: session.provider, size: 22),
              const SizedBox(width: 10),
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
                    const SizedBox(height: 2),
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
              IconButton(
                icon: Icon(Icons.more_horiz_rounded, size: 18, color: palette.text3),
                onPressed: () {
                  SessionActionsSheet.show(
                    context,
                    sessionId: session.id,
                    title: session.summary,
                    provider: session.provider,
                    projectId: project.projectId,
                    projectDisplayName: project.displayName,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openChat(BuildContext context, WidgetRef ref) {
    ref.read(attentionSessionsProvider.notifier).clearAttention(session.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          sessionId: session.id,
          title: session.summary,
          subtitle: session.provider,
          provider: session.provider,
        ),
      ),
    ).then((_) {
      ref.read(homeRefreshProvider)();
    });
  }
}

// ---------------------------------------------------------------------------
// Starred Tab: Starred sessions matching web sidebar's starred mode
// ---------------------------------------------------------------------------

class _StarredTabView extends ConsumerWidget {
  const _StarredTabView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final filtered = ref.watch(filteredStarredSessionsProvider);
    final total = ref.watch(starredSessionsCountProvider);
    final searchQuery = ref.watch(sessionSearchQueryProvider).trim();

    if (filtered.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          _EmptyPlaceholder(
            icon: Icons.star_outline_rounded,
            title: searchQuery.isNotEmpty ? '没有匹配的加星会话' : '暂无加星会话',
            subtitle: searchQuery.isNotEmpty
                ? '尝试更换搜索关键词'
                : '点击会话右侧的星标即可加星',
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: filtered.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Starred conversations',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.text2,
                  ),
                ),
                Text(
                  '$total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: palette.warn,
                  ),
                ),
              ],
            ),
          );
        }

        final session = filtered[index - 1];
        return _RecentSessionRow(session: session);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Running Sessions Tab
// ---------------------------------------------------------------------------

class _RunningSessionsTabView extends ConsumerWidget {
  const _RunningSessionsTabView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final runningAsync = ref.watch(runningSessionsProvider);

    return runningAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (e, _) => Center(
        child: Text('加载运行中会话失败: $e', style: TextStyle(color: palette.danger)),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 100),
              _EmptyPlaceholder(
                icon: Icons.show_chart_rounded,
                title: '当前没有正在运行的会话',
                subtitle: '当 AI 正在思考或调用工具时，会话将在这里集中展示',
              ),
            ],
          );
        }

        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: sessions.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Running now',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.text2,
                      ),
                    ),
                    Text(
                      '${sessions.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: palette.accent,
                      ),
                    ),
                  ],
                ),
              );
            }

            final item = sessions[index - 1];
            return InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatPage(
                      sessionId: item.sessionId,
                      title: '会话 #${item.sessionId.substring(0, item.sessionId.length.clamp(0, 8))}',
                      subtitle: item.provider,
                      provider: item.provider,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _ProviderLogoIcon(provider: item.provider, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.sessionId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: palette.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Provider: ${item.provider.toUpperCase()}',
                            style: TextStyle(fontSize: 11, color: palette.text3),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: palette.text3),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Archived Tab
// ---------------------------------------------------------------------------

class _ArchivedTabView extends ConsumerWidget {
  const _ArchivedTabView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final archivedProjectsAsync = ref.watch(archivedProjectsProvider);
    final archivedSessionsAsync = ref.watch(archivedSessionsProvider);

    final loading = archivedProjectsAsync.isLoading || archivedSessionsAsync.isLoading;
    if (loading) {
      return Center(
        child: CircularProgressIndicator(color: palette.accent),
      );
    }

    final projects = archivedProjectsAsync.value ?? const [];
    final sessions = archivedSessionsAsync.value ?? const [];

    if (projects.isEmpty && sessions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 100),
          _EmptyPlaceholder(
            icon: Icons.archive_outlined,
            title: '归档箱是空的',
            subtitle: '在网页版或设置中归档的项目与会话会显示在此处',
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (projects.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
            child: Text(
              '已归档项目 (${projects.length})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.text3),
            ),
          ),
          for (final proj in projects)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.line),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.folder_off_outlined, size: 20, color: palette.text3),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            proj.displayName.isEmpty ? proj.path : proj.displayName,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: palette.text),
                          ),
                          Text(proj.fullPath, style: TextStyle(fontSize: 11, color: palette.text3)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.restore_rounded, size: 18, color: palette.accent),
                      tooltip: '恢复项目',
                      onPressed: () async {
                        try {
                          await ProjectsApi(ref.read(apiClientProvider)).restoreProject(proj.projectId);
                          ref.invalidate(archivedProjectsProvider);
                          ref.read(projectsProvider.notifier).refresh();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已恢复项目: ${proj.displayName}')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('恢复失败: $e')),
                            );
                          }
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_forever_rounded, size: 18, color: palette.danger),
                      tooltip: '彻底删除',
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: palette.bgElevated,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: Text('彻底删除项目', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: palette.text)),
                            content: Text('确定要彻底删除此项目在应用中的所有记录吗？此操作无法撤销。', style: TextStyle(fontSize: 14, color: palette.text2)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: Text('取消', style: TextStyle(color: palette.text3)),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                style: FilledButton.styleFrom(backgroundColor: palette.danger),
                                child: const Text('彻底删除'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        try {
                          await ProjectsApi(ref.read(apiClientProvider)).deleteProject(proj.projectId, force: true);
                          ref.invalidate(archivedProjectsProvider);
                          ref.read(projectsProvider.notifier).refresh();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已彻底删除项目: ${proj.displayName}')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('删除失败: $e')),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (sessions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
            child: Text(
              '已归档会话 (${sessions.length})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.text3),
            ),
          ),
          for (final session in sessions)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.line),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChatPage(
                          sessionId: session.sessionId,
                          title: session.displayTitle,
                          subtitle: session.projectDisplayName.isNotEmpty
                              ? session.projectDisplayName
                              : session.provider,
                          provider: session.provider,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        _ProviderLogoIcon(provider: session.provider, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.displayTitle,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: palette.text),
                              ),
                              Text(
                                [
                                  if (session.projectDisplayName.isNotEmpty) session.projectDisplayName,
                                  if (session.lastActivity != null) relativeTime(session.lastActivity!),
                                ].join(' · '),
                                style: TextStyle(fontSize: 11, color: palette.text3),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.restore_rounded, size: 18, color: palette.accent),
                          tooltip: '恢复会话',
                          onPressed: () async {
                            try {
                              await SessionsApi(ref.read(apiClientProvider)).restoreSession(session.sessionId);
                              ref.invalidate(archivedSessionsProvider);
                              await ref.read(homeRefreshProvider)();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('已恢复会话: ${session.displayTitle}')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('恢复失败: $e')),
                                );
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_forever_rounded, size: 18, color: palette.danger),
                          tooltip: '彻底删除',
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: palette.bgElevated,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: Text('彻底删除会话', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: palette.text)),
                                content: Text('确定要彻底删除此会话吗？此操作无法撤销。', style: TextStyle(fontSize: 14, color: palette.text2)),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: Text('取消', style: TextStyle(color: palette.text3)),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    style: FilledButton.styleFrom(backgroundColor: palette.danger),
                                    child: const Text('彻底删除'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            try {
                              await SessionsApi(ref.read(apiClientProvider)).deleteSession(session.sessionId, hardDelete: true);
                              ref.invalidate(archivedSessionsProvider);
                              await ref.read(homeRefreshProvider)();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('已彻底删除会话: ${session.displayTitle}')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('删除失败: $e')),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Provider Logo / Icon Widget
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Client filter chips (Claude / Codex / Cursor / OpenCode) for the
// Conversations feed. Mirrors the web sidebar's provider filter bar: tapping
// the active chip again clears the filter back to "all clients".
// ---------------------------------------------------------------------------

class _ProviderFilterBar extends ConsumerWidget {
  const _ProviderFilterBar();

  static const _providers = ['claude', 'codex', 'cursor', 'opencode'];

  String _labelFor(String provider) => switch (provider) {
        'claude' => 'Claude Code',
        'codex' => 'Codex',
        'cursor' => 'Cursor',
        'opencode' => 'OpenCode',
        _ => provider,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final activeFilter = ref.watch(providerFilterProvider);
    final notifier = ref.read(providerFilterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (final provider in _providers) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => notifier.toggle(provider),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: activeFilter == provider
                      ? palette.bgElevated
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: activeFilter == provider
                        ? palette.accent.withValues(alpha: 0.45)
                        : palette.line,
                    width: activeFilter == provider ? 1.2 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ProviderLogoIcon(provider: provider, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      _labelFor(provider),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: activeFilter == provider
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: activeFilter == provider
                            ? palette.text
                            : palette.text3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (provider != _providers.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ProviderLogoIcon extends StatelessWidget {
  const _ProviderLogoIcon({required this.provider, this.size = 28});

  final String provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final normalized = provider.toLowerCase();

    IconData icon;
    Color iconColor;
    Color bg;

    if (normalized.contains('claude')) {
      icon = Icons.auto_awesome_rounded;
      iconColor = palette.claude;
      bg = palette.claude.withValues(alpha: 0.12);
    } else if (normalized.contains('codex') || normalized.contains('openai')) {
      icon = Icons.bubble_chart_rounded;
      iconColor = palette.codex;
      bg = palette.codex.withValues(alpha: 0.12);
    } else if (normalized.contains('cursor')) {
      icon = Icons.code_rounded;
      iconColor = palette.cursor;
      bg = palette.cursor.withValues(alpha: 0.12);
    } else {
      icon = Icons.terminal_rounded;
      iconColor = palette.text2;
      bg = palette.surface3;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: iconColor.withValues(alpha: 0.25), width: 0.8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.55, color: iconColor),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty and Error States
// ---------------------------------------------------------------------------

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionText,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: palette.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 24, color: palette.text3),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.4, color: palette.text3),
          ),
          if (actionText != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: palette.surface3,
                foregroundColor: palette.text,
              ),
              child: Text(actionText!),
            ),
          ],
        ],
      ),
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
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 110),
        Icon(Icons.cloud_off_outlined, size: 34, color: palette.danger),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: palette.text2),
          ),
        ),
        const SizedBox(height: 16),
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
