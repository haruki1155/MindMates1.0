import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/providers/mind_aid_provider.dart';
import '/providers/assessment_provider.dart';
import '/providers/auth_provider.dart';
import '/providers/report_provider.dart';
import '/providers/user_provider.dart';
import '/features/counseling/screens/mind_aid_screen.dart';
import '/features/mind_aid/domain/mind_aid_context.dart';
import '/features/mind_aid/domain/mind_aid_integration_models.dart';
import '/features/counseling/screens/pacc_counseling_screen.dart';
import '/repositories/mind_aid_context_repository.dart';
import '/routes/route_names.dart';

class MindAidPage extends StatefulWidget {
  const MindAidPage({super.key});

  @override
  State<MindAidPage> createState() => _MindAidPageState();
}

class _MindAidPageState extends State<MindAidPage> {
  final MindAidContextRepository _contextRepository =
      MindAidContextRepository();

  String? _loadedContextKey;
  String? _loadedSnapshotUserId;
  MindAidWellnessSnapshot? _wellnessSnapshot;
  bool _consentDialogScheduled = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MindAidProvider>();
    final assessmentProvider = context.watch<AssessmentProvider>();
    final authProvider = context.watch<AuthProvider>();
    final userId = authProvider.userId ?? 'guest';
    final launchContext =
        ModalRoute.of(context)?.settings.arguments is MindAidLaunchContext
        ? ModalRoute.of(context)!.settings.arguments as MindAidLaunchContext
        : const MindAidLaunchContext(source: 'direct');
    _loadWellnessSnapshot(userId);
    final mindAidContext = _buildMindAidContext(
      assessmentProvider,
      _wellnessSnapshot,
    );
    _loadChatWhenContextChanges(userId, mindAidContext, launchContext);
    _scheduleConsentIfNeeded(provider, userId);

