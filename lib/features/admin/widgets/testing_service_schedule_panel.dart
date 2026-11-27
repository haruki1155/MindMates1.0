import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../models/admin_inquiry_model.dart';
import '../../../models/pacc_availability_model.dart';
import '../../../models/profile_roles.dart';
import '../../../models/testing_service_schedule.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../../../repositories/pacc_availability_repository.dart';
import '../../../services/firebase/firebase_error_message.dart';
import '../../counseling/widgets/testing_service_documents_gallery.dart';
import '../services/clinical_file_download_stub.dart'
    if (dart.library.js_interop) '../services/clinical_file_download_web.dart'
    as testing_download;
import '../theme/admin_theme.dart';

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
  return '${weekdays[wallClock.weekday - 1]}, ${months[wallClock.month - 1]} ${wallClock.day}, ${wallClock.year}';
}

String _formatSlotHour(int hour) {
  final display = hour % 12 == 0 ? 12 : hour % 12;
  final period = hour < 12 ? 'AM' : 'PM';
  return '$display:00 $period';
}

DateTime _nextAvailableTestingDate(DateTime now) {
  final manilaNow = now.toUtc().add(const Duration(hours: 8));
  var candidate = DateTime(manilaNow.year, manilaNow.month, manilaNow.day + 1);
  if (candidate.weekday == DateTime.sunday) {
    candidate = candidate.add(const Duration(days: 1));
  }
  return candidate;
}

/// Staff workflow panel for verifying uploaded Testing Service documents and
/// issuing a PACC decision (Accept Schedule, Re-schedule, or Cancel with a
/// dropdown reason), reusing Counseling Appointment decision ergonomics while
/// keeping all state inside `inquiries/{id}`.
class TestingServiceSchedulePanel extends StatefulWidget {
  const TestingServiceSchedulePanel({
    super.key,
    required this.inquiry,
    required this.repository,
    this.nowProvider = DateTime.now,
    this.onDecisionSent,
    this.availabilityStream,
  });

  final AdminInquiryModel inquiry;
  final AdminPortalRepository repository;
  final DateTime Function() nowProvider;
  final VoidCallback? onDecisionSent;
  final Stream<PaccAvailabilityModel?>? availabilityStream;

  @override
  State<TestingServiceSchedulePanel> createState() =>
      _TestingServiceSchedulePanelState();
}

