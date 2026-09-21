import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Appearance mode for the whole app: follow the system, force light or force
/// dark. Persisted; this personal build defaults to light.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    switch (ref.read(prefsStoreProvider).themeMode) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(prefsStoreProvider).setThemeMode(_keyFor(mode));
  }

  static String _keyFor(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.light:
        return 'light';
    }
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);