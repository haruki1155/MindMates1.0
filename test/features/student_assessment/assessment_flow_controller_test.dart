import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/features/student_assessment/models/student_assessment_models.dart';
import 'package:mind_mates/features/student_assessment/models/intervention_models.dart';
import 'package:mind_mates/features/student_assessment/services/student_assessment_calculator.dart';
import 'package:mind_mates/features/student_assessment/screens/assessment_domain_review_screen.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';

void main() {
  test(
    'V4 pauses at each role-specific domain boundary with its ten answers',
    () async {
      for (final role in [
        AssessmentRole.student,
        AssessmentRole.faculty,
        AssessmentRole.staff,
      ]) {
        final repository = _PreviewRepository();
        final provider = AssessmentProvider(repository)..selectRole(role);
        provider.startStudentAssessment();
        for (var index = 0; index < 10; index += 1) {
          await provider.answerCurrentStudentQuestion(LikertAnswer.often);
        }

        expect(provider.flowStage, AssessmentFlowStage.domainReview);
        expect(repository.previewRequests, hasLength(1));
        expect(repository.previewRequests.single.answers, hasLength(10));
        expect(
          repository.previewRequests.single.domainId,
          provider.studentQuestions.first.v4DomainId,
        );
        expect(provider.studentQuestionIndex, 9);
      }
    },
  );

  test(
    'retry and continue-without-preview preserve answers and session identity',
    () async {
      final repository = _PreviewRepository(failFirstPreview: true);
      final provider = AssessmentProvider(repository)..startStudentAssessment();
      final submissionId = provider.v4SubmissionId;
      for (var index = 0; index < 10; index += 1) {
        await provider.answerCurrentStudentQuestion(LikertAnswer.often);
      }

      expect(provider.flowStage, AssessmentFlowStage.recoverableError);
      await provider.retryDomainPreview();
      expect(provider.flowStage, AssessmentFlowStage.domainReview);
      provider.continueAfterDomainReview();
      expect(provider.studentQuestionIndex, 10);
      expect(provider.studentAnswers, hasLength(10));
      expect(provider.v4SubmissionId, submissionId);
    },
  );

  test('editing a reviewed domain requests a replacement preview', () async {
    final repository = _PreviewRepository();
    final provider = AssessmentProvider(repository)..startStudentAssessment();
    for (var index = 0; index < 10; index += 1) {
      await provider.answerCurrentStudentQuestion(LikertAnswer.often);
    }
    provider.continueAfterDomainReview();
    provider.goBackStudentQuestion();
    await provider.answerCurrentStudentQuestion(LikertAnswer.never);

    expect(repository.previewRequests, hasLength(2));
    expect(provider.flowStage, AssessmentFlowStage.domainReview);
  });

  test(
    'all roles retain 50 answers through interventions and save one stable submission',
    () async {
      for (final role in [
        AssessmentRole.student,
        AssessmentRole.faculty,
        AssessmentRole.staff,
      ]) {
        final repository = _EligiblePreviewRepository();
        final provider = AssessmentProvider(repository)..selectRole(role);
        provider.startStudentAssessment();
        final session = provider.v4SubmissionId;
        for (var index = 0; index < 50; index += 1) {
          await provider.answerCurrentStudentQuestion(LikertAnswer.often);
          if (provider.flowStage == AssessmentFlowStage.domainReview) {
            final attempt = provider.beginInterventionAttempt();
            provider.handleInterventionOutcome(
              attempt,
              index == 29
                  ? InterventionOutcome.skipped
                  : InterventionOutcome.completed,
            );
          }
        }
        expect(provider.studentAnswers, hasLength(50));
        expect(provider.v4SubmissionId, session);
        expect(provider.flowStage, AssessmentFlowStage.submitting);

        await provider.saveStudentAssessmentForUser('test-user');
        expect(repository.savedSubmissionIds, [session]);
      }
    },
  );

  test('auth switch clears the previous account assessment before render', () {
    final provider = AssessmentProvider(_PreviewRepository())
      ..bindAuthenticatedUser('user-a')
      ..selectRole(AssessmentRole.faculty)
      ..startStudentAssessment(userId: 'user-a');
    provider.answerCurrentStudentQuestion(LikertAnswer.often);

    provider.bindAuthenticatedUser(null);
    provider.bindAuthenticatedUser('user-b');
    provider.ensureStudentAssessmentStarted(userId: 'user-b');

    expect(provider.assessmentSessionOwnerId, 'user-b');
    expect(provider.studentQuestionIndex, 0);
    expect(provider.studentAnswers, isEmpty);
    expect(provider.domainPreview, isNull);
    expect(provider.studentResult, isNull);
    expect(provider.activeAssessmentUserType, AssessmentUserType.student);
    expect(provider.currentStudentQuestion?.v4DomainId, 'academic');
  });

  test(
    'a different authenticated user cannot save a previous V4 session',
    () async {
      final repository = _EligiblePreviewRepository();
      final provider = AssessmentProvider(repository)
        ..bindAuthenticatedUser('user-a')
        ..startStudentAssessment(userId: 'user-a');

      provider.bindAuthenticatedUser('user-b');
      final saved = await provider.saveStudentAssessmentForUser('user-b');

      expect(saved, isNull);
      expect(repository.savedSubmissionIds, isEmpty);
    },
  );

  test(
    'a proxy-bound signed-out provider cannot start or save a session',
    () async {
      final repository = _EligiblePreviewRepository();
      final provider = AssessmentProvider(repository)
        ..bindAuthenticatedUser(null);

      provider.ensureStudentAssessmentStarted();
      final saved = await provider.saveStudentAssessmentForUser('user-a');

      expect(provider.studentQuestions, isEmpty);
      expect(saved, isNull);
      expect(repository.savedSubmissionIds, isEmpty);
    },
  );

  test('a delayed preview from a logged-out account is discarded', () async {
    final repository = _DelayedPreviewRepository();
    final provider = AssessmentProvider(repository)
      ..bindAuthenticatedUser('user-a')
      ..startStudentAssessment(userId: 'user-a');
    for (var index = 0; index < 9; index += 1) {
      await provider.answerCurrentStudentQuestion(LikertAnswer.often);
    }
    final lastAnswer = provider.answerCurrentStudentQuestion(
      LikertAnswer.often,
    );
    await repository.requested.future;

    provider.bindAuthenticatedUser(null);
    repository.complete();
    await lastAnswer;

    expect(provider.domainPreview, isNull);
    expect(provider.pendingDomainId, isNull);
    expect(provider.studentAnswers, isEmpty);
    expect(provider.flowStage, AssessmentFlowStage.answering);
  });

  testWidgets('domain review renders only the authoritative preview response', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssessmentDomainReviewScreen(
          preview: const {
            'domainLabel': 'Academic',
            'status': 'supportMayHelp',
            'summary': 'Server-calculated category summary.',
            'focusInsight': 'Server focus.',
            'suggestedAction': 'Server action.',
            'reflectionPrompt': 'Server prompt.',
            'interventionEligible': true,
          },
          onContinue: () {},
          onRetry: () async {},
          onBack: () {},
        ),
      ),
    );

    expect(find.text('Academic'), findsOneWidget);
    expect(find.text('Server-calculated category summary.'), findsOneWidget);
    expect(find.text('Continue Assessment'), findsOneWidget);
    expect(find.textContaining('diagnos'), findsNothing);
  });
}

