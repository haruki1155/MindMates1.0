import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/counselor_dashboard_analytics.dart';
import 'package:mind_mates/models/appointment_model.dart';

AppointmentModel _appt({
  required String id,
  required DateTime scheduledAt,
  required String status,
  String userId = 'u1',
  DateTime? archivedAt,
  String? proposedBy,
  String? parentAppointmentId,
  bool followUpRecommended = false,
  String followUpStatus = 'none',
}) => AppointmentModel(
  id: id,
  userId: userId,
  fullName: 'Student $id',
  scheduledAt: scheduledAt,
  scheduledTime: '9:00 AM',
  location: 'PACC Office',
  concern: 'Academic stress',
  contactNumber: '09171234567',
  email: '$userId@example.com',
  preferredContactMethod: 'email',
  status: status,
  createdAt: scheduledAt.subtract(const Duration(days: 1)),
  archivedAt: archivedAt,
  proposedBy: proposedBy,
  parentAppointmentId: parentAppointmentId,
  followUpRecommended: followUpRecommended,
  followUpStatus: followUpStatus,
);

void main() {
  // 2026-11-21 14:00 Manila time = 2026-11-21 06:00 UTC.
  final fixedNow = DateTime.utc(2026, 11, 21, 6, 0);

  group('CounselorDashboardAnalytics', () {
    test(
      'computes PACC metrics, assigned caseload metrics, 7-day schedule buckets, and status breakdown without coercing terminal statuses to completed',
      () {
        final todayConfirm = _appt(
          id: 'a-today-confirm',
          scheduledAt: DateTime.utc(2026, 11, 21, 1, 0), // 9:00 AM Manila
          status: 'confirmed',
        );
        final todayCompleted = _appt(
          id: 'a-today-completed',
          scheduledAt: DateTime.utc(2026, 11, 21, 2, 0),
          status: 'completed',
          followUpRecommended: true,
          followUpStatus: 'offered',
        );
        final todayCancelled = _appt(
          id: 'a-today-cancelled',
          scheduledAt: DateTime.utc(2026, 11, 21, 3, 0),
          status: 'cancelled',
        );
        final tomorrowAssigned = _appt(
          id: 'a-tomorrow-assigned',
          scheduledAt: DateTime.utc(2026, 11, 22, 2, 0),
          status: 'confirmed',
        );
        final requestedPending = _appt(
          id: 'a-requested',
          scheduledAt: DateTime.utc(2026, 11, 23, 2, 0),
          status: 'requested',
        );
        final rescheduleRequired = _appt(
          id: 'a-reschedule',
          scheduledAt: DateTime.utc(2026, 11, 24, 2, 0),
          status: 'reschedule_proposed',
        );
        final noShowRecord = _appt(
          id: 'a-noshow',
          scheduledAt: DateTime.utc(2026, 11, 20, 2, 0),
          status: 'no_show',
        );

        final pacc = [
          todayConfirm,
          todayCompleted,
          todayCancelled,
          tomorrowAssigned,
          requestedPending,
          rescheduleRequired,
          noShowRecord,
        ];
        final myCaseload = [
          todayConfirm,
          todayCompleted,
          tomorrowAssigned,
          noShowRecord,
        ];

        final analytics = CounselorDashboardAnalytics.fromAppointments(
          appointments: pacc,
          myAppointments: myCaseload,
          now: fixedNow,
        );

        expect(analytics.totalPaccAppointments, 7);
        expect(analytics.totalMyAppointments, 4);

        // Completed strictly counts exact completed status, never cancelled/no_show.
        expect(analytics.paccMetrics.completed, 1);
        expect(analytics.myMetrics.completed, 1);
        expect(analytics.paccMetrics.today, 1);
        expect(analytics.myMetrics.today, 1);
        expect(analytics.paccMetrics.upcoming, 1);
        expect(analytics.myMetrics.upcoming, 1);

        // Today schedule includes active today sessions (confirmed + completed),
        // excluding cancelled/declined/expired, with 1 remaining open today.
        expect(
          analytics.todaySchedule.map((a) => a.id).toList(),
          ['a-today-confirm', 'a-today-completed'],
        );
        expect(analytics.todayRemainingCount, 1);

        // My active caseload excludes completed/no_show/cancelled/archived.
        expect(analytics.myActiveCaseloadCount, 2);
        // Follow-up offered awaiting client response count.
        expect(analytics.myAwaitingFollowUpOfferCount, 1);

        // 7-day window buckets (today Nov 21 through Nov 27 Manila).
        expect(analytics.scheduleWindowBuckets, hasLength(7));
        expect(analytics.scheduleWindowBuckets[0].paccCount, 2);
        expect(analytics.scheduleWindowBuckets[0].assignedCount, 2);
        expect(analytics.scheduleWindowBuckets[1].paccCount, 1);
        expect(analytics.scheduleWindowBuckets[1].assignedCount, 1);
        expect(analytics.scheduleWindowBuckets[2].paccCount, 1);
        expect(analytics.scheduleWindowBuckets[2].assignedCount, 0);
        expect(analytics.scheduleWindowBuckets[3].paccCount, 1);
        expect(analytics.upcoming7dTotal, 5);
        expect(analytics.upcoming7dAssignedTotal, 3);

        // Breakdown categories.
        final paccByKey = {
          for (final item in analytics.paccStatusBreakdown)
            item.key: item.count,
        };
        expect(paccByKey['needs_review'], 1);
        expect(paccByKey['confirmed'], 2);
        expect(paccByKey['reschedule'], 1);
        expect(paccByKey['completed'], 1);
        expect(paccByKey['cancelled_declined'], 1);
        expect(paccByKey['no_show'], 1);
      },
    );

    test('handles empty appointment lists cleanly', () {
      final analytics = CounselorDashboardAnalytics.fromAppointments(
        appointments: const [],
        myAppointments: const [],
        now: fixedNow,
      );

      expect(analytics.totalPaccAppointments, 0);
      expect(analytics.totalMyAppointments, 0);
      expect(analytics.upcoming7dTotal, 0);
      expect(analytics.todaySchedule, isEmpty);
      expect(analytics.paccStatusBreakdown, isEmpty);
      expect(analytics.myStatusBreakdown, isEmpty);
      expect(analytics.scheduleWindowBuckets, hasLength(7));
      expect(
        analytics.scheduleWindowBuckets.every((b) => b.paccCount == 0),
        isTrue,
      );
    });
  });
}
