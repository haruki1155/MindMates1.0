import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/widgets/service_inquiry_composer.dart';
import 'package:mind_mates/features/counseling/screens/services_screen.dart';
import 'package:mind_mates/features/counseling/screens/service_detail_screen.dart';
import 'package:mind_mates/routes/route_names.dart';

void main() {
  for (final field in [
    'Personal',
    'Psychological',
    'Social',
    'Educational',
    'Vocational',
  ]) {
    testWidgets('$field inquiry is editable and requires explicit Send', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var sends = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServiceInquiryComposer(
              controller: controller,
              sending: false,
              onSend: () => sends++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Services'));
      await tester.pumpAndSettle();
      for (final service in ServicesScreen.services) {
        expect(find.text(service.title), findsOneWidget);
      }
      await tester.tap(find.text('Information Service'));
      await tester.pumpAndSettle();
      for (final name in [
        'Personal',
        'Psychological',
        'Social',
        'Educational',
        'Vocational',
      ]) {
        expect(find.text('$name Field'), findsOneWidget);
      }
      expect(find.text('General Inquiry'), findsOneWidget);
      await tester.tap(find.text('$field Field'));
      await tester.pumpAndSettle();
      expect(controller.text, contains('specifically the $field Field.'));
      final question = <String, String>{
        'Personal':
            'what information and assistance PACC provides regarding personal concerns',
        'Psychological':
            'what information and guidance PACC provides in this area',
        'Social':
            'what information and support PACC provides regarding social adjustment and relationships',
        'Educational':
            'what educational information and guidance are available to students',
        'Vocational': 'what vocational information and guidance PACC provides',
      }[field]!;
      expect(
        controller.text,
        'Good day! I would like to inquire about Information Service, specifically the $field Field. May I ask $question? Thank you!',
      );
      expect(sends, 0);
      await tester.enterText(find.byType(TextField), 'Edited inquiry');
      await tester.tap(find.byTooltip('Send message'));
      expect(sends, 1);
      expect(controller.text, 'Edited inquiry');
    });
  }

  testWidgets('keeps existing draft unless replacement is confirmed', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'My unsent message');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServiceInquiryComposer(
            controller: controller,
            sending: false,
            onSend: () => fail('automatic send'),
          ),
        ),
      ),
    );
    Future<void> choose() async {
      await tester.tap(find.text('Services'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Information Service'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('General Inquiry'));
      await tester.pumpAndSettle();
    }

    await choose();
    await tester.tap(find.text('Keep draft'));
    await tester.pumpAndSettle();
    expect(controller.text, 'My unsent message');
    await choose();
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(
      controller.text,
      contains('Information Service, specifically General Inquiry'),
    );
  });
  for (final service in ServicesScreen.services.skip(1)) {
    testWidgets('${service.title} topics and General Inquiry', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServiceInquiryComposer(
              controller: controller,
              sending: false,
              onSend: () => fail('automatic send'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Services'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(service.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(service.title));
      await tester.pumpAndSettle();
      for (final topic in serviceInquiryTopics[service.title]!) {
        expect(find.text(topic), findsOneWidget);
        final draft = serviceInquiryDraft(service.title, topic);
        expect(draft, contains(service.title));
        expect(draft, contains(topic));
        expect(draft.length, lessThan(1600));
      }
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Select a PACC service'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      await tester.tap(find.text('Services'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(service.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(service.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text('General Inquiry'));
      await tester.pumpAndSettle();
      expect(
        controller.text,
        contains('${service.title}, specifically General Inquiry'),
      );
    });
  }

  testWidgets(
    'route argument opens topics and small-screen keyboard keeps Send visible',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: const Scaffold(),
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            settings: const RouteSettings(arguments: 'Testing Service'),
            builder: (_) => Scaffold(
              body: ServiceInquiryComposer(
                controller: controller,
                sending: false,
                onSend: () {},
              ),
            ),
          ),
        ),
      );
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/chat');
      await tester.pumpAndSettle();
      expect(
        find.text('What do you want to know about Testing Service?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Testing Schedule'));
      await tester.pumpAndSettle();
      expect(controller.text, contains('Testing Schedule'));
      tester.view.viewInsets = FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Send message').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty and submitting composers disable Send', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    Future<void> pump(bool sending) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServiceInquiryComposer(
            controller: controller,
            sending: sending,
            onSend: () => fail('disabled send'),
          ),
        ),
      ),
    );
    await pump(false);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    controller.text = 'inquiry';
    await pump(true);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Services'))
          .onPressed,
      isNull,
    );
  });
  testWidgets('Ask PACC uses existing chat route with service argument', (
    tester,
  ) async {
    RouteSettings? requestedRoute;
    final service = ServicesScreen.services.firstWhere(
      (s) => s.title == 'Testing Service',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ServiceDetailScreen(service: service),
        onGenerateRoute: (settings) {
          requestedRoute = settings;
          return MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Guidance Assistant')),
          );
        },
      ),
    );
    await tester.tap(find.text('Ask PACC'));
    await tester.pumpAndSettle();
    expect(requestedRoute?.name, RouteNames.counselorChat);
    expect(requestedRoute?.arguments, 'Testing Service');
    expect(find.text('Guidance Assistant'), findsOneWidget);
  });
}