class _TestingServiceSchedulePanelState
    extends State<TestingServiceSchedulePanel> {
  late DateTime _selectedDate;
  int _selectedHour = 9;
  String _action = 'reschedule';
  String _reason = '';
  final _customReasonController = TextEditingController();
  final _locationController = TextEditingController(
    text: testingServiceDefaultLocation,
  );
  String? _requestId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _syncDefaultsFromInquiry();
  }

  @override
  void didUpdateWidget(covariant TestingServiceSchedulePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final statusChanged =
        oldWidget.inquiry.testingSchedule?.status !=
            widget.inquiry.testingSchedule?.status ||
        oldWidget.inquiry.preferredScheduleAt !=
            widget.inquiry.preferredScheduleAt;
    if (oldWidget.inquiry.id != widget.inquiry.id || statusChanged) {
      _syncDefaultsFromInquiry(
        resetText: oldWidget.inquiry.id != widget.inquiry.id,
      );
      _requestId = null;
      _error = null;
    }
  }

  DateTime? _validFuturePreferredWall(
    AdminInquiryModel inquiry, [
    PaccAvailabilityModel? availability,
  ]) {
    final preferredAt = inquiry.preferredScheduleAt;
    if (preferredAt == null) return null;
    if (!preferredAt.toUtc().isAfter(widget.nowProvider().toUtc())) {
      return null;
    }
    final wall = preferredAt.toUtc().add(const Duration(hours: 8));
    if (availability != null) {
      return availability.resolveScheduleAt(preferredAt).canBookAppointments
          ? wall
          : null;
    }
    if (!isWithinTestingServiceAvailability(wall)) return null;
    return testingServiceSlotHours.contains(wall.hour) ? wall : null;
  }

  List<String> _availableActions(
    TestingServiceSchedule schedule,
    DateTime? validFuturePreferred,
  ) {
    if (schedule.isCancelled || schedule.isCompleted || schedule.isConfirmed) {
      return const [];
    }
    return [
      if (schedule.status == TestingScheduleStatus.awaitingSchedule &&
          validFuturePreferred != null)
        'accept',
      'reschedule',
    ];
  }

  static List<String> _testingReasons(String action) => switch (action) {
    'accept' => const [
      'Documents verified and schedule is available',
      'Testing schedule approved by PACC',
      'Other',
    ],
    'reschedule' => const [
      'Psychometrician / Counselor schedule conflict',
      'Testing room unavailable',
      'Office schedule adjustment',
      'Requested time is unavailable',
      'Emergency office closure',
      'Other',
    ],
    'complete' => const [
      'Testing session completed',
      'Psychological assessment finished',
      'Test battery submitted and recorded',
      'Other',
    ],
    _ => const [
      'Incomplete or unreadable Endorsement Letter',
      'Invalid or unreadable Official Receipt (PHP 250.00)',
      'Applicant ineligible for Testing Service',
      'Duplicate Testing Service request',
      'Applicant requested cancellation',
      'Office schedule unavailable',
      'Other',
    ],
  };

  String _actionLabel(String action) => switch (action) {
    'accept' => 'Approve Schedule',
    _ => 'Re-schedule',
  };

  Future<void> _openCancelDialog() async {
    if (_saving) return;
    final reasons = _testingReasons('cancel');
    var selectedReason = reasons.first;
    final customController = TextEditingController();
    String? dialogError;
    final submittedReason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cancel Testing Service Schedule'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  key: const ValueKey('admin-testing-cancel-reason-dropdown'),
                  isExpanded: true,
                  initialValue: selectedReason,
                  decoration: const InputDecoration(
                    labelText: 'Cancellation reason',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final item in reasons)
                      DropdownMenuItem(
                        value: item,
                        child: Text(item, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      selectedReason = value;
                      dialogError = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('admin-testing-cancel-custom-reason'),
                  controller: customController,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: selectedReason == 'Other'
                        ? 'Custom reason (required)'
                        : 'Additional note (optional)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    dialogError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Back'),
            ),
            FilledButton(
              key: const ValueKey('admin-testing-confirm-cancel-btn'),
              style: FilledButton.styleFrom(
                backgroundColor: AdminColors.redFg,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final custom = customController.text.trim();
                if (selectedReason == 'Other' && custom.length < 3) {
                  setDialogState(
                    () => dialogError =
                        'Please enter a custom reason of at least 3 characters.',
                  );
                  return;
                }
                final combined = [
                  if (selectedReason != 'Other') selectedReason,
                  if (custom.isNotEmpty) custom,
                ].join(': ');
                Navigator.of(dialogContext).pop(combined);
              },
              child: const Text('Confirm Cancel'),
            ),
          ],
        ),
      ),
    );
    customController.dispose();
    if (submittedReason == null || !mounted) return;
    _requestId ??= newInquiryRequestId();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.cancelTestingServiceSchedule(
        widget.inquiry.id,
        reason: submittedReason,
        expectedRevision: widget.inquiry.routingRevision,
        requestId: _requestId!,
      );
      if (!mounted) return;
      setState(() => _requestId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Testing Service schedule cancelled.')),
      );
      widget.onDecisionSent?.call();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = FirebaseErrorMessage.describe(
            error,
            fallback: 'Unable to cancel Testing Service schedule.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _syncDefaultsFromInquiry({bool resetText = true}) {
    final schedule =
        widget.inquiry.testingSchedule ??
        const TestingServiceSchedule(
          status: TestingScheduleStatus.awaitingSchedule,
        );
    final preferredWall = _validFuturePreferredWall(widget.inquiry);
    if (preferredWall != null) {
      _selectedDate = DateTime(
        preferredWall.year,
        preferredWall.month,
        preferredWall.day,
      );
      _selectedHour = preferredWall.hour;
    } else {
      _selectedDate = _nextAvailableTestingDate(widget.nowProvider());
      _selectedHour = 9;
    }
    final actions = _availableActions(schedule, preferredWall);
    if (actions.isNotEmpty) {
      if (!actions.contains(_action) || resetText) {
        _action = actions.first;
      }
      final validReasons = _testingReasons(_action);
      if (!validReasons.contains(_reason) || resetText) {
        _reason = validReasons.first;
      }
    }
    if (resetText) {
      _customReasonController.clear();
      final existing = widget.inquiry.testingSchedule;
      _locationController.text =
          (existing != null && existing.location.trim().isNotEmpty)
          ? existing.location
          : testingServiceDefaultLocation;
    }
  }

  @override
  void dispose() {
    _locationController.dispose();
    _customReasonController.dispose();
    super.dispose();
  }

  bool get _isAdminReadOnly =>
      widget.repository.isSuperAdmin ||
      widget.repository.currentAccessRole == AccessRole.admin;

  bool get _canDecide {
    final schedule = widget.inquiry.testingSchedule;
    if (widget.inquiry.isOperationalProjection) return false;
    if (widget.inquiry.status == InquiryStatus.resolved) return false;
    if (schedule?.isCancelled == true || schedule?.isCompleted == true) {
      return false;
    }
    if (_isAdminReadOnly) return false;
    if (widget.inquiry.isTakenOver) return false;
    final uid = widget.repository.currentUserId;
    return widget.repository.currentAccessRole == AccessRole.counselor &&
        uid != null &&
        widget.inquiry.assigneeIds.contains(uid);
  }

  String _readOnlyReason() {
    if (widget.inquiry.isOperationalProjection) {
      return 'Read-only operational status view. Decision controls and document verification are restricted to assigned counselors.';
    }
    if (widget.inquiry.status == InquiryStatus.resolved) {
      return 'This inquiry has been marked resolved, so schedule decisions are closed.';
    }
    if (_isAdminReadOnly) {
      return 'Admin review is read-only (supervising and monitoring only). Only assigned counselors can approve, reschedule, cancel, or complete Testing Service schedules.';
    }
    if (widget.inquiry.isTakenOver) {
      return 'An administrator has taken over this inquiry.';
    }
    if (widget.inquiry.assigneeIds.isEmpty) {
      return 'Awaiting counselor assignment. Assign a counselor in Inquiry Routing below to enable scheduling decisions.';
    }
    return 'Only the counselor assigned to this inquiry can make Testing Service schedule decisions.';
  }

  Future<void> _pickDate(PaccAvailabilityModel? availability) async {
    final manilaToday = widget.nowProvider().toUtc().add(
      const Duration(hours: 8),
    );
    final firstDate = DateTime(
      manilaToday.year,
      manilaToday.month,
      manilaToday.day,
    );
    final now = widget.nowProvider();
    var initialDate = _selectedDate.isBefore(firstDate)
        ? firstDate
        : _selectedDate;
    if (!isTestingServiceDateSelectable(
      initialDate,
      availability: availability,
      now: now,
    )) {
      initialDate = nextSelectableTestingServiceDate(
        startingFrom: firstDate,
        availability: availability,
      );
    }
    if (!isTestingServiceDateSelectable(
      initialDate,
      availability: availability,
      now: now,
    )) {
      setState(
        () => _error = 'No open Testing Service dates are currently scheduled.',
      );
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 180)),
      selectableDayPredicate: (date) => isTestingServiceDateSelectable(
        date,
        availability: availability,
        now: now,
      ),
    );
    if (picked != null && mounted) {
      final slots = testingServiceSlotsForDate(
        picked,
        availability: availability,
        now: now,
      ).where((slot) => slot.available).toList(growable: false);
      setState(() {
        _selectedDate = picked;
        if (slots.isNotEmpty &&
            !slots.any(
              (slot) =>
                  slot.instant.toUtc().add(const Duration(hours: 8)).hour ==
                  _selectedHour,
            )) {
          _selectedHour = slots.first.instant
              .toUtc()
              .add(const Duration(hours: 8))
              .hour;
        }
      });
    }
  }

  Future<void> _sendDecision(PaccAvailabilityModel? availability) async {
    if (_saving) return;
    final custom = _customReasonController.text.trim();
    final combinedReason = [
      if (_reason != 'Other' && _reason.trim().isNotEmpty) _reason.trim(),
      if (custom.isNotEmpty) custom,
    ].join(': ');

    if (_reason == 'Other' && custom.length < 3 && _action != 'complete') {
      setState(
        () => _error = 'Please enter a custom reason of at least 3 characters.',
      );
      return;
    }
    if (_action == 'cancel' && combinedReason.trim().length < 3) {
      setState(
        () => _error = 'Please select or enter a cancellation reason.',
      );
      return;
    }

    final preferredAt = widget.inquiry.preferredScheduleAt;
    final scheduledAt = _action == 'accept' && preferredAt != null
        ? preferredAt
        : testingServiceInstantFromManila(
            year: _selectedDate.year,
            month: _selectedDate.month,
            day: _selectedDate.day,
            hour: _selectedHour,
          );

    if (_action != 'cancel' && _action != 'complete') {
      final now = widget.nowProvider();
      if (!scheduledAt.isAfter(now.toUtc())) {
        setState(
          () => _error = 'Choose a future Testing Service date and time.',
        );
        return;
      }
      if (availability != null) {
        final resolved = availability.resolveScheduleAt(scheduledAt);
        if (!resolved.canBookAppointments) {
          setState(
            () => _error =
                resolved.closureReason ??
                'Selected slot is unavailable in PACC schedule.',
          );
          return;
        }
      }
    }

    _requestId ??= newInquiryRequestId();
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (_action == 'cancel') {
        await widget.repository.cancelTestingServiceSchedule(
          widget.inquiry.id,
          reason: combinedReason,
          expectedRevision: widget.inquiry.routingRevision,
          requestId: _requestId!,
        );
      } else if (_action == 'complete') {
        await widget.repository.completeTestingServiceSchedule(
          widget.inquiry.id,
          note: combinedReason,
          expectedRevision: widget.inquiry.routingRevision,
          requestId: _requestId!,
        );
      } else {
        await widget.repository.proposeTestingServiceSchedule(
          widget.inquiry.id,
          scheduledAt: scheduledAt,
          expectedRevision: widget.inquiry.routingRevision,
          requestId: _requestId!,
          decisionMode: _action == 'accept' ? 'accept_requested' : 'reschedule',
          reason: combinedReason,
          location: _locationController.text.trim(),
        );
      }
      if (!mounted) return;
      final successText = switch (_action) {
        'accept' => 'Testing Service schedule approved and confirmed.',
        'complete' => 'Testing Service request marked as completed.',
        'cancel' => 'Testing Service schedule cancelled.',
        _ => 'Testing Service schedule sent to the applicant.',
      };
      setState(() {
        _customReasonController.clear();
        _requestId = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successText)));
      widget.onDecisionSent?.call();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = FirebaseErrorMessage.describe(
            error,
            fallback: 'Unable to send Testing Service decision.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availabilityStream =
        widget.availabilityStream ??
        (Firebase.apps.isNotEmpty
            ? PaccAvailabilityRepository().watchCurrent()
            : null);
    return StreamBuilder<PaccAvailabilityModel?>(
      stream: availabilityStream,
      builder: (context, availSnap) {
        final availability = availSnap.data;
        final schedule =
            widget.inquiry.testingSchedule ??
            const TestingServiceSchedule(
              status: TestingScheduleStatus.awaitingSchedule,
            );
        final displayAppointment = schedule.toDisplayAppointment(
          inquiryId: widget.inquiry.id,
          userId: widget.inquiry.userId,
          fullName: widget.inquiry.displayName,
          email: widget.inquiry.email,
          concern: widget.inquiry.message,
          createdAt: widget.inquiry.createdAt,
        );
        final docs = widget.inquiry.testingDocuments;
        final preferredAt = widget.inquiry.preferredScheduleAt;
        final preferredWall = preferredAt?.toUtc().add(const Duration(hours: 8));
        final validFuturePreferred = _validFuturePreferredWall(
          widget.inquiry,
          availability,
        );
        final actions = _availableActions(schedule, validFuturePreferred);
        final effectiveAction = actions.contains(_action)
            ? _action
            : (actions.isNotEmpty ? actions.first : _action);
        final reasons = _testingReasons(effectiveAction);
        final selectedReason =
            reasons.contains(_reason) ? _reason : reasons.first;

        final now = widget.nowProvider();
        var displayDate = _selectedDate;
        if (availability != null &&
            !isTestingServiceDateSelectable(
              displayDate,
              availability: availability,
              now: now,
            )) {
          final nextDate = nextSelectableTestingServiceDate(
            startingFrom: displayDate,
            availability: availability,
          );
          if (isTestingServiceDateSelectable(
            nextDate,
            availability: availability,
            now: now,
          )) {
            displayDate = nextDate;
          }
        }
        final slots = testingServiceSlotsForDate(
          displayDate,
          availability: availability,
          now: now,
        ).where((slot) => slot.available).toList(growable: false);
        final selectedHour = slots.any(
          (slot) =>
              slot.instant.toUtc().add(const Duration(hours: 8)).hour ==
              _selectedHour,
        )
            ? _selectedHour
            : (slots.isNotEmpty
                  ? slots.first.instant.toUtc().add(const Duration(hours: 8)).hour
                  : _selectedHour);
        if (slots.isNotEmpty &&
            (selectedHour != _selectedHour || displayDate != _selectedDate)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _selectedDate = displayDate;
              _selectedHour = selectedHour;
            });
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  size: 18,
                  color: AdminColors.muted,
                ),
                SizedBox(width: 8),
                Text(
                  'Testing Service schedule',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AdminColors.canvas,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AdminColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        schedule.status.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: schedule.isCancelled
                              ? AdminColors.redFg
                              : (schedule.isConfirmed || schedule.isCompleted)
                              ? AdminColors.greenFg
                              : AdminColors.ink,
                        ),
                      ),
                      Text(
                        'Reschedules: ${schedule.rescheduleCount}/${schedule.maxReschedules}',
                        style: const TextStyle(
                          color: AdminColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if ((widget.inquiry.contactNumber ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText(
                      'SMS Mobile: ${widget.inquiry.contactNumber}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (preferredWall != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Requested availability: ${_formatManilaDate(preferredWall)} · ${widget.inquiry.preferredScheduleTime ?? _formatSlotHour(preferredWall.hour)} (PHT)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminColors.muted,
                      ),
                    ),
                  ],
                  if (displayAppointment != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${_formatManilaDate(displayAppointment.scheduledAt)} at ${displayAppointment.scheduledTime} (PHT)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Location: ${displayAppointment.location}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminColors.muted,
                      ),
                    ),
                    if ((displayAppointment.counselorName ?? '').isNotEmpty)
                      Text(
                        'Handling counselor: ${displayAppointment.counselorName}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdminColors.muted,
                        ),
                      ),
                  ],
                  if ((schedule.rescheduleReason ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AdminColors.amberBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Applicant reschedule reason: ${schedule.rescheduleReason}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.amberFg,
                        ),
                      ),
                    ),
                  ],
                  if (schedule.isProposed) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AdminColors.blueBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Waiting for the applicant to Accept or Request 1 Reschedule on mobile. You can still Re-schedule or Cancel below.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.blueFg,
                        ),
                      ),
                    ),
                  ],
                  if (schedule.isConfirmed) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AdminColors.greenBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Testing schedule confirmed for applicant. Mark as Completed once the testing session finishes.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.greenFg,
                        ),
                      ),
                    ),
                  ],
                  if (schedule.isCompleted) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: const ValueKey('admin-testing-completed-banner'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AdminColors.greenBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Completed${(schedule.completedByName ?? '').isNotEmpty ? ' by ${schedule.completedByName}' : ''}.',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AdminColors.greenFg,
                            ),
                          ),
                          if ((schedule.completionNote ?? '').isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Notes: ${schedule.completionNote}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AdminColors.greenFg,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (schedule.isCancelled) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: const ValueKey('admin-testing-cancelled-banner'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AdminColors.redBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cancelled${(schedule.cancelledByName ?? '').isNotEmpty ? ' by ${schedule.cancelledByName}' : ''}.',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AdminColors.redFg,
                            ),
                          ),
                          if ((schedule.cancelReason ?? '').isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Reason: ${schedule.cancelReason}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AdminColors.redFg,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!_canDecide &&
                !schedule.isCancelled &&
                !schedule.isCompleted &&
                widget.inquiry.status != InquiryStatus.resolved) ...[
              const SizedBox(height: 10),
              Container(
                key: const ValueKey('admin-testing-readonly-reason'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AdminColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AdminColors.border),
                ),
                child: Text(
                  _readOnlyReason(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.muted,
                  ),
                ),
              ),
            ],
            if (_canDecide && schedule.isConfirmed) ...[
              const SizedBox(height: 16),
              const Text(
                'Session completion',
                key: ValueKey('admin-testing-complete-section'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: const ValueKey('admin-testing-reason-complete'),
                isExpanded: true,
                initialValue: _testingReasons('complete').contains(_reason)
                    ? _reason
                    : _testingReasons('complete').first,
                decoration: const InputDecoration(
                  labelText: 'Completion outcome',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final item in _testingReasons('complete'))
                    DropdownMenuItem(
                      value: item,
                      child: Text(item, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _reason = value;
                            _error = null;
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('admin-testing-custom-reason'),
                controller: _customReasonController,
                enabled: !_saving,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Session notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('admin-testing-mark-complete-btn'),
                    onPressed: _saving
                        ? null
                        : () {
                            _action = 'complete';
                            if (!_testingReasons('complete').contains(_reason)) {
                              _reason = _testingReasons('complete').first;
                            }
                            _sendDecision(availability);
                          },
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.task_alt_outlined),
                    label: Text(_saving ? 'Saving…' : 'Mark as Completed'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('admin-testing-cancel-btn'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.redFg,
                    ),
                    onPressed: _saving ? null : _openCancelDialog,
                    icon: const Icon(Icons.cancel_outlined, size: 17),
                    label: const Text('Cancel Schedule'),
                  ),
                ],
              ),
            ] else if (_canDecide && actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'PACC decision',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('admin-testing-action-dropdown'),
                isExpanded: true,
                initialValue: effectiveAction,
                decoration: const InputDecoration(
                  labelText: 'Action',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final act in actions)
                    DropdownMenuItem(
                      value: act,
                      child: Text(_actionLabel(act)),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _action = value;
                          _reason = _testingReasons(value).first;
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('admin-testing-reason-$effectiveAction'),
                isExpanded: true,
                initialValue: selectedReason,
                decoration: const InputDecoration(
                  labelText: 'Decision reason',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final item in reasons)
                    DropdownMenuItem(
                      value: item,
                      child: Text(item, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _reason = value;
                            _error = null;
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('admin-testing-custom-reason'),
                controller: _customReasonController,
                enabled: !_saving,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: selectedReason == 'Other'
                      ? 'Custom reason (required)'
                      : 'Additional note (optional)',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (effectiveAction == 'accept' &&
                  validFuturePreferred != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AdminColors.greenBg.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Approves & confirms requested slot: ${_formatManilaDate(validFuturePreferred)} at ${_formatSlotHour(validFuturePreferred.hour)} (PHT)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.greenFg,
                    ),
                  ),
                ),
              ],
              if (effectiveAction == 'reschedule') ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('admin-testing-date-picker'),
                      onPressed: _saving ? null : () => _pickDate(availability),
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(_formatManilaDate(displayDate)),
                    ),
                    if (slots.isNotEmpty)
                      DropdownButton<int>(
                        key: const ValueKey('admin-testing-time-dropdown'),
                        value: selectedHour,
                        onChanged: _saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _selectedHour = value);
                                }
                              },
                        items: [
                          for (final slot in slots)
                            DropdownMenuItem<int>(
                              value: slot.instant
                                  .toUtc()
                                  .add(const Duration(hours: 8))
                                  .hour,
                              child: Text('${slot.label} (PHT)'),
                            ),
                        ],
                      )
                    else
                      const Text(
                        'No open PACC time slots on this date.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.redFg,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('admin-testing-location'),
                controller: _locationController,
                enabled: !_saving,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('admin-testing-send-decision'),
                    onPressed: _saving
                        ? null
                        : () {
                            _action = effectiveAction;
                            _sendDecision(availability);
                          },
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            effectiveAction == 'accept'
                                ? Icons.check_circle_outline
                                : Icons.event_available_outlined,
                          ),
                    label: Text(
                      _saving ? 'Sending decision…' : 'Send decision',
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('admin-testing-cancel-btn'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.redFg,
                    ),
                    onPressed: _saving ? null : _openCancelDialog,
                    icon: const Icon(Icons.cancel_outlined, size: 17),
                    label: const Text('Cancel Request'),
                  ),
                ],
              ),
            ],
            if (docs != null && !docs.isEmpty) ...[
              const SizedBox(height: 18),
              TestingServiceDocumentsGallery(
                inquiryId: widget.inquiry.id,
                documents: docs,
                compact: true,
                loadDocument: (path) =>
                    widget.repository.downloadTestingServiceDocument(
                      inquiryId: widget.inquiry.id,
                      path: path,
                    ),
                onDownloadFile: (doc) => testing_download.saveClinicalFileBytes(
                  doc.bytes,
                  doc.name,
                  doc.contentType,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
