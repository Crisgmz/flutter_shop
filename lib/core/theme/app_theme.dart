import 'package:flutter/material.dart';

import 'tokens.dart';

class AppTheme {
  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: AppTokens.brandBlue,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDCE9FF),
      onPrimaryContainer: Color(0xFF001C43),
      secondary: AppTokens.brandBlueLight,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFE7F0FF),
      onSecondaryContainer: Color(0xFF0F2D5C),
      tertiary: AppTokens.info,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFD9F4FF),
      onTertiaryContainer: Color(0xFF002A3A),
      error: Color(0xFFBA1A1A),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Colors.white,
      onSurface: AppTokens.textPrimary,
      onSurfaceVariant: AppTokens.textSecondary,
      outline: Color(0xFFCFD7E6),
      outlineVariant: AppTokens.divider,
      shadow: Color(0x3300285B),
      scrim: Color(0x6600285B),
      inverseSurface: Color(0xFF20293A),
      onInverseSurface: Color(0xFFEEF3FF),
      inversePrimary: Color(0xFFAFCBFF),
      surfaceTint: AppTokens.brandBlue,
    ),
    scaffoldBackgroundColor: AppTokens.scaffold,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: AppTokens.textPrimary,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: AppTokens.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      color: Colors.white,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusL)),
        side: const BorderSide(color: AppTokens.cardBorder),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppTokens.divider,
      thickness: 1,
      space: 1,
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(AppTokens.secondary),
      headingTextStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTokens.foreground,
      ),
      dataTextStyle: const TextStyle(
        fontSize: 14,
        color: AppTokens.foreground,
      ),
      dividerThickness: 1,
      horizontalMargin: AppTokens.s16,
      columnSpacing: AppTokens.s24,
      dataRowMinHeight: 48,
      dataRowMaxHeight: 56,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTokens.border, width: 0.5),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusS + 2),
      ),
      side: const BorderSide(color: Color(0xFFD5E3FF)),
      backgroundColor: const Color(0xFFEAF2FF),
      selectedColor: const Color(0xFFD9E8FF),
      labelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0F2D5C),
      ),
      secondaryLabelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0F2D5C),
      ),
      brightness: Brightness.light,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s8, vertical: AppTokens.s2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppTokens.brandBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTokens.brandBlueDark,
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: Color(0xFFC6D9FF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
        ),
      ),
    ),
    segmentedButtonTheme: const SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: Color(0xFFC6D9FF)),
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppTokens.brandBlue,
      selectedIconTheme: IconThemeData(color: Colors.white),
      unselectedIconTheme: IconThemeData(color: Color(0xCCFFFFFF)),
      selectedLabelTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(color: Color(0xCCFFFFFF)),
      indicatorColor: Color(0xFF2F7CEE),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: AppTokens.brandBlue,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(AppTokens.s20),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTokens.brandBlueDark,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
        borderSide: const BorderSide(color: Color(0xFFD6DFED)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
        borderSide: const BorderSide(color: Color(0xFFD6DFED)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
        borderSide: const BorderSide(color: AppTokens.brandBlue, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 1.4),
      ),
    ),
  );
}
