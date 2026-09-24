import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../expression_check_in/expression_check_in_screen.dart';
import '../expression_check_in/expression_scan_logic.dart';
import '../expression_check_in/tflite_expression_classifier.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/mood_provider.dart';
import '../../../providers/report_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../models/mood_model.dart';
import '../../../repositories/mood_repository.dart';

const bool _expressionCheckInEnabled = true;

class LogMoodScreen extends StatefulWidget {
  const LogMoodScreen({
    super.key,
    DateTime Function()? nowProvider,
    this.expressionScreenBuilder,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  final DateTime Function() _nowProvider;
  final WidgetBuilder? expressionScreenBuilder;

  @override
  State<LogMoodScreen> createState() => _LogMoodScreenState();
}

class _LogMoodScreenState extends State<LogMoodScreen>
    with WidgetsBindingObserver {
  final TextEditingController _noteController = TextEditingController();
  _MoodChoice? _selectedMood;
  ExpressionCue? _expressionCue;
  ExpressionCueSource? _expressionCueSource;
  bool? _expressionSuggestionAccepted;
  int _noteLength = 0;
  bool _isSaving = false;
  bool _isLoadingToday = false;
  String? _todayError;
  MoodModel? _todayMood;
  String? _loadedUserId;
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
    final userId = _currentUserId();
    if (userId == null || userId.isEmpty || _loadedUserId == userId) return;
    _loadedUserId = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadTodayMood(userId);
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
    _noteController
      ..removeListener(_handleNoteChanged)
      ..dispose();
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  void _handleNoteChanged() {
    if (_noteLength == _noteController.text.length) return;
    setState(() => _noteLength = _noteController.text.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MoodLogPalette.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _MoodLogHeader(showingResult: _todayMood != null),
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
    if (_isLoadingToday) {
      return const SizedBox(
        height: 360,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_todayError != null) {
      return _MoodLoadError(
        message: _todayError!,
        onRetry: () {
          final userId = _currentUserId();
          if (userId != null) _loadTodayMood(userId);
        },
      );
    }
    if (_todayMood != null) {
      return _DailyMoodResult(
        mood: _todayMood!,
        currentStreak: _readProviderOrNull<UserProvider>()?.user?.dayStreak,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _MoodLogIntro(),
        const SizedBox(height: 16),
        _MoodChoiceGrid(
          selectedMood: _selectedMood,
          isEnabled: !_isSaving,
          onSelected: (mood) => setState(() => _selectedMood = mood),
        ),
        if (_expressionCheckInEnabled &&
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS)) ...[
          const SizedBox(height: 18),
          _ExpressionCheckInEntry(
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
        _ThoughtsBox(
          controller: _noteController,
          characterCount: _noteLength,
          isEnabled: !_isSaving,
        ),
        const SizedBox(height: 18),
        _SaveMoodButton(
          isEnabled:
              _selectedMood != null &&
              !_isSaving &&
              (_expressionCue == null || _expressionSuggestionAccepted != null),
          isSaving: _isSaving,
          onPressed: _saveMood,
        ),
      ],
    );
  }

  Future<void> _openExpressionCheckIn() async {
    final result = await Navigator.of(context).push<ExpressionCheckInResult>(
      MaterialPageRoute(
        builder:
            widget.expressionScreenBuilder ??
            (_) => const ExpressionCheckInScreen(),
      ),
    );
    if (!mounted || result?.completed != true || result?.cue == null) return;
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
  }

  Future<void> _loadTodayMood(String userId) async {
    final provider = _readProviderOrNull<MoodProvider>();
    if (provider == null) return;
    setState(() {
      _isLoadingToday = true;
      _todayError = null;
    });
    await provider.loadTodayMood(userId, now: _now);
    if (!mounted) return;
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

    final moodProvider = _readProviderOrNull<MoodProvider>();
    if (moodProvider == null) {
      _showSnack('Unable to save mood.');
      return;
    }

    setState(() => _isSaving = true);
    final referenceNow = _now;

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

    if (!mounted) return;

    if (!success) {
      setState(() => _isSaving = false);
      _showSnack('Unable to save mood.');
      return;
    }

    var reportRefreshed = true;
    try {
      await _readProviderOrNull<UserProvider>()?.loadProfile(userId);
      await moodProvider.loadRecentMoods(userId, now: referenceNow);
      await _readProviderOrNull<ReportProvider>()?.refreshWeeklyReport(userId);
    } catch (_) {
      reportRefreshed = false;
    }

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _todayMood = moodProvider.todayMood;
      _selectedMood = null;
      _expressionCue = null;
      _expressionCueSource = null;
      _expressionSuggestionAccepted = null;
      _noteController.clear();
      _noteLength = 0;
      _todayError = null;
    });
    _showSnack(
      reportRefreshed
          ? 'Mood check-in saved.'
          : 'Mood saved. Summary will update later.',
    );
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = _now;
    final manila = MoodRepository.manilaWallClock(now);
    final nextMidnight = DateTime(manila.year, manila.month, manila.day + 1);
    final delay = nextMidnight.difference(manila) + const Duration(seconds: 1);
    _midnightTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {
        _todayMood = null;
        _selectedMood = null;
        _expressionCue = null;
        _expressionCueSource = null;
        _expressionSuggestionAccepted = null;
        _noteController.clear();
      });
      final userId = _currentUserId();
      if (userId != null) _loadTodayMood(userId);
      _scheduleMidnightRefresh();
    });
  }

