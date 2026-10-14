import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/config/app_environment.dart';
import '../database/firestore_collections.dart';
import '../features/quick_assessment/models/quick_assessment_models.dart';
import '../features/student_assessment/models/student_assessment_models.dart';
import '../features/student_assessment/data/student_assessment_questions.dart';
import '../features/student_assessment/data/student_assessment_v4_questions.dart';
import '../services/firebase/firebase_callable_router.dart';
import '../services/firebase/callable_request_timeout.dart';
import '../services/firebase/firestore_service.dart';
import '../services/firebase/firebase_runtime_diagnostics.dart';

typedef StagingQuickAssessmentSubmitter = Future<Map<String, Object>> Function({
  required String userId,
  required QuickAssessmentResult result,
});

typedef QuickAssessmentCompletionChecker = Future<bool> Function(String userId);

class QuickAssessmentSubmissionPendingException implements Exception {
  const QuickAssessmentSubmissionPendingException();
}

class AssessmentRepository {
  AssessmentRepository({
    FirestoreService? firestoreService,
    this.stagingQuickAssessmentSubmitter,
    this.quickAssessmentCompletionChecker,
    this.callableTimeout = const Duration(seconds: 30),
  }) : _firestoreService = firestoreService ?? FirestoreService();

  static const fullAssessmentLimit = 2;
  static const fullAssessmentWindow = Duration(days: 7);
  static const fullAssessmentMinimumInterval = Duration(days: 2);

  final FirestoreService _firestoreService;
  final StagingQuickAssessmentSubmitter? stagingQuickAssessmentSubmitter;
  final QuickAssessmentCompletionChecker? quickAssessmentCompletionChecker;
  final Duration callableTimeout;
  final Set<String> _uncertainQuickSubmissionUserIds = <String>{};

