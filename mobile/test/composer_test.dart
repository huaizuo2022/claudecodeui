import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudcli_mobile/app/theme/app_theme.dart';
import 'package:cloudcli_mobile/features/chat/widgets/composer.dart';

void main() {
  Widget buildComposer({
    required bool isProcessing,
    required VoidCallback onAbort,
    required ValueChanged<String> onSend,
    DateTime? runStartedAt,
    String? statusText,
    int messageCount = 0,
  }) {
    return MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: Center(
          child: Composer(
            isProcessing: isProcessing,
            onSend: onSend,
            onAbort: onAbort,
            runStartedAt: runStartedAt,
            statusText: statusText,
            messageCount: messageCount,
          ),
        ),
      ),
    );
  }

  testWidgets('Composer when idle shows send arrow, hides activity tabs', (tester) async {
    await tester.pumpWidget(
      buildComposer(
        isProcessing: false,
        onSend: (_) {},
        onAbort: () {},
        messageCount: 5,
      ),
    );

    // Activity header tabs should not exist
    expect(find.text('停止'), findsNothing);
    expect(find.textContaining('Working'), findsNothing);
    expect(find.textContaining('Thinking'), findsNothing);

    // Send button shows upward arrow
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

    // Message count badge is visible
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('Composer when processing displays activity tab and both stop buttons', (tester) async {
    var abortedCount = 0;
    final startTime = DateTime.now().subtract(const Duration(seconds: 37));

    await tester.pumpWidget(
      buildComposer(
        isProcessing: true,
        onSend: (_) {},
        onAbort: () => abortedCount++,
        runStartedAt: startTime,
        statusText: 'Working',
        messageCount: 121,
      ),
    );

    await tester.pump();

    // 1. Left activity tab shows "Working..." and "37s"
    expect(find.text('Working...'), findsOneWidget);
    expect(find.text('37s'), findsOneWidget);

    // 2. Top-right activity tab shows "停止"
    final topStopButton = find.text('停止');
    expect(topStopButton, findsOneWidget);

    // Tapping top-right stop triggers onAbort
    await tester.tap(topStopButton);
    expect(abortedCount, 1);

    // 3. Bottom-right stop button does not show send arrow
    expect(find.byIcon(Icons.arrow_upward), findsNothing);

    // Bottom-right button is a square container that triggers onAbort
    // We can find the button by its position or InkWell
    final inkWells = find.byType(InkWell);
    // The last InkWell is the bottom-right stop button
    await tester.tap(inkWells.last);
    expect(abortedCount, 2);

    // 4. Message count badge shows 121
    expect(find.text('121'), findsOneWidget);
  });
}
