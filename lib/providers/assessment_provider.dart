import 'package:flutter/foundation.dart';

import '../core/config/app_environment.dart';
import '../features/quick_assessment/data/quick_assessment_questions.dart';
import '../features/quick_assessment/models/quick_assessment_models.dart';
import '../features/quick_assessment/services/quick_assessment_scoring.dart';
import '../features/student_assessment/data/student_assessment_questions.dart';
import '../features/student_assessment/data/student_assessment_v4_questions.dart';
import '../features/student_assessment/data/workplace_assessment_v4_questions.dart';
import '../features/student_assessment/models/student_assessment_models.dart';
import '../features/student_assessment/services/student_assessment_calculator.dart';
import '../repositories/assessment_repository.dart';

enum AssessmentFlowStage {
  answering,
  previewLoading,
  domainReview,
  resuming,
  submitting,
  recoverableError,
}

class AssessmentProvider extends ChangeNotifier {
  AssessmentProvider(this._repository);

  final AssessmentRepository _repository;

  AssessmentRole? _selectedRole;
  String _name = '';
  int _currentQuestionIndex = 0;
  final Map<String, QuickAssessmentOption> _selectedOptions = {};
  QuickAssessmentResult? _quickResult;
  int _studentQuestionIndex = 0;
  List<StudentAssessmentQuestion> _studentQuestions = const [];
  final List<StudentAssessmentAnswer> _studentAnswers = [];
  StudentAssessmentResult? _studentResult;
  String? _v4SubmissionId;
  bool _isSavingQuickAssessment = false;
  AssessmentFlowStage _flowStage = AssessmentFlowStage.answering;
  Map<String, Object>? _domainPreview;
  Object? _domainPreviewError;
  String? _pendingDomainId;
  int _previewGeneration = 0;
  bool _isRecordingStudentAnswer = false;
  bool _isSavingStudentAssessment = false;

  AssessmentRole? get selectedRole => _selectedRole;
  String get name => _name;
  int get currentQuestionIndex => _currentQuestionIndex;
  QuickAssessmentResult? get quickResult => _quickResult;
  int get studentQuestionIndex => _studentQuestionIndex;
  List<StudentAssessmentQuestion> get studentQuestions => _studentQuestions;
  List<StudentAssessmentAnswer> get studentAnswers =>
      List.unmodifiable(_studentAnswers);
  StudentAssessmentResult? get studentResult => _studentResult;
  bool get isSavingQuickAssessment => _isSavingQuickAssessment;
  AssessmentFlowStage get flowStage => _flowStage;
  Map<String, Object>? get domainPreview => _domainPreview;
  Object? get domainPreviewError => _domainPreviewError;
  String? get pendingDomainId => _pendingDomainId;
  String? get v4SubmissionId => _v4SubmissionId;
  bool get isSavingStudentAssessment => _isSavingStudentAssessment;
  bool get isStudentAssessmentV4 =>
      AppEnvironmentConfig.isStaging &&
      activeAssessmentUserType == AssessmentUserType.student;
  bool get isTeachingAssessmentV4 =>
      AppEnvironmentConfig.isStaging &&
      activeAssessmentUserType == AssessmentUserType.faculty;
  bool get isNonTeachingAssessmentV4 =>
      AppEnvironmentConfig.isStaging &&
      activeAssessmentUserType == AssessmentUserType.staff;
  bool get isV4FullAssessment =>
      isStudentAssessmentV4 ||
      isTeachingAssessmentV4 ||
      isNonTeachingAssessmentV4;

  List<QuickAssessmentQuestion> get questions =>
      QuickAssessmentQuestions.questions;

  QuickAssessmentQuestion get currentQuestion =>
      questions[_currentQuestionIndex];

  int get currentQuestionStep => _currentQuestionIndex + 1;
  String get nameProgressLabel =>
      QuickAssessmentScoring.progressLabelForStep(1, total: questions.length);
  String get questionProgressLabel =>
      QuickAssessmentScoring.progressLabelForStep(
        currentQuestionStep,
        total: questions.length,
      );

