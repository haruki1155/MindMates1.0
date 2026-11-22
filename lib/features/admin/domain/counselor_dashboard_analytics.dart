import '../../../models/appointment_model.dart';
import 'admin_dashboard_analytics.dart';
import 'admin_status_presentation.dart';
import 'portal_appointment_metrics.dart';

class CounselorScheduleDayBucket {
  const CounselorScheduleDayBucket({
    required this.manilaDay,
    required this.paccCount,
    required this.assignedCount,
  });

  final DateTime manilaDay;
  final int paccCount;
  final int assignedCount;
}

/// Pure, deterministic analytics calculation for [CounselorOperationsDashboardPage].
///
/// Uses only authorized Counselor appointment streams (`watchAppointments` and
/// `watchMyAssignedAppointments`). Never invents historical data or coerces
/// terminal statuses (cancelled, declined, no-show, expired) into completed.
class CounselorDashboardAnalytics {
  const CounselorDashboardAnalytics({
    required this.paccMetrics,
    required this.myMetrics,
    required this.totalPaccAppointments,
    required this.totalMyAppointments,
    required this.todayRemainingCount,
    required this.myActiveCaseloadCount,
    required this.myAwaitingFollowUpOfferCount,
    required this.upcoming7dTotal,
    required this.upcoming7dAssignedTotal,
    required this.scheduleWindowBuckets,
    required this.paccStatusBreakdown,
    required this.myStatusBreakdown,
    required this.todaySchedule,
    required this.assignedAppointmentIds,
  });

  final PortalAppointmentMetrics paccMetrics;
  final PortalAppointmentMetrics myMetrics;
  final int totalPaccAppointments;
  final int totalMyAppointments;
  final int todayRemainingCount;
  final int myActiveCaseloadCount;
  final int myAwaitingFollowUpOfferCount;
  final int upcoming7dTotal;
  final int upcoming7dAssignedTotal;
  final List<CounselorScheduleDayBucket> scheduleWindowBuckets;
  final List<DashboardStatusBreakdownItem> paccStatusBreakdown;
  final List<DashboardStatusBreakdownItem> myStatusBreakdown;
  final List<AppointmentModel> todaySchedule;
  final Set<String> assignedAppointmentIds;

