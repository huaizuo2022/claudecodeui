import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the app theme from the design tokens. Only the dark set is wired up
/// today; [buildLightTheme] is the seam for the light variant.
ThemeData buildDarkTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.accentEnd,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
    outline: AppColors.line,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.bg,
    dividerColor: AppColors.line,
    splashFactory: InkSparkle.splashFactory,
    fontFamily: null,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: AppTextSizes.navTitle,
        fontWeight: FontWeight.w600,
      ),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.text, fontSize: AppTextSizes.message, height: 1.5),
      bodySmall: TextStyle(color: AppColors.text2, fontSize: AppTextSizes.meta),
      titleMedium: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.text3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surface3,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.bgElevated,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.text2),
  );
}

ThemeData buildLightTheme() => buildDarkTheme();
