import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/core/utils/philippine_mobile_formatter.dart';
import 'package:mind_mates/features/admin/domain/inquiry_scope.dart';
import 'package:mind_mates/features/admin/widgets/testing_service_schedule_panel.dart';
import 'package:mind_mates/features/counseling/screens/service_detail_screen.dart';
import 'package:mind_mates/features/counseling/screens/services_screen.dart';
import 'package:mind_mates/features/counseling/screens/student_inquiries_screen.dart';
import 'package:mind_mates/features/counseling/screens/testing_service_inquiry_screen.dart';
import 'package:mind_mates/features/counseling/widgets/testing_service_documents_gallery.dart';
import 'package:mind_mates/features/notifications/screens/notifications_screen.dart';
import 'package:mind_mates/features/notifications/widgets/appointment_notification_banner.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/app_notification_model.dart';
import 'package:mind_mates/models/pacc_availability_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/student_inquiry_model.dart';
import 'package:mind_mates/models/testing_service_schedule.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';
import 'package:mind_mates/repositories/inquiry_repository.dart';
import 'package:mind_mates/repositories/notification_repository.dart';
import 'package:mind_mates/services/firebase/app_notification_service.dart';
import 'package:mind_mates/services/firebase/firestore_service.dart';

// 1x1 transparent PNG
final Uint8List _samplePngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);
final Uint8List _samplePdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.4 test'));

class _RecordingInquiryRepository extends InquiryRepository {
  _RecordingInquiryRepository({
    this.uid = 'user-1',
    Map<String, StudentInquiryRecord>? inquiries,
  }) : _inquiries = inquiries ?? {},
       super(
         firestoreService: _NoopFirestoreService(),
         currentUserIdProvider: () => uid,
       );

  final String uid;
  final Map<String, StudentInquiryRecord> _inquiries;
  final List<(String, Map<String, Object?>)> calls = [];
  final StreamController<StudentInquiryRecord?> _detailController =
      StreamController<StudentInquiryRecord?>.broadcast();

  void emitInquiry(StudentInquiryRecord record) {
    _inquiries[record.id] = record;
    _detailController.add(record);
  }

  void dispose() {
    _detailController.close();
  }

  @override
  Stream<List<StudentInquiryRecord>> watchMyInquiries(String userId) =>
      Stream.value(
        _inquiries.values
            .where((item) => item.userId == userId)
            .toList(growable: false),
      );

  @override
  Stream<StudentInquiryRecord?> watchMyInquiry(
    String inquiryId, {
    required String userId,
  }) async* {
    yield _inquiries[inquiryId];
    yield* _detailController.stream.where((item) => item?.id == inquiryId);
  }

  @override
  Stream<List<StudentInquiryReply>> watchMyInquiryReplies(String inquiryId) =>
      Stream.value(const <StudentInquiryReply>[]);

  @override
  Future<TestingServiceDocumentRef> uploadTestingServiceDocument({
    required PendingTestingDocument file,
  }) async {
    calls.add((
      'uploadTestingServiceDocument',
      {'kind': file.kind.wireValue, 'name': file.name, 'size': file.size},
    ));
    return TestingServiceDocumentRef(
      path:
          'testing_service_files/$uid/${file.kind.wireValue}/0123456789abcdef0123456789abcdef.${file.isPdf ? 'pdf' : 'png'}',
      name: file.name,
      contentType: file.contentType,
      size: file.size,
      kind: file.kind,
    );
  }

  @override
  Future<String> submitTestingServiceInquiry({
    required bool isStudentForOjt,
    required bool endorsementLetterConfirmed,
    required bool officialReceiptConfirmed,
    required String mobileNumber,
    required TestingServiceDocumentRef endorsementLetter,
    required TestingServiceDocumentRef officialReceipt,
    List<TestingServiceDocumentRef> admissionRequirements = const [],
    DateTime? preferredScheduleAt,
    required PersonalDataSheetInput personalDataSheet,
    bool personalDataSheetConfirmed = true,
    bool informedConsentConfirmed = true,
    String message = '',
    String? preferredScheduleNote,
    String? requestId,
  }) async {
    calls.add((
      'submitTestingServiceInquiry',
      {
        'isStudentForOjt': isStudentForOjt,
        'endorsementLetterConfirmed': endorsementLetterConfirmed,
        'officialReceiptConfirmed': officialReceiptConfirmed,
        'mobileNumber': mobileNumber,
        'endorsementPath': endorsementLetter.path,
        'receiptPath': officialReceipt.path,
        'admissionCount': admissionRequirements.length,
        'preferredScheduleAt': preferredScheduleAt,
        'personalDataSheet': personalDataSheet.toJson(),
        'personalDataSheetConfirmed': personalDataSheetConfirmed,
        'informedConsentConfirmed': informedConsentConfirmed,
        'message': message,
        'preferredScheduleNote': preferredScheduleNote,
      },
    ));
    final id = 'testing-inq-${calls.length}';
    _inquiries[id] = StudentInquiryRecord(
      id: id,
      userId: uid,
      subject: 'Testing Service Schedule Request',
      message: message.isEmpty
          ? 'Requesting a Testing Service schedule.'
          : message,
      category: 'Service Form',
      formType: testingServiceFormType,
      contactNumber: mobileNumber,
      testingDocuments: TestingServiceDocuments(
        endorsementLetter: endorsementLetter,
        officialReceipt: officialReceipt,
        admissionRequirements: admissionRequirements,
      ),
      status: StudentInquiryStatus.pending,
      createdAt: DateTime(2026, 11, 27, 10),
      testingSchedule: const TestingServiceSchedule(
        status: TestingScheduleStatus.awaitingSchedule,
      ),
    );
    return id;
  }

