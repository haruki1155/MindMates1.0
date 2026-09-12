import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../database/firestore_collections.dart';
import '../models/admin_inquiry_model.dart';
import '../models/admin_activity_analytics_model.dart';
import '../models/admin_mind_aid_analytics_model.dart';
import '../models/appointment_model.dart';
import '../models/app_notification_model.dart';
import '../models/user_model.dart';
import '../models/profile_roles.dart';
import '../models/pacc_availability_model.dart';
import '../features/admin/domain/admin_management_models.dart';
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
    this.role,
    this.archivedAt,
  });

  final String id;
  final String userId;
  final String type;
  final DateTime createdAt;
  final num? score;
  final String? status;
  final String? role;
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

  factory AdminAssessmentRecord.fromJson(Map<String, dynamic> data) =>
      AdminAssessmentRecord(
        id: data['id']?.toString() ?? '',
        userId: data['userId']?.toString() ?? '',
        type: data['type']?.toString() ?? 'Assessment',
        createdAt: _date(data['createdAt']),
        score: data['score'] is num
            ? data['score'] as num
            : num.tryParse('${data['score']}'),
        status: _text(data['status'] ?? data['overallLevel']),
        role: _text(data['populationRole'] ?? data['role']),
        archivedAt: data['archivedAt'] == null
            ? null
            : _date(data['archivedAt']),
      );

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

class AdminPortalRepository {
  AdminPortalRepository({FirestoreService? firestoreService})
    : _firestoreService = firestoreService ?? FirestoreService();

  final FirestoreService _firestoreService;
  AccessRole _currentAccessRole = AccessRole.appUser;
  AccessRole get currentAccessRole => _currentAccessRole;
  bool _isSuperAdmin = false;
  bool get isSuperAdmin => _isSuperAdmin;
  bool _mustChangePassword = false;
  bool get mustChangePassword => _mustChangePassword;

