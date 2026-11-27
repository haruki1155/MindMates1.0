import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../database/firestore_collections.dart';
import '../models/student_inquiry_model.dart';
import '../models/testing_service_schedule.dart';
import '../services/firebase/firebase_callable_router.dart';
import '../services/firebase/firestore_service.dart';

typedef InquiryCallableInvoker =
    Future<Object?> Function(String name, Map<String, Object?> data);

class InquiryRepository {
  InquiryRepository({
    FirestoreService? firestoreService,
    this.currentUserIdProvider,
    InquiryCallableInvoker? callableInvoker,
  }) : _firestore = firestoreService ?? FirestoreService(),
       // ignore: prefer_initializing_formals
       _callableInvoker = callableInvoker;

  final FirestoreService _firestore;
  final String? Function()? currentUserIdProvider;
  final InquiryCallableInvoker? _callableInvoker;

  Future<Object?> _callCallable(String name, Map<String, Object?> data) {
    final invoker = _callableInvoker;
    if (invoker != null) return invoker(name, data);
    return FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).routedCallable(name).call<Object?>(data).then((result) => result.data);
  }

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

  /// Uploads a supporting document for Testing Service to private Storage via
  /// Cloud Functions and returns its verified reference.
  Future<TestingServiceDocumentRef> uploadTestingServiceDocument({
    required PendingTestingDocument file,
  }) async {
    final result = await _callCallable('uploadTestingServiceDocument', {
      'kind': file.kind.wireValue,
      'name': file.name,
      'contentType': file.contentType,
      'size': file.size,
      'dataBase64': base64Encode(file.bytes),
    });
    final data = result is Map ? Map<String, dynamic>.from(result) : const {};
    final ref = TestingServiceDocumentRef.tryFromJson(data['document']);
    if (ref == null) {
      throw StateError('Document upload did not return a valid reference.');
    }
    return ref;
  }

  /// Downloads a Testing Service document for previewing by the inquiry owner.
  Future<({String name, String contentType, Uint8List bytes})>
  downloadTestingServiceDocument({
    required String inquiryId,
    required String path,
  }) async {
    final result = await _callCallable('downloadTestingServiceDocument', {
      'inquiryId': inquiryId,
      'path': path,
    });
    final data = result is Map ? Map<String, dynamic>.from(result) : const {};
    final encoded = data['dataBase64']?.toString() ?? '';
    if (encoded.isEmpty) {
      throw StateError('Downloaded document was empty.');
    }
    return (
      name: data['name']?.toString() ?? 'document',
      contentType:
          data['contentType']?.toString() ?? 'application/octet-stream',
      bytes: base64Decode(encoded),
    );
  }

  /// Submits a Testing Service inquiry via trusted Cloud Functions so server
  /// role eligibility, uploaded documents, mobile number, and agreements cannot
  /// be bypassed.
  Future<String> submitTestingServiceInquiry({
    required bool isStudentForOjt,
    required bool endorsementLetterConfirmed,
    required bool officialReceiptConfirmed,
    required String mobileNumber,
    required TestingServiceDocumentRef endorsementLetter,
    required TestingServiceDocumentRef officialReceipt,
    List<TestingServiceDocumentRef> admissionRequirements = const [],
    DateTime? preferredScheduleAt,
    required PersonalDataSheetInput personalDataSheet,
    bool personalDataSheetConfirmed = true,
    bool informedConsentConfirmed = true,
    String message = '',
    String? preferredScheduleNote,
    String? requestId,
  }) async {
    final result = await _callCallable('submitTestingServiceInquiry', {
      'isStudentForOjt': isStudentForOjt,
      'endorsementLetterConfirmed': endorsementLetterConfirmed,
      'officialReceiptConfirmed': officialReceiptConfirmed,
      'mobileNumber': mobileNumber,
      'endorsementLetter': endorsementLetter.toJson(),
      'officialReceipt': officialReceipt.toJson(),
      'admissionRequirements': admissionRequirements
          .map((doc) => doc.toJson())
          .toList(growable: false),
      if (preferredScheduleAt != null)
        'preferredScheduleAtMillis': preferredScheduleAt.millisecondsSinceEpoch,
      'personalDataSheet': personalDataSheet.toJson(),
      'personalDataSheetConfirmed': personalDataSheetConfirmed,
      'informedConsentConfirmed': informedConsentConfirmed,
      if (message.trim().isNotEmpty) 'message': message.trim(),
      if (preferredScheduleNote != null &&
          preferredScheduleNote.trim().isNotEmpty)
        'preferredScheduleNote': preferredScheduleNote.trim(),
      'requestId': ?requestId,
    });
    final data = result is Map ? result : const {};
    final inquiryId = data['inquiryId']?.toString().trim() ?? '';
    if (inquiryId.isEmpty) {
      throw StateError('Testing Service inquiry did not return an ID.');
    }
    return inquiryId;
  }

  /// Accepts a proposed Testing Service schedule, locking it as confirmed.
  Future<void> acceptTestingServiceSchedule(
    String inquiryId, {
    int? expectedScheduleRevision,
  }) => _callCallable('acceptTestingServiceSchedule', {
    'inquiryId': inquiryId,
    'expectedScheduleRevision': ?expectedScheduleRevision,
  });

  /// Requests the single allowed reschedule for a proposed Testing Service
  /// schedule. Server-enforced atomically so at most one reschedule is allowed.
  Future<void> requestTestingServiceReschedule(
    String inquiryId, {
    required String reason,
    int? expectedScheduleRevision,
  }) => _callCallable('requestTestingServiceReschedule', {
    'inquiryId': inquiryId,
    'reason': reason.trim(),
    'expectedScheduleRevision': ?expectedScheduleRevision,
  });
}
