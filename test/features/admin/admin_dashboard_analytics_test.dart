import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_dashboard_analytics.dart';
import 'package:mind_mates/models/admin_inquiry_model.dart';
import 'package:mind_mates/models/appointment_model.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

UserModel _user(
  String id, {
  DateTime? lastActiveAt,
  bool complete = true,
  AccessRole accessRole = AccessRole.appUser,
}) => UserModel(
  id: id,
  email: '$id@example.com',
  name: 'User $id',
  firstName: complete ? 'First' : null,
  lastName: complete ? 'Last' : null,
  role: 'student',
  schoolId: complete ? '2026-0001' : null,
  department: complete ? 'BSCS' : null,
  course: complete ? 'Computer Science' : null,
  yearLevel: complete ? '3rd Year' : null,
  accessRole: accessRole,
  lastActiveAt: lastActiveAt,
);

AppointmentModel _appointment(
  String id, {
  required String status,
  required DateTime scheduledAt,
  DateTime? createdAt,
  DateTime? archivedAt,
  String? parentAppointmentId,
}) => AppointmentModel(
  id: id,
  userId: 'u1',
  fullName: 'Student $id',
  scheduledAt: scheduledAt,
  scheduledTime: '10:00 AM',
  location: 'PACC Office',
  concern: 'Check-in',
  contactNumber: '09171234567',
  email: 'student@example.com',
  preferredContactMethod: 'email',
  status: status,
  createdAt: createdAt ?? scheduledAt,
  archivedAt: archivedAt,
  parentAppointmentId: parentAppointmentId,
);

AdminInquiryModel _inquiry(
  String id, {
  required InquiryStatus status,
  required DateTime createdAt,
}) => AdminInquiryModel(
  id: id,
  userId: 'u1',
  name: 'Sender $id',
  email: '$id@example.com',
  category: 'General',
  subject: 'Subject $id',
  message: 'Body',
  status: status,
  createdAt: createdAt,
);

AdminAssessmentRecord _assessment(
  String id, {
  required String userId,
  required DateTime createdAt,
  required bool isQuick,
}) => AdminAssessmentRecord(
  id: id,
  userId: userId,
  createdAt: createdAt,
  type: isQuick ? 'quick' : 'full',
  status: 'generally_supported',
);

void main() {
  test('computes accurate metrics, Manila day schedule, and explicit status breakdown', () {
    // 2026-11-21 14:00 Manila = 2026-11-21 06:00 UTC
    final now = DateTime.utc(2026, 11, 21, 6, 0);

    final users = [
      _user('u1', lastActiveAt: now.subtract(const Duration(hours: 2))),
      _user(
        'u2',
        lastActiveAt: now.subtract(const Duration(days: 30)),
        complete: false,
      ),
      _user(
        'u3',
        lastActiveAt: now.subtract(const Duration(days: 31)),
        complete: false,
      ),
      _user(
        'staff1',
        accessRole: AccessRole.counselor,
        lastActiveAt: now,
      ), // excluded from app users
    ];

    final appointments = [
      _appointment('a1', status: 'requested', scheduledAt: now),
      _appointment(
        'a2',
        status: 'confirmed',
        scheduledAt: now.add(const Duration(hours: 1)),
        parentAppointmentId: 'a0',
      ),
      _appointment(
        'a3',
        status: 'reschedule_proposed',
        scheduledAt: now.add(const Duration(days: 1)),
      ),
      _appointment(
        'a4',
        status: 'completed',
        scheduledAt: now.subtract(const Duration(days: 1)),
      ),
      _appointment('a5', status: 'cancelled', scheduledAt: now),
      _appointment('a6', status: 'no_show', scheduledAt: now.subtract(const Duration(days: 2))),
      _appointment('a7', status: 'mystery_legacy', scheduledAt: now.subtract(const Duration(days: 3))),
    ];

    final inquiries = [
      _inquiry('i1', status: InquiryStatus.pending, createdAt: now.subtract(const Duration(hours: 30))),
      _inquiry('i2', status: InquiryStatus.inProgress, createdAt: now.subtract(const Duration(hours: 25))),
      _inquiry('i3', status: InquiryStatus.inProgress, createdAt: now.subtract(const Duration(hours: 5))),
      _inquiry('i4', status: InquiryStatus.resolved, createdAt: now.subtract(const Duration(hours: 48))),
    ];

    final assessments = [
      _assessment('as1', userId: 'u1', createdAt: now.subtract(const Duration(days: 1)), isQuick: false),
      _assessment('as2', userId: 'u1', createdAt: now.subtract(const Duration(days: 1)), isQuick: true),
      _assessment('as3', userId: 'u2', createdAt: now.subtract(const Duration(days: 8)), isQuick: false),
      _assessment('as4', userId: 'hidden_user', createdAt: now.subtract(const Duration(days: 1)), isQuick: false),
    ];

    final analytics = AdminDashboardAnalytics.fromRecords(
      users: users,
      appointments: appointments,
      inquiries: inquiries,
      assessments: assessments,
      now: now,
    );

    expect(analytics.activeUsers30d, 2); // u1 and u2 (exact 30d boundary)
    expect(analytics.incompleteProfiles, 2); // u2, u3
    expect(analytics.openAppointments, 3); // a1, a2, a3 (not completed/cancelled/no_show/unknown)
    expect(analytics.awaitingReviewAppointments, 2); // a1, a3 (not confirmed a2)
    expect(analytics.todayActiveAppointments, 2); // a1, a2 (cancelled a5 excluded!)
    expect(analytics.completedAppointments, 1); // ONLY a4 (cancelled/no_show NOT coerced!)
    expect(analytics.fullAssessments7d, 1); // ONLY as1 (quick as2, old as3, hidden as4 excluded)
    expect(analytics.openInquiries, 3); // i1, i2, i3
    expect(analytics.overdueOpenInquiries24h, 2); // i1, i2

    final keys = analytics.appointmentStatusBreakdown.map((e) => e.key).toList();
    expect(
      keys,
      containsAll([
        'needs_review',
        'confirmed',
        'reschedule',
        'completed',
        'cancelled_declined',
        'no_show',
        'other_unknown',
      ]),
    );
    expect(
      analytics.appointmentStatusBreakdown
          .firstWhere((e) => e.key == 'completed')
          .count,
      1,
    );
    expect(
      analytics.appointmentStatusBreakdown
          .firstWhere((e) => e.key == 'cancelled_declined')
          .count,
      1,
    );
    expect(
      analytics.appointmentStatusBreakdown
          .firstWhere((e) => e.key == 'no_show')
          .count,
      1,
    );
    expect(analytics.latestActivityDayBuckets.length, 7);
    expect(analytics.latestActivityDayBuckets.last.count, 1); // u1 seen today Manila
  });

  test('omits zero status categories including other_unknown when absent', () {
    final now = DateTime.utc(2026, 11, 21, 6, 0);
    final analytics = AdminDashboardAnalytics.fromRecords(
      users: const [],
      appointments: [
        _appointment('a1', status: 'confirmed', scheduledAt: now),
      ],
      inquiries: const [],
      assessments: const [],
      now: now,
    );

    expect(analytics.appointmentStatusBreakdown.length, 1);
    expect(analytics.appointmentStatusBreakdown.single.key, 'confirmed');
  });
}
