import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import 'web_embed_page.dart';

/// Workspace entries are WebView fallbacks (M5). Each card will open the web UI
/// on the matching tab by presetting `localStorage['activeTab']`.
class WorkspacePage extends StatelessWidget {
  const WorkspacePage({super.key});

  static const _entries = <_WorkspaceEntry>[
    (
      icon: Icons.terminal,
      title: '终端',
      subtitle: '真 PTY，完整网页版',
      tab: 'shell',
    ),
    (
      icon: Icons.folder_outlined,
      title: '文件',
      subtitle: '文件树、查看、编辑',
      tab: 'files',
    ),
    (
      icon: Icons.account_tree_outlined,
      title: 'Git 与 Worktree',
      subtitle: '改动、提交、分支、worktree',
      tab: 'git',
    ),
    (
      icon: Icons.checklist,
      title: 'Task Master',
      subtitle: 'PRD 解析、任务列表',
      tab: 'tasks',
    ),
    (
      icon: Icons.public,
      title: '浏览器',
      subtitle: 'browser-use 会话',
      tab: 'browser',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(18, 6, 18, 12),
              child: Text(
                '工作区',
                style: TextStyle(
                  fontSize: AppTextSizes.pageTitle,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
            ),
            for (final entry in _entries)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 11),
                child: _WorkspaceCard(
                  entry: entry,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WebEmbedPage(
                        title: entry.title,
                        tab: entry.tab,
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 2, 16, 26),
              child: Text(
                '这些功能直接内嵌现有网页版：打开时自动带上登录态，并直接落到对应页面。'
                '用下来最常用的还是聊天，所以先把聊天做成原生。',
                style: TextStyle(fontSize: 12.5, height: 1.75, color: palette.text3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _WorkspaceEntry = ({IconData icon, String title, String subtitle, String tab});

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({required this.entry, required this.onTap});

  final _WorkspaceEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: palette.line),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.surface3,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(entry.icon, size: 19, color: palette.text2),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.title,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: palette.text,
                          ),
                        ),
                        SizedBox(width: 6),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            border: Border.all(color: palette.line),
                          ),
                          child: Text(
                            '网页模式',
                            style: TextStyle(fontSize: 10.5, color: Color(0xFFC9D3E6)),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 3),
                    Text(
                      entry.subtitle,
                      style: TextStyle(fontSize: 12.5, color: palette.text3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.text3),
            ],
          ),
        ),
      ),
    );
  }
}
