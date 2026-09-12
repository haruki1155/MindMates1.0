import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../providers/assessment_provider.dart';
import '../../../providers/appointment_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/mood_provider.dart';
import '../../../providers/report_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../repositories/assessment_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../routes/route_names.dart';
import '../../quick_assessment/models/quick_assessment_models.dart';
import '../../counseling/screens/pacc_counseling_screen.dart';
import '../../counseling/widgets/appointment_details_sheet.dart';
import '../../../models/appointment_model.dart';
import '../../../models/profile_roles.dart';
import '../../../services/firebase/app_notification_service.dart';
import '../../../models/pacc_availability_model.dart';
import '../../../repositories/pacc_availability_repository.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../models/home_dashboard_data.dart';
import '../widgets/home_dashboard_widgets.dart';
import 'home_appointment_calendar_screen.dart';

enum _HomeNavDestination { today, secretChat, insight, messages, profile }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.data, DateTime Function()? nowProvider})
    : _nowProvider = nowProvider ?? DateTime.now;

  final HomeDashboardData? data;
  final DateTime Function() _nowProvider;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _navVisibilityThreshold = 24;

  final ScrollController _scrollController = ScrollController();
  final AppNotificationService _notifications = AppNotificationService();

  bool _showBottomNav = true;
  bool _isOpeningAssessment = false;
  bool _isAssessmentBannerDismissed = false;
  _HomeNavDestination _activeDestination = _HomeNavDestination.today;
  String? _loadedBackendUserId;
  String? _loadedAppointmentUserId;

  HomeDashboardData get _data => widget.data ?? HomeDashboardData.mock();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _notifications.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = _currentUserId();
    if (userId == null || userId.isEmpty) return;

    if (_loadedBackendUserId != userId) {
      _loadedBackendUserId = userId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _notifications.initializeForUser(userId).catchError((_) {});
        _readProviderOrNull<UserProvider>(
          context,
        )?.recordActivity(userId, UserActivityType.appOpen);
        _readProviderOrNull<MoodProvider>(context)?.loadRecentMoods(userId);
        final reportProvider = _readProviderOrNull<ReportProvider>(context);
        if (reportProvider == null) return;
        reportProvider.loadLatestReport(userId).then((_) {
          if (!mounted) return;
          reportProvider.ensureWeeklyPlaceholder(userId);
        });
      });
    }

    final appointmentProvider = _readProviderOrNull<AppointmentProvider>(
      context,
    );
    if (appointmentProvider != null && _loadedAppointmentUserId != userId) {
      _loadedAppointmentUserId = userId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) appointmentProvider.loadAppointments(userId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _dashboardDataFromProviders(context);
    final assessmentProvider = context.watch<AssessmentProvider>();
    _watchProviderOrNull<AuthProvider>(context);
    final appointmentProvider = _watchProviderOrNull<AppointmentProvider>(
      context,
    );
    final user = _userFor(data, assessmentProvider);
    final nextAppointment = _nextAppointment(
      appointmentProvider?.appointments ?? const [],
    );
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth < 360 ? 12.0 : 18.0;

    return Scaffold(
      backgroundColor: HomePalette.background,
      body: Stack(
        children: [
          const Positioned.fill(child: HomeDashboardBackground()),
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    28,
                    horizontalPadding,
                    124,
                  ),
                  sliver: SliverList.list(
                    children: [
                      HomeAnimatedSection(
                        delay: 70,
                        child: HomeWelcomeCard(
                          user: user,
                          onNotificationTap: _openNotifications,
                          onCalendarTap: _openAppointmentCalendar,
                          onProfileTap: _openProfile,
                        ),
                      ),
                      const SizedBox(height: 12),
                      HomeAnimatedSection(
                        delay: 74,
                        child: HomeStreakCard(
                          data: data.streak,
                          onTap: _openLogMood,
                        ),
                      ),
                      const SizedBox(height: 12),
                      HomeAnimatedSection(
                        delay: 78,
                        child: StreamBuilder<PaccAvailabilityModel?>(
                          stream: Firebase.apps.isEmpty
                              ? const Stream<PaccAvailabilityModel?>.empty()
                              : PaccAvailabilityRepository().watchCurrent(),
                          builder: (context, snapshot) {
                            final availability = snapshot.data;
                            final open = availability?.isOpenAt(
                              widget._nowProvider(),
                            );
                            final message = availability == null
                                ? 'PAACC office availability has not been published yet.'
                                : '${availability.presence.label}. ${availability.opensAt}–${availability.closesAt}. ${availability.acceptsWalkIns ? 'Walk-ins accepted.' : 'Appointment required.'}';
                            return HomeAnnouncementCard(
                              badge: availability == null
                                  ? 'PAACC'
                                  : availability.statusLabel(
                                      widget._nowProvider(),
                                    ),
                              message: message,
                              isOpen: open,
                              onViewMore: _openNotifications,
                              onViewDetail: () =>
                                  _showAvailabilityDetails(availability),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      HomeAnimatedSection(
                        delay: 86,
                        child: HomeWideButton(
                          label: context.watch<MoodProvider>().hasCheckedInToday
                              ? 'View today’s mood'
                              : 'Log your mood',
                          icon: Icons.add,
                          assetName: '+.png',
                          onTap: _openLogMood,
                        ),
                      ),
                      if (appointmentProvider != null) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'Upcoming Appointments',
                          style: HomeTextStyles.sectionTitle,
                        ),
                        const SizedBox(height: 8),
                        HomeAnimatedSection(
                          delay: 95,
                          child: _HomeAppointmentPreview(
                            appointment: nextAppointment,
                            isLoading:
                                appointmentProvider.isLoading &&
                                appointmentProvider.appointments.isEmpty,
                            errorMessage: appointmentProvider.errorMessage,
                            onOpen: nextAppointment == null
                                ? _openAppointmentCalendar
                                : () => showAppointmentDetailsSheet(
                                    context,
                                    nextAppointment,
                                  ),
                            onBook: _openAppointmentBooking,
                            onRetry: () {
                              final userId = _currentUserId();
                              if (userId != null) {
                                appointmentProvider.loadAppointments(userId);
                              }
                            },
                          ),
                        ),
                      ],
                      if (!_isAssessmentBannerDismissed) ...[
                        const SizedBox(height: 14),
                        HomeAnimatedSection(
                          delay: 110,
                          child: HomeAssessmentBanner(
                            data: data.assessment,
                            onStart: _openStudentAssessment,
                            onClose: _dismissAssessmentBanner,
                          ),
                        ),
                      ],
                      const SizedBox(height: HomeMetrics.sectionGap),
                      HomeAnimatedSection(
                        delay: 120,
                        child: HomePaccServicesSection(
                          services: data.services,
                          onOpen: (_) => _openServices(),
                          onViewAll: _openServices,
                        ),
                      ),
                      const SizedBox(height: HomeMetrics.sectionGap),
                      HomeAnimatedSection(
                        delay: 170,
                        child: HomeDailyInsightsSection(
                          insights: data.insights,
                          affirmation: data.affirmation,
                          onOpen: _openPlaceholder,
                          nowProvider: widget._nowProvider,
                        ),
                      ),
                      const SizedBox(height: HomeMetrics.sectionGap),
                      HomeAnimatedSection(
                        delay: 220,
                        child: HomeMentalHealthCheckCard(
                          data: data.mentalHealthCheck,
                          onStart: _openStudentAssessment,
                          onViewSummary: () => Navigator.of(
                            context,
                          ).pushNamed(RouteNames.mentalHealthReport),
                        ),
                      ),
                      const SizedBox(height: 14),
                      HomeAnimatedSection(
                        delay: 245,
                        child: HomeCounselorCard(
                          onContact: _openAppointmentBooking,
                        ),
                      ),
                      const SizedBox(height: HomeMetrics.sectionGap),
                      HomeAnimatedSection(
                        delay: 270,
                        child: HomeResourcesSection(
                          resources: data.resources,
                          onOpen: _openResource,
                          onSeeAll: () => Navigator.of(
                            context,
                          ).pushNamed(RouteNames.mentalHealthInsights),
                        ),
                      ),
                      const SizedBox(height: HomeMetrics.sectionGap),
                      HomeAnimatedSection(
                        delay: 320,
                        child: HomeToolkitSection(
                          items: data.toolkitItems,
                          onOpen: _openPlaceholder,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 8,
            child: _HomeBottomNav(
              isVisible: _showBottomNav,
              activeDestination: _activeDestination,
              onDestinationSelected: _handleNavDestination,
            ),
          ),
        ],
      ),
    );
  }

  HomeDashboardData _dashboardDataFromProviders(BuildContext context) {
    final base = _data;
    final user = context.watch<UserProvider>().user;
    final latestReport = _watchProviderOrNull<ReportProvider>(
      context,
    )?.latestReport;
    final moodProvider = _watchProviderOrNull<MoodProvider>(context);
    final moods = moodProvider?.moods ?? const [];

    final backendActivityDates =
        user?.activeDateKeys
            .map(_dateFromActivityKey)
            .whereType<DateTime>()
            .toList(growable: false) ??
        const <DateTime>[];
    final activityDates = backendActivityDates.isNotEmpty
        ? backendActivityDates
        : moods.map((mood) => mood.createdAt).toList();
    final displayName = user?.displayName.trim();
    final role = user?.roleLabel;

    return base.copyWith(
      user: HomeUserData(
        displayName: (displayName == null || displayName.isEmpty)
            ? base.user.displayName
            : displayName,
        role: role ?? base.user.role,
      ),
      assessment: user == null
          ? base.assessment
          : HomeAssessmentPromptData(
              title: switch (user.effectivePopulationRole) {
                PopulationRole.student => 'Check in on academic well-being',
                PopulationRole.teaching => 'Check in on teaching well-being',
                PopulationRole.nonTeaching =>
                  'Check in on workplace well-being',
                null => 'Complete your profile for a tailored assessment',
              },
              description:
                  user.verificationStatus == VerificationStatus.verified
                  ? 'Your questions are personalized for your verified ${user.roleLabel.toLowerCase()} role.'
                  : '${user.verificationStatus.label}. You can still use your declared role and all support services.',
              actionLabel: base.assessment.actionLabel,
              attemptsUsedThisMonth: base.assessment.attemptsUsedThisMonth,
              maxAttemptsPerMonth: base.assessment.maxAttemptsPerMonth,
              nextAvailableAt: base.assessment.nextAvailableAt,
              canTakeAssessment: base.assessment.canTakeAssessment,
            ),
      streak: user == null
          ? base.streak
          : HomeStreakData(
              title: 'Day streak',
              days: user.dayStreak,
              description: user.dayStreak == 0
                  ? 'Start with one check-in today'
                  : 'Keep your wellness rhythm going',
              linkLabel: 'View',
              lastActiveAt: user.lastActiveAt,
            ),
      days: activityDates.isEmpty
          ? base.days
          : HomeDashboardData.weekAround(
              widget._nowProvider(),
              activityDates: activityDates,
            ),
      mentalHealthCheck: latestReport == null
          ? base.mentalHealthCheck
          : HomeMentalHealthCheckData(
              title: latestReport.title,
              description: latestReport.hasEnoughData
                  ? 'Your weekly mental health summary is ready to review.'
                  : 'Your summary is ready and will become more detailed as you use MindMate.',
              durationLabel: latestReport.hasEnoughData
                  ? 'Updated this week'
                  : 'Ready for your data',
              actionLabel: 'View Summary',
            ),
    );
  }

  DateTime? _dateFromActivityKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
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

  HomeUserData _userFor(
    HomeDashboardData data,
    AssessmentProvider assessmentProvider,
  ) {
    final assessmentName = assessmentProvider.name.trim();
    final assessmentRole = assessmentProvider.selectedRole;

    return HomeUserData(
      displayName: assessmentName.isNotEmpty
          ? assessmentName
          : data.user.displayName.trim(),
      role: assessmentRole?.label ?? data.user.role,
    );
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;

    final isAtTop = _scrollController.offset <= _navVisibilityThreshold;
    if (isAtTop == _showBottomNav &&
        (!isAtTop || _activeDestination == _HomeNavDestination.today)) {
      return;
    }

    setState(() {
      _showBottomNav = isAtTop;
      if (isAtTop) {
        _activeDestination = _HomeNavDestination.today;
      }
    });
  }

  void _handleNavDestination(_HomeNavDestination destination) {
    switch (destination) {
      case _HomeNavDestination.today:
        _scrollToTop();
      case _HomeNavDestination.secretChat:
        Navigator.of(context).pushNamed(RouteNames.secretChat);
      case _HomeNavDestination.insight:
        Navigator.of(context).pushNamed(RouteNames.mentalHealthInsights);
      case _HomeNavDestination.messages:
        Navigator.of(context).pushNamed(RouteNames.mindAid);
      case _HomeNavDestination.profile:
        _openProfile();
    }
  }

  void _scrollToTop() {
    setState(() {
      _activeDestination = _HomeNavDestination.today;
      _showBottomNav = true;
    });

    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: HomeMotion.duration(context, 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _openProfile() {
    Navigator.of(context).pushNamed(RouteNames.profile);
  }

  void _dismissAssessmentBanner() {
    setState(() {
      _isAssessmentBannerDismissed = true;
    });
  }

  void _openServices() {
    Navigator.of(context).pushNamed(RouteNames.services);
  }

  AppointmentModel? _nextAppointment(List<AppointmentModel> appointments) {
    final now = widget._nowProvider();
    final upcoming =
        appointments
            .where(
              (item) =>
                  {
                    AppointmentDisplayStatus.pending,
                    AppointmentDisplayStatus.upcoming,
                    AppointmentDisplayStatus.confirmed,
                    AppointmentDisplayStatus.rescheduleProposed,
                  }.contains(appointmentDisplayStatus(item.status)) &&
                  !item.scheduledAt.isBefore(now),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  void _openAppointmentCalendar() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            HomeAppointmentCalendarScreen(nowProvider: widget._nowProvider),
      ),
    );
  }

  void _openNotifications() {
    final userId = _currentUserId();
    if (userId == null || userId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(userId: userId),
      ),
    );
  }

  Future<void> _showAvailabilityDetails(PaccAvailabilityModel? availability) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final openDays =
        availability?.openDays.map((day) => days[day - 1]).join(', ') ??
        'Not published';
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PAACC office availability'),
        content: Text(
          availability == null
              ? 'The PAACC schedule has not been published yet.'
              : '${availability.presence.label}\n\nWorking days: $openDays\nHours: ${availability.opensAt}–${availability.closesAt}\n\n${availability.acceptsWalkIns ? 'Walk-in visits are currently accepted during office hours.' : 'Please book an appointment before visiting.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openAppointmentBooking() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaccCounselingScreen(
          startBooking: true,
          nowProvider: widget._nowProvider,
        ),
      ),
    );
  }

  Future<void> _openStudentAssessment() async {
    if (_isOpeningAssessment) return;
    _isOpeningAssessment = true;

    final userId = _currentUserId();
    try {
      if (userId != null && userId.isNotEmpty) {
        try {
          final eligibility = await context
              .read<AssessmentProvider>()
              .fullAssessmentEligibility(userId);
          if (!mounted) return;
          if (!eligibility.canStart) {
            await _showAssessmentLimitDialog(eligibility);
            return;
          }
        } catch (error, stackTrace) {
          debugPrint(
            'Full assessment eligibility check failed: $error\n$stackTrace',
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Unable to verify assessment limit. You can continue for now.',
                ),
              ),
            );
        }
      }

      final shouldStart = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: HomePalette.sun, width: 1.2),
            ),
            title: const Text(
              'Start Assessment?',
              style: TextStyle(
                color: HomePalette.text,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: const Text(
              'This will open your role-based assessment questions. You can skip questions while answering.',
              style: TextStyle(
                color: HomePalette.blueText,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: HomePalette.orange,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: HomePalette.sun,
                  foregroundColor: HomePalette.text,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: const Text('Start'),
              ),
            ],
          );
        },
      );

      if (shouldStart != true || !mounted) return;

      final assessmentProvider = context.read<AssessmentProvider>();
      final savedRole = context.read<UserProvider>().user?.assessmentRole;
      final role =
          assessmentProvider.selectedRole ??
          savedRole ??
          AssessmentRole.student;

      if (assessmentProvider.selectedRole != role) {
        assessmentProvider.selectRole(role);
      }

      Navigator.of(context).pushNamed(RouteNames.studentAssessment);
    } finally {
      _isOpeningAssessment = false;
    }
  }

  String? _currentUserId() {
    try {
      final authProvider = context.read<AuthProvider>();
      final authId = authProvider.userId ?? authProvider.hydrateCurrentUser();
      if (authId != null && authId.isNotEmpty) return authId;
    } on ProviderNotFoundException {
      // Tests and previews may provide only UserProvider.
    }
    final userId = context.read<UserProvider>().user?.id;
    return userId == null || userId.isEmpty ? null : userId;
  }

  Future<void> _showAssessmentLimitDialog(
    FullAssessmentEligibility eligibility,
  ) {
    final nextEligibleAt = eligibility.nextEligibleAt;
    final nextEligibleText = nextEligibleAt == null
        ? 'Please try again later.'
        : 'Try again on ${_formatEligibilityDate(nextEligibleAt)}.';

    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: HomePalette.sun, width: 1.2),
          ),
          title: const Text(
            'Assessment limit reached',
            style: TextStyle(
              color: HomePalette.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'You can take the full assessment up to 2 times in 7 days, with 2 days between attempts. $nextEligibleText',
            style: TextStyle(
              color: HomePalette.blueText,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: HomePalette.sun,
                foregroundColor: HomePalette.text,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  String _formatEligibilityDate(DateTime date) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';

    return '${weekdays[local.weekday - 1]}, ${months[local.month - 1]} ${local.day}, ${local.year} at $hour:$minute $period';
  }

  void _openResource(HomeResourceData resource) {
    if (resource.title == 'Talk to AI companion') {
      Navigator.of(context).pushNamed(RouteNames.mindAid);
      return;
    }

    Navigator.of(context).pushNamed(RouteNames.mentalHealthInsights);
  }

  void _openLogMood() {
    Navigator.of(context).pushNamed(RouteNames.logMood);
  }

  void _openPlaceholder(String title) {
    if (title == 'Log your mood' || title == 'Log Mood') {
      _openLogMood();
      return;
    }

    if (title == 'Mindful breathing' || title == 'Breathing exercise') {
      Navigator.of(context).pushNamed(RouteNames.mindfulBreathing);
      return;
    }

    if (title == 'Sleep Quality') {
      Navigator.of(context).pushNamed(RouteNames.sleepQuality);
      return;
    }

    if (title == 'Facial Recognition') {
      _openLogMood();
      return;
    }

    if (title == 'Quiet reflection' ||
        title == 'Journal' ||
        title == 'My Journal') {
      Navigator.of(context).pushNamed(RouteNames.journal);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BlankHomeFeaturePage(title: title)),
    );
  }
}

