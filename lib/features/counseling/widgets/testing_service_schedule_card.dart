import 'package:flutter/material.dart';

import '../../../models/student_inquiry_model.dart';
import '../../../models/testing_service_schedule.dart';
import 'testing_service_documents_gallery.dart';

class _CardPalette {
  const _CardPalette._();
  static const ink = Color(0xFF1D343C);
  static const muted = Color(0xFF73878E);
  static const border = Color(0xFFE5EAE5);
  static const sun = Color(0xFFFFCD3A);
  static const greenBg = Color(0xFFE3F1E6);
  static const greenInk = Color(0xFF1F6B3A);
  static const blueBg = Color(0xFFE5F0FF);
  static const blueInk = Color(0xFF1D4D8F);
  static const amberBg = Color(0xFFFFF4D8);
  static const amberInk = Color(0xFF8C5B00);
}

String _formatManilaDate(DateTime wallClock) {
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
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final weekday = weekdays[wallClock.weekday - 1];
  return '$weekday, ${months[wallClock.month - 1]} ${wallClock.day}, ${wallClock.year}';
}

/// Displays Testing Service schedule state, requirements checklist, and
/// user actions (Accept or one-time Reschedule) inside an inquiry detail view.
/// Confirmed schedules are locked with no cancel or reschedule controls.
class TestingServiceScheduleCard extends StatelessWidget {
  const TestingServiceScheduleCard({
    super.key,
    required this.inquiry,
    required this.onAccept,
    required this.onRequestReschedule,
    this.onLoadDocument,
    this.busy = false,
    this.showSubmissionBanner = false,
  });

  final StudentInquiryRecord inquiry;
  final Future<void> Function() onAccept;
  final Future<void> Function(String reason) onRequestReschedule;
  final TestingServiceDocumentLoader? onLoadDocument;
  final bool busy;
  final bool showSubmissionBanner;