  bool get isNameValid => _name.trim().isNotEmpty;
  bool get hasSelectedRole => _selectedRole != null;
  bool get hasSelectedAnswer =>
      _selectedOptions.containsKey(currentQuestion.id);
  bool get isLastQuestion => _currentQuestionIndex == questions.length - 1;
  bool get hasStudentAssessmentStarted => _studentQuestions.isNotEmpty;
  bool get isLastStudentQuestion =>
      _studentQuestionIndex == _studentQuestions.length - 1;
  bool get canGoBackStudentQuestion => _studentQuestionIndex > 0;
  AssessmentUserType get activeAssessmentUserType {
    switch (_selectedRole) {
      case AssessmentRole.faculty:
        return AssessmentUserType.faculty;
      case AssessmentRole.staff:
        return AssessmentUserType.staff;
      case AssessmentRole.student:
      case null:
        return AssessmentUserType.student;
    }
  }

  String get activeAssessmentTitle {
    switch (activeAssessmentUserType) {
      case AssessmentUserType.student:
        return isStudentAssessmentV4
            ? 'Student Well-Being Reflection'
            : 'Student Assessment';
      case AssessmentUserType.faculty:
        return isTeachingAssessmentV4
            ? 'Teaching Work Well-Being Reflection'
            : 'Teaching Assessment';
      case AssessmentUserType.staff:
        return isNonTeachingAssessmentV4
            ? 'Work Well-Being Reflection'
            : 'Non-Teaching Assessment';
    }
  }

  double get studentProgress {
    if (_studentQuestions.isEmpty) return 0;
    return (_studentQuestionIndex + 1) / _studentQuestions.length;
  }

  StudentAssessmentQuestion? get currentStudentQuestion {
    if (_studentQuestions.isEmpty) return null;
    return _studentQuestions[_studentQuestionIndex];
  }

  LikertAnswer? get currentStudentAnswer {
    final question = currentStudentQuestion;
    if (question == null) return null;
    return _studentAnswers
        .where(
          (answer) => answer.questionId == question.id && !answer.isSkipped,
        )
        .firstOrNull
        ?.answer;
  }

  QuickAssessmentOption? selectedOptionFor(String questionId) {
    return _selectedOptions[questionId];
  }

  void selectRole(AssessmentRole role) {
    _selectedRole = role;
    _quickResult = null;
    notifyListeners();
  }

  void updateName(String value) {
    _name = value;
    _quickResult = null;
    notifyListeners();
  }

  void selectAnswer(QuickAssessmentOption option) {
    _selectedOptions[currentQuestion.id] = option;
    _quickResult = null;
    notifyListeners();
  }

  bool moveToNextQuestion() {
    if (!hasSelectedAnswer) return false;

    if (!isLastQuestion) {
      _currentQuestionIndex += 1;
      notifyListeners();
      return true;
    }

    _quickResult = calculateResult();
    notifyListeners();
    return true;
  }

  void resetQuestions() {
    _currentQuestionIndex = 0;
    _selectedOptions.clear();
    _quickResult = null;
    notifyListeners();
  }

  QuickAssessmentResult calculateResult({DateTime? createdAt}) {
    final role = _selectedRole;
    if (role == null) {
      throw StateError('A role is required before calculating the result.');
    }

    if (!isNameValid) {
      throw StateError('A name is required before calculating the result.');
    }

    final responses = <QuickAssessmentResponse>[];

    for (final question in questions) {
      final option = _selectedOptions[question.id];
      if (option == null) {
        throw StateError('Every quick assessment question must be answered.');
      }

      responses.add(
        QuickAssessmentResponse(
          questionId: question.id,
          optionId: option.id,
          value: option.value,
          concernScore: QuickAssessmentScoring.concernScore(
            direction: question.direction,
            value: option.value,
            minValue: question.options
                .map((item) => item.value)
                .reduce((a, b) => a < b ? a : b),
            maxValue: question.options
                .map((item) => item.value)
                .reduce((a, b) => a > b ? a : b),
          ),
        ),
      );
    }

    final concernScore = QuickAssessmentScoring.averageConcernScore(responses);
    final overallLevel = QuickAssessmentScoring.overallLevel(concernScore);
    final signalGeneratedAt = createdAt ?? DateTime.now();

    return QuickAssessmentResult(
      role: role,
      name: _name.trim(),
      responses: responses,
      concernScore: concernScore,
      overallLevel: overallLevel,
      summary: QuickAssessmentScoring.summaryForScore(concernScore),
      topConcernAreas: QuickAssessmentScoring.topConcernAreas(responses),
      recommendedNextStep: QuickAssessmentScoring.recommendedNextStepForLevel(
        overallLevel,
      ),
      mentalStatusSignal: QuickAssessmentScoring.signalForLevel(overallLevel),
      signalSource: 'quickAssessment',
      signalGeneratedAt: signalGeneratedAt,
      createdAt: signalGeneratedAt,
      interpretation: QuickAssessmentScoring.interpretationFor(responses),
    );
  }

