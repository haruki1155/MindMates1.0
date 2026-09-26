import 'package:cloud_functions/cloud_functions.dart';

import '../database/firestore_collections.dart';
import '../models/pacc_availability_model.dart';
import '../services/firebase/firebase_callable_router.dart';
import '../services/firebase/firestore_service.dart';

typedef PaccAvailabilityWatchSource = Stream<Map<String, dynamic>?> Function();
typedef PaccAvailabilitySaveCallable = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> payload,
);

class PaccScheduleConflict {
  const PaccScheduleConflict({
    required this.appointmentId,
    required this.status,
    required this.timestamp,
    required this.reason,
  });

  final String appointmentId;
  final String status;
  final int timestamp;
  final String reason;

  factory PaccScheduleConflict.fromJson(Map<String, dynamic> json) =>
      PaccScheduleConflict(
        appointmentId: json['appointmentId']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
        reason: json['reason']?.toString() ?? '',
      );
}

class PaccAvailabilitySaveResult {
  const PaccAvailabilitySaveResult({
    required this.revision,
    required this.conflicts,
  });

  final int revision;
  final List<PaccScheduleConflict> conflicts;

  factory PaccAvailabilitySaveResult.fromJson(Map<String, dynamic> json) =>
      PaccAvailabilitySaveResult(
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        conflicts: (json['conflicts'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => PaccScheduleConflict.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
      );
}

class PaccAvailabilityRepository {
  factory PaccAvailabilityRepository({
    FirestoreService? firestoreService,
    PaccAvailabilityWatchSource? watchCurrentSource,
    PaccAvailabilitySaveCallable? saveCallable,
  }) => PaccAvailabilityRepository._(
    firestoreService: firestoreService,
    watchCurrentSource: watchCurrentSource,
    saveCallable: saveCallable,
  );

  PaccAvailabilityRepository._({
    FirestoreService? firestoreService,
    this._watchCurrentSource,
    this._saveCallable,
  }) : _firestore = firestoreService ?? FirestoreService();

  final FirestoreService _firestore;
  final PaccAvailabilityWatchSource? _watchCurrentSource;
  final PaccAvailabilitySaveCallable? _saveCallable;

  Stream<PaccAvailabilityModel?> watchCurrent() =>
      (_watchCurrentSource?.call() ??
          _firestore.watchDocument(FirestoreCollections.paccAvailability, 'current'))
      .map(
        (data) => data == null ? null : PaccAvailabilityModel.fromJson(data),
      );

  Future<PaccAvailabilitySaveResult> savePaccAvailability(
    PaccAvailabilityModel availability, {
    bool confirmConflicts = false,
  }) async {
    final result = await (_saveCallable ?? _callSavePaccAvailability)({
      'availability': availability.toJson(),
      'expectedRevision': availability.revision,
      'confirmConflicts': confirmConflicts,
    });
    return PaccAvailabilitySaveResult.fromJson(result);
  }

  Future<Map<String, dynamic>> _callSavePaccAvailability(
    Map<String, dynamic> payload,
  ) async {
    final response = await FirebaseFunctions.instance
        .routedCallable('savePaccAvailability')
        .call<Map<String, dynamic>>(payload);
    return response.data;
  }
}
