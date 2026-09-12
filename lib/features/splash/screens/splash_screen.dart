import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/assessment_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../routes/route_names.dart';
import '../../authentication/auth_flow_routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
    _openNextScreen();
  }

  Future<void> _openNextScreen() async {
    await Future<void>.delayed(const Duration(milliseconds: 1900));
    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.hydrateCurrentUser();
    var routeName = RouteNames.login;
    if (userId != null && userId.isNotEmpty) {
      try {
        final userProvider = context.read<UserProvider>();
        final assessmentProvider = context.read<AssessmentProvider>();
        final profileLoaded = await userProvider.loadProfile(userId);
        if (!profileLoaded || userProvider.user == null) {
          throw StateError('Your profile could not be loaded.');
        }
        final authEmail = authProvider.currentUserEmail;
        if (authEmail != null &&
            authEmail.isNotEmpty &&
            !authEmail.endsWith('@mindmate.local') &&
            !authProvider.currentUserEmailVerified) {
          routeName = RouteNames.emailVerification;
          if (mounted) {
            Navigator.of(context).pushReplacementNamed(routeName);
          }
          return;
        }
        if (userProvider.user!.profileVersion >= 3 &&
            (!userProvider.user!.isProfileComplete ||
                !userProvider.user!.profileSetupCompleted)) {
          routeName = RouteNames.profileSetup;
          if (mounted) {
            Navigator.of(context).pushReplacementNamed(routeName);
          }
          return;
        }
        final completed = await assessmentProvider
            .ensureQuickAssessmentCompletion(userId);
        if (completed && userProvider.user?.quickAssessmentCompleted != true) {
          await userProvider.loadProfile(userId);
        }
        routeName = destinationAfterAuthentication(
          hasCompletedQuickAssessment: completed,
        );
      } catch (error) {
        debugPrint('Unable to verify assessment status on startup: $error');
        await authProvider.signOut();
      }
    }
    if (!mounted) return;

    Navigator.of(context).pushReplacementNamed(routeName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _SplashColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            _WarmGlow(alignment: Alignment.topLeft),
            _WarmGlow(alignment: Alignment.bottomRight),
            _SplashContent(),
          ],
        ),
      ),
    );
  }
}

class _SplashContent extends StatelessWidget {
  const _SplashContent();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_SplashScreenState>()!;
    final size = MediaQuery.sizeOf(context);
    final logoSize = size.width.clamp(0, 420) * 0.42;

    return Center(
      child: FadeTransition(
        opacity: state._fadeAnimation,
        child: SlideTransition(
          position: state._slideAnimation,
          child: ScaleTransition(
            scale: state._scaleAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: logoSize.clamp(132, 176).toDouble(),
                    height: logoSize.clamp(132, 176).toDouble(),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _SplashColors.shadow.withAlpha(24),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/APP LOGO/MindMate_LOGO.jpg',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'MindMate',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _SplashColors.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'A softer space to check in with yourself.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _SplashColors.mutedText,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
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

class _WarmGlow extends StatelessWidget {
  const _WarmGlow({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final isTop = alignment == Alignment.topLeft;

    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: Offset(isTop ? -80 : 70, isTop ? -70 : 80),
        child: Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (isTop ? _SplashColors.warm : _SplashColors.softGreen)
                .withAlpha(58),
          ),
        ),
      ),
    );
  }
}

class _SplashColors {
  const _SplashColors._();

  static const background = Color(0xFFFFFCF4);
  static const warm = Color(0xFFFFC944);
  static const softGreen = Color(0xFFBFE3D6);
  static const text = Color(0xFF17201D);
  static const mutedText = Color(0xFF66736F);
  static const shadow = Color(0xFF4B3A12);
}
