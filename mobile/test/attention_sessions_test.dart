import 'dart:async';
import 'dart:convert';

import 'package:cloudcli_mobile/core/providers.dart';
import 'package:cloudcli_mobile/core/ws/chat_socket.dart';
import 'package:cloudcli_mobile/features/sessions/session_list_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeSink implements WebSocketSink {
  @override
  void add(dynamic data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  Future<void> get done => Future<void>.value();
}

class _FrameChannel with StreamChannelMixin implements WebSocketChannel {
  final controller = StreamController<dynamic>.broadcast();

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  WebSocketSink get sink => _FakeSink();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;
}

void main() {
  late _FrameChannel channel;
  late ProviderContainer container;

  setUp(() {
    activeViewedSessionId = null;
    channel = _FrameChannel();
    container = ProviderContainer(
      overrides: [
        chatSocketProvider.overrideWithValue(ChatSocket(channelForTesting: channel)),
      ],
    );
    addTearDown(container.dispose);
    container.read(chatSocketProvider).connect('ws://test/ws');
    // Warm the provider so its socket listener is registered before any frame
    // delivery (Notifier.build is lazy).
    container.read(attentionSessionsProvider);
  });

  Future<void> deliver(Map<String, dynamic> frame) async {
    // `_open` completes asynchronously; frames pushed before the socket is
    // listening on the channel stream are silently dropped by the broadcast.
    final socket = container.read(chatSocketProvider);
    for (var i = 0; i < 50 && !socket.isConnected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(socket.isConnected, isTrue);
    channel.controller.add(jsonEncode(frame));
    // The socket forwards frames through a broadcast stream; let the
    // microtask drain so listeners see them.
    await Future<void>.delayed(Duration.zero);
  }

  Set<String> attentionIds() => container.read(attentionSessionsProvider);

  test('starts empty and markAttention adds a session', () {
    expect(attentionIds(), isEmpty);
    container.read(attentionSessionsProvider.notifier).markAttention('s1');
    expect(attentionIds(), {'s1'});
  });

  test('clearAttention drops the session', () {
    container.read(attentionSessionsProvider.notifier).markAttention('s1');
    container.read(attentionSessionsProvider.notifier).clearAttention('s1');
    expect(attentionIds(), isEmpty);
  });

  test('markAttention never marks the session currently being viewed', () {
    activeViewedSessionId = 's1';
    container.read(attentionSessionsProvider.notifier).markAttention('s1');
    container.read(attentionSessionsProvider.notifier).markAttention('s2');
    expect(attentionIds(), {'s2'}, reason: 'viewed session stays unmarked');
  });

  test('a session_upserted frame for a background session marks attention', () async {
    await deliver({
      'kind': 'session_upserted',
      'sessionId': 'bg-session',
      'session': {'id': 'bg-session', 'summary': '新消息'},
    });
    expect(attentionIds(), contains('bg-session'));
  });

  test('a session_upserted frame for the viewed session does not mark', () async {
    activeViewedSessionId = 'viewed';
    await deliver({
      'kind': 'session_upserted',
      'sessionId': 'viewed',
      'session': {'id': 'viewed', 'summary': '新消息'},
    });
    expect(attentionIds(), isEmpty);
  });

  test('a content frame for a background session marks attention', () async {
    await deliver({
      'kind': 'tool_result',
      'sessionId': 'bg-session',
      'content': 'done',
    });
    expect(attentionIds(), contains('bg-session'));
  });

  test('lifecycle frames like status never mark attention', () async {
    await deliver({'kind': 'status', 'sessionId': 's1', 'text': 'planning'});
    await deliver({'kind': 'stream_end', 'sessionId': 's1'});
    await deliver({'kind': 'chat_subscribed', 'sessionId': 's1', 'isProcessing': true});
    expect(attentionIds(), isEmpty);
  });
}