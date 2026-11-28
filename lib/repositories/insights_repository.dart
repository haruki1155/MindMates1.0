import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/firestore_mapper.dart';
import '../database/firestore_collections.dart';
import '../features/insights/models/insights_models.dart';
import '../models/profile_roles.dart';
import '../models/report_model.dart';
import '../services/firebase/firestore_service.dart';
import 'insights_seed_data.dart';

abstract class InsightsRepositoryDataSource {
  Future<List<Map<String, dynamic>>> fetchCategories();

  Future<List<Map<String, dynamic>>> fetchContent();

  Future<List<Map<String, dynamic>>> fetchRules();

  Future<Map<String, dynamic>?> fetchLatestReport(String userId);
}

class FirestoreInsightsRepositoryDataSource
    implements InsightsRepositoryDataSource {
  FirestoreInsightsRepositoryDataSource(this._firestoreService);

  final FirestoreService _firestoreService;

  @override
  Future<List<Map<String, dynamic>>> fetchCategories() {
    return _firestoreService.getDocuments(
      FirestoreCollections.insightCategories,
      whereEquals: {'isActive': true},
      orderBy: 'sortOrder',
      descending: false,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchContent() {
    return _firestoreService.getDocuments(
      FirestoreCollections.insightContent,
      whereEquals: {'isActive': true},
      orderBy: 'sortOrder',
      descending: false,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRules() {
    return _firestoreService.getDocuments(
      FirestoreCollections.insightRules,
      whereEquals: {'isActive': true},
      orderBy: 'priority',
      descending: false,
    );
  }

  @override
  Future<Map<String, dynamic>?> fetchLatestReport(String userId) async {
    final docs = await _firestoreService.getDocuments(
      FirestoreCollections.reports,
      whereEquals: {'userId': userId},
      orderBy: 'generatedAt',
      limit: 1,
    );
    if (docs.isEmpty) return null;
    return docs.first;
  }
}

class InsightsRepository {
  InsightsRepository({
    FirestoreService? firestoreService,
    InsightsRepositoryDataSource? dataSource,
    this.useFallbackContent = true,
  }) {
    _dataSource =
        dataSource ??
        FirestoreInsightsRepositoryDataSource(
          firestoreService ?? FirestoreService(),
        );
  }

  late final InsightsRepositoryDataSource _dataSource;
  final bool useFallbackContent;

  Future<InsightsDashboardData> fetchInsights(
    InsightRecommendationContext context,
  ) async {
    final categories = await _safeFetch(_dataSource.fetchCategories);
    final content = await _safeFetch(_dataSource.fetchContent);
    final rules = await _safeFetch(_dataSource.fetchRules);
    final reportJson = context.userId.trim().isEmpty
        ? null
        : await _safeFetchReport(context.userId);

    final effectiveCategories = categories.isEmpty && useFallbackContent
        ? insightSeedCategories
        : categories;
    final effectiveContent = content.isEmpty && useFallbackContent
        ? insightSeedContent
        : content;
    final effectiveRules = rules.isEmpty && useFallbackContent
        ? insightSeedRules
        : rules;

    final latestReport = reportJson == null
        ? null
        : ReportModel.fromJson(reportJson, id: reportJson['id']?.toString());
    // Finalized, past-week, or undated reports must not drive "this week".
    final report = latestReport != null && latestReport.isCurrentWeekReport
        ? latestReport
        : null;
    final cards = effectiveContent
        .map(_InsightContent.fromJson)
        .where((item) => item.id.isNotEmpty)
        .where((item) => item.isEligibleFor(context.populationRole))
        .toList(growable: false);
    final activeRules = effectiveRules
        .map(_InsightRule.fromJson)
        .where((rule) => rule.id.isNotEmpty && rule.contentId.isNotEmpty)
        .toList(growable: false);

    final categoryModels = effectiveCategories
        .map(InsightCategory.fromJson)
        .where((category) => category.id.isNotEmpty)
        .toList(growable: false);
    final resources = [
      ...cards.map((item) => item.card),
      ...categoryModels.map(_videoPlaceholderFor),
    ];

    final personalized = report == null
        ? const <_ScoredRecommendation>[]
        : _personalizedCandidates(
            cards: cards,
            rules: activeRules,
            report: report,
          );
    final featured = _featuredRecommendation(
      cards: cards,
      personalized: personalized,
      report: report,
      populationRole: context.populationRole,
    );

    return InsightsDashboardData(
      categories: categoryModels,
      resources: resources,
      featuredRecommendation: featured,
      sections: _buildSections(
        cards: cards,
        personalized: personalized,
        report: report,
        populationRole: context.populationRole,
        featuredId: featured?.item.id,
      ),
    );
  }

  FeaturedInsightRecommendation? _featuredRecommendation({
    required List<_InsightContent> cards,
    required List<_ScoredRecommendation> personalized,
    required ReportModel? report,
    required PopulationRole? populationRole,
  }) {
    if (report != null && report.hasEnoughData) {
      for (final candidate in personalized) {
        if (candidate.card.hasApprovedProvenance) {
          return FeaturedInsightRecommendation(
            item: candidate.card,
            reason: candidate.reason,
          );
        }
      }
    }

    final approved = cards.where((item) => item.card.hasApprovedProvenance);
    final fallback = [
      ...approved.where(
        (item) =>
            item.sectionId == 'recommended' &&
            item.isRoleSpecificFor(populationRole),
      ),
      ...approved.where(
        (item) => item.sectionId == 'recommended' && item.isShared,
      ),
      ...approved.where((item) => item.isRoleSpecificFor(populationRole)),
      ...approved.where((item) => item.isShared),
    ];
    if (fallback.isEmpty) return null;
    return FeaturedInsightRecommendation(
      item: fallback.first.card,
      reason: InsightRecommendationReason.general,
    );
  }

  InsightCardItem _videoPlaceholderFor(InsightCategory category) {
    return InsightCardItem(
      id: 'video_placeholder_${category.id}',
      title: '${category.label} guided video',
      subtitle: 'A guided wellness video will be available here soon.',
      categoryId: category.id,
      category: category.label,
      imageAsset: '',
      contentType: 'video_placeholder',
      durationLabel: 'Coming soon',
      tags: ['video', category.label.toLowerCase()],
      source: 'MindMate',
    );
  }

  Future<List<Map<String, dynamic>>> _safeFetch(
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    if (!useFallbackContent) return fetch();

    try {
      return await fetch();
    } on FirebaseException catch (error) {
      if (error.code == 'failed-precondition' ||
          error.code == 'permission-denied' ||
          error.code == 'unavailable' ||
          error.code == 'no-app') {
        return const [];
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _safeFetchReport(String userId) async {
    if (!useFallbackContent) return _dataSource.fetchLatestReport(userId);

    try {
      return await _dataSource.fetchLatestReport(userId);
    } on FirebaseException catch (error) {
      if (error.code == 'failed-precondition' ||
          error.code == 'permission-denied' ||
          error.code == 'unavailable' ||
          error.code == 'no-app') {
        return null;
      }
      rethrow;
    }
  }

  List<InsightSection> _buildSections({
    required List<_InsightContent> cards,
    required List<_ScoredRecommendation> personalized,
    required ReportModel? report,
    required PopulationRole? populationRole,
    required String? featuredId,
  }) {
    if (cards.isEmpty && report == null) return const [];

    final recommended = report == null
        ? const <InsightCardItem>[]
        : _recommendedCards(
            cards: cards,
            personalized: personalized,
            populationRole: populationRole,
          ).where((item) => item.id != featuredId).toList(growable: false);
    final patternCards = [
      if (report != null) ..._reportPatternCards(report),
      ..._sectionCards(cards, 'patterns'),
    ].take(_sectionLimit).toList(growable: false);
    final wellbeing = _sectionCards(
      cards,
      'wellbeing_101',
    ).take(_sectionLimit).toList(growable: false);
    final latest = [...cards]
      ..sort((left, right) {
        final leftDate = left.publishedAt ?? DateTime(0);
        final rightDate = right.publishedAt ?? DateTime(0);
        return rightDate.compareTo(leftDate);
      });
    final latestCards = latest
        .where((item) => item.sectionId == 'latest')
        .map((item) => item.card)
        .take(_sectionLimit)
        .toList(growable: false);

    final sections = [
      InsightSection(
        id: 'patterns',
        title: 'Your mental health patterns',
        items: patternCards,
      ),
      InsightSection(
        id: 'wellbeing_101',
        title: 'Mental Wellbeing 101',
        items: wellbeing,
      ),
      InsightSection(id: 'latest', title: 'The latest', items: latestCards),
      InsightSection(
        id: 'recommended',
        title: 'Recommended for you',
        items: recommended.take(_sectionLimit).toList(growable: false),
      ),
    ];

    return sections
        .where((section) => section.items.isNotEmpty)
        .toList(growable: false);
  }

  List<InsightCardItem> _sectionCards(
    List<_InsightContent> cards,
    String sectionId,
  ) {
    return cards
        .where((item) => item.sectionId == sectionId)
        .map((item) => item.card)
        .toList(growable: false);
  }

  /// Report-matched cards in display order, each with why it matched.
  List<_ScoredRecommendation> _personalizedCandidates({
    required List<_InsightContent> cards,
    required List<_InsightRule> rules,
    required ReportModel report,
  }) {
    final cardsById = {for (final card in cards) card.id: card.card};
    final matched = <_ScoredRecommendation>[];
    final seen = <String>{};

    // Domain relevance is deterministic and takes precedence over generic
    // rule matches. It uses a centralized exact-label mapping below.
    final concernDomainIds = _concernDomainIds(report);
    for (final content in cards) {
      if (content.domainIds.isEmpty ||
          !content.domainIds.any(concernDomainIds.contains)) {
        continue;
      }
      if (seen.add(content.id)) {
        matched.add(
          _ScoredRecommendation(content.card, const {
            InsightRecommendationReason.assessment,
          }),
        );
      }
    }

    final sortedRules = [...rules]
      ..sort((left, right) => left.priority.compareTo(right.priority));
    for (final rule in sortedRules) {
      final card = cardsById[rule.contentId];
      if (card == null || seen.contains(card.id)) continue;
      final reasons = _matchedReasons(rule, report);
      if (reasons == null) continue;

      matched.add(_ScoredRecommendation(card, reasons));
      seen.add(card.id);
    }
    return matched;
  }

  List<InsightCardItem> _recommendedCards({
    required List<_InsightContent> cards,
    required List<_ScoredRecommendation> personalized,
    required PopulationRole? populationRole,
  }) {
    final matched = [for (final item in personalized) item.card];
    final seen = {for (final item in matched) item.id};

    if (matched.isEmpty) {
      final roleDefaults = cards.where(
        (item) =>
            item.sectionId == 'recommended' &&
            item.isRoleSpecificFor(populationRole),
      );
      for (final content in roleDefaults) {
        if (seen.add(content.id)) matched.add(content.card);
      }

      final sharedDefaults = cards.where(
        (item) => item.sectionId == 'recommended' && item.isShared,
      );
      for (final content in sharedDefaults) {
        if (seen.add(content.id)) matched.add(content.card);
      }
    }

    return matched;
  }

  /// Signal types of the conditions that matched, or null if the rule fails.
  Set<InsightRecommendationReason>? _matchedReasons(
    _InsightRule rule,
    ReportModel report,
  ) {
    final matchedKeys = <String>[];
    var allMatched = true;
    for (final entry in rule.conditions.entries) {
      if (_matchesCondition(entry.key, entry.value, report)) {
        matchedKeys.add(entry.key);
      } else {
        allMatched = false;
      }
    }

    if (rule.conditions.isEmpty || matchedKeys.isEmpty) return null;
    if (rule.matchType != 'any' && !allMatched) return null;
    return {
      for (final key in matchedKeys)
        if (_conditionReasons[key] != null) _conditionReasons[key]!,
    };
  }

  static const _conditionReasons = <String, InsightRecommendationReason>{
    'mentalStatus': InsightRecommendationReason.assessment,
    'topConcernAreas': InsightRecommendationReason.assessment,
    'domainIds': InsightRecommendationReason.assessment,
    'fullAssessmentStatus': InsightRecommendationReason.assessment,
    'quickAssessmentSignal': InsightRecommendationReason.assessment,
    'averageMoodMax': InsightRecommendationReason.mood,
    'moodCheckInMin': InsightRecommendationReason.mood,
    'moodCheckInMax': InsightRecommendationReason.mood,
    'breathingSessionMax': InsightRecommendationReason.appActivity,
    'mindAidMessageMax': InsightRecommendationReason.appActivity,
  };

  bool _matchesCondition(String key, Object? value, ReportModel report) {
    // Without enough data, a zero count is missing data, not low activity.
    if (!report.hasEnoughData &&
        const {
          'moodCheckInMax',
          'breathingSessionMax',
          'mindAidMessageMax',
        }.contains(key) &&
        _intOrZero(value) == 0) {
      return false;
    }
    switch (key) {
      case 'mentalStatus':
        return _matchesAny(value, [report.mentalStatus]);
      case 'topConcernAreas':
        return _matchesAny(value, report.topConcernAreas);
      case 'domainIds':
        return _matchesAny(value, _concernDomainIds(report).toList());
      case 'fullAssessmentStatus':
        return _matchesAny(value, [report.fullAssessmentStatus]);
      case 'quickAssessmentSignal':
        return _matchesAny(value, [report.quickAssessmentSignal]);
      case 'averageMoodMax':
        final average = report.averageMoodLevel;
        return average != null && average <= _doubleOrZero(value);
      case 'moodCheckInMin':
        return report.moodCheckInCount >= _intOrZero(value);
      case 'moodCheckInMax':
        return report.moodCheckInCount <= _intOrZero(value);
      case 'breathingSessionMax':
        return report.breathingSessionCount <= _intOrZero(value);
      case 'mindAidMessageMax':
        return report.mindAidMessageCount <= _intOrZero(value);
      default:
        return false;
    }
  }

  bool _matchesAny(Object? expected, List<Object?> actualValues) {
    final expectedValues = _stringList(expected);
    final actual = actualValues
        .whereType<Object>()
        .map((value) => _normalize(value.toString()))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (expectedValues.isEmpty || actual.isEmpty) return false;

    return expectedValues.any((expectedValue) {
      return actual.any(
        (actualValue) =>
            actualValue == expectedValue || actualValue.contains(expectedValue),
      );
    });
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => _normalize(item.toString()))
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final text = _normalize(value?.toString() ?? '');
    return text.isEmpty ? const [] : [text];
  }

  List<InsightCardItem> _reportPatternCards(ReportModel report) {
    final cards = <InsightCardItem>[];
    if (report.hasEnoughData) {
      cards.add(
        InsightCardItem(
          id: 'report_status_${report.id}',
          title: 'Current wellness signal',
          subtitle: report.description,
          category: report.mentalStatusLabel,
          imageAsset: '',
          contentType: 'generated_pattern',
          source: 'reports',
          publishedAt: report.generatedAt,
        ),
      );
    }

    if (report.topConcernAreas.isNotEmpty) {
      cards.add(
        InsightCardItem(
          id: 'report_focus_${report.id}',
          title: 'Main focus: ${report.topConcernAreas.first}',
          subtitle: report.recommendedNextActions.isEmpty
              ? 'Review your weekly summary for support ideas.'
              : report.recommendedNextActions.first,
          category: 'Your data',
          imageAsset: '',
          contentType: 'generated_pattern',
          source: 'reports',
          publishedAt: report.generatedAt,
        ),
      );
    }

    return cards;
  }

  int _intOrZero(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _doubleOrZero(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _normalize(String value) => value.trim().toLowerCase();

  Set<String> _concernDomainIds(ReportModel report) {
    final ids = <String>{
      for (final label in [
        ...report.topConcernAreas,
        ...report.fullAssessmentTopConcernAreas,
      ])
        if (_domainIdForLabel(label) != null) _domainIdForLabel(label)!,
    };

    for (final statuses in [
      report.fullAssessmentDomainStatuses,
      report.quickAssessmentAreaStatuses,
    ]) {
      statuses.forEach((label, status) {
        if (_isConcernStatus(status)) {
          final domainId = _domainIdForLabel(label);
          if (domainId != null) ids.add(domainId);
        }
      });
    }
    return ids;
  }

  bool _isConcernStatus(String status) {
    final normalized = _normalize(status);
    return const {
      'some strain indicated',
      'support may be helpful',
      'needs improvement',
      'at risk',
      'high concern',
      'very high concern',
      'moderate',
      'elevated',
      'watchful',
    }.contains(normalized);
  }

  String? _domainIdForLabel(String label) =>
      _assessmentDomainIds[_normalize(label)];

  static const _sectionLimit = 6;

  static const _assessmentDomainIds = <String, String>{
    'academic stress': 'academicStress',
    // Student Well-Being V4 reports these shortened labels.
    'academic': 'academicStress',
    'financial well-being': 'financialWellbeing',
    'financial': 'financialWellbeing',
    'social adjustment': 'socialAdjustment',
    'workplace stress': 'workplaceStress',
    'professional support': 'professionalSupport',
    'professional well-being': 'professionalWellbeing',
    'workplace responsibilities': 'workplaceResponsibilities',
    'workplace support': 'workplaceSupport',
    'workplace well-being': 'workplaceWellbeing',
    'sleep and rest': 'sleepRest',
    'emotional well-being': 'emotionalWellbeing',
  };
}

class _InsightContent {
  const _InsightContent({
    required this.sectionId,
    required this.card,
    required this.targetRoles,
    required this.domainIds,
  });

  factory _InsightContent.fromJson(Map<String, dynamic> json) {
    return _InsightContent(
      sectionId: (json['sectionId'] ?? '').toString(),
      card: InsightCardItem.fromJson(json),
      targetRoles: _rolesFrom(json['targetRoles']),
      domainIds: _domainIdsFrom(json['domainIds']),
    );
  }

  String get id => card.id;
  DateTime? get publishedAt => card.publishedAt;
  bool get isShared => targetRoles.contains('all');

  bool isEligibleFor(PopulationRole? role) =>
      isShared || (role != null && targetRoles.contains(role.storedValue));

  bool isRoleSpecificFor(PopulationRole? role) =>
      role != null && !isShared && targetRoles.contains(role.storedValue);

  final String sectionId;
  final InsightCardItem card;
  final List<String> targetRoles;
  final List<String> domainIds;

  static List<String> _rolesFrom(Object? value) {
    if (value is! List) return const ['all'];
    final roles = value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return roles.isEmpty ? const ['all'] : roles;
  }

  static List<String> _domainIdsFrom(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class _ScoredRecommendation {
  const _ScoredRecommendation(this.card, this.reasons);

  final InsightCardItem card;
  final Set<InsightRecommendationReason> reasons;

  /// Precedence when several signal types matched: assessment, mood, activity.
  InsightRecommendationReason get reason {
    for (final reason in const [
      InsightRecommendationReason.assessment,
      InsightRecommendationReason.mood,
      InsightRecommendationReason.appActivity,
    ]) {
      if (reasons.contains(reason)) return reason;
    }
    return InsightRecommendationReason.general;
  }
}

class _InsightRule {
  const _InsightRule({
    required this.id,
    required this.contentId,
    required this.priority,
    required this.matchType,
    required this.conditions,
  });

  factory _InsightRule.fromJson(Map<String, dynamic> json) {
    return _InsightRule(
      id: (json['id'] ?? '').toString(),
      contentId: (json['contentId'] ?? '').toString(),
      priority: intFromFirestore(json['priority']),
      matchType: (json['matchType'] ?? 'all').toString().trim().toLowerCase(),
      conditions: Map<String, Object?>.from(
        json['conditions'] as Map<dynamic, dynamic>? ?? const {},
      ),
    );
  }

  final String id;
  final String contentId;
  final int priority;
  final String matchType;
  final Map<String, Object?> conditions;
}
