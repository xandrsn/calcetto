import 'package:flutter/material.dart';

// Modern light palette — clean white surfaces with vibrant emerald accent
const kBackground = Color(0xFFF8FAFC); // slate-50
const kSurface = Color(0xFFFFFFFF); // white cards
const kSurface2 = Color(0xFFF1F5F9); // slate-100 (subtle alternate surface)
const kBorder = Color(0xFFE2E8F0); // slate-200 (card/input borders)
const kAccentBlue = Color(0xFF3B82F6); // blue-500
const kAccentGreen = Color(0xFF10B981); // emerald-500 (vibrant football green)
const kAccentRed = Color(0xFFEF4444); // red-500
const kAccentYellow = Color(0xFFF59E0B); // amber-400 (warm gold)
const kTextPrimary = Color(0xFF0F172A); // slate-900
const kTextMuted = Color(0xFF64748B); // slate-500
const kTextDim = Color(0xFF94A3B8); // slate-400
const kPitchGreen = Color(0xFF059669); // emerald-600 (field)

/// Compact mechanical font — AppBar titles, tabs, buttons, stats, labels.
const kFontUI = 'ChakraPetch';

/// Clean sans-serif — body text, questions, descriptions, player names.
const kFontBody = 'Inter';

/// Blocky arcade font, reserved for the CALCETTO logo/wordmark only.
const kFontLogo = 'PressStart2P';

ThemeData buildAppTheme() {
  return ThemeData(
    scaffoldBackgroundColor: kBackground,
    colorScheme: const ColorScheme.light(
      surface: kSurface,
      primary: kAccentGreen,
      secondary: kAccentBlue,
      error: kAccentRed,
    ),
    fontFamily: kFontUI,
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 24,
        color: kTextPrimary,
        height: 1.2,
        fontWeight: FontWeight.w700,
        fontFamily: kFontUI,
      ),
      displayMedium: TextStyle(
        fontSize: 20,
        color: kTextPrimary,
        height: 1.2,
        fontWeight: FontWeight.w700,
        fontFamily: kFontUI,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        color: kTextPrimary,
        height: 1.5,
        fontFamily: kFontBody,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: kTextPrimary,
        height: 1.5,
        fontFamily: kFontBody,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        color: kTextMuted,
        height: 1.4,
        fontFamily: kFontBody,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        color: kTextPrimary,
        height: 1.25,
        fontWeight: FontWeight.w600,
        fontFamily: kFontUI,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        color: kTextMuted,
        height: 1.25,
        fontFamily: kFontUI,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kSurface,
      foregroundColor: kTextPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: kFontUI,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: kTextPrimary,
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: kAccentGreen,
      unselectedLabelColor: kTextMuted,
      indicatorColor: kAccentGreen,
      dividerColor: kBorder,
      labelStyle: TextStyle(
        fontFamily: kFontUI,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: kFontUI,
        fontSize: 12,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: kSurface,
      selectedItemColor: kAccentGreen,
      unselectedItemColor: kTextMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorder, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kAccentGreen, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kAccentRed, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kAccentRed, width: 2),
      ),
      hintStyle: const TextStyle(
        fontSize: 14,
        color: kTextMuted,
        fontFamily: kFontUI,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    dividerColor: kBorder,
    cardColor: kSurface,
    useMaterial3: false,
  );
}