class _HomeAppointmentPreview extends StatelessWidget {
  const _HomeAppointmentPreview({
    required this.appointment,
    required this.isLoading,
    required this.errorMessage,
    required this.onOpen,
    required this.onBook,
    required this.onRetry,
  });

  final AppointmentModel? appointment;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onOpen;
  final VoidCallback onBook;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final item = appointment;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: HomeDecor.card(
        color: HomePalette.surfaceWarm,
        borderColor: const Color(0x80E8D38A),
        radius: HomeMetrics.radiusLarge,
      ),
      child: isLoading
          ? const Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 12),
                Text('Loading your appointments…', style: HomeTextStyles.body),
              ],
            )
          : errorMessage != null && item == null
          ? Row(
              children: [
                const Expanded(
                  child: Text(
                    'Unable to load appointments.',
                    style: HomeTextStyles.body,
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            )
          : item == null
          ? Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: HomeCircleIconButton(
                    icon: Icons.calendar_today_outlined,
                    assetName: 'Calendar.png',
                    tooltip: 'Open appointment calendar',
                    onTap: onOpen,
                    size: 38,
                    iconSize: 20,
                  ),
                ),
                const Icon(
                  Icons.calendar_month_rounded,
                  size: 46,
                  color: HomePalette.muted,
                ),
                const SizedBox(height: 8),
                const Text(
                  'No upcoming appointments',
                  style: HomeTextStyles.bodyMuted,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: onBook,
                  style: FilledButton.styleFrom(
                    backgroundColor: HomePalette.sun,
                    foregroundColor: HomePalette.text,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Appoint a Session'),
                ),
              ],
            )
          : InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(HomeMetrics.radius),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 52,
                    decoration: BoxDecoration(
                      color: HomePalette.softGold,
                      borderRadius: BorderRadius.circular(HomeMetrics.radius),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${item.scheduledAt.day}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _shortMonth(item.scheduledAt.month),
                          style: HomeTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Next appointment',
                          style: HomeTextStyles.cardTitle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.scheduledTime} • ${item.location}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HomeTextStyles.body,
                        ),
                        if ((item.counselorName ?? '').trim().isNotEmpty)
                          Text(
                            item.counselorName!.trim(),
                            style: HomeTextStyles.bodyMuted,
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
    );
  }

  String _shortMonth(int month) => const [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ][month - 1];
}

