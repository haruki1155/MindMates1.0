import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/screens/services_screen.dart';
import 'package:mind_mates/features/counseling/screens/student_inquiries_screen.dart';
import 'package:mind_mates/models/student_inquiry_model.dart';
import 'package:mind_mates/providers/appointment_provider.dart';
import 'package:mind_mates/repositories/appointment_repository.dart';
import 'package:mind_mates/repositories/inquiry_repository.dart';
import 'package:mind_mates/services/firebase/firestore_service.dart';
import 'package:provider/provider.dart';

void main() {
  group('InquiryRepository student readers', () {
    test(
      'watchMyInquiries filters to owner and sorts newest createdAt first',
      () async {
        final firestore = _MemoryFirestoreService(
          inquiries: {
            'inq-old': {
              'id': 'inq-old',
              'userId': 'student-1',
              'subject': 'Older inquiry',
              'message': 'Older question',
              'category': 'Service Form',
              'status': 'pending',
              'createdAt': '2026-11-10T08:00:00.000Z',
            },
            'inq-other': {
              'id': 'inq-other',
              'userId': 'student-2',
              'subject': 'Another student inquiry',
              'message': 'Private',
              'category': 'Service Form',
              'status': 'pending',
              'createdAt': '2026-11-16T08:00:00.000Z',
            },
            'inq-new': {
              'id': 'inq-new',
              'userId': 'student-1',
              'subject': 'Newer inquiry',
              'message': 'Newest question',
              'category': 'General Inquiry',
              'status': 'in_progress',
              'createdAt': '2026-11-15T10:30:00.000Z',
              'responseCount': 1,
            },
          },
        );
        final repository = InquiryRepository(
          firestoreService: firestore,
          currentUserIdProvider: () => 'student-1',
        );

        final records = await repository.watchMyInquiries('student-1').first;
        expect(records.map((item) => item.id).toList(), ['inq-new', 'inq-old']);
        expect(records.first.status, StudentInquiryStatus.inProgress);
        expect(records.first.responseCount, 1);
      },
    );

    test(
      'watchMyInquiry rejects documents owned by another student with StateError',
      () async {
        final firestore = _MemoryFirestoreService(
          inquiries: {
            'inq-foreign': {
              'id': 'inq-foreign',
              'userId': 'student-2',
              'subject': 'Private concern',
              'message': 'Should never appear for student-1',
              'status': 'pending',
              'createdAt': '2026-11-15T10:00:00.000Z',
            },
          },
        );
        final repository = InquiryRepository(
          firestoreService: firestore,
          currentUserIdProvider: () => 'student-1',
        );

        await expectLater(
          repository.watchMyInquiry('inq-foreign', userId: 'student-1'),
          emitsError(isA<StateError>()),
        );
      },
    );

    test(
      'watchMyInquiryReplies streams chronological authored counselor and admin replies',
      () async {
        final firestore = _MemoryFirestoreService(
          repliesByInquiry: {
            'inq-1': [
              {
                'id': 'rep-2',
                'message': 'Admin follow-up note.',
                'authorName': 'Director Cruz',
                'authorRole': 'admin',
                'createdAt': '2026-11-15T12:00:00.000Z',
              },
              {
                'id': 'rep-1',
                'message': 'Counselor initial response.',
                'authorName': 'Dr. Santos',
                'authorRole': 'counselor',
                'createdAt': '2026-11-15T09:00:00.000Z',
              },
            ],
          },
        );
        final repository = InquiryRepository(
          firestoreService: firestore,
          currentUserIdProvider: () => 'student-1',
        );

        final replies = await repository.watchMyInquiryReplies('inq-1').first;
        expect(replies.map((reply) => reply.id).toList(), ['rep-1', 'rep-2']);
        expect(replies[0].roleLabel, 'PACC Counselor');
        expect(replies[0].isAdministrator, isFalse);
        expect(replies[1].roleLabel, 'PACC Administrator');
        expect(replies[1].isAdministrator, isTrue);
      },
    );
  });

  group('MyInquiriesScreen & StudentInquiryDetailScreen', () {
    testWidgets(
      'student opens own inquiry, reads counselor & admin replies read-only',
      (tester) async {
        final repository = _StubInquiryRepository(
          inquiriesById: {
            'inq-1': _inquiry(
              id: 'inq-1',
              userId: 'student-1',
              subject: 'Guidance Follow-up',
              message: 'Could we review my scholarship requirements?',
              status: StudentInquiryStatus.inProgress,
              responseCount: 2,
            ),
          },
          repliesById: {
            'inq-1': [
              _reply(
                id: 'r1',
                authorName: 'Dr. Reyes',
                authorRole: 'counselor',
                message: 'Please bring your endorsement letter tomorrow.',
                createdAt: DateTime(2026, 11, 15, 10, 30),
              ),
              _reply(
                id: 'r2',
                authorName: 'Admin Bautista',
                authorRole: 'admin',
                message: 'Your PACC intake slot has been confirmed.',
                createdAt: DateTime(2026, 11, 15, 11, 45),
              ),
            ],
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MyInquiriesScreen(
              userId: 'student-1',
              repository: repository,
              currentUserIdProvider: () => 'student-1',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Guidance Follow-up'), findsOneWidget);
        expect(find.text('In Progress'), findsOneWidget);
        expect(find.text('2 replies'), findsOneWidget);

        await tester.tap(find.text('Guidance Follow-up'));
        await tester.pumpAndSettle();

        expect(find.text('Inquiry Details'), findsOneWidget);
        expect(
          find.text('Could we review my scholarship requirements?'),
          findsOneWidget,
        );
        expect(find.text('PACC Replies'), findsOneWidget);
        expect(find.text('Dr. Reyes · PACC Counselor'), findsOneWidget);
        expect(
          find.text('Please bring your endorsement letter tomorrow.'),
          findsOneWidget,
        );
        expect(
          find.text('Admin Bautista · PACC Administrator'),
          findsOneWidget,
        );
        expect(
          find.text('Your PACC intake slot has been confirmed.'),
          findsOneWidget,
        );

        // Replies remain strictly read-only for students.
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(TextFormField), findsNothing);
        expect(find.textContaining('Send reply'), findsNothing);
      },
    );

    testWidgets('shows loading indicator then empty state when no inquiries', (
      tester,
    ) async {
      final controller = StreamController<List<StudentInquiryRecord>>();
      addTearDown(controller.close);
      final repository = _StreamOverrideInquiryRepository(
        listStreamBuilder: (_) => controller.stream,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MyInquiriesScreen(
            userId: 'student-1',
            repository: repository,
            currentUserIdProvider: () => 'student-1',
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      controller.add(const <StudentInquiryRecord>[]);
      await tester.pumpAndSettle();

      expect(find.text('No submitted inquiries yet'), findsOneWidget);
    });

    testWidgets(
      'handles permission-denied and retries transient list errors cleanly',
      (tester) async {
        final permRepo = _StreamOverrideInquiryRepository(
          listStreamBuilder: (_) => Stream<List<StudentInquiryRecord>>.error(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            ),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MyInquiriesScreen(
              userId: 'student-1',
              repository: permRepo,
              currentUserIdProvider: () => 'student-1',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Unable to access inquiries'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);

        var attempts = 0;
        final retryRepo = _StreamOverrideInquiryRepository(
          listStreamBuilder: (_) {
            attempts++;
            if (attempts == 1) {
              return Stream<List<StudentInquiryRecord>>.error(
                FirebaseException(
                  plugin: 'cloud_firestore',
                  code: 'unavailable',
                  message: 'Temporary outage',
                ),
              );
            }
            return Stream.value([
              _inquiry(
                id: 'inq-recovered',
                userId: 'student-1',
                subject: 'Recovered Inquiry',
                message: 'Now loaded.',
              ),
            ]);
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MyInquiriesScreen(
              userId: 'student-1',
              repository: retryRepo,
              currentUserIdProvider: () => 'student-1',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Could not load your inquiries'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);

        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(find.text('Recovered Inquiry'), findsOneWidget);
      },
    );

    testWidgets(
      'detail handles missing/deleted inquiry, permission-denied, and reply retry',
      (tester) async {
        final missingRepo = _StreamOverrideInquiryRepository(
          detailStreamBuilder: (_, _) =>
              Stream<StudentInquiryRecord?>.value(null),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: StudentInquiryDetailScreen(
              inquiryId: 'inq-missing',
              userId: 'student-1',
              repository: missingRepo,
              currentUserIdProvider: () => 'student-1',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Inquiry not found'), findsOneWidget);

        final deniedRepo = _StreamOverrideInquiryRepository(
          detailStreamBuilder: (_, _) => Stream<StudentInquiryRecord?>.error(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: StudentInquiryDetailScreen(
              inquiryId: 'inq-foreign',
              userId: 'student-1',
              repository: deniedRepo,
              currentUserIdProvider: () => 'student-1',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Inquiry access restricted'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);

        var replyAttempts = 0;
        final replyRetryRepo = _StreamOverrideInquiryRepository(
          detailStreamBuilder: (id, uid) => Stream.value(
            _inquiry(
              id: id,
              userId: uid,
              subject: 'Reply Retry Test',
              message: 'Please update me.',
            ),
          ),
          repliesStreamBuilder: (_) {
            replyAttempts++;
            if (replyAttempts == 1) {
              return Stream<List<StudentInquiryReply>>.error(
                FirebaseException(
                  plugin: 'cloud_firestore',
                  code: 'unavailable',
                ),
              );
            }
            return Stream.value([
              _reply(
                id: 'r-ok',
                authorName: 'Counselor Lim',
                authorRole: 'counselor',
                message: 'Reply loaded after retry.',
                createdAt: DateTime(2026, 11, 15, 14),
              ),
            ]);
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: StudentInquiryDetailScreen(
              inquiryId: 'inq-retry',
              userId: 'student-1',
              repository: replyRetryRepo,
              currentUserIdProvider: () => 'student-1',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Replies could not be loaded right now.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(find.text('Reply loaded after retry.'), findsOneWidget);
      },
    );

    testWidgets(
      'clears displayed inquiry data immediately on sign-out or account switch',
      (tester) async {
        final authController = StreamController<String?>.broadcast();
        addTearDown(authController.close);

        final repository = _StubInquiryRepository(
          inquiriesById: {
            'inq-1': _inquiry(
              id: 'inq-1',
              userId: 'student-1',
              subject: 'Student One Private Subject',
              message: 'Confidential message from student 1',
            ),
            'inq-2': _inquiry(
              id: 'inq-2',
              userId: 'student-2',
              subject: 'Student Two Subject',
              message: 'Message from student 2',
            ),
          },
          repliesById: {
            'inq-1': [
              _reply(
                id: 'r1',
                authorName: 'Dr. Cruz',
                authorRole: 'counselor',
                message: 'Confidential counselor reply to student 1',
                createdAt: DateTime(2026, 11, 15, 13),
              ),
            ],
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: StudentInquiryDetailScreen(
              inquiryId: 'inq-1',
              userId: 'student-1',
              repository: repository,
              currentUserIdProvider: () => 'student-1',
              authUidChanges: authController.stream,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Student One Private Subject'), findsOneWidget);
        expect(
          find.text('Confidential counselor reply to student 1'),
          findsOneWidget,
        );

        // Sign out clears detail screen immediately.
        authController.add(null);
        await tester.pumpAndSettle();

        expect(find.text('Session access changed'), findsOneWidget);
        expect(find.text('Student One Private Subject'), findsNothing);
        expect(
          find.text('Confidential counselor reply to student 1'),
          findsNothing,
        );

        // Unpinned list switches safely between accounts without stale data.
        await tester.pumpWidget(
          MaterialApp(
            home: MyInquiriesScreen(
              repository: repository,
              currentUserIdProvider: () => 'student-1',
              authUidChanges: authController.stream,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Student One Private Subject'), findsOneWidget);
        expect(find.text('Student Two Subject'), findsNothing);

        authController.add('student-2');
        await tester.pumpAndSettle();
        expect(find.text('Student One Private Subject'), findsNothing);
        expect(find.text('Student Two Subject'), findsOneWidget);

        authController.add(null);
        await tester.pumpAndSettle();
        expect(find.text('Sign in required'), findsOneWidget);
        expect(find.text('Student Two Subject'), findsNothing);
      },
    );

    testWidgets(
      'ServicesScreen View My Inquiries button opens MyInquiriesScreen',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(430, 3200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ChangeNotifierProvider<AppointmentProvider>(
            create: (_) => AppointmentProvider(_EmptyAppointmentRepository()),
            child: const MaterialApp(home: ServicesScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('PACC Support Service'), findsNothing);
        expect(find.text('Set Appointment'), findsNothing);
        final button = find.text('View My Inquiries');
        expect(button, findsOneWidget);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();

        expect(find.byType(MyInquiriesScreen), findsOneWidget);
        expect(find.text('My Inquiries'), findsOneWidget);
      },
    );
  });
}

StudentInquiryRecord _inquiry({
  required String id,
  required String userId,
  required String subject,
  required String message,
  StudentInquiryStatus status = StudentInquiryStatus.pending,
  int responseCount = 0,
}) {
  return StudentInquiryRecord(
    id: id,
    userId: userId,
    subject: subject,
    message: message,
    category: 'Service Form',
    status: status,
    createdAt: DateTime(2026, 11, 15, 9),
    responseCount: responseCount,
  );
}

StudentInquiryReply _reply({
  required String id,
  required String authorName,
  required String authorRole,
  required String message,
  DateTime? createdAt,
}) {
  return StudentInquiryReply(
    id: id,
    message: message,
    authorName: authorName,
    authorRole: authorRole,
    createdAt: createdAt,
  );
}

class _StubInquiryRepository extends InquiryRepository {
  _StubInquiryRepository({
    this.inquiriesById = const {},
    this.repliesById = const {},
  });

  final Map<String, StudentInquiryRecord> inquiriesById;
  final Map<String, List<StudentInquiryReply>> repliesById;

  @override
  Stream<List<StudentInquiryRecord>> watchMyInquiries(String userId) {
    final trimmed = userId.trim();
    final items =
        inquiriesById.values.where((item) => item.userId == trimmed).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Stream.value(items);
  }

  @override
  Stream<StudentInquiryRecord?> watchMyInquiry(
    String inquiryId, {
    required String userId,
  }) {
    final record = inquiriesById[inquiryId];
    if (record == null) return Stream.value(null);
    if (record.userId != userId.trim()) {
      return Stream.error(
        StateError('You do not have permission to view this inquiry.'),
      );
    }
    return Stream.value(record);
  }

  @override
  Stream<List<StudentInquiryReply>> watchMyInquiryReplies(String inquiryId) =>
      Stream.value(repliesById[inquiryId] ?? const <StudentInquiryReply>[]);
}

class _StreamOverrideInquiryRepository extends InquiryRepository {
  _StreamOverrideInquiryRepository({
    this.listStreamBuilder,
    this.detailStreamBuilder,
    this.repliesStreamBuilder,
  });

  final Stream<List<StudentInquiryRecord>> Function(String userId)?
  listStreamBuilder;
  final Stream<StudentInquiryRecord?> Function(String inquiryId, String userId)?
  detailStreamBuilder;
  final Stream<List<StudentInquiryReply>> Function(String inquiryId)?
  repliesStreamBuilder;

  @override
  Stream<List<StudentInquiryRecord>> watchMyInquiries(String userId) =>
      listStreamBuilder?.call(userId) ??
      Stream.value(const <StudentInquiryRecord>[]);

  @override
  Stream<StudentInquiryRecord?> watchMyInquiry(
    String inquiryId, {
    required String userId,
  }) =>
      detailStreamBuilder?.call(inquiryId, userId) ??
      Stream<StudentInquiryRecord?>.value(null);

  @override
  Stream<List<StudentInquiryReply>> watchMyInquiryReplies(String inquiryId) =>
      repliesStreamBuilder?.call(inquiryId) ??
      Stream.value(const <StudentInquiryReply>[]);
}

class _MemoryFirestoreService implements FirestoreService {
  _MemoryFirestoreService({
    this.inquiries = const {},
    this.repliesByInquiry = const {},
  });

  final Map<String, Map<String, dynamic>> inquiries;
  final Map<String, List<Map<String, dynamic>>> repliesByInquiry;

  @override
  Stream<Map<String, dynamic>?> watchDocument(
    String collection,
    String documentId,
  ) {
    if (collection == 'inquiries') {
      return Stream.value(inquiries[documentId]);
    }
    return Stream.value(null);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchDocuments(
    String collection, {
    Map<String, Object?> whereEquals = const {},
    Map<String, Object?> whereArrayContains = const {},
    Map<String, List<Object?>> whereIn = const {},
    String? orderBy,
    bool descending = false,
    int? limit,
  }) {
    if (collection == 'inquiries') {
      final uid = whereEquals['userId']?.toString();
      final filtered = inquiries.values
          .where((doc) => uid == null || doc['userId'] == uid)
          .toList();
      return Stream.value(filtered);
    }
    if (collection.startsWith('inquiries/') &&
        collection.endsWith('/replies')) {
      final inquiryId = collection.split('/')[1];
      final items = List<Map<String, dynamic>>.from(
        repliesByInquiry[inquiryId] ?? const [],
      );
      if (orderBy == 'createdAt') {
        items.sort((a, b) {
          final aVal = a['createdAt']?.toString() ?? '';
          final bVal = b['createdAt']?.toString() ?? '';
          return descending ? bVal.compareTo(aVal) : aVal.compareTo(bVal);
        });
      }
      return Stream.value(items);
    }
    return Stream.value(const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyAppointmentRepository extends AppointmentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
