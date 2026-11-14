import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mind_mates/features/counseling/widgets/appointment_details_sheet.dart';
import 'package:mind_mates/features/counseling/widgets/appointment_presentation.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/providers/appointment_provider.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/services/auth/auth_service.dart';

class TestAuth extends AuthProvider {
  TestAuth() : super(AuthRepository(AuthService()));
  String uid = 'student';
  @override
  String get authenticatedUserId => uid;
  void switchAccount(String value) {
    uid = value;
    notifyListeners();
  }
}

class TestRepository extends AppointmentRepository {
  late AppointmentModel item;
  final updates = StreamController<List<AppointmentModel>>.broadcast();
  Completer<void>? pending;
  Object? failure;
  int calls = 0;
  String? lastAgreementAction, lastAgreementReason;
  int? lastAgreementRevision;
  final agreementRequests = <String>[];
  int? revision;
  DateTime? original;
  @override
  Future<List<AppointmentModel>> fetchAppointments(String userId) async => [
    if (item.userId == userId) item,
  ];
  @override
  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      updates.stream;
  @override
  Future<List<AppointmentSlot>> getAvailableSlots(DateTime date) async => [
    AppointmentSlot(
      start: DateTime(date.year, date.month, date.day, 14),
      label: '2:00 PM',
    ),
  ];
  @override
  Future<void> changeAgreement({required AppointmentModel appointment, required String action, required String requestId, String? reason}) async {
    agreementRequests.add(requestId);
    lastAgreementAction = action;
    lastAgreementReason = reason;
    lastAgreementRevision = appointment.proposalRevision;
    if (failure != null) throw failure!;
    item = item.copyWith(status: action == 'cancel' ? 'cancelled' : 'confirmed', proposalStatus: action == 'cancel' ? 'cancelled' : 'accepted', scheduledAt: action == 'accept' ? item.proposedScheduledAt : item.scheduledAt);
    updates.add([item]);
  }
  @override
  Future<void> rescheduleAppointment({
    required String appointmentId,
    required DateTime expectedScheduledAt,
    required int expectedScheduleRevision, int expectedProposalRevision = 0,
    required DateTime scheduledAt,
    required String requestId,
  }) async {
    calls++;
    revision = expectedScheduleRevision;
    original = expectedScheduledAt;
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
    if (scheduledAt != item.scheduledAt) { item = item.copyWith(
      proposedScheduledAt: scheduledAt, proposedScheduledTime: '2:00 PM',
      proposedBy: 'student', proposalStatus: 'pending', proposalRevision: item.proposalRevision + 1,
    ); }
    updates.add([item]);
  }
}

AppointmentModel appointment(String status) {
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  return AppointmentModel(
    id: 'existing-id',
    userId: 'student',
    fullName: 'Student',
    scheduledAt: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10),
    scheduledTime: '10:00 AM',
    location: 'PACC',
    status: status,
    concern: '',
    contactNumber: '',
    email: '',
    preferredContactMethod: '',
    createdAt: DateTime.now(),
    scheduleRevision: 7,
    hasScheduleRevision: true,
  );
}

