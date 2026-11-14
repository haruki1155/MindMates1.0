import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/screens/pacc_counseling_screen.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/appointment_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('saved personal information is restored when booking reopens', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(_paccApp(_EmptyAppointmentRepository(), showBottomNavigation: false));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('intake-facebook')), 'Saved contact');
    await tester.ensureVisible(find.text('Save personal information'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save personal information'));
    await tester.pumpAndSettle();
    expect(find.text('Personal information saved on this device.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_paccApp(_EmptyAppointmentRepository(), showBottomNavigation: false));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('intake-facebook'))).controller!.text, 'Saved contact');
  });
  testWidgets('personal Continue scrolls with the form above the keyboard', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(_paccApp(_EmptyAppointmentRepository()));
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('appointment-stage-action'));
    expect(find.ancestor(of: action, matching: find.byType(Scrollable)), findsWidgets);
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(action).dy, lessThanOrEqualTo(544));
  });
  testWidgets('personal stage uses the compact mockup header and linear progress', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      final font = File('C:/Windows/Fonts/segoeui.ttf');
      if (await font.exists()) {
        final loader = FontLoader('Roboto')..addFont(font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
      }
    });
    await tester.pumpWidget(_paccApp(_EmptyAppointmentRepository(), showBottomNavigation: false));
    await tester.pumpAndSettle();
    expect(find.text('Your information'), findsWidgets);
    expect(find.text("Let's start with you"), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final field = tester.widget<TextField>(find.descendant(of: find.byKey(const ValueKey('intake-email')), matching: find.byType(TextField)));
    expect(field.decoration!.fillColor, Colors.white);
    expect(find.byKey(const ValueKey('appointment-stage-action')), findsOneWidget);
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('.superpowers/sdd/MindMate_Appointment_Implementation_Plan/screenshots');
      await directory.create(recursive: true);
      await File('${directory.path}/personal-information.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
  testWidgets('personal choices have accessible touch targets', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_paccApp(_EmptyAppointmentRepository(), showBottomNavigation: false));
    await tester.pumpAndSettle();
    final choice = find.widgetWithText(InkWell, 'Female');
    expect(tester.getSize(choice).height, greaterThanOrEqualTo(48));
  });

  testWidgets('name fields remain usable on a narrow phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _paccApp(_EmptyAppointmentRepository(), showBottomNavigation: false),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('intake')), findsOneWidget);
    expect(find.byKey(const ValueKey('counselingDetails')), findsNothing);
    expect(find.text('Preferred Contact Method*'), findsNothing);
    for (final hint in ['Last Name', 'First Name', 'M.I. (optional)']) {
      final field = find.ancestor(
        of: find.text(hint),
        matching: find.byType(TextFormField),
      );
      expect(field, findsOneWidget);
      expect(tester.getSize(field).width, greaterThanOrEqualTo(100));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal fields expose appropriate keyboards and touch heights', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _paccApp(_EmptyAppointmentRepository(), showBottomNavigation: false),
    );
    await tester.pumpAndSettle();

    for (final spec in <(String, TextInputType)>[
      ('intake-age', TextInputType.number),
      ('intake-contact', TextInputType.phone),
      ('intake-email', TextInputType.emailAddress),
    ]) {
      final field = find.byKey(ValueKey(spec.$1));
      expect(tester.widget<TextField>(find.descendant(of: field, matching: find.byType(TextField))).keyboardType, spec.$2);
      expect(tester.getSize(field).height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('startBooking opens Personal Information after an empty load', (
    tester,
  ) async {
    await tester.pumpWidget(
      _paccApp(_EmptyAppointmentRepository(), showBottomNavigation: false),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('intake')), findsOneWidget);
    expect(find.byKey(const ValueKey('counselingDetails')), findsNothing);
    expect(find.text('Continue to Counseling Details'), findsOneWidget);
  });

  testWidgets(
    'startBooking opens Personal Information after Home loaded appointments',
    (tester) async {
      final repository = _EmptyAppointmentRepository();
      final appointments = AppointmentProvider(repository);
      await appointments.loadAppointments('user_1');

      await tester.pumpWidget(_paccAppWithProvider(appointments));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('intake')), findsOneWidget);
      expect(find.byKey(const ValueKey('counselingDetails')), findsNothing);
    },
  );

  testWidgets(
    'startBooking does not open intake while appointment loading is pending',
    (tester) async {
      final pendingLoad = Completer<List<AppointmentModel>>();
      await tester.pumpWidget(
        _paccApp(_SequencedAppointmentRepository([() => pendingLoad.future])),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('appointmentLoading')), findsOneWidget);
      expect(find.byKey(const ValueKey('intake')), findsNothing);
    },
  );

  testWidgets(
    'startBooking shows a retryable error after appointment loading fails',
    (tester) async {
      await tester.pumpWidget(
        _paccApp(
          _SequencedAppointmentRepository([
            () => Future<List<AppointmentModel>>.error(StateError('offline')),
            () async => const [],
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('appointmentLoadError')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('intake')), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('appointmentLoadError')), findsNothing);
      expect(find.byKey(const ValueKey('intake')), findsOneWidget);
      expect(find.byKey(const ValueKey('counselingDetails')), findsNothing);
    },
  );

  testWidgets('startBooking preserves the active appointment protection', (
    tester,
  ) async {
    final appointments = _ActiveAppointmentRepository();
    await tester.pumpWidget(_paccApp(appointments));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('You already have an active appointment'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('intake')), findsNothing);
    expect(find.byKey(const ValueKey('counselingDetails')), findsNothing);
    expect(appointments.createCalls, 0);
  });
}

