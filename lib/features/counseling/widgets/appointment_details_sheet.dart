import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/appointment_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../repositories/appointment_repository.dart';

import '../../../models/appointment_model.dart';
import '../../../core/widgets/mindmate_bottom_navigation.dart';
import 'appointment_presentation.dart';

enum AppointmentDisplayStatus {
  requested,
  pending,
  upcoming,
  confirmed,
  rescheduleProposed,
  declined,
  completed,
  cancelled,
  other,
}

AppointmentDisplayStatus appointmentDisplayStatus(String value) {
  return switch (value.trim().toLowerCase()) {
    'requested' => AppointmentDisplayStatus.requested,
    'pending' => AppointmentDisplayStatus.requested,
    'upcoming' => AppointmentDisplayStatus.upcoming,
    'confirmed' => AppointmentDisplayStatus.confirmed,
    'reschedule_proposed' => AppointmentDisplayStatus.rescheduleProposed,
    'declined' => AppointmentDisplayStatus.declined,
    'completed' => AppointmentDisplayStatus.completed,
    'cancelled' || 'canceled' => AppointmentDisplayStatus.cancelled,
    _ => AppointmentDisplayStatus.other,
  };
}

bool isSameAppointmentDate(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String formatAppointmentDate(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

Color appointmentStatusColor(AppointmentDisplayStatus status) =>
    switch (status) {
      AppointmentDisplayStatus.requested => const Color(0xFFF0A400),
      AppointmentDisplayStatus.pending => const Color(0xFFF0A400),
      AppointmentDisplayStatus.upcoming => const Color(0xFFE5AC00),
      AppointmentDisplayStatus.confirmed => const Color(0xFF3D8B68),
      AppointmentDisplayStatus.rescheduleProposed => const Color(0xFF61738A),
      AppointmentDisplayStatus.declined => const Color(0xFFB54A4A),
      AppointmentDisplayStatus.completed => const Color(0xFF3D8B68),
      AppointmentDisplayStatus.cancelled => const Color(0xFF8A8173),
      AppointmentDisplayStatus.other => const Color(0xFF61738A),
    };

Future<void> showAppointmentDetailsSheet(
  BuildContext context,
  AppointmentModel appointment, {
  VoidCallback? onBookAppointment,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppointmentVisuals.background,
  shape: const RoundedRectangleBorder(),
  builder: (context) {
    final auth = context.watch<AuthProvider?>();
    if (auth != null && auth.authenticatedUserId != appointment.userId) {
      return const SafeArea(child: Padding(padding: EdgeInsets.all(24), child: Text('This appointment is unavailable for the current account.')));
    }
    final provider = context.watch<AppointmentProvider?>();
    final matches = provider?.appointments.where((item) => item.id == appointment.id && item.userId == appointment.userId);
    if (provider != null && !provider.isLoading && matches!.isEmpty) {
      return const SafeArea(child: Padding(padding: EdgeInsets.all(24), child: Text('This appointment is no longer available. Reopen your appointments to refresh.')));
    }
    final current = matches != null && matches.isNotEmpty ? matches.first : appointment;
    final canEdit = !current.isArchived && current.hasScheduleRevision &&
        current.scheduledAt.isAfter(DateTime.now()) &&
        (current.lifecycleStatus == AppointmentStatus.requested || current.lifecycleStatus == AppointmentStatus.confirmed) &&
        auth?.authenticatedUserId == current.userId;
    final canBook = onBookAppointment != null && {
      AppointmentStatus.cancelled, AppointmentStatus.completed,
      AppointmentStatus.noShow, AppointmentStatus.declined,
    }.contains(current.lifecycleStatus);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height,
      child: RepaintBoundary(key: const ValueKey('appointment-details-page'), child: Scaffold(
        backgroundColor: AppointmentVisuals.background,
        body: SafeArea(bottom: false, child: Column(children: [
          AppointmentPageHeader(title: 'Appointment details', subtitle: 'Everything about your PACC request.', onBack: () => Navigator.pop(context)),
          Expanded(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                key: const ValueKey('appointment-session-summary'),
                padding: const EdgeInsets.all(20),
                decoration: AppointmentVisuals.card,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LayoutBuilder(builder: (context, constraints) {
                    final label = const Text('YOUR COUNSELING SESSION', style: TextStyle(color: Color(0xFFA17720), fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w800));
                    final badge = AppointmentStatusBadge(status: current.lifecycleStatus);
                    return constraints.maxWidth < 280 || MediaQuery.textScalerOf(context).scale(12) > 18
                        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label, const SizedBox(height: 12), badge])
                        : Row(children: [const Expanded(child: Padding(padding: EdgeInsets.only(right: 12), child: Text('YOUR COUNSELING\nSESSION', style: TextStyle(color: Color(0xFFA17720), fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w800)))), Flexible(child: badge)]);
                  }),
                  const SizedBox(height: 18),
                  const Text('PACC Counseling', style: AppointmentVisuals.title),
                  const SizedBox(height: 12),
                  AppointmentDetailRow(icon: Icons.calendar_today_outlined, label: 'Date', value: _weekdayDate(current.scheduledAt)),
                  AppointmentDetailRow(icon: Icons.schedule, label: 'Time', value: '${current.scheduledTime} \u00b7 Philippine Time (PHT)'),
                  AppointmentDetailRow(icon: Icons.place_outlined, label: 'Location', value: current.location),
                  AppointmentDetailRow(icon: Icons.person_outline, label: 'Counselor', value: _counselorText(current)),
                ]),
              ),
              const SizedBox(height: 24),
              const Text('Appointment activity', style: AppointmentVisuals.section),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20), decoration: AppointmentVisuals.card,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _ActivityEntry(title: 'Request received', detail: 'Your request was received on ${formatAppointmentDate(current.createdAt)}.'),
                  _ActivityEntry(processing: current.lifecycleStatus == AppointmentStatus.requested || current.lifecycleStatus == AppointmentStatus.legacyRequested || current.lifecycleStatus == AppointmentStatus.rescheduleProposed, title: 'Current status', detail: _activityDescription(current.lifecycleStatus)),
                  if (current.scheduleRevision > 0 && current.updatedAt != null)
                    _ActivityEntry(title: 'Appointment updated', detail: 'Last recorded update: ${formatAppointmentDate(current.updatedAt!)}.'),
                  if ((current.staffReply ?? '').trim().isNotEmpty)
                    _ActivityEntry(title: 'Message from PACC', detail: current.staffReply!.trim()),
                ]),
              ),
              if (current.concern.trim().isNotEmpty || current.preferredContactMethod.trim().isNotEmpty || (current.bestTime ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(padding: const EdgeInsets.all(20), decoration: AppointmentVisuals.card, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Your request details', style: AppointmentVisuals.section),
                  if (current.concern.trim().isNotEmpty) ...[
                    const SizedBox(height: 16), const Text('Concern', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6), Text(current.concern.trim(), style: AppointmentVisuals.body),
                  ],
                  if (current.preferredContactMethod.trim().isNotEmpty) AppointmentDetailRow(icon: Icons.contact_phone_outlined, label: 'Preferred contact', value: [current.preferredContactMethod.trim(), current.contactNumber.trim()].where((v) => v.isNotEmpty).join(' \u00b7 ')),
                  if ((current.bestTime ?? '').trim().isNotEmpty) AppointmentDetailRow(icon: Icons.access_time, label: 'Best contact time', value: current.bestTime!.trim()),
                ])),
              ],
              if (current.followUpRecommended && (current.followUpMessage ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(padding: const EdgeInsets.all(20), decoration: AppointmentVisuals.card, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Follow-up offered', style: AppointmentVisuals.section), const SizedBox(height: 8), Text(current.followUpMessage!.trim(), style: AppointmentVisuals.body)])),
              ],
              const SizedBox(height: 16),
              const Text('Appointment details are private to you and authorized PACC staff.', style: AppointmentVisuals.body),
            ])),
          ))),
        ])),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          if (canEdit || canBook) Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            width: double.infinity,
            child: FilledButton.icon(
              style: AppointmentVisuals.primary,
              onPressed: provider?.isSaving == true ? null : () {
                if (canEdit) {
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _EditAppointmentSchedule(appointment: current)));
                } else {
                  Navigator.pop(context);
                  onBookAppointment!();
                }
              },
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(canEdit ? 'Edit date and time' : current.hasAvailableFollowUpOffer ? 'Book Follow-up' : 'Book Appointment'),
            ),
          ),
          const MindMateBottomNavigation(active: MindMateNavDestination.appointments),
        ]),
      )),
    );
  },
);

