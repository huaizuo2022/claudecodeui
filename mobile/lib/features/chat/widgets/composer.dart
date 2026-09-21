import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';

/// Web-parity composer: textarea on top, tool row below, matching the layout
/// of https://claude.huaizuo2029.cn's prompt-input (form > body + footer).
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.isProcessing,
    required this.onSend,
    required this.onAbort,
    this.provider = 'Claude',
    this.modelName,
    this.tokenCount,
    this.messageCount = 0,
    this.onAttach,
    this.onModelTap,
    this.onPermissionTap,
  });

  final bool isProcessing;
  final ValueChanged<String> onSend;
  final VoidCallback onAbort;

  /// Provider display name, used in the placeholder.
  final String provider;

  /// Current model name, shown in the footer.
  final String? modelName;

  /// Token usage for the session, when the server reports it.
  final String? tokenCount;
  final int messageCount;

  final VoidCallback? onAttach;
  final VoidCallback? onModelTap;
  final VoidCallback? onPermissionTap;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isProcessing) return;
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      width: double.infinity,
      color: palette.composerBg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          child: Center(
            heightFactor: 1.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 868),
              child: _InputCard(
                palette: palette,
                focusNode: _focusNode,
                controller: _controller,
                isProcessing: widget.isProcessing,
                hasText: _hasText,
                provider: widget.provider,
                modelName: widget.modelName,
                tokenCount: widget.tokenCount,
                messageCount: widget.messageCount,
                onSubmit: _submit,
                onAbort: widget.onAbort,
                onAttach: widget.onAttach,
                onModelTap: widget.onModelTap,
                onPermissionTap: widget.onPermissionTap,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The rounded card containing textarea + footer, mirroring the web's
/// `form[data-slot="prompt-input"]` structure.
class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.palette,
    required this.focusNode,
    required this.controller,
    required this.isProcessing,
    required this.hasText,
    required this.provider,
    required this.onSubmit,
    required this.onAbort,
    this.modelName,
    this.tokenCount,
    this.messageCount = 0,
    this.onAttach,
    this.onModelTap,
    this.onPermissionTap,
  });

  final AppPalette palette;
  final FocusNode focusNode;
  final TextEditingController controller;
  final bool isProcessing;
  final bool hasText;
  final String provider;
  final String? modelName;
  final String? tokenCount;
  final int messageCount;
  final VoidCallback onSubmit;
  final VoidCallback onAbort;
  final VoidCallback? onAttach;
  final VoidCallback? onModelTap;
  final VoidCallback? onPermissionTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: focusNode.hasFocus
              ? palette.accent.withValues(alpha: 0.3)
              : palette.line.withValues(alpha: 0.5),
        ),
        boxShadow: focusNode.hasFocus
            ? [
                BoxShadow(
                  color: palette.accent.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : [
                BoxShadow(
                  color: palette.brightness == Brightness.light
                    ? Colors.black.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBody(),
          Divider(height: 1, color: palette.line.withValues(alpha: 0.3)),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        minLines: 1,
        maxLines: 6,
        textInputAction: TextInputAction.newline,
        keyboardType: TextInputType.multiline,
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: palette.text,
        ),
        decoration: InputDecoration(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          hintText: '输入 / 调用命令，@ 选择文件，或向 $provider 提问...',
          hintStyle: TextStyle(
            fontSize: 14,
            color: palette.text3,
          ),
        ),
        onSubmitted: (_) => onSubmit(),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // Left tools: attach, token usage, message count.
          _ToolButton(
            icon: Icons.attach_file_outlined,
            palette: palette,
            onTap: onAttach,
          ),
          if (tokenCount != null && tokenCount!.isNotEmpty) ...[
            const SizedBox(width: 4),
            _PillButton(
              icon: Icons.bar_chart_rounded,
              label: tokenCount!,
              palette: palette,
            ),
          ],
          const SizedBox(width: 4),
          _PillButton(
            icon: Icons.chat_bubble_outline,
            label: '$messageCount',
            palette: palette,
          ),

          // Right controls: model, permission, send.
          const Spacer(),
          _ModelButton(
            modelName: (modelName != null && modelName!.isNotEmpty)
                ? modelName!
                : '选择模型',
            palette: palette,
            onTap: onModelTap,
          ),
          const SizedBox(width: 4),
          _PermissionButton(palette: palette, onTap: onPermissionTap),
          const SizedBox(width: 6),
          _SendButton(
            palette: palette,
            enabled: hasText && !isProcessing,
            isProcessing: isProcessing,
            onSubmit: onSubmit,
            onAbort: onAbort,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.palette, this.onTap});

  final IconData icon;
  final AppPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 16, color: palette.text2),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: palette.accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: palette.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelButton extends StatelessWidget {
  const _ModelButton({required this.modelName, required this.palette, this.onTap});

  final String modelName;
  final AppPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: palette.surface2.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.line.withValues(alpha: 0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 82),
                  child: Text(
                    modelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: palette.text,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.expand_more, size: 14, color: palette.text3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionButton extends StatelessWidget {
  const _PermissionButton({required this.palette, this.onTap});

  final AppPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.back_hand_outlined, size: 14, color: palette.text2),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.palette,
    required this.enabled,
    required this.isProcessing,
    required this.onSubmit,
    required this.onAbort,
  });

  final AppPalette palette;
  final bool enabled;
  final bool isProcessing;
  final VoidCallback onSubmit;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context) {
    if (isProcessing) {
      return Material(
        color: palette.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onAbort,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.stop, size: 16, color: palette.danger),
          ),
        ),
      );
    }

    return Material(
      color: enabled ? null : palette.surface2,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        decoration: BoxDecoration(
          gradient: enabled ? palette.primaryButtonGradient : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          onTap: enabled ? onSubmit : null,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              Icons.arrow_upward,
              size: 17,
              color: enabled ? palette.onPrimary : palette.text3,
            ),
          ),
        ),
      ),
    );
  }
}