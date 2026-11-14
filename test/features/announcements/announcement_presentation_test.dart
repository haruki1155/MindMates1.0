import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/announcements/screens/announcements_screen.dart';
import 'package:mind_mates/features/announcements/data/announcement_repository.dart';
import 'package:mind_mates/features/announcements/widgets/announcement_presentation.dart';
import 'package:mind_mates/features/home/widgets/home_dashboard_widgets.dart';

void main() {
  testWidgets(
    'mobile announcement route uses warm app palette independently of parent theme',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.teal),
          home: AnnouncementsScreen(
            repository: AnnouncementRepository(fetch: (_) async => []),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.text('Opportunities start here'));
      expect(Theme.of(context).scaffoldBackgroundColor, HomePalette.background);
      expect(Theme.of(context).colorScheme.primary, HomePalette.text);
      expect(
        Theme.of(context).colorScheme.primaryContainer,
        HomePalette.softGold,
      );
      expect(find.text('No announcements yet'), findsOneWidget);
    },
  );
  testWidgets(
    'presentation feedback respects reduced motion and accessible touch targets',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) => AnnouncementStatusPanel(
                icon: Icons.campaign_outlined,
                title: 'Nothing yet',
                message: 'Check again soon',
                actionLabel: 'Retry',
                onAction: () {},
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.text('Nothing yet'));
      expect(announcementTransitionDuration(context), Duration.zero);
      expect(
        tester.getSize(find.widgetWithText(OutlinedButton, 'Retry')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
