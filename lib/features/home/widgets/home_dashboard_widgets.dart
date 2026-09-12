import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../data/daily_affirmation_quotes.dart';
import '../models/home_dashboard_data.dart';

class HomePalette {
  const HomePalette._();

  static const background = Color(0xFFF7F1DF);
  static const surface = Color(0xFFFFFEFA);
  static const surfaceWarm = Color(0xFFFFFAEE);
  static const sun = Color(0xFFFFC414);
  static const softGold = Color(0xFFFFD75C);
  static const gold = Color(0xFFE9B000);
  static const orange = Color(0xFFFFA000);
  static const mutedGold = Color(0xFFB8922F);
  static const text = Color(0xFF17120A);
  static const muted = Color(0xFF6C665B);
  static const blueText = Color(0xFF66736F);
  static const outline = Color(0x1F5F5035);
  static const outlineStrong = Color(0x385F5035);
  static const shadow = Color(0x140F0B05);
  static const shadowStrong = Color(0x210F0B05);
}

class HomeMetrics {
  const HomeMetrics._();

  static const radiusSmall = 12.0;
  static const radius = 16.0;
  static const radiusLarge = 20.0;
  static const sectionGap = 22.0;
  static const cardPadding = 16.0;
}

class HomeMotion {
  const HomeMotion._();

  static Duration duration(BuildContext context, int milliseconds) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return reduceMotion ? Duration.zero : Duration(milliseconds: milliseconds);
  }
}

class HomeTextStyles {
  const HomeTextStyles._();

  static const sectionTitle = TextStyle(
    color: Color(0xFF3B312B),
    fontSize: 18,
    height: 1.15,
    letterSpacing: -.2,
    fontWeight: FontWeight.w800,
  );

  static const cardTitle = TextStyle(
    color: HomePalette.text,
    fontSize: 13,
    height: 1.18,
    fontWeight: FontWeight.w800,
  );

  static const body = TextStyle(
    color: HomePalette.text,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );

  static const bodyMuted = TextStyle(
    color: HomePalette.blueText,
    fontSize: 11,
    height: 1.25,
    fontWeight: FontWeight.w600,
  );

  static const caption = TextStyle(
    color: HomePalette.muted,
    fontSize: 10,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );

  static const button = TextStyle(
    color: HomePalette.text,
    fontSize: 13,
    fontWeight: FontWeight.w800,
  );
}

class HomeDecor {
  const HomeDecor._();

  static BoxDecoration card({
    Color color = HomePalette.surface,
    Color shadowColor = HomePalette.shadow,
    Color? borderColor,
    double radius = HomeMetrics.radius,
  }) {
    return BoxDecoration(
      color: color,
      border: Border.all(color: borderColor ?? HomePalette.outline),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: shadowColor,
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }
}

class HomeCalendarHeader extends StatelessWidget {
  const HomeCalendarHeader({
    super.key,
    required this.title,
    required this.days,
    required this.onProfileTap,
    required this.onCalendarTap,
  });

