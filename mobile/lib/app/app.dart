import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/login_page.dart';
import '../features/sessions/session_list_page.dart';
import '../features/settings/settings_controller.dart';
import '../features/settings/theme_mode_controller.dart';
import '../core/providers.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

class CloudCliApp extends ConsumerWidget {
  const CloudCliApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final themeMode = ref.watch(themeModeProvider);

    // One socket for the whole app while logged in; closed on logout.
    ref.listen(authControllerProvider, (previous, next) {
      debugPrint('[app] auth ${previous?.status} -> ${next.status}');
      final socket = ref.read(chatSocketProvider);
      final url = ref.read(apiClientProvider).webSocketUrl;
      debugPrint('[app] wsUrl=$url');
      if (next.isAuthenticated && url != null) {
        socket.connect(url);
      } else if (!next.isAuthenticated) {
        socket.close();
      }
    });

    return MaterialApp(
      title: 'Cloud CLI',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(fontScale)),
          child: _LifecycleHost(child: child ?? const SizedBox.shrink()),
        );
      },
      home: switch (auth.status) {
        AuthStatus.bootstrapping => const _BootSplash(),
        AuthStatus.unauthenticated => const LoginPage(),
        AuthStatus.authenticated => const SessionListPage(),
      },
    );
  }
}

/// iOS suspends sockets in the background; on resume, probe the connection and
/// reconnect eagerly if it died while suspended.
class _LifecycleHost extends ConsumerStatefulWidget {
  const _LifecycleHost({required this.child});

  final Widget child;

  @override
  ConsumerState<_LifecycleHost> createState() => _LifecycleHostState();
}

class _LifecycleHostState extends ConsumerState<_LifecycleHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(chatSocketProvider).handleAppResume();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: palette.accent),
        ),
      ),
    );
  }
}
