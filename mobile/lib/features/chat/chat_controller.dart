import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_message.dart';
import '../../core/providers.dart';
import '../../core/util/logger.dart';
import '../../core/ws/server_event.dart';
import 'chat_reducer.dart';

const _historyPageSize = 60;

/// Per-session chat state: history pages + the live run. The socket is shared;
/// this controller only listens while the provider is alive.
class ChatController extends Notifier<ChatState> {
  ChatController(this.sessionId);

  final String sessionId;
  static const _log = Logger('chat');

  bool _subscribedToSocket = false;
  Timer? _streamFlushTimer;
  String _pendingStreamText = '';
  int _historyOffset = 0;

  @override
  ChatState build() {
    final socket = ref.read(chatSocketProvider);
    socket.addListener(_onFrame);
    _subscribedToSocket = true;
    ref.onDispose(() {
      if (_subscribedToSocket) socket.removeListener(_onFrame);
      _streamFlushTimer?.cancel();
    });

    Future.microtask(() async {
      await _loadInitialHistory();
      _subscribe();
    });

    return const ChatState();
  }

  // ── Socket plumbing ──────────────────────────────────────────────────────

  void _onFrame(Map<dynamic, dynamic> frame) {
    final kind = frame['kind'] as String?;
    if (kind == 'socket_connected') {
      // Reconnect: replay what was missed since our highest seq.
      if (state.historyLoaded) _subscribe();
      return;
    }
    if (frame['sessionId'] != null && frame['sessionId'] != sessionId) return;
    _handleEvent(ServerEvent.fromJson(frame));
  }

  void _subscribe() {
    final socket = ref.read(chatSocketProvider);
    final url = ref.read(apiClientProvider).webSocketUrl;
    if (url != null && !socket.isConnected) {
      socket.connect(url);
    }
    socket.send({
      'type': 'chat.subscribe',
      'sessions': [
        {'sessionId': sessionId, 'lastSeq': state.lastSeq},
      ],
    });
    _log.info('subscribed to $sessionId (lastSeq=${state.lastSeq})');
  }

  void _handleEvent(ServerEvent event) {
    // stream_delta arrives per token; buffer and flush at a sane rate so the
    // widget tree is not rebuilt hundreds of times per second.
    if (event.kind == ServerEventKind.streamDelta) {
      _pendingStreamText += event.content ?? '';
      final delta = _pendingStreamText;
      _streamFlushTimer?.cancel();
      _streamFlushTimer = Timer(const Duration(milliseconds: 80), () {
        _flushStream(delta);
      });
      state = state.copyWith(
        isProcessing: true,
        runStartedAt: state.isProcessing ? null : DateTime.now(),
      );
      return;
    }

    _flushStreamNow();
    state = reduceChatEvent(state, event);

    if (event.kind == ServerEventKind.historyTruncated ||
        event.kind == ServerEventKind.complete) {
      _refreshAfterRun();
    }
  }

  void _flushStream(String text) {
    _pendingStreamText = '';
    if (!state.isStreaming && text.isEmpty) return;
    state = state.copyWith(
      streamingText: text,
      isStreaming: true,
      isProcessing: true,
      unreadCount: state.following ? 0 : state.unreadCount + 1,
    );
  }

  void _flushStreamNow() {
    if (_pendingStreamText.isEmpty) return;
    final text = _pendingStreamText;
    _streamFlushTimer?.cancel();
    _flushStream(text);
  }

  Future<void> _refreshAfterRun() async {
    // After a run settles the persisted transcript is authoritative; pull the
    // newest page quietly (dedupe keeps already-rendered rows in place).
    try {
      final page = await ref.read(messagesApiProvider).fetchHistory(
            sessionId,
            limit: _historyPageSize,
            offset: 0,
          );
      _historyOffset = page.messages.length;
      state = state.copyWith(
        messages: _mergeServerMessages(state.messages, page.messages),
        totalMessages: page.total,
        hasMoreHistory: page.hasMore,
      );
    } catch (error) {
      _log.warn('post-run refresh failed: $error');
    }
  }

  // ── History ──────────────────────────────────────────────────────────────

  Future<void> _loadInitialHistory() async {
    state = state.copyWith(loadingHistory: true, clearHistoryError: true);
    try {
      final page = await ref.read(messagesApiProvider).fetchHistory(
            sessionId,
            limit: _historyPageSize,
            offset: 0,
          );
      _historyOffset = page.messages.length;
      state = state.copyWith(
        messages: page.messages,
        totalMessages: page.total,
        hasMoreHistory: page.hasMore,
        loadingHistory: false,
        historyLoaded: true,
        clearHistoryError: true,
      );
    } catch (error) {
      state = state.copyWith(
        loadingHistory: false,
        historyLoaded: true,
        historyError: '$error',
      );
    }
  }

