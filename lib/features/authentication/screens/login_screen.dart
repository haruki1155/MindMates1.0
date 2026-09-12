import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/assessment_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../routes/route_names.dart';
import '../auth_flow_routes.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _LoginColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            _SoftCircle(top: -84, left: -76, size: 198),
            _SoftCircle(top: 46, right: -82, size: 164, muted: true),
            _LoginBody(),
          ],
        ),
      ),
    );
  }
}

class _LoginBody extends StatefulWidget {
  const _LoginBody();

  @override
  State<_LoginBody> createState() => _LoginBodyState();
}

class _LoginBodyState extends State<_LoginBody> {
  final _identificationController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _identificationController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    FocusScope.of(context).unfocus();
    final schoolId = _identificationController.text.trim();
    final password = _passwordController.text;

    if (schoolId.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Enter your School ID and password.')),
        );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();
    final assessmentProvider = context.read<AssessmentProvider>();
    final userId = await authProvider.signIn(
      schoolId: schoolId,
      password: password,
    );

    if (!mounted) return;

    if (userId == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              authProvider.errorMessage ?? 'Unable to sign in. Try again.',
            ),
          ),
        );
      return;
    }

    final authEmail = authProvider.currentUserEmail;
    if (authEmail != null &&
        authEmail.isNotEmpty &&
        !authEmail.endsWith('@mindmate.local') &&
        !authProvider.currentUserEmailVerified) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(RouteNames.emailVerification, (route) => false);
      return;
    }

    try {
      final profileLoaded = await userProvider.loadProfile(userId);
      if (!mounted) return;
      if (!profileLoaded || userProvider.user == null) {
        throw StateError('Your profile could not be loaded.');
      }
      if (userProvider.user!.profileVersion >= 3 &&
          (!userProvider.user!.isProfileComplete ||
              !userProvider.user!.profileSetupCompleted)) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(RouteNames.profileSetup, (route) => false);
        return;
      }
      final hasCompletedQuickAssessment = await assessmentProvider
          .ensureQuickAssessmentCompletion(userId);
      if (hasCompletedQuickAssessment &&
          userProvider.user?.quickAssessmentCompleted != true) {
        await userProvider.loadProfile(userId);
      }

      if (!mounted) return;
      final destination = destinationAfterAuthentication(
        hasCompletedQuickAssessment: hasCompletedQuickAssessment,
      );
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(destination, (route) => false);
    } catch (error) {
      debugPrint('Unable to verify quick assessment completion: $error');
      await authProvider.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to verify your assessment status. Please try again.',
            ),
          ),
        );
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final authProvider = context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();
    final assessmentProvider = context.read<AssessmentProvider>();
    final userId = await authProvider.signInWithGoogle();
    if (!mounted || userId == null) {
      if (mounted && authProvider.errorMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(authProvider.errorMessage!)));
      }
      return;
    }
    userProvider.setUser(null);
    await userProvider.loadProfile(userId);
    if (!mounted) return;
    if (userProvider.user == null) {
      Navigator.of(context).pushReplacementNamed(RouteNames.signup);
      return;
    }
    final completed = await assessmentProvider.ensureQuickAssessmentCompletion(
      userId,
    );
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      destinationAfterAuthentication(hasCompletedQuickAssessment: completed),
      (route) => false,
    );
  }

  void _openForgotPassword() {
    Navigator.of(context).pushNamed(RouteNames.forgotPassword);
  }

  void _openSignup() {
    Navigator.of(context).pushNamed(RouteNames.signup);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compactHeight = size.height < 720;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            24,
            compactHeight ? 22 : 42,
            24,
            28 + MediaQuery.paddingOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 50),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _LogoHeader(),
                    SizedBox(height: compactHeight ? 18 : 24),
                    const _LoginIntro(),
                    const SizedBox(height: 18),
                    Consumer<AuthProvider>(
                      builder: (context, authProvider, _) {
                        return _LoginFormCard(
                          identificationController: _identificationController,
                          passwordController: _passwordController,
                          isLoading: authProvider.isLoading,
                          onForgotPassword: _openForgotPassword,
                          onCreateAccount: _openSignup,
                          onSignIn: _handleSignIn,
                          onGoogleSignIn: _handleGoogleSignIn,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LogoHeader extends StatelessWidget {
  const _LogoHeader();

  static const _logoPath = 'assets/images/APP LOGO/MindMate_LOGO.jpg';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 132,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _LoginColors.shadow.withAlpha(22),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipOval(child: Image.asset(_logoPath, fit: BoxFit.cover)),
    );
  }
}

class _LoginIntro extends StatelessWidget {
  const _LoginIntro();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text(
          'Welcome back',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _LoginColors.text,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Sign in to continue your MindMate check-ins.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _LoginColors.mutedText,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _LoginFormCard extends StatelessWidget {
  const _LoginFormCard({
    required this.identificationController,
    required this.passwordController,
    required this.isLoading,
    required this.onForgotPassword,
    required this.onCreateAccount,
    required this.onSignIn,
    required this.onGoogleSignIn,
  });

  final TextEditingController identificationController;
  final TextEditingController passwordController;
  final bool isLoading;
  final VoidCallback onForgotPassword;
  final VoidCallback onCreateAccount;
  final Future<void> Function() onSignIn;
  final Future<void> Function() onGoogleSignIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        color: _LoginColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _LoginColors.border),
        boxShadow: [
          BoxShadow(
            color: _LoginColors.shadow.withAlpha(18),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LoginField(
            controller: identificationController,
            label: 'School ID',
            assetIconPath: 'assets/images/Login/mail.png',
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          _LoginField(
            controller: passwordController,
            label: 'Password',
            icon: Icons.lock_outline_rounded,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!isLoading) onSignIn();
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onForgotPassword,
              style: TextButton.styleFrom(
                foregroundColor: _LoginColors.text,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Forgot password?'),
            ),
          ),
          const SizedBox(height: 14),
          _SignInButton(onPressed: isLoading ? null : onSignIn),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: isLoading ? null : onGoogleSignIn,
            icon: const Text(
              'G',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            label: const Text('Continue with Google'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: _LoginColors.text,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Flexible(
                child: Text(
                  'New to MindMate?',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _LoginColors.mutedText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: onCreateAccount,
                style: TextButton.styleFrom(
                  foregroundColor: _LoginColors.text,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: const Text('Create account'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.controller,
    required this.label,
    this.assetIconPath,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onSubmitted,
  }) : assert(assetIconPath != null || icon != null);

  final TextEditingController controller;
  final String label;
  final String? assetIconPath;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      style: const TextStyle(
        color: _LoginColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: _LoginColors.mutedText,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        floatingLabelStyle: const TextStyle(
          color: _LoginColors.text,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        prefixIcon: _LoginFieldIcon(assetIconPath: assetIconPath, icon: icon),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 52,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _LoginColors.fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _LoginColors.fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _LoginColors.primary, width: 1.4),
        ),
      ),
    );
  }
}

class _LoginFieldIcon extends StatelessWidget {
  const _LoginFieldIcon({this.assetIconPath, this.icon});

  final String? assetIconPath;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 14, 10, 14),
      child: assetIconPath == null
          ? Icon(icon, size: 20, color: _LoginColors.text)
          : Image.asset(
              assetIconPath!,
              width: 20,
              height: 20,
              fit: BoxFit.contain,
            ),
    );
  }
}

class _SignInButton extends StatelessWidget {
  const _SignInButton({required this.onPressed});

  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _LoginColors.primary,
          foregroundColor: _LoginColors.text,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (onPressed == null) ...[
              SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _LoginColors.text,
                ),
              ),
            ] else ...[
              Icon(Icons.lock_rounded, size: 18),
              SizedBox(width: 10),
              Text('Sign in'),
            ],
          ],
        ),
      ),
    );
  }
}

class _SoftCircle extends StatelessWidget {
  const _SoftCircle({
    this.top,
    this.left,
    this.right,
    required this.size,
    this.muted = false,
  });

  final double? top;
  final double? left;
  final double? right;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (muted ? _LoginColors.softGreen : _LoginColors.primary)
              .withAlpha(48),
        ),
      ),
    );
  }
}

class _LoginColors {
  const _LoginColors._();

  static const background = Color(0xFFFFFCF4);
  static const card = Color(0xFFFFFFFF);
  static const primary = Color(0xFFFFC944);
  static const softGreen = Color(0xFFBFE3D6);
  static const border = Color(0xFFF0E5C8);
  static const fieldBorder = Color(0xFFE7DDC9);
  static const text = Color(0xFF17201D);
  static const mutedText = Color(0xFF66736F);
  static const shadow = Color(0xFF4B3A12);
}
