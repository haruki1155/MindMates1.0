import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/screens/client_feedback_form_screen.dart';
import 'package:mind_mates/features/counseling/screens/guidance_satisfaction_survey_screen.dart';
import 'package:mind_mates/features/counseling/screens/pacc_counseling_screen.dart';
import 'package:mind_mates/features/counseling/screens/service_detail_screen.dart';
import 'package:mind_mates/features/counseling/screens/services_screen.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/appointment_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('best contact time opens a picker and preserves cancellation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_paccApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book Appointment').first);
    await tester.pumpAndSettle();
    await _fillPersonalForm(tester);
    await _chooseVisibleOption(tester, 'Male');
    await _chooseVisibleOption(tester, 'Fourth Year');
    await _tapStageButton(tester, 'Continue to Counseling Details');
    tester.view.physicalSize = const Size(430, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final field = find.byKey(const ValueKey('intake-best-time'));
    expect(tester.widget<TextField>(find.descendant(of: field, matching: find.byType(TextField))).readOnly, isTrue);
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final selected = tester.widget<TextFormField>(field).controller!.text;
    expect(selected, '9:00 AM');
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(field).controller!.text, selected);
  });

  testWidgets('appointment time uses one picker without slot chips', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_paccApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book Appointment').first);
    await tester.pumpAndSettle();
    await _advanceToSchedule(tester);
    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const ValueKey('appointment-time-picker')), findsOneWidget);
    expect(find.text('9:00 AM - 11:00 AM'), findsOneWidget);
    expect(find.text('1:00 PM'), findsOneWidget);
    expect(find.text('9:00 AM - 1:00 PM'), findsNothing);
    expect(find.textContaining('Available hours:'), findsNothing);
  });

  testWidgets('unavailable picker time is rejected without losing the selection', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_paccApp());
    await tester.pumpAndSettle();
    await _reachReview(tester);
    await tester.tap(find.byTooltip('Edit Schedule'));
    await tester.pumpAndSettle();
    await _pickAppointmentTime(tester, 11, minute: 30);
    expect(find.textContaining('That time is unavailable'), findsOneWidget);
    expect(find.text('11:00 AM'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('appointment-time-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('11:00 AM'), findsOneWidget);
    await _tapStageButton(tester, 'Continue to Confirm');
    expect(find.text('11:00 AM (PHT)'), findsOneWidget);
  });

  testWidgets('availability retry retains intake and permits booking after recovery', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _RetrySlotsRepository();
    await tester.pumpWidget(_paccApp(appointmentRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book Appointment').first);
    await tester.pumpAndSettle();
    await _advanceToSchedule(tester);
    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('appointment-time-picker')), findsNothing);
    await tester.tap(find.text('Retry appointment times'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    await _pickAppointmentTime(tester, 11);
    await _tapStageButton(tester, 'Continue to Confirm');
    await _tapStageButton(tester, 'Send appointment request');
    expect(repository.appointments.single.bestTime, '9:00 AM');
    expect(repository.appointments.single.scheduledTime, '11:00 AM');
    expect(repository.lastRequestId, isNotEmpty);
  });

  testWidgets('compact appointment picker works on a narrow phone with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_paccApp());
    await tester.pumpAndSettle();
    await _reachReview(tester);
    await tester.tap(find.byTooltip('Edit Schedule'));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(320, 800));
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('appointment-time-picker'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    expect(tester.getSize(picker).height, greaterThanOrEqualTo(48));
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('11:00 AM'), findsOneWidget);
  });

  testWidgets('picker accepts padded server hours and keeps the server label', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _PaddedSlotsRepository();
    await tester.pumpWidget(_paccApp(appointmentRepository: repository));
    await tester.pumpAndSettle();
    await _reachReview(tester);
    await tester.tap(find.byTooltip('Edit Schedule'));
    await tester.pumpAndSettle();
    await _pickAppointmentTime(tester, 9);
    expect(find.text('09:00 AM'), findsOneWidget);
    await _tapStageButton(tester, 'Continue to Confirm');
    await _tapStageButton(tester, 'Send appointment request');
    expect(repository.appointments.single.scheduledTime, '09:00 AM');
  });

  testWidgets('live follow-up offer uses the latest appointment when booking', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final original = AppointmentModel(id: 'completed-live', userId: 'user_1', fullName: 'Leonardo Molar', scheduledAt: DateTime(2026, 4, 10, 11), scheduledTime: '11:00 AM', location: 'PACC', status: 'completed', concern: 'Original concern', contactNumber: '09123456789', email: 'leo@example.com', preferredContactMethod: 'Email', createdAt: DateTime(2026, 4, 1), course: 'BS Information Technology');
    final repository = _LiveAppointmentRepository(original);
    addTearDown(repository.updates.close);
    await tester.pumpWidget(_paccApp(appointmentRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View appointment'));
    await tester.pumpAndSettle();
    repository.appointments[0] = original.copyWith(followUpRecommended: true, followUpStatus: 'offered', followUpMessage: 'A follow-up is available.');
    repository.updates.add([...repository.appointments]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book Follow-up').last);
    await tester.pumpAndSettle();
    await _advanceToSchedule(tester);
    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();
    await _pickAppointmentTime(tester, 11);
    await _tapStageButton(tester, 'Continue to Confirm');
    await _tapStageButton(tester, 'Send appointment request');
    expect(repository.appointments.first.parentAppointmentId, 'completed-live');
  });

  testWidgets('only the latest availability response is shown after returning to a date', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _DelayedSlotsRepository();
    await tester.pumpWidget(_paccApp(appointmentRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book Appointment').first);
    await tester.pumpAndSettle();
    await _advanceToSchedule(tester);
    await tester.tap(find.text('29'));
    await tester.pump();
    await tester.tap(find.text('30'));
    await tester.pump();
    await tester.tap(find.text('29'));
    await tester.pump();
    repository.calls[2].complete([AppointmentSlot(start: DateTime(2026, 4, 29, 10), label: '10:00 AM')]);
    await tester.pump();
    repository.calls[0].complete([AppointmentSlot(start: DateTime(2026, 4, 29, 9), label: '9:00 AM')]);
    repository.calls[1].complete([]);
    await tester.pumpAndSettle();
    await _pickAppointmentTime(tester, 10);
    expect(find.descendant(of: find.byKey(const ValueKey('appointment-time-picker')), matching: find.text('10:00 AM')), findsOneWidget);
    expect(find.text('9:00 AM'), findsNothing);
  });
  testWidgets('services screen matches the mockup structure and actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_servicesApp());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(find.text('PACC Services'), findsOneWidget);
    expect(find.text('All Services'), findsOneWidget);
    expect(find.text('Information Service'), findsOneWidget);
    expect(find.text('Individual Inventory Service'), findsOneWidget);
    expect(find.text('Testing Service'), findsOneWidget);
    expect(find.text('Counseling Service'), findsOneWidget);
    expect(find.text('Career Guidance and Placement Service'), findsOneWidget);
    expect(find.text('Referral Service'), findsOneWidget);
    expect(find.text('Follow-up Service'), findsOneWidget);
    expect(find.text('Key Features'), findsNothing);
    expect(find.text('Learn More'), findsNothing);
    expect(find.text('Inquire'), findsNothing);
    expect(find.text('PACC Support Service'), findsOneWidget);
    expect(find.text('Set Appointment'), findsOneWidget);
    expect(find.text('Take satisfaction survey'), findsNothing);
    expect(find.text('Open client feedback form'), findsNothing);
    expect(find.text('Today'), findsNothing);
    expect(find.text('Secret chat'), findsNothing);
  });

  testWidgets('service cards are tappable and open the detail screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_servicesApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Testing Service'));
    await tester.pumpAndSettle();

    expect(find.byType(ServiceDetailScreen), findsOneWidget);
    expect(find.text('Testing Service'), findsNWidgets(2));
    expect(
      find.textContaining('psychological tests and non-psychometric devices'),
      findsOneWidget,
    );
    expect(find.text('Set Appointment'), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ServiceDetailScreen), findsNothing);
    expect(find.byType(ServicesScreen), findsOneWidget);
  });

  testWidgets('information service shows its official inquiry guide', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_servicesApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Information Service'));
    await tester.pumpAndSettle();

    expect(find.text('HOW TO AVAIL THIS SERVICE'), findsOneWidget);
    expect(find.text('SERVICE INFORMATION'), findsOneWidget);
    expect(find.text('Make an Inquiry'), findsOneWidget);
    expect(find.text('Transaction Complete'), findsOneWidget);
  });

  testWidgets('counseling detail screen shows the appointment CTA', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_servicesApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Counseling Service'));
    await tester.pumpAndSettle();

    expect(find.byType(ServiceDetailScreen), findsOneWidget);
    expect(
      find.textContaining('"heart" of the guidance program'),
      findsOneWidget,
    );
    expect(find.text('Appointment Support'), findsOneWidget);
    expect(find.text('CONFIDENTIAL COUNSELING'), findsOneWidget);
    expect(find.text('Schedule a Counseling Session'), findsOneWidget);
    expect(find.text('Set Appointment'), findsOneWidget);

    await tester.tap(find.text('Set Appointment'));
    await tester.pumpAndSettle();

    expect(find.byType(PaccCounselingScreen), findsOneWidget);
  });

  testWidgets('follow-up expands official procedures in place', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_servicesApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Follow-up Service'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Follow-up Service'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -650));
    await tester.pumpAndSettle();

    expect(find.text('Adding, Changing & Dropping Subjects'), findsOneWidget);
    expect(find.text('Shifting of Course'), findsOneWidget);
    expect(find.byType(ServiceDetailScreen), findsOneWidget);

    await tester.tap(find.text('Adding, Changing & Dropping Subjects'));
    await tester.pumpAndSettle();
    expect(find.textContaining('if necessary.'), findsOneWidget);

    await tester.ensureVisible(find.text('Shifting of Course'));
    await tester.tap(find.text('Shifting of Course'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('STEP 4 OF 4'));
    expect(find.text('STEP 4 OF 4'), findsOneWidget);
    expect(find.byType(ServiceDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('career guidance detail opens the student satisfaction survey', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_servicesApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Career Guidance and Placement Service'));
    await tester.pumpAndSettle();

    expect(find.text('Available Forms'), findsOneWidget);
    expect(find.text('SERVICE EVALUATION'), findsOneWidget);
    expect(find.text('Guidance Services Student Satisfaction'), findsOneWidget);
    expect(find.text('CLIENT EXPERIENCE'), findsOneWidget);
    expect(find.text('Client Feedback Form'), findsOneWidget);

    await tester.tap(find.text('Open Satisfaction Survey'));
    await tester.pumpAndSettle();

    expect(find.byType(GuidanceSatisfactionSurveyScreen), findsOneWidget);
    expect(find.text('Student Satisfaction Survey'), findsOneWidget);
  });

  testWidgets('career guidance detail opens the client feedback form', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_servicesApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Career Guidance and Placement Service'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Client Feedback Form'));
    await tester.pumpAndSettle();

    expect(find.byType(ClientFeedbackFormScreen), findsOneWidget);
    expect(find.text('STEP 1 OF 3'), findsOneWidget);
    expect(find.text('Client information'), findsOneWidget);
  });

  testWidgets('services Back returns to the previous screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ServicesScreen())),
              child: const Text('Open services'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open services'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Open services'), findsOneWidget);
    expect(find.byType(ServicesScreen), findsNothing);
  });

  testWidgets('services root Back falls back to Home', (tester) async {
    await tester.pumpWidget(
      MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        initialRoute: '/services-root',
        routes: {
          '/services-root': (_) => const ServicesScreen(),
          RouteNames.home: (_) => const Scaffold(body: Text('Home target')),
        },
      ),
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Home target'), findsOneWidget);
  });

  testWidgets('services layout has no overflow on a narrow phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_servicesApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Set Appointment'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('services keeps the main navigation visible', (tester) async {
    await tester.pumpWidget(_servicesApp());
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Appointment'), findsOneWidget);
    expect(find.text('Secret Chat'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets('set appointment opens PACC appointment flow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_servicesApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Set Appointment'),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set Appointment'));
    await tester.pumpAndSettle();

    expect(find.byType(PaccCounselingScreen), findsOneWidget);
    expect(find.text('My appointments'), findsOneWidget);
    expect(find.text('No upcoming appointments'), findsOneWidget);
    expect(find.text('Book Appointment'), findsOneWidget);
  });

  testWidgets('personal information validates before counseling is shown', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_paccApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book Appointment').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('intake')), findsOneWidget);
    expect(find.byKey(const ValueKey('counselingDetails')), findsNothing);
    expect(find.text('Preferred Contact Method*'), findsNothing);
    await _tapStageButton(tester, 'Continue to Counseling Details');
    expect(find.text('Please complete all required fields.'), findsOneWidget);
    expect(find.byKey(const ValueKey('intake')), findsOneWidget);

    await _fillPersonalForm(tester);
    await _chooseVisibleOption(tester, 'Male');
    await _chooseVisibleOption(tester, 'Fourth Year');
    await _tapStageButton(tester, 'Continue to Counseling Details');
    expect(find.byKey(const ValueKey('counselingDetails')), findsOneWidget);
    expect(find.byKey(const ValueKey('intake')), findsNothing);
    expect(find.text('Preferred Contact Method*'), findsOneWidget);

    // The counseling section must enforce its *own* required fields.
    await _tapStageButton(tester, 'Continue to Date & Time');
    expect(find.text('Please complete all required fields.'), findsOneWidget);
    expect(find.byKey(const ValueKey('counselingDetails')), findsOneWidget);
  });

  testWidgets('intake Back and Continue retain personal and counseling values', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_paccApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book Appointment').first);
    await tester.pumpAndSettle();
    await _fillPersonalForm(tester);
    await _chooseVisibleOption(tester, 'Male');
    await _chooseVisibleOption(tester, 'Fourth Year');
    await _tapStageButton(tester, 'Continue to Counseling Details');
    await _fillCounselingForm(tester);
    await _chooseVisibleOption(tester, 'Email');
    await _chooseVisibleOption(tester, 'No');

    await tester.tap(find.byTooltip('Back to personal information'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('intake')), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byKey(const ValueKey('intake-address')))
          .controller!.text,
      'Urdaneta City',
    );
    await _tapStageButton(tester, 'Continue to Counseling Details');
    expect(
      tester.widget<TextFormField>(find.byKey(const ValueKey('intake-concern')))
          .controller!.text,
      'I feel overwhelmed and would like to talk to someone.',
    );
    await _tapStageButton(tester, 'Continue to Date & Time');
    expect(find.text('Appointment Schedule'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to counseling details'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('counselingDetails')), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byKey(const ValueKey('intake-best-time')))
          .controller!.text,
      '9:00 AM',
    );
  });

  testWidgets('appointment flow creates an in-memory appointment', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeAppointmentRepository();
    await tester.pumpWidget(_paccApp(appointmentRepository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Book Appointment').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('intake')), findsOneWidget);
    await _advanceToSchedule(tester);
    expect(find.text('Appointment Schedule'), findsOneWidget);
    expect(find.text('April 2026'), findsOneWidget);

    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();
    expect(find.text('Choose Time'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Philippine Time (PHT)'), findsOneWidget);
    expect(find.textContaining('All counseling sessions are confidential'), findsNothing);
    expect(find.textContaining('PACC handles your information'), findsOneWidget);
    expect(find.text('Thursday, April 30'), findsOneWidget);

    await _pickAppointmentTime(tester, 11);
    await tester.pumpAndSettle();
    await _tapStageButton(tester, 'Continue to Confirm');
    expect(find.text('Review request'), findsOneWidget);
    expect(find.byTooltip('Edit Personal Information'), findsOneWidget);
    expect(find.byTooltip('Edit Counseling Details'), findsOneWidget);
    expect(find.byTooltip('Edit Schedule'), findsOneWidget);
    await _tapStageButton(tester, 'Send appointment request');
    expect(find.text('Request received'), findsOneWidget);
    expect(find.text('Awaiting confirmation'), findsOneWidget);
    expect(find.textContaining('Philippine Time (PHT)'), findsOneWidget);
    expect(repository.appointments, hasLength(1));
    expect(repository.appointments.single.address, 'Urdaneta City');
    expect(repository.appointments.single.concern,
        'I feel overwhelmed and would like to talk to someone.');
    expect(repository.appointments.single.scheduledTime, '11:00 AM');
    expect(repository.appointments.single.status, 'requested');
    expect(repository.lastRequestId, isNotEmpty);

    await tester.tap(find.text('Back to Appointments'));
    await tester.pumpAndSettle();
    expect(find.text('APR'), findsOneWidget);
    expect(find.text('11:00 AM \u00b7 Philippine Time'), findsOneWidget);
    expect(find.text('I feel overwhelmed and would like to talk to someone.'),
        findsNothing);
  });

  testWidgets('review personal Edit retains the schedule and counseling draft', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeAppointmentRepository();
    await tester.pumpWidget(_paccApp(appointmentRepository: repository));
    await tester.pumpAndSettle();
    await _reachReview(tester);

    await tester.tap(find.byTooltip('Edit Personal Information'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('intake')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('intake-address')),
        'Mapandan, Pangasinan');
    await _tapStageButton(tester, 'Save and return to review');
    expect(find.text('Review request'), findsOneWidget);
    expect(find.text('Mapandan, Pangasinan'), findsOneWidget);
    expect(find.text('11:00 AM (PHT)'), findsOneWidget);
    expect(find.text('9:00 AM'), findsOneWidget);

    await _tapStageButton(tester, 'Send appointment request');
    expect(repository.appointments.single.address, 'Mapandan, Pangasinan');
    expect(repository.appointments.single.scheduledTime, '11:00 AM');
  });

  testWidgets('review counseling Edit preserves personal values and slot', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeAppointmentRepository();
    await tester.pumpWidget(_paccApp(appointmentRepository: repository));
    await tester.pumpAndSettle();
    await _reachReview(tester);

    await tester.tap(find.byTooltip('Edit Counseling Details'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('counselingDetails')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('intake-concern')),
        'I would like to discuss time management.');
    await _tapStageButton(tester, 'Save and return to review');
    expect(find.text('I would like to discuss time management.'), findsOneWidget);
    expect(find.text('Urdaneta City'), findsOneWidget);
    expect(find.text('11:00 AM (PHT)'), findsOneWidget);

    await _tapStageButton(tester, 'Send appointment request');
    expect(repository.appointments.single.concern,
        'I would like to discuss time management.');
    expect(repository.appointments.single.scheduledTime, '11:00 AM');
  });

  testWidgets('review Schedule Edit retains intake and uses provider slot', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeAppointmentRepository();
    await tester.pumpWidget(_paccApp(appointmentRepository: repository));
    await tester.pumpAndSettle();
    await _reachReview(tester);

    await tester.tap(find.byTooltip('Edit Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Appointment Schedule'), findsOneWidget);
    await _pickAppointmentTime(tester, 9);
    await tester.pumpAndSettle();
    await _tapStageButton(tester, 'Continue to Confirm');
    expect(find.text('Review request'), findsOneWidget);
    expect(find.text('9:00 AM (PHT)'), findsOneWidget);
    expect(find.text('Urdaneta City'), findsOneWidget);

    await _tapStageButton(tester, 'Send appointment request');
    expect(repository.appointments.single.scheduledTime, '9:00 AM');
    expect(repository.appointments.single.concern,
        'I feel overwhelmed and would like to talk to someone.');
  });

  testWidgets('cancelling schedule Edit restores the prior selected slot', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_paccApp());
    await tester.pumpAndSettle();
    await _reachReview(tester);

    await tester.tap(find.byTooltip('Edit Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('29'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to review'));
    await tester.pumpAndSettle();
    expect(find.text('Review request'), findsOneWidget);
    expect(find.text('Thursday, April 30, 2026'), findsOneWidget);
    expect(find.text('11:00 AM (PHT)'), findsOneWidget);
  });

  testWidgets('review cannot submit invalid personal changes via Back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeAppointmentRepository();
    await tester.pumpWidget(_paccApp(appointmentRepository: repository));
    await tester.pumpAndSettle();
    await _reachReview(tester);
    await tester.tap(find.byTooltip('Edit Personal Information'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('intake-email')), 'invalid');
    await tester.tap(find.byTooltip('Back to review'));
    await tester.pumpAndSettle();
    expect(find.text('Review request'), findsOneWidget);
    await _tapStageButton(tester, 'Send appointment request');
    expect(find.byKey(const ValueKey('intake')), findsOneWidget);
    expect(repository.appointments, isEmpty);
  });

  testWidgets('appointment intake accepts an empty middle initial', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_paccApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book Appointment').first);
    await tester.pumpAndSettle();
    await _fillPersonalForm(tester);
    await tester.enterText(find.byKey(const ValueKey('intake-middle-initial')), '');
    await _chooseVisibleOption(tester, 'Male');
    await _chooseVisibleOption(tester, 'Fourth Year');
    await _tapStageButton(tester, 'Continue to Counseling Details');
    await _fillCounselingForm(tester);
    await _chooseVisibleOption(tester, 'Email');
    await _chooseVisibleOption(tester, 'No');
    await _tapStageButton(tester, 'Continue to Date & Time');
    expect(find.text('Appointment Schedule'), findsOneWidget);
  });

  testWidgets('appointment details and MindMate calendar work', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_paccApp());
    await tester.pumpAndSettle();
    await _createAppointment(tester);

    await tester.tap(find.text('View appointment'));
    await tester.pumpAndSettle();
    expect(find.text('Appointment details'), findsOneWidget);
    expect(find.text('Email \u00b7 +63 912 345 6789'), findsOneWidget);

    Navigator.of(tester.element(find.text('Appointment details'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add to Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Appointment Calendar'), findsOneWidget);
    expect(find.text('April 30, 2026'), findsOneWidget);
  });

  testWidgets('past appointment dates are disabled', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_paccApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book Appointment').first);
    await tester.pumpAndSettle();
    await _advanceToSchedule(tester);

    await tester.tap(find.text('1').last);
    await tester.pumpAndSettle();

    expect(find.text('Appointment Schedule'), findsOneWidget);
    expect(find.text('Choose Time'), findsNothing);
  });

  testWidgets('shows a safe no-slot message supplied by the backend', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeAppointmentRepository()
      ..slotAvailabilityMessage =
          'The counselor is unavailable on this date. Please choose another available date.';
    await tester.pumpWidget(_paccApp(appointmentRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book Appointment').first);
    await tester.pumpAndSettle();
    await _advanceToSchedule(tester);
    await tester.ensureVisible(find.text('29'));
    await tester.tap(find.text('29'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The counselor is unavailable on this date. Please choose another available date.',
      ),
      findsOneWidget,
    );
  });
}