  String? _currentUserId() {
    final authProvider = _readProviderOrNull<AuthProvider>();
    final authUserId =
        authProvider?.userId ?? authProvider?.hydrateCurrentUser();
    if (authUserId != null && authUserId.isNotEmpty) return authUserId;

    final profileUserId = _readProviderOrNull<UserProvider>()?.user?.id;
    if (profileUserId != null && profileUserId.isNotEmpty) return profileUserId;

    return null;
  }

  T? _readProviderOrNull<T>() {
    try {
      return context.read<T>();
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

class _ExpressionCheckInEntry extends StatelessWidget {
  const _ExpressionCheckInEntry({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
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
        color: MoodLogPalette.greenSoft,
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
                      '$currentStreak-day activity streak',
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
  const _MoodLogHeader({required this.showingResult});

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
                    showingResult ? "Today's mood" : 'Log your mood',
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
                    _todayLabel(),
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

  static String _todayLabel() {
    final now = MoodRepository.manilaWallClock(DateTime.now());
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

    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day} check-in';
  }
}

class _HeaderBackButton extends StatelessWidget {
  const _HeaderBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
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
                            color: MoodLogPalette.greenSoft,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.favorite_rounded,
                            color: MoodLogPalette.green,
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
  const _MoodChoiceGrid({
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
        final columns = constraints.maxWidth >= 720 ? 3 : 2;
        final gap = constraints.maxWidth >= 720 ? 14.0 : 10.0;
        final cardWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _MoodSectionTitle(),
            Wrap(
              alignment: WrapAlignment.center,
              runSpacing: gap,
              spacing: gap,
              children: [
                for (final mood in _moodChoices)
                  SizedBox(
                    width: cardWidth,
                    child: _MoodChoiceCard(
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
  const _MoodChoiceCard({
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
        final compact = constraints.maxWidth < 180;
        final glyphSize = compact ? 52.0 : 62.0;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: AnimatedContainer(
              key: ValueKey('mood-card-${mood.label}'),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: compact ? 148 : 158,
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 12,
                compact ? 11 : 13,
                compact ? 10 : 12,
                compact ? 10 : 12,
              ),
              decoration: BoxDecoration(
                color: selected ? mood.auraColor : MoodLogPalette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? mood.accentColor
                      : MoodLogPalette.softBorder,
                  width: selected ? 2 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: selected
                        ? mood.accentColor.withValues(alpha: 0.2)
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
      duration: const Duration(milliseconds: 180),
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
            painter: _MoodGlyphPainter(
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
  const _ThoughtsBox({
    required this.controller,
    required this.characterCount,
    required this.isEnabled,
  });

  final TextEditingController controller;
  final int characterCount;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
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
  });

  final bool isEnabled;
  final bool isSaving;
  final VoidCallback onPressed;

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
            : const Text('Save mood check-in'),
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

class _MoodGlyphPainter extends CustomPainter {
  const _MoodGlyphPainter({required this.glyph, required this.accentColor});

  final _MoodGlyph glyph;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (glyph == _MoodGlyph.excited) {
      _drawParty(canvas, size);
      return;
    }

    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * .42;
    final faceRect = Rect.fromCircle(center: center, radius: radius);
    final facePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.35, -.35),
        radius: .9,
        colors: [
          const Color(0xFFFFF3AC),
          accentColor.withValues(alpha: .7),
          const Color(0xFFFFBC3F),
        ],
        stops: const [0, .62, 1],
      ).createShader(faceRect);

    canvas.drawCircle(center, radius, facePaint);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, size.width * .018)
        ..color = const Color(0xFFFFB42E),
    );

    switch (glyph) {
      case _MoodGlyph.great:
        _drawGreat(canvas, size, center, radius);
      case _MoodGlyph.okay:
        _drawOkay(canvas, size, center, radius);
      case _MoodGlyph.stressed:
        _drawStressed(canvas, size, center, radius);
      case _MoodGlyph.sad:
        _drawSad(canvas, size, center, radius);
      case _MoodGlyph.angry:
        _drawAngry(canvas, size, center, radius);
      case _MoodGlyph.tired:
        _drawTired(canvas, size, center, radius);
      case _MoodGlyph.excited:
        break;
    }
  }

  Paint get _ink => Paint()
    ..color = MoodLogPalette.ink
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _drawGreat(Canvas canvas, Size size, Offset center, double radius) {
    final ink = _ink..strokeWidth = size.width * .055;
    _drawHappyEyes(canvas, center, radius, ink);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .2),
        width: radius * 1.18,
        height: radius * .82,
      ),
      .08,
      math.pi - .16,
      false,
      ink,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .28),
        width: radius * .92,
        height: radius * .42,
      ),
      .08,
      math.pi - .16,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .04
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawOkay(Canvas canvas, Size size, Offset center, double radius) {
    final fill = Paint()..color = MoodLogPalette.ink;
    canvas.drawCircle(
      Offset(center.dx - radius * .34, center.dy - radius * .12),
      radius * .085,
      fill,
    );
    canvas.drawCircle(
      Offset(center.dx + radius * .34, center.dy - radius * .12),
      radius * .085,
      fill,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .17),
        width: radius * .82,
        height: radius * .52,
      ),
      .12,
      math.pi - .24,
      false,
      _ink..strokeWidth = size.width * .04,
    );
  }

  void _drawStressed(Canvas canvas, Size size, Offset center, double radius) {
    final ink = _ink..strokeWidth = size.width * .048;
    canvas.drawLine(
      Offset(center.dx - radius * .54, center.dy - radius * .48),
      Offset(center.dx - radius * .18, center.dy - radius * .34),
      ink,
    );
    canvas.drawLine(
      Offset(center.dx + radius * .54, center.dy - radius * .48),
      Offset(center.dx + radius * .18, center.dy - radius * .34),
      ink,
    );
    _drawDotEyes(canvas, center, radius, radius * .085);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .5),
        width: radius * .86,
        height: radius * .7,
      ),
      math.pi + .2,
      math.pi - .4,
      false,
      ink,
    );
  }

