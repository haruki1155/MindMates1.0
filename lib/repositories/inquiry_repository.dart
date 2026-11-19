import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../database/firestore_collections.dart';
import '../models/student_inquiry_model.dart';
import '../services/firebase/firestore_service.dart';

class InquiryRepository {
  InquiryRepository({
    FirestoreService? firestoreService,
    this.currentUserIdProvider,
  }) : _firestore = firestoreService ?? FirestoreService();

  final FirestoreService _firestore;
  final String? Function()? currentUserIdProvider;

  String? get currentUserId =>
      (currentUserIdProvider ?? _defaultCurrentUserId)();

  static String? _defaultCurrentUserId() {
    if (Firebase.apps.isEmpty) return null;
    return FirebaseAuth.instance.currentUser?.uid;
  }

  Future<String> submitForm({
    required String formType,
    required String subject,
    required String email,
    required String name,
    required Map<String, dynamic> formData,
    String message = 'Completed service form submitted for review.',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Please sign in before submitting this form.');
    }
    return _firestore.createDocument(FirestoreCollections.inquiries, {
      'userId': user.uid,
      'subject': subject,
      'message': message,
      'category': 'Service Form',
      'email': email.trim(),
      'name': name.trim().isEmpty ? (user.displayName ?? '') : name.trim(),
      'role': 'User',
      'formType': formType,
      'formData': formData,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Watches inquiries submitted by [userId], filtered at query time by `userId`
  /// to satisfy Firestore's `isOwner(resource.data.userId)` rule and sorted
  /// client-side newest first without needing a composite index.
  Stream<List<StudentInquiryRecord>> watchMyInquiries(String userId) {
    final trimmed = userId.trim();
    final active = currentUserId;
    if (trimmed.isEmpty || (active != null && active != trimmed)) {
      return Stream.error(
        StateError('Please sign in to view your submitted inquiries.'),
      );
    }
    return _firestore
        .watchDocuments(
          FirestoreCollections.inquiries,
          whereEquals: {'userId': trimmed},
        )
        .map((items) {
          final records = items
              .map(
                (item) => StudentInquiryRecord.fromJson(
                  item,
                  id: item['id']?.toString(),
                ),
              )
              .where((record) => record.userId == trimmed)
              .toList(growable: false);
          return records.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
  }

  /// Watches a single inquiry owned by [userId]. Relies on Firestore security
  /// rules (`allow read: if canReadInquiry(resource.data)`) and defensively
  /// checks ownership so arbitrary notification `inquiryId`s cannot expose
  /// another student's inquiry.
  Stream<StudentInquiryRecord?> watchMyInquiry(
    String inquiryId, {
    required String userId,
  }) {
    final id = inquiryId.trim();
    final uid = userId.trim();
    final active = currentUserId;
    if (id.isEmpty || uid.isEmpty || (active != null && active != uid)) {
      return Stream.error(
        StateError('Please sign in as the inquiry owner to view this inquiry.'),
      );
    }
    return _firestore.watchDocument(FirestoreCollections.inquiries, id).map((
      data,
    ) {
      if (data == null) return null;
      final record = StudentInquiryRecord.fromJson(data, id: id);
      if (record.userId != uid) {
        throw StateError('You do not have permission to view this inquiry.');
      }
      return record;
    });
  }

  /// Watches authored PACC counselor/admin replies for an inquiry owned by the
  /// signed-in student. Firestore rules enforce `canReadInquiry` on the parent.
  Stream<List<StudentInquiryReply>> watchMyInquiryReplies(String inquiryId) {
    final id = inquiryId.trim();
    if (id.isEmpty) {
      return Stream.value(const <StudentInquiryReply>[]);
    }
    return _firestore
        .watchDocuments(
          '${FirestoreCollections.inquiries}/$id/replies',
          orderBy: 'createdAt',
          descending: false,
        )
        .map(
          (items) => items
              .map(
                (item) => StudentInquiryReply.fromJson(
                  item,
                  id: item['id']?.toString() ?? '',
                ),
              )
              .toList(growable: false),
        );
  }
}
