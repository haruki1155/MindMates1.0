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