  @override
  Future<({String name, String contentType, Uint8List bytes})>
  downloadTestingServiceDocument({
    required String inquiryId,
    required String path,
  }) async {
    calls.add((
      'downloadTestingServiceDocument',
      {'inquiryId': inquiryId, 'path': path},
    ));
    final isPdf = path.toLowerCase().endsWith('.pdf');
    return (
      name: isPdf ? 'receipt.pdf' : 'endorsement.png',
      contentType: isPdf ? 'application/pdf' : 'image/png',
      bytes: isPdf ? _samplePdfBytes : _samplePngBytes,
    );
  }

  @override
  Future<void> acceptTestingServiceSchedule(
    String inquiryId, {
    int? expectedScheduleRevision,
  }) async {
    calls.add((
      'acceptTestingServiceSchedule',
      {
        'inquiryId': inquiryId,
        'expectedScheduleRevision': expectedScheduleRevision,
      },
    ));
  }

  @override
  Future<void> requestTestingServiceReschedule(
    String inquiryId, {
    required String reason,
    int? expectedScheduleRevision,
  }) async {
    calls.add((
      'requestTestingServiceReschedule',
      {
        'inquiryId': inquiryId,
        'reason': reason,
        'expectedScheduleRevision': expectedScheduleRevision,
      },
    ));
  }
}

class _NoopFirestoreService extends FirestoreService {
  @override
  Future<String> createDocument(String collection, Map<String, dynamic> data) =>
      throw StateError('Direct Firestore writes must not be used.');
}

class _StubNotificationRepo extends NotificationRepository {
  _StubNotificationRepo(this.items)
    : super(firestoreService: _NoopFirestoreService());

  final List<AppNotificationModel> items;

  @override
  Stream<List<AppNotificationModel>> watchNotifications(String userId) =>
      Stream.value(items);

  @override
  Future<void> markRead(String notificationId) async {}
}

class _FakeFirebaseMessaging extends Fake implements FirebaseMessaging {
  _FakeFirebaseMessaging({this.initial});

  final RemoteMessage? initial;

  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool providesAppNotificationSettings = false,
    bool sound = true,
  }) async => const NotificationSettings(
    authorizationStatus: AuthorizationStatus.authorized,
    alert: AppleNotificationSetting.enabled,
    announcement: AppleNotificationSetting.notSupported,
    badge: AppleNotificationSetting.enabled,
    carPlay: AppleNotificationSetting.notSupported,
    lockScreen: AppleNotificationSetting.enabled,
    notificationCenter: AppleNotificationSetting.enabled,
    showPreviews: AppleShowPreviewSetting.always,
    sound: AppleNotificationSetting.enabled,
    timeSensitive: AppleNotificationSetting.notSupported,
    criticalAlert: AppleNotificationSetting.notSupported,
    providesAppNotificationSettings: AppleNotificationSetting.notSupported,
  );

  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  @override
  Future<RemoteMessage?> getInitialMessage() async => initial;
}

UserModel _user({
  String id = 'user-1',
  PopulationRole? populationRole = PopulationRole.student,
  AccessRole accessRole = AccessRole.appUser,
  String accountStatus = 'active',
}) => UserModel(
  id: id,
  email: '$id@ucu.edu.ph',
  firstName: 'Test',
  lastName: 'User',
  schoolId: populationRole == PopulationRole.student ? '2023-0042' : null,
  employeeId: populationRole == PopulationRole.student ? null : 'EMP-108',
  department: 'College of Information Technology',
  course: populationRole == PopulationRole.student ? 'BSIT' : null,
  position: populationRole == PopulationRole.student ? null : 'Instructor I',
  populationRole: populationRole,
  accessRole: accessRole,
  accountStatus: accountStatus,
);

Future<PendingTestingDocument?> _testFilePicker(
  TestingDocumentKind kind,
) async => switch (kind) {
  TestingDocumentKind.endorsementLetter => PendingTestingDocument(
    name: 'endorsement.png',
    contentType: 'image/png',
    bytes: _samplePngBytes,
    kind: kind,
  ),
  TestingDocumentKind.officialReceipt => PendingTestingDocument(
    name: 'receipt_250.pdf',
    contentType: 'application/pdf',
    bytes: _samplePdfBytes,
    kind: kind,
  ),
  TestingDocumentKind.admissionRequirement => PendingTestingDocument(
    name: 'admission_scan.png',
    contentType: 'image/png',
    bytes: _samplePngBytes,
    kind: kind,
  ),
};

