import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import 'session_list_controller.dart';

/// Bottom sheet for creating a project: input path and optional custom name.
class CreateProjectSheet extends ConsumerStatefulWidget {
  const CreateProjectSheet({super.key});

  @override
  ConsumerState<CreateProjectSheet> createState() => _CreateProjectSheetState();
}

class _CreateProjectSheetState extends ConsumerState<CreateProjectSheet> {
  final _pathController = TextEditingController();
  final _nameController = TextEditingController();
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _pathController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      setState(() => _error = '请输入项目路径');
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final name = _nameController.text.trim();
      final project = await ref.read(projectsProvider.notifier).createProject(
            path: path,
            customName: name.isEmpty ? null : name,
          );
      if (!mounted) return;
      ref.read(sidebarTabProvider.notifier).selectTab(SidebarTab.projects);
      ref.read(expandedProjectsProvider.notifier).toggle(project.projectId);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已创建项目: ${project.displayName.isEmpty ? project.path : project.displayName}')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '新建项目',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: palette.text3, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '项目路径',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.text2,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.line),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _pathController,
                  autofocus: true,
                  style: TextStyle(fontSize: 14, color: palette.text),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '/path/to/your/project',
                    hintStyle: TextStyle(fontSize: 14, color: palette.text3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '项目显示名称（可选）',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.text2,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.line),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _nameController,
                  style: TextStyle(fontSize: 14, color: palette.text),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '默认为目录名称',
                    hintStyle: TextStyle(fontSize: 14, color: palette.text3),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12.5, color: palette.danger),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _creating ? null : _create,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _creating
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '创建项目',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
