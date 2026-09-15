import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../models/admin_inquiry_model.dart';
import '../../../models/appointment_model.dart';
import '../../../models/app_notification_model.dart';
import '../../../models/pacc_availability_model.dart';
import '../../../models/user_model.dart';
import '../../../models/profile_roles.dart';
import '../domain/admin_management_models.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../../../repositories/admin_status_repository.dart';
import 'admin_assessment_detail_screen.dart';
import 'staff_registration_screen.dart';
import 'user_management_page.dart';
import 'profile_management_page.dart';
import 'report_generation_page.dart';
import 'admin_notifications_page.dart';
import 'admin_change_password_screen.dart';
import 'academic_structure_page.dart';
import 'admin_operations_dashboard.dart';
import 'staff_operations_dashboard.dart';
import 'counselor_operations_dashboard.dart';
import 'counselor_workflow_page.dart';
import '../../../services/inquiry_pdf_service.dart';
import '../../../services/firebase/firebase_error_message.dart';
import '../theme/admin_theme.dart';

const _yellow = AdminColors.accentStrong;
const _cream = AdminColors.canvas;
const _purple = AdminColors.accentSoft;

String _headerRoleLabel(AccessRole role) => switch (role) {
  AccessRole.admin => 'Administrator',
  AccessRole.counselor => 'Counselor',
  AccessRole.portalStaff => 'PAACC Staff',
  AccessRole.appUser => 'Portal User',
};

enum AdminPortalPage {
  dashboard,
  users,
  academicStructure,
  profiling,
  appointments,
  cases,
  followUps,
  reports,
  notifications,
  availability,
  inquiries,
  assessments,
  profile,
}

extension on AdminPortalPage {
  String get label => switch (this) {
    AdminPortalPage.dashboard => 'Dashboard',
    AdminPortalPage.users => 'User Management',
    AdminPortalPage.academicStructure => 'Academic Structure',
    AdminPortalPage.profiling => 'Profiling Management',
    AdminPortalPage.appointments => 'Appointments',
    AdminPortalPage.cases => 'My Cases',
    AdminPortalPage.followUps => 'Follow-ups',
    AdminPortalPage.reports => 'Reports',
    AdminPortalPage.notifications => 'Notifications',
    AdminPortalPage.availability => 'Schedule',
    AdminPortalPage.inquiries => 'Inquiries',
    AdminPortalPage.assessments => 'Assessment Results',
    AdminPortalPage.profile => 'Profile',
  };

  String get workspaceLabel => switch (this) {
    AdminPortalPage.appointments => 'Appointments',
    AdminPortalPage.availability => 'Schedule',
    AdminPortalPage.reports => 'Reports',
    _ => label,
  };

  IconData get icon => switch (this) {
    AdminPortalPage.dashboard => Icons.home_outlined,
    AdminPortalPage.users => Icons.group_outlined,
    AdminPortalPage.academicStructure => Icons.account_tree_outlined,
    AdminPortalPage.profiling => Icons.badge_outlined,
    AdminPortalPage.appointments => Icons.calendar_month_outlined,
    AdminPortalPage.cases => Icons.folder_shared_outlined,
    AdminPortalPage.followUps => Icons.task_alt_outlined,
    AdminPortalPage.reports => Icons.analytics_outlined,
    AdminPortalPage.notifications => Icons.notifications_outlined,
    AdminPortalPage.availability => Icons.storefront_outlined,
    AdminPortalPage.inquiries => Icons.chat_bubble_outline_rounded,
    AdminPortalPage.assessments => Icons.assignment_outlined,
    AdminPortalPage.profile => Icons.account_circle_outlined,
  };
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key, this.repository});
  final AdminPortalRepository? repository;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _schoolId = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _passwordVisible = false;

  @override
  void dispose() {
    _schoolId.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_schoolId.text.trim().isEmpty || _password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your School ID and password.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final repository = widget.repository ?? AdminPortalRepository();
      final access = await repository.signInStaff(
        schoolId: _schoolId.text,
        password: _password.text,
      );
      if (!mounted) return;
      if (!access.isGranted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PortalAccessStatusScreen(
              repository: repository,
              evaluation: access,
            ),
          ),
        );
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => repository.mustChangePassword
              ? AdminChangePasswordScreen(repository: repository)
              : AdminPortalHome(repository: repository),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FirebaseAuthException &&
                    const {
                      'invalid-credential',
                      'wrong-password',
                      'user-not-found',
                    }.contains(error.code)
                ? 'Email or password is incorrect.'
                : FirebaseErrorMessage.describe(
                    error,
                    fallback:
                        'We could not sign you in. Check your details and try again.',
                  ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: constraints.maxWidth < 520 ? 20 : 40,
            vertical: 32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(constraints.maxWidth < 520 ? 24 : 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/APP LOGO/MindMate_LOGO.jpg',
                        height: 72,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.psychology_alt_rounded,
                          color: _yellow,
                          size: 62,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'MindMate',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Counseling Management System',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 34),
                      _LoginField(
                        label: 'Email',
                        hint: 'Enter your email address',
                        controller: _schoolId,
                      ),
                      const SizedBox(height: 14),
                      _LoginField(
                        label: 'Password',
                        hint: 'Enter your password',
                        obscure: !_passwordVisible,
                        controller: _password,
                        onSubmitted: (_) {
                          if (!_submitting) _signIn();
                        },
                        suffixIcon: IconButton(
                          tooltip: _passwordVisible
                              ? 'Hide password'
                              : 'Show password',
                          onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _submitting ? null : _signIn,
                          child: Text(
                            _submitting ? 'Signing in...' : 'Sign in',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _submitting ? null : _resetPassword,
                        child: const Text('Forgot password?'),
                      ),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => StaffRegistrationScreen(
                                    repository:
                                        widget.repository ??
                                        AdminPortalRepository(),
                                  ),
                                ),
                              ),
                        child: const Text('Request PAACC Portal Access'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _resetPassword() async {
    if (_schoolId.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email address first.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await (widget.repository ?? AdminPortalRepository()).sendPasswordReset(
        _schoolId.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'If an account exists for that email, a secure password reset '
              'link has been sent.',
            ),
            duration: Duration(seconds: 7),
          ),
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FirebaseErrorMessage.describe(
                error,
                fallback: 'Unable to send the reset email. Please try again.',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to send reset email.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.suffixIcon,
    this.onSubmitted,
  });
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 7),
      TextField(
        controller: controller,
        obscureText: obscure,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: hint,
          suffixIcon: suffixIcon,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
        ),
      ),
    ],
  );
}

class AdminPortalHome extends StatefulWidget {
  const AdminPortalHome({super.key, this.repository});
  final AdminPortalRepository? repository;
  @override
  State<AdminPortalHome> createState() => _AdminPortalHomeState();
}