  void _drawSad(Canvas canvas, Size size, Offset center, double radius) {
    _drawDotEyes(canvas, center, radius, radius * .09);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .52),
        width: radius * .86,
        height: radius * .72,
      ),
      math.pi + .2,
      math.pi - .4,
      false,
      _ink..strokeWidth = size.width * .045,
    );
  }

  void _drawAngry(Canvas canvas, Size size, Offset center, double radius) {
    final ink = _ink..strokeWidth = size.width * .052;
    canvas.drawLine(
      Offset(center.dx - radius * .54, center.dy - radius * .42),
      Offset(center.dx - radius * .16, center.dy - radius * .25),
      ink,
    );
    canvas.drawLine(
      Offset(center.dx + radius * .54, center.dy - radius * .42),
      Offset(center.dx + radius * .16, center.dy - radius * .25),
      ink,
    );
    _drawDotEyes(canvas, center, radius, radius * .08);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .52),
        width: radius * .72,
        height: radius * .62,
      ),
      math.pi + .14,
      math.pi - .28,
      false,
      ink,
    );
  }

  void _drawTired(Canvas canvas, Size size, Offset center, double radius) {
    final ink = _ink..strokeWidth = size.width * .042;
    _drawClosedEyes(canvas, center, radius, ink);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * .46),
        width: radius * .56,
        height: radius * .42,
      ),
      math.pi + .2,
      math.pi - .4,
      false,
      ink,
    );
    _drawZ(
      canvas,
      Offset(center.dx + radius * .68, center.dy - radius * .62),
      size.width * .18,
    );
    _drawZ(
      canvas,
      Offset(center.dx + radius * .9, center.dy - radius * .88),
      size.width * .23,
    );
  }

  void _drawParty(Canvas canvas, Size size) {
    final body = Path()
      ..moveTo(size.width * .28, size.height * .76)
      ..lineTo(size.width * .52, size.height * .18)
      ..lineTo(size.width * .72, size.height * .62)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF6FA7E8), Color(0xFFFFC24E), Color(0xFFF0808F)],
        ).createShader(Offset.zero & size),
    );
    final stripe = Paint()
      ..color = Colors.white.withValues(alpha: .72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .035
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * .39, size.height * .51),
      Offset(size.width * .58, size.height * .6),
      stripe,
    );
    canvas.drawLine(
      Offset(size.width * .45, size.height * .36),
      Offset(size.width * .62, size.height * .45),
      stripe,
    );
    for (final star in [
      Offset(size.width * .74, size.height * .22),
      Offset(size.width * .82, size.height * .42),
      Offset(size.width * .55, size.height * .1),
    ]) {
      _drawStar(canvas, star, size.width * .07, const Color(0xFFF4B844));
    }
    final confettiPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .025
      ..strokeCap = StrokeCap.round;
    for (final item in [
      (Offset(size.width * .34, size.height * .2), const Color(0xFF78B7AE)),
      (Offset(size.width * .7, size.height * .12), const Color(0xFFE88EA0)),
      (Offset(size.width * .26, size.height * .35), const Color(0xFFF6C24B)),
    ]) {
      confettiPaint.color = item.$2;
      canvas.drawLine(
        item.$1,
        item.$1 + Offset(size.width * .03, -size.height * .08),
        confettiPaint,
      );
    }
  }

  void _drawHappyEyes(Canvas canvas, Offset center, double radius, Paint ink) {
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx - radius * .34, center.dy - radius * .18),
        width: radius * .3,
        height: radius * .22,
      ),
      math.pi,
      math.pi,
      false,
      ink,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx + radius * .34, center.dy - radius * .18),
        width: radius * .3,
        height: radius * .22,
      ),
      math.pi,
      math.pi,
      false,
      ink,
    );
  }

  void _drawClosedEyes(Canvas canvas, Offset center, double radius, Paint ink) {
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx - radius * .32, center.dy - radius * .18),
        width: radius * .34,
        height: radius * .18,
      ),
      0,
      math.pi,
      false,
      ink,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx + radius * .32, center.dy - radius * .18),
        width: radius * .34,
        height: radius * .18,
      ),
      0,
      math.pi,
      false,
      ink,
    );
  }

  void _drawDotEyes(
    Canvas canvas,
    Offset center,
    double radius,
    double dotSize,
  ) {
    final fill = Paint()..color = MoodLogPalette.ink;
    canvas.drawCircle(
      Offset(center.dx - radius * .3, center.dy - radius * .08),
      dotSize,
      fill,
    );
    canvas.drawCircle(
      Offset(center.dx + radius * .3, center.dy - radius * .08),
      dotSize,
      fill,
    );
  }

  void _drawZ(Canvas canvas, Offset topLeft, double size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Z',
        style: TextStyle(
          color: const Color(0xFF9D8CC7),
          fontSize: size,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, topLeft);
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(
        center.dx + radius * .18,
        center.dy - radius * .18,
        center.dx + radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx + radius * .18,
        center.dy + radius * .18,
        center.dx,
        center.dy + radius,
      )
      ..quadraticBezierTo(
        center.dx - radius * .18,
        center.dy + radius * .18,
        center.dx - radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx - radius * .18,
        center.dy - radius * .18,
        center.dx,
        center.dy - radius,
      );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MoodGlyphPainter oldDelegate) {
    return oldDelegate.glyph != glyph || oldDelegate.accentColor != accentColor;
  }
}

