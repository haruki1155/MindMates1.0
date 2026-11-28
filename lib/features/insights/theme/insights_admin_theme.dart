import 'package:flutter/material.dart';

/// Page-scoped palette for the Insights Content dashboard and New/Edit Insight
/// editor. Kept intentionally isolated from global `AdminTheme`.
abstract final class InsightsAdminColors {
  static const canvas = Color(0xFFF4F7FB);
  static const surface = Color(0xFFFFFFFF);
  static const navy = Color(0xFF0B1C2D);
  static const bodyMuted = Color(0xFF4B5563);
  static const subtleMuted = Color(0xFF64748B);

  static const cardBorder = Color(0xFFF3F4F6);
  static const controlBorder = Color(0xFFE5E7EB);
  static const controlBorderStrong = Color(0xFFD1D5DB);
  static const hoverSurface = Color(0xFFF3F4F6);

  static const ctaYellow = Color(0xFFFDE68A);
  static const ctaYellowHover = Color(0xFFFCD34D);
  static const ctaYellowPressed = Color(0xFFFBBF24);

  static const primaryBlue = Color(0xFF89CFF0);
  static const primaryBlueHover = Color(0xFF74C3EA);
  static const primaryBluePressed = Color(0xFF5CB6E3);
  static const disabledBg = Color(0xFFE2E8F0);
  static const disabledFg = Color(0xFF94A3B8);

  static const tagBlueBg = Color(0xFFCFEFF7);

  static const activeBg = Color(0xFFDCFCE7);
  static const activeFg = Color(0xFF166534);
  static const activeBorder = Color(0xFF86EFAC);

  static const draftBg = Color(0xFFF3F4F6);
  static const draftFg = Color(0xFF374151);
  static const draftBorder = Color(0xFFD1D5DB);

  static const amberBg = Color(0xFFFEF3C7);
  static const amberFg = Color(0xFF92400E);
  static const amberBorder = Color(0xFFFCD34D);

  static const dangerBg = Color(0xFFFEE2E2);
  static const dangerFg = Color(0xFFB91C1C);
  static const dangerBorder = Color(0xFFFCA5A5);
}

/// Scoped theme, decorations, and button styles used exclusively by
/// `ManageInsightsPage` and `InsightContentEditor`.
abstract final class InsightsAdminTheme {
  static const _fontFamily = 'Roboto';
  static const _fontFallback = <String>['Inter', 'sans-serif'];

