import 'package:flutter/material.dart';

abstract final class AppBrandColors {
  static const red = Color(0xFFB80017);
  static const redDark = Color(0xFF7A0010);
  static const redLight = Color(0xFFFFE8EC);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF111111);
  static const blue = Color(0xFF0B5ED7);
  static const blueLight = Color(0xFFE8F1FF);
  static const gold = Color(0xFFD4AF37);
  static const goldDark = Color(0xFF8F6B00);
  static const goldLight = Color(0xFFFFF4D4);
  static const surface = Color(0xFFFFFBFA);
}

abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AppBrandColors.red,
      onPrimary: AppBrandColors.white,
      primaryContainer: AppBrandColors.redLight,
      onPrimaryContainer: AppBrandColors.redDark,
      secondary: AppBrandColors.blue,
      onSecondary: AppBrandColors.white,
      secondaryContainer: AppBrandColors.blueLight,
      onSecondaryContainer: Color(0xFF001D4A),
      tertiary: AppBrandColors.gold,
      onTertiary: AppBrandColors.black,
      tertiaryContainer: AppBrandColors.goldLight,
      onTertiaryContainer: Color(0xFF3D2F00),
      surface: AppBrandColors.surface,
      onSurface: AppBrandColors.black,
      error: Color(0xFFBA1A1A),
      onError: AppBrandColors.white,
    );

    return _themeFromScheme(scheme);
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: Color(0xFFFFB3B9),
      onPrimary: Color(0xFF68000C),
      primaryContainer: AppBrandColors.redDark,
      onPrimaryContainer: AppBrandColors.white,
      secondary: Color(0xFFADC7FF),
      onSecondary: Color(0xFF002F69),
      secondaryContainer: Color(0xFF004493),
      onSecondaryContainer: AppBrandColors.white,
      tertiary: Color(0xFFEBD078),
      onTertiary: Color(0xFF3D2F00),
      tertiaryContainer: Color(0xFF5D4800),
      onTertiaryContainer: AppBrandColors.goldLight,
      surface: Color(0xFF151111),
      onSurface: AppBrandColors.white,
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
    );

    return _themeFromScheme(scheme);
  }

  static ThemeData _themeFromScheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          scheme.brightness == Brightness.light ? AppBrandColors.white : null,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surface,
        elevation: 0,
        centerTitle: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: scheme.onSurfaceVariant,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.secondary,
        inactiveTrackColor: scheme.primaryContainer,
        overlayColor: scheme.secondary.withValues(alpha: 0.14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primaryContainer;
          }
          return null;
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primaryContainer;
            }
            return null;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return scheme.primary;
            return null;
          }),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppBrandColors.black,
        contentTextStyle: TextStyle(color: AppBrandColors.white),
      ),
    );
  }
}
