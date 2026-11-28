import '../../../core/utils/firestore_mapper.dart';
import '../../../models/mood_model.dart';
import '../../../models/profile_roles.dart';
import '../../../models/report_model.dart';
import '../../../routes/route_names.dart';
import '../../mood/domain/mood_v2_analytics.dart';

/// Why a featured insight was picked. Copy shown to users stays fixed and
/// non-diagnostic per reason.
enum InsightRecommendationReason { assessment, mood, appActivity, general }

class FeaturedInsightRecommendation {
  const FeaturedInsightRecommendation({
    required this.item,
    required this.reason,
  });

  final InsightCardItem item;
  final InsightRecommendationReason reason;
}

const insightEligibleEvidenceTypes = <String, String>{
  'official_guideline': 'Official guideline',
  'systematic_review': 'Systematic review',
  'peer_reviewed_study': 'Peer-reviewed study',
  'institution_approved': 'Institution-approved',
};

const insightEligibleRightsStatuses = {
  'original',
  'open_license',
  'permission_granted',
};

const insightReviewStatuses = [
  'draft',
  'pending_review',
  'approved',
  'archived',
];

/// In-app destinations an insight may link to, with their button labels.
const insightActionRouteLabels = <String, String>{
  RouteNames.mindfulBreathing: 'Try mindful breathing',
  RouteNames.logMood: 'Log a mood check-in',
  RouteNames.mindAid: 'Talk with MindAid',
  RouteNames.services: 'Explore PACC services',
  RouteNames.mentalHealthReport: 'View wellness summary',
  RouteNames.studentAssessment: 'Take wellness assessment',
  RouteNames.sleepQuality: 'Track sleep quality',
};

/// Accepts only absolute https links with a host and no embedded credentials.
Uri? validInsightSourceUri(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

/// Provenance requirements still missing before an item may be approved;
/// empty means ready.
List<String> insightProvenanceGaps({
  required String? sourceTitle,
  required String? sourceUrl,
  required String? evidenceType,
  required String? rightsStatus,
}) => [
  if (sourceTitle == null || sourceTitle.trim().isEmpty) 'Source title',
  if (validInsightSourceUri(sourceUrl) == null) 'HTTPS source link',
  if (!insightEligibleEvidenceTypes.containsKey(evidenceType))
    'Eligible evidence type',
  if (!insightEligibleRightsStatuses.contains(rightsStatus))
    'Cleared rights status',
];

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
    this.featuredRecommendation,
  });

  final List<InsightCategory> categories;
  final List<InsightSection> sections;
  final List<InsightCardItem> resources;
  final FeaturedInsightRecommendation? featuredRecommendation;

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
    this.sourceTitle,
    this.sourceUrl,
    this.evidenceType,
    this.rightsStatus,
    this.reviewStatus,
    this.reviewedAt,
    this.reviewedBy,
    this.sectionId = '',
    this.sortOrder = 0,
    this.isActive = true,
    this.updatedAt,
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
  final String? sourceTitle;
  final String? sourceUrl;
  final String? evidenceType;
  final String? rightsStatus;
  final String? reviewStatus;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String sectionId;
  final int sortOrder;
  final bool isActive;
  final DateTime? updatedAt;

  bool get isVideoPlaceholder => contentType == 'video_placeholder';

  Uri? get validSourceUri => validInsightSourceUri(sourceUrl);

  List<String> get provenanceGaps => insightProvenanceGaps(
    sourceTitle: sourceTitle,
    sourceUrl: sourceUrl,
    evidenceType: evidenceType,
    rightsStatus: rightsStatus,
  );

  /// Only reviewed, source-verified, rights-cleared content may be featured.
  bool get hasApprovedProvenance =>
      !isVideoPlaceholder &&
      contentType != 'generated_pattern' &&
      reviewStatus == 'approved' &&
      provenanceGaps.isEmpty;

  String? get validActionRoute =>
      insightActionRouteLabels.containsKey(actionRoute) ? actionRoute : null;

  String? get actionButtonLabel => insightActionRouteLabels[actionRoute];

  String? get evidenceTypeLabel => insightEligibleEvidenceTypes[evidenceType];

  /// Short publisher name for cards, e.g. "NIMH" from "NIMH — Depression".
  String? get sourcePublisher {
    final title = sourceTitle?.trim();
    if (title == null || title.isEmpty || validSourceUri == null) return null;
    return title.split(' — ').first.trim();
  }

  /// Firestore shape of an `insight_content` document (without `id`).
  Map<String, dynamic> toCatalogJson() => {
    'title': title,
    'subtitle': subtitle,
    'categoryLabel': category,
    'categoryId': categoryId,
    'sectionId': sectionId,
    'imageAsset': imageAsset,
    'actionRoute': actionRoute,
    'publishedAt': publishedAt,
    'contentType': contentType,
    'body': body,
    'tags': tags,
    'source': source,
    'targetRoles': targetRoles,
    'domainIds': domainIds,
    'sourceTitle': sourceTitle,
    'sourceUrl': sourceUrl,
    'evidenceType': evidenceType,
    'rightsStatus': rightsStatus,
    'reviewStatus': reviewStatus,
    'reviewedAt': reviewedAt,
    'reviewedBy': reviewedBy,
    'sortOrder': sortOrder,
    'isActive': isActive,
    'updatedAt': updatedAt,
  };

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
      sourceTitle: _stringOrNull(json['sourceTitle']),
      sourceUrl: _stringOrNull(json['sourceUrl']),
      evidenceType: _stringOrNull(json['evidenceType']),
      rightsStatus: _stringOrNull(json['rightsStatus']),
      reviewStatus: _stringOrNull(json['reviewStatus']),
      reviewedAt: dateTimeFromFirestore(json['reviewedAt']),
      reviewedBy: _stringOrNull(json['reviewedBy']),
      sectionId: (json['sectionId'] ?? '').toString(),
      sortOrder: intFromFirestore(json['sortOrder']),
      isActive: boolFromFirestore(json['isActive'], fallback: true),
      updatedAt: dateTimeFromFirestore(json['updatedAt']),
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
    this.moodActiveDays,
    this.moodStreakDays,
    this.moodHistoryCoverage,
  });

  final int checkIns;
  final int goodDays;
  final int totalLogs;
  final int? moodActiveDays;
  final int? moodStreakDays;
  final MoodHistoryCoverage? moodHistoryCoverage;

  bool get usesMoodV2 => moodHistoryCoverage != null;
  bool get hasPartialMoodHistory =>
      moodHistoryCoverage == MoodHistoryCoverage.partial;

  factory InsightMetricsSummary.from({
    required List<MoodModel> moods,
    ReportModel? report,
    MoodAnalyticsSnapshot? moodV2Analytics,
    DateTime? now,
  }) {
    if (moodV2Analytics != null) {
      final weekly = moodV2Analytics.weekly;
      return InsightMetricsSummary(
        // A check-in is an entry, while a mood-active day remains distinct.
        checkIns: weekly.entryCount,
        goodDays: weekly.distribution[4] + weekly.distribution[5],
        totalLogs: moodV2Analytics.eventCount + (report?.assessmentCount ?? 0),
        moodActiveDays: weekly.activeDayCount,
        moodStreakDays: moodV2Analytics.streak.currentDays,
        moodHistoryCoverage: moodV2Analytics.coverage,
      );
    }
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
