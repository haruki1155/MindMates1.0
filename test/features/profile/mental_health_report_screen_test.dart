import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/profile/screens/mental_health_report_screen.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/insights_provider.dart';
import 'package:mind_mates/providers/report_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/insights_repository.dart';
import 'package:mind_mates/repositories/report_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('summary refresh also refreshes the same user insights', (
    tester,
  ) async {
    final reports = _RecordingReportProvider();
    final insights = _RecordingInsightsProvider();
    final users = UserProvider(UserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'a@example.com'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: users),
          ChangeNotifierProvider<ReportProvider>.value(value: reports),
          ChangeNotifierProvider<InsightsProvider>.value(value: insights),
        ],
        child: const MaterialApp(home: MentalHealthReportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(reports.refreshedUsers, ['user_1']);
    expect(insights.refreshedUsers, ['user_1']);
  });
}

class _RecordingReportProvider extends ReportProvider {
  _RecordingReportProvider() : super(ReportRepository());
  final refreshedUsers = <String>[];

  @override
  Future<void> refreshWeeklyReport(String userId) async {
    refreshedUsers.add(userId);
  }

  @override
  Future<Null> fetchLatestV4ResponseReview(String userId) async => null;

  @override
  Future<Null> fetchLatestV4FullAssessmentResult(String userId) async => null;
}

class _RecordingInsightsProvider extends InsightsProvider {
  _RecordingInsightsProvider() : super(InsightsRepository());
  final refreshedUsers = <String>[];

  @override
  Future<void> refreshLoadedContext(String userId) async {
    refreshedUsers.add(userId);
  }
}