  Future<void> loadOlder() async {
    if (state.loadingHistory || !state.hasMoreHistory) return;
    state = state.copyWith(loadingHistory: true, clearHistoryError: true);
    try {
      final page = await ref.read(messagesApiProvider).fetchHistory(
            sessionId,
            limit: _historyPageSize,
            offset: _historyOffset,
          );
      final existingIds = state.messages.map((message) => message.id).toSet();
      final older = page.messages
          .where((message) => !existingIds.contains(message.id))
          .toList(growable: false);
      _historyOffset += page.messages.length;
      state = state.copyWith(
        messages: [...older, ...state.messages],
        hasMoreHistory: page.hasMore,
        loadingHistory: false,
      );
    } catch (error) {
      state = state.copyWith(loadingHistory: false, historyError: '$error');
    }
  }

  /// Merges live rows with a server page by id (server wins on conflict).
  List<ChatMessage> _mergeServerMessages(
    List<ChatMessage> current,
    List<ChatMessage> serverPage,
  ) {
    final byId = {for (final message in serverPage) message.id: message};
    final kept = current
        .where((message) => !_isSynthetic(message) && !byId.containsKey(message.id))
        .toList();
    final liveTail = current.where(_isSynthetic).toList();
    return [...kept, ...serverPage, ...liveTail]
      ..sort((a, b) => _compareTimestamps(a.timestamp, b.timestamp));
  }

  /// Rows this client synthesized (optimistic sends, streamed text) never
  /// survive a server-page merge: the persisted row replaces them.
  bool _isSynthetic(ChatMessage message) =>
      message.id.startsWith('local_') ||
      message.id.startsWith('stream_') ||
      message.id.startsWith('protocol_error_');

  int _compareTimestamps(String a, String b) {
    final ta = DateTime.tryParse(a)?.millisecondsSinceEpoch ?? 0;
    final tb = DateTime.tryParse(b)?.millisecondsSinceEpoch ?? 0;
    return ta.compareTo(tb);
  }

  // ── User actions ─────────────────────────────────────────────────────────

  Future<bool> send(String content) async {
    final text = content.trim();
    if (text.isEmpty || state.isProcessing) return false;

    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(
          id: 'local_${DateTime.now().microsecondsSinceEpoch}',
          kind: 'text',
          timestamp: DateTime.now().toIso8601String(),
          role: 'user',
          content: text,
        ),
      ],
      following: true,
      unreadCount: 0,
      isProcessing: true,
      runStartedAt: DateTime.now(),
    );

    _subscribe();
    return ref.read(chatSocketProvider).send({
      'type': 'chat.send',
      'sessionId': sessionId,
      'content': text,
      'options': const <String, dynamic>{},
    });
  }

  void abort() {
    ref.read(chatSocketProvider).send({
      'type': 'chat.abort',
      'sessionId': sessionId,
    });
  }

  void answerPermission(String requestId, {required bool allow, bool remember = false}) {
    final match = state.pendingPermissions
        .where((pending) => pending.requestId == requestId)
        .toList(growable: false);
    if (match.isEmpty) return;
    final permission = match.first;
    state = state.copyWith(
      pendingPermissions: state.pendingPermissions
          .where((pending) => pending.requestId != requestId)
          .toList(growable: false),
    );
    ref.read(chatSocketProvider).send({
      'type': 'chat.permission-response',
      'requestId': requestId,
      'allow': allow,
      if (remember) 'rememberEntry': buildPermissionRememberEntry(permission.toolName, permission.input),
      if (!allow) 'message': 'User denied tool use',
    });
  }

  // ── Scroll follow state (driven by the message list) ─────────────────────

  /// Pulls the first page again (retry button / manual refresh).
  Future<void> reload() async {
    await _loadInitialHistory();
    _subscribe();
  }

  void setFollowing(bool following) {
    if (state.following == following) return;
    state = state.copyWith(
      following: following,
      unreadCount: following ? 0 : state.unreadCount,
    );
  }

  void jumpToLatest() => setFollowing(true);
}

final chatControllerProvider =
    NotifierProvider.family<ChatController, ChatState, String>(ChatController.new);
