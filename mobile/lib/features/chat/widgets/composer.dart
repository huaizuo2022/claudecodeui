import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';

/// Growing composer with send ↔ stop switching. Attach/model chips land in M4.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.isProcessing,
    required this.onSend,
    required this.onAbort,
  });

  final bool isProcessing;
  final ValueChanged<String> onSend;
  final VoidCallback onAbort;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Transform.translate(
      // Keep the input above the keyboard without resizing the whole transcript.
      offset: Offset(0, -bottomInset),
      child: Container(
        width: view.physicalSize.width / view.devicePixelRatio,
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 14),
        decoration: const BoxDecoration(
          color: Color(0xF20D1015),
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _CircleButton(
              icon: Icons.add,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('附件/模型选择在 M4 接入')),
                );
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 38, maxHeight: 120),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: AppColors.line),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: AppTextSizes.message, color: AppColors.text),
                  decoration: const InputDecoration(
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: '发送消息…',
                    hintStyle: TextStyle(color: AppColors.text3),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SendButton(isProcessing: widget.isProcessing, onSend: _submit, onAbort: widget.onAbort),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2,
      shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.add, size: 18, color: AppColors.text2),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.isProcessing, required this.onSend, required this.onAbort});

  final bool isProcessing;
  final VoidCallback onSend;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context) {
    if (isProcessing) {
      return Material(
        color: AppColors.danger.withValues(alpha: 0.12),
        shape: const CircleBorder(
          side: BorderSide(color: Color(0x6BFF6B6B)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onAbort,
          child: const SizedBox(
            width: 34,
            height: 34,
            child: Icon(Icons.stop, size: 16, color: Color(0xFFFFB4B4)),
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: AppColors.primaryButtonGradient,
          shape: BoxShape.circle,
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onSend,
          child: const SizedBox(
            width: 34,
            height: 34,
            child: Icon(Icons.arrow_upward, size: 17, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
