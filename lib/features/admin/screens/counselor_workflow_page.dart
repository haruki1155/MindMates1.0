import 'package:flutter/material.dart';

import '../../../models/appointment_model.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../../counseling/widgets/student_personal_info_sheet.dart';
import '../domain/admin_status_presentation.dart';
import '../theme/admin_theme.dart';
import '../widgets/admin_status_badge.dart';
import 'student_case_history_page.dart';

enum CounselorWorkflowMode { cases, followUps }

class CounselorWorkflowPage extends StatelessWidget {
  const CounselorWorkflowPage({
    super.key,
    required this.repository,
    required this.mode,
    required this.onOpenAppointments,
    this.onModeChanged,
    this.studentInfoLoader,
  });

  final StudentPersonalInfoLoader? studentInfoLoader;
  final AdminPortalRepository repository;
  final CounselorWorkflowMode mode;
  final VoidCallback onOpenAppointments;
  final ValueChanged<CounselorWorkflowMode>? onModeChanged;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AppointmentModel>>(
    stream: repository.watchMyAssignedAppointments(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Text('We could not load your assigned counseling work.'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final allAppointments = snapshot.data!;
      final appointmentsById = <String, AppointmentModel>{
        for (final item in allAppointments)
          if (item.id.isNotEmpty) item.id: item,
      };
      final items = mode == CounselorWorkflowMode.cases
          ? _cases(allAppointments)
          : _followUps(allAppointments, appointmentsById: appointmentsById);
      final awaitingClientCount = mode == CounselorWorkflowMode.followUps
          ? items
                .where(
                  (item) => resolveFollowUpOfferStatus(
                    item,
                    linkedAppointment: _linkedAppointment(
                      item,
                      appointmentsById,
                    ),
                  ).isAwaitingClientResponse,
                )
                .length
          : 0;
      return LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 28.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              horizontalPadding,
              horizontalPadding,
              40,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My Cases',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      mode == CounselorWorkflowMode.cases
                          ? 'Continue assigned counseling work with privacy-safe student identifiers.'
                          : 'Review actual post-session follow-up offers and bookings.',
                      style: const TextStyle(color: AdminColors.muted),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Assigned Cases'),
                          selected: mode == CounselorWorkflowMode.cases,
                          onSelected: onModeChanged == null
                              ? null
                              : (_) =>
                                    onModeChanged!(CounselorWorkflowMode.cases),
                        ),
                        ChoiceChip(
                          label: const Text('Follow-ups'),
                          selected: mode == CounselorWorkflowMode.followUps,
                          onSelected: onModeChanged == null
                              ? null
                              : (_) => onModeChanged!(
                                  CounselorWorkflowMode.followUps,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _Summary(
                      items: items,
                      followUps: mode == CounselorWorkflowMode.followUps,
                      awaitingClientCount: awaitingClientCount,
                    ),
                    const SizedBox(height: 18),
                    if (items.isEmpty)
                      _EmptyState(
                        followUps: mode == CounselorWorkflowMode.followUps,
                        onOpenAppointments: onOpenAppointments,
                      )
                    else
                      ...items.map(
                        (appointment) => _WorkCard(
                          repository: repository,
                          appointment: appointment,
                          followUp: mode == CounselorWorkflowMode.followUps,
                          linkedAppointment: _linkedAppointment(
                            appointment,
                            appointmentsById,
                          ),
                          onOpenAppointments: onOpenAppointments,
                          canViewStudentInfo:
                              repository.currentAccessRole.canAccessClinicalData,
                          studentInfoLoader: studentInfoLoader,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  static AppointmentModel? _linkedAppointment(
    AppointmentModel item,
    Map<String, AppointmentModel> appointmentsById,
  ) {
    final linkedId = item.followUpAppointmentId?.trim();
    if (linkedId == null || linkedId.isEmpty) return null;
    return appointmentsById[linkedId];
  }

  static const _includedFollowUpStatuses = <String>{
    'offered',
    'booked',
    'completed',
    'declined',
    'cancelled',
    'canceled',
    'expired',
    'no_show',
    'noshow',
  };

  static List<AppointmentModel> _cases(List<AppointmentModel> values) {
    final ordered = values.where((item) => item.userId.isNotEmpty).toList()
      ..sort((a, b) {
        final bySchedule = b.scheduledAt.compareTo(a.scheduledAt);
        if (bySchedule != 0) return bySchedule;
        final byCreated = b.createdAt.compareTo(a.createdAt);
        if (byCreated != 0) return byCreated;
        return a.id.compareTo(b.id);
      });
    final seen = <String>{};
    return ordered.where((item) => seen.add(item.userId)).toList();
  }

  static List<AppointmentModel> _followUps(
    List<AppointmentModel> values, {
    Map<String, AppointmentModel> appointmentsById = const {},
  }) {
    final filtered = values
        .where(
          (item) =>
              item.followUpRecommended &&
              _includedFollowUpStatuses.contains(
                item.followUpStatus.toLowerCase().trim(),
              ),
        )
        .toList();
    int priority(AppointmentModel item) {
      final state = resolveFollowUpOfferStatus(
        item,
        linkedAppointment: _linkedAppointment(item, appointmentsById),
      );
      if (state.isAwaitingClientResponse) return 0;
      if (state.presentation.label == 'Booked') return 1;
      return 2;
    }

    filtered.sort((a, b) {
      final byPriority = priority(a).compareTo(priority(b));
      if (byPriority != 0) return byPriority;
      return a.scheduledAt.compareTo(b.scheduledAt);
    });
    return filtered;
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.items,
    required this.followUps,
    required this.awaitingClientCount,
  });
  final List<AppointmentModel> items;
  final bool followUps;
  final int awaitingClientCount;

  @override
  Widget build(BuildContext context) {
    final metrics = <Widget>[
      _Metric(
        label: followUps ? 'Follow-up records' : 'Assigned cases',
        value: '${items.length}',
      ),
      if (followUps)
        _Metric(
          label: 'Awaiting client response',
          value: '$awaitingClientCount',
          highlighted: awaitingClientCount > 0,
        ),
      const _Metric(label: 'Privacy scope', value: 'Assigned only'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < metrics.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                metrics[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < metrics.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: metrics[i]),
            ],
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.highlighted = false,
  });
  final String label, value;
  final bool highlighted;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: highlighted
          ? AdminColors.amberBg.withValues(alpha: 0.45)
          : AdminColors.surface,
      border: Border.all(
        color: highlighted ? AdminColors.amberBorder : AdminColors.border,
        width: highlighted ? 1.5 : 1,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: highlighted ? AdminColors.amberFg : AdminColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: highlighted ? AdminColors.amberFg : AdminColors.ink,
          ),
        ),
      ],
    ),
  );
}

class _WorkCard extends StatelessWidget {
  const _WorkCard({
    required this.repository,
    required this.appointment,
    required this.followUp,
    this.linkedAppointment,
    required this.onOpenAppointments,
    required this.canViewStudentInfo,
    this.studentInfoLoader,
  });
  final AdminPortalRepository repository;
  final AppointmentModel appointment;
  final bool followUp;
  final AppointmentModel? linkedAppointment;
  final VoidCallback onOpenAppointments;
  final bool canViewStudentInfo;
  final StudentPersonalInfoLoader? studentInfoLoader;
  @override
  Widget build(BuildContext context) {
    final id = appointment.userId;
    final suffix = id.length > 4 ? id.substring(id.length - 4) : id;
    final recordedName = appointment.fullName.trim();
    final displayName = recordedName.isEmpty
        ? 'Student ••••$suffix'
        : recordedName;
    final followUpState = followUp
        ? resolveFollowUpOfferStatus(
            appointment,
            linkedAppointment: linkedAppointment,
          )
        : null;
    final isPendingOffer = followUpState?.isAwaitingClientResponse ?? false;
    final offerNote = (appointment.followUpMessage ?? '').trim();

    final avatar = CircleAvatar(
      backgroundColor: isPendingOffer
          ? AdminColors.amberBg
          : AdminColors.accentSoft,
      foregroundColor: isPendingOffer ? AdminColors.amberFg : AdminColors.ink,
      child: Text(
        displayName.substring(0, 1).toUpperCase(),
        style: TextStyle(
          fontSize: 14,
          fontWeight: isPendingOffer ? FontWeight.w800 : FontWeight.w600,
          color: isPendingOffer ? AdminColors.amberFg : AdminColors.ink,
        ),
      ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (followUpState != null)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                displayName,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              AdminStatusBadge(
                presentation: followUpState.presentation,
                compact: true,
              ),
            ],
          )
        else
          Text(
            displayName,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        const SizedBox(height: 5),
        Text(
          '${_date(appointment.scheduledAt)} · ${appointment.scheduledTime.isEmpty ? _time(appointment.scheduledAt) : appointment.scheduledTime}',
          style: const TextStyle(color: AdminColors.muted),
        ),
        const SizedBox(height: 4),
        if (followUpState != null) ...[
          Text(
            followUpState.supportingText,
            style: TextStyle(
              color: isPendingOffer ? AdminColors.amberFg : AdminColors.muted,
              fontSize: 13,
              height: 1.35,
              fontWeight: isPendingOffer ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (isPendingOffer && offerNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Offer note: $offerNote',
              style: const TextStyle(
                color: AdminColors.ink,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ] else
          const Text(
            'Assigned counseling case',
            style: TextStyle(color: AdminColors.muted, fontSize: 12),
          ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isPendingOffer
            ? AdminColors.amberBg.withValues(alpha: 0.28)
            : AdminColors.surface,
        border: Border.all(
          color: isPendingOffer ? AdminColors.amberBorder : AdminColors.border,
          width: isPendingOffer ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 680;
          final actions = Wrap(
            alignment: isCompact ? WrapAlignment.start : WrapAlignment.end,
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ViewStudentInformationButton(
                userId: appointment.userId,
                canView: canViewStudentInfo,
                loader: studentInfoLoader,
              ),
              if (id.isNotEmpty && canOpenStudentCaseHistory(repository))
                StudentCaseHistoryButton(
                  repository: repository,
                  studentId: id,
                  studentName: displayName,
                ),
              TextButton(
                onPressed: onOpenAppointments,
                child: const Text('Open appointment'),
              ),
            ],
          );
          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
                    const SizedBox(width: 12),
                    Expanded(child: details),
                  ],
                ),
                const SizedBox(height: 10),
                actions,
              ],
            );
          }
          return Row(
            children: [
              avatar,
              const SizedBox(width: 14),
              Expanded(flex: 3, child: details),
              const SizedBox(width: 12),
              Flexible(flex: 2, child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.followUps,
    required this.onOpenAppointments,
  });
  final bool followUps;
  final VoidCallback onOpenAppointments;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: AdminColors.surface,
      border: Border.all(color: AdminColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          followUps
              ? 'No follow-ups due'
              : 'No cases in your assigned colleges',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          followUps
              ? "You're up to date with your assigned follow-up work."
              : 'No counseling cases were found for your assigned colleges.',
          style: const TextStyle(color: AdminColors.muted),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: onOpenAppointments,
          child: const Text('View appointments'),
        ),
      ],
    ),
  );
}

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _time(DateTime value) =>
    '${value.hour == 0
        ? 12
        : value.hour > 12
        ? value.hour - 12
        : value.hour}:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
