import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/appointment_model.dart';

void main() {
  final time = DateTime.now().add(const Duration(days: 5));
  Map<String, dynamic> record() => {'id': 'agreement', 'userId': 'student', 'scheduledAt': time, 'scheduledTime': '10:00 AM', 'createdAt': time.subtract(const Duration(days: 2)), 'status': 'confirmed', 'scheduleRevision': 4, 'proposalRevision': 7, 'proposalStatus': 'pending', 'proposedBy': 'counselor', 'proposedScheduledAt': time.add(const Duration(hours: 1)), 'proposedScheduledTime': '11:00 AM'};
  test('proposal refresh preserves current reservation, both revisions and recipient', () {
    final item = AppointmentModel.fromJson(record());
    expect(item.hasPendingScheduleChange, isTrue);
    expect(item.pendingScheduleLabel, 'Your confirmation needed');
    final restored = AppointmentModel.fromJson(item.toJson(), id: item.id);
    expect(restored.scheduledAt, time);
    expect(restored.status, 'confirmed');
    expect(restored.proposalRevision, 7);
    expect(restored.scheduleRevision, 4);
    expect(restored.proposedScheduledTime, '11:00 AM');
  });
  test('legacy missing proposal revision safely reads as zero', () {
    final data = record()..remove('proposalRevision');
    expect(AppointmentModel.fromJson(data).proposalRevision, 0);
  });
  test('past, terminal and archived records do not advertise actionable proposals', () {
    expect(AppointmentModel.fromJson({...record(), 'scheduledAt': DateTime.now().subtract(const Duration(days: 1))}).hasPendingScheduleChange, isFalse);
    expect(AppointmentModel.fromJson({...record(), 'status': 'cancelled'}).hasPendingScheduleChange, isFalse);
    expect(AppointmentModel.fromJson({...record(), 'archivedAt': time}).hasPendingScheduleChange, isFalse);
  });
  test('unknown proposal actor does not invent a confirmation action', () {
    expect(AppointmentModel.fromJson({...record(), 'proposedBy': 'unknown'}).hasPendingScheduleChange, isFalse);
  });
}
