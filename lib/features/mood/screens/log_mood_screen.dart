import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../expression_check_in/expression_check_in_screen.dart';
import '../expression_check_in/photo_expression_screen.dart';
import '../expression_check_in/expression_scan_logic.dart';
import '../expression_check_in/tflite_expression_classifier.dart'
    if (dart.library.js_interop) '../expression_check_in/tflite_expression_classifier_web.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/insights_provider.dart';
import '../../../providers/mood_provider.dart';
import '../../../providers/report_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../models/mood_model.dart';
import '../domain/mood_v2_analytics.dart';
import '../../../repositories/mood_repository.dart';
import '../../../repositories/mood_v2_repository.dart';
import '../../../services/firebase/firebase_error_message.dart';
import '../config/mood_v2_feature_flag.dart';
import '../widgets/mood_v2_history_panel.dart';
import '../widgets/mood_glyph.dart';
import 'mood_journey_screen.dart';

const bool _expressionCheckInEnabled = true;

class LogMoodScreen extends StatefulWidget {
  const LogMoodScreen({
    super.key,
    DateTime Function()? nowProvider,
    this.expressionScreenBuilder,
    this.moodV2Writer,
    this.moodV2Presentation = MoodV2FeatureFlag.presentation,
    this.moodV2WriterEnabled = MoodV2FeatureFlag.enabled,
    this.moodV2RequestIdGenerator,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  final DateTime Function() _nowProvider;
  final WidgetBuilder? expressionScreenBuilder;
  final MoodV2EntryWriter? moodV2Writer;

  /// Whether the Mood V2 presentation is shown. Layout only — never
  /// persistence.
  final bool moodV2Presentation;

  /// Whether saving uses the protected V2 writer. Persistence only — never
  /// layout. Off means the legacy writer handles the save.
  final bool moodV2WriterEnabled;
  final String Function()? moodV2RequestIdGenerator;

  @override
  State<LogMoodScreen> createState() => _LogMoodScreenState();
}

class _LogMoodScreenState extends State<LogMoodScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _noteFocus = FocusNode();
  final GlobalKey _noteFieldKey = GlobalKey();
  bool _reflectionOffered = false;
  DialogRoute<bool>? _reflectionRoute;

  void _dismissReflection() {
    final route = _reflectionRoute;
    _reflectionRoute = null;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  Future<void> _offerMoodReflection() async {
    if (!widget.moodV2Presentation ||
        _reflectionOffered ||
        !mounted ||
        _isSaving) {
      return;
    }
    _reflectionOffered = true;
    final owner = _currentUserId();
    final generation = _moodV2RequestGeneration;
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: MoodLogPalette.surface,
        title: const Text('Why do you feel this way?'),
        content: const Text(
          "You can share a little insight in the note below. It's optional.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Skip',
              style: TextStyle(color: MoodLogPalette.ink),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MoodLogPalette.gold,
              foregroundColor: MoodLogPalette.ink,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Add note'),
          ),
        ],
      ),
    );
    _reflectionRoute = route;
    final addNote = await Navigator.of(context).push(route);
    if (_reflectionRoute == route) _reflectionRoute = null;
    if (!mounted ||
        owner != _currentUserId() ||
        generation != _moodV2RequestGeneration ||
        addNote != true) {
      return;
    }
    _noteFocus.requestFocus();
    final field = _noteFieldKey.currentContext;
    if (field != null && field.mounted) {
      await Scrollable.ensureVisible(
        field,
        duration: const Duration(milliseconds: 200),
        alignment: .3,
      );
    }
  }

  _MoodChoice? _selectedMood;
  ExpressionCue? _expressionCue;
  ExpressionCueSource? _expressionCueSource;
  bool? _expressionSuggestionAccepted;
  int _noteLength = 0;
  bool _isSaving = false;
  bool _isLoadingToday = false;
  String? _todayError;
  MoodModel? _todayMood;
  MoodV2Event? _confirmedV2Entry;
  int _todayLoadGeneration = 0;
  String? _loadedUserId;
  String? _moodV2RequestId;
  _MoodV2Draft? _moodV2RetryDraft;
  String? _moodV2Error;
  /// Set when a refused V2 write was rescued through the legacy writer, so the
  /// confirmation can be rendered from [_todayMood] with the writer flag on.
  bool _usedLegacyMoodFallback = false;
  int _moodV2RequestGeneration = 0;
  Timer? _midnightTimer;

  DateTime get _now => widget._nowProvider();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _noteController.addListener(_handleNoteChanged);
    _scheduleMidnightRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = _currentUserId(listen: true);
    if (_loadedUserId == userId) return;
    _dismissReflection();
    _reflectionOffered = false;
    _invalidateMoodV2Request();
    _loadedUserId = userId;
    _todayLoadGeneration++;
    _todayMood = null;
    _todayError = null;
    _isLoadingToday = false;
    _confirmedV2Entry = null;
    _selectedMood = null;
    _expressionCue = null;
    _expressionCueSource = null;
    _expressionSuggestionAccepted = null;
    _noteController.clear();
    if (userId == null || userId.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentUserId() == userId) _loadTodayMood(userId);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final userId = _currentUserId();
      if (userId != null && userId.isNotEmpty) _loadTodayMood(userId);
      _scheduleMidnightRefresh();
    }
  }

  @override
  void dispose() {
    _dismissReflection();
    _noteFocus.dispose();
    _noteController
      ..removeListener(_handleNoteChanged)
      ..dispose();
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleNoteChanged() {
    if (_noteLength == _noteController.text.length) return;
    setState(() => _noteLength = _noteController.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final confirmation = _confirmation;
    return Scaffold(
      backgroundColor: MoodLogPalette.background,
      bottomNavigationBar: widget.moodV2Presentation && confirmation == null
          ? SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  12 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: _SaveMoodButton(
                  isEnabled:
                      _selectedMood != null &&
                      !_isSaving &&
                      // The form is replaced by a spinner or the retry card
                      // while today's mood reloads.
                      !_isLoadingToday &&
                      _todayError == null &&
                      (_expressionCue == null ||
                          _expressionSuggestionAccepted != null),
                  isSaving: _isSaving,
                  onPressed: _saveMood,
                  label: 'Save mood entry',
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _MoodLogHeader(
                v2: widget.moodV2Presentation,
                now: _now,
                showingResult: widget.moodV2Presentation
                    ? confirmation != null
                    : _todayMood != null,
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                28 + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return _buildContent();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final moodProvider = _readProviderOrNull<MoodProvider>(
      listen: MoodV2FeatureFlag.historyRead,
    );
    final showV2History =
        MoodV2FeatureFlag.historyRead &&
        (moodProvider?.isMoodV2ReadEnabled ?? false);
    final confirmation = _confirmation;
    if (widget.moodV2Presentation && confirmation != null) {
      return _MoodSaved(
        confirmation: confirmation,
        onAnother: widget.moodV2WriterEnabled
            ? _startAdditionalMoodEntry
            : null,
        onJourney: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const MoodJourneyScreen()),
        ),
        onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
        historyError: showV2History
            ? moodProvider?.v2HistoryErrorMessage
            : null,
        onRetryHistory: () {
          final uid = _currentUserId();
          if (uid != null) moodProvider?.loadMoodV2History(uid, now: _now);
        },
      );
    }
    if (!widget.moodV2WriterEnabled && _isLoadingToday) {
      return const SizedBox(
        height: 360,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!widget.moodV2WriterEnabled && _todayError != null) {
      return _MoodLoadError(
        message: _todayError!,
        onRetry: () {
          final userId = _currentUserId();
          if (userId != null) _loadTodayMood(userId);
        },
      );
    }
    if (!widget.moodV2WriterEnabled && _todayMood != null) {
      return Column(
        children: [
          _DailyMoodResult(
            mood: _todayMood!,
            currentStreak: _readProviderOrNull<UserProvider>()?.user?.dayStreak,
          ),
          if (showV2History && !widget.moodV2Presentation) ...[
            const SizedBox(height: 20),
            _buildMoodV2HistoryPanel(moodProvider),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.moodV2Presentation && showV2History)
          Semantics(
            button: true,
            label: 'View My Mood Journey',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MoodJourneyScreen(),
                ),
              ),
              child: _MoodCheckInSummary(
                canCheckInAgain: widget.moodV2WriterEnabled,
                history: moodProvider?.v2History,
                userId: _currentUserId(),
                now: _now,
                isLoading: moodProvider?.isLoadingV2History ?? false,
                error: moodProvider?.v2HistoryErrorMessage,
              ),
            ),
          ),
        if (widget.moodV2Presentation) ...[
          const SizedBox(height: 20),
          Text(
            'How are you feeling right now?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: MoodLogPalette.ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose the feeling that best matches what you’re experiencing at the moment.',
          ),
        ] else
          const _MoodLogIntro(),
        const SizedBox(height: 16),
        _MoodChoiceGrid(
          compact: widget.moodV2Presentation,
          selectedMood: _selectedMood,
          isEnabled: !_isSaving,
          onSelected: (mood) {
            setState(() => _selectedMood = mood);
            unawaited(_offerMoodReflection());
          },
        ),
        if (widget.moodV2Presentation) ...[
          const SizedBox(height: 16),
          _ThoughtsBox(
            key: _noteFieldKey,
            focusNode: _noteFocus,
            controller: _noteController,
            characterCount: _noteLength,
            compact: true,
            isEnabled: !_isSaving,
          ),
        ],
        if (_expressionCheckInEnabled &&
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS)) ...[
          const SizedBox(height: 18),
          _ExpressionCheckInEntry(
            compact: widget.moodV2Presentation,
            enabled: !_isSaving,
            onPressed: _openExpressionCheckIn,
          ),
          if (_expressionCue != null) ...[
            const SizedBox(height: 12),
            _ExpressionCueCard(
              cue: _expressionCue!,
              onAccepted: _acceptExpressionSuggestion,
              onRejected: () => setState(() {
                _expressionSuggestionAccepted = false;
              }),
              onSkipped: () => setState(() {
                _expressionCue = null;
                _expressionCueSource = null;
                _expressionSuggestionAccepted = null;
              }),
            ),
          ],
        ],
        const SizedBox(height: 18),
        if (!widget.moodV2Presentation)
          _ThoughtsBox(
            controller: _noteController,
            characterCount: _noteLength,
            compact: widget.moodV2Presentation,
            isEnabled: !_isSaving,
          ),
        if (_moodV2Error != null) ...[
          const SizedBox(height: 12),
          Text(
            _moodV2Error!,
            key: const ValueKey('mood-v2-save-error'),
            style: const TextStyle(color: Colors.redAccent),
          ),
        ],
        const SizedBox(height: 18),
        if (!widget.moodV2Presentation)
          _SaveMoodButton(
            isEnabled:
                _selectedMood != null &&
                !_isSaving &&
                (_expressionCue == null ||
                    _expressionSuggestionAccepted != null),
            isSaving: _isSaving,
            onPressed: _saveMood,
            label: widget.moodV2Presentation
                ? 'Save mood entry'
                : 'Save mood check-in',
          ),
        if (showV2History && !widget.moodV2Presentation) ...[
          const SizedBox(height: 20),
          _buildMoodV2HistoryPanel(moodProvider),
        ],
      ],
    );
  }

  Widget _buildMoodV2HistoryPanel(MoodProvider? moodProvider) =>
      MoodV2HistoryPanel(
        history: moodProvider?.v2History,
        errorMessage: moodProvider?.v2HistoryErrorMessage,
        isLoading: moodProvider?.isLoadingV2History ?? false,
        analytics: moodProvider?.v2Analytics,
        onRetry: () {
          final userId = _currentUserId();
          if (userId != null) {
            moodProvider?.loadMoodV2History(userId, now: _now);
          }
        },
        hasMore: moodProvider?.canLoadMoreMoodV2History ?? false,
        isLoadingMore: moodProvider?.isLoadingMoreV2History ?? false,
        paginationErrorMessage: moodProvider?.v2PaginationErrorMessage,
        onLoadMore: () {
          final userId = _currentUserId();
          if (userId != null) {
            moodProvider?.loadMoreMoodV2History(userId, now: _now);
          }
        },
      );

  Future<void> _openExpressionCheckIn() async {
    final userId = _currentUserId();
    final generation = _moodV2RequestGeneration;
    final result = await Navigator.of(context).push<ExpressionCheckInResult>(
      MaterialPageRoute(
        builder:
            widget.expressionScreenBuilder ??
            (_) => const PhotoExpressionScreen(),
      ),
    );
    if (!mounted ||
        _currentUserId() != userId ||
        generation != _moodV2RequestGeneration ||
        result?.completed != true ||
        result?.cue == null) {
      return;
    }
    setState(() {
      _expressionCue = result!.cue;
      _expressionCueSource = result.source;
      _expressionSuggestionAccepted = null;
    });
  }

  void _acceptExpressionSuggestion() {
    final cue = _expressionCue;
    if (cue == null) return;
    final suggestion = _suggestedMoodFor(cue);
    setState(() {
      _expressionSuggestionAccepted = true;
      if (suggestion != null) _selectedMood = suggestion;
    });
    if (suggestion != null) unawaited(_offerMoodReflection());
  }

  /// Today's confirmed mood, whichever writer produced it.
  ///
  /// `didChangeDependencies` clears both sources on an account switch, so this
  /// never carries another account's entry.
  _ConfirmedMood? get _confirmation {
    final v2Entry = _confirmedV2Entry;
    if (v2Entry != null) return _ConfirmedMood.fromV2(v2Entry);
    if (widget.moodV2WriterEnabled && !_usedLegacyMoodFallback) return null;
    final today = _todayMood;
    return today == null ? null : _ConfirmedMood.fromLegacy(today);
  }

  Future<void> _loadTodayMood(String userId) async {
    final generation = ++_todayLoadGeneration;
    if (widget.moodV2WriterEnabled) {
      if (MoodV2FeatureFlag.historyRead) {
        await _readProviderOrNull<MoodProvider>()?.loadMoodV2History(
          userId,
          now: _now,
        );
      }
      return;
    }
    final provider = _readProviderOrNull<MoodProvider>();
    if (provider == null) return;
    setState(() {
      _isLoadingToday = true;
      _todayError = null;
    });
    await provider.loadTodayMood(userId, now: _now);
    if (MoodV2FeatureFlag.historyRead) {
      await provider.loadMoodV2History(userId, now: _now);
    }
    if (!mounted ||
        generation != _todayLoadGeneration ||
        _currentUserId() != userId) {
      return;
    }
    setState(() {
      _isLoadingToday = false;
      _todayMood = provider.todayMood;
      _todayError = provider.errorMessage;
    });
  }

  Future<void> _saveMood() async {
    final mood = _selectedMood;
    if (mood == null || _isSaving) return;

    final userId = _currentUserId();
    if (userId == null || userId.isEmpty) {
      _showSnack('Please sign in to save your mood.');
      return;
    }

    setState(() => _isSaving = true);
    if (widget.moodV2WriterEnabled) {
      await _saveMoodV2(userId, mood);
      return;
    }
    final moodProvider = _readProviderOrNull<MoodProvider>();
    if (moodProvider == null) {
      setState(() => _isSaving = false);
      _showSnack('Unable to save mood.');
      return;
    }
    final referenceNow = _now;
    final generation = _moodV2RequestGeneration;

    final success = await moodProvider.logDailyMood(
      userId: userId,
      level: mood.level,
      label: mood.label,
      note: _noteController.text,
      entryMethod: _expressionCue == null ? null : 'expression_assisted',
      expressionAssistUsed: _expressionCue == null ? null : true,
      expressionSuggestionAccepted: _expressionCue == null
          ? null
          : _expressionSuggestionAccepted,
      expressionModelVersion: _expressionCueSource == ExpressionCueSource.tflite
          ? TfliteExpressionClassifier.modelVersion
          : null,
      now: referenceNow,
    );

    if (!_isCurrentMoodV2Request(userId, generation)) return;

    if (!success) {
      setState(() => _isSaving = false);
      _showSnack('Unable to save mood.');
      return;
    }

    var reportRefreshed = true;
    try {
      await _readProviderOrNull<UserProvider>()?.loadProfile(userId);
      if (!_isCurrentMoodV2Request(userId, generation)) return;
      await moodProvider.loadRecentMoods(userId, now: referenceNow);
      if (!_isCurrentMoodV2Request(userId, generation)) return;
      if (MoodV2FeatureFlag.historyRead && moodProvider.isMoodV2ReadEnabled) {
        await moodProvider.loadMoodV2History(userId, now: referenceNow);
      }
      if (!_isCurrentMoodV2Request(userId, generation)) return;
      await _readProviderOrNull<ReportProvider>()?.refreshWeeklyReport(userId);
      if (!_isCurrentMoodV2Request(userId, generation)) return;
      await _readProviderOrNull<InsightsProvider>()?.refreshLoadedContext(
        userId,
      );
    } catch (_) {
      reportRefreshed = false;
    }

    if (!_isCurrentMoodV2Request(userId, generation)) return;
    setState(() {
      _isSaving = false;
      _todayMood = moodProvider.todayMood;
      _selectedMood = null;
      _expressionCue = null;
      _expressionCueSource = null;
      _expressionSuggestionAccepted = null;
      _reflectionOffered = false;
      _noteController.clear();
      _noteLength = 0;
      _todayError = null;
    });
    if (widget.moodV2Presentation) _scrollToTop();
    _showSnack(
      reportRefreshed
          ? 'Mood check-in saved.'
          : 'Mood saved. Summary will update later.',
    );
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  void _startAdditionalMoodEntry() {
    setState(() {
      _confirmedV2Entry = null;
      _todayMood = null;
      _usedLegacyMoodFallback = false;
      _moodV2RequestId = null;
      _moodV2RetryDraft = null;
      _moodV2Error = null;
    });
    _scrollToTop();
  }

  Future<void> _saveMoodV2(String userId, _MoodChoice mood) async {
    final writer = widget.moodV2Writer ?? MoodV2Repository();
    final current = _MoodV2Draft(
      level: mood.level,
      label: mood.label,
      note: _noteController.text,
      entryMethod: _expressionCue == null ? 'manual' : 'expression_assisted',
      expressionAssistUsed: _expressionCue != null,
      expressionSuggestionAccepted: _expressionSuggestionAccepted ?? false,
      expressionModelVersion: _expressionCueSource == ExpressionCueSource.tflite
          ? TfliteExpressionClassifier.modelVersion
          : null,
    );
    // A true retry (same selection, same note) reuses the request ID so the
    // server can never create a duplicate. The moment the student edits the
    // selection or the note after a failure, the frozen draft would save a
    // mood they no longer chose, so rotate the ID and save what they picked.
    final previous = _moodV2RetryDraft;
    if (previous == null || !previous.matches(current)) {
      _moodV2RequestId = _newMoodV2RequestId();
      _moodV2RetryDraft = current;
    }
    final requestId = _moodV2RequestId!;
    final draft = _moodV2RetryDraft!;
    final requestGeneration = _moodV2RequestGeneration;
    try {
      final entry = await writer.create(
        level: draft.level,
        label: draft.label,
        note: draft.note,
        entryMethod: draft.entryMethod,
        expressionAssistUsed: draft.expressionAssistUsed,
        expressionSuggestionAccepted: draft.expressionSuggestionAccepted,
        expressionModelVersion: draft.expressionModelVersion,
        clientRequestId: requestId,
      );
      if (!_isCurrentMoodV2Request(userId, requestGeneration)) return;
      _confirmedV2Entry = entry;
      _reflectionOffered = false;
      _readProviderOrNull<MoodProvider>()?.recordConfirmedMoodV2Entry(entry);
      // Keep the stored day streak (reports, MindAid) in step with V2
      // check-ins. Never blocks or fails the confirmed save.
      unawaited(
        _readProviderOrNull<UserProvider>()?.markMoodCheckIn(userId) ??
            Future<void>.value(),
      );
    } catch (error) {
      if (!_isCurrentMoodV2Request(userId, requestGeneration)) return;
      if (_isMoodV2Refusal(error)) {
        // A refusal can never clear by retrying, so the check-in would be
        // lost. Write it through the legacy path instead.
        await _saveMoodV2ThroughLegacyWriter(userId, draft, requestGeneration);
        return;
      }
      setState(() {
        _isSaving = false;
        _moodV2Error = 'Unable to save this mood entry. Try again.';
      });
      return;
    }
    if (!_isCurrentMoodV2Request(userId, requestGeneration)) return;
    setState(() {
      _isSaving = false;
      _moodV2RequestId = null;
      _moodV2RetryDraft = null;
      _moodV2Error = null;
      _selectedMood = null;
      _expressionCue = null;
      _expressionCueSource = null;
      _expressionSuggestionAccepted = null;
      _noteController.clear();
      _noteLength = 0;
    });
    _scrollToTop();
    unawaited(_refreshAfterConfirmedMoodV2Write(userId, requestGeneration));
  }

  /// True when the callable refused the write outright: retrying the same
  /// request can never succeed, so the entry must go somewhere else.
  ///
  /// Transient failures (no network, timeout, `unavailable`, `internal`) are
  /// NOT refusals: those keep the retryable error and the frozen draft.
  static bool _isMoodV2Refusal(Object error) {
    if (error is TimeoutException) return false;
    if (FirebaseErrorMessage.isNetworkFailure(error)) return false;
    if (FirebaseErrorMessage.isAppCheckFailure(error)) return true;
    return const {
      'permission-denied',
      'failed-precondition',
      'unauthenticated',
    }.contains(FirebaseErrorMessage.codeOf(error));
  }

  /// Last-resort write for a refused V2 entry.
  ///
  /// Never records a confirmed V2 entry and never fabricates a [MoodV2Event]:
  /// the legacy entry is shown through [_ConfirmedMood.fromLegacy] only.
  Future<void> _saveMoodV2ThroughLegacyWriter(
    String userId,
    _MoodV2Draft draft,
    int requestGeneration,
  ) async {
    final moodProvider = _readProviderOrNull<MoodProvider>();
    if (moodProvider == null) {
      setState(() {
        _isSaving = false;
        _moodV2Error = 'Unable to save this mood entry. Try again.';
      });
      return;
    }
    final assisted = draft.expressionAssistUsed;
    final saved = await moodProvider.logDailyMood(
      userId: userId,
      level: draft.level,
      label: draft.label,
      note: draft.note,
      entryMethod: assisted ? 'expression_assisted' : null,
      expressionAssistUsed: assisted ? true : null,
      expressionSuggestionAccepted: assisted
          ? draft.expressionSuggestionAccepted
          : null,
      expressionModelVersion: draft.expressionModelVersion,
      now: _now,
    );
    if (!_isCurrentMoodV2Request(userId, requestGeneration)) return;
    if (!saved) {
      setState(() {
        _isSaving = false;
        _moodV2Error = 'Unable to save this mood entry. Try again.';
      });
      return;
    }
    // The legacy writer accepts one check-in per day. `created == false` means
    // today's entry already existed, so show that entry instead of claiming a
    // new save.
    final created = moodProvider.dailySaveResult?.created ?? true;
    final entry = moodProvider.dailySaveResult?.mood ?? moodProvider.todayMood;
    setState(() {
      _isSaving = false;
      _usedLegacyMoodFallback = true;
      _todayMood = entry;
      _confirmedV2Entry = null;
      _reflectionOffered = false;
      _moodV2RequestId = null;
      _moodV2RetryDraft = null;
      _moodV2Error = null;
      _selectedMood = null;
      _expressionCue = null;
      _expressionCueSource = null;
      _expressionSuggestionAccepted = null;
      _noteController.clear();
      _noteLength = 0;
    });
    _scrollToTop();
    _showSnack(
      created
          ? 'Mood check-in saved.'
          : 'You already have a check-in for today. Showing that entry.',
    );
  }

  Future<void> _refreshAfterConfirmedMoodV2Write(
    String userId,
    int requestGeneration,
  ) async {
    final insights = _readProviderOrNull<InsightsProvider>();
    insights?.invalidateForConfirmedMoodV2Write(userId);
    try {
      final mood = _readProviderOrNull<MoodProvider>();
      if (mood?.isMoodV2ReadEnabled ?? false) {
        await mood!.loadMoodV2History(userId, now: _now);
      }
      if (!_isCurrentMoodV2Request(userId, requestGeneration)) return;
      await insights?.refreshLoadedContext(userId);
    } catch (_) {
      // A confirmed write stays successful when a dependent read is unavailable.
      // Providers retain their own scoped error/last-successful-content state.
    }
  }

  bool _isCurrentMoodV2Request(String userId, int requestGeneration) =>
      mounted &&
      requestGeneration == _moodV2RequestGeneration &&
      _currentUserId() == userId;

  void _invalidateMoodV2Request() {
    _moodV2RequestGeneration++;
    _moodV2RequestId = null;
    _moodV2RetryDraft = null;
    _moodV2Error = null;
    _usedLegacyMoodFallback = false;
    _isSaving = false;
  }

  String _newMoodV2RequestId() {
    final supplied = widget.moodV2RequestIdGenerator?.call();
    if (supplied != null && supplied.isNotEmpty) return supplied;
    final random = math.Random.secure();
    String group(int length) => List.generate(
      length,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return '${group(8)}-${group(4)}-4${group(3)}-'
        '${(8 + random.nextInt(4)).toRadixString(16)}${group(3)}-${group(12)}';
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = _now;
    final manila = MoodRepository.manilaWallClock(now);
    final nextMidnight = DateTime(manila.year, manila.month, manila.day + 1);
    final delay = nextMidnight.difference(manila) + const Duration(seconds: 1);
    _midnightTimer = Timer(delay, () {
      if (!mounted) return;
      // V2 requests represent intentional events, not daily check-ins. Keep
      // their draft, frozen retry payload and pending response valid overnight.
      if (!widget.moodV2WriterEnabled) {
        setState(() {
          _todayMood = null;
          _selectedMood = null;
          _expressionCue = null;
          _expressionCueSource = null;
          _expressionSuggestionAccepted = null;
          _reflectionOffered = false;
          _invalidateMoodV2Request();
          _noteController.clear();
        });
      }
      final userId = _currentUserId();
      if (userId != null) _loadTodayMood(userId);
      _scheduleMidnightRefresh();
    });
  }

  String? _currentUserId({bool listen = false}) {
    final authProvider = _readProviderOrNull<AuthProvider>(listen: listen);
    final authUserId =
        authProvider?.userId ?? authProvider?.hydrateCurrentUser();
    if (authUserId != null && authUserId.isNotEmpty) return authUserId;

    final profileUserId = _readProviderOrNull<UserProvider>(
      listen: listen,
    )?.user?.id;
    if (profileUserId != null && profileUserId.isNotEmpty) return profileUserId;

    return null;
  }

  T? _readProviderOrNull<T>({bool listen = false}) {
    try {
      return listen ? context.watch<T>() : context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MoodV2Draft {
  const _MoodV2Draft({
    required this.level,
    required this.label,
    required this.note,
    required this.entryMethod,
    required this.expressionAssistUsed,
    required this.expressionSuggestionAccepted,
    required this.expressionModelVersion,
  });

  final int level;
  final String label;
  final String note;
  final String entryMethod;
  final bool expressionAssistUsed;
  final bool expressionSuggestionAccepted;
  final String? expressionModelVersion;

  /// Whether [other] would send the same payload, so a retry can safely reuse
  /// the same client request ID.
  bool matches(_MoodV2Draft other) =>
      level == other.level &&
      label == other.label &&
      note == other.note &&
      entryMethod == other.entryMethod &&
      expressionAssistUsed == other.expressionAssistUsed &&
      expressionSuggestionAccepted == other.expressionSuggestionAccepted &&
      expressionModelVersion == other.expressionModelVersion;
}

class _ExpressionCheckInEntry extends StatelessWidget {
  const _ExpressionCheckInEntry({
    this.compact = false,
    required this.enabled,
    required this.onPressed,
  });

  final bool compact;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: enabled ? onPressed : null,
            style: FilledButton.styleFrom(
              backgroundColor: MoodLogPalette.gold,
              foregroundColor: MoodLogPalette.ink,
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text(
              'Check expression with camera',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Optional. Your camera image is not saved.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: MoodLogPalette.bodyText),
          ),
        ],
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MoodLogPalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MoodLogPalette.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Check expression with camera'),
          ),
          const SizedBox(height: 6),
          const Text('Optional. Your camera image is not saved.'),
        ],
      ),
    );
  }
}

