import 'package:flutter/material.dart';

/// All visual tokens for one brightness. Widgets pick the live palette with
/// `AppPalette.of(context)`, which reads the effective brightness from the
/// active Material theme — so following the system works everywhere for free.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.bg,
    required this.bgElevated,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.line2,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentEnd,
    required this.accentSoft,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.claude,
    required this.codex,
    required this.cursor,
    required this.brandGradient,
    required this.primaryButtonGradient,
    required this.userBubbleBorder,
    required this.userBubbleText,
    required this.userBubble1,
    required this.userBubble2,
    required this.assistantText,
    required this.codeBlockBg,
    required this.permissionTint,
    required this.permissionText,
    required this.runningTint,
    required this.runningText,
    required this.navBarBg,
    required this.composerBg,
    required this.onPrimary,
    required this.toolNameText,
    required this.toolSummaryText,
    required this.errorText,
    required this.jumpPillBg,
  });

  final Brightness brightness;

  // Surfaces.
  final Color bg;
  final Color bgElevated;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color line;
  final Color line2;

  // Text hierarchy.
  final Color text;
  final Color text2;
  final Color text3;

  // Brand & semantics.
  final Color accent;
  final Color accentEnd;
  final Color accentSoft;
  final Color ok;
  final Color warn;
  final Color danger;

  // Provider identity.
  final Color claude;
  final Color codex;
  final Color cursor;

  // Gradients & message chrome.
  final Gradient brandGradient;
  final Gradient primaryButtonGradient;
  final Color userBubbleBorder;
  final Color userBubbleText;
  final Color userBubble1;
  final Color userBubble2;
  final Color assistantText;
  final Color codeBlockBg;
  final Color permissionTint;
  final Color permissionText;
  final Color runningTint;
  final Color runningText;
  final Color navBarBg;
  final Color composerBg;
  final Color onPrimary;
  final Color toolNameText;
  final Color toolSummaryText;
  final Color errorText;
  final Color jumpPillBg;

  static AppPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light
        ? lightPalette
        : darkPalette;
  }
}

const darkPalette = AppPalette(
  brightness: Brightness.dark,
  bg: Color(0xFF090B0F),
  bgElevated: Color(0xFF0E1116),
  surface: Color(0xFF151920),
  surface2: Color(0xFF1C2129),
  surface3: Color(0xFF232935),
  line: Color(0xFF262C36),
  line2: Color(0xFF333A46),
  text: Color(0xFFE9EEF7),
  text2: Color(0xFF98A3B5),
  text3: Color(0xFF66717F),
  accent: Color(0xFF7B8CFF),
  accentEnd: Color(0xFF4FC3F7),
  accentSoft: Color(0x247B8CFF),
  ok: Color(0xFF3ED598),
  warn: Color(0xFFFFC24B),
  danger: Color(0xFFFF6B6B),
  claude: Color(0xFFE08A5F),
  codex: Color(0xFF5ED3B8),
  cursor: Color(0xFF8FA0FF),
  brandGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7B8CFF), Color(0xFF4FC3F7)],
  ),
  primaryButtonGradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF7B8CFF), Color(0xFF5F70F0)],
  ),
  userBubbleBorder: Color(0x427B8CFF),
  userBubbleText: Color(0xFFEAEFFA),
  userBubble1: Color(0xFF2A3452),
  userBubble2: Color(0xFF232B45),
  assistantText: Color(0xFFDFE6F2),
  codeBlockBg: Color(0xFF0C0F14),
  permissionTint: Color(0x14FFC24B),
  permissionText: Color(0xFFFFE2A8),
  runningTint: Color(0x143ED598),
  runningText: Color(0xFFBFF5DF),
  navBarBg: Color(0xF20D1015),
  composerBg: Color(0xF20D1015),
  onPrimary: Colors.white,
  toolNameText: Color(0xFFC9D4E6),
  toolSummaryText: Color(0xFF98A3B5),
  errorText: Color(0xFFFFC0C0),
  jumpPillBg: Color(0xF01C2129),
);

const lightPalette = AppPalette(
  brightness: Brightness.light,
  bg: Color(0xFFF5F6F8),
  bgElevated: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  surface2: Color(0xFFF0F2F5),
  surface3: Color(0xFFE5E9EF),
  line: Color(0xFFE3E7ED),
  line2: Color(0xFFC8CEDA),
  text: Color(0xFF1B2033),
  text2: Color(0xFF5C6577),
  text3: Color(0xFF9299A8),
  accent: Color(0xFF5F6EE0),
  accentEnd: Color(0xFF2E9FD6),
  accentSoft: Color(0x1E5F6EE0),
  ok: Color(0xFF0E9F6E),
  warn: Color(0xFFD97706),
  danger: Color(0xFFDC2626),
  claude: Color(0xFFC86A4A),
  codex: Color(0xFF3DAA8E),
  cursor: Color(0xFF6478D8),
  brandGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5F6EE0), Color(0xFF2E9FD6)],
  ),
  primaryButtonGradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF6B7CE8), Color(0xFF5563D8)],
  ),
  userBubbleBorder: Color(0x2E5F6EE0),
  userBubbleText: Color(0xFF1B2033),
  userBubble1: Color(0xFFE4E9F6),
  userBubble2: Color(0xFFDDE4F3),
  assistantText: Color(0xFF1B2033),
  codeBlockBg: Color(0xFFF6F7F9),
  permissionTint: Color(0x0FD97706),
  permissionText: Color(0xFFB45309),
  runningTint: Color(0x0F0E9F6E),
  runningText: Color(0xFF047857),
  navBarBg: Color(0xF2FFFFFF),
  composerBg: Color(0xF2FFFFFF),
  onPrimary: Colors.white,
  toolNameText: Color(0xFF3B4358),
  toolSummaryText: Color(0xFF5C6577),
  errorText: Color(0xFFB91C1C),
  jumpPillBg: Color(0xF0FFFFFF),
);

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

  static const message = 15.5;
  static const navTitle = 14.5;
  static const navSubtitle = 11.5;
  static const meta = 11.5;
  static const pageTitle = 28.0;
  static const code = 12.5;
}

enum FontScaleStep {
  standard('标准', 1.0),
  large('大', 1.12),
  larger('更大', 1.25);

  const FontScaleStep(this.label, this.scale);

  final String label;
  final double scale;
}