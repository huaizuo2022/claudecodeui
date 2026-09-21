import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/models/chat_message.dart';

class MessageDirectorySheet extends StatefulWidget {
  const MessageDirectorySheet({
    super.key,
    required this.messages,
    required this.onScrollTo,
  });

  final List<ChatMessage> messages;
  final void Function(int index) onScrollTo;

  static void show(
    BuildContext context, {
    required List<ChatMessage> messages,
    required void Function(int index) onScrollTo,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => MessageDirectorySheet(
        messages: messages,
        onScrollTo: onScrollTo,
      ),
    );
  }

  @override
  State<MessageDirectorySheet> createState() => _MessageDirectorySheetState();
}

class _MessageDirectorySheetState extends State<MessageDirectorySheet> {
  bool _showTools = false;

  bool _keep(ChatMessage msg) {
    if (_showTools) return true;
    if (msg.isUser) return true;
    // Keep assistant text replies, drop tool_use / tool_result
    return msg.role == 'assistant' && (msg.content?.isNotEmpty ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final all = widget.messages.reversed.toList();
    final filtered = all.where(_keep).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.text3.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '会话目录',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showTools = !_showTools),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: _showTools
                          ? palette.accent.withValues(alpha: 0.12)
                          : palette.text3.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(
                        color: _showTools
                            ? palette.accent.withValues(alpha: 0.3)
                            : palette.text3.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showTools ? Icons.build_outlined : Icons.build_outlined,
                          size: 13,
                          color: _showTools ? palette.accent : palette.text3,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '工具',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _showTools ? palette.accent : palette.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${filtered.length}/${all.length}',
                  style: TextStyle(fontSize: 12, color: palette.text3.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配的消息',
                      style: TextStyle(fontSize: 13.5, color: palette.text3),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final msg = filtered[index];
                      final isUser = msg.isUser;
                      final preview = _preview(msg);

                      return InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          final originalIndex = widget.messages.length - 1 - all.indexOf(msg);
                          widget.onScrollTo(originalIndex);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? palette.accent.withValues(alpha: 0.12)
                                      : palette.text3.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  isUser ? Icons.person_outline : Icons.smart_toy_outlined,
                                  size: 16,
                                  color: isUser ? palette.accent : palette.text2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isUser ? '你' : '助手',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: palette.text,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      preview,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12.5, color: palette.text3),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${all.indexOf(msg) + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: palette.text3.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _preview(ChatMessage msg) {
    if (msg.toolName != null && msg.toolName!.isNotEmpty) {
      final kind = msg.kind == 'tool_use' ? '调用' : '结果';
      return '${msg.toolName} ($kind)';
    }
    if (msg.content != null && msg.content!.isNotEmpty) {
      final text = msg.content!.replaceAll(RegExp(r'[\s\n]+'), ' ').trim();
      return text.length > 60 ? '${text.substring(0, 60)}…' : text;
    }
    if (msg.kind == 'tool_use') return '工具调用';
    if (msg.kind == 'tool_result') return '工具结果';
    return '(空消息)';
  }
}