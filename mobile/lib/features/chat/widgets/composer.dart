import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/models/provider_capability.dart';
import '../chat_reducer.dart';

/// Web-parity composer: textarea on top, tool row below, matching the layout
/// of https://claude.huaizuo2029.cn's prompt-input (form > body + footer) and
/// ActivityIndicator atop the card when processing.
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
    this.pendingAttachments = const [],
    this.onRemoveAttachment,
    this.runStartedAt,
    this.statusText,
    this.onAttach,
    this.onModelTap,
    this.onPermissionTap,
    this.permissionMode = 'default',
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

  /// Attachments picked for the next message.
  final List<PendingAttachment> pendingAttachments;
  final ValueChanged<String>? onRemoveAttachment;

  final DateTime? runStartedAt;
  final String? statusText;

  final VoidCallback? onAttach;
  final VoidCallback? onModelTap;
  final VoidCallback? onPermissionTap;
  final String permissionMode;

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
    _focusNode.addListener(() {
      if (mounted) setState(() {});
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
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: widget.isProcessing ? 28 : 0),
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
                      pendingAttachments: widget.pendingAttachments,
                      onRemoveAttachment: widget.onRemoveAttachment,
                      onSubmit: _submit,
                      onAbort: widget.onAbort,
                      onAttach: widget.onAttach,
                      onModelTap: widget.onModelTap,
                      onPermissionTap: widget.onPermissionTap,
                      permissionMode: widget.permissionMode,
                    ),
                  ),
                  if (widget.isProcessing)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 29,
                      child: _ActivityHeader(
                        palette: palette,
                        isFocused: _focusNode.hasFocus,
                        runStartedAt: widget.runStartedAt,
                        statusText: widget.statusText,
                        onAbort: widget.onAbort,
                      ),
                    ),
                ],
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
    this.pendingAttachments = const [],
    this.onRemoveAttachment,
    this.onAttach,
    this.onModelTap,
    this.onPermissionTap,
    this.permissionMode = 'default',
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
  final List<PendingAttachment> pendingAttachments;
  final ValueChanged<String>? onRemoveAttachment;
  final VoidCallback onSubmit;
  final VoidCallback onAbort;
  final VoidCallback? onAttach;
  final VoidCallback? onModelTap;
  final VoidCallback? onPermissionTap;
  final String permissionMode;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: isProcessing
            ? const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              )
            : BorderRadius.circular(16),
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
          if (pendingAttachments.isNotEmpty) _buildAttachmentStrip(),
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

  Widget _buildAttachmentStrip() {
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        itemCount: pendingAttachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final pending = pendingAttachments[index];
          return _AttachmentThumb(
            palette: palette,
            pending: pending,
            onRemove: () => onRemoveAttachment?.call(pending.localId),
          );
        },
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
              icon: Icons.show_chart_rounded,
              label: tokenCount!,
              palette: palette,
            ),
          ],
          const SizedBox(width: 4),
          _MessageCountBadge(
            palette: palette,
            count: messageCount,
          ),

          // Right controls: model, permission, send/stop.
          const Spacer(),
          _ModelButton(
            modelName: (modelName != null && modelName!.isNotEmpty)
                ? modelName!
                : '选择模型',
            palette: palette,
            onTap: onModelTap,
          ),
          const SizedBox(width: 4),
          _PermissionButton(
            permissionMode: permissionMode,
            palette: palette,
            onTap: onPermissionTap,
          ),
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

/// Web-parity ActivityIndicator atop the input card:
/// Left tab: pulsing dot, cycling action word, elapsed timer.
/// Right tab: stop button (■ 停止).
class _ActivityHeader extends StatefulWidget {
  const _ActivityHeader({
    required this.palette,
    required this.isFocused,
    required this.runStartedAt,
    required this.statusText,
    required this.onAbort,
  });

  final AppPalette palette;
  final bool isFocused;
  final DateTime? runStartedAt;
  final String? statusText;
  final VoidCallback onAbort;

  @override
  State<_ActivityHeader> createState() => _ActivityHeaderState();
}

class _ActivityHeaderState extends State<_ActivityHeader> {
  Timer? _timer;
  late int _elapsedSeconds;

  static const _actionWords = [
    'Thinking',
    'Processing',
    'Analyzing',
    'Working',
    'Computing',
    'Reasoning',
  ];

