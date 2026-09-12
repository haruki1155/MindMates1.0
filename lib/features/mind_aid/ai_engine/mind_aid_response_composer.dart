import '../domain/mind_aid_chat_models.dart';
import '../domain/mind_aid_context.dart';
import '../domain/mind_aid_dataset_models.dart';
import '../domain/mind_aid_model_provider.dart';
import '../domain/mind_aid_safety.dart';
import 'mind_aid_dialogue_manager.dart';
import 'response_builder.dart';

class MindAidResponseComposer {
  MindAidResponseComposer({MindAidModelProvider? modelProvider})
    : modelProvider =
          modelProvider ?? HybridMindAidModelProvider.fromEnvironment();

  final MindAidModelProvider modelProvider;

  Future<String> compose({
    required MindAidDialogueAction action,
    required String normalizedInput,
    required String originalInput,
    required List<MindAidIntentMatch> matches,
    required MindAidDatasetBundle dataset,
    required MindAidConversationState state,
    required MindAidContext context,
    required MindAidSafetyLevel safetyLevel,
  }) async {
    if (safetyLevel.blocksCloud) {
      return _safetyResponse(
        safetyLevel: safetyLevel,
        dataset: dataset,
        normalizedInput: normalizedInput,
      );
    }

    if (action != MindAidDialogueAction.escalate &&
        _isAssessmentReviewRequest(normalizedInput) &&
        context.hasAssessment) {
      return _withPersona(
        _assessmentReview(context),
        normalizedInput: normalizedInput,
        matches: matches,
        context: context,
        includeQuestion: false,
      );
    }

    final modelText = await modelProvider.generate(
      MindAidModelPrompt(
        userText: originalInput,
        matches: matches,
        state: state,
        dataset: dataset,
        requiresEscalation: action == MindAidDialogueAction.escalate,
        context: context,
        safetyLevel: safetyLevel,
      ),
    );
    if (modelText.trim().isNotEmpty) return modelText.trim();

    switch (action) {
      case MindAidDialogueAction.clarify:
        return _withPersona(
          _clarify(state),
          normalizedInput: normalizedInput,
          matches: matches,
          context: context,
          includeQuestion: false,
        );
      case MindAidDialogueAction.followUp:
        return _withPersona(
          _followUp(normalizedInput, matches.first, dataset, state),
          normalizedInput: normalizedInput,
          matches: matches,
          context: context,
        );
      case MindAidDialogueAction.escalate:
        return ResponseBuilder.build(
          record: matches.first.record,
          dataset: dataset,
          normalizedInput: normalizedInput,
        );
      case MindAidDialogueAction.answer:
        return _withPersona(
          _answer(normalizedInput, matches, dataset, state, context),
          normalizedInput: normalizedInput,
          matches: matches,
          context: context,
        );
    }
  }

  String _answer(
    String normalizedInput,
    List<MindAidIntentMatch> matches,
    MindAidDatasetBundle dataset,
    MindAidConversationState state,
    MindAidContext context,
  ) {
    final primary = matches.first.record;
    final buffer = StringBuffer(
      ResponseBuilder.build(
        record: primary,
        dataset: dataset,
        normalizedInput: normalizedInput,
        recentResponses: state.recentResponses,
      ),
    );

    if (matches.length > 1) {
      final secondary = matches[1].record;
      buffer.write(
        '\n\nI also hear some ${_readable(secondary.intent)} in what you said. '
        '${_shortSupportLine(secondary, dataset, normalizedInput)}',
      );
    }

    final assessmentLine = _assessmentSupportLine(context, primary.intent);
    if (assessmentLine != null) {
      buffer.write('\n\n$assessmentLine');
    }

    return buffer.toString();
  }

