import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../app/theme/tokens.dart';

/// Assistant markdown with the app's code-block styling. `streaming` adds the
/// caret and lets the renderer reuse settled segments.
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.text, {super.key, this.streaming = false});

  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GptMarkdown(
      text,
      isStreaming: streaming,
      style: TextStyle(
        fontSize: AppTextSizes.message,
        height: 1.62,
        color: palette.assistantText,
      ),
      styleSheet: GptMarkdownStyleSheet(
        codeBlock: CodeBlockStyle(
          borderRadius: Radius.circular(14),
          showCopyButton: true,
        ),
      ),
      onLinkTap: (url, title) => _openLink(context, url),
    );
  }

  void _openLink(BuildContext context, String url) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('链接：$url（M4 接内置浏览器）')),
    );
  }
}