  Future<Map<String, Object>?> saveQuickAssessmentForUser(String userId) async {
    final result = _quickResult;
    if (result == null || _isSavingQuickAssessment) return null;

    _isSavingQuickAssessment = true;
    notifyListeners();
    try {
      return await _repository.saveQuickAssessment(
        userId: userId,
        result: result,
      );
    } finally {
      _isSavingQuickAssessment = false;
      notifyListeners();
    }
  }

  Future<bool> ensureQuickAssessmentCompletion(String userId) {
    return _repository.ensureQuickAssessmentCompletion(userId);
  }

  void startStudentAssessment() {
    _studentQuestionIndex = 0;
    _studentAnswers.clear();
    _studentResult = null;
    _v4SubmissionId = isV4FullAssessment
        ? 'v4_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        : null;
    _studentQuestions = _questionsForActiveRole()
        .where((question) => !question.isConditional)
        .toList();
    _flowStage = AssessmentFlowStage.answering;
    _domainPreview = null;
    _domainPreviewError = null;
    _pendingDomainId = null;
    _previewGeneration += 1;
    notifyListeners();
  }

  /// Used by the assessment screen after reconstruction. Starting a new
  /// assessment remains explicit through [startStudentAssessment].
  void ensureStudentAssessmentStarted() {
    if (hasStudentAssessmentStarted) return;
    startStudentAssessment();
  }

  Future<void> answerCurrentStudentQuestion(
    LikertAnswer answer, {
    bool isSkipped = false,
  }) async {
    if (_isRecordingStudentAnswer || _flowStage != AssessmentFlowStage.answering) {
      return;
    }
    final question = currentStudentQuestion;
    if (question == null) return;
    _isRecordingStudentAnswer = true;

    try {
      _studentAnswers.removeWhere(
        (existing) => existing.questionId == question.id,
      );
      _studentAnswers.add(
        StudentAssessmentAnswer(
          questionId: question.id,
          answer: answer,
          isSkipped: isSkipped,
        ),
      );
      _invalidatePreviewFor(question.v4DomainId);

      if (isV4FullAssessment && question.v4DomainId != null && _isDomainComplete(question.v4DomainId!)) {
        _pendingDomainId = question.v4DomainId;
        await _requestPendingDomainPreview();
        return;
      }

      if (isLastStudentQuestion) {
        _studentResult = StudentAssessmentCalculator.calculate(
          questions: _studentQuestions,
          answers: _studentAnswers,
          userType: activeAssessmentUserType,
        );
        notifyListeners();
        return;
      }

      _studentQuestionIndex += 1;
      notifyListeners();
    } finally {
      _isRecordingStudentAnswer = false;
    }
  }

  Future<void> retryDomainPreview() => _requestPendingDomainPreview();

  void continueAfterDomainReview() {
    if (_flowStage != AssessmentFlowStage.domainReview &&
        _flowStage != AssessmentFlowStage.recoverableError) {
      return;
    }
    _flowStage = AssessmentFlowStage.resuming;
    _domainPreviewError = null;
    _pendingDomainId = null;
    if (isLastStudentQuestion) {
      _flowStage = AssessmentFlowStage.submitting;
    } else {
      _studentQuestionIndex += 1;
      _flowStage = AssessmentFlowStage.answering;
    }
    notifyListeners();
  }

  void returnToAnsweringFromDomainReview() {
    if (_flowStage != AssessmentFlowStage.domainReview &&
        _flowStage != AssessmentFlowStage.recoverableError) {
      return;
    }
    _flowStage = AssessmentFlowStage.answering;
    notifyListeners();
  }

  void goBackStudentQuestion() {
    if (!canGoBackStudentQuestion) return;
    _studentResult = null;
    _studentQuestionIndex -= 1;
    _flowStage = AssessmentFlowStage.answering;
    notifyListeners();
  }

