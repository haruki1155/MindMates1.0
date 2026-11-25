import 'package:flutter/material.dart';

/// Visual language for the standalone admin experience.
///
/// The palette deliberately stays neutral and uses pale yellow only for
/// emphasis, selection, and focus. This keeps dense operational screens calm.
abstract final class AdminColors {
  static const ink = Color(0xFF242423);
  static const muted = Color(0xFF686865);
  static const canvas = Color(0xFFF5F5F2);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFEDEDEA);
  static const border = Color(0xFFDEDED8);
  static const accent = Color(0xFFE6C94F);
  static const accentStrong = Color(0xFFB89400);
  static const accentSoft = Color(0xFFFFF4B8);
  static const accentFaint = Color(0xFFFFFBE8);
  static const success = Color(0xFF3F7257);
  static const danger = Color(0xFFB64B4B);

  // Semantic status tokens (WCAG AA contrast >= 4.5:1 for fg on bg).
  static const amberBg = Color(0xFFFEF3C7);
  static const amberFg = Color(0xFF92400E);
  static const amberBorder = Color(0xFFF59E0B);

  static const blueBg = Color(0xFFDBEAFE);
  static const blueFg = Color(0xFF1E40AF);
  static const blueBorder = Color(0xFF60A5FA);

  static const greenBg = Color(0xFFDCFCE7);
  static const greenFg = Color(0xFF166534);
  static const greenBorder = Color(0xFF4ADE80);

  static const violetBg = Color(0xFFEDE9FE);
  static const violetFg = Color(0xFF5B21B6);
  static const violetBorder = Color(0xFFA78BFA);

  static const redBg = Color(0xFFFEE2E2);
  static const redFg = Color(0xFF991B1B);
  static const redBorder = Color(0xFFF87171);

  static const neutralBg = Color(0xFFF3F4F6);
  static const neutralFg = Color(0xFF374151);
  static const neutralBorder = Color(0xFFD1D5DB);
}

/// Consistent spacing scale for Admin Web screens (8/12/16/24px).
abstract final class AdminSpacing {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
}

abstract final class AdminTheme {
  static ThemeData get data {
    const scheme = ColorScheme.light(
      primary: AdminColors.ink,
      onPrimary: Colors.white,
      primaryContainer: AdminColors.accentSoft,
      onPrimaryContainer: AdminColors.ink,
      secondary: AdminColors.accentStrong,
      onSecondary: Colors.white,
      secondaryContainer: AdminColors.accentSoft,
      onSecondaryContainer: AdminColors.ink,
      surface: AdminColors.surface,
      onSurface: AdminColors.ink,
      error: AdminColors.danger,
      onError: Colors.white,
      outline: AdminColors.border,
      outlineVariant: AdminColors.surfaceMuted,
    );
    const radius = BorderRadius.all(Radius.circular(10));
    final border = OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AdminColors.border),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AdminColors.canvas,
      dividerColor: AdminColors.border,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AdminColors.ink,
          fontSize: 28,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineSmall: TextStyle(
          color: AdminColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: AdminColors.ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: AdminColors.ink, height: 1.45),
        bodyMedium: TextStyle(color: AdminColors.muted, height: 1.4),
        labelLarge: TextStyle(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: AdminColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: const BorderSide(color: AdminColors.border),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AdminColors.surface,
        foregroundColor: AdminColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AdminColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(
            color: AdminColors.accentStrong,
            width: 1.5,
          ),
        ),
        hintStyle: const TextStyle(color: Color(0xFF92928C)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: const BorderSide(color: AdminColors.border),
          shape: RoundedRectangleBorder(borderRadius: radius),
          foregroundColor: AdminColors.ink,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 40),
          foregroundColor: AdminColors.ink,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AdminColors.surfaceMuted,
        selectedColor: AdminColors.accentSoft,
        side: const BorderSide(color: AdminColors.border),
        shape: RoundedRectangleBorder(borderRadius: radius),
        labelStyle: const TextStyle(
          color: AdminColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(AdminColors.surfaceMuted),
        headingTextStyle: TextStyle(
          color: AdminColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        dataTextStyle: TextStyle(color: AdminColors.ink, fontSize: 13),
        dividerThickness: 1,
        columnSpacing: 28,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AdminColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AdminColors.surface,
        surfaceTintColor: Colors.transparent,
        width: 280,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AdminColors.accentStrong,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AdminColors.ink,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
