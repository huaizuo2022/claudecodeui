import 'dart:convert';

import '../../../core/models/chat_message.dart';

/// Formats a list of [ChatMessage]s into a readable Markdown document,
/// matching the web transcript export format.
class SessionExport {
  const SessionExport._();

  static String toMarkdown({
    required String title,
    required String provider,
    required List<ChatMessage> messages,
    DateTime? exportedAt,
  }) {
    final now = exportedAt ?? DateTime.now();
    final buffer = StringBuffer();

    final safeTitle = title.trim().isEmpty ? '未命名会话' : title.trim();
    final safeProvider = provider.trim().isEmpty ? 'Claude' : provider.trim();

    buffer.writeln('# $safeTitle');
    buffer.writeln();
    buffer.writeln('_${messages.length} 条消息 · 导出时间: ${now.toLocal().toString().split('.').first} · 模型平台: $safeProvider _');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();

    for (final msg in messages) {
      if (msg.isUser) {
        buffer.writeln('### 👤 用户 (User)');
        buffer.writeln();
        if (msg.content != null && msg.content!.isNotEmpty) {
          buffer.writeln(msg.content);
          buffer.writeln();
        }
        if (msg.imagePaths.isNotEmpty) {
          buffer.writeln('_[包含 ${msg.imagePaths.length} 张图片附件]_');
          buffer.writeln();
        }
        buffer.writeln('---');
        buffer.writeln();
      } else if (msg.kind == 'thinking') {
        buffer.writeln('<details>');
        buffer.writeln('<summary>💭 思考过程 (Thinking)</summary>');
        buffer.writeln();
        buffer.writeln(msg.content ?? '');
        buffer.writeln('</details>');
        buffer.writeln();
      } else if (msg.toolName != null && msg.toolName!.isNotEmpty) {
        final toolName = msg.toolName!;
        buffer.writeln('**工具调用: `${toolName}`**');
        if (msg.toolSummary.isNotEmpty) {
          buffer.writeln('> ${msg.toolSummary}');
        }
        buffer.writeln();

        final inputPreview = _formatToolInput(msg.toolInput);
        if (inputPreview.isNotEmpty) {
          buffer.writeln('```json');
          buffer.writeln(inputPreview);
          buffer.writeln('```');
          buffer.writeln();
        }

        if (msg.toolResultContent != null && msg.toolResultContent!.isNotEmpty) {
          buffer.writeln(msg.isError ? '**执行失败 (Error):**' : '**执行结果 (Output):**');
          buffer.writeln('```text');
          buffer.writeln(msg.toolResultContent);
          buffer.writeln('```');
          buffer.writeln();
        }
        buffer.writeln('---');
        buffer.writeln();
      } else if (msg.kind == 'error') {
        buffer.writeln('⚠️ **错误:** ${msg.content ?? '未知错误'}');
        buffer.writeln();
        buffer.writeln('---');
        buffer.writeln();
      } else {
        // Normal assistant message.
        if (msg.content != null && msg.content!.trim().isNotEmpty) {
          buffer.writeln('### 🤖 助手 ($safeProvider)');
          buffer.writeln();
          buffer.writeln(msg.content);
          buffer.writeln();
          buffer.writeln('---');
          buffer.writeln();
        }
      }
    }

    return buffer.toString();
  }

  static String _formatToolInput(dynamic input) {
    if (input == null) return '';
    if (input is String) {
      final trimmed = input.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          final decoded = jsonDecode(trimmed);
          return const JsonEncoder.withIndent('  ').convert(decoded);
        } catch (_) {
          return trimmed;
        }
      }
      return trimmed;
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(input);
    } catch (_) {
      return '$input';
    }
  }
}
