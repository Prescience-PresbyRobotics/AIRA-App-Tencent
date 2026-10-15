import 'package:flutter/material.dart';

class AiraColors {
  static const ink = Color(0xFF122923);
  static const forest = Color(0xFF204F43);
  static const cream = Color(0xFFF8F7F2);
  static const muted = Color(0xFF646B69);
  static const sage = Color(0xFFE7EEDB);
  static const lavender = Color(0xFFECE6F7);
  static const peach = Color(0xFFFFE8D9);
  static const coral = Color(0xFFE99A7D);
  static const line = Color(0xFFDFE3DA);
}

/// The roomy values are the original AIRA layout. Compact mode reduces
/// whitespace without scaling interactive hit areas below 48 logical pixels.
class AiraLayout extends ThemeExtension<AiraLayout> {
  final double spacingFactor;
  const AiraLayout({this.spacingFactor = .8});

  static AiraLayout of(BuildContext context) =>
      Theme.of(context).extension<AiraLayout>() ?? const AiraLayout();

  double space(double value) => value * spacingFactor;
  EdgeInsets insets(EdgeInsets value) => value * spacingFactor;

  @override
  AiraLayout copyWith({double? spacingFactor}) =>
      AiraLayout(spacingFactor: spacingFactor ?? this.spacingFactor);

  @override
  AiraLayout lerp(covariant AiraLayout? other, double t) => other == null
      ? this
      : AiraLayout(
          spacingFactor:
              spacingFactor + (other.spacingFactor - spacingFactor) * t,
        );
}

/// Apply AIRA's reading preference before the device's accessibility scaling.
/// Delegating each font size preserves nonlinear system text scaling.
class AiraTextScaler extends TextScaler {
  final TextScaler systemScaler;
  final double factor;
  const AiraTextScaler(this.systemScaler, {required this.factor});

  @override
  double scale(double fontSize) => systemScaler.scale(fontSize * factor);

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is AiraTextScaler &&
      other.systemScaler == systemScaler &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(systemScaler, factor);
}

ThemeData airaTheme({bool largerText = false}) => ThemeData(
  extensions: [AiraLayout(spacingFactor: largerText ? 1 : .8)],
  materialTapTargetSize: MaterialTapTargetSize.padded,
  visualDensity: VisualDensity.standard,
  navigationBarTheme: NavigationBarThemeData(height: largerText ? 80 : 72),
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AiraColors.forest,
    primary: AiraColors.forest,
    surface: AiraColors.cream,
    onSurface: AiraColors.ink,
    error: const Color(0xFFA73737),
  ),
  scaffoldBackgroundColor: AiraColors.cream,
  fontFamily: 'Arial',
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.5,
      height: 1.13,
      color: AiraColors.ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: -.8,
      color: AiraColors.ink,
    ),
    titleLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: AiraColors.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: AiraColors.ink,
    ),
    bodyLarge: TextStyle(fontSize: 20, height: 1.5, color: AiraColors.ink),
    bodyMedium: TextStyle(fontSize: 17, height: 1.45, color: AiraColors.ink),
    bodySmall: TextStyle(fontSize: 15, height: 1.4, color: AiraColors.muted),
    labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: EdgeInsets.symmetric(
      horizontal: largerText ? 20 : 16,
      vertical: largerText ? 19 : 14,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AiraColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AiraColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AiraColors.forest, width: 2),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: largerText ? const Size(56, 56) : const Size(48, 48),
      padding: EdgeInsets.symmetric(
        horizontal: largerText ? 24 : 20,
        vertical: largerText ? 16 : 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: largerText ? const Size(56, 56) : const Size(48, 48),
      side: const BorderSide(color: AiraColors.line),
      foregroundColor: AiraColors.ink,
      padding: EdgeInsets.symmetric(
        horizontal: largerText ? 20 : 16,
        vertical: largerText ? 16 : 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
  dividerTheme: const DividerThemeData(color: AiraColors.line),
);
