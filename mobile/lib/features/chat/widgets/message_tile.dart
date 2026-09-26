import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/providers.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/ws/server_event.dart';
import '../chat_reducer.dart';
import '../utils/diff_helper.dart';
import 'markdown_view.dart';
import 'message_actions_sheet.dart';

class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.message,
    this.streaming = false,
    this.onEditUserMessage,
    this.onForkSession,
  });

  final ChatMessage message;
  final bool streaming;
  final ValueChanged<String>? onEditUserMessage;
  final ValueChanged<String>? onForkSession;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (message.isUser) {
      return _UserBubble(
        message: message,
        onEdit: onEditUserMessage,
        onFork: onForkSession,
      );
    }
    switch (message.kind) {
      case ServerEventKind.thinking:
        return _ThinkingCard(message: message);
      case ServerEventKind.toolUse:
      case ServerEventKind.toolResult:
        return _ToolCard(message: message);
      case ServerEventKind.error:
        return _ErrorRow(message: message);
      default:
        return _AssistantBubble(
          message: message,
          streaming: streaming,
          onFork: onForkSession,
        );
    }
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.message,
    required this.streaming,
    this.onFork,
  });

  final ChatMessage message;
  final bool streaming;
  final ValueChanged<String>? onFork;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        final content = message.content ?? '';
        if (content.trim().isEmpty) return;
        MessageActionsSheet.show(
          context,
          content: content,
          isUser: false,
          messageId: message.id,
          onFork: onFork,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: MarkdownView(message.content ?? '', streaming: streaming),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({
    required this.message,
    this.onEdit,
    this.onFork,
  });

  final ChatMessage message;
  final ValueChanged<String>? onEdit;
  final ValueChanged<String>? onFork;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onLongPress: () {
          final content = message.content ?? '';
          if (content.trim().isEmpty && message.imagePaths.isEmpty) return;
          MessageActionsSheet.show(
            context,
            content: content,
            isUser: true,
            messageId: message.id,
            onEdit: onEdit,
            onFork: onFork,
          );
        },
        child: Container(
          margin: const EdgeInsets.only(left: 42, top: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [palette.userBubble1, palette.userBubble2],
            ),
            border: Border.all(color: palette.accent.withValues(alpha: 0.26)),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (message.imagePaths.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final path in message.imagePaths) _HistoryImage(path: path),
                    ],
                  ),
                ),
              if (message.content != null && message.content!.isNotEmpty)
                Text(
                  message.content!,
                  style: TextStyle(
                    fontSize: AppTextSizes.message,
                    height: 1.5,
                    color: palette.userBubbleText,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One image attached to a historical user message, loaded from the server's
/// asset endpoint (path = stored filename).
class _HistoryImage extends StatelessWidget {
  const _HistoryImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final client = ProviderScope.containerOf(context).read(apiClientProvider);
    final base = client.serverUrl ?? '';
    final filename = path.split('/').last;
    final url = '$base/api/assets/images/$filename';
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: 140,
        fit: BoxFit.cover,
        headers: {
          'Authorization': 'Bearer ${client.token ?? ''}',
        },
        loadingBuilder: (context, child, progress) => SizedBox(
          width: 140,
          height: 100,
          child: progress == null
              ? child
              : Center(child: CircularProgressIndicator(strokeWidth: 2, color: palette.accent)),
        ),
        errorBuilder: (_, _, _) => SizedBox(
          width: 140,
          height: 80,
          child: Icon(Icons.broken_image_outlined, size: 20, color: palette.text3),
        ),
      ),
    );
  }
}

