import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the app theme for each brightness. The color values come from the
/// palettes in tokens.dart so both themes stay visually paired.
ThemeData buildDarkTheme() => _base(darkPalette);

ThemeData buildLightTheme() => _base(lightPalette);

ThemeData _base(AppPalette palette) {
  final isDark = palette.brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.accent,
    brightness: palette.brightness,
    surface: palette.surface,
    onSurface: palette.text,
  ).copyWith(
    primary: palette.accent,
    onPrimary: palette.onPrimary,
    error: palette.danger,
    outline: palette.line,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: palette.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.bg,
    canvasColor: palette.bg,
    dividerColor: palette.line,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: palette.text,
        fontSize: AppTextSizes.navTitle,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: palette.text),
    ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: palette.text, fontSize: AppTextSizes.message, height: 1.5),
      bodySmall: TextStyle(color: palette.text2, fontSize: AppTextSizes.meta),
      titleMedium: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      hintStyle: TextStyle(color: palette.text3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: palette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide(color: palette.accent, width: 1.4),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? palette.surface3 : palette.surface,
      contentTextStyle: TextStyle(color: palette.text),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.bgElevated,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(iconColor: palette.text2),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accent),
  );
}