import 'dart:async';
import 'package:cloudcli_mobile/core/ws/chat_socket.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeWebSocketSink implements WebSocketSink {
  final sent = <dynamic>[];
  bool isClosed = false;

  @override
  void add(dynamic data) {
    sent.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    isClosed = true;
  }

  @override
  Future<void> get done => Future<void>.value();
}

class _FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  _FakeWebSocketChannel() {
    _sink = _FakeWebSocketSink();
    _controller = StreamController<dynamic>.broadcast();
  }

  late final _FakeWebSocketSink _sink;
  late final StreamController<dynamic> _controller;

  @override
  WebSocketSink get sink => _sink;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

void main() {
  group('ChatSocket frame buffering and reconnection', () {
    test('buffers chat.subscribe when disconnected and flushes upon connection', () async {
      final fakeChannel = _FakeWebSocketChannel();
      final socket = ChatSocket(channelForTesting: fakeChannel);

      // Send subscription while disconnected
      final queued = socket.send({
        'type': 'chat.subscribe',
        'sessions': [
          {'sessionId': 's1', 'lastSeq': 0}
        ],
      });
      expect(queued, isTrue);
      expect(fakeChannel._sink.sent, isEmpty);

      // Connect
      socket.connect('ws://test/ws');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // After connection, the buffered subscription should have been sent
      expect(socket.isConnected, isTrue);
      expect(fakeChannel._sink.sent.length, 1);
      expect(fakeChannel._sink.sent.first, contains('chat.subscribe'));

      socket.close();
    });

    test('handleAppResume proactively reconnects', () async {
      final fakeChannel = _FakeWebSocketChannel();
      final socket = ChatSocket(channelForTesting: fakeChannel);

      socket.connect('ws://test/ws');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(socket.isConnected, isTrue);

      // Resume triggers reconnect even if state was connected
      socket.handleAppResume();
      expect(socket.state, SocketConnectionState.connecting);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(socket.isConnected, isTrue);

      socket.close();
    });
  });
}
