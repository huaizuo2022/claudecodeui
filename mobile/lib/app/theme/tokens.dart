import 'package:flutter/material.dart';

/// Design tokens lifted from the approved mockup. Dark is the only implemented
/// set; the light set will mirror these keys so swapping ThemeMode needs no
/// changes in feature code.
class AppColors {
  const AppColors._();

  static const bg = Color(0xFF090B0F);
  static const bgElevated = Color(0xFF0E1116);
  static const surface = Color(0xFF151920);
  static const surface2 = Color(0xFF1C2129);
  static const surface3 = Color(0xFF232935);
  static const line = Color(0xFF262C36);
  static const line2 = Color(0xFF333A46);

  static const text = Color(0xFFE9EEF7);
  static const text2 = Color(0xFF98A3B5);
  static const text3 = Color(0xFF66717F);

  static const accent = Color(0xFF7B8CFF);
  static const accentEnd = Color(0xFF4FC3F7);
  static const accentSoft = Color(0x247B8CFF);

  static const ok = Color(0xFF3ED598);
  static const warn = Color(0xFFFFC24B);
  static const danger = Color(0xFFFF6B6B);

  /// Provider identity colors, shared by badges and dots.
  static const claude = Color(0xFFE08A5F);
  static const codex = Color(0xFF5ED3B8);
  static const cursor = Color(0xFF8FA0FF);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentEnd],
  );

  static const primaryButtonGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [accent, Color(0xFF5F70F0)],
  );
}

class AppRadii {
  const AppRadii._();

  static const lg = 20.0;
  static const md = 14.0;
  static const sm = 10.0;
  static const bubble = 18.0;
  static const pill = 999.0;
}

class AppTextSizes {
  const AppTextSizes._();

  /// Message body size at the "standard" font-scale setting.
  static const message = 15.5;
  static const navTitle = 14.5;
  static const navSubtitle = 11.5;
  static const meta = 11.5;
  static const pageTitle = 28.0;
  static const code = 12.5;
}

/// Font scale steps offered in settings.
enum FontScaleStep {
  standard('标准', 1.0),
  large('大', 1.12),
  larger('更大', 1.25);

  const FontScaleStep(this.label, this.scale);

  final String label;
  final double scale;
}
