import 'dart:convert';

import '../../core/models/chat_message.dart';
import '../../core/ws/server_event.dart';

/// Permission prompt awaiting an answer, kept outside the transcript (the
/// server replays them with `chat.subscribe`).
class PendingPermission {
  const PendingPermission({
    required this.requestId,
    required this.toolName,
    required this.input,
  });

  final String requestId;
  final String toolName;
  final dynamic input;
}

class ChatState {
  const ChatState({
    this.messages = const [],
    this.streamingText = '',
    this.isStreaming = false,
    this.isProcessing = false,
    this.runStartedAt,
    this.statusText,
    this.pendingPermissions = const [],
    this.unreadCount = 0,
    this.following = true,
    this.hasMoreHistory = true,
    this.loadingHistory = false,
    this.historyError,
    this.lastSeq = 0,
    this.totalMessages = 0,
    this.historyLoaded = false,
  });

  /// Transcript rows, oldest → newest.
  final List<ChatMessage> messages;
  final String streamingText;
  final bool isStreaming;

  /// A run is active on the server for this session.
  final bool isProcessing;
  final DateTime? runStartedAt;
  final String? statusText;
  final List<PendingPermission> pendingPermissions;

  /// New transcript content arrived while the user was scrolled up.
  final int unreadCount;

  /// Whether the list should auto-follow new content (user is at the bottom).
  final bool following;

  final bool hasMoreHistory;
  final bool loadingHistory;
  final String? historyError;

  /// Highest live `seq` seen for this session; sent back on `chat.subscribe`
  /// to replay exactly the frames missed across a reconnect.
  final int lastSeq;

  final int totalMessages;

  /// Whether the first history page has loaded at least once.
  final bool historyLoaded;

  ChatState copyWith({
    List<ChatMessage>? messages,
    String? streamingText,
    bool? isStreaming,
    bool? isProcessing,
    DateTime? runStartedAt,
    bool clearRunStartedAt = false,
    String? statusText,
    bool clearStatusText = false,
    List<PendingPermission>? pendingPermissions,
    int? unreadCount,
    bool? following,
    bool? hasMoreHistory,
    bool? loadingHistory,
    String? historyError,
    bool clearHistoryError = false,
    int? lastSeq,
    int? totalMessages,
    bool? historyLoaded,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      streamingText: streamingText ?? this.streamingText,
      isStreaming: isStreaming ?? this.isStreaming,
      isProcessing: isProcessing ?? this.isProcessing,
      runStartedAt: clearRunStartedAt ? null : (runStartedAt ?? this.runStartedAt),
      statusText: clearStatusText ? null : (statusText ?? this.statusText),
      pendingPermissions: pendingPermissions ?? this.pendingPermissions,
      unreadCount: unreadCount ?? this.unreadCount,
      following: following ?? this.following,
      hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
      loadingHistory: loadingHistory ?? this.loadingHistory,
      historyError: clearHistoryError ? null : (historyError ?? this.historyError),
      lastSeq: lastSeq ?? this.lastSeq,
      totalMessages: totalMessages ?? this.totalMessages,
      historyLoaded: historyLoaded ?? this.historyLoaded,
    );
  }
}

/// Kinds that become transcript rows (everything else is lifecycle/UI state).
bool isTranscriptKind(String kind) {
  switch (kind) {
    case ServerEventKind.text:
    case ServerEventKind.toolUse:
    case ServerEventKind.toolResult:
    case ServerEventKind.thinking:
    case ServerEventKind.error:
      return true;
    default:
      return false;
  }
}

/// Pure reducer applying one server frame (or synthetic socket event) to a
/// chat state. Mirrors the web client's semantics: `stream_delta` accumulates,
/// only `complete` ends a run, permissions live outside the transcript.
ChatState reduceChatEvent(ChatState state, ServerEvent event) {
  var next = state;

  if (event.seq != null && event.seq! > state.lastSeq) {
    next = next.copyWith(lastSeq: event.seq);
  }

  final hadNewContent = _applyFrame(event, next, (updated) => next = updated);

  if (hadNewContent && !next.following) {
    next = next.copyWith(unreadCount: next.unreadCount + 1);
  }
  return next;
}

