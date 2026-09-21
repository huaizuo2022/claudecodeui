import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/providers.dart';
import 'chat_controller.dart';
import 'chat_reducer.dart';
import 'widgets/composer.dart';
import 'widgets/markdown_view.dart';
import 'widgets/message_tile.dart';
import 'widgets/run_strip.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    super.key,
    required this.sessionId,
    required this.title,
    required this.subtitle,
    this.provider,
    this.modelName,
  });

  final String sessionId;
  final String title;
  final String subtitle;

  /// Provider display name (Claude/Codex/Cursor), for the composer placeholder.
  final String? provider;

  /// Current model name, shown in the composer footer.
  final String? modelName;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _scrollController = ScrollController();
  bool _nearBottom = true;
  bool _loadingOlderTriggered = false;

  static const _bottomThreshold = 80.0;
  static const _topLoadThreshold = 400.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final nearBottom = position.pixels < _bottomThreshold;
    if (nearBottom != _nearBottom) {
      _nearBottom = nearBottom;
      ref.read(chatControllerProvider(widget.sessionId).notifier).setFollowing(nearBottom);
    }

    final distanceFromTop = position.maxScrollExtent - position.pixels;
    if (distanceFromTop < _topLoadThreshold && !_loadingOlderTriggered) {
      _loadingOlderTriggered = true;
      ref.read(chatControllerProvider(widget.sessionId).notifier).loadOlder().whenComplete(() {
        if (mounted) setState(() => _loadingOlderTriggered = false);
      });
    }
  }

  void _jumpToLatest() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
    ref.read(chatControllerProvider(widget.sessionId).notifier).jumpToLatest();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = ref.watch(chatControllerProvider(widget.sessionId));
    final connected = ref.watch(socketConnectedProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: palette.bg.withValues(alpha: 0.9),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, size: 26, color: palette.text),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          children: [
            Text(
              widget.title.isEmpty ? '(未命名会话)' : widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTextSizes.navTitle,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
            SizedBox(height: 1),
            Text(
              widget.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: palette.text3),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.menu_outlined, size: 20, color: palette.text2),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('会话目录在 M4 接入')),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          RunStrip(
            isProcessing: state.isProcessing,
            runStartedAt: state.runStartedAt,
            statusText: state.statusText,
            connected: connected,
          ),
          Expanded(child: _buildBody(state)),
        ],
      ),
      // The composer translates itself with the keyboard; the bottom bar keeps
      // the transcript height stable while typing.
      bottomNavigationBar: Composer(
        isProcessing: state.isProcessing,
        provider: widget.provider ?? 'Claude',
        modelName: widget.modelName,
        messageCount: state.messages.length,
        onSend: (text) =>
            ref.read(chatControllerProvider(widget.sessionId).notifier).send(text),
        onAbort: () => ref.read(chatControllerProvider(widget.sessionId).notifier).abort(),
        onAttach: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('附件在 M4 接入')),
          );
        },
        onModelTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('模型选择在 M4 接入')),
          );
        },
        onPermissionTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('权限模式在 M4 接入')),
          );
        },
      ),
    );
  }

  Widget _buildBody(ChatState state) {
    final palette = AppPalette.of(context);
    if (!state.historyLoaded && state.loadingHistory) {
      return Center(child: CircularProgressIndicator(color: palette.accent));
    }
    if (state.messages.isEmpty && state.streamingText.isEmpty) {
      if (state.historyError != null) {
        return _Message(
          icon: Icons.cloud_off_outlined,
          color: palette.danger,
          text: state.historyError!,
          action: '重试',
          onAction: () => ref.read(chatControllerProvider(widget.sessionId).notifier).reload(),
        );
      }
      return _Message(
        icon: Icons.chat_bubble_outline,
        color: palette.text3,
        text: '还没有消息，发送第一条吧',
      );
    }

    // Reverse list: index 0 is the newest edge, pinned to the visual bottom.
    // Streaming text and pending permission cards occupy that edge, above the
    // newest transcript row.
    final rows = <Widget>[
      for (final permission in state.pendingPermissions.reversed)
        PermissionCard(
          permission: permission,
          onAnswer: (allow, remember) => ref
              .read(chatControllerProvider(widget.sessionId).notifier)
              .answerPermission(permission.requestId, allow: allow, remember: remember),
        ),
      if (state.streamingText.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: MarkdownView(state.streamingText, streaming: true),
        ),
      for (var i = state.messages.length - 1; i >= 0; i--)
        MessageTile(message: state.messages[i]),
    ];

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          itemCount: rows.length,
          itemBuilder: (context, index) => rows[index],
        ),
        if (!state.following)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Center(
              child: _JumpPill(
                unread: state.unreadCount,
                onTap: _jumpToLatest,
              ),
            ),
          ),
      ],
    );
  }

}

class _JumpPill extends StatelessWidget {
  const _JumpPill({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.jumpPillBg,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: palette.line2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_downward, size: 13, color: palette.text2),
              SizedBox(width: 6),
              Text(
                unread > 0 ? '跳到最新 · $unread 条新消息' : '跳到最新',
                style: TextStyle(fontSize: 12, color: palette.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.color,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: color),
          SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 36),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.6, color: palette.text2),
            ),
          ),
          if (action != null) ...[
            SizedBox(height: 14),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(backgroundColor: palette.surface3),
              child: Text(action!),
            ),
          ],
        ],
      ),
    );
  }
}
