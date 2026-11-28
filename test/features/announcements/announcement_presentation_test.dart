import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/announcements/screens/announcements_screen.dart';
import 'package:mind_mates/features/announcements/data/announcement_repository.dart';
import 'package:mind_mates/features/announcements/widgets/announcement_presentation.dart';
import 'package:mind_mates/features/home/widgets/home_dashboard_widgets.dart';
import 'package:mind_mates/features/announcements/models/announcement.dart';
import 'package:mind_mates/features/announcements/widgets/announcement_card.dart';
import 'package:mind_mates/models/profile_roles.dart';

void main() {
  testWidgets(
    'mobile announcement route uses warm app palette independently of parent theme',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.teal),
          home: AnnouncementsScreen(
            populationRole: PopulationRole.student,
            repository: AnnouncementRepository(fetch: (_) async => []),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.text('Updates from PACC'));
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

  Announcement card(Map<String, dynamic> extra) => Announcement.fromJson('c', {
    'kind': 'link',
    'postType': 'information',
    'title': 'Card title',
    'body': 'Card body',
    'sourceUrl': 'https://news.example/post',
    'status': 'published',
    'publishedAt': DateTime.utc(2026, 11, 14),
    ...extra,
  });
  Widget host(Announcement post, {double scale = 1}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(320, 900),
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          child: AnnouncementCard(announcement: post, onOpenContent: () {}),
        ),
      ),
    ),
  );

  testWidgets('card follows header, text, media, action hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(host(card({'mediaType': 'video'})));
    await tester.pumpAndSettle();
    expect(find.text('PACC · Official update'), findsOneWidget);
    expect(find.textContaining('Information'), findsOneWidget);
    final header = tester.getTopLeft(find.text('PACC · Official update')).dy;
    final title = tester.getTopLeft(find.text('Card title')).dy;
    final body = tester.getTopLeft(find.text('Card body')).dy;
    final media = tester
        .getTopLeft(
          find.byKey(const ValueKey('announcement-video-placeholder')),
        )
        .dy;
    final action = tester.getTopLeft(find.text('Watch Video')).dy;
    expect(
      header < title && title < body && body < media && media < action,
      isTrue,
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    expect(find.text('news.example'), findsOneWidget);
  });

  testWidgets('broken video thumbnail falls back to styled placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        card({
          'mediaType': 'video',
          'imageUrl': 'https://img.example/broken.png',
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('announcement-video-placeholder')),
      findsOneWidget,
    );
    expect(find.text('Image unavailable'), findsNothing);
  });

  testWidgets('standard cards keep type label and fit narrow large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        card({'postType': 'announcement', 'kind': 'original', 'sourceUrl': ''}),
        scale: 1.8,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Announcement'), findsOneWidget);
    expect(find.text('Watch Video'), findsNothing);
    expect(
      find.byKey(const ValueKey('announcement-video-placeholder')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
