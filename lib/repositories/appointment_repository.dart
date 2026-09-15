import 'package:cloud_functions/cloud_functions.dart';

import '../database/firestore_collections.dart';
import '../models/appointment_model.dart';
import '../services/firebase/firestore_service.dart';
import '../services/firebase/firebase_callable_router.dart';

class AppointmentRepository {
  AppointmentRepository({
    FirestoreService? firestoreService,
    this._functions,
  }) : _firestoreService = firestoreService ?? FirestoreService();

  final FirestoreService _firestoreService;
  FirebaseFunctions? _functions;
  FirebaseFunctions get _functionClient =>
      _functions ??= FirebaseFunctions.instance;

  Stream<List<AppointmentModel>> watchAppointments(String userId) =>
      _firestoreService
          .watchDocuments(
            FirestoreCollections.appointments,
            whereEquals: {'userId': userId},
            orderBy: 'scheduledAt',
            descending: false,
          )
          .map(
            (docs) => docs
                .map(
                  (doc) =>
                      AppointmentModel.fromJson(doc, id: doc['id']?.toString()),
                )
                .toList(growable: false),
          );

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
    // Callable data does not share Firestore's DateTime/Timestamp mapper.
    // The backend contract intentionally uses epoch milliseconds so it can
    // validate time without relying on a client serializer.
    final payload = appointment.toJson()
      ..['scheduledAt'] = appointment.scheduledAt.millisecondsSinceEpoch
      ..remove('createdAt')
      ..remove('updatedAt');
    final result = await _functionClient
        .routedCallable('createAppointmentRequest')
        .call<Map<String, dynamic>>(payload);
    final id = result.data['appointmentId']?.toString() ?? '';
    if (id.isEmpty) throw StateError('Appointment request was not created.');
    return appointment.copyWith(
      id: id,
      status: AppointmentStatus.requested.value,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> cancelAppointment(String appointmentId, {String? reason}) =>
      _action(appointmentId, 'cancel', reason: reason);

  Future<void> acceptReschedule(String appointmentId) =>
      _action(appointmentId, 'accept_reschedule');

  Future<void> proposeReschedule(
    String appointmentId,
    DateTime scheduledAt,
    String scheduledTime,
  ) => _action(
    appointmentId,
    'propose_reschedule',
    proposedScheduledAt: scheduledAt.millisecondsSinceEpoch,
    proposedScheduledTime: scheduledTime,
  );

  Future<void> _action(
    String appointmentId,
    String action, {
    String? reason,
    int? proposedScheduledAt,
    String? proposedScheduledTime,
  }) => _functionClient.routedCallable('respondToAppointment').call({
    'appointmentId': appointmentId,
    'action': action,
    if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    'proposedScheduledAt': ?proposedScheduledAt,
    'proposedScheduledTime': ?proposedScheduledTime,
  });
}
