import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/api/sessions_api.dart';
import '../../core/providers.dart';
import '../chat/chat_page.dart';
import 'session_list_controller.dart';

/// Actions sheet mirroring web's SessionOptions menu (media_1790006651776.png):
/// - Header: Session Title + Provider session subtitle
/// - Rename session
/// - Copy provider session ID
/// - Fork session (Continue from a copy, leaving this one untouched.)
/// - Archive or delete session (in red danger style)
class SessionActionsSheet extends ConsumerStatefulWidget {
  const SessionActionsSheet({
    super.key,
    required this.sessionId,
    required this.title,
    required this.provider,
    this.projectId,
    this.projectDisplayName,
  });

  final String sessionId;
  final String title;
  final String provider;
  final String? projectId;
  final String? projectDisplayName;

  static Future<void> show(
    BuildContext context, {
    required String sessionId,
    required String title,
    required String provider,
    String? projectId,
    String? projectDisplayName,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppPalette.of(context).bgElevated,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => SessionActionsSheet(
          sessionId: sessionId,
          title: title,
          provider: provider,
          projectId: projectId,
          projectDisplayName: projectDisplayName,
        ),
      );

  @override
  ConsumerState<SessionActionsSheet> createState() => _SessionActionsSheetState();
}

class _SessionActionsSheetState extends ConsumerState<SessionActionsSheet> {
  bool _operating = false;

  String get _providerLabel {
    final p = widget.provider.toLowerCase();
    if (p.contains('claude')) return 'Claude';
    if (p.contains('codex')) return 'Codex';
    if (p.contains('openai')) return 'OpenAI';
    if (p.contains('cursor')) return 'Cursor';
    if (p.contains('opencode')) return 'OpenCode';
    return widget.provider.isEmpty ? 'AI' : widget.provider;
  }

  Future<void> _handleRename() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final controller = TextEditingController(text: widget.title);

    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return AlertDialog(
          backgroundColor: palette.bgElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '重命名会话',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: palette.text),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(fontSize: 14, color: palette.text),
            decoration: InputDecoration(
              hintText: '输入新会话名称',
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

    if (newTitle == null || newTitle.isEmpty || newTitle == widget.title) return;

    nav.pop();

    try {
      final api = SessionsApi(ref.read(apiClientProvider));
      await api.renameSession(widget.sessionId, newTitle);
      await ref.read(homeRefreshProvider)();
      messenger.showSnackBar(
        const SnackBar(content: Text('已重命名会话')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('重命名失败: $e')),
      );
    }
  }

  Future<void> _handleCopySessionId() async {
    setState(() => _operating = true);
    try {
      final api = SessionsApi(ref.read(apiClientProvider));
      final idToCopy = await api.getProviderSessionId(widget.sessionId);
      await Clipboard.setData(ClipboardData(text: idToCopy));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 $_providerLabel 会话 ID: $idToCopy')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('复制失败: $e')),
      );
    }
  }