  static const cardRadius = BorderRadius.all(Radius.circular(16));
  static const controlRadius = BorderRadius.all(Radius.circular(12));
  static const actionRadius = BorderRadius.all(Radius.circular(8));
  static const tagRadius = BorderRadius.all(Radius.circular(6));
  static const pillRadius = BorderRadius.all(Radius.circular(999));

  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0A0B1C2D),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x050B1C2D),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  static BoxDecoration get cardDecoration => BoxDecoration(
    color: InsightsAdminColors.surface,
    borderRadius: cardRadius,
    border: Border.all(color: InsightsAdminColors.cardBorder, width: 1),
    boxShadow: cardShadow,
  );

  static BoxDecoration get controlDecoration => BoxDecoration(
    color: InsightsAdminColors.surface,
    borderRadius: controlRadius,
    border: Border.all(color: InsightsAdminColors.controlBorder, width: 1),
  );

  static ThemeData get data {
    const scheme = ColorScheme.light(
      primary: InsightsAdminColors.navy,
      onPrimary: Colors.white,
      primaryContainer: InsightsAdminColors.primaryBlue,
      onPrimaryContainer: InsightsAdminColors.navy,
      secondary: InsightsAdminColors.primaryBlue,
      onSecondary: InsightsAdminColors.navy,
      secondaryContainer: InsightsAdminColors.tagBlueBg,
      onSecondaryContainer: InsightsAdminColors.navy,
      surface: InsightsAdminColors.surface,
      onSurface: InsightsAdminColors.navy,
      error: InsightsAdminColors.dangerFg,
      onError: Colors.white,
      outline: InsightsAdminColors.controlBorder,
      outlineVariant: InsightsAdminColors.cardBorder,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: controlRadius,
      borderSide: const BorderSide(color: InsightsAdminColors.controlBorder),
    );

    const baseText = TextStyle(
      fontFamily: _fontFamily,
      fontFamilyFallback: _fontFallback,
      color: InsightsAdminColors.navy,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fontFallback,
      colorScheme: scheme,
      scaffoldBackgroundColor: InsightsAdminColors.canvas,
      dividerColor: InsightsAdminColors.canvas,
      visualDensity: VisualDensity.standard,
      textTheme: TextTheme(
        headlineLarge: baseText.copyWith(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          height: 1.2,
        ),
        headlineSmall: baseText.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
        titleLarge: baseText.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        titleMedium: baseText.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        bodyLarge: baseText.copyWith(
          fontSize: 14,
          height: 1.45,
        ),
        bodyMedium: baseText.copyWith(
          fontSize: 14,
          color: InsightsAdminColors.bodyMuted,
          height: 1.45,
        ),
        bodySmall: baseText.copyWith(
          fontSize: 12,
          color: InsightsAdminColors.subtleMuted,
          height: 1.4,
        ),
        labelLarge: baseText.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: InsightsAdminColors.surface,
        foregroundColor: InsightsAdminColors.navy,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: InsightsAdminColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(
            color: InsightsAdminColors.primaryBlue,
            width: 1.8,
          ),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: InsightsAdminColors.dangerFg),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(
            color: InsightsAdminColors.dangerFg,
            width: 1.5,
          ),
        ),
        labelStyle: const TextStyle(
          color: InsightsAdminColors.bodyMuted,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: const TextStyle(
          color: InsightsAdminColors.navy,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(
          color: InsightsAdminColors.subtleMuted,
          fontSize: 14,
        ),
        helperStyle: const TextStyle(
          color: InsightsAdminColors.subtleMuted,
          fontSize: 12,
        ),
        errorStyle: const TextStyle(
          color: InsightsAdminColors.dangerFg,
          fontSize: 12,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: InsightsAdminColors.surface,
        selectedColor: InsightsAdminColors.tagBlueBg,
        checkmarkColor: InsightsAdminColors.navy,
        side: const BorderSide(color: InsightsAdminColors.controlBorder),
        shape: const RoundedRectangleBorder(borderRadius: tagRadius),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: const TextStyle(
          color: InsightsAdminColors.navy,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return InsightsAdminColors.navy;
          }
          return InsightsAdminColors.surface;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return InsightsAdminColors.primaryBlue;
          }
          return InsightsAdminColors.controlBorder;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return InsightsAdminColors.controlBorderStrong;
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: InsightsAdminColors.primaryBlue,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: InsightsAdminColors.navy,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Warm yellow creation CTA (`+ New insight`), 12px radius.
  static ButtonStyle get newInsightButtonStyle => ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return InsightsAdminColors.disabledBg;
      }
      if (states.contains(WidgetState.pressed)) {
        return InsightsAdminColors.ctaYellowPressed;
      }
      if (states.contains(WidgetState.hovered)) {
        return InsightsAdminColors.ctaYellowHover;
      }
      return InsightsAdminColors.ctaYellow;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return InsightsAdminColors.disabledFg;
      }
      return InsightsAdminColors.navy;
    }),
    elevation: const WidgetStatePropertyAll(0),
    minimumSize: const WidgetStatePropertyAll(Size(48, 46)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: controlRadius),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
    ),
  );

  /// Brand cool-blue primary action (`Approve`, `Save insight`), borderless,
  /// 8px radius.
  static ButtonStyle get primaryActionStyle => ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return InsightsAdminColors.disabledBg;
      }
      if (states.contains(WidgetState.pressed)) {
        return InsightsAdminColors.primaryBluePressed;
      }
      if (states.contains(WidgetState.hovered)) {
        return InsightsAdminColors.primaryBlueHover;
      }
      return InsightsAdminColors.primaryBlue;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return InsightsAdminColors.disabledFg;
      }
      return InsightsAdminColors.navy;
    }),
    side: const WidgetStatePropertyAll(BorderSide.none),
    elevation: const WidgetStatePropertyAll(0),
    minimumSize: const WidgetStatePropertyAll(Size(0, 42)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: actionRadius),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
    ),
  );

  /// Secondary card/editor action (`Edit`, `Hide`, `Archive`, `Cancel`,
  /// `Test link`): transparent fill, 1px light gray border, 8px radius, with
  /// optional destructive red hover treatment for `Archive`.
  static ButtonStyle secondaryActionStyle({
    bool destructiveHover = false,
    double minHeight = 42,
  }) => ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return Colors.transparent;
      }
      if (destructiveHover &&
          (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed))) {
        return InsightsAdminColors.dangerBg;
      }
      if (states.contains(WidgetState.pressed)) {
        return InsightsAdminColors.controlBorder;
      }
      if (states.contains(WidgetState.hovered)) {
        return InsightsAdminColors.hoverSurface;
      }
      return Colors.transparent;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return InsightsAdminColors.disabledFg;
      }
      if (destructiveHover &&
          (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed))) {
        return InsightsAdminColors.dangerFg;
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed)) {
        return InsightsAdminColors.navy;
      }
      return InsightsAdminColors.bodyMuted;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (destructiveHover &&
          (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed))) {
        return const BorderSide(
          color: InsightsAdminColors.dangerBorder,
          width: 1,
        );
      }
      if (states.contains(WidgetState.hovered)) {
        return const BorderSide(
          color: InsightsAdminColors.controlBorderStrong,
          width: 1,
        );
      }
      return const BorderSide(
        color: InsightsAdminColors.controlBorder,
        width: 1,
      );
    }),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    minimumSize: WidgetStatePropertyAll(Size(0, minHeight)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: actionRadius),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
    ),
  );
}