class _PreviewRequest {
  const _PreviewRequest(this.instrumentVersion, this.domainId, this.answers);
  final String instrumentVersion;
  final String domainId;
  final List<StudentAssessmentAnswer> answers;
}

class _PreviewRepository extends AssessmentRepository {
  _PreviewRepository({this.failFirstPreview = false});
  final bool failFirstPreview;
  final List<_PreviewRequest> previewRequests = [];

  @override
  Future<Map<String, Object>> previewV4AssessmentDomain({
    required String instrumentVersion,
    required String domainId,
    required List<StudentAssessmentAnswer> answers,
  }) async {
    previewRequests.add(_PreviewRequest(instrumentVersion, domainId, answers));
    if (failFirstPreview && previewRequests.length == 1) {
      throw StateError('offline');
    }
    return {
      'domainId': domainId,
      'domainLabel': 'Verified domain',
      'status': 'mostlySupported',
      'isScorable': true,
      'answeredCount': 10,
      'presentedCount': 10,
      'summary': 'Server result.',
      'suggestedAction': 'Continue.',
      'reflectionPrompt': 'Reflect.',
      'interventionEligible': false,
      'policyVersion': 'assessment_intervention_v1',
    };
  }
}

class _EligiblePreviewRepository extends _PreviewRepository {
  final List<String> savedSubmissionIds = [];

  @override
  Future<Map<String, Object>> previewV4AssessmentDomain({
    required String instrumentVersion,
    required String domainId,
    required List<StudentAssessmentAnswer> answers,
  }) async => {
    'domainId': domainId,
    'domainLabel': domainId,
    'status': 'supportMayHelp',
    'isScorable': true,
    'answeredCount': 10,
    'presentedCount': 10,
    'summary': 'Server result.',
    'suggestedAction': 'Continue.',
    'reflectionPrompt': 'Reflect.',
    'interventionEligible': true,
    'policyVersion': 'assessment_intervention_v1',
  };

  @override
  Future<Map<String, Object>> saveV4FullAssessment({
    required String userId,
    required String instrumentVersion,
    required List<StudentAssessmentAnswer> answers,
    required String submissionId,
  }) async {
    savedSubmissionIds.add(submissionId);
    return {'submissionId': submissionId};
  }
}

class _DelayedPreviewRepository extends AssessmentRepository {
  final requested = Completer<void>();
  final response = Completer<Map<String, Object>>();

  @override
  Future<Map<String, Object>> previewV4AssessmentDomain({
    required String instrumentVersion,
    required String domainId,
    required List<StudentAssessmentAnswer> answers,
  }) {
    requested.complete();
    return response.future;
  }

  void complete() => response.complete({
    'domainId': 'academic',
    'domainLabel': 'Academic',
    'status': 'mostlySupported',
    'isScorable': true,
    'answeredCount': 10,
    'presentedCount': 10,
    'summary': 'Server result.',
    'suggestedAction': 'Continue.',
    'reflectionPrompt': 'Reflect.',
    'interventionEligible': false,
  });
}
