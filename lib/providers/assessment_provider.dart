import 'package:flutter/foundation.dart';

import '../features/quick_assessment/data/quick_assessment_questions.dart';
import '../features/quick_assessment/models/quick_assessment_models.dart';
import '../features/quick_assessment/services/quick_assessment_scoring.dart';
import '../features/student_assessment/data/student_assessment_questions.dart';
import '../features/student_assessment/models/student_assessment_models.dart';
import '../features/student_assessment/services/student_assessment_calculator.dart';
import '../repositories/assessment_repository.dart';

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
  bool _isSavingQuickAssessment = false;

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
        return 'Student Assessment';
      case AssessmentUserType.faculty:
        return 'Teaching Assessment';
      case AssessmentUserType.staff:
        return 'Non-Teaching Assessment';
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
    _studentQuestions = _questionsForActiveRole()
        .where((question) => !question.isConditional)
        .toList();
    notifyListeners();
  }

  void answerCurrentStudentQuestion(
    LikertAnswer answer, {
    bool isSkipped = false,
  }) {
    final question = currentStudentQuestion;
    if (question == null) return;

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
  }

  void goBackStudentQuestion() {
    if (!canGoBackStudentQuestion) return;
    _studentResult = null;
    _studentQuestionIndex -= 1;
    notifyListeners();
  }

  Future<Map<String, Object>?> saveStudentAssessmentForUser(String userId) {
    final result = _studentResult;
    if (result == null) return Future.value();

    return _repository.saveStudentAssessment(
      userId: userId,
      result: result,
      answers: _studentAnswers,
    );
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
        return StudentAssessmentQuestions.questions;
      case AssessmentUserType.faculty:
        return StudentAssessmentQuestions.facultyQuestions;
      case AssessmentUserType.staff:
        return StudentAssessmentQuestions.staffQuestions;
    }
  }
}