  Future<Map<String, Object>?> saveStudentAssessmentForUser(String userId) async {
    if (_isSavingStudentAssessment) return null;
    _isSavingStudentAssessment = true;
    try {
    if (isV4FullAssessment) {
      return await _repository.saveV4FullAssessment(
        userId: userId,
        instrumentVersion: _v4InstrumentVersion,
        answers: _studentAnswers,
        submissionId:
            _v4SubmissionId ??
            'v4_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      );
    }
    final result = _studentResult;
    if (result == null) return null;

    return await _repository.saveStudentAssessment(
      userId: userId,
      result: result,
      answers: _studentAnswers,
    );
    } finally {
      _isSavingStudentAssessment = false;
    }
  }

  bool _isDomainComplete(String domainId) {
    final questions = _studentQuestions
        .where((question) => question.v4DomainId == domainId)
        .toList();
    return questions.length == 10 && questions.every(
      (question) => _studentAnswers.any((answer) => answer.questionId == question.id),
    );
  }

  List<StudentAssessmentAnswer> _answersForDomain(String domainId) => [
    for (final question in _studentQuestions)
      if (question.v4DomainId == domainId)
        _studentAnswers.firstWhere((answer) => answer.questionId == question.id),
  ];

  Future<void> _requestPendingDomainPreview() async {
    final domainId = _pendingDomainId;
    if (!isV4FullAssessment || domainId == null || _flowStage == AssessmentFlowStage.previewLoading) return;
    final generation = ++_previewGeneration;
    _flowStage = AssessmentFlowStage.previewLoading;
    _domainPreview = null;
    _domainPreviewError = null;
    notifyListeners();
    try {
      final preview = await _repository.previewV4AssessmentDomain(
        instrumentVersion: _v4InstrumentVersion,
        domainId: domainId,
        answers: _answersForDomain(domainId),
      );
      if (generation != _previewGeneration || _pendingDomainId != domainId) return;
      _domainPreview = preview;
      _flowStage = AssessmentFlowStage.domainReview;
    } catch (error) {
      if (generation != _previewGeneration || _pendingDomainId != domainId) return;
      _domainPreviewError = error;
      _flowStage = AssessmentFlowStage.recoverableError;
    }
    notifyListeners();
  }

  void _invalidatePreviewFor(String? domainId) {
    if (domainId == null || _pendingDomainId != domainId) return;
    _previewGeneration += 1;
    _domainPreview = null;
    _domainPreviewError = null;
    _pendingDomainId = null;
    _flowStage = AssessmentFlowStage.answering;
  }

  Future<void> saveAssessmentClarityFeedback(String clarity) {
    final result = _studentResult;
    if (result == null) return Future.value();
    return _repository.saveAssessmentClarityFeedback(
      clarity: clarity,
      algorithmVersion: result.interpretation.algorithmVersion,
      questionSetVersion: result.interpretation.questionSetVersion,
    );
  }

  Future<FullAssessmentEligibility> fullAssessmentEligibility(
    String userId, {
    DateTime? now,
  }) {
    return _repository.fullAssessmentEligibility(userId, now: now);
  }

  List<StudentAssessmentQuestion> _questionsForActiveRole() {
    switch (activeAssessmentUserType) {
      case AssessmentUserType.student:
        return isStudentAssessmentV4
            ? StudentAssessmentV4Questions.questions
            : StudentAssessmentQuestions.questions;
      case AssessmentUserType.faculty:
        return isTeachingAssessmentV4
            ? TeachingAssessmentV4Questions.questions
            : StudentAssessmentQuestions.facultyQuestions;
      case AssessmentUserType.staff:
        return isNonTeachingAssessmentV4
            ? NonTeachingAssessmentV4Questions.questions
            : StudentAssessmentQuestions.staffQuestions;
    }
  }

  String get _v4InstrumentVersion {
    switch (activeAssessmentUserType) {
      case AssessmentUserType.faculty:
        return TeachingAssessmentV4Questions.instrumentVersion;
      case AssessmentUserType.staff:
        return NonTeachingAssessmentV4Questions.instrumentVersion;
      case AssessmentUserType.student:
        return StudentAssessmentV4Questions.instrumentVersion;
    }
  }
}
