import 'package:cloudcli_mobile/core/ws/server_event.dart';
import 'package:cloudcli_mobile/features/chat/chat_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

ServerEvent _event(Map<String, dynamic> frame) => ServerEvent.fromJson(frame);

void main() {
  group('streaming lifecycle', () {
    test('deltas accumulate, stream_end finalizes, complete ends the run', () {
      var state = const ChatState();
      state = reduceChatEvent(
        state,
        _event({'kind': 'stream_delta', 'content': '你好'}),
      );
      state = reduceChatEvent(
        state,
        _event({'kind': 'stream_delta', 'content': '，世界'}),
      );
      expect(state.streamingText, '你好，世界');
      expect(state.isStreaming, isTrue);
      expect(state.isProcessing, isTrue);
      expect(state.messages, isEmpty);

      state = reduceChatEvent(state, _event({'kind': 'stream_end'}));
      expect(state.streamingText, isEmpty);
      expect(state.isStreaming, isFalse);
      expect(state.messages.length, 1);
      expect(state.messages.last.content, '你好，世界');
      expect(state.messages.last.isUser, isFalse);

      state = reduceChatEvent(
        state,
        _event({'kind': 'complete', 'success': true}),
      );
      expect(state.isProcessing, isFalse);
    });

    test('an unfinished stream is flushed by complete', () {
      var state = const ChatState();
      state = reduceChatEvent(state, _event({'kind': 'stream_delta', 'content': '部分'}));
      state = reduceChatEvent(state, _event({'kind': 'complete'}));
      expect(state.messages.last.content, '部分');
      expect(state.isProcessing, isFalse);
    });
  });

  group('transcript rows', () {
    test('rows append and dedupe by id', () {
      var state = const ChatState();
      final frame = {
        'id': 'm1',
        'kind': 'text',
        'role': 'assistant',
        'content': '答案',
      };
      state = reduceChatEvent(state, _event(frame));
      state = reduceChatEvent(state, _event(frame));
      expect(state.messages.length, 1);
      expect(state.lastSeq, 0);
    });

    test('text rows without id get fallback id instead of being dropped', () {
      var state = const ChatState();
      state = reduceChatEvent(
        state,
        _event({
          'kind': 'text',
          'role': 'assistant',
          'content': '无ID消息',
        }),
      );
      expect(state.messages.length, 1);
      expect(state.messages.first.content, '无ID消息');
      expect(state.messages.first.id, startsWith('msg_'));
    });

    test('seq is tracked for replay', () {
      var state = const ChatState();
      state = reduceChatEvent(state, _event({'id': 'm1', 'kind': 'text', 'seq': 5}));
      state = reduceChatEvent(state, _event({'kind': 'stream_delta', 'content': 'x', 'seq': 9}));
      state = reduceChatEvent(state, _event({'kind': 'stream_delta', 'content': 'y', 'seq': 7}));
      expect(state.lastSeq, 9);
    });

    test('tool_result completes the matching tool_use row', () {
      var state = const ChatState();
      state = reduceChatEvent(
        state,
        _event({
          'id': 't1',
          'kind': 'tool_use',
          'toolName': 'Bash',
          'toolId': 'tool-9',
          'toolInput': {'command': 'npm test'},
        }),
      );
      state = reduceChatEvent(
        state,
        _event({
          'id': 'r1',
          'kind': 'tool_result',
          'toolId': 'tool-9',
          'toolResult': {'content': 'ok', 'isError': false},
        }),
      );
      expect(state.messages.length, 1);
      expect(state.messages.last.toolResultContent, 'ok');
      expect(state.messages.last.isError, isFalse);
    });

    test('an unmatched tool_result stands alone', () {
      var state = const ChatState();
      state = reduceChatEvent(
        state,
        _event({
          'id': 'r1',
          'kind': 'tool_result',
          'toolId': 'tool-404',
          'toolResult': {'content': 'boom', 'isError': true},
        }),
      );
      expect(state.messages.length, 1);
      expect(state.messages.last.isError, isTrue);
    });
  });

  group('unread counting', () {
    test('content while scrolled up counts; following resets it', () {
      var state = const ChatState(following: false);
      state = reduceChatEvent(state, _event({'id': 'm1', 'kind': 'text'}));
      state = reduceChatEvent(state, _event({'id': 'm2', 'kind': 'text'}));
      expect(state.unreadCount, 2);

      state = state.copyWith(following: true, unreadCount: 0);
      state = reduceChatEvent(state, _event({'id': 'm3', 'kind': 'text'}));
      expect(state.unreadCount, 0);
    });

    test('lifecycle frames do not count as unread', () {
      var state = const ChatState(following: false);
      state = reduceChatEvent(state, _event({'kind': 'status', 'text': 'busy'}));
      state = reduceChatEvent(state, _event({'kind': 'chat_subscribed', 'isProcessing': true}));
      expect(state.unreadCount, 0);
      expect(state.isProcessing, isTrue);
    });
  });

  group('permissions', () {
    test('request adds a prompt once; resolved removes it', () {
      var state = const ChatState();
      final frame = {
        'kind': 'permission_request',
        'requestId': 'req-1',
        'toolName': 'Bash',
        'input': {'command': 'rm -rf /tmp/x'},
      };
      state = reduceChatEvent(state, _event(frame));
      state = reduceChatEvent(state, _event(frame));
      expect(state.pendingPermissions.length, 1);
      expect(state.pendingPermissions.first.toolName, 'Bash');

      state = reduceChatEvent(
        state,
        _event({'kind': 'permission_resolved', 'requestId': 'req-1'}),
      );
      expect(state.pendingPermissions, isEmpty);
    });

    test('chat_subscribed restores pending permissions', () {
      final state = reduceChatEvent(
        const ChatState(),
        _event({
          'kind': 'chat_subscribed',
          'isProcessing': true,
          'lastSeq': 12,
          'pendingPermissions': [
            {'requestId': 'req-9', 'toolName': 'Bash', 'input': {'command': 'ls'}},
          ],
        }),
      );
      expect(state.isProcessing, isTrue);
      expect(state.lastSeq, 12);
      expect(state.pendingPermissions.length, 1);
    });
  });

  group('permission remember entry', () {
    test('Bash keeps the first command word, git keeps two', () {
      expect(
        buildPermissionRememberEntry('Bash', {'command': 'git push origin main'}),
        'Bash(git push:*)',
      );
      expect(
        buildPermissionRememberEntry('Bash', {'command': 'npm run build'}),
        'Bash(npm:*)',
      );
      expect(buildPermissionRememberEntry('Bash', '{"command": "ls -la"}'), 'Bash(ls:*)');
      expect(buildPermissionRememberEntry('Read', null), 'Read');
    });
  });

  test('protocol_error ends the run and renders a row', () {
    var state = const ChatState().copyWith(isProcessing: true);
    state = reduceChatEvent(
      state,
      _event({'kind': 'protocol_error', 'code': 'SESSION_NOT_FOUND', 'error': '会话不存在'}),
    );
    expect(state.isProcessing, isFalse);
    expect(state.messages.last.kind, ServerEventKind.error);
    expect(state.messages.last.content, '会话不存在');
  });
}