  String _safetyResponse({
    required MindAidSafetyLevel safetyLevel,
    required MindAidDatasetBundle dataset,
    required String normalizedInput,
  }) {
    final record = dataset.crisisRecords.isEmpty
        ? null
        : dataset.crisisRecords.first;
    if (record != null) {
      return ResponseBuilder.build(
        record: record,
        dataset: dataset,
        normalizedInput: normalizedInput,
      );
    }

    if (safetyLevel == MindAidSafetyLevel.crisisOrImmediateRisk) {
      return 'MindAid is an automated wellness assistant and cannot provide emergency care. Your safety matters right now. Please move near a trusted person and contact local emergency services, campus security, PACC, or the nearest emergency room immediately.';
    }
    return 'MindAid is an automated wellness assistant and cannot provide emergency care. This sounds very intense. Please move toward a trusted person or safe place and contact PACC or local emergency services if you may be in immediate danger.';
  }

  String _assessmentReview(MindAidContext context) {
    final assessment = context.assessment;
    if (assessment == null) {
      final quick = context.quickAssessment;
      if (quick != null) {
        final concerns = quick.topConcernAreas.isEmpty
            ? 'your overall check-in pattern'
            : quick.topConcernAreas.take(2).join(' and ');
        return 'I can review your quick assessment as a wellness signal, not a diagnosis. '
            'It suggests a ${quick.level.toLowerCase()} support need (${quick.score}/100), mainly around $concerns. '
            '${quick.summary} ${quick.recommendedNextStep} '
            'What part of this result feels most important today?';
      }

      final snapshot = context.wellnessSnapshot;
      if (snapshot != null) {
        final score = snapshot.assessmentScore;
        final status = snapshot.assessmentStatus;
        final signal = snapshot.mentalStatusSignal;
        final concerns = snapshot.topConcernAreas.isEmpty
            ? 'your recent wellness pattern'
            : snapshot.topConcernAreas.take(2).join(' and ');
        final scoreText = score == null ? '' : ' ($score/100)';
        final statusText = status == null
            ? 'a wellness signal'
            : 'a $status support signal$scoreText';
        final signalText = signal == null ? '' : ' The signal is $signal.';
        final action = snapshot.recommendedSupportAction;
        return 'I can review the latest wellness information I have, not as a diagnosis but as a guide. It points to $statusText, mainly around $concerns.$signalText ${action ?? 'A small next step could be choosing one support action for today.'} What part of this feels most accurate right now?';
      }

      final score = context.effectiveAssessmentScore;
      final scoreText = score == null ? '' : ' of $score/100';
      return 'I can keep your quick assessment score$scoreText in mind as a wellness signal, not a diagnosis. It suggests checking in with what feels most urgent today, then choosing one small support step. What part of your result do you want to understand first?';
    }

    final top = assessment.highestCategory;
    final topCategories = assessment.topCategories
        .map((entry) => '${entry.key} (${entry.value.round()}%)')
        .join(', ');
    final concernText = assessment.mainConcernAreas.isEmpty
        ? top?.key
        : assessment.mainConcernAreas.take(2).join(' and ');
    final scoreText = assessment.overallScore == null
        ? 'An overall concern index was not calculated because one or more categories needed additional responses.'
        : 'Your secondary overall concern index is ${assessment.overallScore!.round()}/100, with a status of ${assessment.status}.';
    final buffer = StringBuffer(
      'I reviewed your latest ${assessment.userType.toLowerCase()} assessment. '
      '$scoreText This experimental university wellness screener is not a diagnosis.',
    );

    if (top != null) {
      buffer.write(
        '\n\nThe strongest area showing up is ${top.key} at ${top.value.round()}%.',
      );
      if (topCategories.isNotEmpty) {
        buffer.write(' Your top categories are $topCategories.');
      }
    }

    if (concernText != null && concernText.trim().isNotEmpty) {
      buffer.write(
        '\n\nA helpful next step could be to focus on $concernText first: choose one small action today, then consider talking with PACC or someone you trust if this has been affecting your daily functioning.',
      );
    } else {
      buffer.write(
        '\n\nA helpful next step could be to choose one area that feels most disruptive today and work on one small, realistic support action.',
      );
    }

    buffer.write('\n\nWhat part of this result feels most true for you?');
    return buffer.toString();
  }

