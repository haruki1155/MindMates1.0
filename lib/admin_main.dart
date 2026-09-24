import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/config/app_environment.dart';
import 'features/admin/screens/admin_auth_gate.dart';
import 'features/admin/screens/admin_email_action_screen.dart';
import 'features/admin/theme/admin_theme.dart';
import 'firebase_options_selector.dart';
import 'services/firebase/firebase_app_check_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_isProductionBuildOnVercel()) {
    runApp(const _AdminDeploymentConfigurationError());
    return;
  }
  final options = MindMatesFirebaseOptions.currentPlatform;
  AppEnvironmentConfig.validateFirebaseIdentity(
    projectId: options.projectId,
    callableRegion: AppEnvironmentConfig.functionsRegion,
  );
  await Firebase.initializeApp(options: options);
  try {
    await FirebaseAppCheckService.activate();
  } catch (error) {
    debugPrint('Firebase App Check activation failed: $error');
  }

  runApp(const MindMateAdminApp());
}

bool _isProductionBuildOnVercel() =>
    AppEnvironmentConfig.current == AppEnvironment.production &&
    Uri.base.host.toLowerCase().endsWith('.vercel.app') &&
    const String.fromEnvironment('VERCEL_DEPLOYMENT_ENV') != 'production';

class _AdminDeploymentConfigurationError extends StatelessWidget {
  const _AdminDeploymentConfigurationError();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MindMate Admin',
    debugShowCheckedModeBanner: false,
    theme: AdminTheme.data,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined, size: 48),
                SizedBox(height: 16),
                Text(
                  'Staging deployment is misconfigured',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 12),
                Text(
                  'This Vercel deployment was built for production. Redeploy it with APP_ENV=staging before signing in.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class MindMateAdminApp extends StatelessWidget {
  const MindMateAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindMate',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.data,
      home: AdminEmailActionScreen.supports(Uri.base)
          ? AdminEmailActionScreen(uri: Uri.base)
          : const AdminAuthGate(),
    );
  }
}
