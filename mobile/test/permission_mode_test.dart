import 'package:cloudcli_mobile/app/theme/app_theme.dart';
import 'package:cloudcli_mobile/core/models/provider_capability.dart';
import 'package:cloudcli_mobile/features/chat/widgets/composer.dart';
import 'package:cloudcli_mobile/features/chat/widgets/permission_mode_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestApp(Widget child, {ThemeMode mode = ThemeMode.dark}) {
    return MaterialApp(
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: mode,
      home: Scaffold(body: child),
    );
  }

  group('PermissionMode models and metadata', () {
    test('getPermissionModeInfo returns correct metadata for all modes', () {
      final defaultInfo = getPermissionModeInfo('default');
      expect(defaultInfo.title, '默认模式');
      expect(defaultInfo.icon, Icons.pan_tool_outlined);

      final autoInfo = getPermissionModeInfo('auto');
      expect(autoInfo.title, 'Auto Mode');
      expect(autoInfo.icon, Icons.smart_toy_outlined);

      final editInfo = getPermissionModeInfo('acceptEdits');
      expect(editInfo.title, '编辑模式');
      expect(editInfo.icon, Icons.sentiment_satisfied_alt_outlined);

      final bypassInfo = getPermissionModeInfo('bypassPermissions');
      expect(bypassInfo.title, '无限制模式');
      expect(bypassInfo.icon, Icons.warning_amber_rounded);

      final planInfo = getPermissionModeInfo('plan');
      expect(planInfo.title, '计划模式');
      expect(planInfo.icon, Icons.assignment_outlined);
    });

    test('fallbackPermissionModes covers claude, cursor, codex, opencode', () {
      expect(fallbackPermissionModes['claude'], contains('bypassPermissions'));
      expect(fallbackPermissionModes['codex'], contains('acceptEdits'));
      expect(fallbackPermissionModes['codex'], isNot(contains('auto')));
      expect(fallbackPermissionModes['cursor'], contains('plan'));
    });
  });

  group('Composer permission button UI', () {
    testWidgets('renders warning triangle icon when in bypassPermissions mode', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          Composer(
            isProcessing: false,
            permissionMode: 'bypassPermissions',
            onSend: (_) {},
            onAbort: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('renders smart toy icon when in auto mode', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          Composer(
            isProcessing: false,
            permissionMode: 'auto',
            onSend: (_) {},
            onAbort: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    });

    testWidgets('renders pan tool icon when in default mode', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          Composer(
            isProcessing: false,
            permissionMode: 'default',
            onSend: (_) {},
            onAbort: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.pan_tool_outlined), findsOneWidget);
    });

    testWidgets('tapping permission button fires onPermissionTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        buildTestApp(
          Composer(
            isProcessing: false,
            permissionMode: 'default',
            onSend: (_) {},
            onAbort: () {},
            onPermissionTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.pan_tool_outlined));
      expect(tapped, true);
    });
  });

  group('PermissionModeSheet widget', () {
    testWidgets('renders modes list and checkmark on selected mode', (tester) async {
      String? selected;
      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                PermissionModeSheet.show(
                  context,
                  provider: 'claude',
                  currentMode: 'bypassPermissions',
                  availableModes: const [
                    'default',
                    'auto',
                    'acceptEdits',
                    'bypassPermissions',
                    'plan',
                  ],
                  onSelectMode: (mode) => selected = mode,
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Check header
      expect(find.text('How should Claude actions be approved?'), findsOneWidget);
      expect(find.text('权限审批模式'), findsOneWidget);

      // Check mode titles and descriptions
      expect(find.text('默认模式'), findsOneWidget);
      expect(find.text('Auto Mode'), findsOneWidget);
      expect(find.text('编辑模式'), findsOneWidget);
      expect(find.text('无限制模式'), findsOneWidget);
      expect(find.text('计划模式'), findsOneWidget);

      // Check checkmark on bypassPermissions
      expect(find.byIcon(Icons.check), findsOneWidget);

      // Tap '编辑模式'
      await tester.tap(find.text('编辑模式'));
      await tester.pumpAndSettle();

      expect(selected, 'acceptEdits');
    });
  });
}