  final String title;
  final List<HomeDayData> days;
  final VoidCallback onProfileTap;
  final VoidCallback onCalendarTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFD24E), HomePalette.sun],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(bottom: BorderSide(color: Color(0x33A87900))),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: HomePalette.shadowStrong,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              HomeCircleIconButton(
                icon: Icons.person_outline,
                assetName: 'Customer.png',
                assetColor: HomePalette.text,
                tooltip: 'Profile',
                onTap: onProfileTap,
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HomePalette.text,
                    fontSize: 24,
                    letterSpacing: -.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              HomeCircleIconButton(
                icon: Icons.calendar_today_outlined,
                assetName: 'Calendar.png',
                tooltip: 'Calendar',
                onTap: onCalendarTap,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(days.length, (index) {
              return Expanded(
                child: Center(child: _DayChip(day: days[index])),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day});

  final HomeDayData day;

  @override
  Widget build(BuildContext context) {
    final isFuture = !day.isPast && !day.isToday;
    final backgroundColor = day.isToday
        ? HomePalette.gold
        : day.hasActivity && day.isPast
        ? const Color(0xFFFFE8A3)
        : isFuture
        ? const Color(0xFFF2EEE4)
        : Colors.white;
    final textColor = isFuture ? HomePalette.muted : HomePalette.text;

    return AnimatedContainer(
      duration: HomeMotion.duration(context, 180),
      curve: Curves.easeOut,
      width: 40,
      height: 44,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: day.isToday
              ? const Color(0xFF9A7000)
              : day.hasActivity && day.isPast
              ? HomePalette.gold
              : const Color(0x22FFFFFF),
          width: day.isToday ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: HomePalette.shadow,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                day.label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 10,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                day.date,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeAssessmentBanner extends StatelessWidget {
  const HomeAssessmentBanner({
    super.key,
    required this.data,
    required this.onStart,
    required this.onClose,
  });

  final HomeAssessmentPromptData data;
  final VoidCallback onStart;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: HomeDecor.card(
        color: const Color(0xFFF1F3FF),
        borderColor: const Color(0x665C7CFF),
        shadowColor: const Color(0x185C7CFF),
        radius: HomeMetrics.radiusLarge,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: HomeDashboardAssetImage(
              assetName: 'High Importance.png',
              width: 24,
              height: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: HomeTextStyles.cardTitle,
                ),
                const SizedBox(height: 4),
                Text(
                  data.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: HomeTextStyles.bodyMuted,
                ),
                const SizedBox(height: 10),
                HomePillButton(
                  label: data.actionLabel,
                  icon: Icons.arrow_forward,
                  assetName: 'Forward.png',
                  onTap: onStart,
                ),
              ],
            ),
          ),
          HomePlainIconButton(
            icon: Icons.close,
            assetName: 'x.png',
            tooltip: 'Dismiss',
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

class HomeWelcomeCard extends StatelessWidget {
  const HomeWelcomeCard({
    super.key,
    required this.user,
    required this.onNotificationTap,
    required this.onCalendarTap,
    required this.onProfileTap,
  });

  final HomeUserData user;
  final VoidCallback onNotificationTap;
  final VoidCallback onCalendarTap;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final displayName = user.displayName.trim();
    final welcomeText = displayName.isEmpty
        ? 'Welcome back!'
        : 'Welcome back, $displayName!';

    return Container(
      padding: const EdgeInsets.all(HomeMetrics.cardPadding),
      decoration: HomeDecor.card(radius: HomeMetrics.radiusLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HomeCircleIconButton(
                icon: Icons.person_outline,
                assetName: 'Customer.png',
                assetColor: HomePalette.text,
                tooltip: 'Profile',
                onTap: onProfileTap,
                size: 36,
                iconSize: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      welcomeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HomePalette.orange,
                        fontSize: 21,
                        letterSpacing: -.35,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HomeTextStyles.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              HomeCircleIconButton(
                icon: Icons.calendar_today_outlined,
                assetName: 'Calendar.png',
                tooltip: 'Calendar',
                onTap: onCalendarTap,
                size: 36,
                iconSize: 20,
              ),
              const SizedBox(width: 8),
              HomeCircleIconButton(
                icon: Icons.notifications_none,
                assetName: 'Notification.png',
                tooltip: 'Notifications',
                onTap: onNotificationTap,
                size: 36,
                iconSize: 20,
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'How are you feeling today?',
            style: TextStyle(
              color: HomePalette.mutedGold,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class HomeDashboardBackground extends StatelessWidget {
  const HomeDashboardBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: CustomPaint(painter: _HomeBubblePainter()));
  }
}

class _HomeBubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 86),
      Paint()..color = HomePalette.sun,
    );
    final bubbles = <(Offset, double, Color)>[
      (Offset(size.width * .54, 195), 17, const Color(0x55FFD75C)),
      (Offset(size.width * .92, 330), 16, const Color(0x3DFFD75C)),
      (Offset(size.width * .12, 690), 19, const Color(0x42E8D7A0)),
      (Offset(size.width * .93, 790), 17, const Color(0x4DFFD75C)),
      (Offset(size.width * .20, 1170), 18, const Color(0x55D5C58E)),
      (Offset(size.width * .88, 1480), 18, const Color(0x48FFD75C)),
      (Offset(size.width * .24, 1840), 17, const Color(0x55D5C58E)),
    ];
    for (final bubble in bubbles) {
      canvas.drawCircle(bubble.$1, bubble.$2, Paint()..color = bubble.$3);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HomeAnnouncementCard extends StatelessWidget {
  const HomeAnnouncementCard({
    super.key,
    required this.onViewMore,
    required this.onViewDetail,
    this.badge = 'LIVE',
    this.message =
        'Join our mental health talk live on Facebook at 6:00 AM today',
    this.isOpen,
  });

  final VoidCallback onViewMore;
  final VoidCallback onViewDetail;
  final String badge;
  final String message;
  final bool? isOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Announcement',
          actionLabel: 'View More',
          onAction: onViewMore,
        ),
        const SizedBox(height: 8),
        Material(
          color: HomePalette.surface,
          borderRadius: BorderRadius.circular(HomeMetrics.radius),
          child: InkWell(
            onTap: onViewDetail,
            borderRadius: BorderRadius.circular(HomeMetrics.radius),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: HomeDecor.card(
                borderColor: const Color(0x99FFC414),
                radius: HomeMetrics.radius,
              ),
              child: Row(
                children: [
                  const Text('📣', style: TextStyle(fontSize: 30)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: isOpen == true
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFFF102B),
                            borderRadius: const BorderRadius.all(
                              Radius.circular(20),
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 3,
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(message, style: HomeTextStyles.bodyMuted),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onViewDetail,
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFE5C3F4),
                      foregroundColor: const Color(0xFF6A2E83),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'View Detail',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class HomeStreakCard extends StatelessWidget {
  const HomeStreakCard({super.key, required this.data, required this.onTap});

  final HomeStreakData? data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final streak = data;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(HomeMetrics.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [HomePalette.softGold, HomePalette.sun],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: const Color(0x269A7000)),
            borderRadius: BorderRadius.circular(HomeMetrics.radius),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      streak?.title ?? 'Your Streak',
                      style: HomeTextStyles.cardTitle,
                    ),
                    const SizedBox(height: 10),
                    if (streak == null)
                      const Row(
                        children: [
                          HomeDashboardAssetImage(
                            assetName: 'Breath.png',
                            width: 42,
                            height: 42,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Ready to sync',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: HomePalette.text,
                                fontSize: 24,
                                height: 1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          const HomeDashboardAssetImage(
                            assetName: 'Breath.png',
                            width: 42,
                            height: 42,
                          ),
                          Text(
                            '${streak.days}',
                            style: const TextStyle(
                              color: HomePalette.text,
                              fontSize: 36,
                              height: .9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text('days', style: HomeTextStyles.body),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Text(
                      streak?.description ??
                          'Your streak will appear here after activity is synced.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HomeTextStyles.body,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      streak == null
                          ? 'Backend-ready for account activity'
                          : '${streak.linkLabel} ->',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HomePalette.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const HomeDashboardAssetImage(
                assetName: '🔥.png',
                width: 46,
                height: 46,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePaccServicesSection extends StatelessWidget {
  const HomePaccServicesSection({
    super.key,
    required this.services,
    required this.onOpen,
    required this.onViewAll,
  });

  final List<HomeServiceData> services;
  final ValueChanged<String> onOpen;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'PACC Services',
          actionLabel: 'Learn more',
          onAction: () => onOpen('PACC Services'),
        ),
        const SizedBox(height: 4),
        const Text(
          'Psychological Assessment & Counseling Center',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: HomeTextStyles.body,
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 340 ? 1 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: services.length > 4 ? 4 : services.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: columns == 1 ? 134 : 112,
              ),
              itemBuilder: (context, index) {
                final service = services[index];
                return _ServiceTile(
                  data: service,
                  onTap: () => onOpen(service.title),
                );
              },
            );
          },
        ),
        const SizedBox(height: 14),
        HomeOutlinedButton(
          label: 'View all ${services.length} PACC services',
          onTap: onViewAll,
        ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.data, required this.onTap});

  final HomeServiceData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(HomeMetrics.radius),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: data.colors,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border.all(color: HomePalette.outline),
            borderRadius: BorderRadius.circular(HomeMetrics.radius),
            boxShadow: const [
              BoxShadow(
                color: HomePalette.shadow,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .38),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(data.icon, color: HomePalette.text, size: 21),
              ),
              const Spacer(),
              Text(
                data.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HomePalette.text,
                  fontSize: 12,
                  height: 1.12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                data.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HomePalette.text,
                  fontSize: 10,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeDailyInsightsSection extends StatelessWidget {
  const HomeDailyInsightsSection({
    super.key,
    required this.insights,
    required this.affirmation,
    required this.onOpen,
    required this.nowProvider,
  });

  final List<HomeInsightData> insights;
  final HomeAffirmationData? affirmation;
  final ValueChanged<String> onOpen;
  final DateTime Function() nowProvider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'My daily insights - Today',
                style: HomeTextStyles.sectionTitle,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE8A3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Small steps',
                style: TextStyle(
                  color: HomePalette.mutedGold,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 10, end: 0),
          duration: HomeMotion.duration(context, 360),
          curve: Curves.easeOutCubic,
          builder: (context, offset, child) => Transform.translate(
            offset: Offset(0, offset),
            child: Opacity(opacity: 1 - offset / 30, child: child),
          ),
          child: SizedBox(
            height: 126,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: insights.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final insight = insights[index];
                if (insight.isAction) {
                  return _InsightActionCard(
                    data: insight,
                    onTap: () => onOpen(insight.title),
                  );
                }
                return _PhotoInsightCard(
                  data: insight,
                  onTap: () => onOpen(insight.title),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _AffirmationCard(data: affirmation, nowProvider: nowProvider),
      ],
    );
  }
}

class _InsightActionCard extends StatelessWidget {
  const _InsightActionCard({required this.data, required this.onTap});

  final HomeInsightData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(HomeMetrics.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(HomeMetrics.radius),
        onTap: onTap,
        child: Container(
          width: 116,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: HomePalette.sun, width: 1.5),
            borderRadius: BorderRadius.circular(HomeMetrics.radius),
            boxShadow: const [
              BoxShadow(
                color: HomePalette.shadow,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: HomePalette.sun,
                  shape: BoxShape.circle,
                ),
                child: data.iconAssetName == null
                    ? Icon(data.icon, color: HomePalette.text, size: 24)
                    : HomeDashboardAssetImage(
                        assetName: data.iconAssetName!,
                        width: 22,
                        height: 22,
                      ),
              ),
              const Spacer(),
              Text(
                data.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HomePalette.text,
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Quick check-in',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HomeTextStyles.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoInsightCard extends StatelessWidget {
  const _PhotoInsightCard({required this.data, required this.onTap});

  final HomeInsightData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(HomeMetrics.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(HomeMetrics.radius),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(HomeMetrics.radius),
          child: SizedBox(
            width: 148,
            child: Stack(
              fit: StackFit.expand,
              children: [
                HomeDashboardAssetImage(
                  assetName: data.imageName ?? '',
                  fit: BoxFit.cover,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0x26000000), Color(0xCC000000)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                if (data.iconAssetName != null)
                  Positioned(
                    top: 9,
                    left: 9,
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .9),
                        shape: BoxShape.circle,
                      ),
                      child: HomeDashboardAssetImage(
                        assetName: data.iconAssetName!,
                        width: 22,
                        height: 22,
                      ),
                    ),
                  ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 1.12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (data.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          data.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF8F3E8),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AffirmationCard extends StatefulWidget {
  const _AffirmationCard({required this.data, required this.nowProvider});

  final HomeAffirmationData? data;
  final DateTime Function() nowProvider;

  @override
  State<_AffirmationCard> createState() => _AffirmationCardState();
}

class _AffirmationCardState extends State<_AffirmationCard> {
  late int _quoteIndex;
  bool _hasAdvanced = false;

  @override
  void initState() {
    super.initState();
    _quoteIndex = _indexForDate(widget.nowProvider());
  }

  int _indexForDate(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return (day.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay) %
        dailyAffirmationQuotes.length;
  }

  void _showNextQuote() {
    setState(() {
      _hasAdvanced = true;
      _quoteIndex = (_quoteIndex + 1) % dailyAffirmationQuotes.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final supplied = widget.data;
    final catalogQuote = dailyAffirmationQuotes[_quoteIndex];
    final quote = supplied != null && !_hasAdvanced
        ? supplied.quote
        : catalogQuote.text;
    final category = supplied != null && !_hasAdvanced
        ? supplied.title
        : catalogQuote.category;
    final author = supplied != null && !_hasAdvanced ? supplied.author : null;

    return Material(
      color: const Color(0xFFF4F1F6),
      borderRadius: BorderRadius.circular(HomeMetrics.radiusLarge),
      child: InkWell(
        borderRadius: BorderRadius.circular(HomeMetrics.radiusLarge),
        onTap: _showNextQuote,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x80B9BED2)),
            borderRadius: BorderRadius.circular(HomeMetrics.radiusLarge),
            boxShadow: const [
              BoxShadow(
                color: HomePalette.shadow,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const HomeDashboardAssetImage(
                    assetName: 'Thumbs up.png',
                    width: 22,
                    height: 26,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Today's affirmation",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HomeTextStyles.cardTitle,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HomePalette.mutedGold,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: HomeMotion.duration(context, 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(0, .08),
                    end: Offset.zero,
                  ).animate(animation);
                  final scale = Tween<double>(
                    begin: .97,
                    end: 1,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: slide,
                      child: ScaleTransition(scale: scale, child: child),
                    ),
                  );
                },
                child: Center(
                  key: ValueKey(quote),
                  child: Column(
                    children: [
                      const Text(
                        '“',
                        style: TextStyle(
                          color: HomePalette.mutedGold,
                          fontSize: 30,
                          height: .55,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        quote,
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: HomePalette.text,
                          fontSize: 15,
                          height: 1.3,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'Tap for another thought',
                  style: TextStyle(
                    color: HomePalette.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (author != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '- $author',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HomeTextStyles.caption,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HomeMentalHealthCheckCard extends StatelessWidget {
  const HomeMentalHealthCheckCard({
    super.key,
    required this.data,
    required this.onStart,
    required this.onViewSummary,
  });

  final HomeMentalHealthCheckData data;
  final VoidCallback onStart;
  final VoidCallback onViewSummary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Mental Health Check',
          actionLabel: 'Start',
          actionAssetName: 'Forward.png',
          onAction: onStart,
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(HomeMetrics.cardPadding),
          decoration: HomeDecor.card(
            borderColor: HomePalette.sun,
            shadowColor: const Color(0x1FFFC107),
            radius: HomeMetrics.radiusLarge,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const HomeDashboardAssetImage(
                assetName: 'Good Quality.png',
                width: 42,
                height: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HomeTextStyles.cardTitle,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      data.description,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: HomeTextStyles.body,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_outlined,
                          size: 16,
                          color: HomePalette.muted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            data.durationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: HomePalette.text,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.center,
                      child: HomePillButton(
                        label: data.actionLabel,
                        assetName: 'Forward.png',
                        onTap: onViewSummary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class HomeCounselorCard extends StatelessWidget {
  const HomeCounselorCard({super.key, required this.onContact});

  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: HomeDecor.card(
        borderColor: HomePalette.sun,
        radius: HomeMetrics.radiusLarge,
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('💛', style: TextStyle(fontSize: 28)),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Need to talk to someone?',
                  style: HomeTextStyles.cardTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'PACC counseling services are available for students and faculty. You’re never alone.',
            textAlign: TextAlign.center,
            style: HomeTextStyles.body,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 210,
            child: FilledButton(
              onPressed: onContact,
              style: FilledButton.styleFrom(
                backgroundColor: HomePalette.sun,
                foregroundColor: HomePalette.text,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: HomeTextStyles.button,
              ),
              child: const Text('Contact counselor'),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeResourcesSection extends StatelessWidget {
  const HomeResourcesSection({
    super.key,
    required this.resources,
    required this.onOpen,
    required this.onSeeAll,
  });

  final List<HomeResourceData> resources;
  final ValueChanged<HomeResourceData> onOpen;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Mental Health Resources',
          actionLabel: 'See All',
          actionAssetName: 'Forward.png',
          onAction: onSeeAll,
        ),
        const SizedBox(height: 12),
        for (final item in resources) ...[
          _ResourceTile(data: item, onTap: () => onOpen(item)),
          if (item != resources.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({required this.data, required this.onTap});

  final HomeResourceData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: data.color,
      borderRadius: BorderRadius.circular(HomeMetrics.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(HomeMetrics.radius),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: data.borderColor ?? const Color(0x33000000),
            ),
            borderRadius: BorderRadius.circular(HomeMetrics.radius),
            boxShadow: const [
              BoxShadow(
                color: HomePalette.shadow,
                blurRadius: 9,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0x52FFFFFF),
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                ),
                child: data.iconAssetName == null
                    ? Icon(data.icon, color: Colors.white, size: 28)
                    : HomeDashboardAssetImage(
                        assetName: data.iconAssetName!,
                        width: 34,
                        height: 34,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HomePalette.text,
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HomePalette.text,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const HomeDashboardAssetImage(
                assetName: 'Forward.png',
                width: 18,
                height: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeToolkitSection extends StatelessWidget {
  const HomeToolkitSection({
    super.key,
    required this.items,
    required this.onOpen,
  });

  final List<HomeToolkitData> items;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Your wellness toolkit', style: HomeTextStyles.sectionTitle),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 340 ? 1 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                mainAxisExtent: columns == 1 ? 108 : 88,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                return _ToolkitTile(
                  data: item,
                  onTap: () => onOpen(item.title),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _ToolkitTile extends StatelessWidget {
  const _ToolkitTile({required this.data, required this.onTap});

  final HomeToolkitData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(HomeMetrics.radius),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: data.colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: HomePalette.outline),
            borderRadius: BorderRadius.circular(HomeMetrics.radius),
            boxShadow: const [
              BoxShadow(
                color: HomePalette.shadow,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeDashboardAssetImage(
                assetName: data.imageName,
                fullAssetPath: data.fullAssetPath,
                width: 28,
                height: 28,
                fit: BoxFit.contain,
              ),
              const Spacer(),
              Text(
                data.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HomePalette.text,
                  fontSize: 11,
                  height: 1.12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HomePalette.text,
                  fontSize: 9.5,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.actionAssetName,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? actionAssetName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: HomeTextStyles.sectionTitle,
          ),
        ),
        if (actionLabel != null)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF9A6700),
              minimumSize: const Size(44, 36),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (actionAssetName != null) ...[
                  const SizedBox(width: 4),
                  HomeDashboardAssetImage(
                    assetName: actionAssetName!,
                    width: 10,
                    height: 14,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class HomePillButton extends StatelessWidget {
  const HomePillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.assetName,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? assetName;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HomePalette.sun,
      borderRadius: BorderRadius.circular(22),
      elevation: 1,
      shadowColor: HomePalette.shadowStrong,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (assetName != null) ...[
                const SizedBox(width: 4),
                HomeDashboardAssetImage(
                  assetName: assetName!,
                  width: 14,
                  height: 18,
                ),
              ] else if (icon != null) ...[
                const SizedBox(width: 4),
                Icon(icon, color: Colors.white, size: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HomeWideButton extends StatelessWidget {
  const HomeWideButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.assetName,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? assetName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: HomePalette.sun,
        borderRadius: BorderRadius.circular(24),
        elevation: 1,
        shadowColor: HomePalette.shadowStrong,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                assetName == null
                    ? Icon(icon, color: HomePalette.text, size: 26)
                    : HomeDashboardAssetImage(
                        assetName: assetName!,
                        width: 20,
                        height: 20,
                      ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HomeTextStyles.button,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeOutlinedButton extends StatelessWidget {
  const HomeOutlinedButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: HomePalette.text,
          backgroundColor: HomePalette.surface,
          side: const BorderSide(color: Color(0xB3D79F00), width: 1.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HomeMetrics.radius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HomeTextStyles.button,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

class HomeCircleIconButton extends StatelessWidget {
  const HomeCircleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.assetName,
    this.assetColor,
    this.size = 44,
    this.iconSize = 22,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final String? assetName;
  final Color? assetColor;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: HomePalette.surface,
        shape: const CircleBorder(),
        elevation: 1,
        shadowColor: HomePalette.shadowStrong,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: assetName == null
                ? Icon(icon, size: iconSize, color: HomePalette.text)
                : Center(
                    child: HomeDashboardAssetImage(
                      assetName: assetName!,
                      width: iconSize,
                      height: iconSize,
                      color: assetColor,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class HomePlainIconButton extends StatelessWidget {
  const HomePlainIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.assetName,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final String? assetName;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: assetName == null
              ? Icon(icon, size: 16, color: HomePalette.text)
              : HomeDashboardAssetImage(
                  assetName: assetName!,
                  width: 12,
                  height: 12,
                ),
        ),
      ),
    );
  }
}

class HomeDashboardAssetImage extends StatelessWidget {
  const HomeDashboardAssetImage({
    super.key,
    required this.assetName,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.color,
    this.fullAssetPath,
  });

  final String assetName;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Color? color;
  final String? fullAssetPath;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      fullAssetPath ?? '${AppAssets.dashboardImages}/$assetName',
      width: width,
      height: height,
      fit: fit,
      color: color,
      colorBlendMode: color == null ? null : BlendMode.srcIn,
      errorBuilder: (_, _, _) {
        return SizedBox(
          width: width,
          height: height,
          child: const Icon(Icons.image_not_supported_outlined),
        );
      },
    );
  }
}

class HomeAnimatedSection extends StatelessWidget {
  const HomeAnimatedSection({
    super.key,
    required this.child,
    required this.delay,
  });

  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: HomeMotion.duration(context, 360 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, animatedChild) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18),
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }
}

class BlankHomeFeaturePage extends StatelessWidget {
  const BlankHomeFeaturePage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomePalette.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: HomePalette.sun,
        foregroundColor: HomePalette.text,
        elevation: 0,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Coming soon',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HomePalette.text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