/// Returns true when the event added visible transcript content.
bool _applyFrame(
  ServerEvent event,
  ChatState state,
  void Function(ChatState updated) update,
) {
  switch (event.kind) {
    case ServerEventKind.streamDelta:
      final text = event.content ?? '';
      if (text.isEmpty) return false;
      final wasStreaming = state.isStreaming;
      update(
        state.copyWith(
          streamingText: state.streamingText + text,
          isStreaming: true,
          isProcessing: true,
          runStartedAt: wasStreaming ? null : DateTime.now(),
        ),
      );
      return true;

    case ServerEventKind.streamEnd:
      final streamed = state.streamingText;
      var messages = state.messages;
      if (streamed.isNotEmpty) {
        messages = _appendDeduped(messages, _streamedMessage(streamed));
      }
      update(
        state.copyWith(
          messages: messages,
          streamingText: '',
          isStreaming: false,
        ),
      );
      return streamed.isNotEmpty;

    case ServerEventKind.complete:
      var messages = state.messages;
      if (state.streamingText.isNotEmpty) {
        messages = _appendDeduped(messages, _streamedMessage(state.streamingText));
      }
      update(
        state.copyWith(
          messages: messages,
          streamingText: '',
          isStreaming: false,
          isProcessing: false,
          pendingPermissions: const [],
          clearRunStartedAt: true,
          clearStatusText: true,
        ),
      );
      return state.streamingText.isNotEmpty;

    case ServerEventKind.chatSubscribed:
      update(
        state.copyWith(
          isProcessing: event.isProcessing,
          runStartedAt: event.isProcessing && !state.isProcessing ? DateTime.now() : null,
          pendingPermissions: _permissionsFromAck(event),
          lastSeq: event.lastSeq > state.lastSeq ? event.lastSeq : state.lastSeq,
        ),
      );
      return false;

    case ServerEventKind.permissionRequest:
      final requestId = event.requestId;
      if (requestId == null) return false;
      if (state.pendingPermissions.any((p) => p.requestId == requestId)) return false;
      update(
        state.copyWith(
          pendingPermissions: [
            ...state.pendingPermissions,
            PendingPermission(
              requestId: requestId,
              toolName: event.toolName ?? 'UnknownTool',
              input: event.input,
            ),
          ],
          isProcessing: true,
        ),
      );
      return false;

    case ServerEventKind.permissionResolved:
    case ServerEventKind.permissionCancelled:
      final requestId = event.requestId;
      update(
        state.copyWith(
          pendingPermissions: requestId == null
              ? state.pendingPermissions
              : state.pendingPermissions
                  .where((p) => p.requestId != requestId)
                  .toList(growable: false),
        ),
      );
      return false;

    case ServerEventKind.status:
      update(state.copyWith(statusText: event.statusText));
      return false;

    case ServerEventKind.toolResult:
      final merged = _mergeToolResult(state.messages, event);
      if (identical(merged, state.messages)) return false;
      update(state.copyWith(messages: merged, isProcessing: true));
      return true;

    case ServerEventKind.protocolError:
      update(
        state.copyWith(
          isProcessing: false,
          isStreaming: false,
          streamingText: '',
          clearRunStartedAt: true,
          messages: _appendDeduped(
            state.messages,
            ChatMessage(
              id: 'protocol_error_${DateTime.now().millisecondsSinceEpoch}',
              kind: ServerEventKind.error,
              timestamp: DateTime.now().toIso8601String(),
              content: event.errorMessage ?? '请求失败',
            ),
          ),
        ),
      );
      return true;

    case ServerEventKind.error:
    case ServerEventKind.text:
    case ServerEventKind.thinking:
    case ServerEventKind.toolUse:
      if (event.raw['id'] == null) return false;
      final message = ChatMessage.fromJson(event.raw);
      final messages = _appendDeduped(state.messages, message);
      if (identical(messages, state.messages)) return false;
      update(state.copyWith(messages: messages, isProcessing: true));
      return true;

    case ServerEventKind.historyTruncated:
    case ServerEventKind.sessionCreated:
    case ServerEventKind.sessionUpserted:
    case ServerEventKind.loadingProgress:
    case ServerEventKind.taskNotification:
      return false;

    default:
      return false;
  }
}

ChatMessage _streamedMessage(String text) => ChatMessage(
      id: 'stream_${DateTime.now().microsecondsSinceEpoch}',
      kind: ServerEventKind.text,
      timestamp: DateTime.now().toIso8601String(),
      role: 'assistant',
      content: text,
    );

List<ChatMessage> _appendDeduped(List<ChatMessage> messages, ChatMessage message) {
  if (messages.any((m) => m.id == message.id)) return messages;
  return [...messages, message];
}

/// `tool_result` rows either complete an existing `tool_use` (matched by
/// `toolId`) or stand alone in the transcript.
List<ChatMessage> _mergeToolResult(List<ChatMessage> messages, ServerEvent event) {
  final toolId = event.toolId;
  final resultContent = event.toolResult?['content'] as String?;
  final isError = event.isError;

  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (message.kind == ServerEventKind.toolUse &&
        toolId != null &&
        message.toolId == toolId &&
        message.toolResultContent == null) {
      final updated = message.copyWith(toolResultContent: resultContent, isError: isError);
      return [...messages.sublist(0, i), updated, ...messages.sublist(i + 1)];
    }
  }

  return _appendDeduped(
    messages,
    ChatMessage.fromJson(event.raw),
  );
}

List<PendingPermission> _permissionsFromAck(ServerEvent event) {
  return event.pendingPermissions
      .map((raw) => PendingPermission(
            requestId: '${raw['requestId']}',
            toolName: (raw['toolName'] as String?) ?? 'UnknownTool',
            input: raw['input'],
          ))
      .where((permission) => permission.requestId.isNotEmpty)
      .toList(growable: false);
}

/// Mirrors the web's `buildClaudeToolPermissionEntry`: Bash keeps the first
/// command word (git keeps two), everything else is the bare tool name.
String buildPermissionRememberEntry(String? toolName, dynamic input) {
  if (toolName == null) return '';
  if (toolName != 'Bash') return toolName;

  var parsed = input;
  if (input is String) {
    try {
      parsed = jsonDecode(input);
    } catch (_) {
      return toolName;
    }
  }
  final command = parsed is Map && parsed['command'] is String
      ? (parsed['command'] as String).trim()
      : '';
  if (command.isEmpty) return toolName;

  final tokens = command.split(RegExp(r'\s+'));
  if (tokens.isEmpty || tokens.first.isEmpty) return toolName;
  if (tokens.first == 'git' && tokens.length > 1) {
    return 'Bash(${tokens[0]} ${tokens[1]}:*)';
  }
  return 'Bash(${tokens[0]}:*)';
}
