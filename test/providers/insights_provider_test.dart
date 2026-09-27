import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/insights/models/insights_models.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/providers/insights_provider.dart';
import 'package:mind_mates/repositories/insights_repository.dart';

void main() {
  test('loadInsights sets loading state and stores data', () async {
    final repository = _FakeInsightsRepository();
    final provider = InsightsProvider(repository);
    final loadingStates = <bool>[];
    provider.addListener(() => loadingStates.add(provider.isLoading));

    await provider.loadInsights(_context());

    expect(loadingStates.first, isTrue);
    expect(loadingStates.last, isFalse);
    expect(provider.data?.categories.single.label, 'Mood tracking');
    expect(provider.errorMessage, isNull);
  });

  test('errors expose friendly message', () async {
    final provider = InsightsProvider(
      _FakeInsightsRepository(shouldThrow: true),
    );

    await provider.loadInsights(_context());

    expect(provider.data, isNull);
    expect(provider.errorMessage, 'Unable to load insights.');
    expect(provider.isLoading, isFalse);
  });

  test('repeated loads for same user are cached unless refreshed', () async {
    final repository = _FakeInsightsRepository();
    final provider = InsightsProvider(repository);

    await provider.loadInsights(_context());
    await provider.loadInsights(_context());
    await provider.loadInsights(_context(), forceRefresh: true);
    await provider.loadInsights(_context(userId: 'user_2'));

    expect(repository.calls, [
      'user_1:student',
      'user_1:student',
      'user_2:student',
    ]);
  });

  test(
    'role changes and invalidation trigger a fresh contextual fetch',
    () async {
      final repository = _FakeInsightsRepository();
      final provider = InsightsProvider(repository);

      await provider.loadInsights(_context(role: PopulationRole.student));
      await provider.loadInsights(_context(role: PopulationRole.teaching));
      provider.invalidateForUser('user_1');
      await provider.loadInsights(_context(role: PopulationRole.teaching));

      expect(repository.calls, [
        'user_1:student',
        'user_1:teaching',
        'user_1:teaching',
      ]);
    },
  );
}

InsightRecommendationContext _context({
  String userId = 'user_1',
  PopulationRole? role = PopulationRole.student,
}) => InsightRecommendationContext(userId: userId, populationRole: role);

class _FakeInsightsRepository extends InsightsRepository {
  _FakeInsightsRepository({this.shouldThrow = false});

  final bool shouldThrow;
  final List<String> calls = [];

  @override
  Future<InsightsDashboardData> fetchInsights(
    InsightRecommendationContext context,
  ) async {
    calls.add(
      '${context.userId}:${context.populationRole?.storedValue ?? 'shared'}',
    );
    if (shouldThrow) throw StateError('boom');

    return const InsightsDashboardData(
      categories: [
        InsightCategory(
          id: 'mood_tracking',
          label: 'Mood tracking',
          icon: 'mood',
        ),
      ],
      sections: [],
    );
  }
}