Future<void> open(
  WidgetTester tester,
  TestRepository repo,
  TestAuth auth,
  AppointmentProvider provider,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await provider.loadAppointments('student');
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AppointmentProvider>.value(value: provider),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        theme: ThemeData(fontFamily: 'Roboto', colorSchemeSeed: const Color(0xFF285D59)),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppointmentDetailsSheet(context, repo.item),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> select(WidgetTester tester, {bool unchanged = false}) async {
  await tester.tap(find.text('Edit date and time'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose a date'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(unchanged ? '10:00 AM (current)' : '2:00 PM'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(unchanged ? '10:00 AM (current)' : '2:00 PM'));
  await tester.pump();
}

void main() {
  testWidgets('processing indicator pulses and respects reduced motion', (tester) async {
    Widget app(bool reduced) => MaterialApp(home: MediaQuery(data: MediaQueryData(disableAnimations: reduced), child: const AppointmentProcessingIndicator()));
    await tester.pumpWidget(app(false));
    final before = tester.widget<FadeTransition>(find.byType(FadeTransition).last).opacity.value;
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.widget<FadeTransition>(find.byType(FadeTransition).last).opacity.value, isNot(before));
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('processing-indicator-static')), findsOneWidget);
  });

  testWidgets('accept retry keeps request identity after a temporary failure', (tester) async {
    final repo = TestRepository()..item = appointment('confirmed').copyWith(proposalStatus: 'pending', proposedBy: 'counselor', proposalRevision: 2, proposedScheduledAt: appointment('confirmed').scheduledAt.add(const Duration(hours: 1)), proposedScheduledTime: '11:00 AM')..failure = FirebaseFunctionsException(code: 'unavailable', message: 'Try again');
    await open(tester, repo, TestAuth(), AppointmentProvider(repo));
    await tester.tap(find.text('Accept proposed time'));
    await tester.pumpAndSettle();
    repo.failure = null;
    await tester.tap(find.text('Accept proposed time'));
    await tester.pumpAndSettle();
    expect(repo.agreementRequests, hasLength(2));
    expect(repo.agreementRequests[0], repo.agreementRequests[1]);
  });

  testWidgets('cancellation keeps optional reason after failure and can be dismissed', (tester) async {
    final repo = TestRepository()..item = appointment('requested')..failure = FirebaseFunctionsException(code: 'unavailable', message: 'Try again');
    await open(tester, repo, TestAuth(), AppointmentProvider(repo));
    await tester.tap(find.text('Cancel appointment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cancellation-reason')), 'Personal decision');
    await tester.tap(find.text('Confirm cancellation'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('cancellation-reason'))).controller!.text, 'Personal decision');
    expect(repo.item.status, 'requested');
    await tester.tap(find.text('Keep appointment'));
    await tester.pumpAndSettle();
    expect(repo.agreementRequests, hasLength(1));
    expect(repo.item.status, 'requested');
  });

  testWidgets('legacy proposals do not promise a retained reservation', (tester) async {
    final repo = TestRepository()..item = appointment('reschedule_proposed').copyWith(hasScheduleRevision: false, proposalStatus: 'pending', proposedBy: 'counselor', proposedScheduledAt: appointment('confirmed').scheduledAt.add(const Duration(hours: 1)), proposedScheduledTime: '11:00 AM');
    await open(tester, repo, TestAuth(), AppointmentProvider(repo));
    expect(find.text('Current time stays reserved until you both agree.'), findsNothing);
    expect(find.text('PACC must verify the reservation for this older proposal.'), findsOneWidget);
    expect(find.text('Accept proposed time'), findsNothing);
  });

  testWidgets('student can cancel approved appointment without a reason', (tester) async {
    final repo = TestRepository()..item = appointment('confirmed');
    await open(tester, repo, TestAuth(), AppointmentProvider(repo));
    await tester.tap(find.text('Cancel appointment'));
    await tester.pumpAndSettle();
    expect(find.text('Reason (optional)'), findsOneWidget);
    await tester.tap(find.text('Confirm cancellation'));
    await tester.pumpAndSettle();
    expect(repo.lastAgreementAction, 'cancel');
    expect(repo.lastAgreementReason, '');
    expect(repo.item.status, 'cancelled');
  });

  testWidgets('PACC proposal shows reserved and proposed times with student accept', (tester) async {
    final repo = TestRepository()..item = appointment('confirmed').copyWith(proposalStatus: 'pending', proposedBy: 'counselor', proposalRevision: 2, proposedScheduledAt: appointment('confirmed').scheduledAt.add(const Duration(hours: 1)), proposedScheduledTime: '11:00 AM');
    await open(tester, repo, TestAuth(), AppointmentProvider(repo));
    expect(find.text('Your confirmation needed'), findsOneWidget);
    expect(find.text('Current time stays reserved until you both agree.'), findsOneWidget);
    await tester.ensureVisible(find.text('Accept proposed time'));
    await tester.tap(find.text('Accept proposed time'));
    await tester.pumpAndSettle();
    expect(repo.lastAgreementAction, 'accept');
    expect(repo.lastAgreementRevision, 2);
  });

  testWidgets('open details follows live status and renders appointment activity', (tester) async {
    final repo = TestRepository()..item = appointment('requested');
    final provider = AppointmentProvider(repo);
    await open(tester, repo, TestAuth(), provider);
    expect(find.text('Awaiting confirmation'), findsOneWidget);
    expect(find.text('Appointment activity'), findsOneWidget);
    expect(find.text('Request received'), findsOneWidget);
    expect(find.text('To be assigned'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    repo.item = repo.item.copyWith(status: 'confirmed', counselorName: 'Counselor Rivera');
    repo.updates.add([repo.item]);
    await tester.pumpAndSettle();
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Awaiting confirmation'), findsNothing);
    expect(find.text('Counselor Rivera'), findsOneWidget);
  });

  testWidgets('schedule change is reviewed before sending and shows truthful result', (tester) async {
    final repo = TestRepository()..item = appointment('confirmed');
    await open(tester, repo, TestAuth(), AppointmentProvider(repo));
    await select(tester);
    expect(find.text('Review schedule change'), findsOneWidget);
    expect(repo.calls, 0);
    await tester.tap(find.text('Review schedule change'));
    await tester.pumpAndSettle();
    expect(find.text('Current schedule'), findsOneWidget);
    expect(find.text('New preferred schedule'), findsOneWidget);
    expect(find.text('Send schedule change'), findsOneWidget);
    expect(repo.calls, 0);
    await tester.tap(find.text('Send schedule change'));
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
    expect(find.text('Change received'), findsOneWidget);
    await tester.tap(find.text('View appointment details'));
    await tester.pumpAndSettle();
    expect(find.text('Awaiting PACC confirmation'), findsOneWidget);
  });

  testWidgets('phone details footer stays reachable and schedule screens render', (tester) async {
    await tester.runAsync(() async {
      for (final entry in {'Roboto': 'C:/Windows/Fonts/segoeui.ttf', 'MaterialIcons': 'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'}.entries) {
        final file = File(entry.value);
        if (await file.exists()) await (FontLoader(entry.key)..addFont(file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)))).load();
      }
    });
    final repo = TestRepository()..item = appointment('confirmed');
    await open(tester, repo, TestAuth(), AppointmentProvider(repo));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    final action = find.widgetWithText(FilledButton, 'Edit date and time');
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    expect(tester.getBottomRight(action).dy, lessThanOrEqualTo(844));
    await _captureAppointment(tester, 'details-live-status');
    await select(tester);
    await _captureAppointment(tester, 'edit-schedule');
    await tester.tap(find.text('Review schedule change'));
    await tester.pumpAndSettle();
    await _captureAppointment(tester, 'review-schedule');
    await tester.tap(find.text('Send schedule change'));
    await tester.pumpAndSettle();
    await _captureAppointment(tester, 'change-received');
  });

  testWidgets('details summary and footer support320px and200percent text', (tester) async {
    final repo = TestRepository()..item = appointment('requested');
    await open(tester, repo, TestAuth(), AppointmentProvider(repo));
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.binding.setSurfaceSize(const Size(320, 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit date and time'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a new date and time'), findsOneWidget);
  });

  testWidgets('details presents a status-first counseling session card', (tester) async {
    final repo = TestRepository()..item = appointment('confirmed');
    await open(tester, repo, TestAuth(), AppointmentProvider(repo));
    expect(find.text('PACC Counseling'), findsOneWidget);
    expect(find.textContaining('Philippine Time (PHT)'), findsOneWidget);
    expect(find.byKey(const ValueKey('appointment-session-summary')), findsOneWidget);
    expect(find.text('Edit date and time'), findsOneWidget);
  });
  testWidgets('previous appointment details stay hidden after account switch and back', (tester) async {
    final repo = TestRepository()..item = appointment('confirmed').copyWith(concern: 'Private concern');
    final auth = TestAuth();
    final provider = AppointmentProvider(repo);
    await open(tester, repo, auth, provider);
    expect(find.text('Private concern'), findsOneWidget);
    await tester.tap(find.text('Edit date and time'));
    await tester.pumpAndSettle();
    auth.switchAccount('other');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Private concern'), findsNothing);
  });
  for (final status in [
    'requested',
    'confirmed',
    'completed',
    'cancelled',
    'declined',
    'expired',
    'no_show',
    'reschedule_proposed',
    'archived',
    'past',
  ]) {
    testWidgets('editing eligibility: $status', (tester) async {
      final repo = TestRepository()..item = appointment(status);
      if (status == 'archived') {
        repo.item = appointment(
          'confirmed',
        ).copyWith(archivedAt: DateTime.now());
      }
      if (status == 'past') {
        repo.item = appointment('confirmed').copyWith(
          scheduledAt: DateTime.now().subtract(const Duration(days: 1)),
        );
      }
      final provider = AppointmentProvider(repo);
      await open(tester, repo, TestAuth(), provider);
      expect(
        find.text('Edit date and time'),
        status == 'requested' || status == 'confirmed'
            ? findsOneWidget
            : findsNothing,
      );
    });
  }
  testWidgets(
    'opened schedule and revision, loading, success and live refresh',
    (tester) async {
      final repo = TestRepository()
        ..item = appointment('confirmed')
        ..pending = Completer<void>();
      final provider = AppointmentProvider(repo);
      await open(tester, repo, TestAuth(), provider);
      final opened = repo.item;
      await select(tester);
      expect(
        find.textContaining(formatAppointmentDate(opened.scheduledAt)),
        findsWidgets,
      );
      await tester.tap(find.text('Review schedule change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send schedule change'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(repo.calls, 1);
      expect(repo.revision, 7);
      expect(repo.original, opened.scheduledAt);
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(provider.appointments.single.id, 'existing-id');
      expect(provider.appointments.single.status, 'confirmed');
      expect(provider.appointments.single.hasPendingScheduleChange, isTrue);
      expect(provider.appointments.single.scheduledAt, opened.scheduledAt);
    },
  );
  testWidgets(
    'unchanged selection preserves confirmed status and truthful success',
    (tester) async {
      final repo = TestRepository()..item = appointment('confirmed');
      final provider = AppointmentProvider(repo);
      await open(tester, repo, TestAuth(), provider);
      await select(tester, unchanged: true);
      await tester.tap(find.text('Review schedule change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send schedule change'));
      await tester.pumpAndSettle();
      expect(provider.appointments.single.status, 'confirmed');
      expect(
        find.text('Appointment updated. Awaiting confirmation.'),
        findsNothing,
      );
    },
  );
  for (final code in ['aborted', 'already-exists']) {
    testWidgets('$code retains selection and requires refresh', (tester) async {
      final repo = TestRepository()
        ..item = appointment('confirmed')
        ..failure = FirebaseFunctionsException(
          code: code,
          message: 'Schedule conflict',
        );
      final provider = AppointmentProvider(repo);
      await open(tester, repo, TestAuth(), provider);
      await select(tester);
      await tester.tap(find.text('Review schedule change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send schedule change'));
      await tester.pumpAndSettle();
      expect(
        find.text('2:00 PM \u00b7 PHT'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.textContaining('Reopen'), findsOneWidget);
      expect(repo.calls, 1);
    });
  }
  testWidgets(
    'account switching invalidates pending result and retained editor',
    (tester) async {
      final repo = TestRepository()
        ..item = appointment('confirmed')
        ..pending = Completer<void>();
      final auth = TestAuth();
      final provider = AppointmentProvider(repo);
      await open(tester, repo, auth, provider);
      await select(tester);
      await tester.tap(find.text('Review schedule change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send schedule change'));
      await tester.pump();
      auth.switchAccount('other');
      await tester.runAsync(() => provider.loadAppointments('other'));
      await tester.pump();
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('This appointment is unavailable for the current account.'),
        findsOneWidget,
      );
      expect(
        find.text('Appointment updated. Awaiting confirmation.'),
        findsNothing,
      );
      auth.switchAccount('student');
      await tester.runAsync(() => provider.loadAppointments('student'));
      await tester.pumpAndSettle();
      expect(find.text('2:00 PM'), findsNothing);
    },
  );
}

Future<void> _captureAppointment(WidgetTester tester, String name) async {
  final editor = find.byKey(const ValueKey('appointment-editor-page'));
  final boundary = tester.renderObject<RenderRepaintBoundary>(editor.evaluate().isNotEmpty ? editor : find.byKey(const ValueKey('appointment-details-page')));
  await tester.runAsync(() async {
    final rendered = await boundary.toImage();
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('.superpowers/sdd/MindMate_Appointment_Implementation_Plan/screenshots');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(data!.buffer.asUint8List());
    rendered.dispose();
  });
}
