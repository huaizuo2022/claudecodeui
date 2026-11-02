import 'dart:convert';

/// One image attached to a user turn. Providers describe the same image in two
/// shapes: Claude history stores an inline `data:` URL, while uploaded
/// attachments carry the absolute path inside the server asset store.
class ChatImage {
  const ChatImage({this.data, this.path, this.name});

  /// Inline `data:image/...;base64,...` URL, when the provider stores bytes.
  final String? data;

  /// Absolute or workspace-relative path on the server.
  final String? path;

  /// The user's original filename, used for display only.
  final String? name;

  bool get hasInlineData => data != null && data!.startsWith('data:');

  /// Filename inside the global asset store (the last path segment).
  String get storedFilename => (path ?? '').split(RegExp(r'[\\/]')).last;

  bool get isEmpty => data == null && path == null;

  factory ChatImage.fromJson(Object? raw) {
    if (raw is String) {
      final value = raw.trim();
      if (value.isEmpty) return const ChatImage();
      return value.startsWith('data:')
          ? ChatImage(data: value)
          : ChatImage(path: value);
    }
    if (raw is Map) {
      String? read(String key) {
        final value = raw[key];
        if (value is! String) return null;
        final trimmed = value.trim();
        return trimmed.isEmpty ? null : trimmed;
      }

      return ChatImage(
        data: read('data'),
        path: read('path'),
        name: read('name'),
      );
    }
    return const ChatImage();
  }

  Map<String, dynamic> toJson() => {
    if (data != null) 'data': data,
    if (path != null) 'path': path,
    if (name != null) 'name': name,
  };
}

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
    this.images = const [],
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

  /// Images attached to a user turn, in either provider shape (inline data URL
  /// or server path).
  final List<ChatImage> images;

  /// Path-backed image sources, kept for export and older callers.
  List<String> get imagePaths => [
    for (final image in images)
      if (image.path != null) image.path!,
  ];

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
      toolResultContent: rawResult is Map
          ? rawResult['content'] as String?
          : null,
      isError:
          json['isError'] == true ||
          (rawResult is Map && rawResult['isError'] == true),
      requestId: json['requestId'] as String?,
      input: json['input'],
      images: _images(json['images']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'timestamp': timestamp,
    if (sessionId != null) 'sessionId': sessionId,
    if (role != null) 'role': role,
    if (content != null) 'content': content,
    if (toolName != null) 'toolName': toolName,
    if (toolInput != null) 'toolInput': toolInput,
    if (toolId != null) 'toolId': toolId,
    if (toolResultContent != null || isError)
      'toolResult': {
        if (toolResultContent != null) 'content': toolResultContent,
        'isError': isError,
      },
    'isError': isError,
    if (requestId != null) 'requestId': requestId,
    if (input != null) 'input': input,
    if (images.isNotEmpty)
      'images': [for (final image in images) image.toJson()],
  };

  /// History `images` is loosely typed: bare strings, `{path, name}` records
  /// (uploads) or `{data}` records (Claude base64 history).
  static List<ChatImage> _images(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (ChatImage.fromJson(entry) case final image when !image.isEmpty)
          image,
    ];
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
    for (final key in const [
      'file_path',
      'path',
      'command',
      'pattern',
      'url',
      'query',
    ]) {
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
  }) => ChatMessage(
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
    images: images,
  );
}
