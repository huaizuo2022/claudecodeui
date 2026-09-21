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

  final _pendingFrames = <Map<String, dynamic>>[];

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
    _pendingFrames.clear();
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
    _log.info('app resumed: reconnecting socket');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectGeneration += 1;
    _open(_connectGeneration);
  }

  bool send(Map<String, dynamic> frame) {
    final channel = _channel;
    if (channel == null || _state != SocketConnectionState.connected) {
      // Only subscriptions may wait in the buffer: they are idempotent and
      // re-sent on every connect. Action frames (chat.send, chat.abort, ...)
      // must never sit there — a reconnect flush could re-execute them, and a
      // failed handshake would silently drop them while the UI already shows
      // the optimistic row. Callers use sendWhenConnected and roll back.
      if (frame['type'] == 'chat.subscribe') {
        _log.info('buffering subscription while ${_state.name}');
        _pendingFrames.add(frame);
        return true;
      }
      _log.warn('refusing ${frame['type']} while ${_state.name}');
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

  /// Sends an action frame once the socket is actually able to carry it,
  /// waiting (and driving) the connect for up to [timeout]. Returns false when
  /// the socket could not become ready in time — the caller is expected to
  /// roll back any optimistic UI it already applied. Never buffers the frame.
  Future<bool> sendWhenConnected(
    Map<String, dynamic> frame, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_state == SocketConnectionState.connected) return send(frame);

    if (_url == null) return false;

    _log.info('waiting for the socket before ${frame['type']}');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    // Don't interrupt a handshake that is already in flight; only start one
    // when the socket is fully idle.
    if (_state != SocketConnectionState.connecting) {
      _connectGeneration += 1;
      _open(_connectGeneration);
    }

    final completer = Completer<bool>();
    late StreamSubscription<SocketConnectionState> subscription;
    subscription = _stateController.stream.listen((state) {
      if (state == SocketConnectionState.connected && !completer.isCompleted) {
        subscription.cancel();
        completer.complete(send(frame));
      }
    });

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.complete(false);
      }
    });
    final sent = await completer.future;
    timer.cancel();
    return sent;
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
      await channel.ready.timeout(const Duration(seconds: 10));
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
        // A superseded connection (older generation) closing must not pull
        // the live state down — only the current channel speaks for the socket.
        if (!identical(channel, _channel)) return;
        _log.warn('socket error: $error');
        _scheduleReconnect();
      },
      onDone: () {
        if (!identical(channel, _channel)) return;
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
      final pending = List<Map<String, dynamic>>.from(_pendingFrames);
      _pendingFrames.clear();
      for (final frame in pending) {
        send(frame);
      }
      for (final listener in List.of(_listeners)) {
        listener(const {'kind': 'socket_connected'});
      }
    } else if (next == SocketConnectionState.disconnected) {
      _pendingFrames.retainWhere((f) => f['type'] == 'chat.subscribe');
    }
  }
}