  Future<void> _handleForkSession() async {
    setState(() => _operating = true);
    try {
      final api = SessionsApi(ref.read(apiClientProvider));
      final forked = await api.forkSession(widget.sessionId);
      await ref.read(homeRefreshProvider)();
      if (!mounted) return;
      Navigator.of(context).pop();
      // Navigate straight into the newly forked session
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(
            sessionId: forked.sessionId,
            title: '${widget.title} (fork)',
            subtitle: widget.projectDisplayName ?? widget.provider,
            provider: widget.provider,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _operating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分叉会话失败: $e')),
      );
    }
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
            '归档或删除会话',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: palette.text),
          ),
          content: Text(
            '您可以将该会话归档（可随时在归档箱中恢复），或彻底删除此会话记录。',
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
              label: Text('归档会话', style: TextStyle(color: palette.text)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: palette.line),
              ),
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
      final api = SessionsApi(ref.read(apiClientProvider));
      final isHardDelete = action == 'delete';
      await api.deleteSession(widget.sessionId, hardDelete: isHardDelete);
      await ref.read(homeRefreshProvider)();
      messenger.showSnackBar(
        SnackBar(content: Text(isHardDelete ? '已彻底删除会话' : '已归档会话')),
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
            // Header (Figure matching media_1790006651776.png)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title.isEmpty ? '(未命名会话)' : widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_providerLabel session',
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.text3,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.line),
            const SizedBox(height: 4),

            // Item 1: Rename session
            ListTile(
              leading: Icon(Icons.edit_outlined, size: 20, color: palette.text2),
              title: Text(
                'Rename session',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: palette.text),
              ),
              onTap: _operating ? null : _handleRename,
            ),

            // Item 2: Copy provider session ID
            ListTile(
              leading: Icon(Icons.copy_rounded, size: 20, color: palette.text2),
              title: Text(
                'Copy $_providerLabel session ID',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: palette.text),
              ),
              trailing: _operating
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: palette.accent),
                    )
                  : null,
              onTap: _operating ? null : _handleCopySessionId,
            ),

            // Item 3: Fork session
            ListTile(
              leading: Icon(Icons.alt_route_rounded, size: 20, color: palette.text2),
              title: Text(
                'Fork session',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: palette.text),
              ),
              subtitle: Text(
                'Continue from a copy, leaving this one untouched.',
                style: TextStyle(fontSize: 12, color: palette.text3),
              ),
              trailing: _operating
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: palette.accent),
                    )
                  : null,
              onTap: _operating ? null : _handleForkSession,
            ),

            // Session star. Only offered when the conversation is in the recent
            // list, which is where its own star state is known; the project row
            // below stars the whole project instead.
            Consumer(
              builder: (context, ref, _) {
                final sessions = ref.watch(recentSessionsWithStarProvider);
                final index = sessions.indexWhere((s) => s.sessionId == widget.sessionId);
                if (index == -1) return const SizedBox.shrink();
                final isStarred = sessions[index].isStarred;
                return ListTile(
                  leading: Icon(
                    isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 20,
                    color: isStarred ? palette.warn : palette.text2,
                  ),
                  title: Text(
                    isStarred ? '取消会话加星' : '为会话加星',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: palette.text,
                    ),
                  ),
                  subtitle: Text(
                    '仅标记此会话',
                    style: TextStyle(fontSize: 12, color: palette.text3),
                  ),
                  onTap: _operating
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final notifier = ref.read(recentSessionsStateProvider.notifier);
                          Navigator.of(context).pop();
                          notifier.toggleSessionStar(widget.sessionId);
                          final message = await notifier.lastStarError;
                          if (message == null) return;
                          messenger
                            ..hideCurrentSnackBar()
                            ..showSnackBar(SnackBar(content: Text(message)));
                        },
                );
              },
            ),

            if (widget.projectId != null && widget.projectId!.isNotEmpty) ...[
              Consumer(
                builder: (context, ref, _) {
                  final projects = ref.watch(projectsProvider).value ?? const [];
                  final isStarred = projects.any(
                    (p) => p.projectId == widget.projectId && p.isStarred,
                  );
                  return ListTile(
                    leading: Icon(
                      isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 20,
                      color: isStarred ? palette.warn : palette.text2,
                    ),
                    title: Text(
                      isStarred ? '取消项目加星' : '为项目加星',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: palette.text,
                      ),
                    ),
                    subtitle: widget.projectDisplayName != null && widget.projectDisplayName!.isNotEmpty
                        ? Text(
                            widget.projectDisplayName!,
                            style: TextStyle(fontSize: 12, color: palette.text3),
                          )
                        : null,
                    onTap: _operating
                        ? null
                        : () async {
                            Navigator.of(context).pop();
                            await ref
                                .read(projectsProvider.notifier)
                                .toggleStar(widget.projectId!);
                          },
                  );
                },
              ),
            ],

            Divider(height: 16, color: palette.line),

            // Item 4: Archive or delete session (danger)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, size: 20, color: palette.danger),
              title: Text(
                '归档或删除会话',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: palette.danger,
                ),
              ),
              onTap: _operating ? null : _handleDeleteOrArchive,
            ),
          ],
        ),
      ),
    );
  }
}
