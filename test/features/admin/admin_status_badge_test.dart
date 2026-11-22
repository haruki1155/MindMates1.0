import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_status_presentation.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/admin/widgets/admin_status_badge.dart';

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
}