class _ThinkingCard extends StatelessWidget {
  const _ThinkingCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return _Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          iconColor: palette.text3,
          collapsedIconColor: palette.text3,
          title: Text(
            '思考过程',
            style: TextStyle(fontSize: 13, color: palette.text2),
          ),
          subtitle: Text(
            (message.content ?? '').trim().split('\n').first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: palette.text3),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                message.content ?? '',
                style: TextStyle(fontSize: 13.5, height: 1.55, color: palette.text2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Upgraded expandable ToolCard with Bash commands, output preview, and unified Diff views.
class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.message});

  final ChatMessage message;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _expanded = false;

  Map<dynamic, dynamic>? _parseMap(dynamic input) {
    if (input is Map) return input;
    if (input is String && input.trimLeft().startsWith('{')) {
      try {
        final decoded = jsonDecode(input);
        if (decoded is Map) return decoded;
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final message = widget.message;
    final done = message.toolResultContent != null || message.kind == ServerEventKind.toolResult;
    final map = _parseMap(message.toolInput);

    return _Card(
      borderColor: message.isError ? palette.danger.withValues(alpha: 0.45) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row (tap to expand/collapse)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: palette.surface3,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _iconFor(message.toolName),
                      size: 13,
                      color: message.isError ? palette.danger : palette.text2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.toolName ?? 'Tool',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontFamily: 'monospace',
                            color: palette.toolNameText,
                          ),
                        ),
                        if (message.toolSummary.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            message.toolSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: palette.text2),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!done)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: palette.accent),
                    )
                  else
                    Icon(
                      message.isError ? Icons.error_outline : Icons.check,
                      size: 14,
                      color: message.isError ? palette.danger : palette.ok,
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: palette.text3,
                  ),
                ],
              ),
            ),
          ),

          // Expanded detail view
          if (_expanded) ...[
            Divider(height: 1, color: palette.line),
            Padding(
              padding: const EdgeInsets.all(10),
              child: _buildExpandedContent(context, map),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context, Map<dynamic, dynamic>? map) {
    final toolName = widget.message.toolName ?? '';
    final isBash = toolName == 'Bash' || toolName.toLowerCase() == 'bash';

    // Check for Edit / Write / Diff
    final isEditOrWrite = toolName == 'Edit' ||
        toolName == 'Write' ||
        toolName == 'MultiEdit' ||
        (map != null && (map.containsKey('old_string') || map.containsKey('TargetContent')));

    if (isBash) {
      return _buildBashView(context, map);
    } else if (isEditOrWrite && map != null) {
      return _buildDiffOrFileView(context, map);
    } else {
      return _buildGenericToolView(context, map);
    }
  }

  Widget _buildBashView(BuildContext context, Map<dynamic, dynamic>? map) {
    final palette = AppPalette.of(context);
    final command = (map?['command'] ?? map?['cmd'] ?? widget.message.toolSummary) as String? ?? '';
    final output = widget.message.toolResultContent ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (command.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '执行命令',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.text3),
              ),
              _CopyIconButton(text: command, label: '命令'),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: palette.codeBlockBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.line),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    '\$ ',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: palette.accent,
                    ),
                  ),
                  Text(
                    command,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: palette.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (output.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.message.isError ? '执行输出 (错误)' : '执行输出',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: widget.message.isError ? palette.danger : palette.text3,
                ),
              ),
              _CopyIconButton(text: output, label: '输出'),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.codeBlockBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.message.isError ? palette.danger.withValues(alpha: 0.4) : palette.line,
              ),
            ),
            child: SingleChildScrollView(
              child: Text(
                output,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.45,
                  color: widget.message.isError ? palette.errorText : palette.text2,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDiffOrFileView(BuildContext context, Map<dynamic, dynamic> map) {
    final palette = AppPalette.of(context);
    final filePath = (map['file_path'] ?? map['TargetFile'] ?? map['path'] ?? '') as String;
    final oldStr = (map['old_string'] ?? map['TargetContent'] ?? '') as String;
    final newStr = (map['new_string'] ?? map['ReplacementContent'] ?? map['content'] ?? map['CodeContent'] ?? '') as String;
    final isDark = palette.brightness == Brightness.dark;
    final resultOutput = widget.message.toolResultContent ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // File path and badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: palette.surface2,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: palette.line),
          ),
          child: Row(
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 14, color: palette.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  filePath.isEmpty ? '文件修改' : filePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                    color: palette.text,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0x333B82F6) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Diff',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Diff lines viewer
        Container(
          constraints: const BoxConstraints(maxHeight: 240),
          decoration: BoxDecoration(
            color: palette.codeBlockBg,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
            border: Border(
              left: BorderSide(color: palette.line),
              right: BorderSide(color: palette.line),
              bottom: BorderSide(color: palette.line),
            ),
          ),
          child: SingleChildScrollView(
            child: _buildDiffLines(context, oldStr, newStr),
          ),
        ),

        if (resultOutput.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            resultOutput,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: palette.text3),
          ),
        ],
      ],
    );
  }

  Widget _buildDiffLines(BuildContext context, String oldStr, String newStr) {
    final palette = AppPalette.of(context);
    final isDark = palette.brightness == Brightness.dark;
    final diffLines = computeDiffLines(oldStr, newStr);

    if (diffLines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Text('无内容改动', style: TextStyle(fontSize: 12, color: palette.text3)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in diffLines)
          Container(
            color: line.type == DiffLineType.added
                ? (isDark ? const Color(0x2816A34A) : const Color(0x2822C55E))
                : line.type == DiffLineType.removed
                    ? (isDark ? const Color(0x28DC2626) : const Color(0x28EF4444))
                    : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 16,
                  child: Text(
                    line.type == DiffLineType.added
                        ? '+'
                        : line.type == DiffLineType.removed
                            ? '-'
                            : ' ',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: line.type == DiffLineType.added
                          ? palette.ok
                          : line.type == DiffLineType.removed
                              ? palette.danger
                              : palette.text3,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    line.text,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: line.type == DiffLineType.added
                          ? (isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D))
                          : line.type == DiffLineType.removed
                              ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C))
                              : palette.text2,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildGenericToolView(BuildContext context, Map<dynamic, dynamic>? map) {
    final palette = AppPalette.of(context);
    final rawInput = widget.message.toolInput;
    String inputStr = '';
    if (rawInput != null) {
      if (rawInput is String) {
        inputStr = rawInput;
      } else {
        try {
          inputStr = const JsonEncoder.withIndent('  ').convert(rawInput);
        } catch (_) {
          inputStr = '$rawInput';
        }
      }
    }
    final output = widget.message.toolResultContent ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (inputStr.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '输入参数',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.text3),
              ),
              _CopyIconButton(text: inputStr, label: '参数'),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: palette.codeBlockBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.line),
            ),
            child: SingleChildScrollView(
              child: Text(
                inputStr,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  color: palette.text2,
                ),
              ),
            ),
          ),
        ],
        if (output.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.message.isError ? '结果 (错误)' : '执行结果',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: widget.message.isError ? palette.danger : palette.text3,
                ),
              ),
              _CopyIconButton(text: output, label: '结果'),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: palette.codeBlockBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.line),
            ),
            child: SingleChildScrollView(
              child: Text(
                output,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  color: widget.message.isError ? palette.errorText : palette.text2,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  IconData _iconFor(String? toolName) {
    switch (toolName) {
      case 'Read':
      case 'Edit':
      case 'Write':
      case 'MultiEdit':
        return Icons.description_outlined;
      case 'Bash':
        return Icons.terminal;
      case 'Grep':
      case 'Glob':
        return Icons.search;
      case 'WebFetch':
      case 'WebSearch':
        return Icons.public;
      case 'Task':
      case 'Agent':
        return Icons.account_tree_outlined;
      default:
        return Icons.build_outlined;
    }
  }
}

class _CopyIconButton extends StatelessWidget {
  const _CopyIconButton({required this.text, required this.label});

  final String text;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$label 已复制到剪贴板'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy_rounded, size: 12, color: palette.text3),
            const SizedBox(width: 4),
            Text(
              '复制',
              style: TextStyle(fontSize: 11, color: palette.text3),
            ),
          ],
        ),
      ),
    );
  }
}


