import '../../../models/admin_inquiry_model.dart';
import '../../../models/appointment_model.dart';
import '../../../models/user_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import 'admin_status_presentation.dart';
import 'inquiry_scope.dart';

/// Manila local time offset (Asia/Manila is fixed UTC+8 with no DST).
const Duration _manilaOffset = Duration(hours: 8);

DateTime toManilaDateTime(DateTime value) => value.toUtc().add(_manilaOffset);

DateTime manilaDateOnly(DateTime value) {
  final manila = toManilaDateTime(value);
  return DateTime.utc(manila.year, manila.month, manila.day);
}

bool isSameManilaDay(DateTime left, DateTime right) =>
    manilaDateOnly(left) == manilaDateOnly(right);

String formatManilaShortDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final manila = toManilaDateTime(value);
  return '${months[manila.month - 1]} ${manila.day}, ${manila.year}';
}

class DashboardCaseRow {
  const DashboardCaseRow({
    required this.appointmentId,
    required this.studentName,
    required this.status,
    required this.scheduledAt,
    required this.scheduledTime,
    required this.nextFollowUpLabel,
    this.nextFollowUpDate,
    this.counselorName,
    this.isFollowUp = false,
    this.isAssignedToMe = false,
    this.hasFollowUpOffer = false,
  });

  final String appointmentId;
  final String studentName;
  final String status;
  final DateTime scheduledAt;
  final String scheduledTime;
  final DateTime? nextFollowUpDate;
  final String nextFollowUpLabel;
  final String? counselorName;
  final bool isFollowUp;
  final bool isAssignedToMe;
  final bool hasFollowUpOffer;
}

