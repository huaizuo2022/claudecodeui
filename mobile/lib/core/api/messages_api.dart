import '../models/chat_message.dart';
import 'api_client.dart';

class MessagesPage {
  const MessagesPage({
    required this.messages,
    required this.total,
    required this.hasMore,
    required this.offset,
  });

  /// Oldest → newest inside the page, matching the transcript order.
  final List<ChatMessage> messages;
  final int total;
  final bool hasMore;
  final int offset;
}

class MessagesApi {
  MessagesApi(this._client);

  final ApiClient _client;

  /// `GET /api/providers/sessions/:id/messages`. `limit` always pairs with an
  /// explicit `offset` so a refresh can never degrade into a full transcript.
  Future<MessagesPage> fetchHistory(
    String sessionId, {
    int limit = 60,
    int offset = 0,
  }) async {
    final body = await _client.getJson(
      'providers/sessions/$sessionId/messages',
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    if (body is! Map || body['messages'] is! List) {
      throw ApiException(message: '历史消息响应格式异常');
    }
    return MessagesPage(
      messages: (body['messages'] as List)
          .whereType<Map>()
          .map(ChatMessage.fromJson)
          .toList(growable: false),
      total: body['total'] is num ? (body['total'] as num).toInt() : 0,
      hasMore: body['hasMore'] == true,
      offset: body['offset'] is num ? (body['offset'] as num).toInt() : offset,
    );
  }
}
