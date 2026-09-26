import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/api/projects_api.dart';
import '../../core/models/project.dart';
import '../../core/providers.dart';
import '../workspace/web_embed_page.dart';
import 'session_list_controller.dart';

/// Actions sheet for a project:
/// - Header: Project Name + Full Path
/// - Rename project
/// - Open in Workspace (Files / Git)
/// - Copy project path
/// - Archive or delete project (danger red)
class ProjectActionsSheet extends ConsumerStatefulWidget {
  const ProjectActionsSheet({
    super.key,
    required this.project,
  });

  final ProjectSummary project;

  static Future<void> show(
    BuildContext context, {
    required ProjectSummary project,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppPalette.of(context).bgElevated,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => ProjectActionsSheet(project: project),
      );

  @override
  ConsumerState<ProjectActionsSheet> createState() => _ProjectActionsSheetState();
}

class _ProjectActionsSheetState extends ConsumerState<ProjectActionsSheet> {
  Future<void> _handleRename() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final controller = TextEditingController(text: widget.project.displayName);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return AlertDialog(
          backgroundColor: palette.bgElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '重命名项目',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: palette.text),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(fontSize: 14, color: palette.text),
            decoration: InputDecoration(
              hintText: '输入新项目名称',
              hintStyle: TextStyle(color: palette.text3),
              filled: true,
              fillColor: palette.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('取消', style: TextStyle(color: palette.text3)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: palette.accent),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (newName == null || newName.isEmpty || newName == widget.project.displayName) return;

    nav.pop();

    try {
      final api = ProjectsApi(ref.read(apiClientProvider));
      await api.renameProject(widget.project.projectId, newName);
      ref.read(projectsProvider.notifier).refresh();
      await ref.read(homeRefreshProvider)();
      messenger.showSnackBar(
        const SnackBar(content: Text('已重命名项目')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('重命名项目失败: $e')),
      );
    }
  }

  Future<void> _handleCopyPath() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    await Clipboard.setData(ClipboardData(text: widget.project.fullPath));
    nav.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('已复制项目路径: ${widget.project.fullPath}')),
    );
  }

  Future<void> _handleOpenWorkspace() async {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const WebEmbedPage(
          title: '文件管理',
          tab: 'files',
        ),
      ),
    );
  }

  Future<void> _handleDeleteOrArchive() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return AlertDialog(
          backgroundColor: palette.bgElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '归档或删除项目',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: palette.text),
          ),
          content: Text(
            '您可以将该项目归档（随时可在归档箱恢复），或彻底删除该项目在应用中的记录。',
            style: TextStyle(fontSize: 14, height: 1.45, color: palette.text2),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: Text('取消', style: TextStyle(color: palette.text3)),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(ctx).pop('archive'),
              icon: Icon(Icons.archive_outlined, size: 16, color: palette.text),
              label: Text('归档项目', style: TextStyle(color: palette.text)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: palette.line)),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop('delete'),
              icon: const Icon(Icons.delete_forever_rounded, size: 16),
              label: const Text('彻底删除'),
              style: FilledButton.styleFrom(backgroundColor: palette.danger),
            ),
          ],
        );
      },
    );

    if (action == null || action == 'cancel') return;

    nav.pop();

    try {
      final api = ProjectsApi(ref.read(apiClientProvider));
      final isHardDelete = action == 'delete';
      await api.deleteProject(widget.project.projectId, force: isHardDelete);
      ref.read(projectsProvider.notifier).refresh();
      ref.invalidate(archivedProjectsProvider);
      await ref.read(homeRefreshProvider)();
      messenger.showSnackBar(
        SnackBar(content: Text(isHardDelete ? '已彻底删除项目' : '已归档项目')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: palette.text3.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header: Project Name & Full Path
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: palette.surface2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.folder_outlined, size: 20, color: palette.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.project.displayName.isEmpty ? widget.project.path : widget.project.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: palette.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.project.fullPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: palette.text3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: 16, color: palette.line),

            // Item 1: Rename Project
            ListTile(
              leading: Icon(Icons.edit_outlined, size: 20, color: palette.text),
              title: Text('重命名项目', style: TextStyle(fontSize: 14.5, color: palette.text)),
              onTap: _handleRename,
            ),

            // Item 2: Open Workspace
            ListTile(
              leading: Icon(Icons.dvr_outlined, size: 20, color: palette.text),
              title: Text('在工作区查看文件与 Git', style: TextStyle(fontSize: 14.5, color: palette.text)),
              onTap: _handleOpenWorkspace,
            ),

            // Item 3: Copy Path
            ListTile(
              leading: Icon(Icons.copy_rounded, size: 20, color: palette.text),
              title: Text('复制项目路径', style: TextStyle(fontSize: 14.5, color: palette.text)),
              onTap: _handleCopyPath,
            ),

            Divider(height: 16, color: palette.line),

            // Item 4: Archive or delete (danger)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, size: 20, color: palette.danger),
              title: Text(
                '归档或删除项目',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: palette.danger),
              ),
              onTap: _handleDeleteOrArchive,
            ),
          ],
        ),
      ),
    );
  }
}
