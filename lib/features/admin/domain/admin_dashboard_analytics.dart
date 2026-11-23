import '../../../models/admin_inquiry_model.dart';
import '../../../models/appointment_model.dart';
import '../../../models/user_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import 'admin_status_presentation.dart';

/// Manila local time offset (Asia/Manila is fixed UTC+8 with no DST).
const Duration _manilaOffset = Duration(hours: 8);

DateTime toManilaDateTime(DateTime value) => value.toUtc().add(_manilaOffset);

DateTime manilaDateOnly(DateTime value) {
  final manila = toManilaDateTime(value);
  return DateTime.utc(manila.year, manila.month, manila.day);
}

bool isSameManilaDay(DateTime left, DateTime right) =>
    manilaDateOnly(left) == manilaDateOnly(right);

class DashboardActivityDayBucket {
  const DashboardActivityDayBucket({
    required this.manilaDay,
    required this.count,
  });

  final DateTime manilaDay;
  final int count;
}

class DashboardStatusBreakdownItem {
  const DashboardStatusBreakdownItem({
    required this.key,
    required this.label,
    required this.count,
    required this.tone,
  });

  final String key;
  final String label;
  final int count;
  final AdminSemanticTone tone;

  double shareOf(int total) => total <= 0 ? 0 : count / total;
  int percentOf(int total) => total <= 0 ? 0 : (count / total * 100).round();
}

/// Pure, deterministic analytics calculation for AdminOperationsDashboardPage.
///
/// Never invents historical data or coerces terminal statuses (cancelled,
/// declined, no-show) into completed.
class AdminDashboardAnalytics {
  const AdminDashboardAnalytics({
    required this.activeUsers30d,
    required this.incompleteProfiles,
    required this.openAppointments,
    required this.awaitingReviewAppointments,
    required this.todayActiveAppointments,
    required this.totalAppointments,
    required this.completedAppointments,
    required this.fullAssessments7d,
    required this.openInquiries,
    required this.overdueOpenInquiries24h,
    required this.latestActivityDayBuckets,
    required this.appointmentStatusBreakdown,
    required this.todaySchedule,
  });

  final int activeUsers30d;
  final int incompleteProfiles;
  final int openAppointments;
  final int awaitingReviewAppointments;
  final int todayActiveAppointments;
  final int totalAppointments;
  final int completedAppointments;
  final int fullAssessments7d;
  final int openInquiries;
  final int overdueOpenInquiries24h;
  final List<DashboardActivityDayBucket> latestActivityDayBuckets;
  final List<DashboardStatusBreakdownItem> appointmentStatusBreakdown;
  final List<AppointmentModel> todaySchedule;

