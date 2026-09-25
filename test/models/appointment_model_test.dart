import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/appointment_model.dart';

void main() {
  test('round-trips complete appointment data', () {
    final scheduledAt = DateTime(2026, 4, 30, 11);
    final createdAt = DateTime(2026, 4, 1, 9);
    final model = AppointmentModel(
      id: 'appointment_1',
      userId: 'user_1',
      fullName: 'Molar, Leonardo M.',
      age: 20,
      address: 'Urdaneta City',
      contactNumber: '+63 912 345 6789',
      email: 'leo@example.com',
      facebook: 'facebook.com/leo',
      sex: 'Male',
      course: 'BS Information Technology',
      yearLevel: 'Fourth Year',
      preferredContactMethod: 'Email',
      therapyBefore: 'No',
      concern: 'I feel overwhelmed.',
      bestTime: 'Weekday mornings',
      scheduledAt: scheduledAt,
      scheduledTime: '11:00 AM',
      location: 'PACC Office',
      status: 'Upcoming',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final decoded = AppointmentModel.fromJson({
      ...model.toJson(),
      'id': model.id,
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(createdAt),
    });

    expect(decoded.id, model.id);
    expect(decoded.userId, model.userId);
    expect(decoded.fullName, model.fullName);
    expect(decoded.age, model.age);
    expect(decoded.concern, model.concern);
    expect(decoded.scheduledAt, scheduledAt);
    expect(decoded.scheduledTime, model.scheduledTime);
    expect(decoded.status, model.status);
  });
  _followUpContract();
}

void _followUpContract() {
  test(
    'defaults legacy follow-up fields and parses client-safe offer metadata',
    () {
      final legacy = AppointmentModel.fromJson({
        'id': 'legacy',
        'userId': 'user',
        'fullName': 'Student',
        'scheduledAt': Timestamp.now(),
        'createdAt': Timestamp.now(),
      });
      expect(legacy.followUpRecommended, isFalse);
      expect(legacy.followUpStatus, 'none');

      final offered = AppointmentModel.fromJson({
        'id': 'offered',
        'userId': 'user',
        'fullName': 'Student',
        'scheduledAt': Timestamp.now(),
        'createdAt': Timestamp.now(),
        'status': 'completed',
        'followUpRecommended': true,
        'followUpMessage': 'Please book when ready.',
        'followUpStatus': 'offered',
        'rescheduleReason': 'Office schedule adjustment',
      });
      expect(offered.followUpRecommended, isTrue);
      expect(offered.followUpMessage, 'Please book when ready.');
      expect(offered.followUpStatus, 'offered');
      expect(offered.rescheduleReason, 'Office schedule adjustment');
      expect(offered.hasAvailableFollowUpOffer, isTrue);
    },
  );
}
