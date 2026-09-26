import 'package:cloudcli_mobile/app/theme/app_theme.dart';
import 'package:cloudcli_mobile/features/sessions/session_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SessionActionsSheet shows error or snackbar', (tester) async {

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  SessionActionsSheet.show(
                    context,
                    sessionId: 'test-session-123',
                    title: 'Test Session',
                    provider: 'claude',
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('归档或删除会话'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('归档会话'));
    await tester.pumpAndSettle();

    // Check if SnackBar appeared
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
