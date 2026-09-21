import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/api/sessions_api.dart';
import '../../core/models/project.dart';
import '../../core/providers.dart';
import '../chat/chat_page.dart';
import 'session_list_controller.dart';

/// Bottom sheet for creating a session: pick provider + project, optionally
/// type the first message, then land in the chat page.
class CreateSessionSheet extends ConsumerStatefulWidget {
  const CreateSessionSheet({super.key});

  @override
  ConsumerState<CreateSessionSheet> createState() => _CreateSessionSheetState();
}

class _CreateSessionSheetState extends ConsumerState<CreateSessionSheet> {
  static const _providers = [
    (id: 'claude', label: 'Claude'),
    (id: 'codex', label: 'Codex'),
    (id: 'cursor', label: 'Cursor'),
    (id: 'opencode', label: 'OpenCode'),
  ];

  final _messageController = TextEditingController();
  String _provider = 'claude';
  String? _projectId;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final projects = ref.read(projectsProvider).value ?? const <ProjectSummary>[];
    final project = projects.where((p) => p.projectId == _projectId).firstOrNull;
    if (project == null) {
      setState(() => _error = '请选择项目');
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final api = SessionsApi(ref.read(apiClientProvider));
      final created = await api.createSession(
        provider: _provider,
        projectPath: project.path,
        initialMessage: _messageController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(
            sessionId: created.sessionId,
            title: '新建会话',
            subtitle: project.displayName.isEmpty ? project.path : project.displayName,
            provider: _provider,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final projectsAsync = ref.watch(projectsProvider);
    final projects = projectsAsync.value ?? const <ProjectSummary>[];
    final selectedProject = projects.where((p) => p.projectId == _projectId).firstOrNull;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.line2,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '新建会话',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '选择模型类型和工作目录，首条消息可以稍后再说',
              style: TextStyle(fontSize: 13, color: palette.text3),
            ),
            const SizedBox(height: 16),

            // Provider chips.
            Text('模型类型', style: TextStyle(fontSize: 12.5, color: palette.text3)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final provider in _providers)
                  _ChoiceChip(
                    label: provider.label,
                    selected: _provider == provider.id,
                    palette: palette,
                    onTap: () => setState(() => _provider = provider.id),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Project picker.
            Text('工作目录', style: TextStyle(fontSize: 12.5, color: palette.text3)),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: palette.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.line),
              ),
              child: projects.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        projectsAsync.isLoading ? '加载中…' : '没有可用的项目',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: palette.text3),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: projects.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: palette.line.withValues(alpha: 0.5),
                      ),
                      itemBuilder: (context, index) {
                        final project = projects[index];
                        final selected = project.projectId == _projectId;
                        return InkWell(
                          onTap: () => setState(() => _projectId = project.projectId),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Icon(
                                  selected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  size: 17,
                                  color: selected ? palette.accent : palette.text3,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        project.displayName.isEmpty
                                            ? project.path
                                            : project.displayName,
                                        style: TextStyle(fontSize: 14, color: palette.text),
                                      ),
                                      Text(
                                        project.path,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 11.5, color: palette.text3),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 16),

            // First message (optional).
            TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 3,
              style: TextStyle(fontSize: 14, color: palette.text),
              decoration: InputDecoration(
                hintText: '首条消息（可选）',
                hintStyle: TextStyle(fontSize: 14, color: palette.text3),
                filled: true,
                fillColor: palette.surface2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: palette.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: palette.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: palette.accent, width: 1.4),
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(fontSize: 12.5, color: palette.danger),
              ),
            ],

            const SizedBox(height: 18),

            // Create button.
            SizedBox(
              height: 46,
              child: FilledButton(
                onPressed: _creating ? null : _create,
                style: FilledButton.styleFrom(
                  backgroundColor: selectedProject == null ? palette.surface3 : null,
                  disabledBackgroundColor: palette.surface3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _creating
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.text2,
                        ),
                      )
                    : Text(
                        '创建并进入会话',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? palette.accentSoft : palette.surface2,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? palette.accent : palette.line,
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? palette.accent : palette.text2,
          ),
        ),
      ),
    );
  }
}