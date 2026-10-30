import 'package:flutter/material.dart';

class LeafLoreTheme {
  const LeafLoreTheme._();

  static const Color pinePrimary = Color(0xFF193B2B);
  static const Color pineDeep = Color(0xFF10271E);
  static const Color pineLight = Color(0xFF2F5C4B);
  static const Color sageAccent = Color(0xFF5D7D6A);
  static const Color sageSoft = Color(0xFFE7F0EB);
  static const Color amberGold = Color(0xFFD4A55A);
  static const Color amberSoft = Color(0xFFFFF1DB);
  static const Color terracotta = Color(0xFFC97D5A);
  static const Color parchment = Color(0xFFFBF8F2);
  static const Color parchmentStrong = Color(0xFFF1EDE2);
  static const Color shellWhite = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE6DFD2);
  static const Color charcoal = Color(0xFF202826);
  static const Color charcoalMuted = Color(0xFF5B6863);

  static const Color nightPrimary = Color(0xFFB9D1C2);
  static const Color nightSurface = Color(0xFF161F1B);
  static const Color nightCard = Color(0xFF1C2A25);
  static const Color nightElevated = Color(0xFF23352E);
  static const Color nightBorder = Color(0xFF2E3F3A);

  static const double pagePadding = 20;
  static const double cardRadius = 20;
  static const double mediumRadius = 16;
  static const double smallRadius = 12;

  static LinearGradient get heroGradient => const LinearGradient(
    colors: [pinePrimary, pineLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: parchment,
      fontFamily: 'Palatino Linotype',
      colorScheme: const ColorScheme.light(
        primary: pinePrimary,
        onPrimary: shellWhite,
        primaryContainer: Color(0xFFE5F0EA),
        onPrimaryContainer: pinePrimary,
        secondary: sageAccent,
        onSecondary: shellWhite,
        secondaryContainer: Color(0xFFEAF1EE),
        onSecondaryContainer: pineDeep,
        tertiary: amberGold,
        onTertiary: Color(0xFF2B1E00),
        surface: shellWhite,
        onSurface: charcoal,
        surfaceContainerLowest: shellWhite,
        surfaceContainer: Color(0xFFF5F0E8),
        surfaceContainerHigh: Color(0xFFF0E8DE),
        surfaceContainerHighest: Color(0xFFEAE2D7),
        outline: borderLight,
        outlineVariant: Color(0xFFEDE3D6),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontFamily: 'Palatino Linotype',
          fontWeight: FontWeight.w700,
          color: pineDeep,
          letterSpacing: -0.7,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Palatino Linotype',
          fontWeight: FontWeight.w700,
          color: pineDeep,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Palatino Linotype',
          fontWeight: FontWeight.w700,
          color: pineDeep,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Trebuchet MS',
          fontWeight: FontWeight.w700,
          color: pineDeep,
          fontSize: 17,
        ),
        titleSmall: TextStyle(
          fontFamily: 'Trebuchet MS',
          fontWeight: FontWeight.w700,
          color: pineDeep,
          fontSize: 14,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Trebuchet MS',
          fontSize: 16,
          height: 1.5,
          color: charcoal,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Trebuchet MS',
          fontSize: 14,
          height: 1.45,
          color: charcoalMuted,
        ),
        labelLarge: TextStyle(
          fontFamily: 'Trebuchet MS',
          fontWeight: FontWeight.w700,
          color: pineDeep,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: pinePrimary,
        titleTextStyle: TextStyle(
          fontFamily: 'Palatino Linotype',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: pinePrimary,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: shellWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: borderLight, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: shellWhite,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(smallRadius),
          borderSide: const BorderSide(color: borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(smallRadius),
          borderSide: const BorderSide(color: borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(smallRadius),
          borderSide: const BorderSide(color: pinePrimary, width: 1.6),
        ),
        labelStyle: const TextStyle(
          fontFamily: 'Trebuchet MS',
          color: charcoalMuted,
        ),
        hintStyle: TextStyle(
          fontFamily: 'Trebuchet MS',
          color: charcoalMuted.withValues(alpha: 0.7),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: pinePrimary,
          foregroundColor: shellWhite,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Trebuchet MS',
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: pinePrimary,
          side: const BorderSide(color: pinePrimary, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Trebuchet MS',
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: pinePrimary,
          foregroundColor: shellWhite,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Trebuchet MS',
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: shellWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        indicatorColor: const Color(0xFFE6F0EA),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Trebuchet MS',
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: parchmentStrong,
        selectedColor: pinePrimary,
        secondarySelectedColor: pinePrimary,
        labelStyle: const TextStyle(
          fontFamily: 'Trebuchet MS',
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        side: const BorderSide(color: borderLight),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      dividerTheme: const DividerThemeData(color: borderLight, thickness: 1),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: nightSurface,
      fontFamily: 'Palatino Linotype',
      colorScheme: const ColorScheme.dark(
        primary: nightPrimary,
        onPrimary: nightSurface,
        primaryContainer: nightElevated,
        onPrimaryContainer: Color(0xFFD8E8DE),
        secondary: amberGold,
        onSecondary: nightSurface,
        secondaryContainer: Color(0xFF2D4037),
        onSecondaryContainer: Color(0xFFF4F9F5),
        tertiary: amberGold,
        onTertiary: nightSurface,
        surface: nightCard,
        onSurface: Color(0xFFF2F4F1),
        surfaceContainerLowest: nightSurface,
        surfaceContainer: Color(0xFF1D2B27),
        surfaceContainerHigh: Color(0xFF263933),
        surfaceContainerHighest: Color(0xFF2F453F),
        outline: nightBorder,
        outlineVariant: Color(0xFF30423E),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontFamily: 'Palatino Linotype',
          fontWeight: FontWeight.w700,
          color: Color(0xFFF2F4F1),
          letterSpacing: -0.7,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Palatino Linotype',
          fontWeight: FontWeight.w700,
          color: Color(0xFFF2F4F1),
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Palatino Linotype',
          fontWeight: FontWeight.w700,
          color: Color(0xFFF2F4F1),
        ),
        titleMedium: TextStyle(
          fontFamily: 'Trebuchet MS',
          fontWeight: FontWeight.w700,
          color: Color(0xFFF2F4F1),
          fontSize: 17,
        ),
        titleSmall: TextStyle(
          fontFamily: 'Trebuchet MS',
          fontWeight: FontWeight.w700,
          color: Color(0xFFF2F4F1),
          fontSize: 14,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Trebuchet MS',
          fontSize: 16,
          height: 1.5,
          color: Color(0xFFE9F0EC),
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Trebuchet MS',
          fontSize: 14,
          height: 1.45,
          color: Color(0xFFB8C7C1),
        ),
        labelLarge: TextStyle(
          fontFamily: 'Trebuchet MS',
          fontWeight: FontWeight.w700,
          color: Color(0xFFF2F4F1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: nightPrimary,
        titleTextStyle: TextStyle(
          fontFamily: 'Palatino Linotype',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: nightPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: nightCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: nightBorder, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: nightCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(smallRadius),
          borderSide: const BorderSide(color: nightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(smallRadius),
          borderSide: const BorderSide(color: nightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(smallRadius),
          borderSide: const BorderSide(color: nightPrimary, width: 1.6),
        ),
        labelStyle: const TextStyle(
          fontFamily: 'Trebuchet MS',
          color: Color(0xFFB8C7C1),
        ),
        hintStyle: TextStyle(
          fontFamily: 'Trebuchet MS',
          color: const Color(0xFFB8C7C1).withValues(alpha: 0.7),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: nightPrimary,
          foregroundColor: nightSurface,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Trebuchet MS',
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: nightPrimary,
          side: const BorderSide(color: nightPrimary, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Trebuchet MS',
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: nightPrimary,
          foregroundColor: nightSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Trebuchet MS',
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: nightCard,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        indicatorColor: nightElevated,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Trebuchet MS',
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: nightElevated,
        selectedColor: nightPrimary,
        secondarySelectedColor: nightPrimary,
        labelStyle: const TextStyle(
          fontFamily: 'Trebuchet MS',
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        side: const BorderSide(color: nightBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      dividerTheme: const DividerThemeData(color: nightBorder, thickness: 1),
    );
  }
}