class _ExpressionCueCard extends StatelessWidget {
  const _ExpressionCueCard({
    required this.cue,
    required this.onAccepted,
    required this.onRejected,
    required this.onSkipped,
  });

  final ExpressionCue cue;
  final VoidCallback onAccepted;
  final VoidCallback onRejected;
  final VoidCallback onSkipped;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MoodLogPalette.goldSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _expressionCueMessage(cue),
            style: const TextStyle(
              color: MoodLogPalette.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text('Does this match how you feel?'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: onAccepted,
                child: const Text('Yes, somewhat'),
              ),
              OutlinedButton(
                onPressed: onRejected,
                child: const Text('Not really'),
              ),
              TextButton(onPressed: onSkipped, child: const Text('Skip')),
            ],
          ),
        ],
      ),
    );
  }
}

String _expressionCueMessage(ExpressionCue cue) => switch (cue) {
  ExpressionCue.positiveLike => 'Your visible expression appeared more upbeat.',
  ExpressionCue.neutralLike =>
    'Your visible expression appeared fairly neutral.',
  ExpressionCue.subduedLike =>
    'Your visible expression appeared a little subdued.',
  ExpressionCue.tenseLike => 'Your visible expression appeared more tense.',
  ExpressionCue.surprisedLike =>
    'Your visible expression appeared more surprised.',
  ExpressionCue.smiling => 'Smiling expression detected',
  ExpressionCue.noStrongExpression => 'No strong expression detected',
  ExpressionCue.unclear => 'Expression unclear',
};