  Future<void> signInStaff({
    required String schoolId,
    required String password,
  }) async {
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: schoolId.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) throw StateError('Unable to identify staff account.');
    final profile = await _firestoreService.getDocument(
      FirestoreCollections.users,
      user.uid,
    );
    final role = AccessRole.parse(
      profile?['accessRole'],
      legacyRole: profile?['role'],
    );
    final status = StaffAccountStatus.parse(profile?['staffAccountStatus']);
    _mustChangePassword = profile?['mustChangePassword'] == true;
    if (status == StaffAccountStatus.pending) {
      final requested = AccessRole.parse(
        profile?['requestedRole'] ?? profile?['requestedAccessRole'],
      );
      final roleLabel = requested == AccessRole.counselor
          ? 'Counselor'
          : 'PAACC Staff';
      final requestState =
          profile?['registrationStatus'] == 'more_information_required'
          ? 'More information is required from you. Contact the PAACC administrator.'
          : 'Your PAACC portal access request for $roleLabel is awaiting administrator review.';
      throw StateError(requestState);
    }
    if (status == StaffAccountStatus.rejected) {
      await FirebaseAuth.instance.signOut();
      throw StateError(
        'Your staff registration was rejected. Contact the administrator.',
      );
    }
    if (status == StaffAccountStatus.disabled) {
      await FirebaseAuth.instance.signOut();
      throw StateError('This staff account is disabled.');
    }
    if (!role.canUsePortal) {
      await FirebaseAuth.instance.signOut();
      throw StateError('This account does not have staff access.');
    }
    _currentAccessRole = role;
    if (role == AccessRole.admin) {
      _isSuperAdmin = await _confirmSuperAdmin();
    }
    await _tryRecordAudit(
      action: 'STAFF_SIGNED_IN',
      category: 'AUTHENTICATION',
    );
  }

  User? get currentAuthUser => FirebaseAuth.instance.currentUser;
  Stream<User?> get authStateChanges =>
      FirebaseAuth.instance.authStateChanges();

  Future<bool> restoreSession() async {
    final user = currentAuthUser;
    if (user == null) return false;
    final profile = await _firestoreService.getDocument(
      FirestoreCollections.users,
      user.uid,
    );
    final status = StaffAccountStatus.parse(profile?['staffAccountStatus']);
    _mustChangePassword = profile?['mustChangePassword'] == true;
    final role = AccessRole.parse(
      profile?['accessRole'],
      legacyRole: profile?['role'],
    );
    if (status == StaffAccountStatus.approved ||
        (status == null && role.canUsePortal)) {
      _currentAccessRole = role;
      if (role == AccessRole.admin) {
        _isSuperAdmin = await _confirmSuperAdmin();
      }
      return role.canUsePortal;
    }
    return false;
  }

  Future<bool> registerStaff({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String employeeId,
    required String position,
    required AccessRole requestedRole,
  }) async {
    final credential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
    try {
      await FirebaseFunctions.instance
          .httpsCallable('registerStaffAccount')
          .call({
            'firstName': firstName.trim(),
            'lastName': lastName.trim(),
            'employeeId': employeeId.trim(),
            'position': position.trim(),
            'requestedRole': requestedRole.storedValue,
          });
    } catch (error) {
      // A callable response can be lost after its Firestore transaction has
      // committed. Reconcile before deleting Auth, otherwise a valid request
      // can be left with no sign-in account or an orphaned profile.
      Map<String, dynamic>? profile;
      try {
        profile = await getOwnProfile(credential.user!.uid);
      } catch (_) {
        // Preserve the original registration error if reconciliation itself
        // is unavailable.
      }
      if (profile == null || profile['accessRequestId'] == null) {
        await credential.user?.delete();
        rethrow;
      }
    }
    try {
      await credential.user?.sendEmailVerification();
      return true;
    } catch (_) {
      // The access request is already safely stored. Let the user retry the
      // verification email from the normal verification flow.
      return false;
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
      // The caller is already an authorized portal administrator. Fall back to
      // the protected Firestore read while a callable/index is propagating.
      final items = await _firestoreService.getDocuments(
        FirestoreCollections.adminAuditLogs,
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

  Stream<List<AppointmentModel>> watchAppointments() => _firestoreService
      .watchDocuments(
        FirestoreCollections.appointments,
        whereEquals: currentAccessRole == AccessRole.counselor
            ? {'assignedStaffId': currentAuthUser?.uid ?? ''}
            : const {},
      )
      .map(
        (items) =>
            items
                .map(
                  (item) => AppointmentModel.fromJson(
                    item,
                    id: item['id']?.toString(),
                  ),
                )
                .toList()
              ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt)),
      );

  Stream<List<AppNotificationModel>> watchPortalNotifications() {
    final userId = currentAuthUser?.uid;
    if (userId == null || !currentAccessRole.canUsePortal) {
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
              .where((item) => item.audience == 'portal' && !item.isArchived)
              .toList(growable: false),
        );
  }

  Future<void> markPortalNotificationRead(String notificationId) {
    if (!currentAccessRole.canUsePortal) {
      throw StateError('Portal access is required.');
    }
    return _firestoreService.updateDocument(
      FirestoreCollections.notifications,
      notificationId,
      {'readAt': FieldValue.serverTimestamp()},
    );
  }

  Future<AdminReportAnalytics> fetchReportAnalytics({
    String userCategory = 'all',
    String appointmentDepartment = 'all',
    String? schoolYear,
  }) async {
    if (!currentAccessRole.canAccessClinicalData) {
      throw StateError('Counselor or administrator access is required.');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('getReportAnalytics')
        .call<Map<String, dynamic>>({
          'userCategory': userCategory,
          'appointmentDepartment': appointmentDepartment,
          'schoolYear': ?schoolYear,
        });
    final raw = result.data['report'];
    if (raw is! Map) {
      throw StateError('The report service returned an invalid response.');
    }
    return AdminReportAnalytics.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<CounselingPopulationConfig> fetchCounselingPopulation(
    String schoolYear,
  ) async {
    if (!currentAccessRole.canAccessClinicalData) {
      throw StateError('Counselor or administrator access is required.');
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
    if (!currentAccessRole.canAccessClinicalData) {
      throw StateError('Counselor or administrator access is required.');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('saveCounselingPopulation')
        .call<Map<String, dynamic>>({
          'schoolYear': schoolYear,
          'populations': populations,
        });
    return CounselingPopulationConfig.fromJson(result.data);
  }

  Future<List<AcademicYearRecord>> createAcademicYear({
    required String schoolYear,
    String? copyFrom,
    bool copyPopulation = false,
  }) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('createAcademicYear')
        .call<Map<String, dynamic>>({
          'schoolYear': schoolYear,
          'copyFrom': ?copyFrom,
          'copyPopulation': copyPopulation,
        });
    return _academicYears(result.data);
  }

  Future<List<AcademicYearRecord>> closeAcademicYear(String schoolYear) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('closeAcademicYear')
        .call<Map<String, dynamic>>({'schoolYear': schoolYear});
    return _academicYears(result.data);
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
    List<WalkInAppointmentImportRow> rows,
  ) async {
    if (!currentAccessRole.canAccessClinicalData) {
      throw StateError('Counselor or administrator access is required.');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('importWalkInAppointments')
        .call<Map<String, dynamic>>({
          'rows': rows.map((row) => row.toJson()).toList(growable: false),
        });
    return (result.data['imported'] as num?)?.toInt() ?? rows.length;
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

  Stream<List<AdminInquiryModel>> watchInquiries() => _firestoreService
      .watchDocuments(FirestoreCollections.inquiries)
      .map(
        (items) =>
            items
                .map(
                  (item) => AdminInquiryModel.fromJson(
                    item,
                    id: item['id']?.toString(),
                  ),
                )
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

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

  Future<void> reviewAppointment({
    required String appointmentId,
    required String action,
    required String reply,
    DateTime? proposedScheduledAt,
    String? proposedScheduledTime,
  }) async {
    final data = <String, dynamic>{
      'appointmentId': appointmentId,
      'action': action,
      'reply': reply,
      if (proposedScheduledAt != null)
        'proposedScheduledAt': proposedScheduledAt.millisecondsSinceEpoch,
    };
    if (proposedScheduledTime != null) {
      data['proposedScheduledTime'] = proposedScheduledTime;
    }
    await FirebaseFunctions.instance
        .httpsCallable('reviewAppointment')
        .call(data);
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

  Future<void> saveOrganizationRecord({
    required String kind,
    String? id,
    required String name,
    required String code,
    required bool active,
    String collegeId = '',
  }) =>
      FirebaseFunctions.instance.httpsCallable('saveOrganizationRecord').call({
        'kind': kind,
        'id': ?id,
        'name': name,
        'code': code,
        'active': active,
        'collegeId': collegeId,
      });

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

  Future<void> updateInquiryStatus(String id, InquiryStatus status) =>
      _firestoreService.updateDocument(FirestoreCollections.inquiries, id, {
        'status': status.storedValue,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> acknowledgeInquiry(String id) => FirebaseFunctions.instance
      .httpsCallable('acknowledgeInquiry')
      .call({'inquiryId': id});

  Stream<PaccAvailabilityModel?> watchPaccAvailability() => _firestoreService
      .watchDocument(FirestoreCollections.paccAvailability, 'current')
      .map(
        (data) => data == null ? null : PaccAvailabilityModel.fromJson(data),
      );

  Future<void> savePaccAvailability(PaccAvailabilityModel availability) =>
      _firestoreService.setDocument(
        FirestoreCollections.paccAvailability,
        'current',
        {...availability.toJson(), 'updatedAt': FieldValue.serverTimestamp()},
        merge: true,
      );

  Future<void> updateOwnProfile(String userId, Map<String, dynamic> values) =>
      _firestoreService.updateDocument(
        FirestoreCollections.users,
        userId,
        values,
      );

  /// Reads the signed-in portal user's Firestore profile. Staff registration
  /// stores the submitted identity here rather than in Firebase Auth.
  Future<Map<String, dynamic>?> getOwnProfile(String userId) =>
      _firestoreService.getDocument(FirestoreCollections.users, userId);

  /// Watches the signed-in portal user's profile so the header updates when
  /// the profile name or phone number changes.
  Stream<Map<String, dynamic>?> watchOwnProfile(String userId) =>
      _firestoreService.watchDocument(FirestoreCollections.users, userId);
}
