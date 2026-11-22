import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_assessment_presentation.dart';
import 'package:mind_mates/features/admin/domain/admin_status_presentation.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

AdminAssessmentRecord record(
  String id,
  String userId, {
  String type = 'quick',
}) => AdminAssessmentRecord(
  id: id,
  userId: userId,
  type: type,
  createdAt: DateTime(2026, 11, 14),
  status: 'moderate',
);

void main() {
  test('quick and full subtabs do not mix submissions', () {
    expect(
      matchesAssessmentView(record('quick_a', 'a'), AssessmentView.quick),
      isTrue,
    );
    expect(
      matchesAssessmentView(
        record('full_a', 'a', type: 'full'),
        AssessmentView.quick,
      ),
      isFalse,
    );
    expect(
      matchesAssessmentView(
        record('full_a', 'a', type: 'full'),
        AssessmentView.full,
      ),
      isTrue,
    );
  });

  test('status colors are meaningfully different and unknowns are safe', () {
    final supported = AssessmentStatusStyle.fromStored('supported');
    final attention = AssessmentStatusStyle.fromStored('someStrain');
    final help = AssessmentStatusStyle.fromStored('supportMayHelp');
    expect(supported.background, isNot(attention.background));
    expect(attention.background, isNot(help.background));
    expect(
      AssessmentStatusStyle.fromStored('unknown_custom').label,
      isNotEmpty,
    );
    expect(AssessmentStatusStyle.fromStored(null).label, 'Result unavailable');
  });

  test('name resolution does not expose a UID as a fallback', () {
    final value = AssessmentParticipantInfo.fromJson({
      'userId': 'sensitive-uid',
      'name': '',
      'role': 'student',
      'college': '',
    });
    expect(value.name, 'Name unavailable');
    expect(value.college, 'Unassigned');
  });

  test('chart counts unique people, not assessment submissions', () {
    final directory = <String, AssessmentParticipantInfo>{
      'student1': const AssessmentParticipantInfo(
        userId: 'student1',
        name: 'Ana',
        role: 'student',
        college: 'CITE',
      ),
      'student2': const AssessmentParticipantInfo(
        userId: 'student2',
        name: 'Ben',
        role: 'student',
        college: 'CITE',
      ),
      'faculty': const AssessmentParticipantInfo(
        userId: 'faculty',
        name: 'Ria',
        role: 'teaching',
        college: 'CITE',
      ),
      'employee': const AssessmentParticipantInfo(
        userId: 'employee',
        name: 'Pat',
        role: 'nonTeaching',
        college: 'Unassigned',
      ),
    };
    final summary = AssessmentParticipantCounts.fromRecords([
      record('quick_student1', 'student1'),
      record('full_student1', 'student1', type: 'full'),
      record('quick_student2', 'student2'),
      record('quick_faculty', 'faculty'),
      record('quick_employee', 'employee'),
    ], directory);
    expect(summary.studentsByCollege['CITE'], 2);
    expect(summary.personnelByRole['Teaching'], 1);
    expect(summary.personnelByRole['Non-Teaching'], 1);
  });

  group('AdminAssessmentRecord.fromJson', () {
    test(
      'prefers result.profileStatus over top-level V4 sentence and preserves fallback',
      () {
        for (final version in const [
          'student_wellbeing_v4',
          'teaching_workplace_reflection_v4',
          'non_teaching_workplace_reflection_v4',
        ]) {
          final parsed = AdminAssessmentRecord.fromJson({
            'id': 'full-$version',
            'userId': 'u-1',
            'assessmentKind': 'full',
            'createdAt': '2026-11-15T00:00:00.000Z',
            'status': 'Well-being appears generally supported.',
            'populationRole': 'student',
            'instrument': {'version': version},
            'result': {'profileStatus': 'generallySupported'},
          });

          expect(parsed.isMainAssessment, isTrue);
          expect(parsed.profileStatus, 'generallySupported');
          expect(parsed.status, 'generallySupported');
          expect(parsed.displayStatus, 'generallySupported');
          expect(parsed.instrumentVersion, version);
        }

        final sentenceOnly = AdminAssessmentRecord.fromJson({
          'id': 'full-sentence',
          'userId': 'u-2',
          'assessmentKind': 'full',
          'createdAt': '2026-11-15T00:00:00.000Z',
          'status': 'Some areas may benefit from attention.',
        });
        expect(sentenceOnly.profileStatus, isNull);
        expect(sentenceOnly.displayStatus, 'Some areas may benefit from attention.');

        final profileOnly = AdminAssessmentRecord.fromJson({
          'id': 'full-profile-only',
          'userId': 'u-3',
          'assessmentKind': 'full',
          'createdAt': '2026-11-15T00:00:00.000Z',
          'result': {'profileStatus': 'mostlySupported'},
        });
        expect(profileOnly.profileStatus, 'mostlySupported');
        expect(profileOnly.displayStatus, 'mostlySupported');
      },
    );

    test('parses V3 legacy, Quick, and missing statuses cleanly', () {
      final v3 = AdminAssessmentRecord.fromJson({
        'id': 'v3-1',
        'userId': 'u-1',
        'type': 'full',
        'createdAt': '2026-11-10T00:00:00.000Z',
        'status': 'Needs Improvement',
      });
      expect(v3.displayStatus, 'Needs Improvement');

      final quick = AdminAssessmentRecord.fromJson({
        'id': 'quick_u1',
        'userId': 'u-1',
        'type': 'quick',
        'createdAt': '2026-11-10T00:00:00.000Z',
        'overallLevel': 'veryHigh',
      });
      expect(quick.isQuickAssessment, isTrue);
      expect(quick.displayStatus, 'veryHigh');

      final missing = AdminAssessmentRecord.fromJson({
        'id': 'full-missing',
        'userId': 'u-1',
        'type': 'full',
        'createdAt': '2026-11-10T00:00:00.000Z',
        'status': '   ',
      });
      expect(missing.status, isNull);
      expect(missing.profileStatus, isNull);
      expect(missing.displayStatus, 'Result unavailable');
    });

    test(
      'empty or whitespace higher-precedence fields do not mask valid fallbacks',
      () {
        final emptyOverallLevel = AdminAssessmentRecord.fromJson({
          'id': 'full-empty-overall',
          'userId': 'u-1',
          'assessmentKind': 'full',
          'createdAt': '2026-11-15T00:00:00.000Z',
          'overallLevel': '',
          'status': 'Well-being appears generally supported.',
          'populationRole': '',
          'role': 'student',
          'instrument': {'version': '  '},
          'questionSetVersion': 'student_wellbeing_v4',
        });
        expect(
          emptyOverallLevel.status,
          'Well-being appears generally supported.',
        );
        expect(
          emptyOverallLevel.displayStatus,
          'Well-being appears generally supported.',
        );
        expect(emptyOverallLevel.role, 'student');
        expect(emptyOverallLevel.instrumentVersion, 'student_wellbeing_v4');

        final whitespaceStatus = AdminAssessmentRecord.fromJson({
          'id': 'v3-whitespace-status',
          'userId': 'u-2',
          'assessmentKind': '',
          'type': 'quick',
          'createdAt': '2026-11-15T00:00:00.000Z',
          'overallLevel': '  ',
          'status': '   ',
          'wellBeingStatus': 'At Risk',
          'populationRole': '   ',
          'role': 'teaching',
          'instrument': {'version': ''},
          'questionSetVersion': 'quick_v2',
        });
        expect(whitespaceStatus.type, 'quick');
        expect(whitespaceStatus.isQuickAssessment, isTrue);
        expect(whitespaceStatus.status, 'At Risk');
        expect(whitespaceStatus.displayStatus, 'At Risk');
        expect(whitespaceStatus.role, 'teaching');
        expect(whitespaceStatus.instrumentVersion, 'quick_v2');

        final patternFallback = AdminAssessmentRecord.fromJson({
          'id': 'v3-pattern-fallback',
          'userId': 'u-3',
          'assessmentKind': 'full',
          'createdAt': '2026-11-15T00:00:00.000Z',
          'overallLevel': '',
          'status': '',
          'wellBeingStatus': '   ',
          'responsePatternCode': 'someStrain',
        });
        expect(patternFallback.status, 'someStrain');
        expect(patternFallback.displayStatus, 'someStrain');
      },
    );

    test('never recalculates status from score or answers on the client', () {
      final highScoreSupported = AdminAssessmentRecord.fromJson({
        'id': 'no-recalc-1',
        'userId': 'u-1',
        'assessmentKind': 'full',
        'createdAt': '2026-11-15T00:00:00.000Z',
        'score': 98,
        'status': 'Support may be helpful right now.',
        'result': {'profileStatus': 'generallySupported'},
      });
      final supportedStyle = AssessmentStatusStyle.fromStored(
        highScoreSupported.displayStatus,
      );
      expect(supportedStyle.label, 'Supported');
      expect(supportedStyle.background, AdminColors.greenBg);

      final lowScoreSupportMayHelp = AdminAssessmentRecord.fromJson({
        'id': 'no-recalc-2',
        'userId': 'u-2',
        'assessmentKind': 'full',
        'createdAt': '2026-11-15T00:00:00.000Z',
        'score': 3,
        'status': 'Support may be helpful right now.',
      });
      final helpStyle = AssessmentStatusStyle.fromStored(
        lowScoreSupportMayHelp.displayStatus,
      );
      expect(helpStyle.label, 'Support may help');
      expect(helpStyle.background, AdminColors.redBg);
    });
  });

  test(
    'AssessmentStatusStyle.fromStored and resolveAdminStatus agree on all V4, V3, Quick, domain, and unavailable statuses',
    () {
      final cases = <String?, (AdminSemanticTone, String, IconData)>{
        'generallySupported': (
          AdminSemanticTone.green,
          'Supported',
          Icons.check_circle_outline,
        ),
        'Well-being appears generally supported.': (
          AdminSemanticTone.green,
          'Supported',
          Icons.check_circle_outline,
        ),
        'supported': (
          AdminSemanticTone.green,
          'Supported',
          Icons.check_circle_outline,
        ),
        'Supported at present': (
          AdminSemanticTone.green,
          'Supported',
          Icons.check_circle_outline,
        ),
        'Thriving': (
          AdminSemanticTone.green,
          'Supported',
          Icons.check_circle_outline,
        ),
        'Stable': (
          AdminSemanticTone.green,
          'Supported',
          Icons.check_circle_outline,
        ),
        'mostlySupported': (
          AdminSemanticTone.blue,
          'Mostly supported',
          Icons.info_outline,
        ),
        'Mostly supported, with an area to explore.': (
          AdminSemanticTone.blue,
          'Mostly supported',
          Icons.info_outline,
        ),
        'Mostly supported; some areas to explore': (
          AdminSemanticTone.blue,
          'Mostly supported',
          Icons.info_outline,
        ),
        'someAreasNeedAttention': (
          AdminSemanticTone.amber,
          'Some areas need attention',
          Icons.warning_amber_outlined,
        ),
        'Some areas may benefit from attention.': (
          AdminSemanticTone.amber,
          'Some areas need attention',
          Icons.warning_amber_outlined,
        ),
        'someStrain': (
          AdminSemanticTone.amber,
          'Some areas need attention',
          Icons.warning_amber_outlined,
        ),
        'Some strain indicated': (
          AdminSemanticTone.amber,
          'Some areas need attention',
          Icons.warning_amber_outlined,
        ),
        'Needs Improvement': (
          AdminSemanticTone.amber,
          'Some areas need attention',
          Icons.warning_amber_outlined,
        ),
        'supportMayHelp': (
          AdminSemanticTone.red,
          'Support may help',
          Icons.priority_high_rounded,
        ),
        'Support may be helpful right now.': (
          AdminSemanticTone.red,
          'Support may help',
          Icons.priority_high_rounded,
        ),
        'Support may be helpful': (
          AdminSemanticTone.red,
          'Support may help',
          Icons.priority_high_rounded,
        ),
        'At Risk': (
          AdminSemanticTone.red,
          'Support may help',
          Icons.priority_high_rounded,
        ),
        'insufficientResponses': (
          AdminSemanticTone.neutral,
          'Insufficient responses',
          Icons.help_outline,
        ),
        'More responses are needed for a complete profile.': (
          AdminSemanticTone.neutral,
          'Insufficient responses',
          Icons.help_outline,
        ),
        'Insufficient Responses': (
          AdminSemanticTone.neutral,
          'Insufficient responses',
          Icons.help_outline,
        ),
        'low': (
          AdminSemanticTone.green,
          'Low',
          Icons.check_circle_outline,
        ),
        'moderate': (
          AdminSemanticTone.amber,
          'Moderate',
          Icons.warning_amber_outlined,
        ),
        'high': (
          AdminSemanticTone.red,
          'High',
          Icons.priority_high_rounded,
        ),
        'veryHigh': (
          AdminSemanticTone.red,
          'Very high',
          Icons.priority_high_rounded,
        ),
        null: (
          AdminSemanticTone.neutral,
          'Result unavailable',
          Icons.help_outline,
        ),
        '': (
          AdminSemanticTone.neutral,
          'Result unavailable',
          Icons.help_outline,
        ),
        'unexpected_custom_band': (
          AdminSemanticTone.neutral,
          'unexpected custom band',
          Icons.help_outline,
        ),
      };

      for (final entry in cases.entries) {
        final raw = entry.key;
        final (expectedTone, expectedLabel, expectedIcon) = entry.value;
        final presentation = resolveAdminStatus(
          AdminStatusDomain.assessment,
          raw,
        );
        final style = AssessmentStatusStyle.fromStored(raw);

        expect(presentation.tone, expectedTone, reason: 'tone for "$raw"');
        expect(presentation.label, expectedLabel, reason: 'label for "$raw"');
        expect(presentation.icon, expectedIcon, reason: 'icon for "$raw"');
        expect(style.label, presentation.label, reason: 'style label for "$raw"');
        expect(
          style.foreground,
          presentation.foregroundColor,
          reason: 'fg for "$raw"',
        );
        expect(
          style.background,
          presentation.backgroundColor,
          reason: 'bg for "$raw"',
        );
      }
    },
  );
}
