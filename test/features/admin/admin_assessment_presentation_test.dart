import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/domain/admin_assessment_presentation.dart';
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
}
