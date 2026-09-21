import 'dart:convert';

/// One transcript row in the provider-neutral `NormalizedMessage` shape, used
/// for both REST history and realtime frames (they share the envelope).
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.kind,
    required this.timestamp,
    this.sessionId,
    this.role,
    this.content,
    this.toolName,
    this.toolInput,
    this.toolId,
    this.toolResultContent,
    this.isError = false,
    this.requestId,
    this.input,
  });

  final String id;
  final String kind;

  /// ISO timestamp from the server; realtime frames and history both carry it.
  final String timestamp;
  final String? sessionId;
  final String? role;
  final String? content;
  final String? toolName;
  final dynamic toolInput;
  final String? toolId;
  final String? toolResultContent;
  final bool isError;
  final String? requestId;
  final dynamic input;

  factory ChatMessage.fromJson(Map<dynamic, dynamic> json) {
    final rawResult = json['toolResult'];
    return ChatMessage(
      id: '${json['id']}',
      kind: (json['kind'] as String?) ?? '',
      timestamp: (json['timestamp'] as String?) ?? '',
      sessionId: json['sessionId'] as String?,
      role: json['role'] as String?,
      content: json['content'] as String?,
      toolName: json['toolName'] as String?,
      toolInput: json['toolInput'],
      toolId: json['toolId'] as String?,
      toolResultContent: rawResult is Map ? rawResult['content'] as String? : null,
      isError: json['isError'] == true || (rawResult is Map && rawResult['isError'] == true),
      requestId: json['requestId'] as String?,
      input: json['input'],
    );
  }

  bool get isUser => role == 'user';

  /// One-line summary used by tool cards: the most descriptive field of the
  /// tool input, mirroring what the web renderer highlights.
  String get toolSummary {
    Map<dynamic, dynamic>? map;
    final value = toolInput;
    if (value is Map) {
      map = value;
    } else if (value is String && value.trimLeft().startsWith('{')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) map = decoded;
      } catch (_) {
        // Fall through and use the raw string below.
      }
    }
    for (final key in const ['file_path', 'path', 'command', 'pattern', 'url', 'query']) {
      final candidate = map?[key];
      if (candidate is String && candidate.isNotEmpty) return candidate;
    }
    if (value is String && value.isNotEmpty && value.length < 120) return value;
    return '';
  }

  ChatMessage copyWith({
    String? content,
    String? toolResultContent,
    bool? isError,
  }) =>
      ChatMessage(
        id: id,
        kind: kind,
        timestamp: timestamp,
        sessionId: sessionId,
        role: role,
        content: content ?? this.content,
        toolName: toolName,
        toolInput: toolInput,
        toolId: toolId,
        toolResultContent: toolResultContent ?? this.toolResultContent,
        isError: isError ?? this.isError,
        requestId: requestId,
        input: input,
      );
}
