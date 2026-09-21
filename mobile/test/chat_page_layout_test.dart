import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudcli_mobile/app/theme/app_theme.dart';
import 'package:cloudcli_mobile/core/models/chat_message.dart';
import 'package:cloudcli_mobile/core/providers.dart';
import 'package:cloudcli_mobile/features/chat/chat_controller.dart';
import 'package:cloudcli_mobile/features/chat/chat_page.dart';
import 'package:cloudcli_mobile/features/chat/chat_reducer.dart';
import 'package:cloudcli_mobile/features/chat/widgets/composer.dart';

void main() {
  testWidgets(
      'ChatPage layout: ListView takes body, Composer is at bottom, lifts on keyboard',
      (tester) async {
    final userMsg = ChatMessage(
      id: 'm1',
      kind: 'text',
      timestamp: DateTime.now().toIso8601String(),
      role: 'user',
      content: '用户发送的消息',
    );
    final assistantMsg = ChatMessage(
      id: 'm2',
      kind: 'text',
      timestamp: DateTime.now().toIso8601String(),
      role: 'assistant',
      content: '这是助手回复的内容',
    );

    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3.0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatControllerProvider('s1').overrideWith(
            () => _FakeChatController(
              's1',
              ChatState(
                historyLoaded: true,
                messages: [userMsg, assistantMsg],
              ),
            ),
          ),
          socketConnectedProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: ThemeMode.light,
          home: const ChatPage(
            sessionId: 's1',
            title: 'Flutter 重做 Cloud CLI 手机 App 与绘图',
            subtitle: 'claudecodeui',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final appBarRect = tester.getRect(find.byType(AppBar));
    final composerRect = tester.getRect(find.byType(Composer));
    final listViewRect = tester.getRect(find.byType(ListView));

    expect(appBarRect.height, 56.0);

    // Messages must be visible
    expect(find.text('用户发送的消息'), findsOneWidget);
    expect(find.text('这是助手回复的内容'), findsOneWidget);

    // Composer is at the bottom of the screen
    expect(composerRect.bottom, 852.0);
    expect(listViewRect.bottom, composerRect.top);

    // Virtual keyboard appearance (height 336 logical px)
    tester.view.viewInsets = FakeViewPadding(bottom: 336 * 3.0);
    await tester.pumpAndSettle();

    final composerRectWithKeyboard = tester.getRect(find.byType(Composer));
    final listViewRectWithKeyboard = tester.getRect(find.byType(ListView));

    // Composer is lifted up right on top of the keyboard (852 - 336 = 516)
    expect(composerRectWithKeyboard.bottom, closeTo(516.0, 1.0));
    expect(listViewRectWithKeyboard.bottom, composerRectWithKeyboard.top);
  });
}

class _FakeChatController extends ChatController {
  _FakeChatController(super.sessionId, this._initial);
  final ChatState _initial;

  @override
  ChatState build() => _initial;
}
