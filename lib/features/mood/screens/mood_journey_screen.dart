import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/mood_provider.dart';
import '../../../repositories/student_academic_calendar_repository.dart';
import '../../../routes/route_names.dart';
import '../../home/widgets/home_dashboard_widgets.dart';
import '../domain/mood_journey_period.dart';
import '../domain/mood_v2_analytics.dart';
import '../widgets/mood_journey_calendar.dart';
import '../widgets/mood_journey_summary.dart';
import '../widgets/mood_v2_history_panel.dart';

class MoodJourneyScreen extends StatefulWidget {
  const MoodJourneyScreen({
    super.key,
    this.nowProvider,
    this.milestoneDays,
    this.academicCalendarRepository,
  });

  final DateTime Function()? nowProvider;

  /// Set when opened from the Home milestone "View recap" (item 38).
  final int? milestoneDays;

  final StudentAcademicCalendarRepository? academicCalendarRepository;

  @override
  State<MoodJourneyScreen> createState() => _MoodJourneyScreenState();
}

class _MoodJourneyScreenState extends State<MoodJourneyScreen> {
  static const String _allYearsValue = '__all_years__';
  static const String _allYearSemestersValue = '__all_semesters__';

  DateTime get _now => widget.nowProvider?.call() ?? DateTime.now();
  String get _todayDateKey => MoodManilaCalendar.dateKeyForInstant(_now);

  String? _loadedUser;
  DateTime? _displayedMonth;
  String? _selectedDateKey;
  Timer? _midnightTimer;

  List<StudentAcademicYear> _academicYears = const [];
  String? _selectedSchoolYear;
  String? _selectedSemesterId;
  int _academicGeneration = 0;

  DateTime get _effectiveDisplayedMonth {
    if (_displayedMonth != null) return _displayedMonth!;
    final today = MoodManilaCalendar.dateForKey(_todayDateKey);
    return DateTime.utc(today.year, today.month, 1);
  }

  String get _effectiveSelectedDateKey => _selectedDateKey ?? _todayDateKey;

  StudentAcademicYear? get _activeAcademicYear {
    if (_selectedSchoolYear == null) return null;
    return _academicYears
        .where((year) => year.schoolYear == _selectedSchoolYear)
        .firstOrNull;
  }

  StudentSemesterRange? get _activeSemester {
    final year = _activeAcademicYear;
    if (year == null || _selectedSemesterId == null) return null;
    return year.semesterRanges
        .where((sem) => sem.id == _selectedSemesterId)
        .firstOrNull;
  }

  MoodWeekRange? get _activeAcademicFilterRange =>
      _activeSemester?.range ?? _activeAcademicYear?.range;

  String? get _activeAcademicFilterLabel {
    final year = _activeAcademicYear;
    if (year == null) return null;
    final semester = _activeSemester;
    if (semester == null) {
      return 'Academic year ${year.schoolYear} · All year';
    }
    final approx = semester.isApproximateReportGrouping
        ? ' · Approximate dates'
        : '';
    return 'Academic year ${year.schoolYear} · ${semester.label}$approx';
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = _now.toUtc();
    final scheduledTodayKey = MoodManilaCalendar.dateKeyForInstant(now);
    final manila = now.add(const Duration(hours: 8));
    final next = DateTime.utc(
      manila.year,
      manila.month,
      manila.day + 1,
    ).subtract(const Duration(hours: 8));
    _midnightTimer = Timer(next.difference(now), () {
      if (!mounted) return;
      final newTodayKey = _todayDateKey;
      final filterRange = _activeAcademicFilterRange;
      final shouldFollowToday =
          _selectedDateKey == null ||
          _selectedDateKey == scheduledTodayKey ||
          _selectedDateKey == newTodayKey;
      setState(() {
        if (shouldFollowToday &&
            (filterRange == null || filterRange.includes(newTodayKey))) {
          final newToday = MoodManilaCalendar.dateForKey(newTodayKey);
          _selectedDateKey = newTodayKey;
          _displayedMonth = DateTime.utc(newToday.year, newToday.month, 1);
        }
      });
      final uid = _provider<AuthProvider>(listen: false)?.authenticatedUserId;
      if (uid != null) {
        _loadHistoryAndCalendar(uid, _effectiveDisplayedMonth);
      }
      _scheduleMidnight();
    });
  }