class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return _Card(
      borderColor: palette.danger.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 15, color: palette.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message.content ?? '出错了',
                style: TextStyle(fontSize: 13.5, height: 1.5, color: palette.errorText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.borderColor});

  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: borderColor ?? palette.line),
      ),
      child: child,
    );
  }
}

/// Pending permission prompt rendered at the end of the transcript.
class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.permission,
    required this.onAnswer,
  });

  final PendingPermission permission;
  final void Function(bool allow, bool remember) onAnswer;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final command = _commandPreview(permission.input);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: palette.warn.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 8),
            child: Row(
              children: [
                Icon(Icons.warning_amber_outlined, size: 16, color: palette.warn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '请求执行 · ${permission.toolName}',
                    style: TextStyle(fontSize: 13.5, color: palette.permissionText),
                  ),
                ),
              ],
            ),
          ),
          if (command.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: palette.codeBlockBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.line),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  command,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    color: palette.text,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: _PermButton(label: '允许一次', color: palette.ok, onTap: () => onAnswer(true, false)),
                ),
                const SizedBox(width: 8),
                Expanded(child: _PermButton(label: '始终允许', onTap: () => onAnswer(true, true))),
                const SizedBox(width: 8),
                Expanded(child: _PermButton(label: '拒绝', color: palette.danger, onTap: () => onAnswer(false, false))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _commandPreview(dynamic input) {
    var parsed = input;
    if (input is String) {
      try {
        parsed = jsonDecode(input);
      } catch (_) {
        return input;
      }
    }
    if (parsed is Map) {
      for (final key in const ['command', 'file_path', 'path', 'pattern', 'url']) {
        final value = parsed[key];
        if (value is String && value.isNotEmpty) return value;
      }
      return const JsonEncoder.withIndent('  ').convert(parsed);
    }
    return '$parsed';
  }
}

class _PermButton extends StatelessWidget {
  const _PermButton({required this.label, required this.onTap, this.color});

  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tint = color ?? palette.text;
    return SizedBox(
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color?.withValues(alpha: 0.12) ?? palette.surface2,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: color?.withValues(alpha: 0.35) ?? palette.line2),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: tint,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