Widget _servicesApp() {
  return MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: const ServicesScreen(),
  );
}

Widget _paccApp({_FakeAppointmentRepository? appointmentRepository}) {
  final userProvider = UserProvider(_FakeUserRepository())
    ..setUser(
      const UserModel(
        id: 'user_1',
        email: 'leo@example.com',
        firstName: 'Leonardo',
        middleName: 'M',
        lastName: 'Molar',
        course: 'BS Information Technology',
      ),
    );

  final appointments = appointmentRepository ?? _FakeAppointmentRepository();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: userProvider),
      ChangeNotifierProvider(create: (_) => AppointmentProvider(appointments)),
    ],
    child: MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: PaccCounselingScreen(nowProvider: () => DateTime(2026, 4, 15, 9)),
    ),
  );
}

Future<void> _createAppointment(WidgetTester tester) async {
  await tester.tap(find.text('Book Appointment').first);
  await tester.pumpAndSettle();
  await _advanceToSchedule(tester);
  await tester.tap(find.text('30'));
  await tester.pumpAndSettle();
  await _pickAppointmentTime(tester, 11);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue to Confirm'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Send appointment request'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Back to Appointments'));
  await tester.pumpAndSettle();
}

Future<void> _tapStageButton(WidgetTester tester, String label) async {
  final control = find.text(label);
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _reachReview(WidgetTester tester) async {
  await tester.tap(find.text('Book Appointment').first);
  await tester.pumpAndSettle();
  await _advanceToSchedule(tester);
  await tester.tap(find.text('30'));
  await tester.pumpAndSettle();
  await _pickAppointmentTime(tester, 11);
  await tester.pumpAndSettle();
  await _tapStageButton(tester, 'Continue to Confirm');
  expect(find.text('Review request'), findsOneWidget);
}

Future<void> _advanceToSchedule(WidgetTester tester) async {
  await _fillPersonalForm(tester);
  await _chooseVisibleOption(tester, 'Male');
  await _chooseVisibleOption(tester, 'Fourth Year');
  await _tapStageButton(tester, 'Continue to Counseling Details');

  await _fillCounselingForm(tester);
  await _chooseVisibleOption(tester, 'Email');
  await _chooseVisibleOption(tester, 'No');
  await _tapStageButton(tester, 'Continue to Date & Time');
}

Future<void> _fillPersonalForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const ValueKey('intake-age')), '20');
  await tester.enterText(find.byKey(const ValueKey('intake-address')), 'Urdaneta City');
  await tester.enterText(find.byKey(const ValueKey('intake-contact')), '+63 912 345 6789');
  await tester.enterText(find.byKey(const ValueKey('intake-email')), 'leo@example.com');
  await tester.enterText(find.byKey(const ValueKey('intake-facebook')), 'facebook.com/leo');
}

