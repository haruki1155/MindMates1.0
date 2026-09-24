import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/journal_model.dart';
import 'package:mind_mates/models/mood_model.dart';
import 'package:mind_mates/models/report_model.dart';
import 'package:mind_mates/providers/journal_provider.dart';
import 'package:mind_mates/providers/mood_provider.dart';
import 'package:mind_mates/providers/report_provider.dart';
import 'package:mind_mates/repositories/journal_repository.dart';
import 'package:mind_mates/repositories/mood_repository.dart';
import 'package:mind_mates/repositories/report_repository.dart';

void main() {
  group('MoodProvider', () {
    test('logs mood and updates local state', () async {
      final repository = _FakeMoodRepository();
      final provider = MoodProvider(repository);

      final success = await provider.logMood(
        userId: 'user_1',
        level: 4,
        label: 'Good',
        note: 'Finished a check-in',
      );

      expect(success, isTrue);
      expect(provider.moods, hasLength(1));
      expect(provider.moods.first.level, 4);
      expect(repository.createdUserId, 'user_1');
    });

    test('tracks daily mood state after a successful check-in', () async {
      final repository = _FakeMoodRepository();
      final provider = MoodProvider(repository);
      final now = DateTime(2026, 7, 7, 12);

      await provider.loadTodayMood('user_1', now: now);

      expect(provider.hasCheckedInToday, isFalse);
      expect(provider.todayMood, isNull);

      final success = await provider.logDailyMood(
        userId: 'user_1',
        level: 3,
        label: 'Okay',
        note: 'Steady day',
        now: now,
      );

      expect(success, isTrue);
      expect(provider.hasCheckedInToday, isTrue);
      expect(provider.todayMood?.level, 3);
      expect(provider.dailySaveResult?.created, isTrue);
      expect(repository.saveCalls, 1);
    });
  });

  group('JournalProvider', () {
    test('creates journal and updates local state', () async {
      final repository = _FakeJournalRepository();
      final provider = JournalProvider(repository);

      final success = await provider.createJournal(
        userId: 'user_1',
        content: 'Today felt manageable.',
        moodLevel: 4,
        tags: const ['check-in'],
      );

      expect(success, isTrue);
      expect(provider.journals.single.content, 'Today felt manageable.');
      expect(provider.journals.single.tags, ['check-in']);
      expect(repository.createdUserId, 'user_1');
    });
  });

  group('ReportProvider', () {
    test('loads latest report', () async {
      final repository = _FakeReportRepository(
        latest: ReportModel(
          id: 'report_1',
          userId: 'user_1',
          generatedAt: DateTime(2026, 6, 30),
          title: 'Mental Health Summary',
          description: 'Ready for review',
        ),
      );
      final provider = ReportProvider(repository);

      await provider.loadLatestReport('user_1');

      expect(provider.latestReport?.id, 'report_1');
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('creates placeholder when no latest report exists', () async {
      final repository = _FakeReportRepository();
      final provider = ReportProvider(repository);

      await provider.ensureWeeklyPlaceholder('user_1');

      expect(repository.createdForUserId, 'user_1');
      expect(provider.latestReport?.id, 'placeholder_1');
    });

    test('refreshes weekly report and reloads latest report', () async {
      final repository = _FakeReportRepository();
      final provider = ReportProvider(repository);

      await provider.refreshWeeklyReport('user_1');

      expect(repository.generatedForUserId, 'user_1');
      expect(provider.latestReport?.id, 'generated_1');
      expect(provider.latestReport?.hasEnoughData, isTrue);
    });
  });
}

class _FakeMoodRepository extends MoodRepository {
  String? createdUserId;
  int saveCalls = 0;

  @override
  Future<String> createMood({
    required String userId,
    required int level,
    String? label,
    String? note,
    DateTime? now,
  }) async {
    createdUserId = userId;
    return 'mood_1';
  }

  @override
  Future<MoodModel?> fetchTodayMood(String userId, {DateTime? now}) async {
    return null;
  }

  @override
  Future<DailyMoodSaveResult> saveDailyMood({
    required String userId,
    required int level,
    String? label,
    String? note,
    String? entryMethod,
    bool? expressionAssistUsed,
    bool? expressionSuggestionAccepted,
    String? expressionModelVersion,
    DateTime? now,
  }) async {
    saveCalls += 1;
    return DailyMoodSaveResult(
      mood: MoodModel(
        id: 'daily_user_1_20260707',
        userId: userId,
        level: level,
        label: label,
        note: note,
        createdAt: now ?? DateTime(2026, 7, 7, 12),
      ),
      created: true,
    );
  }

  @override
  Future<List<MoodModel>> fetchRecentMoods(String userId, {int limit = 14}) {
    return Future.value(const []);
  }
}

class _FakeJournalRepository extends JournalRepository {
  String? createdUserId;

  @override
  Future<String> createJournal({
    required String userId,
    required String content,
    int? moodLevel,
    List<String> tags = const [],
  }) async {
    createdUserId = userId;
    return 'journal_1';
  }

  @override
  Future<List<JournalModel>> fetchRecentJournals(
    String userId, {
    int limit = 20,
  }) {
    return Future.value(const []);
  }
}

class _FakeReportRepository extends ReportRepository {
  _FakeReportRepository({this.latest});

  ReportModel? latest;
  String? createdForUserId;
  String? generatedForUserId;

  @override
  Future<ReportModel?> fetchLatestReport(String userId) async => latest;

  @override
  Future<String> createPlaceholderWeeklyReport(String userId) async {
    createdForUserId = userId;
    latest = ReportModel(
      id: 'placeholder_1',
      userId: userId,
      generatedAt: DateTime(2026, 6, 30),
    );
    return 'placeholder_1';
  }

  @override
  Future<String> generateWeeklyReport(String userId, {DateTime? now}) async {
    generatedForUserId = userId;
    latest = ReportModel(
      id: 'generated_1',
      userId: userId,
      generatedAt: DateTime(2026, 7, 3),
      description: 'Latest full assessment shows Moderate Concern concern.',
      hasEnoughData: true,
    );
    return 'generated_1';
  }
}
