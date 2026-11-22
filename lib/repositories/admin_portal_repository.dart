// ignore_for_file: prefer_initializing_formals
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../database/firestore_collections.dart';
import '../models/academic_import_models.dart';
import '../models/admin_inquiry_model.dart';
import '../models/admin_activity_analytics_model.dart';
import '../models/admin_mind_aid_analytics_model.dart';
import '../models/appointment_model.dart';
import '../features/admin/domain/session_evidence.dart';
import '../models/appointment_queue_item.dart';
import '../models/app_notification_model.dart';
import '../models/user_model.dart';
import '../models/profile_roles.dart';
import '../models/case_remarks_model.dart';
import '../models/student_case_history_model.dart';
import '../models/pacc_availability_model.dart';
import 'appointment_repository.dart';
import 'pacc_availability_repository.dart';
import '../features/admin/domain/admin_activity_log_presentation.dart';
import '../features/admin/domain/admin_management_models.dart';
import '../features/admin/domain/appointment_approvals.dart';
import '../features/admin/domain/backup_export.dart';
import '../features/admin/domain/backup_job.dart';
import '../features/admin/domain/inquiry_scope.dart';
import '../features/admin/domain/inquiry_sla.dart';
import '../features/admin/domain/report_generation_models.dart';
import '../services/firebase/firebase_callable_router.dart';
import '../services/firebase/firestore_service.dart';

class AdminAssessmentRecord {
  const AdminAssessmentRecord({
    required this.id,
    required this.userId,
    required this.type,
    required this.createdAt,
    this.score,
    this.status,
    this.profileStatus,
    this.role,
    this.instrumentVersion,
    this.verificationStatus,
    this.archivedAt,
  });

