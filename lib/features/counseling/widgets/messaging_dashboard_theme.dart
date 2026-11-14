import 'package:flutter/material.dart';
import '../../home/widgets/home_dashboard_widgets.dart';

/// Dashboard identity scoped to messaging; dark surfaces follow the app theme.
class MessagingDashboardTheme extends StatelessWidget {
  const MessagingDashboardTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final dark = base.brightness == Brightness.dark;
    final surface = dark ? base.colorScheme.surface : HomePalette.surface;
    final text = dark ? base.colorScheme.onSurface : HomePalette.text;
    final scheme = base.colorScheme.copyWith(
      primary: HomePalette.sun,
      surfaceTint: HomePalette.sun,
      onPrimary: HomePalette.text,
      primaryContainer: dark
          ? base.colorScheme.surfaceContainerHigh
          : HomePalette.surfaceWarm,
      onPrimaryContainer: text,
      secondary: HomePalette.sun,
      onSecondary: HomePalette.text,
      secondaryContainer: dark
          ? base.colorScheme.surfaceContainerHigh
          : HomePalette.surfaceWarm,
      onSecondaryContainer: text,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: dark
          ? base.colorScheme.onSurfaceVariant
          : HomePalette.muted,
      outlineVariant: dark
          ? base.colorScheme.outlineVariant
          : HomePalette.outlineStrong,
    );
    return Theme(
      data: base.copyWith(
        colorScheme: scheme,
        scaffoldBackgroundColor: dark
            ? base.scaffoldBackgroundColor
            : HomePalette.background,
        textTheme: dark
            ? base.textTheme
            : base.textTheme.apply(bodyColor: text, displayColor: text),
        appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: dark ? surface : HomePalette.sun,
          foregroundColor: text,
          titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
            color: text,
          ),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        bottomSheetTheme: base.bottomSheetTheme.copyWith(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
        ),
        dialogTheme: base.dialogTheme.copyWith(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
        ),
        textSelectionTheme: base.textSelectionTheme.copyWith(
          cursorColor: text,
          selectionColor: HomePalette.softGold.withValues(alpha: .35),
          selectionHandleColor: dark ? HomePalette.sun : HomePalette.text,
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: dark
              ? base.colorScheme.surfaceContainerHigh
              : HomePalette.surfaceWarm,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HomeMetrics.radiusLarge),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HomeMetrics.radiusLarge),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HomeMetrics.radiusLarge),
            borderSide: BorderSide(color: text, width: 2),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: text),
        ),
        progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
          color: dark ? HomePalette.sun : HomePalette.text,
        ),
      ),
      child: child,
    );
  }
}
