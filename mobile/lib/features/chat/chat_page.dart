import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/api/sessions_api.dart';
import '../../core/models/chat_message.dart';
import '../../core/providers.dart';
import '../sessions/session_list_controller.dart';
import 'chat_controller.dart';
import 'chat_reducer.dart';
import 'utils/session_export.dart';
import 'widgets/composer.dart';
import 'widgets/model_picker_sheet.dart';
import 'widgets/permission_mode_sheet.dart';
import 'widgets/markdown_view.dart';
import 'widgets/message_directory_sheet.dart';
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
    this.initialEffort,
  });

  final String sessionId;
  final String title;
  final String subtitle;

  /// Provider for this session (e.g. 'claude', 'codex', 'cursor').
  final String? provider;

  /// Current model name, shown in the composer footer.
  final String? modelName;

  /// Reasoning effort to start with, forwarded to `initSession`.
  final String? initialEffort;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final _composerController = TextEditingController();
  bool _nearBottom = true;
  bool _loadingOlderTriggered = false;
  final Map<String, GlobalKey> _messageKeys = {};

  static const _bottomThreshold = 80.0;
  static const _topLoadThreshold = 400.0;

  GlobalKey _keyFor(ChatMessage msg) =>
      _messageKeys.putIfAbsent(msg.id, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Opening a session clears its attention dot and registers it as the one
      // being viewed, so background frames for it do not re-light the dot while
      // the user is looking at it (mirrors the web's clearSessionAttention).
      // Post-frame: modifying providers during initState is not allowed.
      ref.read(attentionSessionsProvider.notifier).clearAttention(widget.sessionId);
      activeViewedSessionId = widget.sessionId;
      final notifier = ref.read(chatControllerProvider(widget.sessionId).notifier);
      notifier.initSession(
        provider: widget.provider,
        initialModel: widget.modelName,
        initialEffort: widget.initialEffort,
      );
      notifier.reload();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The viewed-session release happens in ChatController's onDispose, which
    // runs when this page unmounts; a widget's dispose() must not touch refs.
    _scrollController.dispose();
    _composerController.dispose();
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

  void _scrollToMessage(int index) {
    final state = ref.read(chatControllerProvider(widget.sessionId));
    if (index < 0 || index >= state.messages.length) return;
    final key = _messageKeys[state.messages[index].id];
    if (key?.currentContext == null) return;
    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  void _openModelPicker(ChatState state) {
    ModelPickerSheet.show(
      context,
      provider: state.provider,
      currentModel: state.currentModel,
      models: state.availableModels,
      isLoading: state.loadingModels,
      currentEffort: state.currentEffort,
      availableEfforts: state.availableEfforts,
      onSelectEffort: (effort) {
        ref
            .read(chatControllerProvider(widget.sessionId).notifier)
            .selectEffort(effort)
            .catchError((error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('切换推理深度失败: $error')),
            );
          }
        });
      },
      onSelectModel: (model) {
        ref
            .read(chatControllerProvider(widget.sessionId).notifier)
            .selectModel(model)
            .catchError((error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('切换模型失败: $error')),
            );
          }
        });
      },
    );
  }

  void _showCostSheet(ChatState state) {
    final palette = AppPalette.of(context);
    final usage = state.tokenUsageText ?? '暂无用量统计';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: palette.line)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.monetization_on_outlined, color: palette.accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Token 消耗与成本 (/cost)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.codeBlockBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前会话累计消耗：',
                    style: TextStyle(fontSize: 12, color: palette.text3),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    usage,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '模型提供商：${state.provider.toUpperCase()} · ${state.currentModelLabel ?? state.currentModel ?? "默认模型"}',
                    style: TextStyle(fontSize: 12, color: palette.text2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _exportAsMarkdown() async {
    final state = ref.read(chatControllerProvider(widget.sessionId));
    final md = SessionExport.toMarkdown(
      title: widget.title,
      provider: widget.provider ?? state.provider,
      messages: state.messages,
    );
    await Clipboard.setData(ClipboardData(text: md));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('会话已导出为 Markdown 并复制到剪贴板'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _forkSession({String? upToAnchorId}) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在创建会话分支...'),
          duration: Duration(seconds: 1),
        ),
      );
      final client = ref.read(apiClientProvider);
      final created = await SessionsApi(client).forkSession(
        widget.sessionId,
        upToAnchorId: upToAnchorId,
      );
      if (!mounted) return;
      ref.read(homeRefreshProvider)();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            sessionId: created.sessionId,
            title: '${widget.title} (分支)',
            subtitle: widget.subtitle,
            provider: created.provider.isNotEmpty ? created.provider : widget.provider,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分叉会话失败: $e')),
        );
      }
    }
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
            const SizedBox(height: 1),
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
            tooltip: '消息目录',
            onPressed: () => MessageDirectorySheet.show(
              context,
              messages: state.messages,
              onScrollTo: _scrollToMessage,
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, size: 22, color: palette.text2),
            color: palette.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (value) {
              switch (value) {
                case 'export':
                  _exportAsMarkdown();
                  break;
                case 'fork':
                  _forkSession();
                  break;
                case 'reload':
                  ref.read(chatControllerProvider(widget.sessionId).notifier).reload();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已刷新会话'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.ios_share_rounded, size: 18, color: palette.text),
                    const SizedBox(width: 10),
                    Text('导出为 Markdown', style: TextStyle(fontSize: 13.5, color: palette.text)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'fork',
                child: Row(
                  children: [
                    Icon(Icons.call_split_rounded, size: 18, color: palette.text),
                    const SizedBox(width: 10),
                    Text('分叉整个会话', style: TextStyle(fontSize: 13.5, color: palette.text)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'reload',
                child: Row(
                  children: [
                    Icon(Icons.refresh_rounded, size: 18, color: palette.text),
                    const SizedBox(width: 10),
                    Text('刷新会话', style: TextStyle(fontSize: 13.5, color: palette.text)),
                  ],
                ),
              ),
            ],
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
            controller: _composerController,
            isProcessing: state.isProcessing,
            provider: widget.provider ?? state.provider,
            modelName: state.currentModelLabel ?? state.currentModel ?? widget.modelName,
            tokenCount: state.tokenUsageText,
            messageCount: state.messages.length,
            runStartedAt: state.runStartedAt,
            statusText: state.statusText,
            permissionMode: state.permissionMode,
            onSend: (text) {
              final trimmed = text.trim();
              if (trimmed == '/models') {
                _openModelPicker(state);
                return;
              }
              if (trimmed == '/cost') {
                _showCostSheet(state);
                return;
              }
              _jumpToLatest();
              ref.read(chatControllerProvider(widget.sessionId).notifier).send(text);
            },
            onAbort: () => ref.read(chatControllerProvider(widget.sessionId).notifier).abort(),
            pendingAttachments: state.pendingAttachments,
            onRemoveAttachment: (localId) =>
                ref.read(chatControllerProvider(widget.sessionId).notifier).removeAttachment(localId),
            onAttach: () {
              ref.read(chatControllerProvider(widget.sessionId).notifier).addImages();
            },
            onModelTap: () => _openModelPicker(state),
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
              key: _keyFor(message),
              message: message,
              onEditUserMessage: (content) {
                _composerController.text = content;
                _composerController.selection = TextSelection.fromPosition(
                  TextPosition(offset: content.length),
                );
                _jumpToLatest();
              },
              onForkSession: (anchorId) => _forkSession(upToAnchorId: anchorId),
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
