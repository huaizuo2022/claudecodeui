/// Every `kind` the server can send down the chat socket, plus the synthetic
/// ones this app generates for socket lifecycle.
class ServerEventKind {
  ServerEventKind._();

  // Provider transcript rows.
  static const text = 'text';
  static const toolUse = 'tool_use';
  static const toolResult = 'tool_result';
  static const thinking = 'thinking';
  static const streamDelta = 'stream_delta';
  static const streamEnd = 'stream_end';
  static const error = 'error';
  static const complete = 'complete';
  static const status = 'status';

  // Permission lifecycle.
  static const permissionRequest = 'permission_request';
  static const permissionResolved = 'permission_resolved';
  static const permissionCancelled = 'permission_cancelled';

  // Session lifecycle.
  static const sessionCreated = 'session_created';
  static const historyTruncated = 'history_truncated';
  static const taskNotification = 'task_notification';

  // Gateway events.
  static const chatSubscribed = 'chat_subscribed';
  static const sessionUpserted = 'session_upserted';
  static const loadingProgress = 'loading_progress';
  static const protocolError = 'protocol_error';
}

/// Thin typed view over one server frame. Keeps the raw map so fields added
/// upstream degrade gracefully instead of disappearing.
class ServerEvent {
  ServerEvent.fromJson(this.raw)
      : kind = raw['kind'] as String? ?? '',
        seq = raw['seq'] is num ? (raw['seq'] as num).toInt() : null;

  final Map<dynamic, dynamic> raw;
  final String kind;
  final int? seq;

  String? get sessionId => raw['sessionId'] as String?;
  String? get role => raw['role'] as String?;
  String? get content => raw['content'] as String?;
  String? get toolName => raw['toolName'] as String?;
  String? get toolId => raw['toolId'] as String?;
  dynamic get toolInput => raw['toolInput'];
  String? get requestId => raw['requestId'] as String?;
  dynamic get input => raw['input'];
  String? get anchorId => raw['anchorId'] as String?;
  String? get newSessionId => raw['newSessionId'] as String?;
  String? get statusText => raw['text'] as String?;
  String? get errorCode => raw['code'] as String?;
  String? get errorMessage => (raw['error'] ?? raw['message']) as String?;

  bool get isProcessing => raw['isProcessing'] == true;
  bool get aborted => raw['aborted'] == true;
  bool get success => raw['success'] != false;

  int get lastSeq => raw['lastSeq'] is num ? (raw['lastSeq'] as num).toInt() : 0;

  List<Map<dynamic, dynamic>> get pendingPermissions {
    final rawList = raw['pendingPermissions'];
    if (rawList is! List) return const [];
    return rawList.whereType<Map>().toList(growable: false);
  }

  /// Tool result payload nested on `tool_result` rows.
  Map<dynamic, dynamic>? get toolResult =>
      raw['toolResult'] is Map ? raw['toolResult'] as Map<dynamic, dynamic> : null;

  bool get isError => raw['isError'] == true || toolResult?['isError'] == true;
}
