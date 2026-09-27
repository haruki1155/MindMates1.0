import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../features/insights/models/insights_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/insights_provider.dart';
import '../../../providers/mood_provider.dart';
import '../../../providers/report_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../routes/route_names.dart';

class MentalHealthInsightsScreen extends StatefulWidget {
  const MentalHealthInsightsScreen({super.key});

  @override
  State<MentalHealthInsightsScreen> createState() =>
      _MentalHealthInsightsScreenState();
}

class _MentalHealthInsightsScreenState
    extends State<MentalHealthInsightsScreen> {
  final TextEditingController _searchController = TextEditingController();
  InsightRecommendationContext? _requestedContext;
  String _searchQuery = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final recommendationContext = _recommendationContext();
    if (_requestedContext == recommendationContext) return;
    _requestedContext = recommendationContext;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _readProviderOrNull<InsightsProvider>(
        context,
      )?.loadInsights(recommendationContext);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insightsProvider = _watchProviderOrNull<InsightsProvider>(context);
    final data = insightsProvider?.data;
    final visibleSections = _visibleSections(data);
    final hasSearchQuery = _searchQuery.trim().isNotEmpty;
    final moodProvider = _watchProviderOrNull<MoodProvider>(context);
    final moods = moodProvider?.moods ?? const [];
    final report = _watchProviderOrNull<ReportProvider>(context)?.latestReport;
    final metrics = InsightMetricsSummary.from(moods: moods, report: report);
    final hasCheckedInToday = moodProvider?.hasCheckedInToday == true;
    final insightsTheme = _InsightsTheme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: insightsTheme.background,
      body: Stack(
        children: [
          const _InsightsBackground(),
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(onNotificationTap: _openNotifications),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 44 + bottomInset),
                  sliver: SliverList.list(
                    children: [
                      _HeroSearchCard(
                        controller: _searchController,
                        onChanged: _updateSearchQuery,
                      ),
                      const SizedBox(height: 26),
                      _CategoryRow(
                        categories: data?.categories ?? const [],
                        onCategoryTap: (category) =>
                            _openCategory(category, data),
                      ),
                      const SizedBox(height: 24),
                      _WeeklyGlanceCard(
                        metrics: metrics,
                        onLogMoodTap: _openLogMood,
                        actionLabel: hasCheckedInToday
                            ? 'View today’s mood'
                            : 'Log mood →',
                      ),
                      const SizedBox(height: 24),
                      if (insightsProvider?.errorMessage != null &&
                          data != null) ...[
                        _InsightsErrorBanner(
                          onRetry: () => insightsProvider?.loadInsights(
                            _recommendationContext(),
                            forceRefresh: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      AnimatedSwitcher(
                        key: const Key('insights_content_switcher'),
                        duration: _insightsMotionDuration(context, 180),
                        transitionBuilder: (child, animation) {
                          final offset = Tween<Offset>(
                            begin: const Offset(0, 0.018),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(
                            _insightContentStateKey(
                              insightsProvider,
                              data,
                              visibleSections,
                              hasSearchQuery,
                            ),
                          ),
                          child: _buildInsightContent(
                            insightsProvider: insightsProvider,
                            data: data,
                            visibleSections: visibleSections,
                            hasSearchQuery: hasSearchQuery,
                          ),
                        ),
                      ),
                      _PaaccSupportCard(onContactTap: _openServices),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  T? _readProviderOrNull<T>(BuildContext context) {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  T? _watchProviderOrNull<T>(BuildContext context) {
    try {
      return context.watch<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  String _currentUserId() {
    final authProvider = _readProviderOrNull<AuthProvider>(context);
    final authUserId =
        authProvider?.userId ?? authProvider?.hydrateCurrentUser();
    if (authUserId != null && authUserId.isNotEmpty) return authUserId;

    final profileUserId = _readProviderOrNull<UserProvider>(context)?.user?.id;
    if (profileUserId != null && profileUserId.isNotEmpty) {
      return profileUserId;
    }

    return 'preview_user';
  }

  InsightRecommendationContext _recommendationContext() {
    return InsightRecommendationContext(
      userId: _currentUserId(),
      populationRole: _readProviderOrNull<UserProvider>(
        context,
      )?.user?.effectivePopulationRole,
    );
  }

  void _updateSearchQuery(String value) {
    setState(() => _searchQuery = value);
  }

  String _insightContentStateKey(
    InsightsProvider? provider,
    InsightsDashboardData? data,
    List<InsightSection> sections,
    bool hasSearchQuery,
  ) {
    if ((provider?.isLoading ?? false) && data == null) return 'loading';
    if (provider?.errorMessage != null && data == null) return 'error';
    if (data == null || data.resources.isEmpty) return 'empty';
    if (sections.isEmpty && hasSearchQuery) return 'no-results:$_searchQuery';
    return 'sections:${sections.map((section) => section.id).join(',')}:$_searchQuery';
  }

  Widget _buildInsightContent({
    required InsightsProvider? insightsProvider,
    required InsightsDashboardData? data,
    required List<InsightSection> visibleSections,
    required bool hasSearchQuery,
  }) {
    if ((insightsProvider?.isLoading ?? false) && data == null) {
      return const _InsightSectionSkeleton();
    }
    if (insightsProvider?.errorMessage != null && data == null) {
      return _InsightsErrorState(
        onRetry: () => insightsProvider?.loadInsights(
          _recommendationContext(),
          forceRefresh: true,
        ),
      );
    }
    if (data == null || data.resources.isEmpty) {
      return const _EmptyInsightState();
    }
    if (visibleSections.isEmpty && hasSearchQuery) {
      return _NoInsightResultsState(query: _searchQuery);
    }
    return Column(
      children: [
        for (final section in visibleSections) ...[
          _InsightSectionView(
            section: section,
            onItemTap: _openInsightArticle,
            onSeeAllTap: () => _openInsightSection(section),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  List<InsightSection> _visibleSections(InsightsDashboardData? data) {
    final query = _searchQuery.trim().toLowerCase();
    if (data == null) return const [];
    if (query.isEmpty) return data.sections;

    final matches = data.resources
        .where((item) => _matchesSearch(item, query))
        .toList(growable: false);
    if (matches.isEmpty) return const [];
    return [
      InsightSection(
        id: 'search_results',
        title: 'Search results',
        items: matches,
        showSeeAll: false,
      ),
    ];
  }

  bool _matchesSearch(InsightCardItem item, String query) {
    final values = [
      item.title,
      item.subtitle,
      item.category,
      item.categoryId,
      item.body ?? '',
      item.source ?? '',
      item.contentType ?? '',
      ...item.tags,
    ];

    return values.any((value) => value.toLowerCase().contains(query));
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InsightsNotificationsScreen()),
    );
  }

  void _openLogMood() {
    Navigator.of(context).pushNamed(RouteNames.logMood);
  }

  void _openServices() {
    Navigator.of(context).pushNamed(RouteNames.services);
  }

  void _openInsightArticle(InsightCardItem item) {
    if (item.isVideoPlaceholder) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Video coming soon')));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InsightArticleDetailScreen(item: item)),
    );
  }

  void _openCategory(InsightCategory category, InsightsDashboardData? data) {
    if (data == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InsightCategoryResourceScreen(
          category: category,
          resources: data.resourcesForCategory(category.id),
        ),
      ),
    );
  }

  void _openInsightSection(InsightSection section) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InsightSectionDetailScreen(
          section: section,
          onItemTap: _openInsightArticle,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onNotificationTap});

  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    return Container(
      key: const Key('insights_header'),
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.header,
        boxShadow: theme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x33B58500)),
            ),
            child: Image.asset(
              'assets/images/INSIGHTS/creativity_15557951 1.png',
              key: const Key('insights_header_brain_asset'),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.psychology_alt_rounded, size: 25),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MindMate',
                  style: _InsightsText.brandTitle.copyWith(
                    color: const Color(0xFF241B00),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Wellness insights',
                  style: _InsightsText.brandSubtitle.copyWith(
                    color: const Color(0xFF5F4900),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(210),
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              tooltip: 'Notifications',
              padding: EdgeInsets.zero,
              onPressed: onNotificationTap,
              icon: Image.asset(
                'assets/images/INSIGHTS/Notification.png',
                width: 22,
                height: 22,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.notifications_none_rounded, size: 23),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSearchCard extends StatelessWidget {
  const _HeroSearchCard({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    return Container(
      key: const Key('insights_hero'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.heroStart, theme.heroEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.border),
        boxShadow: theme.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Image.asset(
                'assets/images/INSIGHTS/Creativity.png',
                key: const Key('insights_hero_brain_asset'),
                width: 30,
                height: 30,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.psychology_alt_rounded,
                  color: Color(0xFFFF6F8F),
                  size: 28,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Insights',
                      key: const Key('insights_hero_title'),
                      style: TextStyle(
                        color: theme.isDark
                            ? const Color(0xFFFFF7E3)
                            : const Color(0xFF251C00),
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your mental wellness hub',
                      style: TextStyle(
                        color: theme.isDark
                            ? const Color(0xFFFFEAB0)
                            : const Color(0xFF6F5200),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.isDark
                      ? Colors.white.withAlpha(210)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset(
                  'assets/images/INSIGHTS/Pulse.png',
                  width: 28,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.monitor_heart, color: Colors.black),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: TextStyle(
              color: theme.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              border: InputBorder.none,
              hintText: 'Search insights...',
              hintStyle: TextStyle(
                color: theme.secondaryText,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 22,
                color: theme.isDark
                    ? const Color(0xFF9CCBFF)
                    : const Color(0xFF2D6EA7),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 32,
              ),
              filled: true,
              fillColor: theme.searchSurface,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: theme.border.withAlpha(100)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: theme.accent, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: _InsightsText.sectionTitle.copyWith(color: theme.text),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: theme.secondaryText,
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.categories, required this.onCategoryTap});

  final List<InsightCategory> categories;
  final ValueChanged<InsightCategory> onCategoryTap;

  @override
  Widget build(BuildContext context) {
    final sourceCategories = categories.isEmpty
        ? const [
            InsightCategory(
              id: 'emotional_wellbeing',
              label: 'Emotions',
              icon: 'mood',
            ),
            InsightCategory(
              id: 'stress_burnout',
              label: 'Stress relief',
              icon: 'stress',
            ),
            InsightCategory(
              id: 'sleep_mental_health',
              label: 'Better sleep',
              icon: 'sleep',
              isSelected: true,
            ),
            InsightCategory(
              id: 'anxiety',
              label: 'Manage anxiety',
              icon: 'anxiety',
            ),
            InsightCategory(
              id: 'self_esteem_confidence',
              label: 'Confidence',
              icon: 'mood',
            ),
            InsightCategory(
              id: 'depression_support',
              label: 'Low mood',
              icon: 'mood',
            ),
          ]
        : categories;
    final effectiveCategories = _orderedInsightCategories(sourceCategories);

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final tileWidth = ((constraints.maxWidth - (gap * 3)) / 4).clamp(
          76.0,
          86.0,
        );
        return SizedBox(
          key: const Key('insights_category_strip'),
          height: 104,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (
                  var index = 0;
                  index < effectiveCategories.length;
                  index++
                ) ...[
                  SizedBox(
                    width: tileWidth,
                    child: _CategoryTile(
                      category: effectiveCategories[index],
                      onTap: () => onCategoryTap(effectiveCategories[index]),
                    ),
                  ),
                  if (index != effectiveCategories.length - 1)
                    const SizedBox(width: gap),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

List<InsightCategory> _orderedInsightCategories(
  List<InsightCategory> categories,
) {
  const priority = {
    'emotional_wellbeing': 0,
    'stress_burnout': 1,
    'sleep_mental_health': 2,
    'anxiety': 3,
    'self_esteem_confidence': 4,
    'depression_support': 5,
  };
  final indexed = categories.indexed.toList(growable: false);
  indexed.sort((left, right) {
    final leftPriority = priority[left.$2.id] ?? (100 + left.$1);
    final rightPriority = priority[right.$2.id] ?? (100 + right.$1);
    return leftPriority.compareTo(rightPriority);
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

String _categoryDisplayLabel(InsightCategory category) {
  if (category.id == 'emotional_wellbeing') return 'Mood tracking';
  return category.label;
}

Duration _insightsMotionDuration(BuildContext context, int milliseconds) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return reduceMotion ? Duration.zero : Duration(milliseconds: milliseconds);
}

class _InsightsPressScale extends StatefulWidget {
  const _InsightsPressScale({required this.child});

  final Widget child;

  @override
  State<_InsightsPressScale> createState() => _InsightsPressScaleState();
}

class _InsightsPressScaleState extends State<_InsightsPressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final duration = _insightsMotionDuration(context, 140);
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        key: const Key('insights_press_scale'),
        scale: _pressed ? 0.98 : 1,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.94 : 1,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final InsightCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    final style = _resolvedCategoryVisualStyle(
      context,
      category.id,
      category.icon,
    );
    final displayLabel = _categoryDisplayLabel(category);
    final selected = category.isSelected;
    final surface = selected ? theme.selectedCategory : style.surface;
    final border = selected ? theme.selectedCategoryBorder : style.border;
    final foreground = selected ? theme.onSelectedCategory : theme.text;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Explore $displayLabel',
      child: _InsightsPressScale(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('insights_category_${category.id}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(15),
            child: Ink(
              key: Key('insights_category_surface_${category.id}'),
              padding: const EdgeInsets.fromLTRB(6, 9, 6, 8),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: border),
                boxShadow: theme.tileShadow,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CategoryVisual(style: style, size: 42, selected: selected),
                  const SizedBox(height: 7),
                  Text(
                    displayLabel,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 10,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryVisual extends StatelessWidget {
  const _CategoryVisual({
    required this.style,
    required this.size,
    this.selected = false,
  });

  final _CategoryVisualStyle style;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('insights_category_visual_${style.id}'),
      width: size,
      height: size,
      padding: EdgeInsets.all(style.assetName == null ? 11 : 7),
      decoration: BoxDecoration(
        color: selected ? Colors.white.withAlpha(150) : style.badge,
        borderRadius: BorderRadius.circular(size * 0.34),
        border: Border.all(
          color: selected ? Colors.white.withAlpha(190) : style.border,
        ),
      ),
      child: style.assetName == null
          ? Icon(
              style.icon,
              key: Key('insights_category_fallback_${style.id}'),
              color: style.accent,
              size: size * 0.5,
            )
          : Image.asset(
              style.assetName!,
              key: Key('insights_category_asset_${style.id}'),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(style.icon, color: style.accent, size: size * 0.5),
            ),
    );
  }
}

class _WeeklyGlanceCard extends StatelessWidget {
  const _WeeklyGlanceCard({
    required this.metrics,
    required this.onLogMoodTap,
    required this.actionLabel,
  });

  final InsightMetricsSummary metrics;
  final VoidCallback onLogMoodTap;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    final items = [
      InsightMetric(
        label: 'Check-ins',
        value: '${metrics.checkIns}',
        icon: 'fire',
      ),
      InsightMetric(
        label: 'Good days',
        value: '${metrics.goodDays}',
        icon: 'mood',
      ),
      InsightMetric(
        label: 'Total logs',
        value: '${metrics.totalLogs}',
        icon: 'chart',
      ),
    ];

    return Container(
      key: const Key('insights_weekly_card'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      decoration: theme.card(radius: 18),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'This week at a glance',
                  style: _InsightsText.sectionTitle.copyWith(color: theme.text),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                key: const Key('insights_log_mood_action'),
                onPressed: onLogMoodTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accent,
                  foregroundColor: theme.onAccent,
                  elevation: 0,
                  minimumSize: const Size(92, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  actionLabel.startsWith('View')
                      ? "View today's mood"
                      : 'Log mood',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                Expanded(
                  child: _MetricColumn(metric: items[index], index: index),
                ),
                if (index != items.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({required this.metric, required this.index});

  final InsightMetric metric;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    final accents = [
      const Color(0xFFA86500),
      const Color(0xFF397250),
      const Color(0xFF476C9E),
    ];

    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accents[index % accents.length].withAlpha(theme.isDark ? 48 : 22),
          theme.surfaceMuted,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _metricIcon(metric.icon),
            size: 23,
            color: theme.isDark
                ? Color.lerp(
                    accents[index % accents.length],
                    Colors.white,
                    0.42,
                  )
                : accents[index % accents.length],
          ),
          const SizedBox(height: 6),
          Text(
            metric.value,
            style: _InsightsText.metricValue.copyWith(color: theme.text),
          ),
          const SizedBox(height: 3),
          Text(
            metric.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _InsightsText.metricLabel.copyWith(color: theme.text),
          ),
        ],
      ),
    );
  }

  IconData _metricIcon(String key) {
    switch (key) {
      case 'fire':
        return Icons.local_fire_department;
      case 'chart':
        return Icons.bar_chart;
      case 'mood':
      default:
        return Icons.sentiment_satisfied_alt;
    }
  }
}

class _InsightSectionView extends StatelessWidget {
  const _InsightSectionView({
    required this.section,
    required this.onItemTap,
    required this.onSeeAllTap,
  });

  final InsightSection section;
  final ValueChanged<InsightCardItem> onItemTap;
  final VoidCallback onSeeAllTap;

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                section.title,
                style: _InsightsText.sectionTitle.copyWith(color: theme.text),
              ),
            ),
            if (section.showSeeAll)
              TextButton(
                onPressed: onSeeAllTap,
                style: TextButton.styleFrom(
                  foregroundColor: theme.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(72, 44),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See all',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(Icons.arrow_forward_rounded, size: 13),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: section.id == 'patterns' ? 148 : 140,
          child: section.items.isEmpty
              ? const _InlineEmptyState()
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: section.items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    return _InsightCard(
                      item: section.items[index],
                      isPatternCard: section.id == 'patterns',
                      onTap: () => onItemTap(section.items[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class InsightCategoryResourceScreen extends StatelessWidget {
  const InsightCategoryResourceScreen({
    required this.category,
    required this.resources,
    super.key,
  });

  final InsightCategory category;
  final List<InsightCardItem> resources;

  @override
  Widget build(BuildContext context) {
    final articles = resources
        .where((item) => !item.isVideoPlaceholder)
        .toList(growable: false);
    final videos = resources
        .where((item) => item.isVideoPlaceholder)
        .toList(growable: false);
    final featured = articles.firstOrNull;

    return Scaffold(
      backgroundColor: _InsightsPalette.background,
      appBar: AppBar(
        title: Text(category.label),
        backgroundColor: _InsightsPalette.sun,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 36),
        children: [
          _CategoryHero(category: category, articleCount: articles.length),
          if (featured != null) ...[
            const SizedBox(height: 22),
            const _SectionHeading(
              title: 'Featured resource',
              subtitle: 'A helpful place to begin',
            ),
            const SizedBox(height: 12),
            _FeaturedResourceCard(
              item: featured,
              onTap: () => _openArticle(context, featured),
            ),
          ],
          const SizedBox(height: 24),
          _SectionHeading(
            title: 'Articles and guides',
            subtitle:
                '${articles.length} resource${articles.length == 1 ? '' : 's'} available',
          ),
          const SizedBox(height: 12),
          if (articles.isEmpty)
            const _CategoryEmptyState()
          else
            for (final item in articles) ...[
              _SectionDetailCard(
                item: item,
                onTap: () => _openArticle(context, item),
              ),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 12),
          const _SectionHeading(
            title: 'Videos',
            subtitle: 'Guided learning resources are being prepared',
          ),
          const SizedBox(height: 12),
          for (final video in videos) _VideoComingSoonCard(item: video),
        ],
      ),
    );
  }

  void _openArticle(BuildContext context, InsightCardItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InsightArticleDetailScreen(item: item),
      ),
    );
  }
}

class _CategoryHero extends StatelessWidget {
  const _CategoryHero({required this.category, required this.articleCount});

  final InsightCategory category;
  final int articleCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD45B), Color(0xFFFFE9A2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(_iconForCategory(category.icon), size: 28),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.label, style: _InsightsText.sectionTitle),
                const SizedBox(height: 7),
                Text(
                  _categoryIntroduction(category.id),
                  style: const TextStyle(fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 10),
                Text(
                  '$articleCount educational resource${articleCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedResourceCard extends StatelessWidget {
  const _FeaturedResourceCard({required this.item, required this.onTap});

  final InsightCardItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _resolvedCategoryVisualStyle(
      context,
      item.categoryId,
      'mood',
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: _InsightsTheme.of(context).card(radius: 22),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: style.badge,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(Icons.auto_stories_outlined, color: style.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: _InsightsText.sectionTitle),
                    const SizedBox(height: 5),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: style.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: style.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoComingSoonCard extends StatelessWidget {
  const _VideoComingSoonCard({required this.item});

  final InsightCardItem item;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: false,
      label: '${item.title}. Video coming soon.',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F0E5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDDD4BE)),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFE4DDCD),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.play_circle_outline, size: 31),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Video coming soon',
                    style: TextStyle(fontSize: 12, color: Color(0xFF716956)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.lock_clock_outlined, color: Color(0xFF8A816D)),
          ],
        ),
      ),
    );
  }
}

class _CategoryEmptyState extends StatelessWidget {
  const _CategoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _InsightsTheme.of(context).card(radius: 18),
      child: const Column(
        children: [
          Icon(Icons.menu_book_outlined, size: 32),
          SizedBox(height: 10),
          Text(
            'Resources are being prepared',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 5),
          Text(
            'Check back soon for articles and practical guides.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

IconData _iconForCategory(String key) => switch (key) {
  'stress' => Icons.self_improvement,
  'sleep' => Icons.bedtime_outlined,
  'anxiety' => Icons.cloud_outlined,
  _ => Icons.sentiment_satisfied_alt,
};

String _categoryIntroduction(String id) => switch (id) {
  'stress_burnout' =>
    'Understand everyday stress, recognize overload, and explore practical ways to recover.',
  'anxiety' =>
    'Learn how anxious feelings can appear and practice supportive ways to respond.',
  'emotional_wellbeing' =>
    'Build emotional awareness, name what you feel, and express emotions safely.',
  'sleep_mental_health' =>
    'Explore how sleep affects mood, concentration, energy, and recovery.',
  'self_esteem_confidence' =>
    'Strengthen self-respect, realistic confidence, and a healthy growth mindset.',
  'depression_support' =>
    'Understand low-mood experiences and learn when additional support may help.',
  _ =>
    'Explore practical information for supporting mental health and well-being.',
};

class InsightSectionDetailScreen extends StatelessWidget {
  const InsightSectionDetailScreen({
    super.key,
    required this.section,
    required this.onItemTap,
  });

  final InsightSection section;
  final ValueChanged<InsightCardItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _InsightsPalette.background,
      appBar: AppBar(
        title: Text(section.title),
        backgroundColor: _InsightsPalette.sun,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView.separated(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        itemCount: section.items.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = section.items[index];
          return _SectionDetailCard(item: item, onTap: () => onItemTap(item));
        },
      ),
    );
  }
}

class _SectionDetailCard extends StatelessWidget {
  const _SectionDetailCard({required this.item, required this.onTap});

  final InsightCardItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: _InsightsTheme.of(context).card(radius: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: _InsightsPalette.sun,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.insights, color: Colors.black87),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CategoryPill(label: item.category),
                    const SizedBox(height: 8),
                    Text(item.title, style: _InsightsText.sectionTitle),
                    const SizedBox(height: 5),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF5E533B),
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.item,
    required this.isPatternCard,
    required this.onTap,
  });

  final InsightCardItem item;
  final bool isPatternCard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    return SizedBox(
      width: 214,
      child: _InsightsPressScale(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                color: isPatternCard
                    ? (theme.isDark
                          ? const Color(0xFF59450E)
                          : const Color(0xFFFFDE83))
                    : theme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: theme.border),
                boxShadow: theme.cardShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!isPatternCard) _ResourceThumbnail(item: item),
                    if (!isPatternCard)
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x05FFFFFF), Color(0xB0000000)],
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CategoryPill(label: item.category),
                          if (item.isVideoPlaceholder) ...[
                            const SizedBox(height: 6),
                            const _CategoryPill(label: 'Video coming soon'),
                          ],
                          const Spacer(),
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isPatternCard ? theme.text : Colors.white,
                              fontSize: 13,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isPatternCard
                                  ? theme.secondaryText
                                  : Colors.white,
                              fontSize: 10,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResourceThumbnail extends StatelessWidget {
  const _ResourceThumbnail({required this.item});

  final InsightCardItem item;

  @override
  Widget build(BuildContext context) {
    if (item.imageAsset.trim().isEmpty) {
      return _ResourceThumbnailFallback(item: item);
    }

    return Image.asset(
      item.imageAsset,
      key: Key('insights_resource_image_${item.id}'),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          _ResourceThumbnailFallback(item: item),
    );
  }
}

class _ResourceThumbnailFallback extends StatelessWidget {
  const _ResourceThumbnailFallback({required this.item});

  final InsightCardItem item;

  @override
  Widget build(BuildContext context) {
    final style = _resolvedCategoryVisualStyle(
      context,
      item.categoryId,
      'mood',
    );
    return DecoratedBox(
      key: Key('insights_resource_fallback_${item.id}'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [style.surface, style.badge],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Align(
        alignment: const Alignment(0.68, -0.42),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(180),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(style.icon, size: 29, color: style.accent),
        ),
      ),
    );
  }
}

class InsightArticleDetailScreen extends StatelessWidget {
  const InsightArticleDetailScreen({super.key, required this.item});

  final InsightCardItem item;

  @override
  Widget build(BuildContext context) {
    final body = item.body?.trim().isNotEmpty == true
        ? item.body!.trim()
        : item.subtitle;
    final metadata = _metadataText(item);
    final isSupportContent =
        item.contentType == 'support' ||
        item.tags.any((tag) => tag.toLowerCase().contains('pacc'));

    return Scaffold(
      backgroundColor: _InsightsPalette.background,
      appBar: AppBar(
        title: const Text('Insight'),
        backgroundColor: _InsightsPalette.sun,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          if (item.imageAsset.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.asset(
                  item.imageAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const _ArticleImageFallback(),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _InsightsTheme.of(context).card(radius: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _CategoryPill(label: item.category),
                ),
                const SizedBox(height: 14),
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 24,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    color: Color(0xFF514832),
                    fontSize: 14,
                    height: 1.42,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (metadata.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    metadata,
                    style: const TextStyle(
                      color: Color(0xFF8D7F5E),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF2F2A1D),
                    fontSize: 14,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in item.tags) _ArticleTagChip(label: tag),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (isSupportContent) ...[
            const SizedBox(height: 14),
            const _ArticleSupportPanel(),
          ],
        ],
      ),
    );
  }

  String _metadataText(InsightCardItem item) {
    final parts = <String>[];
    if (item.source?.trim().isNotEmpty == true) {
      parts.add(item.source!.trim());
    }

    final publishedAt = item.publishedAt;
    if (publishedAt != null) {
      parts.add(_formatDate(publishedAt));
    }

    return parts.join(' • ');
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _ArticleImageFallback extends StatelessWidget {
  const _ArticleImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _InsightsPalette.sun,
      alignment: Alignment.center,
      child: const Icon(Icons.insights, size: 44, color: Colors.black87),
    );
  }
}

class _ArticleTagChip extends StatelessWidget {
  const _ArticleTagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1BE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _InsightsPalette.gold.withValues(alpha: .45)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ArticleSupportPanel extends StatelessWidget {
  const _ArticleSupportPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _InsightsPalette.sun,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.favorite, size: 24, color: Colors.black87),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'If this feels familiar, PACC support is available. Reaching out early is a healthy support step.',
              style: TextStyle(
                color: Colors.black,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(_pillIcon(label), size: 13, color: Colors.black87),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  IconData _pillIcon(String label) {
    switch (label.toLowerCase()) {
      case 'your data':
        return Icons.bar_chart;
      case 'trending':
        return Icons.trending_up;
      case 'academic':
        return Icons.school;
      case 'self-care':
        return Icons.edit;
      case 'social':
        return Icons.groups_2;
      case 'sleep':
        return Icons.bedtime;
      case 'wellbeing':
        return Icons.favorite_border;
      case 'mindfulness':
        return Icons.self_improvement;
      default:
        return Icons.auto_awesome;
    }
  }
}

class _PaaccSupportCard extends StatelessWidget {
  const _PaaccSupportCard({required this.onContactTap});

  final VoidCallback onContactTap;

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PAACC support services',
          style: _InsightsText.sectionTitle.copyWith(color: theme.text),
        ),
        const SizedBox(height: 14),
        Container(
          key: const Key('insights_paacc_card'),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 21, 20, 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [theme.surface, theme.surfaceMuted],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.border),
            boxShadow: theme.cardShadow,
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFFFFE6EC),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(9),
                      child: Icon(
                        Icons.favorite_rounded,
                        color: Color(0xFFB9506D),
                        size: 23,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Need to talk to someone?',
                      style: TextStyle(
                        color: theme.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  "PAACC counseling services are available 24/7 for students and faculty. You're never alone.",
                  style: TextStyle(
                    color: theme.secondaryText,
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: onContactTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accent,
                    foregroundColor: theme.onAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
                    'Contact counselor',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: _InsightsTheme.of(context).card(radius: 20),
      child: Center(
        child: Text(
          'Insights will appear here when content is connected.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.secondaryText,
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _EmptyInsightState extends StatelessWidget {
  const _EmptyInsightState();

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _InsightsTheme.of(context).card(radius: 20),
      child: Column(
        children: [
          Icon(Icons.auto_stories_outlined, size: 34, color: theme.accent),
          const SizedBox(height: 10),
          Text(
            'No wellness resources are available yet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightsErrorState extends StatelessWidget {
  const _InsightsErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _InsightsTheme.of(context).card(radius: 18),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 34),
          const SizedBox(height: 10),
          const Text(
            'We couldn’t load wellness resources.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Check your connection and try again.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _InsightsErrorBanner extends StatelessWidget {
  const _InsightsErrorBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.border),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: theme.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Showing saved resources. Refresh didn’t complete.',
              style: TextStyle(
                color: theme.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _NoInsightResultsState extends StatelessWidget {
  const _NoInsightResultsState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _InsightsTheme.of(context).card(radius: 12),
      child: Text(
        'No insights found for "$query".',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: theme.secondaryText,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class InsightsNotificationsScreen extends StatelessWidget {
  const InsightsNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _InsightsPalette.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: _InsightsPalette.sun,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(22),
          decoration: _InsightsTheme.of(context).card(radius: 12),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_none,
                color: _InsightsPalette.gold,
                size: 42,
              ),
              SizedBox(height: 12),
              Text(
                'No insight notifications yet',
                textAlign: TextAlign.center,
                style: _InsightsText.sectionTitle,
              ),
              SizedBox(height: 8),
              Text(
                'Updates about new recommendations and wellness content will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6F654D),
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightSectionSkeleton extends StatelessWidget {
  const _InsightSectionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 180, height: 16, color: const Color(0x22B88B00)),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 203,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0x22B88B00),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0x18B88B00),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _InsightsBackground extends StatelessWidget {
  const _InsightsBackground();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        _Circle(top: 90, right: 0, size: 44),
        _Circle(top: 205, left: -10, size: 44),
        _Circle(top: 575, right: 58, size: 44),
        _Circle(top: 810, left: -8, size: 36),
        _Circle(bottom: 88, left: 66, size: 38),
        _Circle(bottom: 26, right: 162, size: 40),
      ],
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({
    this.top,
    this.left,
    this.right,
    this.bottom,
    required this.size,
  });

  final double? top;
  final double? left;
  final double? right;
  final double? bottom;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = _InsightsTheme.of(context);
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: theme.accent.withAlpha(theme.isDark ? 20 : 42),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _InsightsTheme {
  const _InsightsTheme({
    required this.isDark,
    required this.background,
    required this.header,
    required this.surface,
    required this.surfaceMuted,
    required this.text,
    required this.secondaryText,
    required this.border,
    required this.accent,
    required this.onAccent,
    required this.heroStart,
    required this.heroEnd,
    required this.searchSurface,
    required this.selectedCategory,
    required this.selectedCategoryBorder,
    required this.onSelectedCategory,
  });

  factory _InsightsTheme.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const _InsightsTheme(
        isDark: true,
        background: Color(0xFF15120D),
        header: Color(0xFFE0A500),
        surface: Color(0xFF241F17),
        surfaceMuted: Color(0xFF30291E),
        text: Color(0xFFFFF7E3),
        secondaryText: Color(0xFFD8CBAA),
        border: Color(0xFF80661E),
        accent: Color(0xFFFFC42E),
        onAccent: Color(0xFF241B00),
        heroStart: Color(0xFF6A4E00),
        heroEnd: Color(0xFF3A2E11),
        searchSurface: Color(0xFF2B251C),
        selectedCategory: Color(0xFFFFBC00),
        selectedCategoryBorder: Color(0xFFFFD464),
        onSelectedCategory: Color(0xFF211800),
      );
    }
    return const _InsightsTheme(
      isDark: false,
      background: Color(0xFFFFF7DB),
      header: Color(0xFFFFCB30),
      surface: Color(0xFFFFFFFF),
      surfaceMuted: Color(0xFFFFFBEE),
      text: Color(0xFF17130B),
      secondaryText: Color(0xFF6F603D),
      border: Color(0xFFE7AF15),
      accent: Color(0xFFF5B800),
      onAccent: Color(0xFF211800),
      heroStart: Color(0xFFFFC30B),
      heroEnd: Color(0xFFFFD75B),
      searchSurface: Color(0xFFFFFFFF),
      selectedCategory: Color(0xFFFFBC00),
      selectedCategoryBorder: Color(0xFFE9A900),
      onSelectedCategory: Color(0xFF211800),
    );
  }

  final bool isDark;
  final Color background;
  final Color header;
  final Color surface;
  final Color surfaceMuted;
  final Color text;
  final Color secondaryText;
  final Color border;
  final Color accent;
  final Color onAccent;
  final Color heroStart;
  final Color heroEnd;
  final Color searchSurface;
  final Color selectedCategory;
  final Color selectedCategoryBorder;
  final Color onSelectedCategory;

  List<BoxShadow> get cardShadow => isDark
      ? const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ];

  List<BoxShadow> get tileShadow => isDark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 7,
            offset: Offset(0, 3),
          ),
        ];

  BoxDecoration card({double radius = 18, Color? color}) {
    return BoxDecoration(
      color: color ?? surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border.withAlpha(isDark ? 150 : 115)),
      boxShadow: cardShadow,
    );
  }
}

class _CategoryVisualStyle {
  const _CategoryVisualStyle({
    required this.id,
    required this.surface,
    required this.badge,
    required this.border,
    required this.accent,
    required this.icon,
    this.assetName,
  });

  final String id;
  final Color surface;
  final Color badge;
  final Color border;
  final Color accent;
  final IconData icon;
  final String? assetName;
}

_CategoryVisualStyle _categoryVisualStyle(String id, String iconKey) {
  return switch (id) {
    'stress_burnout' => const _CategoryVisualStyle(
      id: 'stress_burnout',
      surface: Color(0xFFFFF4D5),
      badge: Color(0xFFFFE7A8),
      border: Color(0xFFE9C96C),
      accent: Color(0xFF8B6200),
      icon: Icons.self_improvement_rounded,
      assetName: 'assets/images/INSIGHTS/🧘 Stress relief.png',
    ),
    'anxiety' => const _CategoryVisualStyle(
      id: 'anxiety',
      surface: Color(0xFFEAF2FD),
      badge: Color(0xFFD7E7FA),
      border: Color(0xFFB8CEE8),
      accent: Color(0xFF3E6798),
      icon: Icons.cloud_outlined,
      assetName: 'assets/images/INSIGHTS/💭 Manage anxiety.png',
    ),
    'emotional_wellbeing' => const _CategoryVisualStyle(
      id: 'emotional_wellbeing',
      surface: Color(0xFFE9F5EA),
      badge: Color(0xFFD5ECD8),
      border: Color(0xFFB7D8BD),
      accent: Color(0xFF397250),
      icon: Icons.sentiment_satisfied_alt_rounded,
      assetName: 'assets/images/INSIGHTS/😊 Mood tracking.png',
    ),
    'sleep_mental_health' => const _CategoryVisualStyle(
      id: 'sleep_mental_health',
      surface: Color(0xFFF0ECFC),
      badge: Color(0xFFE2DAF8),
      border: Color(0xFFC9BDE9),
      accent: Color(0xFF625394),
      icon: Icons.bedtime_rounded,
      assetName: 'assets/images/INSIGHTS/😴 Better sleep.png',
    ),
    'self_esteem_confidence' => const _CategoryVisualStyle(
      id: 'self_esteem_confidence',
      surface: Color(0xFFFFEEE4),
      badge: Color(0xFFFFDDC9),
      border: Color(0xFFE9C1AA),
      accent: Color(0xFF95583A),
      icon: Icons.workspace_premium_rounded,
    ),
    'depression_support' => const _CategoryVisualStyle(
      id: 'depression_support',
      surface: Color(0xFFFCEBF0),
      badge: Color(0xFFF8D9E2),
      border: Color(0xFFE5BAC7),
      accent: Color(0xFF994D65),
      icon: Icons.favorite_rounded,
    ),
    _ => _CategoryVisualStyle(
      id: id.isEmpty ? 'neutral' : id,
      surface: const Color(0xFFF7F1E2),
      badge: const Color(0xFFEDE2C6),
      border: const Color(0xFFD8CAA8),
      accent: const Color(0xFF715F35),
      icon: _fallbackCategoryIcon(iconKey),
    ),
  };
}

_CategoryVisualStyle _resolvedCategoryVisualStyle(
  BuildContext context,
  String id,
  String iconKey,
) {
  final base = _categoryVisualStyle(id, iconKey);
  final theme = _InsightsTheme.of(context);
  if (!theme.isDark) return base;
  final accent = Color.lerp(base.accent, Colors.white, 0.38)!;
  return _CategoryVisualStyle(
    id: base.id,
    surface: Color.alphaBlend(base.accent.withAlpha(38), theme.surface),
    badge: Color.alphaBlend(base.accent.withAlpha(58), theme.surfaceMuted),
    border: base.accent.withAlpha(170),
    accent: accent,
    icon: base.icon,
    assetName: base.assetName,
  );
}

IconData _fallbackCategoryIcon(String key) => switch (key) {
  'stress' => Icons.self_improvement_rounded,
  'sleep' => Icons.bedtime_rounded,
  'anxiety' => Icons.cloud_outlined,
  _ => Icons.auto_awesome_rounded,
};

class _InsightsPalette {
  const _InsightsPalette._();

  static const background = Color(0xFFFFF9E9);
  static const sun = Color(0xFFFFCA24);
  static const gold = Color(0xFFB98200);
  static const ink = Color(0xFF292316);
  static const mutedInk = Color(0xFF675B3D);
}

class _InsightsText {
  const _InsightsText._();

  static const sectionTitle = TextStyle(
    color: _InsightsPalette.ink,
    fontSize: 15,
    fontWeight: FontWeight.w900,
  );

  static const brandTitle = TextStyle(
    color: _InsightsPalette.ink,
    fontSize: 18,
    height: 1,
    fontWeight: FontWeight.w900,
  );

  static const brandSubtitle = TextStyle(
    color: _InsightsPalette.mutedInk,
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
  );

  static const metricValue = TextStyle(
    fontSize: 16,
    height: 1,
    fontWeight: FontWeight.w900,
  );

  static const metricLabel = TextStyle(
    fontSize: 10,
    height: 1.1,
    fontWeight: FontWeight.w900,
  );
}