class _AdminPortalHomeState extends State<AdminPortalHome> {
  late final AdminPortalRepository _repository =
      widget.repository ?? AdminPortalRepository();
  AdminPortalPage _page = AdminPortalPage.dashboard;
  bool _navCollapsed = false;
  late final Stream<List<AppNotificationModel>> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = _repository.watchPortalNotifications();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      return Scaffold(
        backgroundColor: _cream,
        drawer: compact
            ? Drawer(
                child: _Nav(
                  page: _page,
                  onChanged: _setPage,
                  compact: true,
                  accessRole: _repository.currentAccessRole,
                  isSuperAdmin: _repository.isSuperAdmin,
                ),
              )
            : null,
        body: Row(
          children: [
            if (!compact)
              SizedBox(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: _navCollapsed
                      ? 76
                      : constraints.maxWidth < 1120
                      ? 224
                      : 252,
                  child: _Nav(
                    page: _page,
                    onChanged: _setPage,
                    collapsed: _navCollapsed,
                    accessRole: _repository.currentAccessRole,
                    isSuperAdmin: _repository.isSuperAdmin,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  _PortalHeader(
                    compact: compact,
                    navCollapsed: _navCollapsed,
                    onMenuPressed: compact
                        ? null
                        : () => setState(() => _navCollapsed = !_navCollapsed),
                    page: _page,
                    repository: _repository,
                    notifications: _notifications,
                    onOpenNotifications: () =>
                        _setPage(AdminPortalPage.notifications),
                  ),
                  Expanded(child: _buildPage()),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton:
            _repository.currentAccessRole.canAccessClinicalData &&
                _page != AdminPortalPage.notifications
            ? _NotificationBubble(
                notifications: _notifications,
                onPressed: () => _setPage(AdminPortalPage.notifications),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      );
    },
  );

  void _setPage(AdminPortalPage page) {
    Navigator.of(context).maybePop();
    setState(() => _page = page);
  }

  Widget _buildPage() => switch (_page) {
    AdminPortalPage.dashboard =>
      _repository.currentAccessRole == AccessRole.portalStaff
          ? StaffOperationsDashboardPage(
              repository: _repository,
              onNavigate: _setPage,
            )
          : _repository.currentAccessRole == AccessRole.counselor
          ? CounselorOperationsDashboardPage(
              repository: _repository,
              onNavigate: _setPage,
            )
          : AdminOperationsDashboardPage(
              repository: _repository,
              onNavigate: _setPage,
            ),
    AdminPortalPage.users => UserManagementPage(
      repository: _repository,
      onOpenAcademicStructure: () =>
          _setPage(AdminPortalPage.academicStructure),
    ),
    AdminPortalPage.academicStructure => AcademicStructurePage(
      repository: _repository,
    ),
    AdminPortalPage.profiling => ProfileManagementPage(repository: _repository),
    AdminPortalPage.appointments => _AppointmentsPage(
      repository: _repository,
      onOpenAssessments: _repository.currentAccessRole.canAccessClinicalData
          ? () => _setPage(AdminPortalPage.assessments)
          : null,
    ),
    AdminPortalPage.cases => CounselorWorkflowPage(
      repository: _repository,
      mode: CounselorWorkflowMode.cases,
      onOpenAppointments: () => _setPage(AdminPortalPage.appointments),
    ),
    AdminPortalPage.followUps => CounselorWorkflowPage(
      repository: _repository,
      mode: CounselorWorkflowMode.followUps,
      onOpenAppointments: () => _setPage(AdminPortalPage.appointments),
    ),
    AdminPortalPage.reports => ReportGenerationPage(repository: _repository),
    AdminPortalPage.notifications => AdminNotificationsPage(
      repository: _repository,
      onOpenAppointments: () => _setPage(AdminPortalPage.appointments),
      onOpenInquiries: () => _setPage(AdminPortalPage.inquiries),
    ),
    AdminPortalPage.availability => _AvailabilityPage(repository: _repository),
    AdminPortalPage.inquiries => _InquiriesPage(repository: _repository),
    AdminPortalPage.assessments => _AssessmentsPage(
      repository: _repository,
      onBack: () => _setPage(AdminPortalPage.appointments),
    ),
    AdminPortalPage.profile => _ProfilePage(repository: _repository),
  };
}

class _Nav extends StatelessWidget {
  const _Nav({
    required this.page,
    required this.onChanged,
    this.compact = false,
    this.collapsed = false,
    this.accessRole = AccessRole.admin,
    this.isSuperAdmin = false,
  });
  final AdminPortalPage page;
  final ValueChanged<AdminPortalPage> onChanged;
  final bool compact;
  final bool collapsed;
  final AccessRole accessRole;
  final bool isSuperAdmin;

  bool _allowed(AdminPortalPage page) => switch (page) {
    AdminPortalPage.users => isSuperAdmin,
    AdminPortalPage.academicStructure => isSuperAdmin,
    // Counselor case/profile access must come through an assigned-case
    // surface. The legacy organization-wide profiling screen is admin-only.
    AdminPortalPage.profiling => isSuperAdmin,
    AdminPortalPage.cases ||
    AdminPortalPage.followUps => accessRole == AccessRole.counselor,
    AdminPortalPage.reports => accessRole.canAccessClinicalData,
    // Notifications are opened from the persistent header bell instead of
    // duplicating the destination in the workspace navigation.
    AdminPortalPage.notifications => false,
    // Assessment results are intentionally reached from PAACC Appointments.
    AdminPortalPage.assessments => false,
    AdminPortalPage.inquiries =>
      accessRole == AccessRole.counselor || accessRole == AccessRole.admin,
    _ => accessRole.canUsePortal || accessRole == AccessRole.admin,
  };
  @override
  Widget build(BuildContext context) {
    final sections = <_NavSection>[
      const _NavSection('Overview', [AdminPortalPage.dashboard]),
      const _NavSection('People', [
        AdminPortalPage.users,
        AdminPortalPage.profiling,
        AdminPortalPage.academicStructure,
      ]),
      const _NavSection('Counseling', [
        AdminPortalPage.appointments,
        AdminPortalPage.availability,
        AdminPortalPage.cases,
        AdminPortalPage.followUps,
        AdminPortalPage.inquiries,
      ]),
      const _NavSection('Insights', [AdminPortalPage.reports]),
      const _NavSection('System', [AdminPortalPage.profile]),
    ];
    return Material(
      color: AdminColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                collapsed ? 20 : 20,
                22,
                collapsed ? 20 : 20,
                18,
              ),
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AdminColors.accentSoft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.psychology_alt_outlined, size: 21),
                  ),
                  if (!collapsed) const SizedBox(width: 12),
                  if (!collapsed)
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MindMate',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'ADMIN PORTAL',
                            style: TextStyle(
                              color: AdminColors.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (compact)
                    IconButton(
                      tooltip: 'Close navigation',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (!collapsed)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 22, 20, 8),
                child: Text(
                  'WORKSPACE',
                  style: TextStyle(
                    color: AdminColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            if (collapsed) const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final section in sections)
                    if (section.pages.any(_allowed)) ...[
                      if (!collapsed)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 5),
                          child: Text(
                            section.title.toUpperCase(),
                            style: const TextStyle(
                              color: AdminColors.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      for (final item in section.pages.where(_allowed))
                        if (collapsed)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 3,
                            ),
                            child: Tooltip(
                              message: item.workspaceLabel,
                              child: Material(
                                color: page == item
                                    ? AdminColors.accentSoft
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(9),
                                  onTap: () => onChanged(item),
                                  child: SizedBox(
                                    height: 46,
                                    child: Icon(
                                      item.icon,
                                      color: page == item
                                          ? AdminColors.ink
                                          : AdminColors.muted,
                                      size: 21,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 2,
                            ),
                            child: ListTile(
                              dense: true,
                              minTileHeight: 46,
                              leading: Icon(
                                item.icon,
                                color: page == item
                                    ? AdminColors.ink
                                    : AdminColors.muted,
                                size: 21,
                              ),
                              title: Text(
                                item.workspaceLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AdminColors.ink,
                                  fontSize: 13,
                                ),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                              selected: page == item,
                              selectedTileColor: AdminColors.accentSoft,
                              onTap: () => onChanged(item),
                            ),
                          ),
                    ],
                ],
              ),
            ),
            if (!collapsed)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Counseling Management System',
                  style: TextStyle(color: AdminColors.muted, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavSection {
  const _NavSection(this.title, this.pages);

  final String title;
  final List<AdminPortalPage> pages;
}

class _PortalHeader extends StatelessWidget {
  const _PortalHeader({
    required this.compact,
    required this.navCollapsed,
    required this.onMenuPressed,
    required this.page,
    required this.repository,
    required this.notifications,
    required this.onOpenNotifications,
  });
  final bool compact;
  final bool navCollapsed;
  final VoidCallback? onMenuPressed;
  final AdminPortalPage page;
  final AdminPortalRepository repository;
  final Stream<List<AppNotificationModel>> notifications;
  final VoidCallback onOpenNotifications;
  @override
  Widget build(BuildContext context) {
    final showIdentity = MediaQuery.sizeOf(context).width >= 560;
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 28),
      decoration: const BoxDecoration(
        color: AdminColors.surface,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        children: [
          Builder(
            builder: (context) => IconButton(
              tooltip: compact
                  ? 'Open workspace'
                  : navCollapsed
                  ? 'Expand workspace'
                  : 'Collapse workspace',
              icon: const Icon(Icons.menu),
              onPressed: compact
                  ? () => Scaffold.of(context).openDrawer()
                  : onMenuPressed,
            ),
          ),
          if (compact) const SizedBox(width: 4),
          Text(
            page.label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          _HeaderNotificationButton(
            notifications: notifications,
            onPressed: onOpenNotifications,
          ),
          const SizedBox(width: 4),
          if (showIdentity) _HeaderIdentity(repository: repository),
          if (showIdentity) const SizedBox(width: 10),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Sign out?'),
                  content: const Text(
                    'Are you sure you want to sign out of the MindMate Admin Portal?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              await repository.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => AdminLoginScreen(repository: repository),
                  ),
                  (_) => false,
                );
              }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
    );
  }
}

class _HeaderIdentity extends StatelessWidget {
  const _HeaderIdentity({required this.repository});
  final AdminPortalRepository repository;

  @override
  Widget build(BuildContext context) {
    final user = repository.currentAuthUser;
    if (user == null) return const SizedBox.shrink();
    return StreamBuilder<Map<String, dynamic>?>(
      stream: repository.watchOwnProfile(user.uid),
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};
        final first = data['firstName']?.toString().trim() ?? '';
        final last = data['lastName']?.toString().trim() ?? '';
        final profileName = [
          first,
          last,
        ].where((part) => part.isNotEmpty).join(' ');
        final name = profileName.isNotEmpty
            ? profileName
            : (data['name']?.toString().trim().isNotEmpty == true
                  ? data['name'].toString().trim()
                  : user.displayName?.trim().isNotEmpty == true
                  ? user.displayName!.trim()
                  : 'Staff member');
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(
              _headerRoleLabel(repository.currentAccessRole),
              style: const TextStyle(fontSize: 11, color: AdminColors.muted),
            ),
          ],
        );
      },
    );
  }
}

class _HeaderNotificationButton extends StatelessWidget {
  const _HeaderNotificationButton({
    required this.notifications,
    required this.onPressed,
  });

  final Stream<List<AppNotificationModel>> notifications;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<AppNotificationModel>>(
        stream: notifications,
        builder: (context, snapshot) {
          final unread = (snapshot.data ?? const <AppNotificationModel>[])
              .where((item) => !item.isRead)
              .length;
          return IconButton(
            tooltip: unread == 0
                ? 'Notifications'
                : '$unread unread notifications',
            onPressed: onPressed,
            icon: _NotificationIcon(unread: unread),
          );
        },
      );
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.unread});
  final int unread;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      const Icon(Icons.notifications_outlined),
      if (unread > 0)
        Positioned(
          right: -8,
          top: -7,
          child: Container(
            constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AdminColors.danger,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AdminColors.surface, width: 1.5),
            ),
            child: Text(
              unread > 99 ? '99+' : '$unread',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
    ],
  );
}

class _NotificationBubble extends StatelessWidget {
  const _NotificationBubble({
    required this.notifications,
    required this.onPressed,
  });

  final Stream<List<AppNotificationModel>> notifications;
  final VoidCallback onPressed;

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<AppNotificationModel>>(
    stream: notifications,
    builder: (context, snapshot) {
      final unread = (snapshot.data ?? const <AppNotificationModel>[])
          .where((item) => !item.isRead)
          .toList(growable: false);
      if (unread.isEmpty) return const SizedBox.shrink();
      return FloatingActionButton.extended(
        heroTag: 'admin-notification-bubble',
        onPressed: onPressed,
        backgroundColor: AdminColors.accentSoft,
        foregroundColor: AdminColors.ink,
        icon: const Icon(Icons.notifications_outlined),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: Text(
            '${unread.length} new ${unread.length == 1 ? 'notification' : 'notifications'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    },
  );
}

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
      28,
      MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
      40,
    ),
    child: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            child,
          ],
        ),
      ),
    ),
  );
}

