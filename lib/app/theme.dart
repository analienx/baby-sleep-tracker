import 'package:flutter/material.dart';

abstract final class SleepPalette {
  static const ink = Color(0xFF20263C);
  static const twilight = Color(0xFF27324D);
  static const lavender = Color(0xFFC7B6F0);
  static const sage = Color(0xFFABCDBA);
  // Dark enough for chart marks against both elevated white and lilac surfaces.
  static const daytimeChart = Color(0xFF346E59);
  static const cream = Color(0xFFF7F6F3);
  static const night = Color(0xFF111622);
  static const daytimePrimary = Color(0xFF4C416F);
  static const daytimeSecondary = Color(0xFF326754);
}

abstract final class SleepTheme {
  static ThemeData light() => _create(Brightness.light);
  static ThemeData dark() => _create(Brightness.dark);

  static ThemeData _create(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = dark
        ? ColorScheme.fromSeed(
            seedColor: SleepPalette.lavender,
            brightness: Brightness.dark,
            surface: const Color(0xFF1D2534),
          )
        : ColorScheme.fromSeed(
            seedColor: SleepPalette.daytimePrimary,
            brightness: Brightness.light,
          ).copyWith(
            primary: SleepPalette.daytimePrimary,
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFECE6F8),
            onPrimaryContainer: const Color(0xFF2F254A),
            secondary: SleepPalette.daytimeSecondary,
            onSecondary: Colors.white,
            secondaryContainer: const Color(0xFFDBF0E4),
            onSecondaryContainer: const Color(0xFF173F32),
            tertiary: const Color(0xFF895F30),
            onTertiary: Colors.white,
            tertiaryContainer: const Color(0xFFF5E5CD),
            onTertiaryContainer: const Color(0xFF4C3118),
            surface: Colors.white,
            onSurface: SleepPalette.ink,
            onSurfaceVariant: const Color(0xFF485064),
            outline: const Color(0xFF737A8B),
            outlineVariant: const Color(0xFFC9CCD5),
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFFBFAFD),
            surfaceContainer: const Color(0xFFF4F2F8),
            surfaceContainerHigh: const Color(0xFFEEEDF5),
            surfaceContainerHighest: const Color(0xFFE7E7F0),
            error: const Color(0xFFAD2E43),
            onError: Colors.white,
            errorContainer: const Color(0xFFFFE6EB),
            onErrorContainer: const Color(0xFF651F2C),
          );

    return ThemeData(
      useMaterial3: true,
      // Bundled Inter is deterministic offline on Android and iOS, unlike
      // OEM-provided Roboto aliases (some devices replace them with themed fonts).
      fontFamily: 'Inter',
      splashFactory: InkRipple.splashFactory,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? SleepPalette.night : SleepPalette.cream,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? SleepPalette.night : SleepPalette.cream,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(fontSize: 16),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: dark ? const Color(0xFF1B2230) : Colors.white,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? scheme.surfaceContainerHigh : const Color(0xFFF9F8FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(58),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          // Button styles do not inherit ThemeData.fontFamily on all OEMs.
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