  factory CounselorDashboardAnalytics.fromAppointments({
    required List<AppointmentModel> appointments,
    required List<AppointmentModel> myAppointments,
    required DateTime now,
    int scheduleDaysWindow = 7,
  }) {
    final manilaNow = toManilaDateTime(now);
    final manilaLocalReference = DateTime(
      manilaNow.year,
      manilaNow.month,
      manilaNow.day,
      manilaNow.hour,
      manilaNow.minute,
      manilaNow.second,
    );

    List<AppointmentModel> normalizeToManila(List<AppointmentModel> source) =>
        source
            .map((a) {
              final m = toManilaDateTime(a.scheduledAt);
              return a.copyWith(
                scheduledAt: DateTime(
                  m.year,
                  m.month,
                  m.day,
                  m.hour,
                  m.minute,
                  m.second,
                ),
              );
            })
            .toList();

    final normalizedPacc = normalizeToManila(appointments);
    final normalizedMy = normalizeToManila(myAppointments);

    final paccMetrics = PortalAppointmentMetrics.fromAppointments(
      normalizedPacc,
      manilaLocalReference,
    );
    final myMetrics = PortalAppointmentMetrics.fromAppointments(
      normalizedMy,
      manilaLocalReference,
    );

    final assignedIds = myAppointments
        .map((a) => a.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final todayManila = manilaDateOnly(now);
    final windowDays = List<DateTime>.generate(
      scheduleDaysWindow,
      (i) => todayManila.add(Duration(days: i)),
    );
    final paccDayCounts = <DateTime, int>{for (final d in windowDays) d: 0};
    final assignedDayCounts = <DateTime, int>{for (final d in windowDays) d: 0};

    for (final appt in appointments) {
      if (!_isActiveScheduledSession(appt)) continue;
      final day = manilaDateOnly(appt.scheduledAt);
      if (paccDayCounts.containsKey(day)) {
        paccDayCounts[day] = (paccDayCounts[day] ?? 0) + 1;
        if (assignedIds.contains(appt.id.trim())) {
          assignedDayCounts[day] = (assignedDayCounts[day] ?? 0) + 1;
        }
      }
    }

    // Also include any assigned appointment not already counted by ID in PACC list.
    final paccIds = appointments
        .map((a) => a.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final appt in myAppointments) {
      if (paccIds.contains(appt.id.trim())) continue;
      if (!_isActiveScheduledSession(appt)) continue;
      final day = manilaDateOnly(appt.scheduledAt);
      if (assignedDayCounts.containsKey(day)) {
        assignedDayCounts[day] = (assignedDayCounts[day] ?? 0) + 1;
      }
    }

    final scheduleWindowBuckets = windowDays
        .map(
          (day) => CounselorScheduleDayBucket(
            manilaDay: day,
            paccCount: paccDayCounts[day] ?? 0,
            assignedCount: assignedDayCounts[day] ?? 0,
          ),
        )
        .toList();

    final upcoming7dTotal = scheduleWindowBuckets.fold<int>(
      0,
      (sum, b) => sum + b.paccCount,
    );
    final upcoming7dAssignedTotal = scheduleWindowBuckets.fold<int>(
      0,
      (sum, b) => sum + b.assignedCount,
    );

    final todaySchedule =
        appointments
            .where(
              (a) =>
                  _isActiveScheduledSession(a) &&
                  isSameManilaDay(a.scheduledAt, now),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    final todayRemainingCount = todaySchedule
        .where((a) => !_isClosedStatus(a.status))
        .length;

    final myActiveCaseloadCount = myAppointments
        .where((a) => !a.isArchived && !_isClosedStatus(a.status))
        .length;

    final myAwaitingFollowUpOfferCount = myAppointments
        .where((a) => !a.isArchived && a.hasAvailableFollowUpOffer)
        .length;

    return CounselorDashboardAnalytics(
      paccMetrics: paccMetrics,
      myMetrics: myMetrics,
      totalPaccAppointments: appointments.length,
      totalMyAppointments: myAppointments.length,
      todayRemainingCount: todayRemainingCount,
      myActiveCaseloadCount: myActiveCaseloadCount,
      myAwaitingFollowUpOfferCount: myAwaitingFollowUpOfferCount,
      upcoming7dTotal: upcoming7dTotal,
      upcoming7dAssignedTotal: upcoming7dAssignedTotal,
      scheduleWindowBuckets: scheduleWindowBuckets,
      paccStatusBreakdown: buildAppointmentStatusBreakdown(appointments),
      myStatusBreakdown: buildAppointmentStatusBreakdown(myAppointments),
      todaySchedule: todaySchedule,
      assignedAppointmentIds: assignedIds,
    );
  }

  static bool _isClosedStatus(String rawStatus) {
    final s = rawStatus.trim().toLowerCase();
    return s == 'completed' ||
        s == 'complete' ||
        s == 'cancelled' ||
        s == 'canceled' ||
        s == 'declined' ||
        s == 'no_show' ||
        s == 'noshow' ||
        s == 'expired';
  }

  static bool _isActiveScheduledSession(AppointmentModel appointment) {
    if (appointment.isArchived) return false;
    final status = appointment.lifecycleStatus;
    return status != AppointmentStatus.cancelled &&
        status != AppointmentStatus.declined &&
        status != AppointmentStatus.expired;
  }

  static List<DashboardStatusBreakdownItem> buildAppointmentStatusBreakdown(
    List<AppointmentModel> appointments,
  ) {
    var needsReview = 0;
    var confirmed = 0;
    var reschedule = 0;
    var completed = 0;
    var cancelledOrDeclined = 0;
    var noShow = 0;
    var otherUnknown = 0;

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
      } else {
        switch (status) {
          case AppointmentStatus.requested:
          case AppointmentStatus.legacyRequested:
            needsReview++;
          case AppointmentStatus.confirmed:
            confirmed++;
          case AppointmentStatus.rescheduleProposed:
            reschedule++;
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
    }

    return <DashboardStatusBreakdownItem>[
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
  }
}