class _UsersPage extends StatefulWidget {
  const _UsersPage({required this.repository});
  final AdminPortalRepository repository;
  @override
  State<_UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<_UsersPage> {
  String query = '';
  VerificationStatus? verificationFilter;
  @override
  Widget build(BuildContext context) => _Page(
    title: 'User Management',
    subtitle: 'Manage system users and staff accounts',
    child: StreamBuilder<List<UserModel>>(
      stream: widget.repository.watchUsers(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const _AccessPanel();
        final users = (snapshot.data ?? const <UserModel>[])
            .where(
              (u) =>
                  (u.displayName.toLowerCase().contains(query.toLowerCase()) ||
                      u.email.toLowerCase().contains(query.toLowerCase())) &&
                  (verificationFilter == null ||
                      u.verificationStatus == verificationFilter),
            )
            .toList();
        return Container(
          decoration: _box,
          child: Column(
            children: [
              if (widget.repository.currentAccessRole.canManageAccess)
                _RoleCorrectionQueue(repository: widget.repository),
              if (widget.repository.currentAccessRole.canManageAccess)
                _OrganizationDirectoryPanel(repository: widget.repository),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => query = v),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search users...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<VerificationStatus?>(
                      value: verificationFilter,
                      hint: const Text('All verification states'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All')),
                        ...VerificationStatus.values.map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => verificationFilter = value),
                    ),
                  ],
                ),
              ),
              _ResponsiveTable(
                columns: const [
                  'Name',
                  'Contact',
                  'Role',
                  'Account',
                  'Department',
                  'College / Course',
                  'Status',
                  'Last Active',
                  'Join Date',
                  'Actions',
                ],
                rows: users
                    .map(
                      (u) => [
                        u.displayName,
                        u.email,
                        _Tag(label: u.roleLabel, color: _purple),
                        _Tag(
                          label: u.staffAccountStatus?.label ?? 'App user',
                          color:
                              u.staffAccountStatus ==
                                  StaffAccountStatus.approved
                              ? const Color(0xFF8DD78B)
                              : Colors.orange.shade200,
                        ),
                        u.departmentId ?? u.department ?? '—',
                        [u.collegeId, u.courseId]
                                .whereType<String>()
                                .where((e) => e.isNotEmpty)
                                .join(' / ')
                                .isEmpty
                            ? '—'
                            : [u.collegeId, u.courseId]
                                  .whereType<String>()
                                  .where((e) => e.isNotEmpty)
                                  .join(' / '),
                        _Tag(
                          label: u.verificationStatus.label,
                          color:
                              u.verificationStatus ==
                                  VerificationStatus.verified
                              ? const Color(0xFF8DD78B)
                              : Colors.orange.shade200,
                        ),
                        _date(u.lastActiveAt),
                        _date(u.createdAt),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Review verification',
                              onPressed: () => _reviewVerification(u),
                              icon: const Icon(
                                Icons.verified_user_outlined,
                                color: _yellow,
                              ),
                            ),
                            if (u.staffAccountStatus ==
                                    StaffAccountStatus.pending &&
                                widget
                                    .repository
                                    .currentAccessRole
                                    .canManageAccess)
                              IconButton(
                                tooltip: 'Review staff registration',
                                onPressed: () => _reviewStaff(u),
                                icon: const Icon(
                                  Icons.how_to_reg,
                                  color: Colors.green,
                                ),
                              ),
                            if ((u.staffAccountStatus ==
                                        StaffAccountStatus.approved ||
                                    u.staffAccountStatus ==
                                        StaffAccountStatus.disabled) &&
                                widget
                                    .repository
                                    .currentAccessRole
                                    .canManageAccess)
                              IconButton(
                                tooltip:
                                    u.staffAccountStatus ==
                                        StaffAccountStatus.disabled
                                    ? 'Enable account'
                                    : 'Disable account',
                                onPressed: () => _toggleStaff(u),
                                icon: Icon(
                                  u.staffAccountStatus ==
                                          StaffAccountStatus.disabled
                                      ? Icons.lock_open
                                      : Icons.block,
                                  color: Colors.red,
                                ),
                              ),
                            if (widget
                                .repository
                                .currentAccessRole
                                .canManageAccess)
                              IconButton(
                                tooltip: 'Manage portal access',
                                onPressed: () => _manageAccess(u),
                                icon: const Icon(
                                  Icons.admin_panel_settings_outlined,
                                ),
                              ),
                            if (u.staffAccountStatus != null &&
                                widget
                                    .repository
                                    .currentAccessRole
                                    .canManageAccess)
                              IconButton(
                                tooltip: 'View audit history',
                                onPressed: () => _showAudit(u),
                                icon: const Icon(Icons.history),
                              ),
                          ],
                        ),
                      ],
                    )
                    .toList(),
              ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _reviewVerification(UserModel user) async {
    var decision = VerificationStatus.verified;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Review ${user.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<VerificationStatus>(
                initialValue: decision,
                items: const [
                  DropdownMenuItem(
                    value: VerificationStatus.verified,
                    child: Text('Verify'),
                  ),
                  DropdownMenuItem(
                    value: VerificationStatus.rejected,
                    child: Text('Reject'),
                  ),
                  DropdownMenuItem(
                    value: VerificationStatus.needsReview,
                    child: Text('Needs review'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => decision = value);
                },
              ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Decision reason'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && reason.text.trim().length >= 3) {
      await widget.repository.reviewProfileVerification(
        userId: user.id,
        decision: decision,
        reason: reason.text,
      );
    }
    reason.dispose();
  }

  Future<void> _manageAccess(UserModel user) async {
    var access = user.accessRole;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Access for ${user.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<AccessRole>(
                initialValue: access,
                items:
                    const [
                          AccessRole.appUser,
                          AccessRole.portalStaff,
                          AccessRole.counselor,
                        ]
                        .map(
                          (role) => DropdownMenuItem(
                            value: role,
                            child: Text(role.storedValue),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => access = value);
                },
              ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Change reason'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && reason.text.trim().length >= 3) {
      await widget.repository.assignAccessRole(
        userId: user.id,
        accessRole: access,
        reason: reason.text,
      );
    }
    reason.dispose();
  }

  Future<void> _reviewStaff(UserModel user) async {
    var role = AccessRole.portalStaff;
    var approve = true;
    final reason = TextEditingController(text: 'Staff registration reviewed');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Review ${user.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                value: approve,
                onChanged: (v) => setState(() => approve = v),
                title: Text(approve ? 'Approve' : 'Reject'),
              ),
              if (approve)
                DropdownButtonFormField<AccessRole>(
                  initialValue: role,
                  items: const [
                    DropdownMenuItem(
                      value: AccessRole.portalStaff,
                      child: Text('Portal Staff'),
                    ),
                    DropdownMenuItem(
                      value: AccessRole.counselor,
                      child: Text('Counselor'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => role = v);
                  },
                ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await widget.repository.reviewStaffRegistration(
        userId: user.id,
        approve: approve,
        accessRole: role,
        reason: reason.text,
      );
    }
    reason.dispose();
  }

  Future<void> _toggleStaff(UserModel user) async {
    final enable = user.staffAccountStatus == StaffAccountStatus.disabled;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${enable ? 'Enable' : 'Disable'} ${user.displayName}?'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true && reason.text.trim().length >= 3) {
      await widget.repository.setStaffAccountEnabled(
        userId: user.id,
        enabled: enable,
        reason: reason.text,
      );
    }
    reason.dispose();
  }

  Future<void> _showAudit(UserModel user) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Audit history — ${user.displayName}'),
      content: SizedBox(
        width: 560,
        child: StreamBuilder<List<AdminAuditEvent>>(
          stream: widget.repository.watchAdminAudit(user.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Unable to load audit history.');
            }
            final events = snapshot.data ?? const [];
            if (events.isEmpty) {
              return const Text('No privileged changes recorded.');
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: events.length,
              itemBuilder: (_, index) {
                final event = events[index];
                return ListTile(
                  title: Text(event.action),
                  subtitle: Text('${event.reason}\nActor: ${event.actorId}'),
                  trailing: Text(_date(event.createdAt)),
                );
              },
            );
          },
        ),
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

class _OrganizationDirectoryPanel extends StatelessWidget {
  const _OrganizationDirectoryPanel({required this.repository});
  final AdminPortalRepository repository;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text(
      'Colleges, Departments & Courses',
      style: TextStyle(fontWeight: FontWeight.w800),
    ),
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<List<College>>(
          stream: repository.watchColleges(),
          builder: (context, colleges) => StreamBuilder<List<Department>>(
            stream: repository.watchDepartments(),
            builder: (context, departments) => StreamBuilder<List<Course>>(
              stream: repository.watchCourses(),
              builder: (context, courses) => Column(
                children: [
                  _directoryRow(
                    context,
                    'college',
                    'Colleges',
                    colleges.data ?? const [],
                  ),
                  _directoryRow(
                    context,
                    'department',
                    'Departments',
                    departments.data ?? const [],
                    colleges: colleges.data ?? const [],
                  ),
                  _directoryRow(
                    context,
                    'course',
                    'Courses',
                    courses.data ?? const [],
                    colleges: colleges.data ?? const [],
                    departments: departments.data ?? const [],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _directoryRow(
    BuildContext context,
    String kind,
    String label,
    List<OrganizationRecord> records, {
    List<College> colleges = const [],
    List<Department> departments = const [],
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ListTile(
        title: Text(label),
        trailing: IconButton(
          icon: const Icon(Icons.add),
          onPressed: () =>
              _edit(context, kind, colleges, departments: departments),
        ),
      ),
      if (records.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('No records'),
        ),
      Wrap(
        spacing: 8,
        children: records
            .map(
              (record) => ActionChip(
                avatar: Icon(
                  record.active ? Icons.check_circle : Icons.pause_circle,
                  size: 18,
                ),
                label: Text('${record.code}: ${record.name}'),
                onPressed: () => _edit(
                  context,
                  kind,
                  colleges,
                  departments: departments,
                  record: record,
                ),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 12),
    ],
  );

  Future<void> _edit(
    BuildContext context,
    String kind,
    List<College> colleges, {
    List<Department> departments = const [],
    OrganizationRecord? record,
  }) async {
    final name = TextEditingController(text: record?.name);
    final code = TextEditingController(text: record?.code);
    String? collegeId = record is Course
        ? record.collegeId
        : record is Department
        ? record.collegeId
        : null;
    String? departmentId = record is Course ? record.departmentId : null;
    var active = record?.active ?? true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('${record == null ? 'Add' : 'Edit'} $kind'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: code,
                decoration: const InputDecoration(labelText: 'Code'),
              ),
              if (kind == 'course')
                DropdownButtonFormField<String>(
                  initialValue: collegeId,
                  decoration: const InputDecoration(labelText: 'College'),
                  items: colleges
                      .where((e) => e.active)
                      .map(
                        (e) =>
                            DropdownMenuItem(value: e.id, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    collegeId = v;
                    departmentId = null;
                  }),
                ),
              if (kind == 'department' || kind == 'course')
                DropdownButtonFormField<String>(
                  initialValue: kind == 'department' ? collegeId : departmentId,
                  decoration: InputDecoration(
                    labelText: kind == 'department' ? 'College' : 'Department',
                  ),
                  items:
                      (kind == 'department'
                              ? colleges
                                    .where((e) => e.active)
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e.id,
                                        child: Text(e.name),
                                      ),
                                    )
                              : departments
                                    .where(
                                      (e) =>
                                          e.active && e.collegeId == collegeId,
                                    )
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e.id,
                                        child: Text(e.name),
                                      ),
                                    ))
                          .toList(),
                  onChanged: (v) => setState(() {
                    if (kind == 'department') {
                      collegeId = v;
                    } else {
                      departmentId = v;
                    }
                  }),
                ),
              SwitchListTile(
                value: active,
                onChanged: (v) => setState(() => active = v),
                title: const Text('Active'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true &&
        name.text.trim().length >= 2 &&
        code.text.trim().isNotEmpty &&
        (kind == 'college' || collegeId != null) &&
        (kind != 'course' || departmentId != null)) {
      await repository.saveOrganizationRecord(
        kind: kind,
        id: record?.id,
        name: name.text,
        code: code.text,
        active: active,
        collegeId: collegeId ?? '',
        departmentId: departmentId ?? '',
      );
    }
    name.dispose();
    code.dispose();
  }
}

class _RoleCorrectionQueue extends StatelessWidget {
  const _RoleCorrectionQueue({required this.repository});
  final AdminPortalRepository repository;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<AdminRoleCorrectionRequest>>(
        stream: repository.watchRoleCorrectionRequests(),
        builder: (context, snapshot) {
          final requests =
              snapshot.data ?? const <AdminRoleCorrectionRequest>[];
          if (requests.isEmpty) return const SizedBox.shrink();
          return ExpansionTile(
            initiallyExpanded: true,
            title: Text('Role correction requests (${requests.length})'),
            children: requests
                .map(
                  (request) => ListTile(
                    title: Text(
                      '${request.currentRole} → ${request.requestedRole}',
                    ),
                    subtitle: Text(request.reason),
                    trailing: Wrap(
                      children: [
                        TextButton(
                          onPressed: () => _review(context, request, false),
                          child: const Text('Reject'),
                        ),
                        FilledButton(
                          onPressed: () => _review(context, request, true),
                          child: const Text('Approve'),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          );
        },
      );

  Future<void> _review(
    BuildContext context,
    AdminRoleCorrectionRequest request,
    bool approve,
  ) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          approve ? 'Approve role correction' : 'Reject role correction',
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Decision reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true && controller.text.trim().length >= 3) {
      await repository.reviewRoleCorrection(
        requestId: request.id,
        approve: approve,
        reason: controller.text,
      );
    }
    controller.dispose();
  }
}

class _AppointmentsPage extends StatefulWidget {
  const _AppointmentsPage({
    required this.repository,
    required this.onOpenAssessments,
  });
  final AdminPortalRepository repository;
  final VoidCallback? onOpenAssessments;
  @override
  State<_AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<_AppointmentsPage> {
  String filter = 'All';
  String departmentFilter = 'All departments';
  bool showHistory = false;
  final Set<String> selectedIds = <String>{};
  bool archiving = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: widget.repository.currentAccessRole == AccessRole.portalStaff
        ? 'Appointments'
        : 'PAACC Appointments',
    subtitle: widget.repository.currentAccessRole == AccessRole.portalStaff
        ? 'Manage today’s PAACC appointments and scheduling.'
        : 'Review, schedule, and manage counseling appointments.',
    child: StreamBuilder<List<AppointmentModel>>(
      stream: widget.repository.watchAppointments(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const _AccessPanel();
        final all = (snapshot.data ?? const <AppointmentModel>[])
            .where((appointment) => appointment.isArchived == showHistory)
            .toList();
        final query = _search.text.trim().toLowerCase();
        final items = all.where((a) {
          final status = a.status.toLowerCase().trim();
          final tab = switch (filter) {
            'Needs action' => const {
              'pending',
              'requested',
              'reschedule_required',
              'reschedule_proposed',
            }.contains(status),
            'Upcoming' =>
              status == 'confirmed' && a.scheduledAt.isAfter(DateTime.now()),
            'Completed' => const {'completed', 'complete'}.contains(status),
            'Closed' => const {
              'no_show',
              'noshow',
              'cancelled',
              'canceled',
              'declined',
            }.contains(status),
            _ => true,
          };
          return tab &&
              (query.isEmpty ||
                  a.fullName.toLowerCase().contains(query) ||
                  a.userId.toLowerCase().contains(query)) &&
              (departmentFilter == 'All departments' ||
                  a.department == departmentFilter);
        }).toList();
        final needsAction = all
            .where(
              (a) => const {
                'pending',
                'requested',
                'reschedule_required',
                'reschedule_proposed',
              }.contains(a.status.toLowerCase().trim()),
            )
            .length;
        final upcoming = all
            .where(
              (a) =>
                  a.status.toLowerCase() == 'confirmed' &&
                  a.scheduledAt.isAfter(DateTime.now()) &&
                  a.scheduledAt.isBefore(
                    DateTime.now().add(const Duration(days: 7)),
                  ),
            )
            .length;
        final completed = all
            .where(
              (a) => const {
                'completed',
                'complete',
              }.contains(a.status.toLowerCase()),
            )
            .length;
        final departments =
            all
                .map((a) => a.department ?? '')
                .where((a) => a.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        selectedIds.removeWhere(
          (id) => !items.any((appointment) => appointment.id == id),
        );
        final selectable = items
            .where((appointment) => appointment.isFinalized)
            .toList();
        final allSelected =
            selectable.isNotEmpty &&
            selectable.every(
              (appointment) => selectedIds.contains(appointment.id),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.inbox_outlined),
                  label: Text('Active queue'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.history_outlined),
                  label: Text('History'),
                ),
              ],
              selected: {showHistory},
              onSelectionChanged: (value) => setState(() {
                showHistory = value.first;
                filter = 'All';
                selectedIds.clear();
              }),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = <Widget>[
                  _AppointmentSummaryCard(
                    label: 'Needs action',
                    value: needsAction,
                    subtitle: 'Awaiting review',
                    icon: Icons.priority_high_rounded,
                    onTap: () => setState(() => filter = 'Needs action'),
                  ),
                  _AppointmentSummaryCard(
                    label: 'Today',
                    value: all
                        .where(
                          (a) =>
                              a.status.toLowerCase() == 'confirmed' &&
                              _sameDay(a.scheduledAt, DateTime.now()),
                        )
                        .length,
                    subtitle: 'Confirmed today',
                    icon: Icons.today_outlined,
                    onTap: () => setState(() => filter = 'Upcoming'),
                  ),
                  _AppointmentSummaryCard(
                    label: 'Upcoming',
                    value: upcoming,
                    subtitle: 'Next 7 days',
                    icon: Icons.event_available_outlined,
                    onTap: () => setState(() => filter = 'Upcoming'),
                  ),
                  _AppointmentSummaryCard(
                    label: 'Completed',
                    value: completed,
                    subtitle: 'This academic year',
                    icon: Icons.task_alt_outlined,
                    onTap: () => setState(() => filter = 'Completed'),
                  ),
                ];
                if (constraints.maxWidth >= 900) {
                  return Row(
                    children: [
                      for (final card in cards) ...[
                        Expanded(child: card),
                        if (card != cards.last) const SizedBox(width: 12),
                      ],
                    ],
                  );
                }
                return Wrap(spacing: 12, runSpacing: 12, children: cards);
              },
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search student name or ID',
                    ),
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: departmentFilter,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: ['All departments', ...departments]
                        .map(
                          (d) => DropdownMenuItem(
                            value: d,
                            child: Text(d, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(
                      () => departmentFilter = v ?? 'All departments',
                    ),
                  ),
                ),
                if (query.isNotEmpty || departmentFilter != 'All departments')
                  TextButton(
                    onPressed: () {
                      _search.clear();
                      setState(() => departmentFilter = 'All departments');
                    },
                    child: const Text('Clear filters'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final tab in const [
                  'All',
                  'Needs action',
                  'Upcoming',
                  'Completed',
                  'Closed',
                ])
                  ChoiceChip(
                    label: Text(
                      '$tab ${tab == 'All'
                          ? all.length
                          : tab == 'Needs action'
                          ? needsAction
                          : tab == 'Upcoming'
                          ? upcoming
                          : tab == 'Completed'
                          ? completed
                          : all.length - needsAction - upcoming - completed}',
                    ),
                    selected: filter == tab,
                    onSelected: (_) => setState(() => filter = tab),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Showing ${items.length} of ${all.length} appointments',
              style: const TextStyle(color: AdminColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (selectable.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: allSelected,
                            tristate: selectedIds.isNotEmpty && !allSelected,
                            onChanged: (value) => setState(() {
                              if (allSelected || value == false) {
                                selectedIds.clear();
                              } else {
                                selectedIds.addAll(
                                  selectable.map(
                                    (appointment) => appointment.id,
                                  ),
                                );
                              }
                            }),
                          ),
                          Text('Select finished (${selectable.length})'),
                        ],
                      ),
                      if (selectedIds.isNotEmpty)
                        FilledButton.icon(
                          onPressed: archiving ? null : _bulkArchive,
                          icon: Icon(
                            showHistory
                                ? Icons.unarchive_outlined
                                : Icons.archive_outlined,
                          ),
                          label: Text(
                            showHistory
                                ? 'Restore selected (${selectedIds.length})'
                                : 'Move to history (${selectedIds.length})',
                          ),
                        ),
                      if (selectedIds.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => selectedIds.clear()),
                          child: const Text('Clear selection'),
                        ),
                    ],
                  ),
                ),
              ),
            if (items.isNotEmpty && MediaQuery.sizeOf(context).width >= 760)
              const _AppointmentListHeader(),
            ...items.map(
              (a) => _AppointmentCard(
                item: a,
                repository: widget.repository,
                selected: selectedIds.contains(a.id),
                onSelected: a.isFinalized
                    ? (value) => setState(() {
                        if (value) {
                          selectedIds.add(a.id);
                        } else {
                          selectedIds.remove(a.id);
                        }
                      })
                    : null,
                onArchive: () => _archiveOne(a),
              ),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _archiveOne(AppointmentModel appointment) async {
    final action = showHistory ? 'restore' : 'move to history';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${action[0].toUpperCase()}${action.substring(1)} appointment?',
        ),
        content: Text(
          showHistory
              ? 'This appointment will return to the active queue.'
              : 'This finished appointment will be kept safely in History.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action[0].toUpperCase() + action.substring(1)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.archiveAppointments(
        appointmentIds: [appointment.id],
        archived: !showHistory,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              showHistory
                  ? 'Appointment restored.'
                  : 'Appointment moved to History.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The appointment could not be updated. Please try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _bulkArchive() async {
    final ids = selectedIds.toList();
    final action = showHistory ? 'restore' : 'move to History';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${action[0].toUpperCase()}${action.substring(1)} ${ids.length} appointments?',
        ),
        content: Text(
          'Only finished appointments are included. They will remain available in the ${showHistory ? 'active queue' : 'History'} view.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action[0].toUpperCase() + action.substring(1)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => archiving = true);
    try {
      final count = await widget.repository.archiveAppointments(
        appointmentIds: ids,
        archived: !showHistory,
      );
      if (mounted) {
        setState(() => selectedIds.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$count appointments ${showHistory ? 'restored' : 'moved to History'}.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The selected appointments could not be updated. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => archiving = false);
    }
  }
}

class PortalAccessStatusScreen extends StatefulWidget {
  const PortalAccessStatusScreen({
    super.key,
    required this.repository,
    required this.evaluation,
  });

  final AdminPortalRepository repository;
  final PortalAccessEvaluation evaluation;

  @override
  State<PortalAccessStatusScreen> createState() =>
      _PortalAccessStatusScreenState();
}

class _PortalAccessStatusScreenState extends State<PortalAccessStatusScreen> {
  bool _busy = false;
  String? _message;

  String get _roleLabel =>
      widget.evaluation.requestedRole == AccessRole.counselor
      ? 'Counselor'
      : 'PAACC Staff';

  ({IconData icon, String title, String body}) get _content => switch (widget
      .evaluation
      .state) {
    PortalAccessState.emailVerificationRequired => (
      icon: Icons.mark_email_unread_outlined,
      title: 'Email Verification Required',
      body:
          'Your password is correct, but your email address must be verified before your PAACC access request can be reviewed.',
    ),
    PortalAccessState.pendingAdminApproval => (
      icon: Icons.hourglass_top_rounded,
      title: 'Access Request Pending',
      body:
          'Your email has been verified. Your PAACC portal access request is waiting for administrator approval.',
    ),
    PortalAccessState.moreInformationRequired => (
      icon: Icons.info_outline_rounded,
      title: 'More Information Required',
      body: widget.evaluation.reason?.trim().isNotEmpty == true
          ? widget.evaluation.reason!
          : 'An administrator needs more information before this access request can be approved.',
    ),
    PortalAccessState.suspended => (
      icon: Icons.pause_circle_outline_rounded,
      title: 'Account Access Suspended',
      body:
          'Your PAACC portal access is currently suspended. Contact an authorized MindMate administrator if you believe this is an error.',
    ),
    PortalAccessState.rejected => (
      icon: Icons.cancel_outlined,
      title: 'Access Request Closed',
      body:
          'This PAACC portal access request was not approved. Contact an authorized MindMate administrator for assistance.',
    ),
    PortalAccessState.disabled => (
      icon: Icons.block_outlined,
      title: 'Account Access Disabled',
      body:
          'This account is not currently enabled for PAACC portal access. Contact an authorized MindMate administrator.',
    ),
    PortalAccessState.accountNotFound => (
      icon: Icons.person_search_outlined,
      title: 'Portal Account Not Found',
      body:
          'This account does not have a PAACC portal access request. Request access or contact an authorized administrator.',
    ),
    PortalAccessState.noPortalRole => (
      icon: Icons.lock_outline_rounded,
      title: 'Portal Access Not Available',
      body:
          'This account does not currently have an approved PAACC portal role.',
    ),
    PortalAccessState.granted => (
      icon: Icons.verified_outlined,
      title: 'Access Approved',
      body: 'Your PAACC portal account is active.',
    ),
  };

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final latest = await widget.repository.evaluatePortalAccess(
        refreshUser: true,
      );
      if (!mounted) return;
      if (latest.isGranted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AdminPortalHome(repository: widget.repository),
          ),
        );
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PortalAccessStatusScreen(
            repository: widget.repository,
            evaluation: latest,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = FirebaseErrorMessage.describe(
            error,
            fallback:
                'We could not refresh your access status. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final cooldown = await widget.repository.resendStaffVerificationEmail();
      if (!mounted) return;
      setState(() {
        _message = cooldown == Duration.zero
            ? 'A new verification email was sent to ${widget.evaluation.email}.'
            : 'Please wait ${cooldown.inSeconds} seconds before requesting another email.';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = FirebaseErrorMessage.describe(
            error,
            fallback:
                'We could not send a verification email. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await widget.repository.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => AdminLoginScreen(repository: widget.repository),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;
    final verificationRequired =
        widget.evaluation.state == PortalAccessState.emailVerificationRequired;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(content.icon, size: 52, color: _yellow),
                      const SizedBox(height: 18),
                      Text(
                        content.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        content.body,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AdminColors.muted,
                          height: 1.45,
                        ),
                      ),
                      if (widget.evaluation.email.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _AccessDetail(
                          label: 'Email',
                          value: widget.evaluation.email,
                        ),
                      ],
                      if (widget.evaluation.requestedRole != null) ...[
                        const SizedBox(height: 10),
                        _AccessDetail(
                          label: 'Requested role',
                          value: _roleLabel,
                        ),
                      ],
                      if (widget.evaluation.reference != null) ...[
                        const SizedBox(height: 10),
                        _AccessDetail(
                          label: 'Reference',
                          value: widget.evaluation.reference!,
                        ),
                      ],
                      if (verificationRequired ||
                          widget.evaluation.state ==
                              PortalAccessState.pendingAdminApproval) ...[
                        const SizedBox(height: 22),
                        _AccessProgress(verified: !verificationRequired),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 18),
                        Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AdminColors.muted),
                        ),
                      ],
                      const SizedBox(height: 26),
                      if (verificationRequired)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _busy ? null : _resend,
                            child: Text(
                              _busy ? 'Sending…' : 'Resend Verification Email',
                            ),
                          ),
                        ),
                      if (verificationRequired) const SizedBox(height: 10),
                      if (verificationRequired ||
                          widget.evaluation.state ==
                              PortalAccessState.pendingAdminApproval)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _busy ? null : _continue,
                            child: Text(_busy ? 'Checking…' : 'Continue'),
                          ),
                        ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: _busy ? null : _signOut,
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessDetail extends StatelessWidget {
  const _AccessDetail({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: AdminColors.muted)),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _AccessProgress extends StatelessWidget {
  const _AccessProgress({required this.verified});
  final bool verified;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AdminColors.surfaceMuted,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        _step(Icons.check_rounded, 'Access request', true),
        _step(
          verified ? Icons.check_rounded : Icons.mail_outline_rounded,
          'Email verification',
          verified,
        ),
        _step(Icons.hourglass_top_rounded, 'Administrator approval', false),
      ],
    ),
  );

  Widget _step(IconData icon, String label, bool complete) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: complete ? AdminColors.success : AdminColors.muted,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: complete ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          complete ? 'Complete' : 'Pending',
          style: const TextStyle(fontSize: 12, color: AdminColors.muted),
        ),
      ],
    ),
  );
}

class _AppointmentSummaryCard extends StatelessWidget {
  const _AppointmentSummaryCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final int value;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: AdminColors.accentStrong, size: 25),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AdminColors.muted)),
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AdminColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.item,
    required this.repository,
    required this.selected,
    required this.onSelected,
    required this.onArchive,
  });
  final AppointmentModel item;
  final AdminPortalRepository repository;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final VoidCallback onArchive;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: _box,
    child: LayoutBuilder(
      builder: (context, box) {
        final student = Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                item.userId,
                style: const TextStyle(color: AdminColors.muted, fontSize: 12),
              ),
            ],
          ),
        );
        final schedule = Expanded(
          flex: 2,
          child: Text(
            '${_date(item.scheduledAt)}\n${item.scheduledTime.isEmpty ? 'Awaiting scheduling' : item.scheduledTime}',
            style: const TextStyle(fontSize: 12),
          ),
        );
        final department = Expanded(
          flex: 3,
          child: Text(
            '${item.department ?? 'Department not provided'}\n${item.course ?? 'Course not provided'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        );
        final action = TextButton.icon(
          onPressed: () => _showReviewDialog(context),
          icon: Icon(
            item.isFinalized
                ? Icons.visibility_outlined
                : Icons.rate_review_outlined,
            size: 17,
          ),
          label: Text(item.isFinalized ? 'View' : 'Review'),
        );
        final historyAction = item.isFinalized
            ? IconButton(
                tooltip: item.isArchived
                    ? 'Restore from history'
                    : 'Move to history',
                onPressed: onArchive,
                icon: Icon(
                  item.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                  size: 19,
                ),
              )
            : const SizedBox.shrink();
        if (box.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (onSelected != null)
                    Checkbox(
                      value: selected,
                      onChanged: (value) => onSelected!(value ?? false),
                    ),
                  student,
                  const SizedBox(width: 4),
                  historyAction,
                  action,
                ],
              ),
              const SizedBox(height: 10),
              Row(children: [schedule, department]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _Tag(
                  label: _formalLabel(item.status),
                  color: _statusColor(item.status),
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            if (onSelected != null)
              Checkbox(
                value: selected,
                onChanged: (value) => onSelected!(value ?? false),
              ),
            student,
            const SizedBox(width: 16),
            schedule,
            const SizedBox(width: 16),
            department,
            const SizedBox(width: 12),
            _Tag(
              label: _formalLabel(item.status),
              color: _statusColor(item.status),
            ),
            const SizedBox(width: 8),
            historyAction,
            action,
          ],
        );
      },
    ),
  );

  Future<void> _showReviewDialog(BuildContext context) async {
    final currentStatus = item.status.toLowerCase().trim();
    var action = currentStatus == 'confirmed'
        ? 'completed'
        : currentStatus == 'reschedule_required'
        ? 'reschedule_proposed'
        : 'confirmed';
    String reason = _appointmentReasons(action).first;
    final proposedTime = TextEditingController();
    DateTime? proposedDate;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
          contentPadding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.isFinalized ? 'Appointment details' : 'Review appointment',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 5),
              Text(
                item.fullName,
                style: const TextStyle(
                  color: AdminColors.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 660,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _AppointmentSectionHeader(
                    icon: Icons.person_outline,
                    title: 'Client information',
                  ),
                  const SizedBox(height: 12),
                  _AppointmentFieldGrid(
                    fields: [
                      _AppointmentFieldData('Email address', item.email),
                      _AppointmentFieldData(
                        'Contact number',
                        item.contactNumber,
                      ),
                      _AppointmentFieldData(
                        'Course and year',
                        '${item.course ?? 'Not provided'} • ${item.yearLevel ?? 'Not provided'}',
                      ),
                      _AppointmentFieldData(
                        'Preferred contact',
                        item.preferredContactMethod,
                      ),
                      _AppointmentFieldData(
                        'Previous counseling',
                        item.therapyBefore ?? 'Not provided',
                      ),
                    ],
                  ),
                  const Divider(height: 34),
                  const _AppointmentSectionHeader(
                    icon: Icons.event_note_outlined,
                    title: 'Request details',
                  ),
                  const SizedBox(height: 12),
                  _AppointmentField(
                    label: 'Primary concern',
                    value: item.concern,
                    prominent: true,
                  ),
                  const SizedBox(height: 12),
                  _AppointmentFieldGrid(
                    fields: [
                      _AppointmentFieldData(
                        'Requested schedule',
                        '${_date(item.scheduledAt)} • ${item.scheduledTime}',
                      ),
                      _AppointmentFieldData(
                        'Current status',
                        _formalLabel(item.status),
                      ),
                      if ((item.staffReply ?? '').isNotEmpty)
                        _AppointmentFieldData(
                          'Decision reason',
                          item.staffReply!,
                        ),
                      if (item.proposedScheduledAt != null)
                        _AppointmentFieldData(
                          'Proposed schedule',
                          '${_date(item.proposedScheduledAt)} • ${item.proposedScheduledTime ?? ''}',
                        ),
                    ],
                  ),
                  if (item.isFinalized) ...[
                    const SizedBox(height: 22),
                    const _AppointmentNotice(
                      icon: Icons.lock_outline,
                      message:
                          'This appointment has been finalized. The recorded decision is read-only.',
                    ),
                  ] else ...[
                    const Divider(height: 34),
                    const _AppointmentSectionHeader(
                      icon: Icons.fact_check_outlined,
                      title: 'PAACC decision',
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: action,
                      decoration: const InputDecoration(labelText: 'Action'),
                      items: currentStatus == 'confirmed'
                          ? const [
                              DropdownMenuItem(
                                value: 'completed',
                                child: Text('Mark session as completed'),
                              ),
                              DropdownMenuItem(
                                value: 'no_show',
                                child: Text('Mark as no-show'),
                              ),
                              DropdownMenuItem(
                                value: 'cancelled',
                                child: Text('Cancel appointment'),
                              ),
                            ]
                          : currentStatus == 'reschedule_required'
                          ? const [
                              DropdownMenuItem(
                                value: 'reschedule_proposed',
                                child: Text('Propose new schedule'),
                              ),
                            ]
                          : const [
                              DropdownMenuItem(
                                value: 'confirmed',
                                child: Text('Confirm appointment'),
                              ),
                              DropdownMenuItem(
                                value: 'reschedule_required',
                                child: Text('Schedule adjustment needed'),
                              ),
                              DropdownMenuItem(
                                value: 'reschedule_proposed',
                                child: Text('Propose new schedule'),
                              ),
                            ],
                      onChanged: (value) => setDialogState(() {
                        action = value!;
                        reason = _appointmentReasons(action).first;
                      }),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('reason-$action'),
                      initialValue: reason,
                      decoration: const InputDecoration(
                        labelText: 'Decision reason',
                      ),
                      items: _appointmentReasons(action)
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => reason = value!),
                    ),
                    if (action == 'reschedule_proposed') ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: dialogContext,
                                initialDate: DateTime.now().add(
                                  const Duration(days: 1),
                                ),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                              );
                              if (picked != null) {
                                setDialogState(() => proposedDate = picked);
                              }
                            },
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text(
                              proposedDate == null
                                  ? 'Select a date'
                                  : _date(proposedDate),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: proposedTime,
                              decoration: const InputDecoration(
                                labelText: 'Proposed time',
                                hintText: 'e.g. 2:00 PM',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(item.isFinalized ? 'Close' : 'Cancel'),
            ),
            if (!item.isFinalized)
              FilledButton(
                onPressed: () async {
                  if (action == 'reschedule_proposed' &&
                      (proposedDate == null ||
                          proposedTime.text.trim().isEmpty)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Enter a reply and all proposed time details.',
                        ),
                      ),
                    );
                    return;
                  }
                  try {
                    await repository.reviewAppointment(
                      appointmentId: item.id,
                      action: action,
                      reply: reason,
                      proposedScheduledAt: proposedDate,
                      proposedScheduledTime: proposedTime.text.trim(),
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Unable to update the appointment.'),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Send decision'),
              ),
          ],
        ),
      ),
    );
    proposedTime.dispose();
  }

  static List<String> _appointmentReasons(String action) => switch (action) {
    'confirmed' => const [
      'Schedule and counselor are available',
      'Appointment approved by PAACC',
    ],
    'reschedule_required' => const ['Schedule adjustment needed'],
    'reschedule_proposed' => const [
      'A different office time is available',
      'The requested time needs to be adjusted',
    ],
    'no_show' => const ['Student did not attend the confirmed appointment'],
    'cancelled' => const [
      'Student requested cancellation',
      'Schedule conflict',
      'Office closure',
      'Counselor unavailable',
      'Other legitimate reason',
    ],
    _ => const ['Counseling session completed'],
  };
}