/// Fully rounded (`999px`) status pill with a matching 1px border.
class InsightsStatusPill extends StatelessWidget {
  const InsightsStatusPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.borderColor,
  });

  factory InsightsStatusPill.active(bool isActive, {Key? key}) => isActive
      ? InsightsStatusPill(
          key: key,
          label: 'Active',
          background: InsightsAdminColors.activeBg,
          foreground: InsightsAdminColors.activeFg,
          borderColor: InsightsAdminColors.activeBorder,
        )
      : InsightsStatusPill(
          key: key,
          label: 'Hidden',
          background: InsightsAdminColors.amberBg,
          foreground: InsightsAdminColors.amberFg,
          borderColor: InsightsAdminColors.amberBorder,
        );

  factory InsightsStatusPill.reviewStatus(String status, {Key? key}) =>
      switch (status) {
        'approved' => InsightsStatusPill(
          key: key,
          label: 'Approved',
          background: InsightsAdminColors.activeBg,
          foreground: InsightsAdminColors.activeFg,
          borderColor: InsightsAdminColors.activeBorder,
        ),
        'pending_review' => InsightsStatusPill(
          key: key,
          label: 'Pending review',
          background: InsightsAdminColors.amberBg,
          foreground: InsightsAdminColors.amberFg,
          borderColor: InsightsAdminColors.amberBorder,
        ),
        'archived' => InsightsStatusPill(
          key: key,
          label: 'Archived',
          background: InsightsAdminColors.dangerBg,
          foreground: InsightsAdminColors.dangerFg,
          borderColor: InsightsAdminColors.dangerBorder,
        ),
        _ => InsightsStatusPill(
          key: key,
          label: 'Draft',
          background: InsightsAdminColors.draftBg,
          foreground: InsightsAdminColors.draftFg,
          borderColor: InsightsAdminColors.draftBorder,
        ),
      };

  final String label;
  final Color background;
  final Color foreground;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: InsightsAdminTheme.pillRadius,
      border: Border.all(color: borderColor, width: 1),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: foreground,
        height: 1.2,
      ),
    ),
  );
}

/// Rectangular (`6px`) cool-blue category/audience tag distinct from rounded
/// status pills.
class InsightsCategoryTag extends StatelessWidget {
  const InsightsCategoryTag(this.label, {super.key, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: const BoxDecoration(
      color: InsightsAdminColors.tagBlueBg,
      borderRadius: InsightsAdminTheme.tagRadius,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: InsightsAdminColors.navy),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: InsightsAdminColors.navy,
            height: 1.2,
          ),
        ),
      ],
    ),
  );
}
