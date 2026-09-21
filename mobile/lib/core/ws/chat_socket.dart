import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../util/logger.dart';

enum SocketConnectionState { disconnected, connecting, connected }

/// The app's single `/ws` connection, mirroring the web client: one socket for
/// everything, flat 3s reconnect, no send queue — a frame sent while offline is
/// logged and dropped.
class ChatSocket {
  ChatSocket({WebSocketChannel? channelForTesting})
      : _channelForTesting = channelForTesting;

  static const _log = Logger('ws');
  static const _reconnectDelay = Duration(seconds: 3);

  final WebSocketChannel? _channelForTesting;
  final _listeners = <void Function(Map<dynamic, dynamic> frame)>{};
  final _stateController = StreamController<SocketConnectionState>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  String? _url;
  bool _intentionallyClosed = false;
  int _connectGeneration = 0;
  SocketConnectionState _state = SocketConnectionState.disconnected;

  /// Notified on every state transition, so providers can mirror the current
  /// value instead of watching a broadcast stream (which drops history).
  void Function(SocketConnectionState state)? onStateChanged;

  SocketConnectionState get state => _state;
  Stream<SocketConnectionState> get states => _stateController.stream;
  bool get isConnected => _state == SocketConnectionState.connected;

  /// Registers a frame listener. The listener receives a synthetic
  /// `{kind: 'socket_connected'}` frame after every (re)connect so it can
  /// re-send its `chat.subscribe`.
  void addListener(void Function(Map<dynamic, dynamic> frame) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(Map<dynamic, dynamic> frame) listener) {
    _listeners.remove(listener);
  }

  void connect(String url) {
    if (_url == url && _state == SocketConnectionState.connected) {
      return;
    }
    _url = url;
    _intentionallyClosed = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectGeneration += 1;
    _open(_connectGeneration);
  }

  void close() {
    _intentionallyClosed = true;
    _connectGeneration += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _url = null;
    _setState(SocketConnectionState.disconnected);
  }

  /// Called when the app returns to the foreground: iOS suspends sockets, so a
  /// live-looking but dead connection gets probed by reconnecting eagerly.
  void handleAppResume() {
    if (_url == null || _intentionallyClosed) return;
    if (_state != SocketConnectionState.connected) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _connectGeneration += 1;
      _open(_connectGeneration);
    }
  }

  bool send(Map<String, dynamic> frame) {
    final channel = _channel;
    if (channel == null || _state != SocketConnectionState.connected) {
      _log.warn('dropping frame while ${_state.name}: ${frame['type']}');
      return false;
    }
    try {
      channel.sink.add(jsonEncode(frame));
      return true;
    } catch (error) {
      _log.error('failed to send ${frame['type']}', error);
      return false;
    }
  }

  Future<void> _open(int generation) async {
    final url = _url;
    if (url == null) return;

    _setState(SocketConnectionState.connecting);
    _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;

    final WebSocketChannel channel;
    if (_channelForTesting != null) {
      channel = _channelForTesting;
    } else {
      channel = WebSocketChannel.connect(Uri.parse(url));
    }

    try {
      // The WebSocket handshake (TCP + TLS + upgrade) completes asynchronously;
      // `ready` succeeds only when the socket is actually usable.
      _log.info('opening generation=$generation url=$url');
      await channel.ready;
      _log.info('ready ok generation=$generation');
    } catch (error) {
      if (_intentionallyClosed || generation != _connectGeneration) return;
      _log.warn('connect failed: $error');
      _scheduleReconnect();
      return;
    }

    // A close() or a newer connect() may have raced this attempt.
    if (_intentionallyClosed || generation != _connectGeneration) {
      await channel.sink.close();
      return;
    }

    _channel = channel;
    _subscription = channel.stream.listen(
      (data) => _onData(data),
      onError: (Object error) {
        _log.warn('socket error: $error');
        _scheduleReconnect();
      },
      onDone: () {
        _log.info('socket closed');
        _scheduleReconnect();
      },
    );
    _setState(SocketConnectionState.connected);
  }

  void _onData(Object data) {
    if (data is! String) return;
    Map<dynamic, dynamic>? frame;
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) frame = decoded;
    } catch (error) {
      _log.warn('bad frame: $error');
      return;
    }
    if (frame == null) return;
    for (final listener in List.of(_listeners)) {
      listener(frame);
    }
  }

  void _scheduleReconnect() {
    if (_intentionallyClosed) return;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _setState(SocketConnectionState.disconnected);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (!_intentionallyClosed && _url != null) {
        _connectGeneration += 1;
        _open(_connectGeneration);
      }
    });
  }

  void _setState(SocketConnectionState next) {
    final becameConnected = next == SocketConnectionState.connected &&
        _state != SocketConnectionState.connected;
    _state = next;
    _stateController.add(next);
    onStateChanged?.call(next);
    if (becameConnected) {
      for (final listener in List.of(_listeners)) {
        listener(const {'kind': 'socket_connected'});
      }
    }
  }
}