class _ActivityEntry extends StatelessWidget {
  const _ActivityEntry({required this.title, required this.detail, this.processing = false});
  final bool processing;
  final String title, detail;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Column(children: [
      if (processing) const AppointmentProcessingIndicator() else Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFD1EADD), border: Border.all(color: const Color(0xFF99CEB8), width: 2))),
      Expanded(child: Container(width: 1, color: const Color(0xFFDCEBE3))),
    ]),
    const SizedBox(width: 12),
    Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: AppointmentVisuals.ink, fontSize: 13, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5), Text(detail, style: AppointmentVisuals.body.copyWith(fontSize: 12)),
    ]))),
  ]));
}

String _weekdayDate(DateTime date) {
  const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  return '${weekdays[date.weekday - 1]}, ${formatAppointmentDate(date)}';
}

String _activityDescription(AppointmentStatus status) => switch (status) {
  AppointmentStatus.requested || AppointmentStatus.legacyRequested => 'PACC is reviewing your preferred schedule.',
  AppointmentStatus.confirmed => 'PACC has confirmed your appointment schedule.',
  AppointmentStatus.rescheduleProposed => 'PACC is finalizing the updated appointment schedule.',
  AppointmentStatus.completed => 'This counseling appointment is completed.',
  AppointmentStatus.cancelled => 'This appointment has been cancelled.',
  AppointmentStatus.declined => 'PACC could not confirm this appointment request.',
  AppointmentStatus.expired => 'This request expired before it was confirmed.',
  AppointmentStatus.noShow => 'This appointment was marked as not attended.',
  AppointmentStatus.unknown => 'Reopen your appointments or contact PACC to check this status.',
};