enum _MoodGlyph { great, okay, stressed, sad, angry, tired, excited }

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
  final _MoodGlyph glyph;
  final Color auraColor;
  final Color accentColor;
}

const _moodChoices = [
  _MoodChoice(
    label: 'Great',
    description: 'Feeling good and positive',
    level: 5,
    glyph: _MoodGlyph.great,
    auraColor: Color(0xFFE4F3D0),
    accentColor: Color(0xFF78A94E),
  ),
  _MoodChoice(
    label: 'Okay',
    description: "It's a normal, average day",
    level: 4,
    glyph: _MoodGlyph.okay,
    auraColor: Color(0xFFDCECF7),
    accentColor: Color(0xFF5E95BC),
  ),
  _MoodChoice(
    label: 'Stressed',
    description: 'Feeling overwhelmed or anxious',
    level: 2,
    glyph: _MoodGlyph.stressed,
    auraColor: Color(0xFFE4DDF4),
    accentColor: Color(0xFF8F76C2),
  ),
  _MoodChoice(
    label: 'Sad',
    description: 'Feeling down or low',
    level: 1,
    glyph: _MoodGlyph.sad,
    auraColor: Color(0xFFF4E7C8),
    accentColor: Color(0xFFC89F3A),
  ),
  _MoodChoice(
    label: 'Angry',
    description: 'Frustrated or irritated',
    level: 1,
    glyph: _MoodGlyph.angry,
    auraColor: Color(0xFFFFDED5),
    accentColor: Color(0xFFE3704D),
  ),
  _MoodChoice(
    label: 'Tired',
    description: 'Mentally or physically drained',
    level: 3,
    glyph: _MoodGlyph.tired,
    auraColor: Color(0xFFE1DDF0),
    accentColor: Color(0xFF8072A8),
  ),
  _MoodChoice(
    label: 'Excited',
    description: 'Looking forward to something',
    level: 5,
    glyph: _MoodGlyph.excited,
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
  static const green = Color(0xFF4F8A70);
  static const greenSoft = Color(0xFFDCEEE5);
}
