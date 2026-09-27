import '../../../core/utils/firestore_mapper.dart';
import '../../../models/mood_model.dart';
import '../../../models/profile_roles.dart';
import '../../../models/report_model.dart';

/// The minimum trusted profile context needed to tailor educational resources.
/// A missing role intentionally resolves to shared content only.
class InsightRecommendationContext {
  const InsightRecommendationContext({
    required this.userId,
    this.populationRole,
  });

  final String userId;
  final PopulationRole? populationRole;

  @override
  bool operator ==(Object other) =>
      other is InsightRecommendationContext &&
      other.userId == userId &&
      other.populationRole == populationRole;

  @override
  int get hashCode => Object.hash(userId, populationRole);
}

class InsightsDashboardData {
  const InsightsDashboardData({
    required this.categories,
    required this.sections,
    this.resources = const [],
  });

  final List<InsightCategory> categories;
  final List<InsightSection> sections;
  final List<InsightCardItem> resources;

  List<InsightCardItem> resourcesForCategory(String categoryId) {
    return resources
        .where((resource) => resource.categoryId == categoryId)
        .toList(growable: false);
  }
}

class InsightCategory {
  const InsightCategory({
    required this.id,
    required this.label,
    required this.icon,
    this.isSelected = false,
  });

  final String id;
  final String label;
  final String icon;
  final bool isSelected;

  factory InsightCategory.fromJson(Map<String, dynamic> json) {
    return InsightCategory(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      icon: (json['icon'] ?? 'mood').toString(),
      isSelected: boolFromFirestore(json['isDefaultSelected']),
    );
  }
}

class InsightMetric {
  const InsightMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final String icon;
}

class InsightCardItem {
  const InsightCardItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.imageAsset,
    this.actionRoute,
    this.publishedAt,
    this.contentType,
    this.body,
    this.tags = const [],
    this.source,
    this.categoryId = '',
    this.videoUrl,
    this.thumbnailUrl,
    this.durationLabel,
    this.targetRoles = const ['all'],
    this.domainIds = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final String category;
  final String imageAsset;
  final String? actionRoute;
  final DateTime? publishedAt;
  final String? contentType;
  final String? body;
  final List<String> tags;
  final String? source;
  final String categoryId;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? durationLabel;
  final List<String> targetRoles;
  final List<String> domainIds;

  bool get isVideoPlaceholder => contentType == 'video_placeholder';

  factory InsightCardItem.fromJson(Map<String, dynamic> json) {
    return InsightCardItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      category: (json['categoryLabel'] ?? json['category'] ?? '').toString(),
      imageAsset: (json['imageAsset'] ?? '').toString(),
      actionRoute: _stringOrNull(json['actionRoute']),
      publishedAt: dateTimeFromFirestore(json['publishedAt']),
      contentType: _stringOrNull(json['contentType']),
      body: _stringOrNull(json['body']),
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((tag) => tag.toString())
          .where((tag) => tag.trim().isNotEmpty)
          .toList(growable: false),
      source: _stringOrNull(json['source']),
      categoryId: (json['categoryId'] ?? '').toString(),
      videoUrl: _stringOrNull(json['videoUrl']),
      thumbnailUrl: _stringOrNull(json['thumbnailUrl']),
      durationLabel: _stringOrNull(json['durationLabel']),
      targetRoles: _stringListOrDefault(json['targetRoles'], const ['all']),
      domainIds: _stringListOrDefault(json['domainIds'], const []),
    );
  }
}

class InsightSection {
  const InsightSection({
    required this.id,
    required this.title,
    required this.items,
    this.showSeeAll = true,
  });

  final String id;
  final String title;
  final List<InsightCardItem> items;
  final bool showSeeAll;
}

class InsightMetricsSummary {
  const InsightMetricsSummary({
    required this.checkIns,
    required this.goodDays,
    required this.totalLogs,
  });

  final int checkIns;
  final int goodDays;
  final int totalLogs;

  factory InsightMetricsSummary.from({
    required List<MoodModel> moods,
    ReportModel? report,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final startOfWeek = DateTime(
      effectiveNow.year,
      effectiveNow.month,
      effectiveNow.day,
    ).subtract(Duration(days: effectiveNow.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));
    final weeklyMoods = moods
        .where((mood) {
          final createdAt = mood.createdAt;
          return !createdAt.isBefore(startOfWeek) &&
              createdAt.isBefore(endOfWeek);
        })
        .toList(growable: false);

    return InsightMetricsSummary(
      checkIns: weeklyMoods.length,
      goodDays: weeklyMoods.where((mood) => mood.level >= 4).length,
      totalLogs: moods.length + (report?.assessmentCount ?? 0),
    );
  }
}

String? _stringOrNull(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

List<String> _stringListOrDefault(Object? value, List<String> fallback) {
  if (value is! List) return fallback;
  final values = value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return values.isEmpty ? fallback : values;
}
