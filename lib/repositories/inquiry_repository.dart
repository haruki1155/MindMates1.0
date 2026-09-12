import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../database/firestore_collections.dart';
import '../services/firebase/firestore_service.dart';

class InquiryRepository {
  InquiryRepository({FirestoreService? firestoreService})
    : _firestore = firestoreService ?? FirestoreService();

  final FirestoreService _firestore;

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
}
