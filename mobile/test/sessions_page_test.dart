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
            isStarred: false,
          ),
        ],
        total: 1492,
        hasMore: true,
        isLoadingMore: false,
      );
}

/// Same single row, but the conversation itself is starred.
class _FakeStarredSessionNotifier extends RecentSessionsNotifier {
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
            isStarred: true,
          ),
        ],
        total: 42,
        hasMore: false,
        isLoadingMore: false,
      );
}

class _FakeStarredProjectsController extends ProjectsController {
  @override
  Future<List<ProjectSummary>> build() async => [
        const ProjectSummary(
          projectId: 'p1',
          path: '/path/p1',
          displayName: 'Demo Project',
          fullPath: '/path/p1',
          isStarred: true,
          sessions: [],
          totalSessions: 0,
        ),
      ];
}

void main() {
  testWidgets('SessionListPage renders CloudCLI header, action buttons, and segmented tabs with Starred tab', (tester) async {
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

    // 2. Segmented Tabs exist (conversations, projects, starred, running, archived)
    expect(find.text('对话'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    // Two outline stars: the starred tab, plus the unstarred row's own star.
    expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.show_chart_rounded), findsOneWidget);
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);

    // 3. Under 对话 tab, shows "Recent conversations" and total count 1492
    expect(find.text('Recent conversations'), findsOneWidget);
    expect(find.text('1492'), findsOneWidget);
    expect(find.text('Hello Mobile'), findsOneWidget);

    // 4. Tap the star tab switches view to Starred (empty: no session is starred)
    // The tab icon comes before the list in the tree, so `.first` is the tab.
    await tester.tap(find.byIcon(Icons.star_outline_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('暂无加星会话'), findsOneWidget);
    expect(find.text('点击会话右侧的星标即可加星'), findsOneWidget);

    // 5. Tap '项目' tab switches view to Projects
    await tester.tap(find.text('项目'));
    await tester.pumpAndSettle();

    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Demo Project'), findsOneWidget);
  });

  testWidgets('a starred project does not pull its conversations into the starred tab', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider.overrideWith(_FakeStarredProjectsController.new),
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

    // Starring the project used to make one tap show every conversation of it.
    await tester.tap(find.byIcon(Icons.star_outline_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('暂无加星会话'), findsOneWidget);
    expect(find.text('Hello Mobile'), findsNothing);
  });

  testWidgets('a starred conversation shows up in the starred tab', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider.overrideWith(_FakeProjectsController.new),
          recentSessionsStateProvider.overrideWith(_FakeStarredSessionNotifier.new),
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

    // 1. Star tab icon is filled and shows the count badge '1'
    expect(find.text('1'), findsOneWidget);

    // 2. Tap the Starred tab (tab icon precedes the rows in the tree)
    await tester.tap(find.byIcon(Icons.star_rounded).first);
    await tester.pumpAndSettle();

    // 3. The one conversation the user starred is listed
    expect(find.text('Starred conversations'), findsOneWidget);
    expect(find.text('Hello Mobile'), findsOneWidget);
  });
}
