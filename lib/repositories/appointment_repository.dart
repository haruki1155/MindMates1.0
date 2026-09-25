import 'package:cloud_functions/cloud_functions.dart';

import '../database/firestore_collections.dart';
import '../models/appointment_model.dart';
import '../services/firebase/firestore_service.dart';
import '../services/firebase/firebase_callable_router.dart';

class AppointmentRepository {
  AppointmentRepository({FirestoreService? firestoreService, this._functions})
    : _firestoreService = firestoreService ?? FirestoreService();

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

  Future<List<AppointmentSlot>> getAvailableSlots(DateTime date) async {
    final day =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await _functionClient
        .routedCallable('getAvailableAppointmentSlots')
        .call<Map<String, dynamic>>({'date': day});
    final slots = result.data['slots'];
    if (slots is! List) return const [];
    return slots
        .whereType<Map>()
        .map(
          (slot) => AppointmentSlot.fromJson(Map<String, dynamic>.from(slot)),
        )
        .toList(growable: false);
  }

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
    if ((appointment.parentAppointmentId ?? '').trim().isNotEmpty) {
      payload['parentAppointmentId'] = appointment.parentAppointmentId!.trim();
    }
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

  Future<void> acceptReschedule(String appointmentId) =>
      _functionClient.routedCallable('respondToAppointment').call({
        'appointmentId': appointmentId,
        'action': 'accept_reschedule',
      });

}

class AppointmentSlot {
  const AppointmentSlot({required this.start, required this.label});
  final DateTime start;
  final String label;

  factory AppointmentSlot.fromJson(Map<String, dynamic> json) {
    final start = json['start'];
    return AppointmentSlot(
      start: DateTime.fromMillisecondsSinceEpoch(
        start is num ? start.toInt() : int.parse('$start'),
      ),
      label: json['label']?.toString() ?? '',
    );
  }
}