    return MindAidScreen(
      messages: provider.messages,
      suggestions: provider.suggestions,
      isAssistantTyping: provider.isSending || provider.isLoading,
      errorText: provider.errorMessage,
      onSendMessage: (text) {
        _sendAndRecordActivity(userId, text, mindAidContext);
      },
      onSuggestionSelected: (suggestion) {
        _selectSuggestionAndRecordActivity(userId, suggestion, mindAidContext);
      },
      onNotificationTap: () {},
      onActionSelected: (action) => _handleAction(action, launchContext),
      onFeedback: (messageId, helpful) async {
        if (userId == 'guest') return;
        await provider.submitFeedback(
          userId: userId,
          messageId: messageId,
          helpful: helpful,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Thanks for your feedback.')),
          );
        }
      },
      onRetry: () => provider.retryLastMessage(userId, context: mindAidContext),
      onClearHistory: () => _confirmClearHistory(provider, userId),
      onNewConversation: () => _startNewConversation(provider, userId),
      onPrivacyTap: () => _showConsentDialog(provider, userId, editing: true),
      disclaimerText: provider.usesDialogflow
          ? 'MindAid is an automated, non-clinical wellness assistant. It offers general information, reflection prompts, and coping suggestions when PACC or administrators are unavailable. It is not monitored in real time, does not diagnose or treat mental-health conditions, and never replaces professional support or emergency services.'
          : 'MindAid is an automated, non-clinical wellness assistant. It offers general information, reflection prompts, and coping suggestions when PACC or administrators are unavailable. It is not monitored in real time, does not diagnose or treat mental-health conditions, and never replaces professional support or emergency services.',
    );
  }

  Future<void> _sendAndRecordActivity(
    String userId,
    String text,
    MindAidContext contextValue,
  ) async {
    final sent = await context.read<MindAidProvider>().sendMessage(
      userId,
      text,
      context: contextValue,
    );
    if (!mounted || !sent || userId == 'guest') return;
    if (!context.read<MindAidProvider>().lastUserMessagePersisted) return;
    await context.read<UserProvider>().markMindAidMessage(userId);
    await _refreshProfileAndReport(userId);
  }

  Future<void> _selectSuggestionAndRecordActivity(
    String userId,
    MindAidSuggestion suggestion,
    MindAidContext contextValue,
  ) async {
    final sent = await context.read<MindAidProvider>().selectSuggestion(
      suggestion,
      userId,
      context: contextValue,
    );
    if (!mounted || !sent || userId == 'guest') return;
    if (!context.read<MindAidProvider>().lastUserMessagePersisted) return;
    await context.read<UserProvider>().markMindAidMessage(userId);
    await _refreshProfileAndReport(userId);
  }

  Future<void> _refreshProfileAndReport(String userId) async {
    try {
      await context.read<UserProvider>().loadProfile(userId);
      await _readProviderOrNull<ReportProvider>()?.refreshWeeklyReport(userId);
    } catch (_) {
      // MindAid chat remains available even if summary refresh is delayed.
    }
  }

  T? _readProviderOrNull<T>() {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  MindAidContext _buildMindAidContext(
    AssessmentProvider provider,
    MindAidWellnessSnapshot? snapshot,
  ) {
    final fullResult = provider.studentResult;
    if (fullResult != null) {
      return MindAidContext(
        assessment: MindAidAssessmentContext(
          userType: fullResult.userType,
          overallScore: fullResult.overallScore,
          status: fullResult.status,
          mainConcernAreas: fullResult.mainConcernAreas,
          subscaleScores: fullResult.subscaleScores,
          summaryMessage: fullResult.message,
        ),
        wellnessSnapshot: snapshot,
      );
    }

    final quickResult = provider.quickResult;
    if (quickResult != null) {
      return MindAidContext(
        quickAssessment: MindAidQuickAssessmentContext(
          score: quickResult.concernScore.round(),
          level: quickResult.overallLevel.label,
          signal: quickResult.mentalStatusSignal.name,
          summary: quickResult.summary,
          topConcernAreas: quickResult.topConcernAreas,
          recommendedNextStep: quickResult.recommendedNextStep,
          createdAt: quickResult.createdAt,
        ),
        wellnessSnapshot: snapshot,
      );
    }

    return MindAidContext(wellnessSnapshot: snapshot);
  }

  void _loadWellnessSnapshot(String userId) {
    if (userId == 'guest' || userId.trim().isEmpty) {
      if (_wellnessSnapshot != null || _loadedSnapshotUserId != userId) {
        _loadedSnapshotUserId = userId;
        _wellnessSnapshot = null;
      }
      return;
    }

    if (_loadedSnapshotUserId == userId) return;
    _loadedSnapshotUserId = userId;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final snapshot = await _contextRepository.fetchWellnessSnapshot(userId);
      if (!mounted || _loadedSnapshotUserId != userId) return;
      setState(() {
        _wellnessSnapshot = snapshot;
      });
    });
  }

  void _loadChatWhenContextChanges(
    String userId,
    MindAidContext contextValue,
    MindAidLaunchContext launchContext,
  ) {
    final key = '$userId:${_contextKey(contextValue)}';
    if (_loadedContextKey == key) return;

    _loadedContextKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MindAidProvider>().loadChat(
        userId,
        context: contextValue,
        launchContext: launchContext,
      );
    });
  }

  void _scheduleConsentIfNeeded(MindAidProvider provider, String userId) {
    if (userId == 'guest' ||
        !provider.needsConsent ||
        _consentDialogScheduled) {
      return;
    }
    _consentDialogScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _showConsentDialog(provider, userId);
    });
  }

  Future<void> _showConsentDialog(
    MindAidProvider provider,
    String userId, {
    bool editing = false,
  }) async {
    final useCloud = await showDialog<bool>(
      context: context,
      barrierDismissible: editing,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          editing ? 'AI privacy settings' : 'Choose how MindAid works',
        ),
        content: const Text(
          'MindAid is a non-clinical automated wellness assistant, not a therapist, diagnostic tool, treatment service, or emergency response service. It can provide general wellness information and coping suggestions when PACC or administrators are unavailable, but chats are not monitored in real time. Dialogflow can make MindAid more conversational. With your permission, it receives your chat turns and limited derived signals such as mood trends and assessment level. Journal text, mood notes, raw answers, and contact details are never sent. You can instead keep using the local assistant.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Use local only'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Use personalized AI'),
          ),
        ],
      ),
    );
    if (useCloud == null || !mounted) return;
    await provider.setConsent(userId: userId, cloudConsent: useCloud);
  }

  Future<void> _confirmClearHistory(
    MindAidProvider provider,
    String userId,
  ) async {
    if (userId == 'guest') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear MindAid history?'),
        content: const Text(
          'This permanently removes your saved MindAid messages and starts a new conversation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await provider.clearHistory(userId);
  }

  Future<void> _startNewConversation(
    MindAidProvider provider,
    String userId,
  ) async {
    if (userId == 'guest') return;
    await provider.startNewConversation(userId);
  }

  void _handleAction(MindAidAction action, MindAidLaunchContext launchContext) {
    switch (action.type) {
      case MindAidActionType.logMood:
        Navigator.pushNamed(context, RouteNames.logMood);
        return;
      case MindAidActionType.startBreathing:
        Navigator.pushNamed(context, RouteNames.mindfulBreathing);
        return;
      case MindAidActionType.openAssessment:
        Navigator.pushNamed(context, RouteNames.studentAssessment);
        return;
      case MindAidActionType.openInsights:
        Navigator.pushNamed(context, RouteNames.mentalHealthInsights);
        return;
      case MindAidActionType.openCounselingServices:
        Navigator.pushNamed(context, RouteNames.services);
        return;
      case MindAidActionType.bookAppointment:
        final concern =
            (action.payload['concern'] ??
                    launchContext.appointmentConcern ??
                    'I would like support with a concern discussed in MindAid.')
                .toString();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PaccCounselingScreen(
              startBooking: true,
              initialConcern: concern,
            ),
          ),
        );
        return;
      case MindAidActionType.viewAppointments:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PaccCounselingScreen()));
        return;
    }
  }

  String _contextKey(MindAidContext contextValue) {
    final assessment = contextValue.assessment;
    if (assessment != null) {
      final categoryKey = assessment.subscaleScores.entries
          .map((entry) => '${entry.key}:${entry.value.round()}')
          .join('|');
      return [
        'full',
        assessment.userType,
        assessment.status,
        assessment.overallScore?.round(),
        assessment.mainConcernAreas.join('|'),
        categoryKey,
        _snapshotKey(contextValue.wellnessSnapshot),
      ].join(':');
    }

    final quick = contextValue.quickAssessment;
    if (quick != null) {
      return [
        'quick',
        quick.score,
        quick.level,
        quick.signal,
        quick.topConcernAreas.join('|'),
        _snapshotKey(contextValue.wellnessSnapshot),
      ].join(':');
    }

    final snapshot = contextValue.wellnessSnapshot;
    if (snapshot != null) {
      return [
        'wellness',
        snapshot.latestMoodLevel ?? 'mood-none',
        snapshot.recentMoodAverage?.toStringAsFixed(1) ?? 'avg-none',
        snapshot.moodTrend?.name ?? 'trend-none',
        snapshot.assessmentStatus ?? 'status-none',
        snapshot.assessmentScore ?? 'score-none',
        snapshot.mentalStatusSignal ?? 'signal-none',
        snapshot.topConcernAreas.join('|'),
        snapshot.currentStreak,
        snapshot.activeDayCount,
        snapshot.breathingSessionCount,
      ].join(':');
    }

    return 'quick:${contextValue.assessmentScore ?? 'none'}';
  }

  String _snapshotKey(MindAidWellnessSnapshot? snapshot) {
    if (snapshot == null) return 'snapshot:none';
    return [
      'wellness',
      snapshot.latestMoodLevel ?? 'mood-none',
      snapshot.recentMoodAverage?.toStringAsFixed(1) ?? 'avg-none',
      snapshot.moodTrend?.name ?? 'trend-none',
      snapshot.assessmentStatus ?? 'status-none',
      snapshot.assessmentScore ?? 'score-none',
      snapshot.mentalStatusSignal ?? 'signal-none',
      snapshot.topConcernAreas.join('|'),
      snapshot.currentStreak,
      snapshot.activeDayCount,
      snapshot.breathingSessionCount,
    ].join(':');
  }
}