  Future<Map<String, Object>> saveQuickAssessment({
    required String userId,
    required QuickAssessmentResult result,
  }) async {
    if (AppEnvironmentConfig.isStaging) {
      if (_uncertainQuickSubmissionUserIds.contains(userId)) {
        return _reconcileUncertainQuickSubmission(userId);
      }
      try {
        return await _saveQuickAssessmentThroughStagingFunction(
          userId: userId,
          result: result,
        );
      } on CallableRequestTimeoutException catch (error) {
        _uncertainQuickSubmissionUserIds.add(userId);
        return _reconcileTimedOutQuickSubmission(userId, error);
      }
    }

    final documentId = quickAssessmentDocumentId(userId);
    final existing = await _firestoreService.getDocument(
      FirestoreCollections.assessments,
      documentId,
    );
    if (existing != null) {
      await _markQuickAssessmentCompleted(userId);
      return Map<String, Object>.from(existing);
    }

    final payload = <String, Object>{
      'userId': userId,
      'type': 'quick',
      'populationRole': result.role.populationRole.storedValue,
      ...result.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _firestoreService.setDocumentsAtomically([
      FirestoreSetOperation(
        collection: FirestoreCollections.assessments,
        documentId: documentId,
        data: Map<String, dynamic>.from(payload),
      ),
      FirestoreSetOperation(
        collection: FirestoreCollections.users,
        documentId: userId,
        data: {
          'quickAssessmentCompleted': true,
          'quickAssessmentCompletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        merge: true,
      ),
    ]);

    return payload;
  }

  static String quickAssessmentDocumentId(String userId) => 'quick_$userId';

  Future<bool> ensureQuickAssessmentCompletion(String userId) async {
    final checker = quickAssessmentCompletionChecker;
    if (checker != null) return checker(userId);
    final user = await _firestoreService.getDocument(
      FirestoreCollections.users,
      userId,
    );
    if (user?['quickAssessmentCompleted'] == true) return true;

    final deterministic = await _firestoreService.getDocument(
      FirestoreCollections.assessments,
      quickAssessmentDocumentId(userId),
    );
    if (deterministic != null && deterministic['type'] == 'quick') {
      await _markQuickAssessmentCompleted(userId);
      return true;
    }

    final legacy = await _firestoreService.getDocuments(
      FirestoreCollections.assessments,
      whereEquals: {'userId': userId, 'type': 'quick'},
      limit: 1,
    );
    if (legacy.isEmpty) return false;

    await _markQuickAssessmentCompleted(userId);
    return true;
  }

  Future<void> _markQuickAssessmentCompleted(String userId) {
    return _firestoreService.setDocument(FirestoreCollections.users, userId, {
      'quickAssessmentCompleted': true,
      'quickAssessmentCompletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, merge: true);
  }

  Future<Map<String, Object>> saveStudentAssessment({
    required String userId,
    required StudentAssessmentResult result,
    List<StudentAssessmentAnswer> answers = const [],
  }) async {
    if (AppEnvironmentConfig.isStaging) {
      return _saveStudentAssessmentThroughStagingFunction(
        userId: userId,
        result: result,
        answers: answers,
      );
    }

    final populationRole = switch (result.userType.toLowerCase()) {
      'student' => 'student',
      'teaching personnel' || 'teaching' || 'faculty' => 'teaching',
      'non-teaching personnel' || 'non-teaching' || 'staff' => 'nonTeaching',
      _ => '',
    };
    final questionBank = switch (populationRole) {
      'teaching' => StudentAssessmentQuestions.facultyQuestions,
      'nonTeaching' => StudentAssessmentQuestions.staffQuestions,
      _ => StudentAssessmentQuestions.questions,
    };
    final questionById = {
      for (final question in questionBank) question.id: question,
    };
    final responseSnapshots = answers.map((answer) {
      final question = questionById[answer.questionId];
      return <String, Object>{
        ...answer.toJson(),
        if (question != null) 'questionText': question.text,
        if (question != null) 'category': question.section.label,
        if (question != null) 'direction': question.direction.name,
        'answerLabel': answer.answer.label,
      };
    }).toList();
    final payload = <String, Object>{
      'userId': userId,
      'type': result.userType.toLowerCase(),
      'role': result.userType.toLowerCase(),
      'populationRole': populationRole,
      ...result.toJson(),
      'responses': responseSnapshots,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _firestoreService.createDocument(
      FirestoreCollections.assessments,
      Map<String, dynamic>.from(payload),
    );

    return payload;
  }

  /// V4 results are derived only by the callable backend. This is deliberately
  /// staging-gated until the approved pilot is released to production.
  Future<Map<String, Object>> saveStudentV4Assessment({
    required String userId,
    required List<StudentAssessmentAnswer> answers,
    required String submissionId,
  }) async {
    return saveV4FullAssessment(
      userId: userId,
      instrumentVersion: StudentAssessmentV4Questions.instrumentVersion,
      answers: answers,
      submissionId: submissionId,
    );
  }

  /// V4 results are derived only by the callable backend and remain staging-only.
  Future<Map<String, Object>> saveV4FullAssessment({
    required String userId,
    required String instrumentVersion,
    required List<StudentAssessmentAnswer> answers,
    required String submissionId,
  }) async {
    if (!AppEnvironmentConfig.isStaging) {
      throw StateError('V4 full assessments are enabled for staging only.');
    }
    final response = await _stagingFunctions
        .routedCallable('submitFullAssessment')
        .call({
          'submissionId': submissionId,
          'instrumentVersion': instrumentVersion,
          'answers': [for (final answer in answers) answer.toV4Json()],
        });
    FirebaseRuntimeDiagnostics.log(
      event: 'v4_assessment_submitted',
      correlationId: _correlationId(response.data),
    );
    return _objectMap(response.data);
  }

  /// Provides a server-calculated, non-persistent V4 domain result for the
  /// in-progress assessment flow. The UI integration follows in Phase 3.
  Future<Map<String, Object>> previewV4AssessmentDomain({
    required String instrumentVersion,
    required String domainId,
    required List<StudentAssessmentAnswer> answers,
  }) async {
    if (!AppEnvironmentConfig.isStaging) {
      throw StateError('V4 assessment previews are enabled for staging only.');
    }
    final response = await _stagingFunctions
        .routedCallable('previewAssessmentDomain')
        .call({
          'instrumentVersion': instrumentVersion,
          'domainId': domainId,
          'answers': [for (final answer in answers) answer.toV4Json()],
        });
    FirebaseRuntimeDiagnostics.log(
      event: 'v4_assessment_domain_previewed',
      correlationId: _correlationId(response.data),
    );
    return _objectMap(response.data);
  }

  Future<void> saveAssessmentClarityFeedback({
    required String clarity,
    required String algorithmVersion,
    required String questionSetVersion,
  }) async {
    await _firestoreService
        .createDocument(FirestoreCollections.assessmentFeedback, {
          'clarity': clarity,
          'algorithmVersion': algorithmVersion,
          'questionSetVersion': questionSetVersion,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  Future<Map<String, Object>> _saveQuickAssessmentThroughStagingFunction({
    required String userId,
    required QuickAssessmentResult result,
  }) async {
    final submitter = stagingQuickAssessmentSubmitter;
    if (submitter != null) {
      return runBoundedCallable<Map<String, Object>>(
        operation: 'quick_assessment_submission',
        timeout: callableTimeout,
        request: () => submitter(userId: userId, result: result),
      );
    }
    final response = await runBoundedCallable(
      operation: 'quick_assessment_submission',
      timeout: callableTimeout,
      request: () => _stagingFunctions
          .routedCallable(
            'submitQuickAssessment',
            options: HttpsCallableOptions(timeout: callableTimeout),
          )
          .call({
            'submissionId': 'quick_${_safeSubmissionPart(userId)}',
            'role': result.role.populationRole.storedValue,
            'name': result.name,
            'responses': [
              for (final answer in result.responses)
                {
                  'questionId': answer.questionId,
                  'optionId': answer.optionId,
                  'value': answer.value,
                },
            ],
          }),
    );
    FirebaseRuntimeDiagnostics.log(
      event: 'staging_quick_assessment_submitted',
      correlationId: _correlationId(response.data),
    );
    return _objectMap(response.data);
  }

  Future<Map<String, Object>> _reconcileTimedOutQuickSubmission(
    String userId,
    CallableRequestTimeoutException timeoutError,
  ) async {
    try {
      final completed = await runBoundedCallable<bool>(
        operation: 'quick_assessment_completion_reconciliation',
        timeout: callableTimeout,
        request: () => ensureQuickAssessmentCompletion(userId),
      );
      if (completed) {
        _uncertainQuickSubmissionUserIds.remove(userId);
        FirebaseRuntimeDiagnostics.log(
          event: 'quick_assessment_submission_reconciled',
        );
        return <String, Object>{'reconciled': true};
      }
    } on Object {
      // The original timeout remains the actionable error for this attempt.
    }
    throw timeoutError;
  }

  Future<Map<String, Object>> _reconcileUncertainQuickSubmission(
    String userId,
  ) async {
    final completed = await runBoundedCallable<bool>(
      operation: 'quick_assessment_completion_reconciliation',
      timeout: callableTimeout,
      request: () => ensureQuickAssessmentCompletion(userId),
    );
    if (completed) {
      _uncertainQuickSubmissionUserIds.remove(userId);
      FirebaseRuntimeDiagnostics.log(
        event: 'quick_assessment_submission_reconciled',
      );
      return <String, Object>{'reconciled': true};
    }
    throw const QuickAssessmentSubmissionPendingException();
  }

  Future<Map<String, Object>> _saveStudentAssessmentThroughStagingFunction({
    required String userId,
    required StudentAssessmentResult result,
    required List<StudentAssessmentAnswer> answers,
  }) async {
    final response = await _stagingFunctions
        .routedCallable('submitFullAssessment')
        .call({
          'submissionId': _fullSubmissionId(userId, answers),
          'answers': [for (final answer in answers) answer.toJson()],
        });
    FirebaseRuntimeDiagnostics.log(
      event: 'staging_full_assessment_submitted',
      correlationId: _correlationId(response.data),
    );
    return _objectMap(response.data);
  }

  FirebaseFunctions get _stagingFunctions => FirebaseFunctions.instanceFor(
    region: AppEnvironmentConfig.functionsRegion,
  );

  static String _safeSubmissionPart(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return safe.length > 70 ? safe.substring(0, 70) : safe;
  }

  static String _fullSubmissionId(
    String userId,
    List<StudentAssessmentAnswer> answers,
  ) {
    final canonical = [
      userId,
      for (final answer in answers)
        '${answer.questionId}:${answer.answer.name}:${answer.isSkipped}',
    ].join('|');
    var hash = 2166136261;
    for (final codeUnit in canonical.codeUnits) {
      hash = ((hash ^ codeUnit) * 16777619) & 0x7fffffff;
    }
    return 'full_${_safeSubmissionPart(userId)}_${hash.toRadixString(36)}';
  }

  static String? _correlationId(Object? value) {
    if (value is! Map) return null;
    final id = value['correlationId']?.toString().trim() ?? '';
    return id.isEmpty ? null : id;
  }

  static Map<String, Object> _objectMap(Object? value) {
    if (value is! Map) {
      throw StateError('The staging assessment response was not an object.');
    }
    return {
      for (final entry in value.entries)
        if (entry.key != null && entry.value != null)
          entry.key.toString(): entry.value as Object,
    };
  }

  Future<Map<String, dynamic>?> fetchLatestAssessment(String userId) async {
    final docs = await _firestoreService.getDocuments(
      FirestoreCollections.assessments,
      whereEquals: {'userId': userId},
      orderBy: 'createdAt',
      limit: 1,
    );
    if (docs.isEmpty) return null;
    return docs.first;
  }

  Future<int> countAssessmentsSince({
    required String userId,
    required DateTime since,
  }) async {
    final snapshot = await _firestoreService.firestore
        .collection(FirestoreCollections.assessments)
        .where('userId', isEqualTo: userId)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .get();
    return snapshot.docs.length;
  }

  Future<FullAssessmentEligibility> fullAssessmentEligibility(
    String userId, {
    DateTime? now,
  }) async {
    final checkedAt = now ?? DateTime.now();
    final docs = await _firestoreService.getDocuments(
      FirestoreCollections.assessments,
      whereEquals: {'userId': userId},
      orderBy: 'createdAt',
      descending: true,
    );

    final fullAssessmentDates = docs
        .where((doc) => doc['type'] != 'quick')
        .map((doc) => _dateFromValue(doc['createdAt']))
        .whereType<DateTime>()
        .toList();

    return FullAssessmentEligibility.fromCompletedDates(
      completedAt: fullAssessmentDates,
      now: checkedAt,
    );
  }

  DateTime? _dateFromValue(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}

enum FullAssessmentBlockReason { minimumInterval, rollingLimit }

class FullAssessmentEligibility {
  const FullAssessmentEligibility({
    required this.canStart,
    this.nextEligibleAt,
    this.reason,
  });

  factory FullAssessmentEligibility.fromCompletedDates({
    required List<DateTime> completedAt,
    required DateTime now,
  }) {
    final windowStart = now.subtract(AssessmentRepository.fullAssessmentWindow);
    final fullAssessmentDates =
        completedAt.where((date) => date.isAfter(windowStart)).toList()..sort();

    if (fullAssessmentDates.isEmpty) {
      return const FullAssessmentEligibility(canStart: true);
    }

    final latestEligibleAt = fullAssessmentDates.last.add(
      AssessmentRepository.fullAssessmentMinimumInterval,
    );
    DateTime? nextEligibleAt;
    var reason = FullAssessmentBlockReason.minimumInterval;

    if (now.isBefore(latestEligibleAt)) {
      nextEligibleAt = latestEligibleAt;
    }

    if (fullAssessmentDates.length >=
        AssessmentRepository.fullAssessmentLimit) {
      final rollingEligibleAt = fullAssessmentDates.first.add(
        AssessmentRepository.fullAssessmentWindow,
      );
      if (nextEligibleAt == null || rollingEligibleAt.isAfter(nextEligibleAt)) {
        nextEligibleAt = rollingEligibleAt;
        reason = FullAssessmentBlockReason.rollingLimit;
      }
    }

    if (nextEligibleAt == null || !now.isBefore(nextEligibleAt)) {
      return const FullAssessmentEligibility(canStart: true);
    }

    return FullAssessmentEligibility(
      canStart: false,
      nextEligibleAt: nextEligibleAt,
      reason: reason,
    );
  }

  final bool canStart;
  final DateTime? nextEligibleAt;
  final FullAssessmentBlockReason? reason;
}
