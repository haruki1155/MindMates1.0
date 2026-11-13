import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mind_mates/features/counseling/widgets/counselor_unread_badges.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/core/theme/app_theme.dart';
import 'package:mind_mates/features/home/widgets/home_dashboard_widgets.dart';
import 'package:mind_mates/features/counseling/screens/messages_hub_screen.dart';
import 'package:mind_mates/routes/route_names.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'Messages reuses Dashboard gold with readable themed cards ($dark)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const MessagesHubScreen(),
            routes: {
              RouteNames.counselorChat: (_) =>
                  const Scaffold(body: Text('Counselor destination')),
              RouteNames.mindAid: (_) =>
                  const Scaffold(body: Text('MindAid destination')),
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('A space to connect'), findsNothing);
        expect(
          find.text('Choose the support that feels right for you.'),
          findsNothing,
        );
        expect(find.byIcon(Icons.forum_outlined), findsNothing);
        expect(find.text('Conversations'), findsOneWidget);
        expect(tester.getTopLeft(find.text('Conversations')).dy, lessThan(110));
        final context = tester.element(find.text('Messages'));
        expect(Theme.of(context).colorScheme.primary, HomePalette.sun);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          dark ? AppTheme.dark.scaffoldBackgroundColor : HomePalette.background,
        );
        expect(find.byKey(const Key('messages_counselor')), findsOneWidget);
        expect(find.byKey(const Key('messages_mindaid')), findsOneWidget);
        expect(
          find.ancestor(
            of: find.byKey(const Key('messages_counselor')),
            matching: find.byKey(const Key('conversation_list')),
          ),
          findsOneWidget,
        );
        expect(
          find.ancestor(
            of: find.byKey(const Key('messages_mindaid')),
            matching: find.byKey(const Key('conversation_list')),
          ),
          findsOneWidget,
        );
        expect(find.byType(StudentCounselorUnreadBadge), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('messages_counselor')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('messages_counselor')));
        await tester.pumpAndSettle();
        expect(find.text('Counselor destination'), findsOneWidget);
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('messages_mindaid')),
          250,
        );
        expect(find.byKey(const Key('messages_mindaid')), findsOneWidget);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('messages_mindaid')));
        await tester.pumpAndSettle();
        expect(find.text('MindAid destination'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final dark in [false, true]) {
    testWidgets('compact conversation rows align on 320px screens ($dark)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: const MessagesHubScreen(),
        ),
      );
      await tester.pumpAndSettle();
      final counselor = find.byKey(const Key('messages_counselor'));
      final mindaid = find.byKey(const Key('messages_mindaid'));
      expect(tester.getSize(counselor).height, tester.getSize(mindaid).height);
      expect(tester.getSize(counselor).height, 120);
      expect(
        tester.getTopLeft(find.text('Guidance Assistant')).dx,
        tester.getTopLeft(find.text('MindAid')).dx,
      );
      final badge = tester.widget<StudentCounselorUnreadBadge>(
        find.byType(StudentCounselorUnreadBadge),
      );
      expect(badge.backgroundColor, HomePalette.sun);
      expect(badge.foregroundColor, HomePalette.text);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const MessagesHubScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Conversations'), findsOneWidget);
      expect(find.byKey(const Key('messages_counselor')), findsOneWidget);
      expect(find.byKey(const Key('messages_mindaid')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('gold unread badge respects existing reply and read timestamps', (
    tester,
  ) async {
    final reply = Timestamp.fromDate(DateTime(2026, 11, 13, 12));
    Future<void> pump(Map<String, dynamic> thread) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnreadCountBadge(
            count: studentThreadUnread(thread) ? 1 : 0,
            backgroundColor: HomePalette.sun,
            foregroundColor: HomePalette.text,
          ),
        ),
      ),
    );
    await pump({'lastCounselorMessageAt': reply});
    expect(find.text('1'), findsOneWidget);
    await pump({'lastCounselorMessageAt': reply, 'studentReadAt': reply});
    expect(find.text('1'), findsNothing);
    await pump({});
    expect(find.text('1'), findsNothing);
  });
}
