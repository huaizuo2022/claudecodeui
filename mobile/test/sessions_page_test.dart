import 'package:cloudcli_mobile/app/theme/app_theme.dart';
import 'package:cloudcli_mobile/core/models/project.dart';
import 'package:cloudcli_mobile/core/models/session.dart';
import 'package:cloudcli_mobile/features/sessions/session_list_controller.dart';
import 'package:cloudcli_mobile/features/sessions/session_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProjectsController extends ProjectsController {
  @override
  Future<List<ProjectSummary>> build() async => [
        const ProjectSummary(
          projectId: 'p1',
          path: '/path/p1',
          displayName: 'Demo Project',
          fullPath: '/path/p1',
          isStarred: false,
          sessions: [],
          totalSessions: 0,
        ),
      ];
}

class _FakeRecentSessionsNotifier extends RecentSessionsNotifier {
  @override
  Future<RecentSessionsState> build() async => const RecentSessionsState(
        conversations: [
          RecentSession(
            sessionId: 'ses-1',
            provider: 'claude',
            projectId: 'p1',
            projectDisplayName: 'Demo Project',
            sessionTitle: 'Hello Mobile',
            lastActivity: null,
            isProjectStarred: false,
          ),
        ],
        total: 1492,
        hasMore: true,
        isLoadingMore: false,
      );
}

void main() {
  testWidgets('SessionListPage renders CloudCLI header, action buttons, and segmented tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider.overrideWith(_FakeProjectsController.new),
          recentSessionsStateProvider.overrideWith(_FakeRecentSessionsNotifier.new),
          runningSessionsProvider.overrideWith((ref) async => []),
          archivedProjectsProvider.overrideWith((ref) async => []),
          archivedSessionsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const SessionListPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Header has CloudCLI branding and quick action buttons
    expect(find.text('CloudCLI'), findsOneWidget);
    expect(find.byIcon(Icons.add_comment_rounded), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // 2. Segmented Tabs exist
    expect(find.text('对话'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    expect(find.byIcon(Icons.show_chart_rounded), findsOneWidget);
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);

    // 3. Under 对话 tab, shows "Recent conversations" and total count 1492
    expect(find.text('Recent conversations'), findsOneWidget);
    expect(find.text('1492'), findsOneWidget);
    expect(find.text('Hello Mobile'), findsOneWidget);

    // 4. Tap '项目' tab switches view to Projects
    await tester.tap(find.text('项目'));
    await tester.pumpAndSettle();

    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Demo Project'), findsOneWidget);
  });
}
