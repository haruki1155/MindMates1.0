import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/mood_provider.dart';
import '../../../routes/route_names.dart';
import '../widgets/mood_v2_history_panel.dart';
import '../widgets/mood_journey_summary.dart';
import '../../home/widgets/home_dashboard_widgets.dart';

class MoodJourneyScreen extends StatefulWidget {
  const MoodJourneyScreen({super.key});

  @override
  State<MoodJourneyScreen> createState() => _MoodJourneyScreenState();
}

class _MoodJourneyScreenState extends State<MoodJourneyScreen> {
  String? _loadedUser;
  Timer? _midnightTimer;

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = DateTime.now().toUtc();
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
        _provider<MoodProvider>(listen: false)?.loadMoodV2History(uid);
      }
      setState(() {});
      _scheduleMidnight();
    });
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
    if (uid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _provider<AuthProvider>(listen: false)?.authenticatedUserId ==
                uid) {
          _provider<MoodProvider>(listen: false)?.loadMoodV2History(uid);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _provider<AuthProvider>()?.authenticatedUserId;
    final mood = _provider<MoodProvider>();
    final history = mood?.v2History;
    final safeHistory =
        uid != null &&
            history != null &&
            history.events.every((event) => event.userId == uid)
        ? history
        : null;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F1DF),
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
                const SizedBox(height: 6),
                const Text(
                  'Notice your emotional patterns and small shifts throughout your days.',
                ),
                const SizedBox(height: 16),
                if (safeHistory != null)
                  MoodJourneySummary(
                    key: ValueKey(uid),
                    history: safeHistory,
                    now: DateTime.now(),
                  ),
                MoodV2HistoryPanel(
                  history: safeHistory,
                  isLoading: mood?.isLoadingV2History ?? false,
                  errorMessage: mood?.v2HistoryErrorMessage,
                  showPersonalDetails: true,
                  v2PersonalNotes: mood?.v2PersonalNotes ?? const {},
                  v2NoteLoadingDays: mood?.v2NoteLoadingDays ?? const {},
                  v2NoteErrorDays: mood?.v2NoteErrorDays ?? const {},
                  onExpandDay: (day) => mood?.loadMoodV2DayNotes(uid, day),
                  onRetry: () => mood?.loadMoodV2History(uid),
                  hasMore: mood?.canLoadMoreMoodV2History ?? false,
                  isLoadingMore: mood?.isLoadingMoreV2History ?? false,
                  paginationErrorMessage: mood?.v2PaginationErrorMessage,
                  onLoadMore: () => mood?.loadMoreMoodV2History(uid),
                ),
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
