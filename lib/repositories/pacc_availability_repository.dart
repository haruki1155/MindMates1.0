import '../database/firestore_collections.dart';
import '../models/pacc_availability_model.dart';
import '../services/firebase/firestore_service.dart';

class PaccAvailabilityRepository {
  PaccAvailabilityRepository({FirestoreService? firestoreService})
    : _firestore = firestoreService ?? FirestoreService();

  final FirestoreService _firestore;

  Stream<PaccAvailabilityModel?> watchCurrent() => _firestore
      .watchDocument(FirestoreCollections.paccAvailability, 'current')
      .map(
        (data) => data == null ? null : PaccAvailabilityModel.fromJson(data),
      );
}
