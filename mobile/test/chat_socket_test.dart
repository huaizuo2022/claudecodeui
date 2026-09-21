import 'dart:async';

import 'package:cloudcli_mobile/core/ws/chat_socket.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeSink implements WebSocketSink {
  final sent = <dynamic>[];

  @override
  void add(dynamic data) => sent.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  Future<void> get done => Future<void>.value();
}

class _FakeChannel with StreamChannelMixin implements WebSocketChannel {
  _FakeChannel({Future<void>? ready}) : _ready = ready ?? Future<void>.value();

  final Future<void> _ready;
  final $$sink = _FakeSink();
  final _streamController = StreamController<dynamic>.broadcast();

  @override
  Stream<dynamic> get stream => _streamController.stream;

  @override
  Future<void> get ready => _ready;

  @override
  WebSocketSink get sink => $$sink;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;
}

void main() {
  test('action frames are refused while disconnected, subscriptions buffer', () {
    final socket = ChatSocket();
    expect(socket.send({'type': 'chat.send', 'content': 'hi'}), isFalse);
    expect(socket.send({'type': 'chat.abort'}), isFalse);
    expect(socket.send({'type': 'chat.subscribe', 'sessions': []}), isTrue,
        reason: 'subscriptions may wait for the next connect');
  });

  test('sendWhenConnected waits for the handshake and delivers the frame', () async {
    final channel = _FakeChannel();
    final socket = ChatSocket(channelForTesting: channel);
    socket.connect('ws://example.com/ws');

    final sent = await socket.sendWhenConnected({'type': 'chat.send', 'content': 'hi'});
    expect(sent, isTrue);
    expect(channel.$$sink.sent, hasLength(1));
  });

  test('sendWhenConnected times out and reports failure when the socket never connects', () async {
    final neverReady = Completer<void>();
    final channel = _FakeChannel(ready: neverReady.future);
    final socket = ChatSocket(channelForTesting: channel);
    // Trigger the (never-completing) handshake.
    socket.connect('ws://example.com/ws');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final sent = await socket.sendWhenConnected(
      {'type': 'chat.send', 'content': 'hi'},
      timeout: const Duration(milliseconds: 200),
    );
    expect(sent, isFalse);
    expect(channel.$$sink.sent, isEmpty);
  });

  test('sendWhenConnected fails fast when no URL is configured', () async {
    final socket = ChatSocket();
    final sent = await socket.sendWhenConnected({'type': 'chat.send'});
    expect(sent, isFalse);
  });
}