Future<void> _fillCounselingForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('intake-concern')),
    'I feel overwhelmed and would like to talk to someone.',
  );
  await tester.tap(find.byKey(const ValueKey('intake-best-time')));
  await _acceptTime(tester, 9);
}

Future<void> _chooseVisibleOption(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _FakeUserRepository extends UserRepository {}

class _DelayedSlotsRepository extends _FakeAppointmentRepository {
  final calls = <Completer<List<AppointmentSlot>>>[];
  @override
  Future<List<AppointmentSlot>> getAvailableSlots(DateTime date) {
    final call = Completer<List<AppointmentSlot>>();
    calls.add(call);
    return call.future;
  }
}

class _FakeAppointmentRepository extends AppointmentRepository {
  _FakeAppointmentRepository({List<AppointmentModel> appointments = const []})
    : appointments = [...appointments];

  final List<AppointmentModel> appointments;
  bool shouldFail = false;
  String? slotAvailabilityMessage;
  String? lastRequestId;
  @override
  String? get lastSlotAvailabilityMessage => slotAvailabilityMessage;
  @override
  Future<List<AppointmentSlot>> getAvailableSlots(DateTime date) async {
    if (date.year == 2026 && date.month == 4 && date.day == 30) {
      return [
        AppointmentSlot(start: DateTime(2026, 4, 30, 9), label: '9:00 AM'),
        AppointmentSlot(start: DateTime(2026, 4, 30, 10), label: '10:00 AM'),
        AppointmentSlot(start: DateTime(2026, 4, 30, 11), label: '11:00 AM'),
        AppointmentSlot(start: DateTime(2026, 4, 30, 13), label: '1:00 PM'),
      ];
    }

    return [];
  }

  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) async {
    if (shouldFail) throw StateError('load failed');
    return appointments.where((item) => item.userId == userId).toList();
  }

  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      Stream.value(
        appointments.where((item) => item.userId == userId).toList(),
      );

  @override
  Future<AppointmentModel> createAppointment(
    AppointmentModel appointment, {
    String? requestId,
  }) async {
    lastRequestId = requestId;
    if (shouldFail) throw StateError('save failed');
    final created = appointment.copyWith(
      id: 'appointment_${appointments.length + 1}',
    );
    appointments.insert(0, created);
    return created;
  }
}

