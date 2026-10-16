import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/quick_assessment/models/quick_assessment_models.dart';
import 'package:mind_mates/features/student_assessment/models/student_assessment_models.dart';
import 'package:mind_mates/features/student_assessment/models/intervention_models.dart';
import 'package:mind_mates/features/student_assessment/services/student_assessment_calculator.dart';
import 'package:mind_mates/features/student_assessment/screens/assessment_domain_review_screen.dart';
import 'package:mind_mates/features/student_assessment/widgets/domain_preview_loading_view.dart';
import 'package:mind_mates/features/student_assessment/screens/assessment_submission_review_screen.dart';
import 'package:mind_mates/features/student_assessment/widgets/assessment_presentation.dart';
import 'package:mind_mates/providers/assessment_provider.dart';
import 'package:mind_mates/repositories/assessment_repository.dart';

void main() {
  testWidgets(
    'domain preview loading identifies the current domain without a fabricated result',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DomainPreviewLoadingView(
            domainLabel: 'Financial',
            domainNumber: 2,
            domainCount: 5,
          ),
        ),
      );

      expect(find.text('Reviewing Financial'), findsOneWidget);
      expect(find.text('Domain 2 of 5'), findsOneWidget);
      expect(find.textContaining('reviewing your answers'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('supportMayHelp'), findsNothing);
    },
  );

  test(
    'non-eligible V4 previews advance each role-specific domain without review',
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

        expect(provider.flowStage, AssessmentFlowStage.answering);
        expect(repository.previewRequests, hasLength(1));
        expect(repository.previewRequests.single.answers, hasLength(10));
        expect(
          repository.previewRequests.single.domainId,
          provider.studentQuestions.first.v4DomainId,
        );
        expect(provider.studentQuestionIndex, 10);
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
      expect(provider.flowStage, AssessmentFlowStage.answering);
      expect(provider.studentQuestionIndex, 10);
      expect(provider.studentAnswers, hasLength(10));
      expect(provider.v4SubmissionId, submissionId);
    },
  );

  test('editing a reviewed domain requests a replacement preview', () async {
    final repository = _EligiblePreviewRepository();
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
        expect(provider.flowStage, AssessmentFlowStage.submissionReview);

        // The fifth-domain review must not save until the user explicitly
        // confirms the final submission boundary.
        expect(repository.savedSubmissionIds, isEmpty);
        provider.confirmV4Submission();
        provider.confirmV4Submission();
        expect(provider.flowStage, AssessmentFlowStage.submitting);

        final first = await provider.saveStudentAssessmentForUser('test-user');
        final second = await provider.saveStudentAssessmentForUser('test-user');
        expect(second, first);
        expect(repository.savedSubmissionIds, [session]);
      }
    },
  );

  test(
    'declining or skipping a final intervention never submits by itself',
    () async {
      for (final outcome in [
        InterventionOutcome.skipped,
        InterventionOutcome.selfReportedCompleted,
      ]) {
        final repository = _EligiblePreviewRepository();
        final provider = AssessmentProvider(repository)
          ..startStudentAssessment();
        for (var index = 0; index < 50; index += 1) {
          await provider.answerCurrentStudentQuestion(LikertAnswer.often);
          if (provider.flowStage == AssessmentFlowStage.domainReview) {
            if (index == 49) {
              final attempt = provider.beginInterventionAttempt();
              provider.handleInterventionOutcome(attempt, outcome);
            } else {
              provider.continueAfterDomainReview();
            }
          }
        }
        expect(provider.flowStage, AssessmentFlowStage.submissionReview);
        expect(repository.savedSubmissionIds, isEmpty);
      }
    },
  );

  test(
    'feedback is session-local, optional, and recorded once per attempt',
    () async {
      final provider = AssessmentProvider(_EligiblePreviewRepository())
        ..startStudentAssessment();
      for (var index = 0; index < 10; index += 1) {
        await provider.answerCurrentStudentQuestion(LikertAnswer.often);
      }
      final attempt = provider.beginInterventionAttempt();
      provider.recordInterventionFeedback(
        attempt,
        const InterventionFeedback(choice: InterventionFeedbackChoice.neutral),
      );
      provider.recordInterventionFeedback(
        attempt,
        const InterventionFeedback(choice: InterventionFeedbackChoice.helped),
      );

      expect(
        provider.interventionFeedback[attempt]?.choice,
        InterventionFeedbackChoice.neutral,
      );
      provider.bindAuthenticatedUser(null);
      expect(provider.interventionFeedback, isEmpty);
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
    expect(find.text('Server-calculated category summary.'), findsNothing);
    expect(find.text('Not now, continue assessment'), findsOneWidget);
    expect(find.textContaining('diagnos'), findsNothing);
  });

  testWidgets(
    'domain review presents an eligible server preview in the Assessment card while preserving both choices',
    (tester) async {
      var triedActivity = false;
      var continued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AssessmentDomainReviewScreen(
            preview: const {
              'domainLabel': 'Academic',
              'status': 'supportMayHelp',
              'interventionEligible': true,
            },
            intervention: InterventionType.breathing,
            onTryActivity: () => triedActivity = true,
            onContinue: () => continued = true,
            onRetry: () async {},
            onBack: () {},
          ),
        ),
      );

      expect(find.byType(AssessmentSurfaceCard), findsWidgets);
      expect(find.byType(AssessmentStatusPill), findsOneWidget);
      await tester.tap(find.text('Try Activity'));
      expect(triedActivity, isTrue);
      await tester.tap(find.text('Not now, continue assessment'));
      expect(continued, isTrue);
    },
  );

  testWidgets(
    'submission review keeps the explicit confirmation boundary inside the Assessment presentation',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const AssessmentSubmissionReviewScreen(),
                  ),
                );
              },
              child: const Text('Open review'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open review'));
      await tester.pumpAndSettle();
      expect(find.byType(AssessmentSurfaceCard), findsWidgets);
      expect(find.byType(AssessmentStatusPill), findsOneWidget);
      expect(find.text('Completion summary'), findsOneWidget);
      expect(find.text('About this assessment'), findsOneWidget);
      await tester.ensureVisible(find.text('Submit assessment'));
      await tester.tap(find.text('Submit assessment'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    },
  );
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
  }) async {
    previewRequests.add(_PreviewRequest(instrumentVersion, domainId, answers));
    return {
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
  }

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
