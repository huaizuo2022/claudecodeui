import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/tokens.dart';

/// Bottom sheet offering user-turn and assistant-turn actions:
/// Copy text, Edit & Retry, and Fork Session from this message.
class MessageActionsSheet extends StatelessWidget {
  const MessageActionsSheet({
    super.key,
    required this.content,
    required this.isUser,
    this.messageId,
    this.onEdit,
    this.onFork,
  });

  final String content;
  final bool isUser;
  final String? messageId;
  final ValueChanged<String>? onEdit;
  final ValueChanged<String>? onFork;

  static Future<void> show(
    BuildContext context, {
    required String content,
    required bool isUser,
    String? messageId,
    ValueChanged<String>? onEdit,
    ValueChanged<String>? onFork,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MessageActionsSheet(
        content: content,
        isUser: isUser,
        messageId: messageId,
        onEdit: onEdit,
        onFork: onFork,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    isUser ? Icons.person_outline_rounded : Icons.smart_toy_outlined,
                    size: 18,
                    color: palette.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isUser ? '用户消息操作' : '助手消息操作',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.line),
            ListTile(
              leading: Icon(Icons.copy_rounded, size: 20, color: palette.text),
              title: Text(
                isUser ? '复制文本' : '复制 Markdown',
                style: TextStyle(fontSize: 14, color: palette.text),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await Clipboard.setData(ClipboardData(text: content));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制到剪贴板'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
            ),
            if (isUser && onEdit != null)
              ListTile(
                leading: Icon(Icons.edit_note_rounded, size: 22, color: palette.accent),
                title: Text(
                  '编辑并重新发送',
                  style: TextStyle(fontSize: 14, color: palette.text),
                ),
                subtitle: Text(
                  '将此内容填入输入框进行修改',
                  style: TextStyle(fontSize: 11.5, color: palette.text3),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  onEdit?.call(content);
                },
              ),
            if (onFork != null && messageId != null && messageId!.isNotEmpty)
              ListTile(
                leading: Icon(Icons.call_split_rounded, size: 20, color: palette.accentEnd),
                title: Text(
                  '从此处分叉新会话 (Fork)',
                  style: TextStyle(fontSize: 14, color: palette.text),
                ),
                subtitle: Text(
                  '以此节点为起点创建新分支会话',
                  style: TextStyle(fontSize: 11.5, color: palette.text3),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  onFork?.call(messageId!);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
