import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/home/models/home_dashboard_data.dart';
import 'package:mind_mates/routes/app_pages.dart';
import 'package:mind_mates/routes/route_names.dart';

void main() {
  test(
    'Dashboard exposes the supplied Better Sleep artwork and named route',
    () {
      final sleep = HomeDashboardData.mock().toolkitItems.singleWhere(
        (item) => item.title == 'Sleep Quality',
      );
      expect(sleep.subtitle, 'Track rest and patterns');
      expect(sleep.fullAssetPath, 'assets/images/INSIGHTS/better_sleep.png');
      expect(AppPages.routes[RouteNames.sleepQuality], isNotNull);
    },
  );
}
