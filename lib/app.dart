import 'package:flutter/material.dart';

import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'routes/route_generator.dart';
import 'routes/route_names.dart';
import 'features/mind_aid/widgets/mind_aid_launcher_overlay.dart';

class MindMateApp extends StatelessWidget {
  const MindMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: MindAidNavigation.navigatorKey,
      navigatorObservers: [MindAidNavigation.observer],
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      initialRoute: RouteNames.splash,
      onGenerateRoute: RouteGenerator.generateRoute,
    );
  }
}
