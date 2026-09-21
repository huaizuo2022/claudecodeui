import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/ws/server_event.dart';
import '../chat_reducer.dart';
import 'markdown_view.dart';

class MessageTile extends StatelessWidget {
  const MessageTile({super.key, required this.message, this.streaming = false});

  final ChatMessage message;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) return _UserBubble(message: message);
    switch (message.kind) {
      case ServerEventKind.thinking:
        return _ThinkingCard(message: message);
      case ServerEventKind.toolUse:
      case ServerEventKind.toolResult:
        return _ToolCard(message: message);
      case ServerEventKind.error:
        return _ErrorRow(message: message);
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: MarkdownView(message.content ?? '', streaming: streaming),
        );
    }
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 42, top: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A3452), Color(0xFF232B45)],
          ),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.26)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: Text(
          message.content ?? '',
          style: const TextStyle(fontSize: AppTextSizes.message, height: 1.5, color: Color(0xFFEAEFFA)),
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
    return _Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          iconColor: AppColors.text3,
          collapsedIconColor: AppColors.text3,
          title: const Text(
            '思考过程',
            style: TextStyle(fontSize: 13, color: AppColors.text2),
          ),
          subtitle: Text(
            (message.content ?? '').trim().split('\n').first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.text3),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                message.content ?? '',
                style: const TextStyle(fontSize: 13.5, height: 1.55, color: AppColors.text2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final done = message.toolResultContent != null || message.kind == ServerEventKind.toolResult;
    return _Card(
      borderColor: message.isError ? AppColors.danger.withValues(alpha: 0.45) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _iconFor(message.toolName),
                size: 13,
                color: message.isError ? AppColors.danger : AppColors.text2,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.toolName ?? 'Tool',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                      color: Color(0xFFC9D4E6),
                    ),
                  ),
                  if (message.toolSummary.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      message.toolSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.text2),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!done)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.accent),
              )
            else
              Icon(
                message.isError ? Icons.error_outline : Icons.check,
                size: 14,
                color: message.isError ? AppColors.danger : AppColors.ok,
              ),
          ],
        ),
      ),
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

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return _Card(
      borderColor: AppColors.danger.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 15, color: AppColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message.content ?? '出错了',
                style: const TextStyle(fontSize: 13.5, height: 1.5, color: Color(0xFFFFC0C0)),
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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: borderColor ?? AppColors.line),
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
    final command = _commandPreview(permission.input);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.warn.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_outlined, size: 16, color: AppColors.warn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '请求执行 · ${permission.toolName}',
                    style: const TextStyle(fontSize: 13.5, color: Color(0xFFFFE2A8)),
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
                color: const Color(0xFF0C0F14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  command,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    color: Color(0xFFD8E1F0),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: _PermButton(label: '允许一次', color: AppColors.ok, onTap: () => onAnswer(true, false)),
                ),
                const SizedBox(width: 8),
                Expanded(child: _PermButton(label: '始终允许', onTap: () => onAnswer(true, true))),
                const SizedBox(width: 8),
                Expanded(child: _PermButton(label: '拒绝', color: AppColors.danger, onTap: () => onAnswer(false, false))),
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
    final tint = color ?? const Color(0xFFDCE4F2);
    return SizedBox(
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color?.withValues(alpha: 0.12) ?? AppColors.surface2,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: color?.withValues(alpha: 0.35) ?? AppColors.line2),
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