  @override
  Widget build(BuildContext context) {
    final schedule =
        inquiry.testingSchedule ??
        const TestingServiceSchedule(
          status: TestingScheduleStatus.awaitingSchedule,
        );
    final displayAppointment = schedule.toDisplayAppointment(
      inquiryId: inquiry.id,
      userId: inquiry.userId,
      fullName: '',
      email: '',
      concern: inquiry.message,
      createdAt: inquiry.createdAt,
    );

    final (badgeBg, badgeFg) = switch (schedule.status) {
      TestingScheduleStatus.confirmed ||
      TestingScheduleStatus.completed => (
        _CardPalette.greenBg,
        _CardPalette.greenInk,
      ),
      TestingScheduleStatus.proposed => (
        _CardPalette.blueBg,
        _CardPalette.blueInk,
      ),
      TestingScheduleStatus.cancelled => (
        const Color(0xFFFDECEC),
        const Color(0xFF9E2A2B),
      ),
      _ => (_CardPalette.amberBg, _CardPalette.amberInk),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _CardPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(
                Icons.fact_check_outlined,
                size: 18,
                color: _CardPalette.ink,
              ),
              const Text(
                'Testing Service Schedule',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _CardPalette.ink,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  schedule.status.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: badgeFg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Requirements: Endorsement Letter · Official receipt for PHP 250',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _CardPalette.muted,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Availability: Monday–Saturday, 8:00 AM–5:00 PM (PHT)',
            style: TextStyle(fontSize: 12, color: _CardPalette.muted),
          ),
          if ((inquiry.contactNumber ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'SMS Contact: ${inquiry.contactNumber}',
              style: const TextStyle(fontSize: 12, color: _CardPalette.muted),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('testing-processing-counselor'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _CardPalette.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.badge_outlined,
                  size: 18,
                  color: _CardPalette.ink,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        inquiry.processingCounselorName != null
                            ? 'Processing Counselor: ${inquiry.processingCounselorName}'
                            : 'Assigning a PACC Counselor / Psychometrician',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _CardPalette.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        inquiry.processingCounselorName != null
                            ? 'Approach ${inquiry.processingCounselorName} (${inquiry.processingCounselorRoleLabel}) at the PACC Office for your testing schedule and requirements.'
                            : 'Their name will appear here once assigned so you know whom to approach at the PACC Office.',
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: _CardPalette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (inquiry.testingDocuments != null &&
              !inquiry.testingDocuments!.isEmpty) ...[
            const SizedBox(height: 12),
            if (onLoadDocument != null)
              TestingServiceDocumentsGallery(
                inquiryId: inquiry.id,
                documents: inquiry.testingDocuments!,
                loadDocument: onLoadDocument!,
                compact: true,
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < inquiry.testingDocuments!.all.length; i++)
                    () {
                      final doc = inquiry.testingDocuments!.all[i];
                      final admissionOrder =
                          doc.kind == TestingDocumentKind.admissionRequirement
                          ? inquiry.testingDocuments!.all
                                .take(i + 1)
                                .where(
                                  (item) =>
                                      item.kind ==
                                      TestingDocumentKind.admissionRequirement,
                                )
                                .length
                          : null;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F6F4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${doc.kind.label}: ${doc.displayFileName(admissionIndex: admissionOrder)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _CardPalette.ink,
                          ),
                        ),
                      );
                    }(),
                ],
              ),
          ],
          const SizedBox(height: 12),
          if (displayAppointment != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAF7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _CardPalette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_formatManilaDate(displayAppointment.scheduledAt)} · ${displayAppointment.scheduledTime} (PHT)',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _CardPalette.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Location: ${displayAppointment.location}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _CardPalette.ink,
                    ),
                  ),
                  if ((displayAppointment.counselorName ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Scheduled by: ${displayAppointment.counselorName}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _CardPalette.muted,
                      ),
                    ),
                  ],
                  if ((displayAppointment.staffReply ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      displayAppointment.staffReply!,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: _CardPalette.ink,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (showSubmissionBanner ||
              schedule.status == TestingScheduleStatus.awaitingSchedule)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _CardPalette.greenBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'The Psychometrician-in-charge will review your uploaded documents (2–5 minutes processing time) and send your confirmed testing schedule via SMS and in-app notifications.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: _CardPalette.greenInk,
                ),
              ),
            ),
          if (schedule.status == TestingScheduleStatus.rescheduleRequested) ...[
            if ((schedule.rescheduleReason ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Reschedule reason: ${schedule.rescheduleReason}',
                  style: const TextStyle(fontSize: 13, color: _CardPalette.ink),
                ),
              ),
            const Text(
              'Reschedule requested (1 of 1 used). Waiting for PACC to propose a revised schedule.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _CardPalette.muted,
              ),
            ),
          ],
          if (schedule.status == TestingScheduleStatus.proposed) ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  key: const ValueKey('testing-accept-schedule'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _CardPalette.sun,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: busy ? null : onAccept,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(busy ? 'Saving…' : 'Accept Schedule'),
                ),
                if (schedule.canUserRequestReschedule)
                  OutlinedButton.icon(
                    key: const ValueKey('testing-request-reschedule'),
                    onPressed: busy
                        ? null
                        : () => _openRescheduleDialog(context),
                    icon: const Icon(Icons.event_repeat_outlined),
                    label: const Text('Request Reschedule'),
                  ),
              ],
            ),
            if (schedule.hasUsedReschedule) ...[
              const SizedBox(height: 8),
              const Text(
                'You have used your one allowed reschedule request. Please accept this revised schedule.',
                style: TextStyle(
                  fontSize: 12,
                  color: _CardPalette.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
          if (schedule.status == TestingScheduleStatus.confirmed)
            const Text(
              'Your Testing Service schedule is confirmed and locked. Cancellation and further rescheduling are not available.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _CardPalette.greenInk,
              ),
            ),
          if (schedule.status == TestingScheduleStatus.completed)
            Container(
              key: const ValueKey('testing-mobile-completed-banner'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _CardPalette.greenBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Completed${(schedule.completedByName ?? '').isNotEmpty ? ' by ${schedule.completedByName}' : ''}.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _CardPalette.greenInk,
                    ),
                  ),
                  if ((schedule.completionNote ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Notes: ${schedule.completionNote}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: _CardPalette.greenInk,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  const Text(
                    'You may now submit a new Testing Service schedule request when needed.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _CardPalette.greenInk,
                    ),
                  ),
                ],
              ),
            ),
          if (schedule.status == TestingScheduleStatus.cancelled)
            Container(
              key: const ValueKey('testing-mobile-cancelled-banner'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cancelled${(schedule.cancelledByName ?? '').isNotEmpty ? ' by ${schedule.cancelledByName}' : ''}.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF9E2A2B),
                    ),
                  ),
                  if ((schedule.cancelReason ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Reason: ${schedule.cancelReason}',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFF9E2A2B),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openRescheduleDialog(BuildContext context) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RescheduleReasonDialog(),
    );
    if (reason != null && reason.isNotEmpty) {
      await onRequestReschedule(reason);
    }
  }
}

class _RescheduleReasonDialog extends StatefulWidget {
  const _RescheduleReasonDialog();

  @override
  State<_RescheduleReasonDialog> createState() =>
      _RescheduleReasonDialogState();
}

class _RescheduleReasonDialogState extends State<_RescheduleReasonDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Request One-Time Reschedule'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You may request a reschedule only once for this Testing Service request.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('testing-reschedule-reason'),
              controller: _controller,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: 'Reason for reschedule',
                errorText: _errorText,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Back'),
      ),
      FilledButton(
        key: const ValueKey('testing-reschedule-submit'),
        onPressed: () {
          final trimmed = _controller.text.trim();
          if (trimmed.length < 3) {
            setState(
              () => _errorText = 'Please enter at least 3 characters.',
            );
            return;
          }
          Navigator.of(context).pop(trimmed);
        },
        child: const Text('Submit Request'),
      ),
    ],
  );
}