  String? _assessmentSupportLine(MindAidContext context, String intent) {
    final assessment = context.assessment;
    if (assessment == null || assessment.subscaleScores.isEmpty) return null;

    final top = assessment.highestCategory;
    if (top == null || top.value < 55) return null;

    final topLabel = top.key.toLowerCase();
    final readableIntent = _readable(intent);
    final isRelevant =
        topLabel.contains(readableIntent) ||
        readableIntent.contains('stress') && topLabel.contains('stress') ||
        readableIntent.contains('burnout') &&
            (topLabel.contains('well-being') || topLabel.contains('rest')) ||
        readableIntent.contains('anxiety') && topLabel.contains('emotional');

    if (!isRelevant) return null;

    return 'I am also keeping your assessment in mind: ${top.key} was one of the higher areas, so it could help to make the next step small and specific rather than trying to fix everything at once.';
  }

  bool _isAssessmentReviewRequest(String value) {
    if (value.isEmpty) return false;
    final mentionsAssessment =
        value.contains('assessment') ||
        value.contains('result') ||
        value.contains('score');
    final asksForReview =
        value.contains('review') ||
        value.contains('think') ||
        value.contains('mean') ||
        value.contains('help') ||
        value.contains('suggest') ||
        value.contains('what should i do') ||
        value.contains('next');

    return mentionsAssessment && asksForReview;
  }

  String _followUp(
    String normalizedInput,
    MindAidIntentMatch match,
    MindAidDatasetBundle dataset,
    MindAidConversationState state,
  ) {
    final record = match.record;
    final topic = _readable(record.intent);
    final buffer = StringBuffer();

    if (_isYes(normalizedInput)) {
      buffer.write('Okay. Let us stay with $topic and keep it manageable.');
    } else if (_isNo(normalizedInput)) {
      buffer.write(
        'That is okay. We can change direction and focus on what feels more useful now.',
      );
    } else {
      buffer.write(
        'Thanks for telling me. I will connect that back to $topic so we can make the next step clearer.',
      );
    }

    MindAidCopingExercise? exercise;
    for (final id in record.copingSteps) {
      exercise = dataset.copingById(id);
      if (exercise != null) break;
    }
    if (exercise != null) {
      buffer.write('\n\nA small next step: ${exercise.description}');
    }

    final question = record.followUpQuestions.isNotEmpty
        ? record.followUpQuestions.first
        : state.lastQuestion;
    if (question != null && question.trim().isNotEmpty) {
      buffer.write('\n\n$question');
    }

    return buffer.toString();
  }

  String _clarify(MindAidConversationState state) {
    if (state.lastQuestion != null) {
      return 'I want to understand you better. ${state.lastQuestion}';
    }
    return 'I want to support you well, but I need a little more detail. Is this mostly about school, relationships, stress, anxiety, or something else?';
  }

  String _withPersona(
    String base, {
    required String normalizedInput,
    required List<MindAidIntentMatch> matches,
    required MindAidContext context,
    bool includeQuestion = true,
  }) {
    final trimmed = base.trim();
    if (trimmed.isEmpty) return trimmed;

    final parts = <String>[];
    final empathy = _empathyLine(context, matches);
    if (!_startsWithAny(trimmed, ['i hear', 'i can', 'thanks', 'okay'])) {
      parts.add(empathy);
    }

    final opinion = _perspectiveLine(context, matches);
    if (opinion != null && !trimmed.toLowerCase().contains('my take')) {
      parts.add(opinion);
    }

    parts.add(trimmed);

    final contextual = _contextualSupportLine(context, matches);
    if (contextual != null && !trimmed.contains(contextual)) {
      parts.add(contextual);
    }

    if (includeQuestion &&
        !trimmed.endsWith('?') &&
        !parts.any((part) => part.trim().endsWith('?'))) {
      parts.add(_gentleQuestion(context, matches));
    }

    return parts.join('\n\n');
  }