  factory AdminDashboardAnalytics.fromRecords({
    required List<UserModel> users,
    required List<AppointmentModel> appointments,
    required List<AdminInquiryModel> inquiries,
    required List<AdminAssessmentRecord> assessments,
    required DateTime now,
    int activityDaysWindow = 7,
  }) {
    final appUsers = users.where((u) => u.isAppUser).toList();
    final appUserIds = appUsers.map((u) => u.id).toSet();

    final cutoff30d = now.subtract(const Duration(days: 30));
    final activeUsers30d = appUsers
        .where(
          (u) => u.lastActiveAt != null && !u.lastActiveAt!.isBefore(cutoff30d),
        )
        .map((u) => u.id)
        .toSet()
        .length;

    final incompleteProfiles = appUsers
        .where((u) => !u.isProfileComplete)
        .length;

    // Last-seen day distribution over the rolling Manila-day window.
    final todayManila = manilaDateOnly(now);
    final windowDays = List<DateTime>.generate(
      activityDaysWindow,
      (i) => todayManila.subtract(Duration(days: activityDaysWindow - 1 - i)),
    );
    final dayCounts = <DateTime, int>{for (final d in windowDays) d: 0};
    for (final user in appUsers) {
      final seen = user.lastActiveAt;
      if (seen == null) continue;
      final seenDay = manilaDateOnly(seen);
      if (dayCounts.containsKey(seenDay)) {
        dayCounts[seenDay] = (dayCounts[seenDay] ?? 0) + 1;
      }
    }
    final latestActivityDayBuckets = windowDays
        .map(
          (day) => DashboardActivityDayBucket(
            manilaDay: day,
            count: dayCounts[day] ?? 0,
          ),
        )
        .toList();

    // Appointment breakdown & open counts.
    var needsReview = 0;
    var confirmed = 0;
    var reschedule = 0;
    var completed = 0;
    var cancelledOrDeclined = 0;
    var noShow = 0;
    var otherUnknown = 0;
    var openAppointments = 0;

    final todaySchedule = <AppointmentModel>[];

    for (final appt in appointments) {
      final status = appt.lifecycleStatus;
      final isRescheduleState =
          status == AppointmentStatus.rescheduleProposed ||
          (appt.hasPendingScheduleChange &&
              status != AppointmentStatus.completed &&
              status != AppointmentStatus.cancelled &&
              status != AppointmentStatus.declined &&
              status != AppointmentStatus.noShow &&
              status != AppointmentStatus.expired);

      if (isRescheduleState) {
        reschedule++;
        if (!appt.isArchived) openAppointments++;
      } else {
        switch (status) {
          case AppointmentStatus.requested:
          case AppointmentStatus.legacyRequested:
            needsReview++;
            if (!appt.isArchived) openAppointments++;
          case AppointmentStatus.confirmed:
            confirmed++;
            if (!appt.isArchived) openAppointments++;
          case AppointmentStatus.rescheduleProposed:
            reschedule++;
            if (!appt.isArchived) openAppointments++;
          case AppointmentStatus.completed:
            completed++;
          case AppointmentStatus.cancelled:
          case AppointmentStatus.declined:
            cancelledOrDeclined++;
          case AppointmentStatus.noShow:
            noShow++;
          case AppointmentStatus.expired:
          case AppointmentStatus.unknown:
            otherUnknown++;
        }
      }

      // Today's Counseling Schedule (Manila local day): exclude cancelled,
      // declined, expired from active scheduled sessions.
      final isCancelledLike =
          status == AppointmentStatus.cancelled ||
          status == AppointmentStatus.declined ||
          status == AppointmentStatus.expired;
      if (!appt.isArchived &&
          !isCancelledLike &&
          isSameManilaDay(appt.scheduledAt, now)) {
        todaySchedule.add(appt);
      }
    }

    todaySchedule.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    final awaitingReviewAppointments = appointments.where((appt) {
      if (appt.isArchived) return false;
      final s = appt.lifecycleStatus;
      if (s == AppointmentStatus.completed ||
          s == AppointmentStatus.cancelled ||
          s == AppointmentStatus.declined ||
          s == AppointmentStatus.noShow ||
          s == AppointmentStatus.expired) {
        return false;
      }
      return s == AppointmentStatus.requested ||
          s == AppointmentStatus.legacyRequested ||
          s == AppointmentStatus.rescheduleProposed ||
          (appt.hasPendingScheduleChange && appt.proposedBy == 'student');
    }).length;

    final breakdown = <DashboardStatusBreakdownItem>[
      if (needsReview > 0)
        DashboardStatusBreakdownItem(
          key: 'needs_review',
          label: 'Needs review',
          count: needsReview,
          tone: AdminSemanticTone.amber,
        ),
      if (confirmed > 0)
        DashboardStatusBreakdownItem(
          key: 'confirmed',
          label: 'Confirmed / upcoming',
          count: confirmed,
          tone: AdminSemanticTone.blue,
        ),
      if (reschedule > 0)
        DashboardStatusBreakdownItem(
          key: 'reschedule',
          label: 'Reschedule required / proposed',
          count: reschedule,
          tone: AdminSemanticTone.amber,
        ),
      if (completed > 0)
        DashboardStatusBreakdownItem(
          key: 'completed',
          label: 'Completed',
          count: completed,
          tone: AdminSemanticTone.green,
        ),
      if (cancelledOrDeclined > 0)
        DashboardStatusBreakdownItem(
          key: 'cancelled_declined',
          label: 'Cancelled / declined',
          count: cancelledOrDeclined,
          tone: AdminSemanticTone.neutral,
        ),
      if (noShow > 0)
        DashboardStatusBreakdownItem(
          key: 'no_show',
          label: 'No-show',
          count: noShow,
          tone: AdminSemanticTone.red,
        ),
      if (otherUnknown > 0)
        DashboardStatusBreakdownItem(
          key: 'other_unknown',
          label: 'Other / unknown',
          count: otherUnknown,
          tone: AdminSemanticTone.neutral,
        ),
    ];

    // Full assessments in rolling 7 days (applying existing visibility rule:
    // main assessment belonging to a visible app user).
    final cutoff7d = now.subtract(const Duration(days: 7));
    final fullAssessments7d = assessments
        .where(
          (a) =>
              a.isMainAssessment &&
              appUserIds.contains(a.userId) &&
              !a.createdAt.isBefore(cutoff7d),
        )
        .length;

    // Open inquiries: pending + in_progress (not resolved).
    final openInquiryList = inquiries
        .where((i) => i.status != InquiryStatus.resolved)
        .toList();
    final overdueOpenInquiries24h = openInquiryList
        .where((i) => now.difference(i.createdAt).inHours >= 24)
        .length;

    return AdminDashboardAnalytics(
      activeUsers30d: activeUsers30d,
      incompleteProfiles: incompleteProfiles,
      openAppointments: openAppointments,
      awaitingReviewAppointments: awaitingReviewAppointments,
      todayActiveAppointments: todaySchedule.length,
      totalAppointments: appointments.length,
      completedAppointments: completed,
      fullAssessments7d: fullAssessments7d,
      openInquiries: openInquiryList.length,
      overdueOpenInquiries24h: overdueOpenInquiries24h,
      latestActivityDayBuckets: latestActivityDayBuckets,
      appointmentStatusBreakdown: breakdown,
      todaySchedule: todaySchedule,
    );
  }
}