_MoodChoice? _suggestedMoodFor(ExpressionCue cue) {
  final label = switch (cue) {
    ExpressionCue.positiveLike || ExpressionCue.smiling => 'Great',
    ExpressionCue.neutralLike || ExpressionCue.noStrongExpression => 'Okay',
    ExpressionCue.subduedLike => 'Sad',
    ExpressionCue.tenseLike => 'Stressed',
    _ => null,
  };
  if (label == null) return null;
  for (final choice in _moodChoices) {
    if (choice.label == label) return choice;
  }
  return null;
}

class _MoodLoadError extends StatelessWidget {
  const _MoodLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MoodLogPalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MoodLogPalette.softBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 38),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _DailyMoodResult extends StatelessWidget {
  const _DailyMoodResult({required this.mood, required this.currentStreak});

  final MoodModel mood;
  final int? currentStreak;

  @override
  Widget build(BuildContext context) {
    final choice = _choiceFor(mood);
    final note = (mood.note ?? '').trim();
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          decoration: BoxDecoration(
            color: MoodLogPalette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: MoodLogPalette.softBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              _MoodEmojiBadge(mood: choice, selected: true, size: 96),
              const SizedBox(height: 18),
              const Text(
                "Today's check-in is complete",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MoodLogPalette.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                mood.label?.trim().isNotEmpty == true
                    ? mood.label!.trim()
                    : choice.label,
                style: TextStyle(
                  color: choice.accentColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Saved at ${_timeLabel(mood.createdAt)}',
                style: const TextStyle(
                  color: MoodLogPalette.bodyText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (currentStreak != null) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      color: MoodLogPalette.goldText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$currentStreak-day mood streak',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: MoodLogPalette.fieldFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MoodLogPalette.softBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your private note',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(note, style: const TextStyle(height: 1.45)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'You can check in again tomorrow. This is a wellness record, not a diagnosis.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MoodLogPalette.bodyText,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  static _MoodChoice _choiceFor(MoodModel mood) {
    for (final choice in _moodChoices) {
      if (choice.label.toLowerCase() == (mood.label ?? '').toLowerCase()) {
        return choice;
      }
    }
    return _moodChoices.reduce(
      (current, choice) =>
          (choice.level - mood.level).abs() < (current.level - mood.level).abs()
          ? choice
          : current,
    );
  }

  static String _timeLabel(DateTime instant) {
    final time = MoodRepository.manilaWallClock(instant);
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.hour >= 12 ? 'PM' : 'AM'}';
  }
}

class _MoodLogHeader extends StatelessWidget {
  const _MoodLogHeader({
    required this.showingResult,
    required this.v2,
    required this.now,
  });
  final bool v2;
  final DateTime now;

  final bool showingResult;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
        decoration: BoxDecoration(
          color: MoodLogPalette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: MoodLogPalette.softBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 14,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          children: [
            _HeaderBackButton(onPressed: () => Navigator.of(context).pop()),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showingResult
                        ? (v2 ? "Mood saved" : "Today's mood")
                        : 'Log your mood',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MoodLogPalette.ink,
                      fontSize: 20,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _todayLabel(now),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MoodLogPalette.bodyText,
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: MoodLogPalette.goldSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.self_improvement_rounded,
                color: MoodLogPalette.ink,
                size: 21,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _todayLabel(DateTime instant) {
    final now = MoodRepository.manilaWallClock(instant);
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }
}

class _HeaderBackButton extends StatelessWidget {
  const _HeaderBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MoodLogPalette.background,
          shape: BoxShape.circle,
          border: Border.all(color: MoodLogPalette.softBorder),
        ),
        child: IconButton(
          onPressed: onPressed,
          tooltip: 'Back',
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: MoodLogPalette.ink,
            size: 22,
          ),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _MoodLogIntro extends StatelessWidget {
  const _MoodLogIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: MoodLogPalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MoodLogPalette.softBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showArt = constraints.maxWidth >= 360;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How are you feeling?',
                      style: TextStyle(
                        color: MoodLogPalette.ink,
                        fontSize: 26,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Choose the closest match, then add a few words if you want.',
                      style: TextStyle(
                        color: MoodLogPalette.bodyText,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (showArt) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 96,
                  height: 76,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const _CalmCloudIllustration(),
                      Positioned(
                        right: 4,
                        top: 3,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            color: MoodLogPalette.goldSoft,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.favorite_rounded,
                            color: MoodLogPalette.goldText,
                            size: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MoodSectionTitle extends StatelessWidget {
  const _MoodSectionTitle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 2, bottom: 10),
      child: Text(
        'Pick one',
        style: TextStyle(
          color: MoodLogPalette.subtleText,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _MoodChoiceGrid extends StatelessWidget {
  final bool compact;
  const _MoodChoiceGrid({
    this.compact = false,
    required this.selectedMood,
    required this.onSelected,
    required this.isEnabled,
  });

  final _MoodChoice? selectedMood;
  final ValueChanged<_MoodChoice> onSelected;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = !compact && constraints.maxWidth >= 720 ? 3 : 2;
        final gap = constraints.maxWidth >= 720 ? 14.0 : 10.0;
        final cardWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact) const _MoodSectionTitle(),
            Wrap(
              alignment: WrapAlignment.center,
              runSpacing: gap,
              spacing: gap,
              children: [
                for (final mood in _moodChoices)
                  SizedBox(
                    width: compact && mood == _moodChoices.last
                        ? constraints.maxWidth
                        : cardWidth,
                    child: _MoodChoiceCard(
                      compact: compact,
                      mood: mood,
                      selected: mood == selectedMood,
                      onTap: isEnabled ? () => onSelected(mood) : null,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _MoodChoiceCard extends StatelessWidget {
  final bool compact;
  const _MoodChoiceCard({
    this.compact = false,
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  final _MoodChoice mood;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (this.compact) {
          return Semantics(
            button: true,
            selected: selected,
            label: mood.label,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  key: ValueKey('mood-card-${mood.label}'),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(10),
                  constraints: BoxConstraints(
                    minHeight: mood == _moodChoices.last ? 60 : 80,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? MoodLogPalette.fieldFill
                        : const Color(0xFFFFFEFA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? MoodLogPalette.goldText
                          : MoodLogPalette.softBorder,
                      width: selected ? 2 : 1.2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0C17120A),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: _MoodEmojiBadge(
                          mood: mood,
                          selected: selected,
                          size: 42,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mood.label,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: MoodLogPalette.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              mood.description,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.25,
                                color: MoodLogPalette.bodyText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        const Icon(
                          Icons.check_circle,
                          color: MoodLogPalette.goldText,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        final compact = constraints.maxWidth < 180;
        final glyphSize = compact ? 52.0 : 62.0;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: AnimatedContainer(
              key: ValueKey('mood-card-${mood.label}'),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: compact ? 148 : 158,
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 12,
                compact ? 11 : 13,
                compact ? 10 : 12,
                compact ? 10 : 12,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? MoodLogPalette.goldSoft
                    : MoodLogPalette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? MoodLogPalette.gold
                      : MoodLogPalette.softBorder,
                  width: selected ? 2 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: selected
                        ? MoodLogPalette.gold.withValues(alpha: 0.2)
                        : const Color(0x10000000),
                    blurRadius: selected ? 16 : 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MoodEmojiBadge(
                    mood: mood,
                    selected: selected,
                    size: glyphSize,
                  ),
                  const SizedBox(height: 9),
                  Text(
                    mood.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MoodLogPalette.ink,
                      fontSize: compact ? 15 : 16,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Flexible(
                    child: Text(
                      mood.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: MoodLogPalette.bodyText,
                        fontSize: compact ? 10.5 : 11.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MoodEmojiBadge extends StatelessWidget {
  const _MoodEmojiBadge({
    required this.mood,
    required this.selected,
    required this.size,
  });

  final _MoodChoice mood;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? Colors.white.withValues(alpha: 0.74) : mood.auraColor,
        boxShadow: selected
            ? [
                BoxShadow(
                  color: mood.accentColor.withValues(alpha: 0.18),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Center(
        child: SizedBox.square(
          dimension: size * .72,
          child: CustomPaint(
            painter: MoodGlyphPainter(
              glyph: mood.glyph,
              accentColor: mood.accentColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _ThoughtsBox extends StatelessWidget {
  final bool compact;
  const _ThoughtsBox({
    super.key,
    this.focusNode,
    this.compact = false,
    required this.controller,
    required this.characterCount,
    required this.isEnabled,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final int characterCount;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: isEnabled,
        maxLength: 300,
        minLines: 1,
        maxLines: 5,
        decoration: InputDecoration(
          hintText: 'Add a note (optional)',
          prefixIcon: const Icon(Icons.edit_outlined),
          filled: true,
          fillColor: MoodLogPalette.fieldFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: MoodLogPalette.softBorder),
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: MoodLogPalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MoodLogPalette.softBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.edit_note_rounded,
                color: MoodLogPalette.goldText,
                size: 22,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "What's on your mind today?",
                  style: TextStyle(
                    color: MoodLogPalette.ink,
                    fontSize: 17,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: MoodLogPalette.fieldFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MoodLogPalette.softBorder),
            ),
            child: TextField(
              controller: controller,
              enabled: isEnabled,
              maxLength: 300,
              maxLines: 5,
              minLines: 3,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(14, 12, 14, 12),
                hintText: 'Share your thoughts...',
                hintStyle: TextStyle(
                  color: MoodLogPalette.hintText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: const TextStyle(
                color: MoodLogPalette.bodyText,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$characterCount/300 characters',
              style: const TextStyle(
                color: MoodLogPalette.subtleText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveMoodButton extends StatelessWidget {
  const _SaveMoodButton({
    required this.isEnabled,
    required this.isSaving,
    required this.onPressed,
    required this.label,
  });

  final bool isEnabled;
  final bool isSaving;
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isEnabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: MoodLogPalette.gold,
          foregroundColor: MoodLogPalette.ink,
          disabledBackgroundColor: MoodLogPalette.softBorder,
          disabledForegroundColor: MoodLogPalette.subtleText,
          elevation: isEnabled ? 5 : 0,
          shadowColor: const Color(0x33000000),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        child: isSaving
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : Text(label),
      ),
    );
  }
}

class _CalmCloudIllustration extends StatelessWidget {
  const _CalmCloudIllustration();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _CalmCloudPainter());
  }
}

class _CalmCloudPainter extends CustomPainter {
  const _CalmCloudPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 360, size.height / 190);
    canvas.save();
    canvas.translate((size.width - 360 * scale) / 2, size.height - 190 * scale);
    canvas.scale(scale);

    _drawLeaves(canvas, const Offset(58, 150), -1);
    _drawLeaves(canvas, const Offset(302, 150), 1);
    _drawSpark(canvas, const Offset(102, 26), 9);
    _drawSpark(canvas, const Offset(284, 50), 7);
    _drawSpark(canvas, const Offset(322, 22), 5);

    final cloudPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFE389), Color(0xFFFFC442), Color(0xFFFFB929)],
      ).createShader(const Rect.fromLTWH(70, 48, 220, 126));
    for (final circle in const [
      (Offset(132, 118), 62.0),
      (Offset(180, 82), 74.0),
      (Offset(226, 124), 60.0),
      (Offset(101, 145), 48.0),
      (Offset(260, 150), 48.0),
      (Offset(179, 151), 66.0),
    ]) {
      canvas.drawCircle(circle.$1, circle.$2, cloudPaint);
    }

    final face = Paint()
      ..color = MoodLogPalette.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      const Rect.fromLTWH(142, 88, 28, 22),
      0,
      math.pi,
      false,
      face,
    );
    canvas.drawArc(
      const Rect.fromLTWH(198, 88, 28, 22),
      0,
      math.pi,
      false,
      face,
    );
    canvas.drawArc(
      const Rect.fromLTWH(168, 116, 36, 26),
      0,
      math.pi,
      false,
      face,
    );

    final heart = Path()
      ..moveTo(180, 158)
      ..cubicTo(155, 140, 148, 118, 168, 112)
      ..cubicTo(176, 109, 181, 116, 184, 124)
      ..cubicTo(189, 116, 197, 109, 206, 113)
      ..cubicTo(224, 121, 210, 146, 180, 158);
    canvas.drawPath(heart, Paint()..color = Colors.white);

    final cheek = Paint()
      ..color = const Color(0xFFF2AA27).withValues(alpha: .42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      const Rect.fromLTWH(106, 121, 58, 42),
      -.1,
      2.1,
      false,
      cheek,
    );
    canvas.drawArc(
      const Rect.fromLTWH(215, 121, 58, 42),
      1.0,
      2.0,
      false,
      cheek,
    );
    canvas.restore();
  }

  void _drawLeaves(Canvas canvas, Offset root, int direction) {
    final stem = Paint()
      ..color = direction < 0
          ? const Color(0xFFFFCC4D)
          : const Color(0xFFD2D2D2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(root, root + Offset(42.0 * direction, -88), stem);
    final leafPaint = Paint()
      ..color = direction < 0
          ? const Color(0xFFFFD45B)
          : const Color(0xFFD8D8D8)
      ..style = PaintingStyle.fill;
    for (var i = 0; i < 5; i++) {
      final center = root + Offset(direction * (12 + i * 8), -20.0 - i * 16);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(direction * (.7 - i * .08));
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 18, height: 42),
        leafPaint,
      );
      canvas.restore();
    }
  }

  void _drawSpark(Canvas canvas, Offset center, double radius) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(
        center.dx + 3,
        center.dy - 3,
        center.dx + radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx + 3,
        center.dy + 3,
        center.dx,
        center.dy + radius,
      )
      ..quadraticBezierTo(
        center.dx - 3,
        center.dy + 3,
        center.dx - radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx - 3,
        center.dy - 3,
        center.dx,
        center.dy - radius,
      );
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFD565));
  }

  @override
  bool shouldRepaint(covariant _CalmCloudPainter oldDelegate) => false;
}

class _MoodChoice {
  const _MoodChoice({
    required this.label,
    required this.description,
    required this.level,
    required this.glyph,
    required this.auraColor,
    required this.accentColor,
  });

  final String label;
  final String description;
  final int level;
  final MoodGlyph glyph;
  final Color auraColor;
  final Color accentColor;
}

const _moodChoices = [
  _MoodChoice(
    label: 'Great',
    description: 'Feeling good and positive',
    level: 5,
    glyph: MoodGlyph.great,
    auraColor: Color(0xFFE4F3D0),
    accentColor: Color(0xFF78A94E),
  ),
  _MoodChoice(
    label: 'Okay',
    description: "It's a normal, average day",
    level: 4,
    glyph: MoodGlyph.okay,
    auraColor: Color(0xFFDCECF7),
    accentColor: Color(0xFF5E95BC),
  ),
  _MoodChoice(
    label: 'Stressed',
    description: 'Feeling overwhelmed or anxious',
    level: 2,
    glyph: MoodGlyph.stressed,
    auraColor: Color(0xFFE4DDF4),
    accentColor: Color(0xFF8F76C2),
  ),
  _MoodChoice(
    label: 'Sad',
    description: 'Feeling down or low',
    level: 1,
    glyph: MoodGlyph.sad,
    auraColor: Color(0xFFF4E7C8),
    accentColor: Color(0xFFC89F3A),
  ),
  _MoodChoice(
    label: 'Angry',
    description: 'Frustrated or irritated',
    level: 1,
    glyph: MoodGlyph.angry,
    auraColor: Color(0xFFFFDED5),
    accentColor: Color(0xFFE3704D),
  ),
  _MoodChoice(
    label: 'Tired',
    description: 'Mentally or physically drained',
    level: 3,
    glyph: MoodGlyph.tired,
    auraColor: Color(0xFFE1DDF0),
    accentColor: Color(0xFF8072A8),
  ),
  _MoodChoice(
    label: 'Excited',
    description: 'Looking forward to something',
    level: 5,
    glyph: MoodGlyph.excited,
    auraColor: Color(0xFFFFEBC2),
    accentColor: Color(0xFFD99B20),
  ),
];

class MoodLogPalette {
  const MoodLogPalette._();

  static const background = Color(0xFFF7F1DF);
  static const surface = Color(0xFFFFFFFF);
  static const fieldFill = Color(0xFFFFFCF4);
  static const softBorder = Color(0xFFE9DFC6);
  static const ink = Color(0xFF17120A);
  static const bodyText = Color(0xFF5F655D);
  static const subtleText = Color(0xFF8B7A58);
  static const hintText = Color(0xFF9A9489);
  static const gold = Color(0xFFFFC414);
  static const goldSoft = Color(0xFFFFE8A3);
  static const goldText = Color(0xFFB78306);
  static const green = Color(0xFF2F7D6D);
  static const greenSoft = Color(0xFFDCEEE5);
}

class _MoodCheckInSummary extends StatelessWidget {
  const _MoodCheckInSummary({
    required this.history,
    required this.userId,
    required this.now,
    required this.isLoading,
    required this.canCheckInAgain,
    this.error,
  });

  /// False when the protected writer is off: the legacy writer accepts one
  /// check-in per day, so the copy must not invite another.
  final bool canCheckInAgain;
  final MoodHistoryWindow? history;
  final String? userId;
  final DateTime now;
  final bool isLoading;
  final String? error;
  @override
  Widget build(BuildContext context) {
    final safe =
        userId != null &&
            history != null &&
            history!.events.every((e) => e.userId == userId)
        ? history
        : null;
    final today = MoodManilaCalendar.dateKeyForInstant(now);
    final count =
        safe?.uniqueEvents.where((e) => e.dateKey == today).length ?? 0;
    final streak = safe == null
        ? 0
        : MoodAnalytics.streak(safe, referenceInstant: now).currentDays;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: MoodLogPalette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MoodLogPalette.gold, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: MoodLogPalette.gold.withValues(alpha: .24),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.event_available_outlined,
                color: MoodLogPalette.goldText,
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My Mood Journey',
                      style: TextStyle(
                        fontSize: 18,
                        color: MoodLogPalette.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      error != null
                          ? 'Check-in summary unavailable'
                          : isLoading && safe == null
                          ? 'Loading check-ins…'
                          : '$count check-ins today',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Mood streak · $streak ${streak == 1 ? 'day' : 'days'}',
                    ),
                    if (safe?.coverage == MoodHistoryCoverage.partial)
                      const Text(
                        'Based on loaded entries',
                        style: TextStyle(fontSize: 11),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: MoodLogPalette.ink,
              ),
            ],
          ),
        ),
        if (canCheckInAgain) ...[
          const SizedBox(height: 8),
          const Text(
            'You can check in again whenever you need.',
            style: TextStyle(fontSize: 12, color: MoodLogPalette.bodyText),
          ),
        ],
      ],
    );
  }
}

/// A saved mood, with no claim about which writer produced it.
///
/// Built from a [MoodV2Event] when the protected writer is on, and from the
/// legacy [MoodModel] when it is off. Nothing fabricates a [MoodV2Event] from
/// a legacy entry: a synthetic event would carry an invented id, dateKey and
/// clientRequestId and could leak into combined history.
class _ConfirmedMood {
  const _ConfirmedMood({required this.occurredAt, this.label, this.note});

  factory _ConfirmedMood.fromV2(MoodV2Event entry) => _ConfirmedMood(
    occurredAt: entry.occurredAt,
    label: entry.label,
    note: entry.note,
  );

  factory _ConfirmedMood.fromLegacy(MoodModel mood) => _ConfirmedMood(
    occurredAt: mood.createdAt,
    // saveDailyMood stores `label?.trim() ?? ''`, so a legacy entry can carry
    // a blank label. Fall back to the level's own label rather than render an
    // empty pill with no emoji.
    label: _nonBlank(mood.label) ?? _labelForLevel(mood.level),
    note: mood.note,
  );

  static String? _nonBlank(String? value) {
    final trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Levels 1 and 2 are shared by more than one choice, so only an
  /// unambiguous level yields a label.
  static String? _labelForLevel(int level) {
    final matches = _moodChoices.where((m) => m.level == level).toList();
    return matches.length == 1 ? matches.single.label : null;
  }

  final DateTime occurredAt;
  final String? label;
  final String? note;
}

class _MoodSaved extends StatelessWidget {
  const _MoodSaved({
    required this.confirmation,
    required this.onAnother,
    required this.onJourney,
    required this.onHome,
    this.historyError,
    required this.onRetryHistory,
  });
  final _ConfirmedMood confirmation;

  /// Null when the protected writer is off: the legacy writer accepts one
  /// check-in per day, so a second entry must not be offered.
  final VoidCallback? onAnother;
  final VoidCallback onJourney, onHome, onRetryHistory;
  final String? historyError;
  @override
  Widget build(BuildContext context) {
    final choice = _moodChoices
        .where((m) => m.label == confirmation.label)
        .firstOrNull;
    final time = TimeOfDay.fromDateTime(
      MoodRepository.manilaWallClock(confirmation.occurredAt),
    ).format(context);
    final note = (confirmation.note ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('mood-v2-confirmation'),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFEFA),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: MoodLogPalette.softBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1017120A),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 56,
                color: MoodLogPalette.goldText,
              ),
              const SizedBox(height: 16),
              const Text(
                'Your mood is recorded',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: MoodLogPalette.ink,
                ),
              ),
              const SizedBox(height: 20),
              if (choice != null)
                _MoodEmojiBadge(mood: choice, selected: false, size: 80),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: choice?.auraColor ?? MoodLogPalette.goldSoft,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  confirmation.label ?? 'Mood entry',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  note,
                  key: const ValueKey('mood-confirmation-note'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: MoodLogPalette.bodyText,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Thank you for checking in with yourself.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: MoodLogPalette.bodyText),
              ),
              const SizedBox(height: 10),
              Text(
                '$time · Manila time',
                style: const TextStyle(color: MoodLogPalette.bodyText),
              ),
            ],
          ),
        ),
        if (onAnother != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MoodLogPalette.goldSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  color: MoodLogPalette.goldText,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You can check in again if your feelings change.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('mood-v2-add-entry'),
            onPressed: onAnother,
            style: FilledButton.styleFrom(
              backgroundColor: MoodLogPalette.gold,
              foregroundColor: MoodLogPalette.ink,
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.add),
            label: const Text(
              'Log another mood',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onJourney,
          style: OutlinedButton.styleFrom(
            foregroundColor: MoodLogPalette.goldText,
            side: const BorderSide(color: MoodLogPalette.goldText, width: 1.5),
            minimumSize: const Size.fromHeight(52),
          ),
          child: const Text(
            'View My Mood Journey',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        TextButton(
          onPressed: onHome,
          style: TextButton.styleFrom(
            foregroundColor: MoodLogPalette.goldText,
            minimumSize: const Size(48, 48),
          ),
          child: const Text('Return Home'),
        ),
        if (historyError != null) ...[
          Text(historyError!, textAlign: TextAlign.center),
          TextButton(
            onPressed: onRetryHistory,
            child: const Text('Retry history'),
          ),
        ],
        const Divider(color: MoodLogPalette.softBorder),
        const Text(
          'Your check-in is a personal record, not a diagnosis.',
          textAlign: TextAlign.center,
          style: TextStyle(color: MoodLogPalette.bodyText, fontSize: 12),
        ),
      ],
    );
  }
}
