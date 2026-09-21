import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/providers.dart';
import 'chat_controller.dart';
import 'chat_reducer.dart';
import 'widgets/composer.dart';
import 'widgets/model_picker_sheet.dart';
import 'widgets/permission_mode_sheet.dart';
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

  /// Provider for this session (e.g. 'claude', 'codex', 'cursor').
  final String? provider;

  /// Current model name, shown in the composer footer.
  final String? modelName;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  bool _nearBottom = true;
  bool _loadingOlderTriggered = false;

  static const _bottomThreshold = 80.0;
  static const _topLoadThreshold = 400.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(chatControllerProvider(widget.sessionId).notifier);
      notifier.initSession(
        provider: widget.provider,
        initialModel: widget.modelName,
      );
      notifier.reload();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(chatControllerProvider(widget.sessionId).notifier).handleAppResume();
    }
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
      resizeToAvoidBottomInset: true,
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
            icon: Icon(Icons.refresh, size: 22, color: palette.text2),
            tooltip: '刷新会话',
            onPressed: () {
              ref.read(chatControllerProvider(widget.sessionId).notifier).reload();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已刷新会话'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
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
          Composer(
            isProcessing: state.isProcessing,
            provider: widget.provider ?? state.provider,
            modelName: state.currentModelLabel ?? state.currentModel ?? widget.modelName,
            tokenCount: state.tokenUsageText,
            messageCount: state.messages.length,
            runStartedAt: state.runStartedAt,
            statusText: state.statusText,
            permissionMode: state.permissionMode,
            onSend: (text) =>
                ref.read(chatControllerProvider(widget.sessionId).notifier).send(text),
            onAbort: () => ref.read(chatControllerProvider(widget.sessionId).notifier).abort(),
            pendingAttachments: state.pendingAttachments,
            onRemoveAttachment: (localId) =>
                ref.read(chatControllerProvider(widget.sessionId).notifier).removeAttachment(localId),
            onAttach: () {
              ref.read(chatControllerProvider(widget.sessionId).notifier).addImages();
            },
            onModelTap: () {
              ModelPickerSheet.show(
                context,
                provider: state.provider,
                currentModel: state.currentModel,
                models: state.availableModels,
                isLoading: state.loadingModels,
                onSelectModel: (model) {
                  ref
                      .read(chatControllerProvider(widget.sessionId).notifier)
                      .selectModel(model)
                      .catchError((error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('切换模型失败: $error')),
                      );
                    }
                  });
                },
              );
            },
            onPermissionTap: () {
              PermissionModeSheet.show(
                context,
                provider: state.provider,
                currentMode: state.permissionMode,
                availableModes: state.availablePermissionModes,
                onSelectMode: (mode) {
                  ref
                      .read(chatControllerProvider(widget.sessionId).notifier)
                      .selectPermissionMode(mode);
                },
              );
            },
          ),
        ],
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
    final permissionsCount = state.pendingPermissions.length;
    final hasStreaming = state.streamingText.isNotEmpty;
    final streamingIndex = permissionsCount;
    final messagesStartIndex = permissionsCount + (hasStreaming ? 1 : 0);
    final totalCount = messagesStartIndex + state.messages.length;

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          itemCount: totalCount,
          itemBuilder: (context, index) {
            if (index < permissionsCount) {
              final permission = state.pendingPermissions[permissionsCount - 1 - index];
              return PermissionCard(
                key: ValueKey(permission.requestId),
                permission: permission,
                onAnswer: (allow, remember) => ref
                    .read(chatControllerProvider(widget.sessionId).notifier)
                    .answerPermission(permission.requestId, allow: allow, remember: remember),
              );
            }
            if (hasStreaming && index == streamingIndex) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: MarkdownView(state.streamingText, streaming: true),
              );
            }
            final messageIndex = state.messages.length - 1 - (index - messagesStartIndex);
            final message = state.messages[messageIndex];
            return MessageTile(
              key: ValueKey(message.id),
              message: message,
            );
          },
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