List<DashboardCaseRow> buildDashboardCaseRows({
  required List<AppointmentModel> sourceAppointments,
  required List<AppointmentModel> allAppointments,
  required DateTime now,
  Set<String> assignedIds = const {},
}) {
  bool isCancelledLike(AppointmentStatus status) =>
      status == AppointmentStatus.cancelled ||
      status == AppointmentStatus.declined ||
      status == AppointmentStatus.expired;

  bool isActionNeeded(AppointmentModel appt) {
    final s = appt.lifecycleStatus;
    if (appt.isFinalized) return false;
    return s == AppointmentStatus.requested ||
        s == AppointmentStatus.legacyRequested ||
        s == AppointmentStatus.rescheduleProposed ||
        appt.hasPendingScheduleChange;
  }

  int priorityRank(AppointmentModel appt) {
    if (isActionNeeded(appt)) return 0;
    if (appt.lifecycleStatus == AppointmentStatus.confirmed) return 1;
    if (appt.hasAvailableFollowUpOffer) return 2;
    return 3;
  }

  final activeVisible = sourceAppointments
      .where((a) => !a.isArchived)
      .toList(growable: false);

  final activePool = allAppointments
      .where((a) => !a.isArchived && !isCancelledLike(a.lifecycleStatus))
      .toList(growable: false);

  final sorted = [...activeVisible]
    ..sort((a, b) {
      final rankA = priorityRank(a);
      final rankB = priorityRank(b);
      if (rankA != rankB) return rankA.compareTo(rankB);
      if (rankA <= 1) {
        return a.scheduledAt.compareTo(b.scheduledAt);
      }
      return b.scheduledAt.compareTo(a.scheduledAt);
    });

  return sorted.map((a) {
    final id = a.userId.trim().isEmpty ? a.id.trim() : a.userId.trim();
    final suffix = id.length > 4 ? id.substring(id.length - 4) : id;
    final trimmedName = a.fullName.trim();
    final studentName = trimmedName.isNotEmpty
        ? trimmedName
        : 'Student ••••$suffix';

    DateTime? nextFollowUpDate;
    var nextFollowUpLabel = 'None scheduled';
    var hasFollowUpOffer = false;

    final followUpId = (a.followUpAppointmentId ?? '').trim();
    AppointmentModel? linkedFollowUp;
    for (final other in activePool) {
      if (other.id.trim() == a.id.trim()) continue;
      if ((followUpId.isNotEmpty && other.id.trim() == followUpId) ||
          (other.parentAppointmentId ?? '').trim() == a.id.trim()) {
        if (linkedFollowUp == null ||
            other.scheduledAt.isBefore(linkedFollowUp.scheduledAt)) {
          linkedFollowUp = other;
        }
      }
    }

    if (linkedFollowUp != null) {
      nextFollowUpDate = linkedFollowUp.scheduledAt;
      nextFollowUpLabel = formatManilaShortDate(linkedFollowUp.scheduledAt);
    } else if (a.hasAvailableFollowUpOffer) {
      hasFollowUpOffer = true;
      nextFollowUpLabel = 'Follow-up offered';
    } else if (a.userId.trim().isNotEmpty) {
      AppointmentModel? nextUpcoming;
      for (final other in activePool) {
        if (other.id.trim() == a.id.trim()) continue;
        if (other.userId.trim() != a.userId.trim()) continue;
        if (!other.isActive) continue;
        if (!other.scheduledAt.isAfter(a.scheduledAt)) continue;
        if (nextUpcoming == null ||
            other.scheduledAt.isBefore(nextUpcoming.scheduledAt)) {
          nextUpcoming = other;
        }
      }
      if (nextUpcoming != null) {
        nextFollowUpDate = nextUpcoming.scheduledAt;
        nextFollowUpLabel = formatManilaShortDate(nextUpcoming.scheduledAt);
      }
    }

    final rawTime = a.scheduledTime.trim();
    final manilaAt = toManilaDateTime(a.scheduledAt);
    final hour = manilaAt.hour == 0
        ? 12
        : manilaAt.hour > 12
        ? manilaAt.hour - 12
        : manilaAt.hour;
    final formattedTime = rawTime.isNotEmpty
        ? rawTime
        : '$hour:${manilaAt.minute.toString().padLeft(2, '0')} ${manilaAt.hour >= 12 ? 'PM' : 'AM'}';

    final counselor = (a.counselorName ?? '').trim();
    return DashboardCaseRow(
      appointmentId: a.id,
      studentName: studentName,
      status: a.status,
      scheduledAt: a.scheduledAt,
      scheduledTime: formattedTime,
      nextFollowUpDate: nextFollowUpDate,
      nextFollowUpLabel: nextFollowUpLabel,
      counselorName: counselor.isEmpty ? null : counselor,
      isFollowUp: (a.parentAppointmentId ?? '').trim().isNotEmpty,
      isAssignedToMe: assignedIds.contains(a.id.trim()),
      hasFollowUpOffer: hasFollowUpOffer,
    );
  }).toList(growable: false);
}

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
    this.processedInquiries = 0,
    required this.latestActivityDayBuckets,
    required this.appointmentStatusBreakdown,
    required this.todaySchedule,
    this.upcomingScheduleBuckets = const [],
    this.upcoming7dAppointments = 0,
    this.activeCaseRows = const [],
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
  final int processedInquiries;
  final List<DashboardActivityDayBucket> latestActivityDayBuckets;
  final List<DashboardStatusBreakdownItem> appointmentStatusBreakdown;
  final List<AppointmentModel> todaySchedule;
  final List<DashboardActivityDayBucket> upcomingScheduleBuckets;
  final int upcoming7dAppointments;
  final List<DashboardCaseRow> activeCaseRows;

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

    // Admin-visible inquiries: only counselor-processed, forwarded, or taken-over
    // items are surfaced or counted on the Administrator dashboard.
    final adminVisibleInquiries = inquiries.where(isAdminVisibleInquiry).toList();
    final openInquiryList = adminVisibleInquiries
        .where((i) => i.isEscalated || i.status != InquiryStatus.resolved)
        .toList();
    final overdueOpenInquiries24h = openInquiryList
        .where((i) => now.difference(i.createdAt).inHours >= 24)
        .length;

    // Upcoming 7-day counseling schedule buckets (Manila today + next 6 days).
    final upcomingDays = List<DateTime>.generate(
      7,
      (i) => todayManila.add(Duration(days: i)),
    );
    final upcomingCounts = <DateTime, int>{for (final d in upcomingDays) d: 0};
    for (final appt in appointments) {
      if (appt.isArchived) continue;
      final status = appt.lifecycleStatus;
      if (status == AppointmentStatus.cancelled ||
          status == AppointmentStatus.declined ||
          status == AppointmentStatus.expired) {
        continue;
      }
      final day = manilaDateOnly(appt.scheduledAt);
      if (upcomingCounts.containsKey(day)) {
        upcomingCounts[day] = (upcomingCounts[day] ?? 0) + 1;
      }
    }
    final upcomingScheduleBuckets = upcomingDays
        .map(
          (day) => DashboardActivityDayBucket(
            manilaDay: day,
            count: upcomingCounts[day] ?? 0,
          ),
        )
        .toList(growable: false);
    final upcoming7dAppointments = upcomingScheduleBuckets.fold<int>(
      0,
      (sum, b) => sum + b.count,
    );

    final activeCaseRows = buildDashboardCaseRows(
      sourceAppointments: appointments
          .where((a) => !a.isFinalized || a.hasAvailableFollowUpOffer)
          .toList(growable: false),
      allAppointments: appointments,
      now: now,
    );

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
      processedInquiries: adminVisibleInquiries.length,
      latestActivityDayBuckets: latestActivityDayBuckets,
      appointmentStatusBreakdown: breakdown,
      todaySchedule: todaySchedule,
      upcomingScheduleBuckets: upcomingScheduleBuckets,
      upcoming7dAppointments: upcoming7dAppointments,
      activeCaseRows: activeCaseRows,
    );
  }
}
