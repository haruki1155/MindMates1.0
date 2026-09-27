import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/student_assessment/data/workplace_assessment_v4_questions.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';

void main() {
  group('workplace V4 assessment catalogs', () {
    test('staging routes the three population roles to their V4 catalogs', () {
      final provider = AssessmentProvider(AssessmentRepository());
      provider.selectRole(AssessmentRole.student);
      provider.startStudentAssessment();
      expect(provider.isStudentAssessmentV4, isTrue);
      expect(provider.studentQuestions.first.id, 'student_v4_academic_01');

      provider.selectRole(AssessmentRole.faculty);
      provider.startStudentAssessment();
      expect(provider.isTeachingAssessmentV4, isTrue);
      expect(
        provider.studentQuestions.first.id,
        'teaching_v4_workload_demands_01',
      );

      provider.selectRole(AssessmentRole.staff);
      provider.startStudentAssessment();
      expect(provider.isNonTeachingAssessmentV4, isTrue);
      expect(
        provider.studentQuestions.first.id,
        'non_teaching_v4_workload_demands_01',
      );
    });

    test('Teaching catalog is an immutable 50-item agreement instrument', () {
      final questions = TeachingAssessmentV4Questions.questions;
      expect(
        TeachingAssessmentV4Questions.instrumentVersion,
        'teaching_workplace_reflection_v4',
      );
      expect(questions, hasLength(50));
      expect(questions.map((question) => question.id).toSet(), hasLength(50));
      expect(
        questions.map((question) => question.displayOrder),
        List<int>.generate(50, (index) => index + 1),
      );
      expect(
        questions.map((question) => question.v4DomainId).toSet(),
        hasLength(5),
      );
      expect(
        questions
            .where((question) => question.v4DomainId == 'sleepRest')
            .first
            .text,
        'I was able to fall asleep in a reasonable amount of time.',
      );
    });

    test(
      'Non-Teaching catalog is an immutable 50-item agreement instrument',
      () {
        final questions = NonTeachingAssessmentV4Questions.questions;
        expect(
          NonTeachingAssessmentV4Questions.instrumentVersion,
          'non_teaching_workplace_reflection_v4',
        );
        expect(questions, hasLength(50));
        expect(questions.map((question) => question.id).toSet(), hasLength(50));
        expect(
          questions.map((question) => question.displayOrder),
          List<int>.generate(50, (index) => index + 1),
        );
        expect(
          questions.map((question) => question.v4DomainId).toSet(),
          hasLength(5),
        );
        expect(
          questions
              .where((question) => question.v4DomainId == 'emotionalWellbeing')
              .last
              .text,
          'I felt satisfied with my current emotional well-being.',
        );
      },
    );
  });
}