class _AppointmentListHeader extends StatelessWidget {
  const _AppointmentListHeader();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 112, 8),
    child: Row(
      children: const [
        Expanded(flex: 3, child: Text('STUDENT', style: _listHeaderStyle)),
        SizedBox(width: 16),
        Expanded(flex: 2, child: Text('SCHEDULE', style: _listHeaderStyle)),
        SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: Text('DEPARTMENT / COURSE', style: _listHeaderStyle),
        ),
        SizedBox(width: 12),
        SizedBox(width: 108, child: Text('STATUS', style: _listHeaderStyle)),
      ],
    ),
  );
}

const _listHeaderStyle = TextStyle(
  color: AdminColors.muted,
  fontSize: 10,
  fontWeight: FontWeight.w900,
  letterSpacing: .8,
);

class _AppointmentSectionHeader extends StatelessWidget {
  const _AppointmentSectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 19, color: AdminColors.muted),
      const SizedBox(width: 9),
      Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _AppointmentFieldData {
  const _AppointmentFieldData(this.label, this.value);
  final String label;
  final String value;
}

class _AppointmentFieldGrid extends StatelessWidget {
  const _AppointmentFieldGrid({required this.fields});
  final List<_AppointmentFieldData> fields;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = box.maxWidth >= 560
          ? (box.maxWidth - 24) / 2
          : box.maxWidth;
      return Wrap(
        spacing: 24,
        runSpacing: 16,
        children: fields
            .map(
              (field) => SizedBox(
                width: width,
                child: _AppointmentField(
                  label: field.label,
                  value: field.value,
                ),
              ),
            )
            .toList(),
      );
    },
  );
}

