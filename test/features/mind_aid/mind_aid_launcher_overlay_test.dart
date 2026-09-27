import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/mind_aid/widgets/mind_aid_launcher_overlay.dart';
import 'package:mind_mates/providers/auth_provider.dart';
import 'package:mind_mates/repositories/auth_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:mind_mates/services/auth/auth_service.dart';
import 'package:provider/provider.dart';

class _SignedInAuthRepository extends AuthRepository {
  _SignedInAuthRepository() : super(AuthService());

  @override
  String? get currentUserId => 'student-test-user';
}

void main() {
  testWidgets('global launcher renders outside Navigator without assertions', (
    tester,
  ) async {
    MindAidNavigation.observer.currentRoute.value = RouteNames.splash;

    await tester.pumpWidget(_launcherApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('globalMindAidLauncher')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('globalMindAidLauncher')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('MindAid destination'), findsOneWidget);
    expect(find.byKey(const ValueKey('globalMindAidLauncher')), findsNothing);
  });

  testWidgets('global launcher can be dragged and remains inside the screen', (
    tester,
  ) async {
    MindAidNavigation.observer.currentRoute.value = RouteNames.splash;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_launcherApp());
    await tester.pump();

    final launcher = find.byKey(const ValueKey('globalMindAidLauncher'));
    final initialCenter = tester.getCenter(launcher);
    expect(tester.getRect(launcher).bottom, lessThanOrEqualTo(700));

    await tester.drag(launcher, const Offset(-180, -260));
    await tester.pump();

    final movedCenter = tester.getCenter(launcher);
    expect(movedCenter.dx, lessThan(initialCenter.dx));
    expect(movedCenter.dy, lessThan(initialCenter.dy));

    await tester.drag(launcher, const Offset(-1000, -1000));
    await tester.pump();

    final boundedRect = tester.getRect(launcher);
    expect(boundedRect.left, greaterThanOrEqualTo(12));
    expect(boundedRect.top, greaterThanOrEqualTo(12));
    await tester.drag(launcher, const Offset(1000, 1000));
    await tester.pump();
    expect(tester.getRect(launcher).bottom, lessThanOrEqualTo(700));
    expect(tester.takeException(), isNull);
  });
}

Widget _launcherApp() {
  return ChangeNotifierProvider(
    create: (_) => AuthProvider(_SignedInAuthRepository()),
    child: MaterialApp(
      navigatorKey: MindAidNavigation.navigatorKey,
      navigatorObservers: [MindAidNavigation.observer],
      initialRoute: RouteNames.home,
      routes: {
        RouteNames.home: (_) => const Scaffold(body: Text('Home')),
        RouteNames.mindAid: (_) =>
            const Scaffold(body: Text('MindAid destination')),
      },
      builder: (context, child) =>
          MindAidLauncherOverlay(child: child ?? const SizedBox.shrink()),
    ),
  );
}
