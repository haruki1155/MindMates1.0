import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/mood_provider.dart';
import '../../../routes/route_names.dart';
import '../../home/widgets/home_dashboard_widgets.dart';
import '../domain/mood_journey_period.dart';
import '../domain/mood_v2_analytics.dart';
import '../widgets/mood_journey_calendar.dart';
import '../widgets/mood_journey_summary.dart';
import '../widgets/mood_v2_history_panel.dart';

class MoodJourneyScreen extends StatefulWidget {
  const MoodJourneyScreen({super.key, this.nowProvider, this.milestoneDays});
  final DateTime Function()? nowProvider;

  /// Set when opened from the Home milestone "View recap" (item 38).
  final int? milestoneDays;

  @override
  State<MoodJourneyScreen> createState() => _MoodJourneyScreenState();
}

class _MoodJourneyScreenState extends State<MoodJourneyScreen> {
  DateTime get _now => widget.nowProvider?.call() ?? DateTime.now();
  String get _todayDateKey => MoodManilaCalendar.dateKeyForInstant(_now);

  String? _loadedUser;
  DateTime? _displayedMonth;
  String? _selectedDateKey;
  Timer? _midnightTimer;

  DateTime get _effectiveDisplayedMonth {
    if (_displayedMonth != null) return _displayedMonth!;
    final today = MoodManilaCalendar.dateForKey(_todayDateKey);
    return DateTime.utc(today.year, today.month, 1);
  }