  final String id;
  final String userId;
  final String type;
  final DateTime createdAt;
  final num? score;
  final String? status;
  final String? profileStatus;
  final String? role;
  final String? instrumentVersion;
  final String? verificationStatus;
  final DateTime? archivedAt;
  bool get isArchived => archivedAt != null;
  bool get isQuickAssessment {
    final normalizedType = type.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z]'),
      '',
    );
    return normalizedType == 'quick' ||
        normalizedType == 'quickassessment' ||
        id.toLowerCase().startsWith('quick_');
  }

  bool get isMainAssessment => !isQuickAssessment;
  String get displayStatus {
    final canonical = profileStatus?.trim() ?? '';
    if (canonical.isNotEmpty) return canonical;
    final stored = status?.trim() ?? '';
    return stored.isNotEmpty ? stored : 'Result unavailable';
  }

  factory AdminAssessmentRecord.fromJson(Map<String, dynamic> data) {
    final result = data['result'] is Map
        ? Map<String, dynamic>.from(data['result'] as Map)
        : const <String, dynamic>{};
    final instrument = data['instrument'] is Map
        ? Map<String, dynamic>.from(data['instrument'] as Map)
        : const <String, dynamic>{};
    final profileStatus = _text(result['profileStatus']);
    final status =
        profileStatus ??
        _text(data['overallLevel']) ??
        _text(data['status']) ??
        _text(data['wellBeingStatus']) ??
        _text(data['responsePatternCode']);
    return AdminAssessmentRecord(
      id: data['id']?.toString() ?? '',
      userId: data['userId']?.toString() ?? '',
      type:
          _text(data['assessmentKind']) ??
          _text(data['type']) ??
          'Assessment',
      createdAt: _date(data['createdAt']),
      score: data['score'] is num
          ? data['score'] as num
          : num.tryParse('${data['score']}'),
      status: status,
      profileStatus: profileStatus,
      role: _text(data['populationRole']) ?? _text(data['role']),
      instrumentVersion:
          _text(instrument['version']) ?? _text(data['questionSetVersion']),
      verificationStatus: _text(data['verificationStatus']),
      archivedAt: data['archivedAt'] == null ? null : _date(data['archivedAt']),
    );
  }

  static DateTime _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse('$value') ?? DateTime.now();
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class AdminRoleCorrectionRequest {
  const AdminRoleCorrectionRequest({
    required this.id,
    required this.userId,
    required this.currentRole,
    required this.requestedRole,
    required this.reason,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String currentRole;
  final String requestedRole;
  final String reason;
  final String status;
  final DateTime createdAt;

  factory AdminRoleCorrectionRequest.fromJson(Map<String, dynamic> data) =>
      AdminRoleCorrectionRequest(
        id: data['id']?.toString() ?? '',
        userId: data['userId']?.toString() ?? '',
        currentRole: data['currentRole']?.toString() ?? '',
        requestedRole: data['requestedRole']?.toString() ?? '',
        reason: data['reason']?.toString() ?? '',
        status: data['status']?.toString() ?? 'pending',
        createdAt: AdminAssessmentRecord._date(data['createdAt']),
      );
}

class StaffAccessRequestSubmission {
  const StaffAccessRequestSubmission({
    required this.verificationSent,
    this.requestId,
    this.reference,
  });

  final bool verificationSent;
  final String? requestId;
  final String? reference;
}

enum PortalAccessState {
  granted,
  emailVerificationRequired,
  pendingAdminApproval,
  moreInformationRequired,
  suspended,
  disabled,
  rejected,
  accountNotFound,
  noPortalRole,
}

class PortalAccessEvaluation {
  const PortalAccessEvaluation({
    required this.state,
    this.email = '',
    this.requestedRole,
    this.reference,
    this.reason,
  });

  final PortalAccessState state;
  final String email;
  final AccessRole? requestedRole;
  final String? reference;
  final String? reason;
  bool get isGranted => state == PortalAccessState.granted;
}

/// Invokes a callable by name and returns its response data. Injectable so
/// tests can fake the catalogue import callables.
/// Idempotency key for a reply: a retried call with the same key returns the
/// reply it already created instead of posting a second one.
String newInquiryRequestId() {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List.generate(24, (_) => alphabet[random.nextInt(alphabet.length)])
      .join();
}

typedef AdminCallableInvoker =
    Future<Object?> Function(String name, Map<String, Object?> data);

class AdminPortalRepository {
  AdminPortalRepository({
    FirestoreService? firestoreService,
    PaccAvailabilityRepository? paccAvailabilityRepository,
    AdminCallableInvoker? callableInvoker,
  }) : _callableInvoker = callableInvoker,
       _firestoreService = firestoreService ?? FirestoreService(),
       _paccAvailabilityRepository =
           paccAvailabilityRepository ??
           PaccAvailabilityRepository(firestoreService: firestoreService);

  final FirestoreService _firestoreService;
  final PaccAvailabilityRepository _paccAvailabilityRepository;
  final AdminCallableInvoker? _callableInvoker;

  Future<Object?> _callCallable(String name, Map<String, Object?> data) {
    final invoker = _callableInvoker;
    if (invoker != null) return invoker(name, data);
    return FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).routedCallable(name).call<Object?>(data).then((result) => result.data);
  }

  /// One page of a student's appointments (current and archived), newest
  /// first. The server matches by the student's verified account ID and
  /// refuses staff who are not authorized for that student.
  Future<StudentCaseHistoryResult> fetchStudentCaseHistory({
    required String studentId,
    String? cursor,
    int pageSize = 20,
  }) async {
    final data = await _callCallable('getStudentCaseHistory', {
      'studentId': studentId,
      'cursor': ?cursor,
      'pageSize': pageSize,
    });
    return StudentCaseHistoryResult.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : const {},
    );
  }

  /// Optional counselor transcript / remarks for one case. The server enforces
  /// counselor entitlement and audits every read.
  Future<CaseRemarks> fetchCaseRemarks(String appointmentId) async {
    final data = await _callCallable('getCaseRemarks', {
      'appointmentId': appointmentId,
    });
    return CaseRemarks.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : const {},
    );
  }

  /// Saves (or clears) counselor transcript / remarks for one case. Blank is
  /// valid; [expectedRevision] prevents overwriting concurrent edits.
  Future<CaseRemarks> saveCaseRemarks({
    required String appointmentId,
    required String text,
    required int expectedRevision,
  }) async {
    final data = await _callCallable('saveCaseRemarks', {
      'appointmentId': appointmentId,
      'text': text,
      'expectedRevision': expectedRevision,
    });
    return CaseRemarks.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : const {},
    );
  }

  /// Dry-runs a catalogue file. [rows] are passed through untouched: an
  /// unmapped role must be absent, a mapped blank cell must be `''`.
  Future<CatalogPreview> previewCatalogImport({
    required String fileName,
    required String sheetName,
    required List<Map<String, String>> rows,
  }) async => CatalogPreview.fromJson(
    await _callCallable('previewAcademicCatalogImport', {
      'fileName': fileName,
      'sheetName': sheetName,
      'rows': rows,
    }),
  );

  Future<CatalogImportResult> importCatalog({
    required String fileName,
    required String sheetName,
    required List<Map<String, String>> rows,
  }) async => CatalogImportResult.fromJson(
    await _callCallable('importAcademicCatalog', {
      'fileName': fileName,
      'sheetName': sheetName,
      'rows': rows,
    }),
  );

  Future<List<AppointmentSlot>> getAvailableAppointmentSlots(DateTime date) =>
      AppointmentRepository().getAvailableSlots(date);
  AccessRole _currentAccessRole = AccessRole.appUser;
  AccessRole get currentAccessRole => _currentAccessRole;
  bool _isSuperAdmin = false;
  bool get isSuperAdmin => _isSuperAdmin;
  bool _mustChangePassword = false;
  bool _staffQueueRefreshAttempted = false;
  bool get mustChangePassword => _mustChangePassword;

  /// Error code from the last best-effort `refreshPortalAppointmentQueue`
  /// catch-up, or `null` when it succeeded or has not run. Staff screens use
  /// this to tell "the sync Function is missing/denied" apart from "no
  /// appointments exist".
  final ValueNotifier<String?> portalQueueSyncError = ValueNotifier<String?>(
    null,
  );

  AccessRole _profileAccessRole(Map<String, dynamic>? profile) {
    final storedAccessRole = profile?['accessRole']?.toString().trim();
    // `appUser` is the pre-approval placeholder. Once an account is
    // approved, older records may retain it while `approvedRole` contains
    // the actual portal role.
    final effectiveRole =
        storedAccessRole == null ||
            storedAccessRole.isEmpty ||
            storedAccessRole.toLowerCase() == 'appuser'
        ? (profile?['approvedRole'])
        : storedAccessRole;
    return AccessRole.parse(effectiveRole, legacyRole: profile?['role']);
  }

  Future<PortalAccessEvaluation> signInStaff({
    required String schoolId,
    required String password,
  }) async {
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: schoolId.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) throw StateError('Unable to identify staff account.');
    final evaluation = await evaluatePortalAccess(refreshUser: true);
    if (evaluation.isGranted) await _recordPortalSessionActivity();
    return evaluation;
  }

  Future<PortalAccessEvaluation> evaluatePortalAccess({
    bool refreshUser = false,
  }) async {
    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const PortalAccessEvaluation(
        state: PortalAccessState.accountNotFound,
      );
    }
    if (refreshUser) {
      await user.reload();
      user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return const PortalAccessEvaluation(
          state: PortalAccessState.accountNotFound,
        );
      }
      await user.getIdToken(true);
    }
    final profile = await _firestoreService.getDocument(
      FirestoreCollections.users,
      user.uid,
    );
    if (profile == null) {
      return PortalAccessEvaluation(
        state: PortalAccessState.accountNotFound,
        email: user.email ?? '',
      );
    }
    final isStaffRequest = profile['staffAccountStatus'] != null;
    if (isStaffRequest && !user.emailVerified) {
      return PortalAccessEvaluation(
        state: PortalAccessState.emailVerificationRequired,
        email: user.email ?? '',
        requestedRole: AccessRole.parse(profile['requestedRole']),
        reference: _requestReference(profile),
      );
    }
    if (isStaffRequest && user.emailVerified) {
      try {
        await FirebaseFunctions.instance
            .httpsCallable('syncStaffEmailVerification')
            .call<Map<String, dynamic>>();
      } on FirebaseFunctionsException catch (error) {
        // A missing request is handled below from the profile. A network or
        // server error must be shown as such instead of advancing the user to
        // a misleading pending-review state.
        if (error.code != 'not-found') rethrow;
      }
    }
    final refreshedProfile = isStaffRequest
        ? await _firestoreService.getDocument(
            FirestoreCollections.users,
            user.uid,
          )
        : profile;
    final resolvedProfile = refreshedProfile ?? profile;
    final role = _profileAccessRole(resolvedProfile);
    final status = StaffAccountStatus.parse(
      resolvedProfile['staffAccountStatus'],
    );
    final registrationStatus = resolvedProfile['registrationStatus']
        ?.toString();
    _mustChangePassword = resolvedProfile['mustChangePassword'] == true;
    if (status == StaffAccountStatus.pending) {
      return PortalAccessEvaluation(
        state: registrationStatus == 'more_information_required'
            ? PortalAccessState.moreInformationRequired
            : PortalAccessState.pendingAdminApproval,
        email: user.email ?? '',
        requestedRole: AccessRole.parse(resolvedProfile['requestedRole']),
        reference: _requestReference(resolvedProfile),
        reason: resolvedProfile['moreInformationReason']?.toString(),
      );
    }
    if (status == StaffAccountStatus.rejected) {
      return PortalAccessEvaluation(
        state: PortalAccessState.rejected,
        email: user.email ?? '',
      );
    }
    if (status == StaffAccountStatus.disabled) {
      return PortalAccessEvaluation(
        state: registrationStatus == 'approved'
            ? PortalAccessState.suspended
            : PortalAccessState.disabled,
        email: user.email ?? '',
      );
    }
    if (!role.canUsePortal) {
      return PortalAccessEvaluation(
        state: PortalAccessState.noPortalRole,
        email: user.email ?? '',
      );
    }
    _currentAccessRole = role;
    if (role == AccessRole.admin) {
      _isSuperAdmin = await _confirmSuperAdmin();
    } else {
      _isSuperAdmin = false;
    }
    await _tryRecordAudit(
      action: 'STAFF_SIGNED_IN',
      category: 'AUTHENTICATION',
    );
    return PortalAccessEvaluation(
      state: PortalAccessState.granted,
      email: user.email ?? '',
    );
  }

  String? _requestReference(Map<String, dynamic> profile) {
    final requestId = profile['accessRequestId']?.toString().trim() ?? '';
    final end = requestId.length < 8 ? requestId.length : 8;
    return requestId.isEmpty
        ? null
        : 'REQ-${requestId.substring(0, end).toUpperCase()}';
  }

  User? get currentAuthUser => FirebaseAuth.instance.currentUser;
  String? get currentUserId => currentAuthUser?.uid;
  Stream<User?> get authStateChanges =>
      FirebaseAuth.instance.authStateChanges();

  Future<bool> restoreSession() async {
    final evaluation = await evaluatePortalAccess(refreshUser: true);
    if (evaluation.isGranted) await _recordPortalSessionActivity();
    return evaluation.isGranted;
  }

  Future<void> _recordPortalSessionActivity() async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('recordPortalSessionActivity')
          .call<void>();
    } catch (_) {
      // Activity telemetry must never interrupt an otherwise valid login.
    }
  }

  Future<int> backfillStaffAccountAuthMetadata() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('backfillStaffAccountAuthMetadata')
        .call<Map<String, dynamic>>();
    return (result.data['updated'] as num?)?.toInt() ?? 0;
  }

  Future<StaffAccessRequestSubmission> registerStaff({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String employeeId,
    required String position,
    String department = '',
    String departmentId = '',
    String collegeId = '',
    String courseId = '',
    required AccessRole requestedRole,
  }) async {
    final credential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
    String? requestId;
    String? reference;
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('registerStaffAccount')
          .call<Map<String, dynamic>>({
            'firstName': firstName.trim(),
            'lastName': lastName.trim(),
            'employeeId': employeeId.trim(),
            'position': position.trim(),
            'department': department.trim(),
            'departmentId': departmentId,
            'collegeId': collegeId,
            'courseId': courseId,
            'requestedRole': requestedRole.storedValue,
          });
      requestId = result.data['requestId']?.toString();
      reference = result.data['reference']?.toString();
    } catch (error) {
      // The callable can commit the access request and then lose its response
      // over the network. Do not delete a valid Auth account in that case.
      Map<String, dynamic>? profile;
      try {
        profile = await getOwnProfile(credential.user!.uid);
      } catch (_) {
        // Preserve the original error when reconciliation is unavailable.
      }
      if (profile == null || profile['accessRequestId'] == null) {
        await credential.user?.delete();
        rethrow;
      }
    }

    try {
      await FirebaseFunctions.instance
          .routedCallable('requestStaffEmailVerification')
          .call<void>();
      return StaffAccessRequestSubmission(
        verificationSent: true,
        requestId: requestId,
        reference: reference,
      );
    } catch (_) {
      // The access request is already safely stored. The user can resend
      // verification later without losing the registration.
      return StaffAccessRequestSubmission(
        verificationSent: false,
        requestId: requestId,
        reference: reference,
      );
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await FirebaseFunctions.instance
        .routedCallable('requestAdminPasswordReset')
        .call<void>({'email': email.trim()});
  }

  Future<void> signOut() async {
    await _tryRecordAudit(
      action: 'STAFF_SIGNED_OUT',
      category: 'AUTHENTICATION',
    );
    _currentAccessRole = AccessRole.appUser;
    _isSuperAdmin = false;
    _mustChangePassword = false;
    await FirebaseAuth.instance.signOut();
  }

  Future<void> cancelPendingRegistration() async {
    await FirebaseFunctions.instance
        .routedCallable('cancelPendingRegistration')
        .call<void>();
    _currentAccessRole = AccessRole.appUser;
    _isSuperAdmin = false;
    _mustChangePassword = false;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Server cancellation already succeeded; local session cleanup is best effort.
    }
  }

  Future<void> _tryRecordAudit({
    required String action,
    required String category,
    String? targetType,
    String? targetId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await recordAuditEvent(
        action: action,
        category: category,
        targetType: targetType,
        targetId: targetId,
        metadata: metadata,
      );
    } catch (_) {
      // Authentication and navigation must not fail because audit delivery is unavailable.
    }
  }

  Future<bool> _confirmSuperAdmin() async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('confirmSuperAdmin')
          .call<Map<String, dynamic>>();
      return result.data['isSuperAdmin'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> completeMandatoryPasswordChange(String password) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Administrator session is missing.');
    await user.updatePassword(password);
    await FirebaseFunctions.instance
        .httpsCallable('completeAdminPasswordChange')
        .call();
    _mustChangePassword = false;
    await user.getIdToken(true);
  }

  Stream<List<College>> watchColleges() => _firestoreService
      .watchDocuments(FirestoreCollections.colleges)
      .map(
        (v) =>
            v.map(College.fromJson).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
      );
  Stream<List<Department>> watchDepartments() => _firestoreService
      .watchDocuments(FirestoreCollections.departments)
      .map(
        (v) =>
            v.map(Department.fromJson).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
      );
  Stream<List<Course>> watchCourses() => _firestoreService
      .watchDocuments(FirestoreCollections.courses)
      .map(
        (v) =>
            v.map(Course.fromJson).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
      );

  /// Firestore managed-export job history. Only the configured
  /// super-administrator may read `backup_jobs`; everyone else gets an
  /// error stream so the page shows "not authorized", never "no backups".
  Stream<List<BackupJob>> watchBackupJobs() {
    if (!isSuperAdmin) {
      return Stream.error(
        StateError(
          'Backup history requires the configured super-administrator account.',
        ),
      );
    }
    return _firestoreService
        .watchDocuments(
          FirestoreCollections.backupJobs,
          orderBy: 'requestedAt',
          descending: true,
          limit: 50,
        )
        .map(
          (items) => items
              .map((item) => BackupJob.fromJson(item, id: item['id']?.toString()))
              .toList(),
        );
  }

  /// Starts one managed Firestore export. Server-side authorization only.
  Future<String> requestFirestoreBackup() async {
    final result = await _callCallable('requestFirestoreBackup', {});
    final data = result is Map ? Map<String, dynamic>.from(result) : const {};
    return data['jobId']?.toString() ?? '';
  }

  Future<void> refreshBackupJobStatus(String jobId) =>
      _callCallable('refreshFirestoreBackupStatus', {'jobId': jobId});

  /// Retrieves the complete Firestore backup snapshot via paginated
  /// super-admin-authorized Cloud Function calls. Throws if any page fails
  /// or pagination ends without a complete cursor cycle so partial exports are
  /// never returned.
  Future<BackupExportDataset> fetchCompleteFirestoreBackup({
    required BackupExportFormat format,
    int pageSize = 200,
    void Function(BackupExportProgress progress)? onProgress,
  }) async {
    if (!isSuperAdmin) {
      throw StateError(
        'Backup export requires the configured super-administrator account.',
      );
    }

    String? exportId;
    DateTime? exportedAt;
    Map<String, Object?>? cursor;
    String? previousCursorKey;
    var pagesLoaded = 0;
    var totalDocs = 0;

    final collectionPathsByKey = <String, Set<String>>{};
    final docsByKey = <String, List<BackupDocumentRecord>>{};
    final seenDocPaths = <String>{};

    while (true) {
      final raw = await _callCallable('exportFirestoreBackupPage', {
        'format': format.wireName,
        'pageSize': pageSize,
        'exportId': ?exportId,
        'cursor': ?cursor,
      });
      if (raw is! Map) {
        throw const FormatException(
          'Incomplete backup export: unexpected server response.',
        );
      }
      final payload = Map<String, dynamic>.from(raw);
      final pageExportId = payload['exportId']?.toString().trim() ?? '';
      if (pageExportId.isEmpty) {
        throw const FormatException(
          'Incomplete backup export: missing export identifier.',
        );
      }
      if (exportId == null) {
        exportId = pageExportId;
      } else if (exportId != pageExportId) {
        throw StateError(
          'Incomplete backup export: mismatched export session.',
        );
      }

      if (exportedAt == null) {
        final rawAt = payload['exportedAt']?.toString();
        exportedAt = rawAt == null
            ? DateTime.now().toUtc()
            : DateTime.parse(rawAt).toUtc();
      }

      final visited = payload['visitedCollections'];
      if (visited is! List) {
        throw const FormatException(
          'Incomplete backup export: missing visited collections metadata.',
        );
      }
      for (final entry in visited) {
        if (entry is! Map) {
          throw const FormatException(
            'Incomplete backup export: malformed collection metadata.',
          );
        }
        final map = Map<String, dynamic>.from(entry);
        final key = map['collectionKey']?.toString().trim() ?? '';
        final path = map['collectionPath']?.toString().trim() ?? '';
        if (key.isEmpty || path.isEmpty) {
          throw const FormatException(
            'Incomplete backup export: empty collection metadata.',
          );
        }
        collectionPathsByKey.putIfAbsent(key, () => <String>{}).add(path);
        docsByKey.putIfAbsent(key, () => <BackupDocumentRecord>[]);
      }

      final rawDocs = payload['documents'];
      if (rawDocs is! List) {
        throw const FormatException(
          'Incomplete backup export: missing documents list.',
        );
      }
      for (final item in rawDocs) {
        if (item is! Map) {
          throw const FormatException(
            'Incomplete backup export: malformed document payload.',
          );
        }
        final record = BackupDocumentRecord.fromJson(
          Map<String, dynamic>.from(item),
        );
        collectionPathsByKey
            .putIfAbsent(record.collectionKey, () => <String>{})
            .add(record.collectionPath);
        if (seenDocPaths.add(record.documentPath)) {
          docsByKey
              .putIfAbsent(record.collectionKey, () => <BackupDocumentRecord>[])
              .add(record);
          totalDocs++;
        }
      }

      pagesLoaded++;
      onProgress?.call(
        BackupExportProgress(
          pagesLoaded: pagesLoaded,
          documentsLoaded: totalDocs,
          collectionsDiscovered: collectionPathsByKey.length,
        ),
      );

      final hasMore = payload['hasMore'] == true;
      if (!hasMore) break;

      final nextRaw = payload['nextCursor'];
      if (nextRaw is! Map || nextRaw.isEmpty) {
        throw StateError(
          'Incomplete backup export: server indicated more data without a cursor.',
        );
      }
      final nextCursor = Map<String, Object?>.from(
        nextRaw.map((k, v) => MapEntry(k.toString(), v)),
      );
      final nextKey =
          '${nextCursor['currentCollection']}|${nextCursor['afterDocId']}|${nextCursor['queue']}';
      if (previousCursorKey != null && nextKey == previousCursorKey) {
        throw StateError(
          'Incomplete backup export: pagination cursor did not advance.',
        );
      }
      previousCursorKey = nextKey;
      cursor = nextCursor;
    }

    final sortedKeys = collectionPathsByKey.keys.toList()..sort();
    final collections = <BackupCollectionDataset>[
      for (final key in sortedKeys)
        BackupCollectionDataset(
          collectionKey: key,
          collectionPaths: collectionPathsByKey[key]!.toList()..sort(),
          documents: (docsByKey[key] ?? const <BackupDocumentRecord>[])
            ..sort((a, b) => a.documentPath.compareTo(b.documentPath)),
        ),
    ];

    return BackupExportDataset(
      exportId: exportId,
      exportedAt: exportedAt,
      collections: collections,
    );
  }

  Stream<List<AdminAuditEvent>> watchAdminAudit(String userId) =>
      _firestoreService
          .watchDocuments(
            FirestoreCollections.adminAuditLogs,
            whereEquals: {'targetUserId': userId},
          )
          .map(
            (items) => items.map(AdminAuditEvent.fromJson).toList()
              ..sort(
                (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
                  a.createdAt ?? DateTime(1970),
                ),
              ),
          );

  Future<({List<AdminAuditEvent> events, bool hasMore})> fetchAuditLogPage({
    required String targetUserId,
    String category = '',
    String action = '',
    DateTime? before,
    DateTime? after,
    int pageSize = 25,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('getAuditLogPage')
          .call<Map<String, dynamic>>({
            'targetUserId': targetUserId,
            if (category.isNotEmpty) 'category': category,
            if (action.isNotEmpty) 'action': action,
            if (before != null) 'beforeMillis': before.millisecondsSinceEpoch,
            if (after != null) 'afterMillis': after.millisecondsSinceEpoch,
            'pageSize': pageSize,
          });
      final raw = result.data['events'];
      final events = raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (item) =>
                      AdminAuditEvent.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : <AdminAuditEvent>[];
      return (events: events, hasMore: result.data['hasMore'] == true);
    } catch (_) {
      // Never report "no views" when the access-log query itself failed (for
      // example a missing index); the client-side fallback cannot filter it.
      if (const {
        'STUDENT_PERSONAL_INFO_VIEWED',
        'COUNSELING_HISTORY_VIEWED',
        'CASE_REMARKS_VIEWED',
        'CASE_REMARKS_UPDATED',
        'CLINICAL_ATTACHMENT_DOWNLOADED',
      }.contains(action)) {
        rethrow;
      }
      // The caller is already an authorized portal administrator. Fall back to
      // the protected Firestore read while a callable/index is propagating.
      final items = await _firestoreService.getDocuments(
        FirestoreCollections.adminAuditLogs,
        // View-filter queries rethrew above, so this fallback only ever serves
        // target-scoped ones.
        whereEquals: {'targetUserId': targetUserId},
        orderBy: 'createdAt',
        limit: pageSize,
      );
      final events = items.map((item) => AdminAuditEvent.fromJson(item)).where((
        event,
      ) {
        final matchesCategory = category.isEmpty || event.category == category;
        final matchesAction = action.isEmpty || event.action == action;
        final matchesAfter =
            after == null || (event.createdAt?.isAfter(after) ?? false);
        final matchesBefore =
            before == null || (event.createdAt?.isBefore(before) ?? false);
        return matchesCategory &&
            matchesAction &&
            matchesAfter &&
            matchesBefore;
      }).toList();
      return (events: events, hasMore: false);
    }
  }

  /// Fetches a paginated, sanitized page of Admin-wide activity logs monitoring
  /// Administrator, Counselor, and PAACC Staff actions.
  ///
  /// Restricted strictly to Super-Administrators on both client and server.
  Future<({List<AdminAuditEvent> events, bool hasMore, String? nextCursor})>
  fetchActivityLogPage({
    ActivityActorRoleFilter roleFilter = ActivityActorRoleFilter.all,
    String actorId = '',
    String category = '',
    String action = '',
    String search = '',
    DateTime? after,
    DateTime? before,
    String? cursor,
    int pageSize = 25,
  }) async {
    if (!isSuperAdmin) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message:
            'Super-administrator access is required to view system activity logs.',
      );
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('getAuditLogPage')
        .call<Map<String, dynamic>>({
          if (roleFilter != ActivityActorRoleFilter.all)
            'actorRole': roleFilter.code,
          if (actorId.trim().isNotEmpty) 'filterActorId': actorId.trim(),
          if (category.trim().isNotEmpty) 'category': category.trim(),
          if (action.trim().isNotEmpty) 'action': action.trim(),
          if (search.trim().isNotEmpty) 'search': search.trim(),
          if (after != null) 'afterMillis': after.millisecondsSinceEpoch,
          if (before != null) 'beforeMillis': before.millisecondsSinceEpoch,
          'cursor': ?cursor,
          'pageSize': pageSize,
        });
    final raw = result.data['events'];
    final events = raw is List
        ? raw
              .whereType<Map>()
              .map(
                (item) => sanitizeAuditEventForDisplay(
                  AdminAuditEvent.fromJson(Map<String, dynamic>.from(item)),
                ),
              )
              .toList()
        : <AdminAuditEvent>[];
    final nextCursor = result.data['nextCursor'] as String?;
    return (
      events: events,
      hasMore: nextCursor != null,
      nextCursor: nextCursor,
    );
  }

  Future<void> recordAuditEvent({
    required String action,
    required String category,
    String? targetType,
    String? targetId,
    Map<String, dynamic>? metadata,
  }) async {
    await FirebaseFunctions.instance.httpsCallable('recordAuditEvent').call({
      'action': action,
      'category': category,
      'targetType': ?targetType,
      'targetId': ?targetId,
      'metadata': ?metadata,
    });
  }

  Future<List<PublicAppUserRecord>> listPublicAppUsers() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('listPublicAppUsers')
        .call<Map<String, dynamic>>();
    final raw = result.data['users'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) =>
              PublicAppUserRecord.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList()
      ..sort((a, b) => a.publicUserId.compareTo(b.publicUserId));
  }

  Future<int> backfillPublicAppUserIds() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('backfillPublicAppUserIds')
        .call<Map<String, dynamic>>();
    return (result.data['processed'] as num?)?.toInt() ?? 0;
  }

  Stream<List<UserModel>> watchUsers() => _firestoreService
      .watchDocuments(FirestoreCollections.users)
      .map(
        (items) =>
            items
                .map(
                  (item) =>
                      UserModel.fromJson(item, id: item['id']?.toString()),
                )
                .toList()
              ..sort((a, b) => a.displayName.compareTo(b.displayName)),
      );

  Stream<List<AdminRoleCorrectionRequest>> watchRoleCorrectionRequests() =>
      _firestoreService
          .watchDocuments(FirestoreCollections.roleCorrectionRequests)
          .map(
            (items) =>
                items
                    .map(AdminRoleCorrectionRequest.fromJson)
                    .where((item) => item.status == 'pending')
                    .toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
          );

  List<AppointmentModel> _mapAppointments(List<Map<String, dynamic>> items) =>
      items
          .map(
            (item) =>
                AppointmentModel.fromJson(item, id: item['id']?.toString()),
          )
          .toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  Stream<List<AppointmentModel>> _watchCollegeScopedAppointments({
    Map<String, Object?> extraWhereEquals = const {},
    required bool errorWhenUnauthorized,
  }) {
    final uid = currentUserId;
    final role = currentAccessRole;
    if (extraWhereEquals.isEmpty && isSuperAdmin) {
      return _firestoreService
          .watchDocuments(FirestoreCollections.appointments)
          .map(_mapAppointments);
    }
    if (role != AccessRole.counselor || uid == null || uid.trim().isEmpty) {
      if (errorWhenUnauthorized) {
        return Stream<List<AppointmentModel>>.error(
          StateError(
            'Appointments are visible only to assigned counselors and the super-administrator.',
          ),
        );
      }
      return Stream.value(const <AppointmentModel>[]);
    }

    late final StreamController<List<AppointmentModel>> controller;
    StreamSubscription<Map<String, dynamic>?>? profileSub;
    final querySubs = <StreamSubscription<List<Map<String, dynamic>>>>[];
    var chunkResults = <int, List<Map<String, dynamic>>>{};
    String? activeScopeKey;
    var hasResolvedScope = false;

    Future<void> cancelQuerySubs() async {
      final subs = List<StreamSubscription<List<Map<String, dynamic>>>>.from(
        querySubs,
      );
      querySubs.clear();
      chunkResults = <int, List<Map<String, dynamic>>>{};
      for (final sub in subs) {
        await sub.cancel();
      }
    }

    void emitMerged() {
      if (controller.isClosed) return;
      final byId = <String, Map<String, dynamic>>{};
      for (final list in chunkResults.values) {
        for (final item in list) {
          final id = item['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            byId[id] = item;
          }
        }
      }
      controller.add(_mapAppointments(byId.values.toList(growable: false)));
    }

    controller = StreamController<List<AppointmentModel>>(
      onListen: () {
        profileSub = _firestoreService
            .watchDocument(FirestoreCollections.users, uid)
            .listen(
              (profile) async {
                if (controller.isClosed) return;
                final accessRole = profile?['accessRole']?.toString().trim();
                final accountStatus = profile?['accountStatus']
                    ?.toString()
                    .trim();
                final staffStatus = profile?['staffAccountStatus']
                    ?.toString()
                    .trim();
                final isActiveCounselor =
                    profile != null &&
                    (accessRole == null ||
                        accessRole.isEmpty ||
                        accessRole == 'counselor') &&
                    (accountStatus == null ||
                        accountStatus.isEmpty ||
                        accountStatus == 'active') &&
                    (staffStatus == null ||
                        staffStatus.isEmpty ||
                        staffStatus == 'approved');
                final rawColleges = profile?['assignedCollegeIds'];
                final collegeIds = isActiveCounselor && rawColleges is List
                    ? (rawColleges
                          .whereType<String>()
                          .map((id) => id.trim())
                          .where((id) => id.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort())
                    : <String>[];

                final nextScopeKey = isActiveCounselor
                    ? collegeIds.join('\u0000')
                    : null;
                if (hasResolvedScope &&
                    nextScopeKey == activeScopeKey &&
                    (collegeIds.isEmpty || querySubs.isNotEmpty)) {
                  return;
                }
                hasResolvedScope = true;
                activeScopeKey = nextScopeKey;
                final hadActiveSubscriptions = querySubs.isNotEmpty;
                await cancelQuerySubs();
                if (controller.isClosed) return;
                if (collegeIds.isEmpty) {
                  controller.add(const <AppointmentModel>[]);
                  return;
                }
                if (hadActiveSubscriptions) {
                  controller.add(const <AppointmentModel>[]);
                }

                const chunkSize = 30;
                final chunks = <List<String>>[
                  for (var i = 0; i < collegeIds.length; i += chunkSize)
                    collegeIds.sublist(
                      i,
                      min(i + chunkSize, collegeIds.length),
                    ),
                ];
                for (var index = 0; index < chunks.length; index++) {
                  final chunk = chunks[index];
                  final sub = _firestoreService
                      .watchDocuments(
                        FirestoreCollections.appointments,
                        whereEquals: {
                          ...extraWhereEquals,
                          'studentVerificationStatus': 'verified',
                        },
                        whereIn: {'collegeId': chunk},
                      )
                      .listen(
                        (items) {
                          chunkResults[index] = items;
                          if (chunkResults.length == chunks.length) {
                            emitMerged();
                          }
                        },
                        onError: (Object error, StackTrace stackTrace) {
                          if (!controller.isClosed) {
                            controller.addError(error, stackTrace);
                          }
                        },
                      );
                  querySubs.add(sub);
                }
              },
              onError: (Object error, StackTrace stackTrace) {
                if (!controller.isClosed) {
                  controller.addError(error, stackTrace);
                }
              },
            );
      },
      onCancel: () async {
        await profileSub?.cancel();
        await cancelQuerySubs();
      },
    );
    return controller.stream;
  }

  /// College-scoped appointments for counselors (verified students in
  /// `assignedCollegeIds`), or all appointments for the super-administrator.
  Stream<List<AppointmentModel>> watchAppointments() =>
      _watchCollegeScopedAppointments(errorWhenUnauthorized: true);

  /// The counselor's college-scoped caseload within their currently assigned colleges.
  Stream<List<AppointmentModel>> watchMyAssignedAppointments() {
    final userId = currentUserId;
    if (currentAccessRole != AccessRole.counselor ||
        isSuperAdmin ||
        userId == null ||
        userId.trim().isEmpty) {
      return Stream.value(const <AppointmentModel>[]);
    }
    return _watchCollegeScopedAppointments(errorWhenUnauthorized: false);
  }

  /// Explicitly backfill the staff-safe queue from canonical appointments.
  /// This is a privileged Cloud Function; callers never receive clinical data.
  /// On staging it requires the Function to be deployed and Staff approval.
  Future<int> refreshPortalAppointmentQueue() async {
    if (currentAccessRole != AccessRole.portalStaff) {
      throw StateError('PACC Staff access is required.');
    }
    final result = await FirebaseFunctions.instance
        .routedCallable('refreshPortalAppointmentQueue')
        .call<Map<String, dynamic>>();
    return (result.data['refreshed'] as num?)?.toInt() ?? 0;
  }

  /// Read the existing staff-safe appointment projection directly.
  ///
  /// Do not gate the whole screen on `refreshPortalAppointmentQueue`: a
  /// callable can be unavailable in staging, rate-limited, or fail App Check,
  /// even when the user is authorized to read existing queue documents.
  /// Projection refresh is a separate privileged operation, not a read
  /// prerequisite. Firestore rules still enforce portalStaff-only access.
  Stream<List<AppointmentQueueItem>> watchPortalAppointmentQueue() {
    if (currentAccessRole != AccessRole.portalStaff) {
      return Stream.value(const <AppointmentQueueItem>[]);
    }
    // Best-effort catch-up for records created before the queue projection
    // trigger was deployed. Never block reads on this Cloud Function.
    // One attempt per repository instance avoids repeat requests on rebuild.
    if (!_staffQueueRefreshAttempted) {
      _staffQueueRefreshAttempted = true;
      unawaited(
        FirebaseFunctions.instance
            .routedCallable('refreshPortalAppointmentQueue')
            .call()
            .then<void>((_) => portalQueueSyncError.value = null)
            .catchError((Object error, StackTrace stackTrace) {
              // The Firestore queue listener remains authoritative and live.
              // App Check / callable failures must not blank the Staff UI,
              // but they must be visible: a missing or denied sync Function
              // is the usual reason the queue projection is empty.
              portalQueueSyncError.value = error is FirebaseFunctionsException
                  ? error.code
                  : 'unavailable';
            }),
      );
    }
    return _firestoreService
        .watchDocuments(FirestoreCollections.appointmentQueue)
        .map(
          (items) =>
              items
                  .map(
                    (item) => AppointmentQueueItem.fromJson(
                      item,
                      id: item['id']?.toString(),
                    ),
                  )
                  .toList()
                ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt)),
        );
  }

  Stream<List<AppNotificationModel>> watchPortalNotifications() =>
      _watchPortalNotifications(archived: false);

  Stream<List<AppNotificationModel>> watchArchivedPortalNotifications() =>
      _watchPortalNotifications(archived: true);

  Stream<List<AppNotificationModel>> _watchPortalNotifications({
    required bool archived,
  }) {
    final userId = currentAuthUser?.uid;
    if (userId == null || !currentAccessRole.canAccessClinicalData) {
      return Stream.value(const []);
    }
    return _firestoreService
        .watchDocuments(
          FirestoreCollections.notifications,
          whereEquals: {'userId': userId},
          orderBy: 'createdAt',
          descending: true,
          limit: 200,
        )
        .map(
          (items) => items
              .map(
                (item) => AppNotificationModel.fromJson(
                  item,
                  id: item['id']?.toString(),
                ),
              )
              .where(
                (item) =>
                    item.audience == 'portal' && item.isArchived == archived,
              )
              .toList(growable: false),
        );
  }

  static DateTime? _lastVerificationEmailSentAt;

  Future<Duration> resendStaffVerificationEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in is required to resend verification.');
    }
    final now = DateTime.now();
    final previous = _lastVerificationEmailSentAt;
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 60)) {
      return const Duration(seconds: 60) - now.difference(previous);
    }
    await FirebaseFunctions.instance
        .routedCallable('requestStaffEmailVerification')
        .call<void>();
    _lastVerificationEmailSentAt = now;
    return Duration.zero;
  }

  Future<void> managePortalNotification(
    String notificationId, {
    required String action,
  }) async {
    await managePortalNotifications([notificationId], action: action);
  }

  Future<void> managePortalNotifications(
    List<String> notificationIds, {
    required String action,
  }) async {
    if (!currentAccessRole.canAccessClinicalData) {
      throw StateError('Counselor or administrator access is required.');
    }
    await FirebaseFunctions.instance
        .httpsCallable('managePortalNotification')
        .call<Map<String, dynamic>>({
          'notificationIds': notificationIds,
          'action': action,
        });
  }

  Future<void> markPortalNotificationRead(String notificationId) {
    if (!currentAccessRole.canAccessClinicalData) {
      throw StateError('Counselor or administrator access is required.');
    }
    return _firestoreService.updateDocument(
      FirestoreCollections.notifications,
      notificationId,
      {'readAt': FieldValue.serverTimestamp()},
    );
  }

  Future<Map<String, dynamic>> fetchMindAidEmergencyAlert(
    String alertId,
  ) async {
    if (!currentAccessRole.canAccessClinicalData) {
      throw StateError('Counselor or administrator access is required.');
    }
    final snapshot = await FirebaseFirestore.instance
        .collection('mind_aid_emergency_alerts')
        .doc(alertId)
        .get();
    if (!snapshot.exists) throw StateError('Emergency alert is unavailable.');
    return snapshot.data() ?? const <String, dynamic>{};
  }

  Future<void> acknowledgeMindAidEmergencyAlert(String alertId) async {
    if (!currentAccessRole.canAccessClinicalData) {
      throw StateError('Counselor or administrator access is required.');
    }
    await FirebaseFunctions.instance
        .httpsCallable('acknowledgeMindAidEmergencyAlert')
        .call<void>({'alertId': alertId});
  }

  Future<void> resolveMindAidEmergencyAlert(
    String alertId, {
    required String resolutionDisposition,
  }) async {
    if (!currentAccessRole.canAccessClinicalData) {
      throw StateError('Counselor or administrator access is required.');
    }
    await FirebaseFunctions.instance
        .httpsCallable('resolveMindAidEmergencyAlert')
        .call<void>({
          'alertId': alertId,
          'resolutionDisposition': resolutionDisposition,
        });
  }

  Future<AdminReportAnalytics> fetchReportAnalytics({
    String userCategory = 'all',
    String appointmentDepartment = 'all',
    String? schoolYear,
    DateTime? startDate,
    DateTime? endDate,
  }) => _callReportAnalytics(
    userCategory: userCategory,
    appointmentDepartment: appointmentDepartment,
    schoolYear: schoolYear,
    startDate: startDate,
    endDate: endDate,
    emotionalSource: 'all',
  );

  Future<AdminReportAnalytics> fetchEmotionalReportAnalytics({
    String userCategory = 'all',
    String appointmentDepartment = 'all',
    String? schoolYear,
    DateTime? startDate,
    DateTime? endDate,
    String emotionalSource = 'all',
  }) {
    if (emotionalSource == 'all') {
      return fetchReportAnalytics(
        userCategory: userCategory,
        appointmentDepartment: appointmentDepartment,
        schoolYear: schoolYear,
        startDate: startDate,
        endDate: endDate,
      );
    }
    return _callReportAnalytics(
      userCategory: userCategory,
      appointmentDepartment: appointmentDepartment,
      schoolYear: schoolYear,
      startDate: startDate,
      endDate: endDate,
      emotionalSource: emotionalSource,
    );
  }

  /// Fetches report analytics with optional college-scoped [program] and
  /// [periodLabel] filters while preserving backward compatibility for legacy
  /// test overrides of [fetchReportAnalytics] and
  /// [fetchEmotionalReportAnalytics].
  Future<AdminReportAnalytics> fetchFilteredReportAnalytics({
    String userCategory = 'all',
    String appointmentDepartment = 'all',
    String program = 'all',
    String? schoolYear,
    String? periodLabel,
    DateTime? startDate,
    DateTime? endDate,
    String emotionalSource = 'all',
  }) {
    if (program == 'all' && periodLabel == null) {
      return fetchEmotionalReportAnalytics(
        userCategory: userCategory,
        appointmentDepartment: appointmentDepartment,
        schoolYear: schoolYear,
        startDate: startDate,
        endDate: endDate,
        emotionalSource: emotionalSource,
      );
    }
    return _callReportAnalytics(
      userCategory: userCategory,
      appointmentDepartment: appointmentDepartment,
      program: program,
      schoolYear: schoolYear,
      periodLabel: periodLabel,
      startDate: startDate,
      endDate: endDate,
      emotionalSource: emotionalSource,
    );
  }

  Future<AdminReportAnalytics> _callReportAnalytics({
    required String userCategory,
    required String appointmentDepartment,
    String program = 'all',
    String? schoolYear,
    String? periodLabel,
    DateTime? startDate,
    DateTime? endDate,
    required String emotionalSource,
  }) async {
    if (!currentAccessRole.canAccessClinicalData) {
      throw StateError('Counselor or administrator access is required.');
    }
    final data = await _callCallable('getReportAnalytics', {
      'userCategory': userCategory,
      'appointmentDepartment': appointmentDepartment,
      'program': program,
      'schoolYear': ?schoolYear,
      'periodLabel': ?periodLabel,
      'startDate': ?startDate?.toUtc().toIso8601String(),
      'endDate': ?endDate?.toUtc().toIso8601String(),
      'emotionalSource': emotionalSource,
    });
    final raw = data is Map ? data['report'] : null;
    if (raw is! Map) {
      throw StateError('The report service returned an invalid response.');
    }
    return AdminReportAnalytics.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<CounselingPopulationConfig> fetchCounselingPopulation(
    String schoolYear,
  ) async {
    if (currentAccessRole != AccessRole.admin) {
      throw StateError('Administrator access is required.');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('getCounselingPopulation')
        .call<Map<String, dynamic>>({'schoolYear': schoolYear});
    return CounselingPopulationConfig.fromJson(result.data);
  }

  Future<CounselingPopulationConfig> saveCounselingPopulation({
    required String schoolYear,
    required Map<String, int> populations,
  }) async {
    if (currentAccessRole != AccessRole.admin) {
      throw StateError('Administrator access is required.');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('saveCounselingPopulation')
        .call<Map<String, dynamic>>({
          'schoolYear': schoolYear,
          'populations': populations,
        });
    return CounselingPopulationConfig.fromJson(result.data);
  }

  bool? _extendedAcademicYearLifecycleEnabled;

  bool get isExtendedAcademicYearLifecycleEnabled =>
      _extendedAcademicYearLifecycleEnabled ?? false;

  Future<List<AcademicYearRecord>> _callAcademicYearAction(
    String callable,
    Map<String, dynamic> payload,
  ) async {
    if (currentAccessRole != AccessRole.admin) {
      throw StateError('Administrator access is required.');
    }
    final data = await _callCallable(callable, payload);
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : const <String, dynamic>{};
    if (map['extendedLifecycleEnabled'] is bool) {
      _extendedAcademicYearLifecycleEnabled =
          map['extendedLifecycleEnabled'] as bool;
    } else if (callable == 'getAcademicYears') {
      _extendedAcademicYearLifecycleEnabled = false;
    }
    return _academicYears(map);
  }

  Future<List<AcademicYearRecord>> fetchAcademicYears({
    bool includeVoided = false,
  }) => _callAcademicYearAction(
    'getAcademicYears',
    includeVoided ? const {'includeVoided': true} : const {},
  );

  Future<List<AcademicYearRecord>> createAcademicYear({
    required String schoolYear,
    String? startDate,
    String? endDate,
    String? copyFrom,
    bool copyPopulation = false,
    String? reinstateReason,
    int? expectedRevision,
  }) => _callAcademicYearAction('createAcademicYear', {
    'schoolYear': schoolYear,
    'startDate': ?startDate,
    'endDate': ?endDate,
    'copyFrom': ?copyFrom,
    'copyPopulation': copyPopulation,
    'reinstateReason': ?reinstateReason,
    'expectedRevision': ?expectedRevision,
  });

  Future<List<AcademicYearRecord>> activateAcademicYear(
    String schoolYear, {
    int? expectedRevision,
  }) => _callAcademicYearAction('activateAcademicYear', {
    'schoolYear': schoolYear,
    'expectedRevision': ?expectedRevision,
  });

  Future<List<AcademicYearRecord>> closeAcademicYear(
    String schoolYear, {
    int? expectedRevision,
    String? confirmation,
  }) => _callAcademicYearAction('closeAcademicYear', {
    'schoolYear': schoolYear,
    'expectedRevision': ?expectedRevision,
    'confirmation': ?confirmation,
  });

  Future<List<AcademicYearRecord>> voidAcademicYear({
    required String schoolYear,
    required String reason,
    required String confirmationText,
    int? expectedRevision,
  }) async {
    if (!isSuperAdmin) {
      throw StateError('Super-admin access is required.');
    }
    return _callAcademicYearAction('voidAcademicYear', {
      'schoolYear': schoolYear,
      'reason': reason,
      'confirmation': confirmationText,
      'expectedRevision': ?expectedRevision,
    });
  }

  static List<AcademicYearRecord> _academicYears(Map<String, dynamic> data) =>
      (data['years'] is List ? data['years'] as List : const [])
          .whereType<Map>()
          .map(
            (item) =>
                AcademicYearRecord.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);

  Future<int> importWalkInAppointments(
    List<WalkInAppointmentImportRow> rows, {
    String? fileName,
  }) async {
    if (!currentAccessRole.canAccessClinicalData) {
      throw StateError('Counselor or administrator access is required.');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('importWalkInAppointments')
        .call<Map<String, dynamic>>({
          'rows': rows.map((row) => row.toJson()).toList(growable: false),
          if (fileName != null && fileName.trim().isNotEmpty)
            'fileName': fileName.trim(),
        });
    return (result.data['imported'] as num?)?.toInt() ?? rows.length;
  }

  Future<List<ImportedWalkInFile>> listWalkInImports() async {
    if (currentAccessRole != AccessRole.admin) {
      throw StateError('Administrator access is required.');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('listWalkInImports')
        .call<Map<String, dynamic>>();
    final raw = result.data['files'];
    return raw is List
        ? raw
              .whereType<Map>()
              .map(
                (item) => ImportedWalkInFile.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false)
        : const [];
  }

  Future<int> deleteWalkInImport(String importId) async {
    if (currentAccessRole != AccessRole.admin) {
      throw StateError('Administrator access is required.');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('deleteWalkInImport')
        .call<Map<String, dynamic>>({'importId': importId});
    return (result.data['deleted'] as num?)?.toInt() ?? 0;
  }

  Future<void> archiveWalkInImport(
    String importId, {
    required bool archived,
  }) async {
    if (currentAccessRole != AccessRole.admin) {
      throw StateError('Administrator access is required.');
    }
    await FirebaseFunctions.instance
        .httpsCallable('archiveWalkInImport')
        .call<Map<String, dynamic>>({
          'importId': importId,
          'archived': archived,
        });
  }

  Stream<List<AdminAssessmentRecord>> watchAssessments() => _firestoreService
      .watchDocuments(FirestoreCollections.assessments)
      .map(
        (items) =>
            items.map(AdminAssessmentRecord.fromJson).toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  Future<void> setAssessmentArchived(String assessmentId, bool archived) {
    final actor = FirebaseAuth.instance.currentUser;
    if (actor == null || !currentAccessRole.canAccessClinicalData) {
      throw StateError('Clinical staff access is required.');
    }
    return _firestoreService.updateDocument(
      FirestoreCollections.assessments,
      assessmentId,
      archived
          ? {
              'archivedAt': FieldValue.serverTimestamp(),
              'archivedBy': actor.uid,
            }
          : {
              'archivedAt': FieldValue.delete(),
              'archivedBy': FieldValue.delete(),
            },
    );
  }

  /// Raw inquiry details visible to this session. Firestore rules restrict raw
  /// inquiries strictly to the super-administrator (all) and assigned
  /// counselors (`assigneeIds array-contains uid`). Operational portalStaff must
  /// use [watchInquiryStatuses] instead and never fall back to raw reads.
  Stream<List<AdminInquiryModel>> watchInquiries() {
    final uid = currentUserId;
    final role = currentAccessRole;
    if (!isSuperAdmin && (role != AccessRole.counselor || uid == null)) {
      return Stream.error(
        StateError(
          'Raw inquiries are visible only to assigned counselors and the super-administrator.',
        ),
      );
    }
    return _firestoreService
        .watchDocuments(
          FirestoreCollections.inquiries,
          whereArrayContains: isSuperAdmin ? const {} : {'assigneeIds': uid},
        )
        .map(
          (items) => scopeInquiriesForRole(
            items
                .map(
                  (item) => AdminInquiryModel.fromJson(
                    item,
                    id: item['id']?.toString(),
                  ),
                )
                .toList(),
            role: role,
            uid: uid,
            isSuperAdmin: isSuperAdmin,
          )..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  /// Sanitized operational inquiry status projection for operational
  /// monitoring staff (`monitoringStaffIds array-contains uid`) and the
  /// super-administrator. Never queries raw `inquiries` as a fallback.
  Stream<List<AdminInquiryModel>> watchInquiryStatuses() {
    final uid = currentUserId;
    final role = currentAccessRole;
    if (!isSuperAdmin && (role != AccessRole.portalStaff || uid == null)) {
      return Stream.error(
        StateError(
          'Operational inquiry statuses are visible only to assigned monitoring staff and the super-administrator.',
        ),
      );
    }
    return _firestoreService
        .watchDocuments(
          FirestoreCollections.inquiryStatuses,
          whereArrayContains: isSuperAdmin
              ? const {}
              : {'monitoringStaffIds': uid},
        )
        .map(
          (items) => scopeInquiriesForRole(
            items
                .map(
                  (item) => AdminInquiryModel.fromOperationalProjection(
                    item,
                    id: item['id']?.toString(),
                  ),
                )
                .toList(),
            role: role,
            uid: uid,
            isSuperAdmin: isSuperAdmin,
          )..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  Stream<List<AdminActivityAnalyticsModel>> watchActivityAnalytics() =>
      _firestoreService
          .watchDocuments(FirestoreCollections.analyticsDaily)
          .map(
            (items) =>
                items.map(AdminActivityAnalyticsModel.fromJson).toList()
                  ..sort((a, b) => b.dateKey.compareTo(a.dateKey)),
          );

  Stream<List<AdminMindAidAnalyticsModel>> watchMindAidAnalytics() =>
      _firestoreService
          .watchDocuments(FirestoreCollections.mindAidAnalyticsDaily)
          .map(
            (items) =>
                items.map(AdminMindAidAnalyticsModel.fromJson).toList()
                  ..sort((a, b) => b.dateKey.compareTo(a.dateKey)),
          );

  /// Clinical appointment callables keep their existing transport; tests may
  /// inject [AdminCallableInvoker] instead.
  Future<Object?> _clinicalAppointmentCallable(
    String name,
    Map<String, Object?> data,
  ) async {
    final invoker = _callableInvoker;
    if (invoker != null) return invoker(name, data);
    final result = await FirebaseFunctions.instance
        .httpsCallable(name)
        .call<Object?>(data);
    return result.data;
  }

  /// [exceptionReason] is the super-administrator's written reason for acting
  /// on an appointment a college counselor is assigned to.
  Future<void> initializeAppointmentScheduleRevision({
    required String appointmentId,
    required DateTime scheduledAt,
    required String status,
    String? exceptionReason,
  }) async {
    await _clinicalAppointmentCallable(
      'initializeAppointmentScheduleRevision',
      {
        'appointmentId': appointmentId,
        'expectedScheduledAt': scheduledAt.millisecondsSinceEpoch,
        'expectedStatus': status,
        'exceptionReason': ?exceptionReason,
      },
    );
  }

  Future<void> changeAppointmentAgreement(
    AppointmentModel appointment,
    String action,
    String requestId, {
    String? exceptionReason,
  }) async {
    await _clinicalAppointmentCallable('changeAppointmentAgreement', {
      'appointmentId': appointment.id,
      'action': action,
      'requestId': requestId,
      'expectedScheduledAt': appointment.scheduledAt.millisecondsSinceEpoch,
      'expectedScheduleRevision': appointment.scheduleRevision,
      'expectedProposalRevision': appointment.proposalRevision,
      'exceptionReason': ?exceptionReason,
    });
  }

  /// "My College's Approvals" for counselors; approval exceptions for the
  /// super-administrator. Server-computed from live college assignments with
  /// cursor-based pagination.
  Future<AppointmentApprovalsPage> listAppointmentApprovalsPage({
    String? cursor,
    int limit = 50,
  }) async {
    final payload = <String, Object?>{
      'limit': limit,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final result = await _callCallable('listAppointmentApprovals', payload);
    final data = result is Map
        ? Map<String, dynamic>.from(result)
        : const <String, dynamic>{};
    return AppointmentApprovalsPage.fromJson(data);
  }

  /// Convenience wrapper returning the first page of approvals.
  Future<List<AppointmentApprovalItem>> listAppointmentApprovals() async =>
      (await listAppointmentApprovalsPage()).items;

  /// Fetches an authorized single pending appointment record via the
  /// server-enforced `getAppointmentForApproval` callable when an item in the
  /// paginated approvals queue is outside the currently streamed local list.
  Future<AppointmentModel?> fetchAppointmentById(String appointmentId) async {
    final id = appointmentId.trim();
    if (id.isEmpty) return null;
    if (currentAccessRole != AccessRole.counselor &&
        !(currentAccessRole == AccessRole.admin && isSuperAdmin)) {
      return null;
    }
    final result = await _callCallable('getAppointmentForApproval', {
      'appointmentId': id,
    });
    if (result is! Map) return null;
    final payload = Map<String, dynamic>.from(result);
    if (payload['available'] != true) return null;
    final raw = payload['appointment'];
    if (raw is! Map) return null;
    final data = Map<String, dynamic>.from(raw);
    return AppointmentModel.fromJson(data, id: id);
  }

  Future<SessionEvidenceRecord?> getClinicalSessionEvidence(
    String appointmentId,
  ) async {
    final snapshot = await _firestoreService.firestore
        .collection('appointments')
        .doc(appointmentId)
        .collection('clinical_notes')
        .doc('session')
        .get();
    final data = snapshot.data();
    return data == null ? null : SessionEvidenceRecord.fromJson(data);
  }

  static final RegExp _clinicalEvidencePathPattern = RegExp(
    r'^counseling_session_files/([A-Za-z0-9_-]{1,120})/([A-Za-z0-9_-]{1,120})/([a-f0-9]{32}\.(jpg|jpeg|png|pdf|doc|docx))$',
  );

  /// Downloads private session evidence through the server-authorized callable.
  /// No public Storage download token or signed URL is produced.
  Future<Uint8List> getClinicalEvidenceBytes(
    String path, {
    String? appointmentId,
  }) async {
    if (path.contains('..') ||
        path.contains('\\') ||
        path.contains('%') ||
        RegExp(r'[\x00-\x1f]').hasMatch(path)) {
      throw const FormatException('Not a clinical attachment path.');
    }
    final match = _clinicalEvidencePathPattern.firstMatch(path);
    if (match == null) {
      throw const FormatException('Not a clinical attachment path.');
    }
    final pathAppointmentId = match.group(1)!;
    final resolvedAppointmentId = appointmentId == null
        ? pathAppointmentId
        : appointmentId.trim();
    if (resolvedAppointmentId.isEmpty ||
        resolvedAppointmentId != pathAppointmentId) {
      throw const FormatException(
        'Attachment does not belong to this appointment.',
      );
    }
    final raw = await _callCallable('downloadClinicalSessionEvidence', {
      'appointmentId': resolvedAppointmentId,
      'path': path,
    });
    if (raw is! Map) {
      throw StateError('Attachment unavailable.');
    }
    final encoded = raw['dataBase64'];
    if (encoded is! String || encoded.trim().isEmpty) {
      throw StateError('Attachment unavailable.');
    }
    final bytes = base64Decode(encoded.trim());
    if (bytes.isEmpty || bytes.length > maxSessionEvidenceFileBytes) {
      throw StateError('Attachment unavailable.');
    }
    return bytes;
  }

  /// Uploads are immutable and bound to the currently authenticated clinician.
  /// They are referenced in clinical_notes only after server verification.
  Future<List<SessionEvidenceAttachment>> uploadClinicalEvidenceFiles({
    required String appointmentId,
    required List<PendingSessionEvidenceFile> files,
  }) async {
    if (currentAccessRole != AccessRole.counselor || isSuperAdmin) {
      throw StateError(
        'Clinical session attachment uploads are restricted to assigned college counselors.',
      );
    }
    if (files.isEmpty) return const [];
    if (files.length > maxSessionEvidenceFiles) {
      throw const FormatException('Choose no more than five files.');
    }
    final uid = currentUserId;
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Sign in again to upload attachments.');
    }
    final attachments = <SessionEvidenceAttachment>[];
    for (final file in files) {
      final mime = sessionEvidenceMimeType(file.name);
      if (!validSessionEvidenceFileName(file.name) ||
          mime == null ||
          mime != file.contentType ||
          file.size == 0 ||
          file.size > maxSessionEvidenceFileBytes) {
        throw const FormatException('Unsupported file or file size.');
      }
      final result = await _callCallable('uploadClinicalSessionEvidence', {
        'appointmentId': appointmentId,
        'name': file.name,
        'contentType': file.contentType,
        'size': file.size,
        'dataBase64': base64Encode(file.bytes),
      });
      final path = result is Map ? result['path'] : null;
      final match = path is String
          ? _clinicalEvidencePathPattern.firstMatch(path)
          : null;
      if (path is! String ||
          match?.group(1) != appointmentId ||
          match?.group(2) != uid) {
        throw StateError('Attachment upload could not be verified.');
      }
      attachments.add(
        SessionEvidenceAttachment(
          path: path,
          name: file.name,
          contentType: file.contentType,
          size: file.size,
        ),
      );
    }
    return attachments;
  }

  Future<void> reviewAppointment({
    required String appointmentId,
    required String action,
    required String reply,
    int? expectedScheduledAt,
    required int expectedScheduleRevision,
    int expectedProposalRevision = 0,
    required String expectedStatus,
    DateTime? proposedScheduledAt,
    String? proposedScheduledTime,
    String? rescheduleReason,
    String? sessionSummary,
    List<SessionEvidenceAttachment> attachments = const [],
    bool offerFollowUp = false,
    String? followUpMessage,
    String? exceptionReason,
  }) async {
    final data = <String, Object?>{
      'appointmentId': appointmentId,
      'action': action,
      'reply': reply,
      'expectedScheduledAt': ?expectedScheduledAt,
      'expectedScheduleRevision': expectedScheduleRevision,
      'expectedProposalRevision': expectedProposalRevision,
      'expectedStatus': expectedStatus,
      if (proposedScheduledAt != null)
        'proposedScheduledAt': proposedScheduledAt.millisecondsSinceEpoch,
      if (proposedScheduledAt != null)
        'proposedScheduledDate':
            '${proposedScheduledAt.year.toString().padLeft(4, '0')}-${proposedScheduledAt.month.toString().padLeft(2, '0')}-${proposedScheduledAt.day.toString().padLeft(2, '0')}',
    };
    if (proposedScheduledTime != null) {
      data['proposedScheduledTime'] = proposedScheduledTime;
    }
    if (rescheduleReason != null) data['rescheduleReason'] = rescheduleReason;
    if (sessionSummary != null) {
      data['sessionSummary'] = sessionSummary;
      data['attachments'] = attachments.map((file) => file.toJson()).toList();
    }
    if (offerFollowUp) data['offerFollowUp'] = true;
    if (followUpMessage != null) data['followUpMessage'] = followUpMessage;
    if (exceptionReason != null) data['exceptionReason'] = exceptionReason;
    await _clinicalAppointmentCallable('reviewAppointment', data);
  }

  Future<void> reviewProfileVerification({
    required String userId,
    required VerificationStatus decision,
    required String reason,
  }) async {
    await FirebaseFunctions.instance
        .httpsCallable('reviewProfileVerification')
        .call({
          'userId': userId,
          'decision': decision.storedValue,
          'reason': reason.trim(),
        });
  }

  Future<void> assignAccessRole({
    required String userId,
    required AccessRole accessRole,
    required String reason,
  }) async {
    await FirebaseFunctions.instance.httpsCallable('assignAccessRole').call({
      'userId': userId,
      'accessRole': accessRole.storedValue,
      'reason': reason.trim(),
    });
  }

  Future<void> reviewStaffRegistration({
    required String userId,
    required bool approve,
    required AccessRole accessRole,
    required String reason,
    String? decision,
  }) =>
      FirebaseFunctions.instance.httpsCallable('reviewStaffRegistration').call({
        'userId': userId,
        'approve': approve,
        'accessRole': accessRole.storedValue,
        'reason': reason.trim(),
        'decision': ?decision,
      });

  Future<void> setStaffAccountEnabled({
    required String userId,
    required bool enabled,
    required String reason,
  }) => FirebaseFunctions.instance.httpsCallable('setStaffAccountEnabled').call(
    {'userId': userId, 'enabled': enabled, 'reason': reason.trim()},
  );

  Future<int> bulkManageStaffAccounts({
    required List<String> userIds,
    required String action,
    required String reason,
  }) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('bulkManageStaffAccounts')
        .call<Map<String, dynamic>>({
          'userIds': userIds,
          'action': action,
          'reason': reason.trim(),
        });
    return (result.data['affected'] as num?)?.toInt() ?? userIds.length;
  }

  Future<int> archiveAppointments({
    required List<String> appointmentIds,
    required bool archived,
  }) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('archiveAppointments')
        .call<Map<String, dynamic>>({
          'appointmentIds': appointmentIds,
          'archived': archived,
        });
    return (result.data['affected'] as num?)?.toInt() ?? appointmentIds.length;
  }

  Future<void> saveOrganizationRecord({
    required String kind,
    String? id,
    required String name,
    required String code,
    required bool active,
    String collegeId = '',
    String departmentId = '',
  }) =>
      FirebaseFunctions.instance.httpsCallable('saveOrganizationRecord').call({
        'kind': kind,
        'id': ?id,
        'name': name,
        'code': code,
        'active': active,
        'collegeId': collegeId,
        'departmentId': departmentId,
      });

  Future<void> archiveOrganizationRecord({
    required String kind,
    required String id,
    required bool archived,
  }) => FirebaseFunctions.instance
      .httpsCallable('archiveOrganizationRecord')
      .call({'kind': kind, 'id': id, 'archived': archived});

  Future<int> initializeAcademicStructure() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('initializeAcademicStructure')
        .call<Map<String, dynamic>>();
    return (result.data['colleges'] as num?)?.toInt() ?? 0;
  }

  /// Replaces the colleges an authorized counselor serves. Authorization,
  /// uniqueness, and revision checks happen server-side; returns the new
  /// revision. Legacy portal staff accounts only permit removal/cleanup.
  Future<int> setStaffCollegeAssignments({
    required String userId,
    required List<String> collegeIds,
    required int expectedRevision,
    required String reason,
  }) async {
    final result = await _callCallable('setStaffCollegeAssignments', {
      'userId': userId,
      'collegeIds': collegeIds,
      'expectedRevision': expectedRevision,
      'reason': reason,
    });
    final data = result is Map ? result : const {};
    return (data['revision'] as num?)?.toInt() ?? expectedRevision;
  }

  /// Atomically assigns, transfers, unassigns, or resolves a duplicate
  /// counselor conflict for one college across all affected counselor accounts.
  Future<Map<String, int>> reassignCollegeCounselor({
    required String collegeId,
    required String? toCounselorId,
    required List<String> expectedOwnerIds,
    required Map<String, int> expectedRevisions,
    required String reason,
  }) async {
    final result = await _callCallable('reassignCollegeCounselor', {
      'collegeId': collegeId,
      'toCounselorId': toCounselorId,
      'expectedOwnerIds': expectedOwnerIds,
      'expectedRevisions': expectedRevisions,
      'reason': reason,
    });
    final data = result is Map ? result : const {};
    final rawRevisions = data['revisions'];
    if (rawRevisions is! Map) return const {};
    return {
      for (final entry in rawRevisions.entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).toInt(),
    };
  }

  Future<void> updateStaffOrganization({
    required String userId,
    required String departmentId,
    required String collegeId,
    required String courseId,
    required String reason,
  }) =>
      FirebaseFunctions.instance.httpsCallable('updateStaffOrganization').call({
        'userId': userId,
        'departmentId': departmentId,
        'collegeId': collegeId,
        'courseId': courseId,
        'reason': reason,
      });

  Future<void> reviewRoleCorrection({
    required String requestId,
    required bool approve,
    required String reason,
  }) async {
    await FirebaseFunctions.instance.httpsCallable('reviewRoleCorrection').call(
      {'requestId': requestId, 'approve': approve, 'reason': reason.trim()},
    );
  }

  /// Status changes are audited server-side; clients cannot write inquiries.
  /// Pass [expectedRevision] to reject the change if someone acted first.
  Future<void> updateInquiryStatus(
    String id,
    InquiryStatus status, {
    int? expectedRevision,
  }) => _callCallable('setInquiryStatus', {
    'inquiryId': id,
    'status': status.storedValue,
    'expectedRevision': ?expectedRevision,
  });

  /// Marks an acknowledged (in-progress) inquiry as resolved server-side.
  /// Pass [expectedRevision] to reject the change if someone acted first.
  Future<void> resolveInquiry(String id, {int? expectedRevision}) =>
      _callCallable('resolveInquiry', {
        'inquiryId': id,
        'expectedRevision': ?expectedRevision,
      });

  /// Assignee or super-administrator posts an authored reply; returns the
  /// new revision. [requestId] makes retries return the original reply.
  Future<int> replyToInquiry(
    String id, {
    required String message,
    required int expectedRevision,
    required String requestId,
  }) async {
    final result = await _callCallable('replyToInquiry', {
      'inquiryId': id,
      'message': message,
      'expectedRevision': expectedRevision,
      'requestId': requestId,
    });
    final data = result is Map ? result : const {};
    return (data['revision'] as num?)?.toInt() ?? expectedRevision;
  }

  /// Super-administrator takes over an unresolved inquiry.
  Future<int> takeOverInquiry(
    String id, {
    required int expectedRevision,
    required String reason,
  }) async {
    final result = await _callCallable('takeOverInquiry', {
      'inquiryId': id,
      'expectedRevision': expectedRevision,
      'reason': reason,
    });
    final data = result is Map ? result : const {};
    return (data['revision'] as num?)?.toInt() ?? expectedRevision;
  }

  /// Super-administrator chooses the response target (24, 48 or 72 hours).
  Future<void> setInquirySla(int hours) =>
      _callCallable('setInquirySla', {'hours': hours});

  /// The configured response target; unset until the super-admin chooses one.
  Stream<InquirySla> watchInquirySla() => _firestoreService
      .watchDocument('system_config', 'inquiry_sla')
      .map(InquirySla.fromJson);

  /// Reply timeline, oldest first. Rules limit it to the inquiry's readers.
  Stream<List<InquiryReply>> watchInquiryReplies(String inquiryId) =>
      _firestoreService
          .watchDocuments(
            '${FirestoreCollections.inquiries}/$inquiryId/replies',
            orderBy: 'createdAt',
            descending: false,
          )
          .map(
            (items) => items
                .map(
                  (item) => InquiryReply.fromJson(
                    item,
                    id: item['id']?.toString() ?? '',
                  ),
                )
                .toList(),
          );

  /// Pass [expectedRevision] so the server rejects a stale view.
  Future<void> acknowledgeInquiry(String id, {int? expectedRevision}) =>
      _callCallable('acknowledgeInquiry', {
        'inquiryId': id,
        'expectedRevision': ?expectedRevision,
      });

  /// Assignee asks the super-administrator to review the inquiry.
  Future<void> escalateInquiry(
    String id, {
    InquiryEscalationType? escalationType,
    String? reason,
    int? expectedRevision,
  }) {
    final trimmedReason = reason?.trim();
    if (trimmedReason != null && trimmedReason.isNotEmpty) {
      if (trimmedReason.length < 3 || trimmedReason.length > 500) {
        throw ArgumentError.value(
          reason,
          'reason',
          'Reason must be 3-500 characters.',
        );
      }
      if (escalationType == InquiryEscalationType.counselorConfirmation) {
        throw ArgumentError.value(
          escalationType,
          'escalationType',
          'counselorConfirmation cannot include a free-text reason.',
        );
      }
    } else if (reason != null) {
      throw ArgumentError.value(
        reason,
        'reason',
        'Reason must be 3-500 characters.',
      );
    } else if (escalationType != InquiryEscalationType.counselorConfirmation) {
      throw escalationType == InquiryEscalationType.staffReasoned
          ? ArgumentError.value(
              reason,
              'reason',
              'Reason must be 3-500 characters.',
            )
          : ArgumentError(
              'Either escalationType or a 3-500 character reason is required.',
            );
    }
    return _callCallable('escalateInquiry', {
      'inquiryId': id,
      if (escalationType != null) 'escalationType': escalationType.storedValue,
      if (trimmedReason != null && trimmedReason.isNotEmpty)
        'reason': trimmedReason,
      'expectedRevision': ?expectedRevision,
    });
  }

  /// Super-administrator replaces the clinical counselors (and optionally
  /// operational monitoring staff); returns the new revision.
  Future<int> reassignInquiry(
    String id, {
    required List<String> assigneeIds,
    List<String>? monitoringStaffIds,
    required int expectedRevision,
    required String reason,
  }) async {
    final result = await _callCallable('reassignInquiry', {
      'inquiryId': id,
      'assigneeIds': assigneeIds,
      'monitoringStaffIds': ?monitoringStaffIds,
      'expectedRevision': expectedRevision,
      'reason': reason,
    });
    final data = result is Map ? result : const {};
    return (data['revision'] as num?)?.toInt() ?? expectedRevision;
  }

  /// Super-administrator routes inquiries created before college routing,
  /// one bounded batch per call. Resume with the returned cursor until done.
  Future<InquiryRoutingBackfillResult> routeExistingInquiries({
    int limit = 100,
    String? cursor,
  }) async {
    final result = await _callCallable('routeExistingInquiries', {
      'limit': limit,
      'cursor': ?cursor,
    });
    final data = result is Map ? result : const {};
    int count(String key) => (data[key] as num?)?.toInt() ?? 0;
    final next = data['nextCursor']?.toString();
    return InquiryRoutingBackfillResult(
      routed: count('routed'),
      needsTriage: count('needsTriage'),
      // Absent or malformed responses are never treated as finished.
      done: data['done'] == true,
      nextCursor: next == null || next.isEmpty ? null : next,
    );
  }

  Stream<PaccAvailabilityModel?> watchPaccAvailability() =>
      _paccAvailabilityRepository.watchCurrent();

  Future<PaccAvailabilitySaveResult> savePaccAvailability(
    PaccAvailabilityModel availability, {
    bool confirmConflicts = false,
  }) {
    if (!currentAccessRole.canAccessClinicalData) {
      throw StateError('Counselor or administrator access is required.');
    }
    return _paccAvailabilityRepository.savePaccAvailability(
      availability,
      confirmConflicts: confirmConflicts,
    );
  }

  Future<void> updateOwnProfile(String userId, Map<String, dynamic> values) =>
      _firestoreService.updateDocument(
        FirestoreCollections.users,
        userId,
        values,
      );

  Future<Map<String, dynamic>?> getOwnProfile(String userId) =>
      _firestoreService.getDocument(FirestoreCollections.users, userId);

  Stream<Map<String, dynamic>?> watchOwnProfile(String userId) =>
      _firestoreService.watchDocument(FirestoreCollections.users, userId);
}
