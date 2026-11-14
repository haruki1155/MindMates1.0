import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_status_dashboard_screen.dart';
import 'package:mind_mates/models/admin_status_summary_model.dart';
import 'package:mind_mates/repositories/admin_status_repository.dart';

void main() {
  testWidgets('admin status dashboard shows user status categories', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminStatusDashboardScreen(
          repository: _FakeAdminStatusRepository([
            AdminStatusSummaryModel(
              userId: 'user_1',
              userLabel: 'Leo Molar',
              status: AdminUserStatus.severe,
              role: 'student',
              latestAssessmentStatus: 'High Concern',
              fullAssessmentStatus: 'High Concern',
              quickAssessmentStatus: 'watchful',
              activeDayCount: 2,
              assessmentCount: 1,
              mindAidMessageCount: 4,
              breathingSessionCount: 1,
              moodCheckInCount: 2,
              secretChatEngagementCount: 3,
              totalEngagementCount: 13,
              updatedAt: DateTime(2026, 7, 3),
            ),
            AdminStatusSummaryModel(
              userId: 'user_2',
              userLabel: 'Mia Reyes',
              status: AdminUserStatus.normal,
              role: 'faculty',
              latestAssessmentStatus: 'Stable',
              quickAssessmentStatus: 'stable',
              activeDayCount: 3,
              secretChatEngagementCount: 0,
              updatedAt: DateTime(2026, 7, 3),
            ),
          ]),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Admin User Status'), findsOneWidget);
    expect(find.text('Leo Molar'), findsOneWidget);
    expect(find.text('Mia Reyes'), findsOneWidget);
    expect(find.text('Prompt follow-up'), findsWidgets);
    expect(find.text('Routine monitoring'), findsWidgets);
    expect(find.text('Engagement'), findsOneWidget);
    expect(find.text('Forum'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
  });
}

class _FakeAdminStatusRepository extends AdminStatusRepository {
  _FakeAdminStatusRepository(this.statuses);

  final List<AdminStatusSummaryModel> statuses;

  @override
  Stream<List<AdminStatusSummaryModel>> watchUserStatuses({int limit = 200}) {
    return Stream.value(statuses);
  }
}