  String get _effectiveSelectedDateKey => _selectedDateKey ?? _todayDateKey;

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = _now.toUtc();
    final manila = now.add(const Duration(hours: 8));
    final next = DateTime.utc(
      manila.year,
      manila.month,
      manila.day + 1,
    ).subtract(const Duration(hours: 8));
    _midnightTimer = Timer(next.difference(now), () {
      if (!mounted) return;
      final uid = _provider<AuthProvider>(listen: false)?.authenticatedUserId;
      if (uid != null) {
        _loadHistoryAndCalendar(uid, _effectiveDisplayedMonth);
      }
      setState(() {});
      _scheduleMidnight();
    });
  }

  void _loadHistoryAndCalendar(String uid, DateTime month) {
    final mood = _provider<MoodProvider>(listen: false);
    if (mood == null) return;
    mood.loadMoodV2History(uid);
    _loadCalendarRange(uid, month);
  }

  void _loadCalendarRange(String uid, DateTime month) {
    final mood = _provider<MoodProvider>(listen: false);
    if (mood == null) return;
    final range = moodVisibleMonthRange(month);
    mood.loadMoodCalendarRange(
      uid,
      startDateKey: range.startDateKey,
      endExclusiveDateKey: range.endExclusiveDateKey,
    );
  }

  @override
  void initState() {
    super.initState();
    _scheduleMidnight();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    super.dispose();
  }

  T? _provider<T>({bool listen = true}) {
    try {
      return Provider.of<T>(context, listen: listen);
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = _provider<AuthProvider>()?.authenticatedUserId;
    if (uid == _loadedUser) return;
    _loadedUser = uid;
    final today = MoodManilaCalendar.dateForKey(_todayDateKey);
    _displayedMonth = DateTime.utc(today.year, today.month, 1);
    _selectedDateKey = _todayDateKey;
    if (uid != null) {
      final monthToLoad = _effectiveDisplayedMonth;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _provider<AuthProvider>(listen: false)?.authenticatedUserId ==
                uid) {
          _loadHistoryAndCalendar(uid, monthToLoad);
        }
      });
    }
  }

  void _handleMonthChanged(String uid, DateTime nextMonth) {
    final normalized = DateTime.utc(nextMonth.year, nextMonth.month, 1);
    final changed =
        normalized.year != _effectiveDisplayedMonth.year ||
        normalized.month != _effectiveDisplayedMonth.month;
    setState(() {
      _displayedMonth = normalized;
      _selectedDateKey = defaultSelectedDateKeyForMonth(
        displayedMonth: normalized,
        todayDateKey: _todayDateKey,
      );
    });
    if (changed) {
      _loadCalendarRange(uid, normalized);
    }
  }

  void _handleDaySelected(String uid, String dateKey) {
    final selectedDate = MoodManilaCalendar.dateForKey(dateKey);
    final targetMonth = DateTime.utc(selectedDate.year, selectedDate.month, 1);
    final monthChanged =
        targetMonth.year != _effectiveDisplayedMonth.year ||
        targetMonth.month != _effectiveDisplayedMonth.month;
    setState(() {
      _selectedDateKey = dateKey;
      _displayedMonth = targetMonth;
    });
    if (monthChanged) {
      _loadCalendarRange(uid, targetMonth);
    }
  }

  void _handleTodayPressed(String uid) {
    final todayKey = _todayDateKey;
    final today = MoodManilaCalendar.dateForKey(todayKey);
    final todayMonth = DateTime.utc(today.year, today.month, 1);
    final monthChanged =
        todayMonth.year != _effectiveDisplayedMonth.year ||
        todayMonth.month != _effectiveDisplayedMonth.month;
    setState(() {
      _selectedDateKey = todayKey;
      _displayedMonth = todayMonth;
    });
    if (monthChanged) {
      _loadCalendarRange(uid, todayMonth);
    }
  }

  MoodHistoryWindow? _resolveCalendarHistory({
    required String? uid,
    required MoodProvider? mood,
    required MoodHistoryWindow? safeRecentHistory,
    required DateTime displayedMonth,
  }) {
    if (uid == null || mood == null) return null;
    final visibleRange = moodVisibleMonthRange(displayedMonth);
    final rawCalendar = mood.moodCalendarHistory;
    final calendarMatchesOwner =
        rawCalendar != null &&
        rawCalendar.events.every((event) => event.userId == uid);
    final loadedStart = mood.loadedMoodCalendarStartKey;
    final loadedEnd = mood.loadedMoodCalendarEndExclusiveKey;
    final rangeMatches =
        loadedStart == null ||
        (loadedStart == visibleRange.startDateKey &&
            loadedEnd == visibleRange.endExclusiveDateKey);

    if (calendarMatchesOwner && rangeMatches) {
      final recentInRange =
          safeRecentHistory?.uniqueEvents
              .where((e) => visibleRange.includes(e.dateKey))
              .toList() ??
          const <NormalizedMoodEvent>[];
      if (recentInRange.isEmpty) {
        return rawCalendar;
      }
      final merged = MoodHistoryWindow(
        events: [...rawCalendar.events, ...recentInRange],
        coverage: rawCalendar.coverage,
      );
      return MoodHistoryWindow(
        events: merged.uniqueEvents,
        coverage: rawCalendar.coverage,
      );
    }

    if (!mood.isLoadingMoodCalendarRange &&
        mood.moodCalendarRangeError == null &&
        loadedStart == null &&
        safeRecentHistory != null &&
        safeRecentHistory.coverage == MoodHistoryCoverage.complete) {
      return MoodHistoryWindow(
        events: safeRecentHistory.uniqueEvents
            .where((e) => visibleRange.includes(e.dateKey))
            .toList(growable: false),
        coverage: safeRecentHistory.coverage,
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final uid = _provider<AuthProvider>()?.authenticatedUserId;
    final mood = _provider<MoodProvider>();
    final recentHistory = mood?.v2History;
    final safeRecentHistory =
        uid != null &&
            recentHistory != null &&
            recentHistory.events.every((event) => event.userId == uid)
        ? recentHistory
        : null;
    final displayedMonth = _effectiveDisplayedMonth;
    final selectedDateKey = _effectiveSelectedDateKey;
    final safeCalendarHistory = _resolveCalendarHistory(
      uid: uid,
      mood: mood,
      safeRecentHistory: safeRecentHistory,
      displayedMonth: displayedMonth,
    );
    final isCalendarLoading =
        (mood?.isLoadingMoodCalendarRange ?? false) ||
        (safeCalendarHistory == null && (mood?.isLoadingV2History ?? false));
    final calendarError =
        mood?.moodCalendarRangeError ??
        (safeCalendarHistory == null ? mood?.v2HistoryErrorMessage : null);

    return Scaffold(
      backgroundColor: HomePalette.background,
      appBar: AppBar(
        title: const Text(
          'My Mood Journey',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: HomePalette.surface,
        foregroundColor: HomePalette.text,
      ),
      body: uid == null
          ? const Center(child: Text('Sign in to view your mood journey.'))
          : !((mood?.isMoodV2ReadEnabled) ?? false)
          ? const Center(
              child: Text('Mood history is not available right now.'),
            )
          : ListView(
              cacheExtent: 1800,
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Your feelings, over time',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Notice your emotional patterns and small shifts throughout your days.',
                ),
                const SizedBox(height: 10),
                MoodJourneyCalendar(
                  displayedMonth: displayedMonth,
                  selectedDateKey: selectedDateKey,
                  todayDateKey: _todayDateKey,
                  history: safeCalendarHistory,
                  isLoading: isCalendarLoading,
                  errorMessage: calendarError,
                  onRetry: () => _loadHistoryAndCalendar(uid, displayedMonth),
                  onMonthChanged: (next) => _handleMonthChanged(uid, next),
                  onDaySelected: (dayKey) => _handleDaySelected(uid, dayKey),
                  onTodayPressed: () => _handleTodayPressed(uid),
                ),
                const SizedBox(height: 10),
                MoodV2HistoryPanel(
                  history: safeCalendarHistory,
                  isLoading: isCalendarLoading,
                  errorMessage: calendarError,
                  showPersonalDetails: true,
                  selectedDateKey: selectedDateKey,
                  referenceInstant: _now,
                  v2PersonalNotes: mood?.v2PersonalNotes ?? const {},
                  v2NoteLoadingDays: mood?.v2NoteLoadingDays ?? const {},
                  v2NoteErrorDays: mood?.v2NoteErrorDays ?? const {},
                  onExpandDay: (day) => mood?.loadMoodV2DayNotes(uid, day),
                  onRetry: () => _loadHistoryAndCalendar(uid, displayedMonth),
                  hasMore: false,
                  isLoadingMore: false,
                  paginationErrorMessage: null,
                ),
                if (safeCalendarHistory != null) ...[
                  const SizedBox(height: 10),
                  MoodJourneySummary(
                    key: ValueKey(uid),
                    history: safeCalendarHistory,
                    streakHistory: safeRecentHistory ?? safeCalendarHistory,
                    now: _now,
                    selectedDateKey: selectedDateKey,
                    displayedMonth: displayedMonth,
                    showWeekRecap: true,
                    milestoneDays: widget.milestoneDays,
                  ),
                ],
                const SizedBox(height: 16),
                const Card(
                  color: HomePalette.surface,
                  child: ListTile(
                    leading: Icon(Icons.self_improvement),
                    title: Text('Mindful Essentials'),
                    subtitle: Text(
                      'Sleep Quality and Mindful Breathing · Coming together soon',
                    ),
                  ),
                ),
                Card(
                  color: HomePalette.surface,
                  child: ListTile(
                    leading: const Icon(Icons.favorite_outline),
                    title: const Text('Mental Health Support'),
                    subtitle: const Text('Open inSIGHT'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed(RouteNames.mentalHealthInsights),
                  ),
                ),
              ],
            ),
    );
  }
}