class _HomeBottomNav extends StatelessWidget {
  const _HomeBottomNav({
    this.isVisible = true,
    required this.activeDestination,
    required this.onDestinationSelected,
  });

  final bool? isVisible;
  final _HomeNavDestination? activeDestination;
  final ValueChanged<_HomeNavDestination>? onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final visible = isVisible ?? true;
    final active = activeDestination ?? _HomeNavDestination.today;
    final motionDuration = HomeMotion.duration(context, 220);

    return SafeArea(
      top: false,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1),
        duration: motionDuration,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: HomeMotion.duration(context, 180),
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: !visible,
            child: Container(
              height: 68,
              decoration: const BoxDecoration(
                color: HomePalette.surface,
                border: Border.fromBorderSide(
                  BorderSide(color: HomePalette.outlineStrong),
                ),
                borderRadius: BorderRadius.all(Radius.circular(22)),
                boxShadow: [
                  BoxShadow(
                    color: HomePalette.shadowStrong,
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _HomeBottomNavItem(
                    icon: Icons.calendar_today,
                    assetName: 'Calendar.png',
                    label: 'Today',
                    isActive: active == _HomeNavDestination.today,
                    onTap: () =>
                        onDestinationSelected?.call(_HomeNavDestination.today),
                  ),
                  _HomeBottomNavItem(
                    icon: Icons.forum_outlined,
                    assetName: '💭.png',
                    label: 'Secret chat',
                    isActive: active == _HomeNavDestination.secretChat,
                    onTap: () => onDestinationSelected?.call(
                      _HomeNavDestination.secretChat,
                    ),
                  ),
                  _HomeBottomNavItem(
                    icon: Icons.show_chart,
                    label: 'Insight',
                    isActive: active == _HomeNavDestination.insight,
                    onTap: () => onDestinationSelected?.call(
                      _HomeNavDestination.insight,
                    ),
                  ),
                  _HomeBottomNavItem(
                    icon: Icons.chat_bubble_outline,
                    assetName: 'mail.png',
                    label: 'Messages',
                    isActive: active == _HomeNavDestination.messages,
                    onTap: () => onDestinationSelected?.call(
                      _HomeNavDestination.messages,
                    ),
                  ),
                  _HomeBottomNavItem(
                    icon: Icons.person,
                    assetName: 'Customer.png',
                    assetColor: HomePalette.text,
                    label: 'Profile',
                    isActive: active == _HomeNavDestination.profile,
                    onTap: () => onDestinationSelected?.call(
                      _HomeNavDestination.profile,
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

class _HomeBottomNavItem extends StatelessWidget {
  const _HomeBottomNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.assetName,
    this.assetColor,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final String? assetName;
  final Color? assetColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: HomeMotion.duration(context, 170),
                curve: Curves.easeOutCubic,
                width: isActive ? 36 : 30,
                height: isActive ? 34 : 30,
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFFFD75C)
                      : Colors.transparent,
                  border: isActive
                      ? Border.all(color: const Color(0x669A7000))
                      : null,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: assetName == null
                    ? Icon(icon, size: 20, color: HomePalette.text)
                    : Padding(
                        padding: const EdgeInsets.all(4),
                        child: HomeDashboardAssetImage(
                          assetName: assetName!,
                          color: assetColor,
                        ),
                      ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: HomePalette.text,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