Widget _paccApp(
  AppointmentRepository repository, {
  bool showBottomNavigation = true,
}) => MultiProvider(
  providers: [
    ChangeNotifierProvider(
      create: (_) =>
          UserProvider(_FakeUserRepository())
            ..setUser(const UserModel(id: 'user_1', email: 'user@example.com')),
    ),
    ChangeNotifierProvider(create: (_) => AppointmentProvider(repository)),
  ],
  child: MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
    home: PaccCounselingScreen(
      startBooking: true,
      showBottomNavigation: showBottomNavigation,
    ),
  ),
);

Widget _paccAppWithProvider(AppointmentProvider provider) => MultiProvider(
  providers: [
    ChangeNotifierProvider(
      create: (_) =>
          UserProvider(_FakeUserRepository())
            ..setUser(const UserModel(id: 'user_1', email: 'user@example.com')),
    ),
    ChangeNotifierProvider<AppointmentProvider>.value(value: provider),
  ],
  child: MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),home: PaccCounselingScreen(startBooking: true)),
);

class _FakeUserRepository extends UserRepository {}

class _ActiveAppointmentRepository extends AppointmentRepository {
  int createCalls = 0;

  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) async => [
    AppointmentModel(
      id: 'active_1',
      userId: userId,
      fullName: 'Existing User',
      scheduledAt: DateTime(2026, 10, 12, 9),
      scheduledTime: '9:00 AM',
      location: 'PACC',
      status: 'requested',
      concern: 'Existing concern',
      contactNumber: '09123456789',
      email: 'user@example.com',
      preferredContactMethod: 'Email',
      createdAt: DateTime(2026, 10, 9),
    ),
  ];

  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      Stream.value([]);

  @override
  Future<AppointmentModel> createAppointment(
    AppointmentModel appointment, {
    String? requestId,
  }) async {
    createCalls += 1;
    return appointment.copyWith(id: 'created_1');
  }
}

class _EmptyAppointmentRepository extends AppointmentRepository {
  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) async =>
      const [];

  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      const Stream<List<AppointmentModel>>.empty();
}

class _SequencedAppointmentRepository extends AppointmentRepository {
  _SequencedAppointmentRepository(this._loads);

  final List<Future<List<AppointmentModel>> Function()> _loads;
  int _loadIndex = 0;

  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) {
    final index = _loadIndex++;
    return _loads[index.clamp(0, _loads.length - 1)]();
  }

  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      const Stream<List<AppointmentModel>>.empty();
}
