import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/widgets/staff_queue_refresh_button.dart';
import 'package:mind_mates/repositories/admin_portal_repository.dart';

class _RefreshRepo extends AdminPortalRepository {
  _RefreshRepo({this.fail = false});
  final bool fail;
  int calls = 0;

  @override
  Future<int> refreshPortalAppointmentQueue() async {
    calls++;
    if (fail) throw StateError('Unavailable staging callable');
    return 3;
  }
}

void main() {
  testWidgets('schedule refresh reports result and invokes the queue once',
      (tester) async {
    final repo = _RefreshRepo();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffQueueRefreshButton(repository: repo),
      ),
    ));
    await tester.tap(find.text('Refresh schedules'));
    await tester.pump();
    expect(repo.calls, 1);
    expect(find.textContaining('Refresh completed for 3 source appointments'),
        findsOneWidget);
  });

  testWidgets('schedule refresh displays actionable failure instead of fake data',
      (tester) async {
    final repo = _RefreshRepo(fail: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffQueueRefreshButton(repository: repo),
      ),
    ));
    await tester.tap(find.text('Refresh schedules'));
    await tester.pump();
    expect(repo.calls, 1);
    expect(find.textContaining('Could not refresh staff schedules'),
        findsOneWidget);
  });
}