Future<void> _acceptTime(WidgetTester tester, int hour, {int minute = 0}) async {
  tester.view.physicalSize = const Size(430, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final inputs = find.descendant(of: find.byType(TimePickerDialog), matching: find.byType(TextField));
  await tester.enterText(inputs.at(0), hour.toString());
  await tester.enterText(inputs.at(1), minute.toString().padLeft(2, '0'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _pickAppointmentTime(WidgetTester tester, int hour, {int minute = 0}) async {
  await tester.tap(find.byKey(const ValueKey('appointment-time-picker')));
  await _acceptTime(tester, hour, minute: minute);
}

class _RetrySlotsRepository extends _FakeAppointmentRepository {
  int calls = 0;
  @override
  Future<List<AppointmentSlot>> getAvailableSlots(DateTime date) async {
    if (++calls == 1) throw StateError('temporary availability error');
    return super.getAvailableSlots(date);
  }
}

class _PaddedSlotsRepository extends _FakeAppointmentRepository {
  @override
  Future<List<AppointmentSlot>> getAvailableSlots(DateTime date) async => [
    for (final slot in await super.getAvailableSlots(date))
      AppointmentSlot(start: slot.start, label: slot.label.padLeft(8, '0')),
  ];
}

class _LiveAppointmentRepository extends _FakeAppointmentRepository {
  _LiveAppointmentRepository(AppointmentModel initial) : super(appointments: [initial]);
  final updates = StreamController<List<AppointmentModel>>.broadcast();
  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) => updates.stream;
}
