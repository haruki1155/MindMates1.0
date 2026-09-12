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
    expect(find.text('PAACC Support Service'), findsOneWidget);
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

  testWidgets('follow-up shows procedure placeholders without removed forms', (
    tester,
  ) async {
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

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('Reactivation of Enrollment'), findsOneWidget);
    expect(
      find.textContaining('The reactivation process helps returning students'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('reactivation-procedure-steps')),
      findsOneWidget,
    );
    expect(find.text('Open Reactivation Form'), findsNothing);
    expect(find.text('Student Shifting'), findsOneWidget);
    expect(
      find.textContaining('The shifting process helps students'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('shifting-procedure-steps')),
      findsOneWidget,
    );
    expect(find.text('Open Shifting Form'), findsNothing);
    expect(find.text('Available Forms'), findsNothing);
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
      MaterialApp(
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
      MaterialApp(
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
    expect(find.text('PACC Counseling'), findsOneWidget);
    expect(find.text('No upcoming appointments'), findsOneWidget);
    expect(find.text('Appoint a Session'), findsOneWidget);
  });

  testWidgets('appointment flow creates an in-memory appointment', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_paccApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Appoint New'));
    await tester.pumpAndSettle();
    expect(find.text('Counseling Intake Form'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Please complete all required fields.'), findsOneWidget);

    await _fillVisibleForm(tester);
    await _chooseVisibleOption(tester, 'Male');
    await _chooseVisibleOption(tester, 'Fourth Year');
    await _chooseVisibleOption(tester, 'Email');
    await _chooseVisibleOption(tester, 'No');

    await tester.ensureVisible(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Appointment Schedule'), findsOneWidget);
    expect(find.text('April 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to intake form'));
    await tester.pumpAndSettle();
    expect(find.text('Counseling Intake Form'), findsOneWidget);
    expect(
      find.text('I feel overwhelmed and would like to talk to someone.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();
    expect(find.text('Choose Time'), findsOneWidget);
    expect(find.text('Thursday, April 30'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Appointment Schedule'), findsOneWidget);

    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('11:00 AM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Appointment').last);
    await tester.pumpAndSettle();
    expect(find.text('Confirm Appointment'), findsOneWidget);

    await tester.tap(find.text('Back to My Appointments'));
    await tester.pumpAndSettle();
    expect(find.text('Molar, Leonardo M.'), findsOneWidget);
    expect(find.text('Thursday, April 30, 2026'), findsOneWidget);
    expect(find.text('11:00 AM'), findsOneWidget);
    expect(
      find.text('I feel overwhelmed and would like to talk to someone.'),
      findsOneWidget,
    );
  });

  testWidgets('appointment details and MindMate calendar work', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_paccApp());
    await tester.pumpAndSettle();
    await _createAppointment(tester);

    await tester.tap(find.text('View Details'));
    await tester.pumpAndSettle();
    expect(find.text('Appointment Details'), findsOneWidget);
    expect(find.text('Email | +63 912 345 6789'), findsOneWidget);

    Navigator.of(tester.element(find.text('Appointment Details'))).pop();
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
    await tester.tap(find.text('Appoint New'));
    await tester.pumpAndSettle();
    await _fillVisibleForm(tester);
    await _chooseVisibleOption(tester, 'Male');
    await _chooseVisibleOption(tester, 'Fourth Year');
    await _chooseVisibleOption(tester, 'Email');
    await _chooseVisibleOption(tester, 'No');
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();

    expect(find.text('Appointment Schedule'), findsOneWidget);
    expect(find.text('Choose Time'), findsNothing);
  });
}

Widget _servicesApp() {
  return MaterialApp(
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
    child: MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: PaccCounselingScreen(nowProvider: () => DateTime(2026, 4, 15, 9)),
    ),
  );
}

Future<void> _createAppointment(WidgetTester tester) async {
  await tester.tap(find.text('Appoint New'));
  await tester.pumpAndSettle();
  await _fillVisibleForm(tester);
  await _chooseVisibleOption(tester, 'Male');
  await _chooseVisibleOption(tester, 'Fourth Year');
  await _chooseVisibleOption(tester, 'Email');
  await _chooseVisibleOption(tester, 'No');

  await tester.ensureVisible(find.text('Next'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('30'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('11:00 AM'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirm Appointment').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Back to My Appointments'));
  await tester.pumpAndSettle();
}

Future<void> _fillVisibleForm(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(3), '20');
  await tester.enterText(fields.at(4), 'Urdaneta City');
  await tester.enterText(fields.at(5), '+63 912 345 6789');
  await tester.enterText(fields.at(6), 'leo@example.com');
  await tester.enterText(fields.at(7), 'facebook.com/leo');
  await tester.enterText(
    fields.at(8),
    'I feel overwhelmed and would like to talk to someone.',
  );
  await tester.enterText(fields.at(9), 'Weekday mornings');
}

Future<void> _chooseVisibleOption(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _FakeUserRepository extends UserRepository {}

class _FakeAppointmentRepository extends AppointmentRepository {
  _FakeAppointmentRepository({List<AppointmentModel> appointments = const []})
    : appointments = [...appointments];

  final List<AppointmentModel> appointments;
  bool shouldFail = false;

  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) async {
    if (shouldFail) throw StateError('load failed');
    return appointments.where((item) => item.userId == userId).toList();
  }

  @override
  Future<AppointmentModel> createAppointment(
    AppointmentModel appointment,
  ) async {
    if (shouldFail) throw StateError('save failed');
    final created = appointment.copyWith(
      id: 'appointment_${appointments.length + 1}',
    );
    appointments.insert(0, created);
    return created;
  }
}
