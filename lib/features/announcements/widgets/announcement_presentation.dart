import 'package:flutter/material.dart';
import '../../home/widgets/home_dashboard_widgets.dart';

Duration announcementTransitionDuration(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 180);

ThemeData announcementMobileTheme(ThemeData base) => base.copyWith(
  scaffoldBackgroundColor: HomePalette.background,
  colorScheme: base.colorScheme.copyWith(
    primary: HomePalette.text,
    onPrimary: Colors.white,
    primaryContainer: HomePalette.softGold,
    onPrimaryContainer: HomePalette.text,
    surface: HomePalette.surface,
    onSurface: HomePalette.text,
    outline: HomePalette.outlineStrong,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: HomePalette.background,
    foregroundColor: HomePalette.text,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
    elevation: 0,
  ),
  cardTheme: const CardThemeData(
    color: HomePalette.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(20)),
      side: BorderSide(color: HomePalette.outline),
    ),
  ),
  chipTheme: base.chipTheme.copyWith(
    backgroundColor: HomePalette.surface,
    selectedColor: HomePalette.softGold,
    labelStyle: const TextStyle(
      color: HomePalette.text,
      fontWeight: FontWeight.w600,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    side: const BorderSide(color: HomePalette.outline),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
);

class AnnouncementStatusPanel extends StatelessWidget {
  const AnnouncementStatusPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: announcementTransitionDuration(context),
    alignment: Alignment.topCenter,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    ),
  );
}