class _EditAppointmentSchedule extends StatefulWidget {
  const _EditAppointmentSchedule({required this.appointment});
  final AppointmentModel appointment;
  @override
  State<_EditAppointmentSchedule> createState() =>
      _EditAppointmentScheduleState();
}

class _EditAppointmentScheduleState extends State<_EditAppointmentSchedule> {
  DateTime? date;
  AppointmentSlot? selected;
  List<AppointmentSlot> slots = [];
  bool loading = false;
  String? requestId;
  String? error;
  bool refreshRequired = false;
  bool sessionInvalidated = false;
  bool reviewing = false;
  bool sent = false;

  Future<void> chooseDate() async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      date = chosen;
      selected = null;
      slots = [];
      loading = true;
      requestId = null;
      error = null;
    });
    final provider = context.read<AppointmentProvider>();
    final result = await provider.getAvailableSlots(chosen);
    if (!mounted || sessionInvalidated || date != chosen) return;
    setState(() {
      final original = widget.appointment.scheduledAt;
      slots = isSameAppointmentDate(chosen, original)
          ? [AppointmentSlot(start: original, label: '${widget.appointment.scheduledTime} (current)'), ...result]
          : result;
      loading = false;
      error = slots.isEmpty ? provider.slotAvailabilityMessage : null;
    });
  }

  Future<void> save() async {
    final slot = selected;
    if (slot == null) return;
    final provider = context.read<AppointmentProvider>();
    requestId ??=
        'edit_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final ok = await provider.rescheduleAppointment(
      widget.appointment,
      slot.start,
      requestId!,
    );
    if (!mounted || context.read<AuthProvider?>()?.authenticatedUserId != widget.appointment.userId) return;
    if (!ok) {
      setState(
        () { error = '${provider.errorMessage ?? 'Unable to change the appointment.'} Reopen the appointment to refresh before trying again.'; refreshRequired = true; },
      );
      return;
    }
    setState(() => sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider?>()?.authenticatedUserId;
    if (uid != widget.appointment.userId) sessionInvalidated = true;
    if (sessionInvalidated) {
      return const Scaffold(body: Center(child: Text('This appointment is unavailable for the current account.')));
    }
    final busy = context.watch<AppointmentProvider>().isSaving;
    final unchanged = selected?.start == widget.appointment.scheduledAt;
    return PopScope(
      canPop: !busy,
      child: RepaintBoundary(key: const ValueKey('appointment-editor-page'), child: Scaffold(
        backgroundColor: AppointmentVisuals.background,
        body: SafeArea(bottom: false, child: Column(children: [
          AppointmentPageHeader(
            title: sent ? 'Schedule update sent' : reviewing ? 'Review schedule change' : 'Edit date & time',
            subtitle: sent ? 'Your appointment information' : reviewing ? 'Check the details before saving' : 'Your appointment \u00b7 ${appointmentStatusLabel(widget.appointment.lifecycleStatus)}',
            onBack: busy ? null : () {
              if (reviewing && !sent) { setState(() => reviewing = false); }
              else { Navigator.pop(context); }
            },
          ),
          Expanded(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (sent) ...[
                const SizedBox(height: 32),
                Center(child: Container(width: 84, height: 84, decoration: BoxDecoration(color: const Color(0xFFE0F3E9), borderRadius: BorderRadius.circular(28)), child: const Icon(Icons.check, size: 40, color: Color(0xFF248166)))),
                const SizedBox(height: 24),
                Center(child: Text(unchanged ? 'Schedule unchanged' : 'Change received', style: AppointmentVisuals.title, textAlign: TextAlign.center)),
                const SizedBox(height: 12),
                Text(unchanged ? 'Your existing schedule and approval have been kept.' : 'Your new preferred time has been submitted. Your appointment is now awaiting confirmation by PACC.', textAlign: TextAlign.center, style: AppointmentVisuals.body),
                const SizedBox(height: 24),
                _ScheduleSummary(title: 'Current state', date: selected!.start, time: selected!.label.replaceAll(' (current)', ''), status: unchanged ? widget.appointment.lifecycleStatus : AppointmentStatus.requested),
                const SizedBox(height: 20),
                const _ScheduleNotice('Watch for a notification when PACC reviews your new preference.'),
              ] else ...[
                if (!reviewing) ...[
                  const _ScheduleNotice('Your current approved/requested slot stays as it is until a change is saved. If you select a different schedule, it must be reviewed by PACC again.'),
                  const SizedBox(height: 18),
                ],
                _ScheduleSummary(title: 'Current schedule', date: widget.appointment.scheduledAt, time: widget.appointment.scheduledTime, status: widget.appointment.lifecycleStatus),
                const SizedBox(height: 22),
                if (reviewing) ...[
                  _ScheduleSummary(title: 'New preferred schedule', date: selected!.start, time: selected!.label.replaceAll(' (current)', ''), onEdit: busy || refreshRequired ? null : () => setState(() => reviewing = false)),
                  const SizedBox(height: 18),
                  _ScheduleNotice(unchanged ? 'This is your current schedule. Its existing approval will be kept.' : 'Changing your schedule will return it to Awaiting confirmation. PACC will need to review the new selection.'),
                ] else ...[
                  const Text('Choose a new date and time', style: AppointmentVisuals.section),
                  const SizedBox(height: 16),
                  Container(padding: const EdgeInsets.all(16), decoration: AppointmentVisuals.card, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: busy || loading || refreshRequired ? null : chooseDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(date == null ? 'Choose a date' : _weekdayDate(date!)),
                    ),
                    if (loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                    for (final slot in slots) Material(color: Colors.transparent, child: ListTile(
                      title: Text(slot.label),
                      subtitle: const Text('Philippine Time (PHT)'),
                      leading: Icon(selected == slot ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: AppointmentVisuals.teal),
                      selected: selected == slot,
                      selectedTileColor: const Color(0xFFFFF4D9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onTap: busy || refreshRequired ? null : () => setState(() { selected = slot; requestId = null; error = null; }),
                    )),
                    if (date != null && !loading && slots.isEmpty && error == null) const Text('No appointment times are available for this date. Please choose another date.', style: AppointmentVisuals.body),
                  ])),
                ],
              ],
              if (error != null) ...[
                const SizedBox(height: 18),
                Semantics(liveRegion: true, child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error, height: 1.5))),
              ],
              const SizedBox(height: 20),
            ]),
          )))),
        ])),
        bottomNavigationBar: SafeArea(top: false, child: Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), child: FilledButton.icon(
          style: AppointmentVisuals.primary,
          iconAlignment: IconAlignment.end,
          icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_forward, size: 18),
          onPressed: sent ? () => Navigator.pop(context) : selected == null || busy || loading || refreshRequired ? null : reviewing ? save : () => setState(() => reviewing = true),
          label: Text(sent ? 'View appointment details' : busy ? 'Saving?' : reviewing ? 'Send schedule change' : 'Review schedule change'),
        ))),
      )),
    );
  }
}