  @override
  void initState() {
    super.initState();
    _calcElapsed();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _calcElapsed();
        });
      }
    });
  }

  void _calcElapsed() {
    final started = widget.runStartedAt;
    if (started != null) {
      _elapsedSeconds = DateTime.now().difference(started).inSeconds;
      if (_elapsedSeconds < 0) _elapsedSeconds = 0;
    } else {
      _elapsedSeconds = 0;
    }
  }

  @override
  void didUpdateWidget(_ActivityHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.runStartedAt != oldWidget.runStartedAt) {
      _calcElapsed();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final borderColor = widget.isFocused
        ? palette.accent.withValues(alpha: 0.3)
        : palette.line.withValues(alpha: 0.5);

    // Action word calculation matching Web ActivityIndicator:
    final cycleIndex = (_elapsedSeconds ~/ 4) % _actionWords.length;
    final defaultWord = _actionWords[cycleIndex];
    final rawLabel = (widget.statusText != null && widget.statusText!.trim().isNotEmpty)
        ? widget.statusText!.trim()
        : defaultWord;
    final label = rawLabel.replaceAll(RegExp(r'\.+$'), '');

    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;
    final elapsedText = minutes < 1 ? '${seconds}s' : '${minutes}m ${seconds}s';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left tab: • Working... 37s
        Container(
          height: 29,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(8),
            ),
            border: Border(
              top: BorderSide(color: borderColor),
              left: BorderSide(color: borderColor),
              right: BorderSide(color: borderColor),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulsingDot(color: palette.accent),
              const SizedBox(width: 6),
              Text(
                '$label...',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: palette.text,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                elapsedText,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.normal,
                  color: palette.text3,
                ),
              ),
            ],
          ),
        ),

        // Right tab: ■ 停止
        Material(
          color: palette.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(12),
          ),
          child: InkWell(
            onTap: widget.onAbort,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(12),
            ),
            child: Container(
              height: 29,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(12),
                ),
                border: Border(
                  top: BorderSide(color: borderColor),
                  left: BorderSide(color: borderColor),
                  right: BorderSide(color: borderColor),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: palette.text2,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '停止',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: palette.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Gently pulsing accent dot for the activity indicator tab.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: child,
        );
      },
      child: Container(
        width: 6.5,
        height: 6.5,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
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

class _MessageCountBadge extends StatelessWidget {
  const _MessageCountBadge({
    required this.palette,
    required this.count,
  });

  final AppPalette palette;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _ToolButton(
          icon: Icons.chat_bubble_outline,
          palette: palette,
          onTap: null,
        ),
        if (count > 0)
          Positioned(
            right: 0,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              alignment: Alignment.center,
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ),
          ),
      ],
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
  const _PermissionButton({
    required this.palette,
    this.permissionMode = 'default',
    this.onTap,
  });

  final AppPalette palette;
  final String permissionMode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final info = getPermissionModeInfo(permissionMode);
    final isDark = palette.brightness == Brightness.dark;

    Color bg;
    Color border;
    Color iconColor;

    switch (permissionMode) {
      case 'bypassPermissions':
        bg = isDark ? const Color(0x28C2410C) : const Color(0xFFFFF7ED);
        border = isDark ? const Color(0x66EA580C) : const Color(0xFFFDBA74);
        iconColor = isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C);
        break;
      case 'auto':
        bg = isDark ? const Color(0x282563EB) : const Color(0xFFEFF6FF);
        border = isDark ? const Color(0x663B82F6) : const Color(0xFFBFDBFE);
        iconColor = isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
        break;
      case 'acceptEdits':
        bg = isDark ? const Color(0x2816A34A) : const Color(0xFFF0FDF4);
        border = isDark ? const Color(0x6622C55E) : const Color(0xFFBBF7D0);
        iconColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
        break;
      case 'plan':
        bg = isDark ? const Color(0x287C3AED) : const Color(0xFFF5F3FF);
        border = isDark ? const Color(0x668B5CF6) : const Color(0xFFDDD6FE);
        iconColor = isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
        break;
      case 'default':
      default:
        bg = palette.surface2;
        border = palette.line.withValues(alpha: 0.5);
        iconColor = palette.text2;
        break;
    }

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: border, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(info.icon, size: 16, color: iconColor),
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
      // Replicating Web PromptInputSubmit when active:
      // Solid primary button (palette.accent) with a crisp white solid square icon.
      return Material(
        color: palette.accent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onAbort,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
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
/// One selected-attachment thumbnail: image preview, upload spinner, error
/// badge, and a remove button.
class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({
    required this.palette,
    required this.pending,
    required this.onRemove,
  });

  final AppPalette palette;
  final PendingAttachment pending;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final failed = pending.hasFailed;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Container(
            width: 64,
            height: 64,
            color: palette.surface2,
            child: Image.file(
              File(pending.localPath),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                size: 20,
                color: palette.text3,
              ),
            ),
          ),
          if (failed)
            Container(
              width: 64,
              height: 64,
              color: palette.danger.withValues(alpha: 0.55),
              child: const Icon(Icons.error_outline, size: 18, color: Colors.white),
            )
          else if (pending.isUploading)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0x66000000),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