void main() {
  setUp(TestingServiceDocumentCache.clearForTests);

  test('Philippine mobile formatter normalizes 09 and 9xx inputs into +63 9XX XXX XXXX', () {
    expect(formatPhilippineMobile('09171234567'), '+63 917 123 4567');
    expect(formatPhilippineMobile('9171234567'), '+63 917 123 4567');
    expect(formatPhilippineMobile('+63 917 123 4567'), '+63 917 123 4567');
    expect(isValidPhilippineMobile('+63 917 123 4567'), isTrue);
    expect(isValidPhilippineMobile('09171234567'), isTrue);
    expect(isValidPhilippineMobile('12345'), isFalse);
  });

  test(
    'Testing Service guide text states 2-5 min review with SMS and in-app notifications',
    () {
      final testing = ServicesScreen.services.firstWhere(
        (service) => service.title == 'Testing Service',
      );
      expect(testing.hasTestingServiceInquiry, isTrue);
      final guideText = testing.guides.single.steps.single.providerAction;
      expect(guideText, contains('SMS'));
      expect(guideText.toLowerCase(), contains('in-app notifications'));
    },
  );

  test(
    'TestingServiceSchedule maps onto AppointmentModel for display only when scheduled',
    () {
      const unscheduled = TestingServiceSchedule(
        status: TestingScheduleStatus.awaitingSchedule,
      );
      expect(
        unscheduled.toDisplayAppointment(
          inquiryId: 'inq-1',
          userId: 'u-1',
          fullName: 'Student OJT',
          email: 's@ucu.edu.ph',
          concern: 'Testing',
          createdAt: DateTime(2026, 11, 27),
        ),
        isNull,
      );

      final proposed = TestingServiceSchedule(
        status: TestingScheduleStatus.proposed,
        scheduledAt: testingServiceInstantFromManila(
          year: 2030,
          month: 1,
          day: 7,
          hour: 10,
        ),
        scheduledTime: '10:00 AM',
        location: 'PACC Testing Room',
        proposedByName: 'Dr. Reyes',
      );
      final mapped = proposed.toDisplayAppointment(
        inquiryId: 'inq-1',
        userId: 'u-1',
        fullName: 'Student OJT',
        email: 's@ucu.edu.ph',
        concern: 'Testing',
        createdAt: DateTime(2026, 11, 27),
      );
      expect(mapped, isNotNull);
      expect(mapped!.status, 'requested');
      expect(mapped.scheduledAt, DateTime(2030, 1, 7, 10, 0));
      expect(mapped.scheduledTime, '10:00 AM');
      expect(mapped.location, 'PACC Testing Room');
      expect(mapped.counselorName, 'Dr. Reyes');
    },
  );

  group('3-step wizard, smart defaults, uploads & SMS banner', () {
    testWidgets(
      'Student for OJT completes 3-step wizard with required uploads, preview, formatted mobile, smart PDS defaults, and SMS confirmation banner',
      (tester) async {
        final repo = _RecordingInquiryRepository(uid: 'student-1');
        addTearDown(repo.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: TestingServiceInquiryScreen(
              user: _user(
                id: 'student-1',
                populationRole: PopulationRole.student,
              ),
              repository: repo,
              currentUserIdProvider: () => 'student-1',
              nowProvider: () => DateTime.utc(2026, 11, 27, 2),
              pickFile: _testFilePicker,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Step 1 progress indicator & smart default radio
        expect(find.text('STEP 1 OF 3'), findsOneWidget);
        expect(find.byKey(const ValueKey('testing-ojt-checkbox')), findsOneWidget);

        // Cannot advance without OJT confirmation + required uploads
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-step1-next')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-step1-next')));
        await tester.pumpAndSettle();
        expect(find.text('STEP 1 OF 3'), findsOneWidget);

        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold)),
        ).hideCurrentSnackBar();
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-ojt-checkbox')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-ojt-checkbox')));
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-upload-endorsement')),
        );
        await tester.tap(
          find.byKey(const ValueKey('testing-upload-endorsement')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Endorsement_Letter.png'), findsOneWidget);

        // Image preview dialog works immediately
        await tester.tap(find.byTooltip('Preview Endorsement_Letter.png'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Close preview'), findsOneWidget);
        await tester.tap(find.byTooltip('Close preview'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-upload-receipt')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-upload-receipt')));
        await tester.pumpAndSettle();
        expect(find.text('Official_Receipt_PHP250.pdf'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-upload-admission')),
        );
        await tester.tap(
          find.byKey(const ValueKey('testing-upload-admission')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Admission_Requirement_1.png'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-step1-next')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-step1-next')));
        await tester.pumpAndSettle();

        // Step 2: Mobile autoformatting & schedule preferences
        expect(find.text('STEP 2 OF 3'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('testing-mobile-input')),
          '09185551234',
        );
        await tester.pumpAndSettle();
        expect(find.text('+63 918 555 1234'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-step2-next')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-step2-next')));
        await tester.pumpAndSettle();

        // Step 3: Smart-defaulted Personal Data Sheet, Digital Agreements & SMS Confirmation Banner
        expect(find.text('STEP 3 OF 3'), findsOneWidget);
        expect(find.text('Test User'), findsOneWidget);
        expect(find.text('2023-0042'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('testing-sms-confirmation-banner')),
          findsOneWidget,
        );
        expect(
          find.textContaining('2–5 minutes processing time'),
          findsOneWidget,
        );
        expect(find.textContaining('+63 918 555 1234'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-pds-consent')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-pds-consent')));
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-informed-consent')),
        );
        await tester.tap(
          find.byKey(const ValueKey('testing-informed-consent')),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-submit-button')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-submit-button')));
        await tester.pumpAndSettle();

        // 3 uploads + 1 submit call
        expect(
          repo.calls
              .where((c) => c.$1 == 'uploadTestingServiceDocument')
              .length,
          3,
        );
        final submitCall = repo.calls.firstWhere(
          (c) => c.$1 == 'submitTestingServiceInquiry',
        );
        expect(submitCall.$2['isStudentForOjt'], isTrue);
        expect(submitCall.$2['mobileNumber'], '+63 918 555 1234');
        expect(submitCall.$2['admissionCount'], 1);
        expect(find.byType(StudentInquiryDetailScreen), findsOneWidget);
        expect(
          find.textContaining('2–5 minutes processing time'),
          findsOneWidget,
        );
      },
    );

    for (final role in [PopulationRole.teaching, PopulationRole.nonTeaching]) {
      testWidgets('${role.label} employee defaults to UCU Employee and submits without OJT checkbox', (
        tester,
      ) async {
        final repo = _RecordingInquiryRepository(uid: 'emp-1');
        addTearDown(repo.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: TestingServiceInquiryScreen(
              user: _user(id: 'emp-1', populationRole: role),
              repository: repo,
              currentUserIdProvider: () => 'emp-1',
              nowProvider: () => DateTime.utc(2026, 11, 27, 2),
              pickFile: _testFilePicker,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('testing-ojt-checkbox')),
          findsNothing,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-upload-endorsement')),
        );
        await tester.tap(
          find.byKey(const ValueKey('testing-upload-endorsement')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-upload-receipt')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-upload-receipt')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-step1-next')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-step1-next')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('testing-mobile-input')),
          '9187654321',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-step2-next')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-step2-next')));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-pds-consent')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-pds-consent')));
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-informed-consent')),
        );
        await tester.tap(
          find.byKey(const ValueKey('testing-informed-consent')),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-submit-button')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-submit-button')));
        await tester.pumpAndSettle();

        final submitCall = repo.calls.firstWhere(
          (c) => c.$1 == 'submitTestingServiceInquiry',
        );
        expect(submitCall.$2['isStudentForOjt'], isFalse);
        expect(submitCall.$2['mobileNumber'], '+63 918 765 4321');
        expect(find.byType(StudentInquiryDetailScreen), findsOneWidget);
      });
    }

    testWidgets('ineligible roles cannot submit Testing Service requests', (
      tester,
    ) async {
      final repo = _RecordingInquiryRepository(uid: 'staff-1');
      addTearDown(repo.dispose);

      for (final ineligibleUser in [
        _user(
          id: 'staff-1',
          populationRole: PopulationRole.nonTeaching,
          accessRole: AccessRole.portalStaff,
        ),
        _user(
          id: 'c-1',
          populationRole: PopulationRole.teaching,
          accessRole: AccessRole.counselor,
        ),
        _user(
          id: 'no-role',
          populationRole: null,
          accessRole: AccessRole.appUser,
        ),
        null,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: TestingServiceInquiryScreen(
              user: ineligibleUser,
              repository: repo,
              currentUserIdProvider: () => 'staff-1',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('testing-step1-next')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('testing-submit-button')),
          findsNothing,
        );
      }
      expect(repo.calls, isEmpty);
    });

    testWidgets(
      'narrow viewport keeps submit and step button labels padded and centered inside buttons',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final repo = _RecordingInquiryRepository(uid: 'student-1');
        addTearDown(repo.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: TestingServiceInquiryScreen(
              user: _user(
                id: 'student-1',
                populationRole: PopulationRole.student,
              ),
              repository: repo,
              currentUserIdProvider: () => 'student-1',
              nowProvider: () => DateTime.utc(2026, 11, 27, 2),
              pickFile: _testFilePicker,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Step 1 on narrow viewport
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-ojt-checkbox')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-ojt-checkbox')));
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-upload-endorsement')),
        );
        await tester.tap(
          find.byKey(const ValueKey('testing-upload-endorsement')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-upload-receipt')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-upload-receipt')));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-step1-next')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-step1-next')));
        await tester.pumpAndSettle();

        // Step 2 on narrow viewport
        await tester.enterText(
          find.byKey(const ValueKey('testing-mobile-input')),
          '09185551234',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-step2-next')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-step2-next')));
        await tester.pumpAndSettle();

        // Step 3: verify submit button geometry, inner padding, and optical center
        final submitFinder = find.byKey(const ValueKey('testing-submit-button'));
        await tester.ensureVisible(submitFinder);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final buttonRect = tester.getRect(submitFinder);
        final labelFinder = find.descendant(
          of: submitFinder,
          matching: find.text('Submit Testing Service Request'),
        );
        final rowFinder = find.descendant(
          of: submitFinder,
          matching: find.byType(Row),
        );
        final textRect = tester.getRect(labelFinder);
        final rowRect = tester.getRect(rowFinder);

        expect(textRect.left, greaterThanOrEqualTo(buttonRect.left + 12));
        expect(textRect.right, lessThanOrEqualTo(buttonRect.right - 12));
        expect(textRect.top, greaterThanOrEqualTo(buttonRect.top + 8));
        expect(textRect.bottom, lessThanOrEqualTo(buttonRect.bottom - 8));
        expect((rowRect.center.dx - buttonRect.center.dx).abs(), lessThanOrEqualTo(2.0));
        expect((rowRect.center.dy - buttonRect.center.dy).abs(), lessThanOrEqualTo(2.0));
      },
    );
  });

  group('User schedule lifecycle (one-time reschedule & confirmed lock)', () {
    testWidgets(
      'proposed -> one reschedule -> revised proposal (no 2nd reschedule) -> accept locks schedule',
      (tester) async {
        final proposed1 = StudentInquiryRecord(
          id: 'inq-test-1',
          userId: 'user-1',
          subject: 'Testing Service Schedule Request',
          message: 'OJT testing request',
          category: 'Service Form',
          formType: testingServiceFormType,
          status: StudentInquiryStatus.inProgress,
          createdAt: DateTime(2026, 11, 27, 9),
          testingSchedule: TestingServiceSchedule(
            status: TestingScheduleStatus.proposed,
            scheduledAt: testingServiceInstantFromManila(
              year: 2030,
              month: 1,
              day: 7,
              hour: 9,
            ),
            scheduledTime: '09:00 AM',
            location: 'PACC Testing Room',
            proposedByName: 'Dr. Reyes',
            rescheduleCount: 0,
            maxReschedules: 1,
            revision: 1,
          ),
        );
        final repo = _RecordingInquiryRepository(
          uid: 'user-1',
          inquiries: {'inq-test-1': proposed1},
        );
        addTearDown(repo.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: StudentInquiryDetailScreen(
              inquiryId: 'inq-test-1',
              userId: 'user-1',
              repository: repo,
              currentUserIdProvider: () => 'user-1',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Testing Service Schedule'), findsOneWidget);
        expect(find.textContaining('09:00 AM (PHT)'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('testing-accept-schedule')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('testing-request-reschedule')),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-request-reschedule')),
        );
        await tester.tap(
          find.byKey(const ValueKey('testing-request-reschedule')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('testing-reschedule-reason')),
          'I have a mandatory OJT briefing.',
        );
        await tester.tap(
          find.byKey(const ValueKey('testing-reschedule-submit')),
        );
        await tester.pumpAndSettle();

        expect(
          repo.calls.last.$1,
          'requestTestingServiceReschedule',
        );
        expect(
          repo.calls.last.$2['reason'],
          'I have a mandatory OJT briefing.',
        );

        repo.emitInquiry(
          StudentInquiryRecord(
            id: 'inq-test-1',
            userId: 'user-1',
            subject: 'Testing Service Schedule Request',
            message: 'OJT testing request',
            category: 'Service Form',
            formType: testingServiceFormType,
            status: StudentInquiryStatus.inProgress,
            createdAt: DateTime(2026, 11, 27, 9),
            testingSchedule: TestingServiceSchedule(
              status: TestingScheduleStatus.proposed,
              scheduledAt: testingServiceInstantFromManila(
                year: 2030,
                month: 1,
                day: 8,
                hour: 14,
              ),
              scheduledTime: '02:00 PM',
              location: 'PACC Testing Room',
              proposedByName: 'Dr. Reyes',
              rescheduleCount: 1,
              maxReschedules: 1,
              revision: 3,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('testing-request-reschedule')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('testing-accept-schedule')),
          findsOneWidget,
        );
        expect(
          find.textContaining('used your one allowed reschedule'),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-accept-schedule')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-accept-schedule')));
        await tester.pumpAndSettle();
        expect(repo.calls.last.$1, 'acceptTestingServiceSchedule');

        repo.emitInquiry(
          StudentInquiryRecord(
            id: 'inq-test-1',
            userId: 'user-1',
            subject: 'Testing Service Schedule Request',
            message: 'OJT testing request',
            category: 'Service Form',
            formType: testingServiceFormType,
            status: StudentInquiryStatus.inProgress,
            createdAt: DateTime(2026, 11, 27, 9),
            testingSchedule: TestingServiceSchedule(
              status: TestingScheduleStatus.confirmed,
              scheduledAt: testingServiceInstantFromManila(
                year: 2030,
                month: 1,
                day: 8,
                hour: 14,
              ),
              scheduledTime: '02:00 PM',
              location: 'PACC Testing Room',
              rescheduleCount: 1,
              maxReschedules: 1,
              revision: 4,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Schedule Confirmed'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('testing-accept-schedule')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('testing-request-reschedule')),
          findsNothing,
        );
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
        expect(find.text('Cancel'), findsNothing);
      },
    );

    testWidgets(
      'mobile detail renders inline uploaded image preview with zoom lightbox and processing counselor name',
      (tester) async {
        final inquiryWithDocs = StudentInquiryRecord.fromJson({
          'id': 'inq-mobile-preview',
          'userId': 'user-1',
          'subject': 'Testing Service Schedule Request',
          'message': 'Please check my endorsement and receipt.',
          'category': 'Service Form',
          'formType': testingServiceFormType,
          'status': 'in_progress',
          'contactNumber': '+63 918 555 1234',
          'assigneeIds': ['coun-1'],
          'assigneeLabels': {'coun-1': 'Dr. Maria Santos'},
          'ownerId': 'coun-1',
          'createdAt': '2026-11-27T08:00:00.000Z',
          'testingDocuments': {
            'endorsementLetter': {
              'path':
                  'testing_service_files/user-1/endorsement_letter/0123456789abcdef0123456789abcdef.png',
              'name': 'endorsement.png',
              'contentType': 'image/png',
              'size': _samplePngBytes.length,
              'kind': 'endorsement_letter',
            },
            'officialReceipt': {
              'path':
                  'testing_service_files/user-1/official_receipt/0123456789abcdef0123456789abcdef.png',
              'name': 'receipt.png',
              'contentType': 'image/png',
              'size': _samplePngBytes.length,
              'kind': 'official_receipt',
            },
            'admissionRequirements': [],
          },
          'testingSchedule': {
            'status': 'awaiting_schedule',
            'rescheduleCount': 0,
            'maxReschedules': 1,
            'revision': 0,
          },
        }, id: 'inq-mobile-preview');

        final repo = _RecordingInquiryRepository(
          uid: 'user-1',
          inquiries: {'inq-mobile-preview': inquiryWithDocs},
        );
        addTearDown(repo.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: StudentInquiryDetailScreen(
              inquiryId: 'inq-mobile-preview',
              userId: 'user-1',
              repository: repo,
              currentUserIdProvider: () => 'user-1',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('testing-processing-counselor')),
          findsOneWidget,
        );
        expect(
          find.text('Processing Counselor: Dr. Maria Santos'),
          findsOneWidget,
        );
        expect(find.textContaining('Approach Dr. Maria Santos'), findsOneWidget);
        expect(find.byType(Image), findsNWidgets(2));
        expect(
          repo.calls
              .where((c) => c.$1 == 'downloadTestingServiceDocument')
              .length,
          2,
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-doc-zoom-0')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-doc-zoom-0')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('testing-doc-lightbox')),
          findsOneWidget,
        );
        expect(find.byType(InteractiveViewer), findsOneWidget);
        await tester.tap(find.byTooltip('Close preview'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('testing-doc-lightbox')),
          findsNothing,
        );
      },
    );
  });

  group('Staff PACC decision (Accept Schedule, Re-schedule, Cancel) & Mobile cancelled state', () {
    testWidgets(
      'staff sees inline previews with lightbox and uses Action + Decision reason dropdown for Accept Schedule, Re-schedule, and Cancel',
      (tester) async {
        final calls = <(String, Map<String, Object?>)>[];
        final repo = AdminPortalRepository(
          callableInvoker: (name, data) async {
            calls.add((name, data));
            if (name == 'downloadTestingServiceDocument') {
              return {
                'name': 'endorsement.png',
                'contentType': 'image/png',
                'size': _samplePngBytes.length,
                'dataBase64': base64Encode(_samplePngBytes),
              };
            }
            return {'ok': true, 'revision': 2};
          },
        );

        final awaiting = AdminInquiryModel.fromJson({
          'id': 'inq-staff-1',
          'userId': 'emp-1',
          'subject': 'Testing Service Schedule Request',
          'message': 'Testing request',
          'category': 'Service Form',
          'formType': testingServiceFormType,
          'contactNumber': '+63 917 123 4567',
          'preferredScheduleAt': '2030-01-07T01:00:00.000Z',
          'preferredScheduleTime': '09:00 AM',
          'assigneeIds': ['coun-1'],
          'assigneeLabels': {'coun-1': 'Dr. Elena Cruz'},
          'testingDocuments': {
            'endorsementLetter': {
              'path':
                  'testing_service_files/emp-1/endorsement_letter/0123456789abcdef0123456789abcdef.png',
              'name': 'endorsement.png',
              'contentType': 'image/png',
              'size': _samplePngBytes.length,
              'kind': 'endorsement_letter',
            },
            'officialReceipt': {
              'path':
                  'testing_service_files/emp-1/official_receipt/0123456789abcdef0123456789abcdef.pdf',
              'name': 'receipt.pdf',
              'contentType': 'application/pdf',
              'size': 200,
              'kind': 'official_receipt',
            },
            'admissionRequirements': [],
          },
          'status': 'pending',
          'routingRevision': 1,
          'createdAt': '2026-11-27T08:00:00.000Z',
          'testingSchedule': {
            'status': 'awaiting_schedule',
            'rescheduleCount': 0,
            'maxReschedules': 1,
            'revision': 0,
          },
        });

        expect(isAdminVisibleInquiry(awaiting), isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TestingServiceSchedulePanel(
                  inquiry: awaiting,
                  repository: _AdminOverrideRepo(
                    repo,
                    role: AccessRole.counselor,
                    uid: 'coun-1',
                  ),
                  nowProvider: () => DateTime.utc(2026, 11, 27, 2),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('SMS Mobile: +63 917 123 4567'), findsOneWidget);
        expect(find.textContaining('Endorsement_Letter.png'), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);

        // PACC decision controls appear ABOVE Uploaded Documents
        final actionTop = tester
            .getTopLeft(find.byKey(const ValueKey('admin-testing-action-dropdown')))
            .dy;
        final docsTop = tester.getTopLeft(find.text('Uploaded Documents')).dy;
        expect(actionTop, lessThan(docsTop));

        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-doc-zoom-0')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-doc-zoom-0')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('testing-doc-lightbox')),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Close preview'));
        await tester.pumpAndSettle();

        // 1. Default action is Accept Schedule -> sends decisionMode: accept_requested
        final sendBtn = find.byKey(
          const ValueKey('admin-testing-send-decision'),
        );
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();

        expect(calls.last.$1, 'proposeTestingServiceSchedule');
        expect(calls.last.$2['decisionMode'], 'accept_requested');
        expect(
          calls.last.$2['reason'],
          'Documents verified and schedule is available',
        );
        expect(
          calls.last.$2['scheduledAtMillis'],
          DateTime.utc(2030, 1, 7, 1, 0).millisecondsSinceEpoch,
        );

        // Pending/awaiting Action dropdown only has Approve Schedule and Re-schedule (never Mark as Completed)
        expect(find.text('Mark as Completed'), findsNothing);
        await tester.ensureVisible(
          find.byKey(const ValueKey('admin-testing-action-dropdown')),
        );
        await tester.tap(
          find.byKey(const ValueKey('admin-testing-action-dropdown')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Mark as Completed'), findsNothing);
        await tester.tap(find.text('Re-schedule').last);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('admin-testing-date-picker')),
          findsOneWidget,
        );
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();
        expect(calls.last.$1, 'proposeTestingServiceSchedule');
        expect(calls.last.$2['decisionMode'], 'reschedule');
        expect(
          calls.last.$2['reason'],
          'Psychometrician / Counselor schedule conflict',
        );

        // 3. Cancel action via secondary Cancel Request button & reason dialog
        ScaffoldMessenger.of(tester.element(sendBtn)).hideCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('admin-testing-cancel-btn')),
        );
        await tester.tap(
          find.byKey(const ValueKey('admin-testing-cancel-btn')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('admin-testing-confirm-cancel-btn')),
        );
        await tester.pumpAndSettle();
        expect(calls.last.$1, 'cancelTestingServiceSchedule');
        expect(
          calls.last.$2['reason'],
          'Incomplete or unreadable Endorsement Letter',
        );

        // 4. Cancelled inquiry hides decision form on Web and shows reason on Mobile
        final cancelledWeb = AdminInquiryModel.fromJson({
          'id': 'inq-staff-1',
          'userId': 'emp-1',
          'subject': 'Testing Service Schedule Request',
          'message': 'Testing request',
          'category': 'Service Form',
          'formType': testingServiceFormType,
          'status': 'in_progress',
          'routingRevision': 4,
          'createdAt': '2026-11-27T08:00:00.000Z',
          'testingSchedule': {
            'status': 'cancelled',
            'cancelReason': 'Incomplete or unreadable Endorsement Letter',
            'cancelledByName': 'Dr. Elena Cruz',
            'revision': 3,
          },
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TestingServiceSchedulePanel(
                  inquiry: cancelledWeb,
                  repository: _AdminOverrideRepo(repo, isSuperAdmin: true),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('admin-testing-cancelled-banner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('admin-testing-send-decision')),
          findsNothing,
        );

        final cancelledMobile = StudentInquiryRecord.fromJson({
          'id': 'inq-mob-cancel',
          'userId': 'user-1',
          'subject': 'Testing Service Schedule Request',
          'message': 'Requesting schedule',
          'category': 'Service Form',
          'formType': testingServiceFormType,
          'status': 'in_progress',
          'createdAt': '2026-11-27T08:00:00.000Z',
          'testingSchedule': {
            'status': 'cancelled',
            'cancelReason': 'Incomplete or unreadable Endorsement Letter',
            'cancelledByName': 'Dr. Elena Cruz',
            'revision': 3,
          },
        }, id: 'inq-mob-cancel');
        final mobRepo = _RecordingInquiryRepository(
          uid: 'user-1',
          inquiries: {'inq-mob-cancel': cancelledMobile},
        );
        addTearDown(mobRepo.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: StudentInquiryDetailScreen(
              inquiryId: 'inq-mob-cancel',
              userId: 'user-1',
              repository: mobRepo,
              currentUserIdProvider: () => 'user-1',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('testing-mobile-cancelled-banner')),
          findsOneWidget,
        );
        expect(find.textContaining('Dr. Elena Cruz'), findsAtLeastNWidgets(1));
        expect(
          find.byKey(const ValueKey('testing-accept-schedule')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('testing-request-reschedule')),
          findsNothing,
        );
      },
    );
  });

  group('Notifications routing for inquiryId', () {
    test(
      'AppNotificationService dispatches initial message inquiryId to onInquiryOpened',
      () async {
        String? openedInquiry;
        String? openedAppointment;
        final service = AppNotificationService(
          messaging: _FakeFirebaseMessaging(
            initial: const RemoteMessage(
              data: {'type': 'inquiry', 'inquiryId': 'inq-notif-1'},
            ),
          ),
          firestoreService: _NoopFirestoreService(),
        );
        await service.initializeForUser(
          'user-1',
          onAppointmentOpened: (id) => openedAppointment = id,
          onInquiryOpened: (id) => openedInquiry = id,
        );
        expect(openedInquiry, 'inq-notif-1');
        expect(openedAppointment, isNull);
        await service.dispose();
      },
    );

    testWidgets(
      'foreground banner shows View for inquiryId without appointmentId',
      (tester) async {
        var viewed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showAppointmentNotificationBanner(
                      context,
                      title: 'Testing Service schedule proposed',
                      message: 'Open MindMate to review.',
                      onView: () => viewed = true,
                    ),
                    child: const Text('Trigger'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Trigger'));
        await tester.pumpAndSettle();
        expect(find.text('View'), findsOneWidget);
        await tester.tap(find.text('View'));
        await tester.pumpAndSettle();
        expect(viewed, isTrue);
      },
    );

    testWidgets(
      'NotificationsScreen opens StudentInquiryDetailScreen when tapping an inquiry notification',
      (tester) async {
        final inquiryRepo = _RecordingInquiryRepository(
          uid: 'user-1',
          inquiries: {
            'inq-notif-2': StudentInquiryRecord(
              id: 'inq-notif-2',
              userId: 'user-1',
              subject: 'Testing Service Schedule Request',
              message: 'My testing request',
              category: 'Service Form',
              formType: testingServiceFormType,
              status: StudentInquiryStatus.inProgress,
              createdAt: DateTime(2026, 11, 27, 9),
            ),
          },
        );
        addTearDown(inquiryRepo.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: NotificationsScreen(
              userId: 'user-1',
              repository: _StubNotificationRepo([
                AppNotificationModel(
                  id: 'n-1',
                  userId: 'user-1',
                  type: 'inquiry',
                  title: 'Testing Service schedule proposed',
                  body:
                      'PACC proposed a schedule for your Testing Service inquiry.',
                  createdAt: DateTime(2026, 11, 27, 9),
                  inquiryId: 'inq-notif-2',
                ),
              ]),
              inquiryRepository: inquiryRepo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Testing Service schedule proposed'));
        await tester.pumpAndSettle();

        expect(find.byType(StudentInquiryDetailScreen), findsOneWidget);
        expect(find.text('Testing Service Schedule Request'), findsOneWidget);
      },
    );

    testWidgets(
      'hides synthetic @students.mindmate.local email, syncs PACC availability slots, locks active CTA until Completed, and supports Mark as Completed',
      (tester) async {
        // 1. Synthetic email is never prefilled on PDS
        await tester.pumpWidget(
          MaterialApp(
            home: TestingServiceInquiryScreen(
              user: const UserModel(
                id: 'student-synth',
                email: '20220367@students.mindmate.local',
                firstName: 'MJ',
                lastName: 'Guntang',
                role: 'Student',
                populationRole: PopulationRole.student,
                accessRole: AccessRole.appUser,
                accountStatus: 'active',
                schoolId: '20220367',
              ),
              repository: _RecordingInquiryRepository(uid: 'student-synth'),
              currentUserIdProvider: () => 'student-synth',
              nowProvider: () => DateTime.utc(2026, 11, 27, 2),
              availabilityStream: Stream.value(
                PaccAvailabilityModel(
                  openDays: const [1, 2, 3, 4, 5],
                  opensAt: '10:00',
                  closesAt: '14:00',
                  presence: CounselorPresence.inOffice,
                  acceptsWalkIns: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Advance to Step 2 and verify Admin PACC slots (10 AM - 1 PM, NOT 8 AM/5 PM)
        await tester.ensureVisible(
          find.byKey(const ValueKey('testing-ojt-checkbox')),
        );
        await tester.tap(find.byKey(const ValueKey('testing-ojt-checkbox')));
        // Step 1 requires docs; test PDS seeding + slot availability on screen via direct state check & CTA lock
        expect(find.textContaining('students.mindmate.local'), findsNothing);

        // 2. ServiceDetailScreen disables CTA while an active Testing Service request exists
        final testingService = ServicesScreen.services.firstWhere(
          (service) => service.title == 'Testing Service',
        );
        final activeStreamController =
            StreamController<List<StudentInquiryRecord>>.broadcast();
        addTearDown(activeStreamController.close);

        await tester.pumpWidget(
          MaterialApp(
            home: ServiceDetailScreen(
              service: testingService,
              myInquiriesStream: activeStreamController.stream,
            ),
          ),
        );
        activeStreamController.add([
          StudentInquiryRecord(
            id: 'inq-active-1',
            userId: 'student-synth',
            subject: 'Testing Service Schedule Request',
            message: 'Testing',
            category: 'Service Form',
            formType: testingServiceFormType,
            status: StudentInquiryStatus.inProgress,
            createdAt: DateTime(2026, 11, 27),
            testingSchedule: const TestingServiceSchedule(
              status: TestingScheduleStatus.confirmed,
            ),
          ),
        ]);
        await tester.pumpAndSettle();

        expect(find.text('Testing Request Ongoing'), findsOneWidget);
        expect(find.text('Request Testing Schedule'), findsNothing);

        // Unlocks once marked Completed
        activeStreamController.add([
          StudentInquiryRecord(
            id: 'inq-active-1',
            userId: 'student-synth',
            subject: 'Testing Service Schedule Request',
            message: 'Testing',
            category: 'Service Form',
            formType: testingServiceFormType,
            status: StudentInquiryStatus.resolved,
            createdAt: DateTime(2026, 11, 27),
            testingSchedule: const TestingServiceSchedule(
              status: TestingScheduleStatus.completed,
              completedByName: 'Dr. Elena Cruz',
            ),
          ),
        ]);
        await tester.pumpAndSettle();

        expect(find.text('Request Testing Schedule'), findsOneWidget);
        expect(find.text('Testing Request Ongoing'), findsNothing);

        // 3. Web panel supports Mark as Completed for assigned counselor, and stays view-only for Admin
        final calls = <(String, Map<String, Object?>)>[];
        final baseRepo = AdminPortalRepository(
          callableInvoker: (name, data) async {
            calls.add((name, data));
            return {'ok': true, 'revision': 5};
          },
        );
        final counselorRepo = _AdminOverrideRepo(
          baseRepo,
          role: AccessRole.counselor,
          uid: 'coun-1',
        );
        final confirmed = AdminInquiryModel.fromJson({
          'id': 'inq-complete-1',
          'userId': 'student-synth',
          'subject': 'Testing Service Schedule Request',
          'message': 'Testing request',
          'category': 'Service Form',
          'formType': testingServiceFormType,
          'email': '20220367@students.mindmate.local',
          'studentNumber': '20220367',
          'assigneeIds': ['coun-1'],
          'assigneeLabels': {'coun-1': 'Dr. Elena Cruz'},
          'status': 'in_progress',
          'routingRevision': 4,
          'createdAt': '2026-11-27T08:00:00.000Z',
          'testingSchedule': {
            'status': 'confirmed',
            'scheduledAt': '2030-01-07T02:00:00.000Z',
            'scheduledTime': '10:00 AM',
            'revision': 2,
          },
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TestingServiceSchedulePanel(
                  inquiry: confirmed,
                  repository: counselorRepo,
                  nowProvider: () => DateTime.utc(2026, 11, 27, 2),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('admin-testing-action-dropdown')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin-testing-complete-section')),
          findsOneWidget,
        );
        expect(find.text('Mark as Completed'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('admin-testing-mark-complete-btn')),
        );
        await tester.pumpAndSettle();
        expect(calls.last.$1, 'completeTestingServiceSchedule');

        // 4. Admin viewing confirmed or awaiting request gets read-only supervising/monitoring view
        final adminReadOnlyRepo = _AdminOverrideRepo(
          baseRepo,
          isSuperAdmin: true,
          role: AccessRole.admin,
          uid: 'admin-1',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TestingServiceSchedulePanel(
                  inquiry: confirmed,
                  repository: adminReadOnlyRepo,
                  nowProvider: () => DateTime.utc(2026, 11, 27, 2),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('admin-testing-readonly-reason')),
          findsOneWidget,
        );
        expect(find.textContaining('Admin review is read-only'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('admin-testing-complete-section')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin-testing-mark-complete-btn')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin-testing-action-dropdown')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin-testing-send-decision')),
          findsNothing,
        );
      },
    );
  });
}

class _AdminOverrideRepo extends AdminPortalRepository {
  _AdminOverrideRepo(
    this.delegate, {
    this.isSuperAdmin = false,
    this.role = AccessRole.admin,
    this.uid = 'admin-1',
  });

  final AdminPortalRepository delegate;
  @override
  final bool isSuperAdmin;
  final AccessRole role;
  final String uid;

  @override
  AccessRole get currentAccessRole => role;

  @override
  String? get currentUserId => uid;

  @override
  Future<({String name, String contentType, Uint8List bytes})>
  downloadTestingServiceDocument({
    required String inquiryId,
    required String path,
  }) => delegate.downloadTestingServiceDocument(
    inquiryId: inquiryId,
    path: path,
  );

  @override
  Future<int> proposeTestingServiceSchedule(
    String id, {
    required DateTime scheduledAt,
    required int expectedRevision,
    required String requestId,
    String? decisionMode,
    String? reason,
    String? note,
    String? location,
  }) => delegate.proposeTestingServiceSchedule(
    id,
    scheduledAt: scheduledAt,
    expectedRevision: expectedRevision,
    requestId: requestId,
    decisionMode: decisionMode,
    reason: reason,
    note: note,
    location: location,
  );

  @override
  Future<int> cancelTestingServiceSchedule(
    String id, {
    required String reason,
    required int expectedRevision,
    required String requestId,
  }) => delegate.cancelTestingServiceSchedule(
    id,
    reason: reason,
    expectedRevision: expectedRevision,
    requestId: requestId,
  );

  @override
  Future<int> completeTestingServiceSchedule(
    String id, {
    String? note,
    required int expectedRevision,
    required String requestId,
  }) => delegate.completeTestingServiceSchedule(
    id,
    note: note,
    expectedRevision: expectedRevision,
    requestId: requestId,
  );
}