class _ScheduleSummary extends StatelessWidget {
  const _ScheduleSummary({required this.title, required this.date, required this.time, this.status, this.onEdit});
  final String title, time;
  final DateTime date;
  final AppointmentStatus? status;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18), decoration: AppointmentVisuals.card,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(title, style: AppointmentVisuals.section.copyWith(fontSize: 15)),
        if (status != null) AppointmentStatusBadge(status: status!),
        if (onEdit != null) TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
      ]),
      const SizedBox(height: 12),
      Text(_weekdayDate(date), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppointmentVisuals.ink)),
      const Divider(height: 24, color: AppointmentVisuals.line),
      Text('$time \u00b7 PHT', style: const TextStyle(fontWeight: FontWeight.w700, color: AppointmentVisuals.ink)),
    ]),
  );
}

class _ScheduleNotice extends StatelessWidget {
  const _ScheduleNotice(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFEEF7FA), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFD5E9ED))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.info_outline, color: Color(0xFF4D7988), size: 20), const SizedBox(width: 10), Expanded(child: Text(message, style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF4D7988))))]),
  );
}

String _counselorText(AppointmentModel appointment) {
  final name = appointment.counselorName?.trim() ?? '';
  if (name.isEmpty) return (appointment.assignedStaffId ?? '').trim().isEmpty ? 'To be assigned' : 'PACC Counseling Staff';
  if (name.toLowerCase() == 'admin') return 'PACC Counseling Staff';
  return name;
}
