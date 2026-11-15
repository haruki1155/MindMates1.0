import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreSetOperation {
  const FirestoreSetOperation({
    required this.collection,
    required this.documentId,
    required this.data,
    this.merge = false,
  });

  final String collection;
  final String documentId;
  final Map<String, dynamic> data;
  final bool merge;
}

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore}) {
    _firestore = firestore;
  }

  FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  Future<String> createDocument(
    String collection,
    Map<String, dynamic> data,
  ) async {
    final document = await firestore.collection(collection).add(data);
    return document.id;
  }

  Future<void> setDocument(
    String collection,
    String documentId,
    Map<String, dynamic> data, {
    bool merge = false,
  }) {
    return firestore
        .collection(collection)
        .doc(documentId)
        .set(data, SetOptions(merge: merge));
  }

  Future<void> setDocumentsAtomically(
    List<FirestoreSetOperation> operations,
  ) async {
    final batch = firestore.batch();
    for (final operation in operations) {
      final reference = firestore
          .collection(operation.collection)
          .doc(operation.documentId);
      batch.set(reference, operation.data, SetOptions(merge: operation.merge));
    }
    await batch.commit();
  }

  Future<Map<String, dynamic>?> getDocument(
    String collection,
    String documentId,
  ) async {
    final snapshot = await firestore
        .collection(collection)
        .doc(documentId)
        .get();
    return snapshot.data();
  }

  Future<List<Map<String, dynamic>>> getDocuments(
    String collection, {
    Map<String, Object?> whereEquals = const {},
    String? orderBy,
    bool descending = true,
    int? limit,
  }) async {
    Query<Map<String, dynamic>> query = firestore.collection(collection);

    for (final entry in whereEquals.entries) {
      query = query.where(entry.key, isEqualTo: entry.value);
    }

    if (orderBy != null) {
      query = query.orderBy(orderBy, descending: descending);
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList(growable: false);
  }

  Stream<List<Map<String, dynamic>>> watchDocuments(
    String collection, {
    Map<String, Object?> whereEquals = const {},
    Map<String, Object?> whereArrayContains = const {},
    String? orderBy,
    bool descending = true,
    int? limit,
  }) {
    Query<Map<String, dynamic>> query = firestore.collection(collection);

    for (final entry in whereEquals.entries) {
      query = query.where(entry.key, isEqualTo: entry.value);
    }
    for (final entry in whereArrayContains.entries) {
      query = query.where(entry.key, arrayContains: entry.value);
    }

    if (orderBy != null) {
      query = query.orderBy(orderBy, descending: descending);
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList(growable: false),
    );
  }

  Stream<Map<String, dynamic>?> watchDocument(
    String collection,
    String documentId,
  ) {
    return firestore
        .collection(collection)
        .doc(documentId)
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  Future<void> updateDocument(
    String collection,
    String documentId,
    Map<String, dynamic> data,
  ) {
    return firestore.collection(collection).doc(documentId).update(data);
  }

  Future<void> deleteDocument(String collection, String documentId) {
    return firestore.collection(collection).doc(documentId).delete();
  }
}
