import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/widgets/mindmate_terms_and_conditions.dart';
import '../../../core/widgets/mindmate_bottom_navigation.dart';
import '../../../models/user_model.dart';
import '../../../models/profile_roles.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/report_provider.dart';
import '../../../providers/sleep_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../routes/route_names.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.data});

  final ProfileViewData? data;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambientController;
  bool _requestedProfile = false;
  bool _requestedReport = false;
  bool _requestedSleep = false;
  bool _isSigningOut = false;

  static const List<ProfileActionItem> _actions = [
    ProfileActionItem(
      label: 'Secret Chats profile',
      icon: Icons.article_outlined,
    ),
    ProfileActionItem(
      label: 'Mood tracking settings',
      icon: Icons.monitor_heart_outlined,
    ),
    ProfileActionItem(
      label: 'Privacy settings',
      icon: Icons.privacy_tip_outlined,
    ),
    ProfileActionItem(label: 'Reminders', icon: Icons.notifications),
    ProfileActionItem(label: 'Help', icon: Icons.help_outline),
    ProfileActionItem(label: 'About MindMate', icon: Icons.info),
    ProfileActionItem(
      label: 'Terms and Conditions',
      icon: Icons.gavel_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.data != null) return;

    final authProvider = _authProviderOrNull(context);
    final userId = authProvider?.userId ?? authProvider?.hydrateCurrentUser();
    if (userId == null) return;

    final userProvider = context.read<UserProvider>();
    final shouldLoadProfile = userProvider.user == null && !_requestedProfile;
    final shouldLoadReport = !_requestedReport;
    final sleepProvider = _sleepProviderOrNull(context);
    final shouldLoadSleep = sleepProvider != null && !_requestedSleep;

    if (!shouldLoadProfile && !shouldLoadReport && !shouldLoadSleep) return;

    if (shouldLoadProfile) _requestedProfile = true;
    if (shouldLoadReport) _requestedReport = true;
    if (shouldLoadSleep) _requestedSleep = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (shouldLoadProfile) {
        userProvider.loadProfile(userId);
      }

      if (shouldLoadReport) {
        final reportProvider = _reportProviderOrNull(context);
        reportProvider?.loadLatestReport(userId).then((_) {
          if (!mounted) return;
          reportProvider.ensureWeeklyPlaceholder(userId);
        });
      }
      if (shouldLoadSleep) sleepProvider.load(userId);
    });
  }

  @override
  void dispose() {
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        final reportProvider = _watchReportProviderOrNull(context);
        final sleepProvider = _watchSleepProviderOrNull(context);
        final authProvider = widget.data == null && userProvider.user == null
            ? _authProviderOrNull(context)
            : null;
        final data =
            widget.data ??
            _profileDataFromUser(
              userProvider.user,
              fallbackUserId: authProvider?.userId,
              fallbackEmail: authProvider?.currentUserEmail,
              summary: reportProvider?.latestReport == null
                  ? null
                  : ProfileSummaryData(
                      title: reportProvider!.latestReport!.title,
                      description: reportProvider.latestReport!.description,
                    ),
              sleepAverage: sleepProvider?.profileAverage,
              onSleepTap: () =>
                  Navigator.of(context).pushNamed(RouteNames.sleepQuality),
            );

        return Scaffold(
          backgroundColor: _ProfileColors.background,
          bottomNavigationBar: const MindMateBottomNavigation(active: null),
          body: Stack(
            children: [
              _FloatingProfileBackground(animation: _ambientController),
              SafeArea(
                bottom: false,
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _ProfileHeader(
                        onNotificationTap: () =>
                            _openPlaceholder(context, 'Notifications'),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                      sliver: SliverList.list(
                        children: [
                          const _AnimatedProfileSection(
                            delay: 0,
                            child: Text(
                              'Your Profile',
                              style: _ProfileText.title,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _AnimatedProfileSection(
                            delay: 60,
                            child: _ProfileSummaryCard(
                              data: data,
                              isLoading: userProvider.isLoading,
                              onEditTap: () =>
                                  _openEditProfile(context, userProvider.user),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _AnimatedProfileSection(
                            delay: 120,
                            child: _ActionListCard(
                              actions: _actions,
                              onActionTap: (action) {
                                if (action.label == 'Secret Chats profile') {
                                  Navigator.of(
                                    context,
                                  ).pushNamed(RouteNames.secretChatProfile);
                                  return;
                                }
                                if (action.label == 'Terms and Conditions') {
                                  showMindMateTermsAndConditions(context);
                                  return;
                                }
                                _openPlaceholder(context, action.label);
                              },
                            ),
                          ),
                          const SizedBox(height: 18),
                          _AnimatedProfileSection(
                            delay: 180,
                            child: _MentalHealthSummaryCard(
                              data: data?.summary ?? _defaultSummary,
                              onReportTap: () => Navigator.of(
                                context,
                              ).pushNamed(RouteNames.mentalHealthReport),
                              onInsightsTap: () => Navigator.of(
                                context,
                              ).pushNamed(RouteNames.mentalHealthInsights),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const _AnimatedProfileSection(
                            delay: 240,
                            child: _AboutMindMateCard(),
                          ),
                          const SizedBox(height: 18),
                          const _AnimatedProfileSection(
                            delay: 300,
                            child: _DataProtectionCard(),
                          ),
                          const SizedBox(height: 18),
                          _AnimatedProfileSection(
                            delay: 330,
                            child: _LogOutButton(
                              isLoading: _isSigningOut,
                              onTap: _isSigningOut ? null : _confirmAndLogOut,
                            ),
                          ),
                          const SizedBox(height: 26),
                          _AnimatedProfileSection(
                            delay: 360,
                            child: _ProfileFooter(
                              onTermsTap: () =>
                                  showMindMateTermsAndConditions(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  AuthProvider? _authProviderOrNull(BuildContext context) {
    try {
      return context.read<AuthProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  ReportProvider? _reportProviderOrNull(BuildContext context) {
    try {
      return context.read<ReportProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  ReportProvider? _watchReportProviderOrNull(BuildContext context) {
    try {
      return context.watch<ReportProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  SleepProvider? _sleepProviderOrNull(BuildContext context) {
    try {
      return context.read<SleepProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  SleepProvider? _watchSleepProviderOrNull(BuildContext context) {
    try {
      return context.watch<SleepProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  static const _defaultSummary = ProfileSummaryData(
    title: 'Mental Health Summary',
    description: "This week's positive moods",
  );

  ProfileViewData? _profileDataFromUser(
    UserModel? user, {
    String? fallbackUserId,
    String? fallbackEmail,
    ProfileSummaryData? summary,
    double? sleepAverage,
    VoidCallback? onSleepTap,
  }) {
    final effectiveUser =
        user ??
        ((fallbackUserId != null || fallbackEmail != null)
            ? UserModel(
                id: fallbackUserId ?? '',
                email: fallbackEmail ?? '',
                role: null,
              )
            : null);
    if (effectiveUser == null) return null;

    return ProfileViewData(
      displayName: effectiveUser.displayName,
      role: effectiveUser.roleLabel,
      verificationLabel: effectiveUser.verificationStatus.label,
      avatarAssetName: effectiveUser.avatarAssetName,
      profilePhotoUrl: effectiveUser.profilePhotoUrl,
      metrics: [
        ProfileMetricData(
          label: 'Day Streak',
          value: '${effectiveUser.dayStreak}',
          icon: Icons.local_fire_department,
        ),
        ProfileMetricData(
          label: 'Sleep Quality',
          value: sleepAverage == null
              ? '--/5'
              : '${sleepAverage.toStringAsFixed(1)}/5',
          icon: Icons.sentiment_satisfied_alt,
          onTap: onSleepTap,
        ),
        ProfileMetricData(
          label: 'Age',
          value: effectiveUser.age?.toString() ?? '--',
          icon: Icons.cake_outlined,
        ),
      ],
      summary: summary ?? _defaultSummary,
    );
  }

  Future<void> _openEditProfile(BuildContext context, UserModel? user) async {
    if (user == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Profile is still loading.')),
        );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(user: user),
    );
  }

  void _openPlaceholder(BuildContext context, String title) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => _BlankProfilePage(title: title)));
  }

  Future<void> _confirmAndLogOut() async {
    final shouldLogOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out of MindMate?'),
        content: const Text(
          'You will need to sign in again to access your profile and saved activity.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (shouldLogOut != true || !mounted) return;

    final authProvider = _authProviderOrNull(context);
    if (authProvider == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Unable to log out right now.')),
        );
      return;
    }

    setState(() => _isSigningOut = true);
    try {
      await authProvider.signOut();
      if (!mounted) return;
      context.read<UserProvider>().setUser(null);
      setState(() => _isSigningOut = false);
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(RouteNames.login, (route) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSigningOut = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Unable to log out. Please try again.')),
        );
    }
  }
}

class ProfileViewData {
  const ProfileViewData({
    this.displayName,
    this.role,
    this.verificationLabel,
    this.email,
    this.schoolId,
    this.department,
    this.memberSince,
    this.avatarAssetName,
    this.profilePhotoUrl,
    this.metrics = const [],
    this.summary,
  });

  final String? displayName;
  final String? role;
  final String? verificationLabel;
  final String? email;
  final String? schoolId;
  final String? department;
  final String? memberSince;
  final String? avatarAssetName;
  final String? profilePhotoUrl;
  final List<ProfileMetricData> metrics;
  final ProfileSummaryData? summary;
}

class ProfileMetricData {
  const ProfileMetricData({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
}

class ProfileSummaryData {
  const ProfileSummaryData({this.title, this.description});

  final String? title;
  final String? description;
}

class ProfileActionItem {
  const ProfileActionItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.onNotificationTap});

  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: _ProfileColors.sun,
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const _ProfileAssetImage(
            assetName: 'logo.png 3.png',
            width: 34,
            height: 34,
          ),
          const SizedBox(width: 8),
          const _ProfileAssetImage(
            assetName: 'MindMate.png',
            height: 30,
            fit: BoxFit.contain,
          ),
          const Spacer(),
          Tooltip(
            message: 'Notifications',
            child: IconButton(
              onPressed: onNotificationTap,
              icon: const Icon(Icons.notifications, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard({
    required this.data,
    required this.isLoading,
    required this.onEditTap,
  });

  final ProfileViewData? data;
  final bool isLoading;
  final VoidCallback onEditTap;

  @override
  Widget build(BuildContext context) {
    final displayName = data?.displayName;
    final role = data?.role;
    final hasProfile = displayName != null || role != null;
    final metrics = data?.metrics ?? const <ProfileMetricData>[];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: _ProfileDecor.card(
        color: _ProfileColors.sun,
        radius: 14,
        shadowColor: const Color(0x33A36B00),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _AvatarSlot(
                assetName: data?.avatarAssetName,
                photoUrl: data?.profilePhotoUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: hasProfile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (displayName != null)
                            Text(displayName, style: _ProfileText.profileName),
                          if (role != null)
                            Text(role, style: _ProfileText.profileRole),
                          if (data?.verificationLabel != null)
                            Text(
                              data!.verificationLabel!,
                              style: _ProfileText.profileRole.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      )
                    : const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SkeletonLine(
                            widthFactor: .52,
                            height: 14,
                            color: Color(0x77FFFFFF),
                          ),
                          SizedBox(height: 8),
                          _SkeletonLine(
                            widthFactor: .34,
                            height: 10,
                            color: Color(0x77FFFFFF),
                          ),
                        ],
                      ),
              ),
              Tooltip(
                message: 'Edit profile',
                child: Material(
                  color: Colors.black,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: isLoading ? null : onEditTap,
                    child: const SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(
                        Icons.arrow_forward,
                        color: _ProfileColors.sun,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: List.generate(3, (index) {
              final metric = index < metrics.length ? metrics[index] : null;
              return Expanded(child: _MetricSlot(metric: metric));
            }),
          ),
        ],
      ),
    );
  }
}

class _AvatarSlot extends StatelessWidget {
  const _AvatarSlot({required this.assetName, this.photoUrl});

  final String? assetName;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: const BoxDecoration(
        color: Color(0xFFFFE587),
        shape: BoxShape.circle,
      ),
      child: photoUrl != null && photoUrl!.trim().isNotEmpty
          ? ClipOval(
              child: Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(
                    Icons.person_rounded,
                    size: 34,
                    color: Colors.black,
                  ),
                ),
              ),
            )
          : assetName == null || assetName!.trim().isEmpty
          ? const Center(
              child: Icon(Icons.person_rounded, size: 34, color: Colors.black),
            )
          : ClipOval(
              child: _ProfileAssetImage(
                assetName: assetName!,
                fit: BoxFit.cover,
              ),
            ),
    );
  }
}

class _MetricSlot extends StatelessWidget {
  const _MetricSlot({required this.metric});

  final ProfileMetricData? metric;

  @override
  Widget build(BuildContext context) {
    final metric = this.metric;

    if (metric == null) {
      return const Column(
        children: [
          _SkeletonCircle(size: 24, color: Color(0x66FFFFFF)),
          SizedBox(height: 10),
          _SkeletonLine(widthFactor: .44, height: 15, color: Color(0x77FFFFFF)),
          SizedBox(height: 7),
          _SkeletonLine(widthFactor: .36, height: 8, color: Color(0x77FFFFFF)),
        ],
      );
    }

    return Semantics(
      button: metric.onTap != null,
      label: metric.onTap == null ? null : 'Open ${metric.label}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: metric.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Icon(metric.icon, size: 28, color: Colors.black),
              const SizedBox(height: 8),
              Text(metric.value, style: _ProfileText.metricValue),
              Text(metric.label, style: _ProfileText.metricLabel),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionListCard extends StatelessWidget {
  const _ActionListCard({required this.actions, required this.onActionTap});

  final List<ProfileActionItem> actions;
  final ValueChanged<ProfileActionItem> onActionTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _ProfileDecor.card(radius: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            for (var index = 0; index < actions.length; index++)
              _ActionListTile(
                action: actions[index],
                showDivider: index != actions.length - 1,
                onTap: () => onActionTap(actions[index]),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionListTile extends StatelessWidget {
  const _ActionListTile({
    required this.action,
    required this.showDivider,
    required this.onTap,
  });

  final ProfileActionItem action;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            border: showDivider
                ? const Border(
                    bottom: BorderSide(color: _ProfileColors.divider),
                  )
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(action.icon, size: 21, color: Colors.black),
              const SizedBox(width: 14),
              Expanded(child: Text(action.label, style: _ProfileText.action)),
              const Icon(Icons.chevron_right, size: 18, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

class _MentalHealthSummaryCard extends StatelessWidget {
  const _MentalHealthSummaryCard({
    required this.data,
    required this.onReportTap,
    required this.onInsightsTap,
  });

  final ProfileSummaryData? data;
  final VoidCallback onReportTap;
  final VoidCallback onInsightsTap;

  @override
  Widget build(BuildContext context) {
    final title = data?.title;
    final description = data?.description;
    final hasText = title != null || description != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      decoration: _ProfileDecor.card(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.favorite, color: _ProfileColors.sun, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: hasText
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null)
                            Text(title, style: _ProfileText.cardTitle),
                          if (description != null) ...[
                            const SizedBox(height: 4),
                            Text(description, style: _ProfileText.body),
                          ],
                        ],
                      )
                    : const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SkeletonLine(widthFactor: .58, height: 13),
                          SizedBox(height: 8),
                          _SkeletonLine(widthFactor: .74, height: 9),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              Expanded(
                child: _SkeletonAwareButton(
                  label: 'Full Report',
                  icon: Icons.bar_chart,
                  color: _ProfileColors.sun,
                  onTap: onReportTap,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _SkeletonAwareButton(
                  label: 'View Insights',
                  icon: Icons.insights,
                  color: _ProfileColors.periwinkle,
                  onTap: onInsightsTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonAwareButton extends StatelessWidget {
  const _SkeletonAwareButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String? label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: label == null ? null : onTap,
        child: SizedBox(
          height: 36,
          child: Center(
            child: label == null
                ? const _SkeletonLine(widthFactor: .54, height: 10)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 16, color: Colors.black),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label!,
                          overflow: TextOverflow.ellipsis,
                          style: _ProfileText.button,
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

class _AboutMindMateCard extends StatelessWidget {
  const _AboutMindMateCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _ProfileDecor.card(radius: 14),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About MindMate', style: _ProfileText.cardTitle),
          SizedBox(height: 10),
          Text(
            'MindMate supports mental health awareness, reflection, and access to counseling resources.',
            style: _ProfileText.body,
          ),
          SizedBox(height: 10),
          Text(
            'This app does not replace professional care. For urgent concerns, contact PACC Counseling Services.',
            style: _ProfileText.body,
          ),
        ],
      ),
    );
  }
}

class _DataProtectionCard extends StatelessWidget {
  const _DataProtectionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: _ProfileDecor.card(radius: 14),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.privacy_tip_outlined, size: 28, color: Colors.black),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your data is protected', style: _ProfileText.cardTitle),
                SizedBox(height: 7),
                Text(
                  'Profile details will stay private and only appear here when connected to secure backend data.',
                  style: _ProfileText.body,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileFooter extends StatelessWidget {
  const _ProfileFooter({required this.onTermsTap});

  final VoidCallback onTermsTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            const Text('Privacy Policy', style: _ProfileText.footerLink),
            const Text('-', style: _ProfileText.footerLink),
            TextButton(
              key: const Key('profile-terms-link'),
              onPressed: onTermsTap,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Terms and Conditions',
                style: _ProfileText.footerLink,
              ),
            ),
            const Text('-', style: _ProfileText.footerLink),
            const Text(
              'Accessibility Statement',
              style: _ProfileText.footerLink,
            ),
          ],
        ),
        const SizedBox(height: 28),
        const _ProfileAssetImage(
          assetName: 'logo.png 3.png',
          width: 48,
          height: 48,
        ),
        const SizedBox(height: 8),
        const Text('Mental Health Companion', style: _ProfileText.footer),
      ],
    );
  }
}

class _LogOutButton extends StatelessWidget {
  const _LogOutButton({required this.isLoading, required this.onTap});

  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Log out of MindMate',
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton.icon(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: _ProfileColors.danger,
            backgroundColor: Colors.white,
            side: const BorderSide(color: _ProfileColors.danger, width: 1.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          icon: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _ProfileColors.danger,
                  ),
                )
              : const Icon(Icons.logout_rounded, size: 20),
          label: Text(isLoading ? 'Logging Out...' : 'Log Out'),
        ),
      ),
    );
  }
}

class _FloatingProfileBackground extends StatelessWidget {
  const _FloatingProfileBackground({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = animation.value;
        return Stack(
          children: [
            _BackgroundCircle(top: 30 + (value * 10), left: 42, size: 40),
            _BackgroundCircle(top: 92, right: 10 + (value * 8), size: 38),
            _BackgroundCircle(top: 260 + (value * 12), left: 172, size: 42),
            _BackgroundCircle(bottom: 210, left: 0 + (value * 12), size: 36),
            _BackgroundCircle(bottom: 92 + (value * 9), right: 38, size: 40),
            _BackgroundCircle(bottom: 36, left: 82 + (value * 7), size: 38),
          ],
        );
      },
    );
  }
}

class _BackgroundCircle extends StatelessWidget {
  const _BackgroundCircle({
    this.top,
    this.right,
    this.bottom,
    this.left,
    required this.size,
  });

  final double? top;
  final double? right;
  final double? bottom;
  final double? left;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: _ProfileColors.circle,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ProfileAssetImage extends StatelessWidget {
  const _ProfileAssetImage({
    required this.assetName,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  final String assetName;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      '${AppAssets.profileImages}/$assetName',
      width: width,
      height: height,
      fit: fit,
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

class _AnimatedProfileSection extends StatelessWidget {
  const _AnimatedProfileSection({required this.child, required this.delay});

  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + delay),
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

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({
    required this.widthFactor,
    required this.height,
    this.color = const Color(0xFFEDE4CA),
  });

  final double widthFactor;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: _SkeletonBox(height: height, color: color),
    );
  }
}

class _SkeletonCircle extends StatelessWidget {
  const _SkeletonCircle({
    required this.size,
    this.color = const Color(0xFFEDE4CA),
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _SkeletonBox(
      width: size,
      height: size,
      radius: size / 2,
      color: color,
    );
  }
}

class _SkeletonBox extends StatefulWidget {
  const _SkeletonBox({
    required this.height,
    this.width,
    this.radius = 8,
    this.color = const Color(0xFFEDE4CA),
  });

  final double? width;
  final double height;
  final double radius;
  final Color color;

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: .46,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.user});

  final UserModel user;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _schoolIdController;
  late final TextEditingController _departmentController;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(
      text: widget.user.firstName ?? '',
    );
    _middleNameController = TextEditingController(
      text: widget.user.middleName ?? '',
    );
    _lastNameController = TextEditingController(
      text: widget.user.lastName ?? '',
    );
    _schoolIdController = TextEditingController(
      text: widget.user.schoolId ?? '',
    );
    _departmentController = TextEditingController(
      text: widget.user.department ?? '',
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _schoolIdController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final isSaving = context.watch<UserProvider>().isSaving;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: _ProfileColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD7CBA7),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('Edit Profile', style: _ProfileText.title),
                  const SizedBox(height: 14),
                  _EditField(
                    controller: _firstNameController,
                    label: 'First name',
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  _EditField(
                    controller: _middleNameController,
                    label: 'Middle name',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 10),
                  _EditField(
                    controller: _lastNameController,
                    label: 'Last name',
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  _EditField(
                    controller: _schoolIdController,
                    label: 'School ID',
                    enabled: false,
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  _EditField(
                    controller: _departmentController,
                    label: 'College or Department',
                    enabled: false,
                    textInputAction: TextInputAction.done,
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  InputDecorator(
                    decoration: _editDecoration('Verified population role'),
                    child: Text(widget.user.roleLabel),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: isSaving ? null : _requestRoleCorrection,
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Request role correction'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: isSaving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _ProfileColors.sun,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text('Save Profile'),
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

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final updated = widget.user.copyWith(
      firstName: _firstNameController.text.trim(),
      middleName: _middleNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
    );
    final success = await context.read<UserProvider>().updateProfile(updated);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Profile updated.')));
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            context.read<UserProvider>().errorMessage ??
                'Unable to update profile.',
          ),
        ),
      );
  }

  Future<void> _requestRoleCorrection() async {
    final reasonController = TextEditingController();
    var requested =
        widget.user.effectivePopulationRole == PopulationRole.student
        ? PopulationRole.teaching
        : PopulationRole.student;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Request role correction'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<PopulationRole>(
                initialValue: requested,
                items: PopulationRole.values
                    .where(
                      (role) => role != widget.user.effectivePopulationRole,
                    )
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(role.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => requested = value);
                },
                decoration: const InputDecoration(labelText: 'Requested role'),
              ),
              TextField(
                controller: reasonController,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText:
                      'Explain why your institutional role needs correction.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (reasonController.text.trim().length >= 10) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) {
      reasonController.dispose();
      return;
    }
    final success = await context.read<UserProvider>().requestRoleCorrection(
      requestedRole: requested,
      reason: reasonController.text,
    );
    reasonController.dispose();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Role correction request submitted.'
              : 'Unable to submit request.',
        ),
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.controller,
    required this.label,
    this.textInputAction,
    this.validator,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      textInputAction: textInputAction,
      validator: validator,
      decoration: _editDecoration(label),
      style: const TextStyle(
        color: _ProfileColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

InputDecoration _editDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _ProfileColors.divider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _ProfileColors.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _ProfileColors.sun, width: 1.5),
    ),
  );
}

class _BlankProfilePage extends StatelessWidget {
  const _BlankProfilePage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ProfileColors.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: _ProfileColors.sun,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: const SizedBox.expand(),
    );
  }
}

class _ProfileColors {
  const _ProfileColors._();

  static const background = Color(0xFFFAF4E1);
  static const sun = Color(0xFFFFCA24);
  static const circle = Color(0x66E5D28F);
  static const divider = Color(0xFFE1D9C7);
  static const text = Color(0xFF18130C);
  static const muted = Color(0xFF6E6658);
  static const periwinkle = Color(0xFFAFC2F7);
  static const danger = Color(0xFFB3261E);
}

class _ProfileText {
  const _ProfileText._();

  static const title = TextStyle(
    color: Colors.black,
    fontSize: 20,
    fontWeight: FontWeight.w900,
  );

  static const profileName = TextStyle(
    color: Colors.black,
    fontSize: 15,
    fontWeight: FontWeight.w900,
  );

  static const profileRole = TextStyle(
    color: Colors.black,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  static const metricValue = TextStyle(
    color: Colors.black,
    fontSize: 22,
    height: 1,
    fontWeight: FontWeight.w900,
  );

  static const metricLabel = TextStyle(
    color: Colors.black,
    fontSize: 10,
    fontWeight: FontWeight.w800,
  );

  static const action = TextStyle(
    color: _ProfileColors.text,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  static const cardTitle = TextStyle(
    color: Colors.black,
    fontSize: 13,
    fontWeight: FontWeight.w900,
  );

  static const body = TextStyle(
    color: _ProfileColors.muted,
    fontSize: 11,
    height: 1.38,
    fontWeight: FontWeight.w500,
  );

  static const button = TextStyle(
    color: Colors.black,
    fontSize: 11,
    fontWeight: FontWeight.w900,
  );

  static const footerLink = TextStyle(
    color: Colors.black,
    fontSize: 12,
    fontWeight: FontWeight.w900,
  );

  static const footer = TextStyle(
    color: Colors.black,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );
}

class _ProfileDecor {
  const _ProfileDecor._();

  static BoxDecoration card({
    Color color = Colors.white,
    Color shadowColor = const Color(0x1F000000),
    double radius = 12,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: shadowColor,
          blurRadius: 14,
          offset: const Offset(0, 7),
        ),
      ],
    );
  }
}
