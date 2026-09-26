import 'package:flutter_test/flutter_test.dart';
import 'package:cloudcli_mobile/core/models/chat_message.dart';
import 'package:cloudcli_mobile/features/chat/utils/session_export.dart';

void main() {
  group('SessionExport', () {
    test('exports user and assistant messages to markdown', () {
      final messages = [
        ChatMessage(
          id: '1',
          kind: 'message',
          timestamp: '2026-09-24T10:00:00Z',
          role: 'user',
          content: 'Hello Antigravity',
        ),
        ChatMessage(
          id: '2',
          kind: 'message',
          timestamp: '2026-09-24T10:00:05Z',
          role: 'assistant',
          content: 'Hello! How can I help you today?',
        ),
      ];

      final md = SessionExport.toMarkdown(
        title: '测试会话',
        provider: 'Claude',
        messages: messages,
        exportedAt: DateTime.utc(2026, 9, 24, 10, 5),
      );

      expect(md, contains('# 测试会话'));
      expect(md, contains('### 👤 用户 (User)'));
      expect(md, contains('Hello Antigravity'));
      expect(md, contains('### 🤖 助手 (Claude)'));
      expect(md, contains('Hello! How can I help you today?'));
    });

    test('exports tool invocations with input and results', () {
      final messages = [
        ChatMessage(
          id: 'tool_1',
          kind: 'tool_use',
          timestamp: '2026-09-24T10:00:01Z',
          toolName: 'Bash',
          toolInput: {'command': 'ls -la'},
          toolResultContent: 'total 0\n-rw-r--r-- 1 user staff 0 file.txt',
        ),
      ];

      final md = SessionExport.toMarkdown(
        title: 'Tool Test',
        provider: 'Claude',
        messages: messages,
      );

      expect(md, contains('**工具调用: `Bash`**'));
      expect(md, contains('ls -la'));
      expect(md, contains('total 0'));
    });
  });
}