class _AppointmentField extends StatelessWidget {
  const _AppointmentField({
    required this.label,
    required this.value,
    this.prominent = false,
  });

  final String label;
  final String value;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Container(
    padding: prominent ? const EdgeInsets.all(14) : EdgeInsets.zero,
    decoration: prominent
        ? BoxDecoration(
            color: AdminColors.canvas,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AdminColors.border),
          )
        : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AdminColors.muted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: .7,
          ),
        ),
        const SizedBox(height: 5),
        SelectableText(
          value.trim().isEmpty ? 'Not provided' : value,
          style: const TextStyle(
            color: AdminColors.ink,
            fontSize: 14,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _AppointmentNotice extends StatelessWidget {
  const _AppointmentNotice({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AdminColors.accentFaint,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: AdminColors.accentSoft),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _AvailabilityPage extends StatefulWidget {
  const _AvailabilityPage({required this.repository});
  final AdminPortalRepository repository;

  @override
  State<_AvailabilityPage> createState() => _AvailabilityPageState();
}

class _AvailabilityPageState extends State<_AvailabilityPage> {
  PaccAvailabilityModel? _draft;
  bool _saving = false;

  @override
  Widget build(BuildContext context) => _Page(
    title: 'PAACC Schedule & Availability',
    subtitle:
        'Publish office hours, walk-in availability, and counselor presence',
    child: StreamBuilder<PaccAvailabilityModel?>(
      stream: widget.repository.watchPaccAvailability(),
      builder: (context, snapshot) {
        final value =
            _draft ??
            snapshot.data ??
            const PaccAvailabilityModel(
              openDays: [1, 2, 3, 4, 5],
              opensAt: '08:00',
              closesAt: '17:00',
              presence: CounselorPresence.inOffice,
              acceptsWalkIns: true,
            );
        return Container(
          padding: const EdgeInsets.all(28),
          decoration: _box,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Working days',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: List.generate(7, (index) {
                  final day = index + 1;
                  const labels = [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun',
                  ];
                  return FilterChip(
                    label: Text(labels[index]),
                    selected: value.openDays.contains(day),
                    onSelected: (selected) => _update(
                      value,
                      openDays: selected
                          ? ([...value.openDays, day]..sort())
                          : value.openDays
                                .where((item) => item != day)
                                .toList(),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 14,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickTime(value, opening: true),
                    icon: const Icon(Icons.login_outlined),
                    label: Text('Opens ${value.opensAt}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickTime(value, opening: false),
                    icon: const Icon(Icons.logout_outlined),
                    label: Text('Closes ${value.closesAt}'),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              DropdownButtonFormField<CounselorPresence>(
                initialValue: value.presence,
                decoration: const InputDecoration(
                  labelText: 'Counselor status',
                  border: OutlineInputBorder(),
                ),
                items: CounselorPresence.values
                    .map(
                      (presence) => DropdownMenuItem(
                        value: presence,
                        child: Text(presence.label),
                      ),
                    )
                    .toList(),
                onChanged: (presence) {
                  if (presence != null) _update(value, presence: presence);
                },
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Accept walk-in visits'),
                subtitle: const Text(
                  'Users will see whether they may visit without an appointment.',
                ),
                value: value.acceptsWalkIns,
                onChanged: (enabled) => _update(value, acceptsWalkIns: enabled),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _save(value),
                  icon: const Icon(Icons.publish_outlined),
                  label: Text(
                    _saving ? 'Publishing...' : 'Publish availability',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  void _update(
    PaccAvailabilityModel current, {
    List<int>? openDays,
    String? opensAt,
    String? closesAt,
    CounselorPresence? presence,
    bool? acceptsWalkIns,
  }) {
    setState(
      () => _draft = PaccAvailabilityModel(
        openDays: openDays ?? current.openDays,
        opensAt: opensAt ?? current.opensAt,
        closesAt: closesAt ?? current.closesAt,
        presence: presence ?? current.presence,
        acceptsWalkIns: acceptsWalkIns ?? current.acceptsWalkIns,
        notice: current.notice,
        updatedAt: current.updatedAt,
      ),
    );
  }

  Future<void> _pickTime(
    PaccAvailabilityModel value, {
    required bool opening,
  }) async {
    final raw = opening ? value.opensAt : value.closesAt;
    final parts = raw.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (picked == null) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    _update(
      value,
      opensAt: opening ? formatted : null,
      closesAt: opening ? null : formatted,
    );
  }

  Future<void> _save(PaccAvailabilityModel value) async {
    setState(() => _saving = true);
    try {
      await widget.repository.savePaccAvailability(value);
      _draft = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PAACC availability published.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AssessmentsPage extends StatefulWidget {
  const _AssessmentsPage({required this.repository, required this.onBack});
  final AdminPortalRepository repository;
  final VoidCallback onBack;
  @override
  State<_AssessmentsPage> createState() => _AssessmentsPageState();
}

class _AssessmentsPageState extends State<_AssessmentsPage> {
  String typeFilter = 'All Types';
  String yearFilter = 'All Years';
  String statusFilter = 'All Statuses';
  String roleFilter = 'All Roles';
  String archiveFilter = 'Active';

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Assessment Results',
    subtitle: 'Review and archive assessment records from PAACC appointments',
    child: StreamBuilder<List<AdminAssessmentRecord>>(
      stream: widget.repository.watchAssessments(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const _AccessPanel();
        final all = snapshot.data ?? const <AdminAssessmentRecord>[];
        final years = {
          for (final item in all) '${item.createdAt.year}',
        }.toList()..sort((a, b) => b.compareTo(a));
        final statuses = {
          for (final item in all) item.status ?? 'Pending',
        }.toList()..sort();
        final roles = {for (final item in all) item.role ?? 'User'}.toList()
          ..sort();
        final types = [
          'All Types',
          ...{for (final item in all) item.type},
        ];
        final items = all
            .where(
              (item) =>
                  (archiveFilter == 'Archived'
                      ? item.isArchived
                      : !item.isArchived) &&
                  (typeFilter == 'All Types' || item.type == typeFilter) &&
                  (yearFilter == 'All Years' ||
                      '${item.createdAt.year}' == yearFilter) &&
                  (statusFilter == 'All Statuses' ||
                      (item.status ?? 'Pending') == statusFilter) &&
                  (roleFilter == 'All Roles' ||
                      (item.role ?? 'User') == roleFilter),
            )
            .toList();
        final active = all.where((item) => !item.isArchived).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to PAACC appointments'),
            ),
            const SizedBox(height: 20),
            _CompactSummaryStrip(
              values: {
                'Active': active.length,
                'With results': active
                    .where((a) => (a.status ?? '').isNotEmpty)
                    .length,
                'Pending': active.where((a) => (a.status ?? '').isEmpty).length,
                'Archived': all.where((a) => a.isArchived).length,
              },
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: _box,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filter records',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _FilterField(
                        label: 'Record state',
                        value: archiveFilter,
                        values: const ['Active', 'Archived'],
                        onChanged: (value) =>
                            setState(() => archiveFilter = value!),
                      ),
                      _FilterField(
                        label: 'Year',
                        value: yearFilter,
                        values: ['All Years', ...years],
                        onChanged: (value) =>
                            setState(() => yearFilter = value!),
                      ),
                      _FilterField(
                        label: 'Status',
                        value: statusFilter,
                        values: ['All Statuses', ...statuses],
                        onChanged: (value) =>
                            setState(() => statusFilter = value!),
                      ),
                      _FilterField(
                        label: 'Role',
                        value: roleFilter,
                        values: ['All Roles', ...roles],
                        onChanged: (value) =>
                            setState(() => roleFilter = value!),
                      ),
                      _FilterField(
                        label: 'Assessment',
                        value: typeFilter,
                        values: types,
                        onChanged: (value) =>
                            setState(() => typeFilter = value!),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              _EmptyPanel(
                message:
                    'No ${archiveFilter.toLowerCase()} assessments match these filters.',
              )
            else
              Container(
                decoration: _box,
                child: _ResponsiveTable(
                  columns: const [
                    'User reference',
                    'Year',
                    'Date',
                    'Status',
                    'Role',
                    'Assessment Type',
                    'Actions',
                  ],
                  rows: items
                      .map(
                        (assessment) => [
                          _UserReference(value: assessment.userId),
                          '${assessment.createdAt.year}',
                          _date(assessment.createdAt),
                          _Tag(
                            label: _formalLabel(assessment.status ?? 'Pending'),
                            color: (assessment.status ?? '').isEmpty
                                ? AdminColors.accentSoft
                                : AdminColors.surfaceMuted,
                          ),
                          _formalLabel(assessment.role ?? 'User'),
                          _formalLabel(assessment.type),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'View assessment results',
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AdminAssessmentDetailScreen(
                                      userId: assessment.userId,
                                      userLabel: assessment.userId,
                                      assessmentId: assessment.id,
                                      repository: AdminStatusRepository(),
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.visibility_outlined),
                              ),
                              IconButton(
                                tooltip: assessment.isArchived
                                    ? 'Restore assessment'
                                    : 'Archive assessment',
                                onPressed: () => _setArchived(assessment),
                                icon: Icon(
                                  assessment.isArchived
                                      ? Icons.unarchive_outlined
                                      : Icons.archive_outlined,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                      .toList(),
                ),
              ),
          ],
        );
      },
    ),
  );

  Future<void> _setArchived(AdminAssessmentRecord assessment) async {
    final archive = !assessment.isArchived;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${archive ? 'Archive' : 'Restore'} assessment?'),
        content: Text(
          archive
              ? 'This keeps the record securely stored but removes it from the active assessment list.'
              : 'This returns the record to the active assessment list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(archive ? 'Archive' : 'Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.setAssessmentArchived(assessment.id, archive);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              archive ? 'Assessment archived.' : 'Assessment restored.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update assessment: $error')),
        );
      }
    }
  }
}

class _CompactSummaryStrip extends StatelessWidget {
  const _CompactSummaryStrip({required this.values});
  final Map<String, int> values;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: _box,
    child: LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 620;
        return Wrap(
          children: values.entries
              .map(
                (entry) => SizedBox(
                  width: compact
                      ? box.maxWidth / 2
                      : box.maxWidth / values.length,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        right: BorderSide(color: AdminColors.border),
                        bottom: BorderSide(color: AdminColors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${entry.value}',
                          style: const TextStyle(
                            fontSize: 24,
                            height: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              color: AdminColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: values
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(_formalLabel(item), overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
    ),
  );
}

class _UserReference extends StatelessWidget {
  const _UserReference({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final abbreviated = value.length > 14
        ? '${value.substring(0, 6)}…${value.substring(value.length - 5)}'
        : value;
    return Tooltip(
      message: value,
      child: Text(
        abbreviated,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InquiriesPage extends StatefulWidget {
  const _InquiriesPage({required this.repository});
  final AdminPortalRepository repository;
  @override
  State<_InquiriesPage> createState() => _InquiriesPageState();
}

class _InquiriesPageState extends State<_InquiriesPage> {
  String status = 'All Status';
  String category = 'All Categories';

  void _openInquiry(AdminInquiryModel inquiry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _InquiryDetailScreen(
          inquiry: inquiry,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Inquiries',
    subtitle: 'Review, acknowledge, and resolve submitted inquiries.',
    child: StreamBuilder<List<AdminInquiryModel>>(
      stream: widget.repository.watchInquiries(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const _AccessPanel();
        final all = snapshot.data ?? const <AdminInquiryModel>[];
        final categories = [
          'All Categories',
          ...{for (final item in all) item.category},
        ];
        final items = all
            .where(
              (i) =>
                  (status == 'All Status' || i.status.label == status) &&
                  (category == 'All Categories' || i.category == category),
            )
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CompactSummaryStrip(
              values: {
                'Total': all.length,
                'Pending': all
                    .where((item) => item.status == InquiryStatus.pending)
                    .length,
                'In progress': all
                    .where((item) => item.status == InquiryStatus.inProgress)
                    .length,
                'Resolved': all
                    .where((item) => item.status == InquiryStatus.resolved)
                    .length,
              },
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: _box,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  _FilterField(
                    label: 'Status',
                    value: status,
                    values: const [
                      'All Status',
                      'Pending',
                      'In Progress',
                      'Resolved',
                    ],
                    onChanged: (value) => setState(() => status = value!),
                  ),
                  _FilterField(
                    label: 'Category',
                    value: category,
                    values: categories,
                    onChanged: (value) => setState(() => category = value!),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${items.length} ${items.length == 1 ? 'inquiry' : 'inquiries'} shown',
                      style: const TextStyle(
                        color: AdminColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _InquiryList(items: items, selected: null, onSelect: _openInquiry),
          ],
        );
      },
    ),
  );
}

class _InquiryList extends StatelessWidget {
  const _InquiryList({
    required this.items,
    required this.selected,
    required this.onSelect,
  });
  final List<AdminInquiryModel> items;
  final AdminInquiryModel? selected;
  final ValueChanged<AdminInquiryModel> onSelect;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyPanel(
        message: 'No inquiries match the selected filters.',
      );
    }
    return Container(
      decoration: _box,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 15, 16, 12),
            child: Text(
              'Inquiry queue',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          const Divider(height: 1),
          for (var index = 0; index < items.length; index++) ...[
            _InquiryQueueRow(
              item: items[index],
              selected: items[index].id == selected?.id,
              onTap: () => onSelect(items[index]),
            ),
            if (index < items.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _InquiryQueueRow extends StatelessWidget {
  const _InquiryQueueRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final AdminInquiryModel item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? AdminColors.accentFaint : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: _statusColor(item.status.storedValue),
                  shape: BoxShape.circle,
                  border: Border.all(color: AdminColors.border),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _date(item.createdAt),
                          style: const TextStyle(
                            color: AdminColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdminColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.message.trim().isEmpty
                          ? 'No message provided.'
                          : item.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _Tag(
                          label: item.status.label,
                          color: _statusColor(item.status.storedValue),
                        ),
                        _Tag(
                          label: item.category,
                          color: AdminColors.surfaceMuted,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _InquiryDetailScreen extends StatelessWidget {
  const _InquiryDetailScreen({required this.inquiry, required this.repository});

  final AdminInquiryModel inquiry;
  final AdminPortalRepository repository;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AdminColors.canvas,
    appBar: AppBar(
      toolbarHeight: 68,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Inquiry details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            'Review the submitted message, form responses, and case status.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AdminColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
    body: StreamBuilder<List<AdminInquiryModel>>(
      stream: repository.watchInquiries(),
      builder: (context, snapshot) {
        var current = inquiry;
        for (final item in snapshot.data ?? const <AdminInquiryModel>[]) {
          if (item.id == inquiry.id) {
            current = item;
            break;
          }
        }
        return SingleChildScrollView(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: _InquiryDetails(
                item: current,
                repository: repository,
                onUpdated: () {},
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _InquiryDetails extends StatelessWidget {
  const _InquiryDetails({
    required this.item,
    required this.repository,
    required this.onUpdated,
  });
  final AdminInquiryModel? item;
  final AdminPortalRepository repository;
  final VoidCallback onUpdated;
  @override
  Widget build(BuildContext context) {
    if (item == null) {
      return const _EmptyPanel(
        message: 'Select an inquiry to view its details.',
      );
    }
    return Container(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 18 : 22),
      decoration: _box,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Tag(
                label: item!.status.label,
                color: _statusColor(item!.status.storedValue),
              ),
              _Tag(label: item!.category, color: AdminColors.surfaceMuted),
              Text(
                _date(item!.createdAt),
                style: const TextStyle(
                  color: AdminColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            item!.subject,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 16),
          _InquirySender(item: item!),
          const Divider(height: 34),
          const _InquirySectionHeading(
            icon: Icons.chat_bubble_outline,
            title: 'Message',
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AdminColors.canvas,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AdminColors.border),
            ),
            child: SelectableText(
              item!.message.trim().isEmpty
                  ? 'No message was provided.'
                  : item!.message,
              style: const TextStyle(fontSize: 14, height: 1.55),
            ),
          ),
          if (item!.isFormSubmission) ...[
            const Divider(height: 34),
            const _InquirySectionHeading(
              icon: Icons.description_outlined,
              title: 'Form responses',
            ),
            const SizedBox(height: 12),
            _InquiryResponseGrid(responses: item!.formData),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => InquiryPdfService.preview(item!),
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('PDF preview'),
                ),
                FilledButton.icon(
                  onPressed: () => InquiryPdfService.download(item!),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download PDF'),
                ),
              ],
            ),
          ],
          const Divider(height: 34),
          const _InquirySectionHeading(
            icon: Icons.task_alt_outlined,
            title: 'Case actions',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: item!.isAcknowledged
                    ? null
                    : () => _acknowledge(context),
                icon: Icon(
                  item!.isAcknowledged
                      ? Icons.check_circle_outline
                      : Icons.notifications_active_outlined,
                ),
                label: Text(
                  item!.isAcknowledged
                      ? 'Receipt acknowledged'
                      : 'Acknowledge receipt',
                ),
              ),
              _InquiryStatusMenu(
                current: item!.status,
                onSelected: (next) => _updateStatus(context, next),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _acknowledge(BuildContext context) async {
    try {
      await repository.acknowledgeInquiry(item!.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt notification sent.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to acknowledge inquiry: $error')),
        );
      }
    }
  }

  Future<void> _updateStatus(BuildContext context, InquiryStatus next) async {
    if (next == item!.status) return;
    try {
      await repository.updateInquiryStatus(item!.id, next);
      onUpdated();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Inquiry marked ${next.label.toLowerCase()}.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update inquiry: $error')),
        );
      }
    }
  }
}

class _InquirySectionHeading extends StatelessWidget {
  const _InquirySectionHeading({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: AdminColors.muted),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _InquirySender extends StatelessWidget {
  const _InquirySender({required this.item});
  final AdminInquiryModel item;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AdminColors.accentFaint,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: AdminColors.accentSoft),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: AdminColors.accentSoft,
          child: Text(
            item.displayName.trim().isEmpty
                ? '?'
                : item.displayName.trim()[0].toUpperCase(),
            style: const TextStyle(
              color: AdminColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.displayName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              SelectableText(
                item.email,
                style: const TextStyle(color: AdminColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 5),
              Text(
                _formalLabel(item.role ?? 'User'),
                style: const TextStyle(color: AdminColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InquiryResponseGrid extends StatelessWidget {
  const _InquiryResponseGrid({required this.responses});
  final Map<String, dynamic> responses;

  @override
  Widget build(BuildContext context) {
    if (responses.isEmpty) {
      return const Text(
        'No structured responses were included.',
        style: TextStyle(color: AdminColors.muted, fontSize: 12),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth >= 620
            ? (box.maxWidth - 12) / 2
            : box.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: responses.entries
              .map(
                (response) => SizedBox(
                  width: width,
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AdminColors.canvas,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AdminColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formalLabel(response.key).toUpperCase(),
                          style: const TextStyle(
                            color: AdminColors.muted,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .6,
                          ),
                        ),
                        const SizedBox(height: 5),
                        SelectableText(
                          response.value?.toString().trim().isNotEmpty == true
                              ? response.value.toString()
                              : 'Not provided',
                          style: const TextStyle(fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _InquiryStatusMenu extends StatelessWidget {
  const _InquiryStatusMenu({required this.current, required this.onSelected});
  final InquiryStatus current;
  final ValueChanged<InquiryStatus> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<InquiryStatus>(
    tooltip: 'Change inquiry status',
    onSelected: onSelected,
    itemBuilder: (context) => InquiryStatus.values
        .map(
          (status) => PopupMenuItem(
            value: status,
            child: Row(
              children: [
                Icon(
                  status == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 17,
                ),
                const SizedBox(width: 9),
                Text(status.label),
              ],
            ),
          ),
        )
        .toList(),
    child: Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AdminColors.ink,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.swap_horiz, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            'Change status',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
        ],
      ),
    ),
  );
}

class _ProfilePage extends StatefulWidget {
  const _ProfilePage({required this.repository});
  final AdminPortalRepository repository;
  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  Map<String, dynamic> _profile = const {};
  bool _profileLoading = true;
  bool _savingProfile = false;
  String? _profileError;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _profileLoading = false);
      return;
    }
    try {
      final profile = await widget.repository.getOwnProfile(user.uid);
      if (!mounted) return;
      final firstName = profile?['firstName']?.toString().trim() ?? '';
      final lastName = profile?['lastName']?.toString().trim() ?? '';
      final storedName = profile?['name']?.toString().trim() ?? '';
      final resolvedName = [
        firstName,
        lastName,
      ].where((part) => part.isNotEmpty).join(' ');
      final phoneNumber = profile?['phone']?.toString().trim() ?? '';
      setState(() {
        _profile = profile ?? const {};
        name.text = resolvedName.isNotEmpty
            ? resolvedName
            : (storedName.isNotEmpty ? storedName : user.displayName ?? '');
        email.text = user.email ?? profile?['email']?.toString() ?? '';
        phone.text = phoneNumber;
        _profileLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profileLoading = false;
        _profileError = 'Profile details could not be loaded.';
        name.text = user.displayName ?? '';
        email.text = user.email ?? '';
      });
    }
  }

  String get _roleLabel {
    final role = _profile['approvedRole'] ?? _profile['accessRole'];
    return switch (role?.toString()) {
      'counselor' => 'Counselor',
      'portalStaff' || 'staff' => 'PAACC Staff',
      'admin' => 'Administrator',
      _ => switch (widget.repository.currentAccessRole) {
        AccessRole.counselor => 'Counselor',
        AccessRole.portalStaff => 'PAACC Staff',
        AccessRole.admin => 'Administrator',
        AccessRole.appUser => 'Portal User',
      },
    };
  }

  Future<void> _saveProfile(String userId) async {
    final fullName = name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (fullName.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid name before saving.')),
      );
      return;
    }
    final parts = fullName.split(' ');
    setState(() => _savingProfile = true);
    try {
      await widget.repository.updateOwnProfile(userId, {
        'name': fullName,
        'firstName': parts.first,
        'lastName': parts.skip(1).join(' '),
        'phone': phone.text.trim(),
        'updatedAt': DateTime.now(),
      });
      if (!mounted) return;
      setState(() {
        _profile = {
          ..._profile,
          'name': fullName,
          'firstName': parts.first,
          'lastName': parts.skip(1).join(' '),
          'phone': phone.text.trim(),
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile changes saved successfully.')),
      );
    } catch (error, stackTrace) {
      FirebaseErrorMessage.log(
        error,
        stackTrace,
        area: 'Profile update failed.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FirebaseErrorMessage.describe(
              error,
              fallback: 'Profile changes could not be saved. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _Page(
        title: 'Profile Settings',
        subtitle: 'Manage your account information and preferences',
        child: _AccessPanel(),
      );
    }
    return _Page(
      title: 'Profile Settings',
      subtitle: 'Manage your account information and preferences',
      child: LayoutBuilder(
        builder: (context, box) {
          final stacked = box.maxWidth < 900;
          final profileWidth = stacked ? box.maxWidth : 300.0;
          final formWidth = stacked ? box.maxWidth : box.maxWidth - 324;
          return Wrap(
            spacing: 24,
            runSpacing: 18,
            children: [
              Container(
                width: profileWidth,
                padding: const EdgeInsets.all(28),
                decoration: _box,
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 54,
                      backgroundColor: AdminColors.accentSoft,
                      child: Icon(
                        Icons.person_outline,
                        color: AdminColors.ink,
                        size: 54,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _profileLoading
                          ? 'Loading profile…'
                          : (name.text.isEmpty ? 'MindMate User' : name.text),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user.email ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AdminColors.muted),
                    ),
                    const SizedBox(height: 10),
                    Chip(label: Text(_roleLabel)),
                    if (_profileError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _profileError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AdminColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: formWidth,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: _box,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Personal information',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (!_profileLoading &&
                              _profile['employeeId'] != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Employee ID: ${_profile['employeeId']}',
                              style: const TextStyle(color: AdminColors.muted),
                            ),
                          ],
                          const SizedBox(height: 35),
                          LayoutBuilder(
                            builder: (context, fieldBox) {
                              final fieldWidth = fieldBox.maxWidth >= 780
                                  ? (fieldBox.maxWidth - 20) / 2
                                  : fieldBox.maxWidth;
                              return Wrap(
                                spacing: 30,
                                runSpacing: 22,
                                children: [
                                  SizedBox(
                                    width: fieldWidth,
                                    child: TextField(
                                      controller: name,
                                      decoration: const InputDecoration(
                                        labelText: 'Full name',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: fieldWidth,
                                    child: TextField(
                                      controller: email,
                                      readOnly: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Email',
                                        helperText:
                                            'Account email cannot be changed here.',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: fieldWidth,
                                    child: TextField(
                                      controller: phone,
                                      decoration: const InputDecoration(
                                        labelText: 'Phone number',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 28),
                          Center(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _yellow,
                              ),
                              onPressed: _savingProfile
                                  ? null
                                  : () => _saveProfile(user.uid),
                              child: _savingProfile
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Save Changes'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: _box,
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Change Password',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 22),
                          TextField(
                            enabled: false,
                            decoration: InputDecoration(
                              labelText: 'Available after admin authentication',
                              border: OutlineInputBorder(),
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
        },
      ),
    );
  }
}

class _ResponsiveTable extends StatelessWidget {
  const _ResponsiveTable({required this.columns, required this.rows});
  final List<String> columns;
  final List<List<Object>> rows;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: box.maxWidth),
        child: DataTable(
          columns: columns
              .map(
                (c) => DataColumn(
                  label: Text(
                    c,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              )
              .toList(),
          rows: rows
              .map(
                (row) => DataRow(
                  cells: row
                      .map(
                        (cell) =>
                            DataCell(cell is Widget ? cell : Text('$cell')),
                      )
                      .toList(),
                ),
              )
              .toList(),
        ),
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
    ),
  );
}

class _AccessPanel extends StatelessWidget {
  const _AccessPanel();
  @override
  Widget build(BuildContext context) => const _EmptyPanel(
    message:
        'Live admin data requires an authenticated Firebase user with an admin or counselor role.',
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(32),
    decoration: _box,
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AdminColors.muted),
    ),
  );
}

String _date(DateTime? date) => date == null
    ? '-'
    : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String _formalLabel(String value) {
  switch (value.toLowerCase().trim()) {
    case 'pending':
    case 'requested':
      return 'Pending review';
    case 'reschedule_required':
      return 'Schedule adjustment needed';
    case 'reschedule_proposed':
      return 'New schedule proposed';
    case 'declined':
      return 'Schedule adjustment needed';
    case 'no_show':
    case 'noshow':
      return 'No-show';
    default:
      return value
          .replaceAllMapped(
            RegExp(r'([a-z])([A-Z])'),
            (match) => '${match.group(1)} ${match.group(2)}',
          )
          .replaceAll('_', ' ')
          .split(' ')
          .where((word) => word.isNotEmpty)
          .map(
            (word) =>
                '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
          )
          .join(' ');
  }
}

Color _statusColor(String status) =>
    switch (status.toLowerCase().replaceAll(' ', '_')) {
      'resolved' || 'complete' => const Color(0xFF8ED77B),
      'in_progress' || 'confirmed' => _purple,
      _ => const Color(0xFFFFE8A7),
    };
final _box = BoxDecoration(
  color: AdminColors.surface,
  borderRadius: BorderRadius.circular(10),
  border: Border.all(color: AdminColors.border),
);