  String _empathyLine(
    MindAidContext context,
    List<MindAidIntentMatch> matches,
  ) {
    final snapshot = context.wellnessSnapshot;
    if (snapshot?.hasRecentLowMood == true) {
      return 'I hear that this has been heavy lately, and I want to keep the next step gentle.';
    }
    final intent = matches.isEmpty
        ? null
        : _readable(matches.first.record.intent);
    if (intent != null) {
      return 'I hear you. $intent can feel like a lot when you are carrying it alone.';
    }
    return 'I hear you, and I am glad you said it here.';
  }

  String? _perspectiveLine(
    MindAidContext context,
    List<MindAidIntentMatch> matches,
  ) {
    final snapshot = context.wellnessSnapshot;
    if (snapshot?.hasElevatedAssessment == true) {
      final concern = snapshot?.primaryConcernLabel;
      return 'My take is that this deserves steady support, especially${concern == null ? '' : ' around $concern'}, without treating it like something you have to solve all at once.';
    }
    if (snapshot?.hasPositivePractice == true) {
      return 'What stands out to me is that you already have some supportive activity in motion, so we can build from what is working.';
    }
    if (matches.isNotEmpty) {
      return 'My take is that the most useful move is to make this smaller and more specific first.';
    }
    return null;
  }

  String? _contextualSupportLine(
    MindAidContext context,
    List<MindAidIntentMatch> matches,
  ) {
    final snapshot = context.wellnessSnapshot;
    if (snapshot == null) return null;

    if (snapshot.hasRecentLowMood) {
      return 'Because your recent mood looks low, I would keep today\'s goal small: one grounding step, one basic need, or one trusted person.';
    }
    if (snapshot.hasElevatedAssessment) {
      final action = snapshot.recommendedSupportAction;
      return action == null
          ? 'Your recent wellness signal looks elevated, so it could help to include PACC or someone you trust if this is affecting daily life.'
          : 'Your recent wellness signal looks elevated, so a helpful next step is: $action.';
    }
    if (snapshot.hasNoRecentCheckIn && matches.isEmpty) {
      return 'I do not see a recent check-in, so a quick mood log could help me support you with better context.';
    }
    if (snapshot.hasPositivePractice) {
      return 'The streak or breathing activity in your recent pattern is worth keeping; consistency can be a quiet anchor.';
    }
    return null;
  }

  String _gentleQuestion(
    MindAidContext context,
    List<MindAidIntentMatch> matches,
  ) {
    final concern = context.wellnessSnapshot?.primaryConcernLabel;
    if (concern != null) {
      return 'What feels most connected to $concern right now?';
    }
    if (matches.isNotEmpty) {
      return 'What is the smallest part of this you want help with first?';
    }
    return 'What feels hardest right now?';
  }

  String _shortSupportLine(
    MindAidDatasetRecord record,
    MindAidDatasetBundle dataset,
    String normalizedInput,
  ) {
    final response = ResponseBuilder.build(
      record: record,
      dataset: dataset,
      normalizedInput: normalizedInput,
      includeFollowUp: false,
      includeExercise: false,
    );
    final firstSentence = response.split(RegExp(r'(?<=[.!?])\s+')).first;
    return firstSentence;
  }

  String _readable(String value) => value.replaceAll('_', ' ');

  bool _isYes(String value) => value == 'yes' || value.startsWith('yes ');

  bool _isNo(String value) => value == 'no' || value.startsWith('no ');

  bool _startsWithAny(String value, List<String> prefixes) {
    final normalized = value.toLowerCase();
    return prefixes.any(normalized.startsWith);
  }
}