  void _loadHistoryAndCalendar(String uid, DateTime month) {
    final mood = _provider<MoodProvider>(listen: false);
    if (mood == null) return;
    mood.loadMoodV2History(uid, now: _now);
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

  Future<void> _loadAcademicCalendar(String uid) async {
    final generation = ++_academicGeneration;
    final repo =
        widget.academicCalendarRepository ??
        _provider<StudentAcademicCalendarRepository>(listen: false);
    if (repo == null) return;
    try {
      final years = await repo.fetchAcademicYears();
      if (!mounted ||
          generation != _academicGeneration ||
          _loadedUser != uid ||
          _provider<AuthProvider>(listen: false)?.authenticatedUserId != uid) {
        return;
      }
      if (years.isEmpty) {
        setState(() {
          _academicYears = const [];
          _selectedSchoolYear = null;
          _selectedSemesterId = null;
        });
        return;
      }
      final todayKey = _todayDateKey;
      final defaultYear =
          years
              .where(
                (y) => y.isCurrent && y.startDateKey.compareTo(todayKey) <= 0,
              )
              .firstOrNull ??
          years.where((y) => y.range.includes(todayKey)).firstOrNull ??
          years.where((y) => y.isCurrent).firstOrNull ??
          years.first;
      setState(() {
        _academicYears = years;
      });
      _applyFilterPeriodSelection(
        uid,
        schoolYear: defaultYear.schoolYear,
        semesterId: null,
      );
    } catch (_) {
      if (!mounted || generation != _academicGeneration || _loadedUser != uid) {
        return;
      }
      setState(() {
        _academicYears = const [];
        _selectedSchoolYear = null;
        _selectedSemesterId = null;
      });
    }
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
    _academicGeneration++;
    _academicYears = const [];
    _selectedSchoolYear = null;
    _selectedSemesterId = null;
    final today = MoodManilaCalendar.dateForKey(_todayDateKey);
    _displayedMonth = DateTime.utc(today.year, today.month, 1);
    _selectedDateKey = _todayDateKey;
    if (uid != null) {
      unawaited(_loadAcademicCalendar(uid));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _provider<AuthProvider>(listen: false)?.authenticatedUserId ==
                uid) {
          _loadHistoryAndCalendar(uid, _effectiveDisplayedMonth);
        }
      });
    }
  }

  void _applyFilterPeriodSelection(
    String uid, {
    required String? schoolYear,
    required String? semesterId,
  }) {
    final currentMonth = _effectiveDisplayedMonth;
    final schoolYearChanged = schoolYear != _selectedSchoolYear;
    setState(() {
      _selectedSchoolYear = schoolYear;
      _selectedSemesterId = semesterId;
    });
    final filterRange = _activeAcademicFilterRange;
    if (filterRange == null) return;

    final currentSelected = _effectiveSelectedDateKey;
    if (!filterRange.includes(currentSelected)) {
      final String nextSelected;
      if (schoolYearChanged) {
        nextSelected = filterRange.includes(_todayDateKey)
            ? _todayDateKey
            : filterRange.startDateKey;
      } else if (currentSelected.compareTo(filterRange.startDateKey) < 0) {
        nextSelected = filterRange.startDateKey;
      } else {
        final lastDay = MoodManilaCalendar.dateForKey(
          filterRange.endExclusiveDateKey,
        ).subtract(const Duration(days: 1));
        nextSelected = MoodManilaCalendar.dateKeyForDate(lastDay);
      }
      final nextDate = MoodManilaCalendar.dateForKey(nextSelected);
      final nextMonth = DateTime.utc(nextDate.year, nextDate.month, 1);
      final monthChanged =
          nextMonth.year != currentMonth.year ||
          nextMonth.month != currentMonth.month;
      setState(() {
        _selectedDateKey = nextSelected;
        _displayedMonth = nextMonth;
      });
      if (monthChanged) {
        _loadCalendarRange(uid, nextMonth);
      }
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
        filterRange: _activeAcademicFilterRange,
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
    final filterRange = _activeAcademicFilterRange;
    setState(() {
      if (filterRange != null && !filterRange.includes(todayKey)) {
        final activeYear = _activeAcademicYear;
        if (activeYear != null && activeYear.range.includes(todayKey)) {
          _selectedSemesterId = activeYear.semesterRanges
              .where((sem) => sem.range.includes(todayKey))
              .firstOrNull
              ?.id;
        } else {
          final matchingYear =
              _academicYears
                  .where((y) => y.isCurrent && y.range.includes(todayKey))
                  .firstOrNull ??
              _academicYears
                  .where((y) => y.range.includes(todayKey))
                  .firstOrNull;
          _selectedSchoolYear = matchingYear?.schoolYear;
          _selectedSemesterId = null;
        }
      }
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

  Widget _buildAcademicFilterBar(BuildContext context, String uid) {
    final activeYear = _activeAcademicYear;
    final activeSemester = _activeSemester;
    final yearLabel = activeYear?.schoolYear ?? 'All history';
    final semesterLabel = activeSemester?.label ?? 'All year';
    final semesters = activeYear?.semesterRanges ?? const [];

    return Container(
      key: const Key('mood-academic-filter-bar'),
      decoration: HomeDecor.card(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PopupMenuButton<String>(
                key: const Key('mood-academic-year-selector'),
                tooltip: 'Change academic year',
                onSelected: (value) {
                  final nextYear = value == _allYearsValue ? null : value;
                  _applyFilterPeriodSelection(
                    uid,
                    schoolYear: nextYear,
                    semesterId: null,
                  );
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                    value: _allYearsValue,
                    child: Text('All history'),
                  ),
                  for (final year in _academicYears)
                    PopupMenuItem<String>(
                      value: year.schoolYear,
                      child: Text(year.schoolYear),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: HomePalette.surfaceWarm,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: HomePalette.outlineStrong),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'Academic year: ',
                              style: TextStyle(
                                color: HomePalette.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              yearLabel,
                              style: const TextStyle(
                                color: HomePalette.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_drop_down,
                        size: 18,
                        color: HomePalette.text,
                      ),
                    ],
                  ),
                ),
              ),
              if (activeYear != null)
                PopupMenuButton<String>(
                  key: const Key('mood-academic-semester-selector'),
                  tooltip: 'Change semester',
                  enabled: semesters.isNotEmpty,
                  onSelected: (value) {
                    final nextSem = value == _allYearSemestersValue
                        ? null
                        : value;
                    _applyFilterPeriodSelection(
                      uid,
                      schoolYear: activeYear.schoolYear,
                      semesterId: nextSem,
                    );
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: _allYearSemestersValue,
                      child: Text('All year'),
                    ),
                    for (final sem in semesters)
                      PopupMenuItem<String>(
                        value: sem.id,
                        child: Text(sem.label),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: HomePalette.surfaceWarm,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: HomePalette.outlineStrong),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text(
                                'Semester: ',
                                style: TextStyle(
                                  color: HomePalette.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                semesterLabel,
                                style: const TextStyle(
                                  color: HomePalette.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (semesters.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_drop_down,
                            size: 18,
                            color: HomePalette.text,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (activeSemester != null &&
              activeSemester.isApproximateReportGrouping) ...[
            const SizedBox(height: 6),
            const Text(
              'Approximate dates (6-month report grouping)',
              key: Key('mood-academic-approximate-notice'),
              style: TextStyle(
                color: HomePalette.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
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
    final filterRange = _activeAcademicFilterRange;
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
                if (_academicYears.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildAcademicFilterBar(context, uid),
                ],
                const SizedBox(height: 10),
                MoodJourneyCalendar(
                  displayedMonth: displayedMonth,
                  selectedDateKey: selectedDateKey,
                  todayDateKey: _todayDateKey,
                  history: safeCalendarHistory,
                  isLoading: isCalendarLoading,
                  errorMessage: calendarError,
                  permittedRange: filterRange,
                  onRetry: () => _loadHistoryAndCalendar(uid, displayedMonth),
                  onMonthChanged: (next) => _handleMonthChanged(uid, next),
                  onDaySelected: (dayKey) => _handleDaySelected(uid, dayKey),
                  onTodayPressed: () => _handleTodayPressed(uid),
                ),
                if (safeCalendarHistory != null) ...[
                  const SizedBox(height: 10),
                  MoodV2HistoryPanel(
                    history: safeCalendarHistory,
                    isLoading: isCalendarLoading,
                    showPersonalDetails: true,
                    selectedDateKey: selectedDateKey,
                    permittedRange: filterRange,
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
                  const SizedBox(height: 10),
                  MoodJourneySummary(
                    key: ValueKey(uid),
                    history: safeCalendarHistory,
                    streakHistory: safeRecentHistory ?? safeCalendarHistory,
                    now: _now,
                    selectedDateKey: selectedDateKey,
                    displayedMonth: displayedMonth,
                    academicFilterRange: filterRange,
                    academicFilterLabel: _activeAcademicFilterLabel,
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
