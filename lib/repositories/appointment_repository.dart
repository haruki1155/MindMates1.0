import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_collections.dart';
import '../models/appointment_model.dart';
import '../services/firebase/firestore_service.dart';
import 'user_repository.dart';

class AppointmentRepository {
  AppointmentRepository({
    FirestoreService? firestoreService,
    UserRepository? userRepository,
  }) : _firestoreService = firestoreService ?? FirestoreService(),
       _userRepository = userRepository ?? UserRepository();

  final FirestoreService _firestoreService;
  final UserRepository _userRepository;

  Future<List<AppointmentModel>> fetchAppointments(String userId) {
    return _firestoreService
        .getDocuments(
          FirestoreCollections.appointments,
          whereEquals: {'userId': userId},
          orderBy: 'scheduledAt',
          descending: false,
        )
        .then(
          (docs) => docs
              .where((doc) => doc['userId']?.toString() == userId)
              .map(
                (doc) =>
                    AppointmentModel.fromJson(doc, id: doc['id']?.toString()),
              )
              .toList(growable: false),
        );
  }

  Future<AppointmentModel> createAppointment(
    AppointmentModel appointment,
  ) async {
    final profile = await _userRepository.fetchUserProfile(appointment.userId);
    final data = appointment.toJson()
      ..['populationRole'] = profile?.effectivePopulationRole?.storedValue ?? ''
      ..['department'] = profile?.department ?? appointment.department ?? ''
      ..['academicYearId'] = _academicYearFor(appointment.scheduledAt)
      ..['createdAt'] = FieldValue.serverTimestamp()
      ..['updatedAt'] = FieldValue.serverTimestamp();
    final id = await _firestoreService.createDocument(
      FirestoreCollections.appointments,
      data,
    );
    await _userRepository.recordActivity(
      appointment.userId,
      UserActivityType.appointmentRequested,
    );
    return appointment.copyWith(id: id, updatedAt: DateTime.now());
  }

  static String _academicYearFor(DateTime date) {
    final start = date.month >= 6 ? date.year : date.year - 1;
    return '$start-${start + 1}';
  }
}
