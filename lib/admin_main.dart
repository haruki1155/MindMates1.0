import 'package:firebase_auth/firebase_auth.dart';
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
  const MindMateAdminApp({
    super.key,
    this.initialUri,
    this.auth,
    this.onReplaceLocation,
    this.authGateBuilder,
  });

  final Uri? initialUri;
  final FirebaseAuth? auth;
  final void Function(String url)? onReplaceLocation;
  final WidgetBuilder? authGateBuilder;

  static Uri resolveActionUri(String? routeName, Uri baseUri) {
    if (routeName != null && routeName.isNotEmpty) {
      final parsed = Uri.tryParse(routeName);
      if (parsed != null && AdminEmailActionScreen.supports(parsed)) {
        if (!parsed.hasAuthority &&
            baseUri.hasAuthority &&
            (baseUri.scheme == 'http' || baseUri.scheme == 'https')) {
          return baseUri.replace(
            path: parsed.path,
            query: parsed.hasQuery ? parsed.query : null,
          );
        }
        return parsed;
      }
    }
    return baseUri;
  }

  Widget _buildScreenForUri(BuildContext context, Uri uri) {
    if (AdminEmailActionScreen.supports(uri)) {
      return AdminEmailActionScreen(
        uri: uri,
        auth: auth,
        onReplaceLocation: onReplaceLocation,
      );
    }
    return authGateBuilder?.call(context) ?? const AdminAuthGate();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindMate',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.data,
      onGenerateInitialRoutes: (initialRoute) {
        final targetUri = initialUri ?? resolveActionUri(initialRoute, Uri.base);
        return [
          MaterialPageRoute<void>(
            settings: RouteSettings(name: initialRoute),
            builder: (context) => _buildScreenForUri(context, targetUri),
          ),
        ];
      },
      onGenerateRoute: (settings) {
        final targetUri = initialUri ?? resolveActionUri(settings.name, Uri.base);
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => _buildScreenForUri(context, targetUri),
        );
      },
    );
  }
}
