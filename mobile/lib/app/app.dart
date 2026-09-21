import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/login_page.dart';
import '../features/settings/settings_controller.dart';
import 'shell.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

class CloudCliApp extends ConsumerWidget {
  const CloudCliApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final fontScale = ref.watch(fontScaleProvider);

    return MaterialApp(
      title: 'Cloud CLI',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.dark,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(fontScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: switch (auth.status) {
        AuthStatus.bootstrapping => const _BootSplash(),
        AuthStatus.unauthenticated => const LoginPage(),
        AuthStatus.authenticated => const AppShell(),
      },
    );
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
        ),
      ),
    );
  }
}
