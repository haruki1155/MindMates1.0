import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_status_presentation.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/admin_status_badge.dart';
import 'package:mind_mates/models/appointment_model.dart';

AppointmentModel _appointment({
  String id = 'appt-1',
  String status = 'completed',
  bool followUpRecommended = true,
  String followUpStatus = 'offered',
  String? followUpAppointmentId,
}) => AppointmentModel(
  id: id,
  userId: 'student-1',
  fullName: 'Ana Cruz',
  scheduledAt: DateTime(2026, 11, 20, 9),
  scheduledTime: '9:00 AM',
  location: 'PACC',
  status: status,
  concern: 'Academic stress',
  contactNumber: '',
  email: '',
  preferredContactMethod: 'email',
  createdAt: DateTime(2026, 11, 19),
  followUpRecommended: followUpRecommended,
  followUpStatus: followUpStatus,
  followUpAppointmentId: followUpAppointmentId,
);

void main() {
  group('resolveAdminStatus', () {
    test('maps appointment lifecycle statuses to distinct semantic tones', () {
      final pending = resolveAdminStatus(
        AdminStatusDomain.appointment,
        'requested',
      );
      final confirmed = resolveAdminStatus(
        AdminStatusDomain.appointment,
        'confirmed',
      );
      final completed = resolveAdminStatus(
        AdminStatusDomain.appointment,
        'completed',
      );
      final noShow = resolveAdminStatus(
        AdminStatusDomain.appointment,
        'no_show',
      );
      final cancelled = resolveAdminStatus(
        AdminStatusDomain.appointment,
        'cancelled',
      );

      expect(pending.tone, AdminSemanticTone.amber);
      expect(pending.label, 'Pending review');
      expect(confirmed.tone, AdminSemanticTone.blue);
      expect(confirmed.label, 'Confirmed');
      expect(completed.tone, AdminSemanticTone.green);
      expect(completed.label, 'Completed');
      expect(noShow.tone, AdminSemanticTone.red);
      expect(noShow.label, 'No-show');
      expect(cancelled.tone, AdminSemanticTone.neutral);
      expect(cancelled.label, 'Cancelled');
    });

    test('maps inquiry statuses cleanly', () {
      expect(
        resolveAdminStatus(AdminStatusDomain.inquiry, 'pending').tone,
        AdminSemanticTone.amber,
      );
      expect(
        resolveAdminStatus(AdminStatusDomain.inquiry, 'in_progress').tone,
        AdminSemanticTone.blue,
      );
      expect(
        resolveAdminStatus(AdminStatusDomain.inquiry, 'resolved').tone,
        AdminSemanticTone.green,
      );
    });

    test('maps disabled/suspended account status to Inactive', () {
      final disabled = resolveAdminStatus(
        AdminStatusDomain.account,
        'disabled',
      );
      final suspended = resolveAdminStatus(
        AdminStatusDomain.account,
        'suspended',
      );
      expect(disabled.label, 'Inactive');
      expect(disabled.tone, AdminSemanticTone.neutral);
      expect(suspended.label, 'Inactive');
      expect(suspended.tone, AdminSemanticTone.neutral);
    });

    test('maps follow-up appointment type to violet Follow-up badge', () {
      final followUp = resolveAdminStatus(
        AdminStatusDomain.appointmentType,
        'follow_up',
      );
      expect(followUp.tone, AdminSemanticTone.violet);
      expect(followUp.label, 'Follow-up');
      expect(followUp.backgroundColor, AdminColors.violetBg);
    });

    test(
      'maps assessment statuses with neutral fallback for missing/unknown',
      () {
        final supported = resolveAdminStatus(
          AdminStatusDomain.assessment,
          'generally_supported',
        );
        final v4SentenceSupported = resolveAdminStatus(
          AdminStatusDomain.assessment,
          'Well-being appears generally supported.',
        );
        final mostlySupported = resolveAdminStatus(
          AdminStatusDomain.assessment,
          'Mostly supported, with an area to explore.',
        );
        final needsAttention = resolveAdminStatus(
          AdminStatusDomain.assessment,
          'Some areas may benefit from attention.',
        );
        final supportMayHelp = resolveAdminStatus(
          AdminStatusDomain.assessment,
          'Support may be helpful right now.',
        );
        final v3Thriving = resolveAdminStatus(
          AdminStatusDomain.assessment,
          'Thriving',
        );
        final v3NeedsImprovement = resolveAdminStatus(
          AdminStatusDomain.assessment,
          'Needs Improvement',
        );
        final v3AtRisk = resolveAdminStatus(
          AdminStatusDomain.assessment,
          'At Risk',
        );
        final moderate = resolveAdminStatus(
          AdminStatusDomain.assessment,
          'moderate',
        );
        final high = resolveAdminStatus(AdminStatusDomain.assessment, 'high');
        final veryHigh = resolveAdminStatus(
          AdminStatusDomain.assessment,
          'veryHigh',
        );
        final insufficient = resolveAdminStatus(
          AdminStatusDomain.assessment,
          'insufficientResponses',
        );
        final missing = resolveAdminStatus(AdminStatusDomain.assessment, '');
        final unknown = resolveAdminStatus(
          AdminStatusDomain.assessment,
          'custom_legacy_band',
        );

        expect(supported.tone, AdminSemanticTone.green);
        expect(supported.backgroundColor, AdminColors.greenBg);
        expect(v4SentenceSupported.tone, AdminSemanticTone.green);
        expect(v4SentenceSupported.label, 'Supported');
        expect(v4SentenceSupported.icon, Icons.check_circle_outline);

        expect(mostlySupported.tone, AdminSemanticTone.blue);
        expect(mostlySupported.label, 'Mostly supported');
        expect(mostlySupported.backgroundColor, AdminColors.blueBg);
        expect(mostlySupported.icon, Icons.info_outline);

        expect(needsAttention.tone, AdminSemanticTone.amber);
        expect(needsAttention.label, 'Some areas need attention');
        expect(needsAttention.backgroundColor, AdminColors.amberBg);
        expect(needsAttention.icon, Icons.warning_amber_outlined);

        expect(supportMayHelp.tone, AdminSemanticTone.red);
        expect(supportMayHelp.label, 'Support may help');
        expect(supportMayHelp.backgroundColor, AdminColors.redBg);
        expect(supportMayHelp.icon, Icons.priority_high_rounded);

        expect(v3Thriving.tone, AdminSemanticTone.green);
        expect(v3NeedsImprovement.tone, AdminSemanticTone.amber);
        expect(v3AtRisk.tone, AdminSemanticTone.red);

        expect(moderate.tone, AdminSemanticTone.amber);
        expect(high.tone, AdminSemanticTone.red);
        expect(veryHigh.tone, AdminSemanticTone.red);
        expect(veryHigh.label, 'Very high');

        expect(insufficient.tone, AdminSemanticTone.neutral);
        expect(insufficient.label, 'Insufficient responses');
        expect(insufficient.icon, Icons.help_outline);

        expect(missing.tone, AdminSemanticTone.neutral);
        expect(missing.label, 'Result unavailable');
        expect(missing.icon, Icons.help_outline);

        expect(unknown.tone, AdminSemanticTone.neutral);
        expect(unknown.label, 'custom legacy band');
      },
    );
  });

  testWidgets('AdminStatusBadge renders icon, text, and accessible semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AdminTheme.data,
        home: Scaffold(
          body: Row(
            children: [
              AdminStatusBadge.fromStatus(
                domain: AdminStatusDomain.appointmentType,
                status: 'follow_up',
              ),
              const SizedBox(width: 8),
              AdminStatusBadge.fromStatus(
                domain: AdminStatusDomain.appointment,
                status: 'confirmed',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Follow-up'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.byIcon(Icons.event_repeat_outlined), findsOneWidget);
    expect(find.byIcon(Icons.event_available_outlined), findsOneWidget);
  });

  group('AdminStatusDomain.followUp & resolveFollowUpOfferStatus', () {
    test('maps AdminStatusDomain.followUp keys to canonical semantic tones', () {
      final offered = resolveAdminStatus(
        AdminStatusDomain.followUp,
        'offered',
      );
      final booked = resolveAdminStatus(AdminStatusDomain.followUp, 'booked');
      final completed = resolveAdminStatus(
        AdminStatusDomain.followUp,
        'completed',
      );
      final declined = resolveAdminStatus(
        AdminStatusDomain.followUp,
        'declined',
      );
      final cancelled = resolveAdminStatus(
        AdminStatusDomain.followUp,
        'cancelled',
      );
      final expired = resolveAdminStatus(AdminStatusDomain.followUp, 'expired');
      final noShow = resolveAdminStatus(AdminStatusDomain.followUp, 'no_show');

      expect(offered.tone, AdminSemanticTone.amber);
      expect(offered.label, 'Awaiting Client Response');
      expect(offered.icon, Icons.hourglass_top_outlined);
      expect(offered.backgroundColor, AdminColors.amberBg);
      expect(offered.foregroundColor, AdminColors.amberFg);
      expect(offered.borderColor, AdminColors.amberBorder);

      expect(booked.tone, AdminSemanticTone.blue);
      expect(booked.label, 'Booked');
      expect(booked.icon, Icons.event_available_outlined);

      expect(completed.tone, AdminSemanticTone.green);
      expect(completed.label, 'Completed');
      expect(completed.icon, Icons.check_circle_outline);

      expect(declined.tone, AdminSemanticTone.neutral);
      expect(declined.label, 'Declined');

      expect(cancelled.tone, AdminSemanticTone.neutral);
      expect(cancelled.label, 'Cancelled');

      expect(expired.tone, AdminSemanticTone.neutral);
      expect(expired.label, 'Expired');
      expect(expired.icon, Icons.timer_off_outlined);

      expect(noShow.tone, AdminSemanticTone.red);
      expect(noShow.label, 'No-show');
      expect(noShow.icon, Icons.person_off_outlined);
    });

    test(
      'resolveFollowUpOfferStatus highlights pending offered state in amber without green',
      () {
        final offered = resolveFollowUpOfferStatus(_appointment());
        expect(offered.isAwaitingClientResponse, isTrue);
        expect(offered.presentation.tone, AdminSemanticTone.amber);
        expect(offered.presentation.label, 'Awaiting Client Response');
        expect(offered.presentation.backgroundColor, AdminColors.amberBg);
        expect(offered.presentation.foregroundColor, AdminColors.amberFg);
        expect(offered.presentation.borderColor, AdminColors.amberBorder);
        expect(offered.presentation.backgroundColor, isNot(AdminColors.greenBg));
        expect(offered.supportingText, contains('client has not booked'));
      },
    );

    test(
      'resolveFollowUpOfferStatus distinguishes booked and linked child lifecycle states',
      () {
        final standaloneBooked = resolveFollowUpOfferStatus(
          _appointment(followUpStatus: 'booked'),
        );
        expect(standaloneBooked.isAwaitingClientResponse, isFalse);
        expect(standaloneBooked.presentation.tone, AdminSemanticTone.blue);
        expect(standaloneBooked.presentation.label, 'Booked');
        expect(
          standaloneBooked.supportingText,
          'Client booked a follow-up session.',
        );

        final linkedConfirmed = resolveFollowUpOfferStatus(
          _appointment(
            followUpStatus: 'booked',
            followUpAppointmentId: 'child-1',
          ),
          linkedAppointment: _appointment(
            id: 'child-1',
            status: 'confirmed',
            followUpRecommended: false,
            followUpStatus: 'none',
          ),
        );
        expect(linkedConfirmed.isAwaitingClientResponse, isFalse);
        expect(linkedConfirmed.presentation.tone, AdminSemanticTone.blue);
        expect(linkedConfirmed.presentation.label, 'Booked');
        expect(
          linkedConfirmed.supportingText,
          'Follow-up session booked and confirmed.',
        );

        final linkedCompleted = resolveFollowUpOfferStatus(
          _appointment(
            followUpStatus: 'booked',
            followUpAppointmentId: 'child-2',
          ),
          linkedAppointment: _appointment(
            id: 'child-2',
            status: 'completed',
            followUpRecommended: false,
            followUpStatus: 'none',
          ),
        );
        expect(linkedCompleted.isAwaitingClientResponse, isFalse);
        expect(linkedCompleted.presentation.tone, AdminSemanticTone.green);
        expect(linkedCompleted.presentation.label, 'Completed');
        expect(linkedCompleted.supportingText, 'Follow-up session completed.');

        final linkedDeclined = resolveFollowUpOfferStatus(
          _appointment(
            followUpStatus: 'booked',
            followUpAppointmentId: 'child-3',
          ),
          linkedAppointment: _appointment(
            id: 'child-3',
            status: 'declined',
            followUpRecommended: false,
            followUpStatus: 'none',
          ),
        );
        expect(linkedDeclined.presentation.tone, AdminSemanticTone.neutral);
        expect(linkedDeclined.presentation.label, 'Declined');

        final linkedCancelled = resolveFollowUpOfferStatus(
          _appointment(
            followUpStatus: 'booked',
            followUpAppointmentId: 'child-4',
          ),
          linkedAppointment: _appointment(
            id: 'child-4',
            status: 'cancelled',
            followUpRecommended: false,
            followUpStatus: 'none',
          ),
        );
        expect(linkedCancelled.presentation.tone, AdminSemanticTone.neutral);
        expect(linkedCancelled.presentation.label, 'Cancelled');

        final linkedExpired = resolveFollowUpOfferStatus(
          _appointment(
            followUpStatus: 'booked',
            followUpAppointmentId: 'child-5',
          ),
          linkedAppointment: _appointment(
            id: 'child-5',
            status: 'expired',
            followUpRecommended: false,
            followUpStatus: 'none',
          ),
        );
        expect(linkedExpired.presentation.tone, AdminSemanticTone.neutral);
        expect(linkedExpired.presentation.label, 'Expired');

        final linkedNoShow = resolveFollowUpOfferStatus(
          _appointment(
            followUpStatus: 'booked',
            followUpAppointmentId: 'child-6',
          ),
          linkedAppointment: _appointment(
            id: 'child-6',
            status: 'no_show',
            followUpRecommended: false,
            followUpStatus: 'none',
          ),
        );
        expect(linkedNoShow.presentation.tone, AdminSemanticTone.red);
        expect(linkedNoShow.presentation.label, 'No-show');
      },
    );

    test(
      'resolveFollowUpOfferStatus handles direct terminal statuses and non-eligible parents',
      () {
        expect(
          resolveFollowUpOfferStatus(
            _appointment(followUpStatus: 'declined'),
          ).presentation.label,
          'Declined',
        );
        expect(
          resolveFollowUpOfferStatus(
            _appointment(followUpStatus: 'cancelled'),
          ).presentation.label,
          'Cancelled',
        );
        expect(
          resolveFollowUpOfferStatus(
            _appointment(followUpStatus: 'expired'),
          ).presentation.label,
          'Expired',
        );

        final orphanedExpired = resolveFollowUpOfferStatus(
          _appointment(status: 'expired', followUpStatus: 'offered'),
        );
        expect(orphanedExpired.isAwaitingClientResponse, isFalse);
        expect(orphanedExpired.presentation.tone, AdminSemanticTone.neutral);
        expect(orphanedExpired.presentation.label, 'Expired');

        final notRecommended = resolveFollowUpOfferStatus(
          _appointment(followUpRecommended: false, followUpStatus: 'offered'),
        );
        expect(notRecommended.isAwaitingClientResponse, isFalse);
      },
    );
  });
}
