// ignore_for_file: prefer_initializing_formals
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/student_personal_info.dart';
import '../models/student_roster_models.dart';
import '../services/firebase/firebase_callable_router.dart';

/// Invokes a callable by its protected name and returns the response data.
typedef StudentRosterCallableInvoker =
    Future<Object?> Function(String name, Map<String, Object?> data);

/// An active college or course the student may pick when requesting a
/// correction. [collegeId] is empty for colleges.
class AcademicOption {
  const AcademicOption({
    required this.id,
    required this.name,
    this.collegeId = '',
  });

  final String id;
  final String name;
  final String collegeId;
}

typedef AcademicOptions = ({
  List<AcademicOption> colleges,
  List<AcademicOption> courses,
});

typedef AcademicOptionsLoader = Future<AcademicOptions> Function();

class RecoveryCodeRequest {
  const RecoveryCodeRequest({
    this.alreadyVerified = false,
    this.maskedEmail = '',
    this.expiresInSeconds = 0,
  });

  final bool alreadyVerified;
  final String maskedEmail;
  final int expiresInSeconds;
}

class StudentRosterRepository {
  StudentRosterRepository({
    FirebaseFunctions? functions,
    StudentRosterCallableInvoker? invoker,
    AcademicOptionsLoader? academicLoader,
  }) : _functions = functions,
       _invoker = invoker,
       _academicLoader = academicLoader;

  final AcademicOptionsLoader? _academicLoader;

  /// Active colleges and courses (client-readable catalogue collections),
  /// queried the same way the server validates correction ids.
  Future<AcademicOptions> listAcademicOptions() async {
    final loader = _academicLoader;
    if (loader != null) return loader();
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('colleges').where('active', isEqualTo: true).get(),
      db.collection('courses').where('active', isEqualTo: true).get(),
    ]);
    List<AcademicOption> read(QuerySnapshot<Map<String, dynamic>> snap) => [
      for (final d in snap.docs)
        AcademicOption(
          id: d.id,
          name: asText(d.data()['name']),
          collegeId: asText(d.data()['collegeId']),
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return (colleges: read(results[0]), courses: read(results[1]));
  }

  final FirebaseFunctions? _functions;
  final StudentRosterCallableInvoker? _invoker;

  Future<Object?> _call(
    String name, [
    Map<String, Object?> data = const {},
    HttpsCallableOptions? options,
  ]) {
    final invoker = _invoker;
    if (invoker != null) return invoker(name, data);
    final functions =
        _functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
    return functions
        .routedCallable(name, options: options)
        .call<Object?>(data)
        .then((result) => result.data);
  }

  Future<Map<String, Object?>> _callMap(
    String name, [
    Map<String, Object?> data = const {},
    HttpsCallableOptions? options,
  ]) async => asStringMap(await _call(name, data, options));

  // ---------------------------------------------------------- activation

  /// Returns the Firebase Auth email the account was created with. Students sign
  /// in with their Student ID, so this is the internal alias the server returns
  /// as `authEmail` (the real email is only a recovery contact). A server that
  /// predates Student ID sign-in returns just `email`.
  Future<String> startAccountSetup({
    required String studentNo,
    required String firstName,
    required String middleName,
    required String lastName,
    required String dateOfBirthKey,
    String? email,
    required String password,
  }) async {
    try {
      // The email is only sent when PACC has none on file for the record; otherwise the server uses its own.
      final result = await _callMap('startStudentAccountSetup', {
        'studentNo': studentNo,
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'dateOfBirth': dateOfBirthKey,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        'password': password,
      });
      final authEmail = asText(result['authEmail']);
      if (authEmail.isEmpty) {
        throw const StudentActivationException(
          StudentActivationFailure.unknown,
        );
      }
      return authEmail;
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final emailRequired =
          details is Map && details['reason'] == 'email-required';
      throw StudentActivationException(
        emailRequired
            ? StudentActivationFailure.emailRequired
            : StudentActivationFailure.fromCode(error.code),
        message: error.message,
      );
    }
  }

  /// Submits the verified setup for PACC approval, or reports it approved.
  /// Safe to repeat. Returns `approved` or `awaiting-approval`.
  Future<String> completeAccountSetup() async {
    final result = await _callMap('completeStudentAccountSetup');
    return asText(result['status']) == 'approved'
        ? 'approved'
        : 'awaiting-approval';
  }

  // ---------------------------------------------- administrator review

  Future<List<StudentAccountClaim>> listAccountClaims() async {
    final result = await _callMap('listStudentAccountClaims');
    return [
      for (final c in asList(result['claims']))
        StudentAccountClaim.fromJson(asStringMap(c)),
    ];
  }

  /// The server refuses unless the administrator attests they verified the
  /// student's identity.
  Future<void> approveAccountClaim(String uid) => _call(
    'approveStudentAccountClaim',
    {'uid': uid, 'identityVerified': true},
  );

  Future<void> rejectAccountClaim(String uid) =>
      _call('rejectStudentAccountClaim', {'uid': uid});

  // ------------------------------------------- recovery email and reset

  /// Emails a one-time code to the student's recovery address. The response
  /// carries only a masked address, never the code.
  Future<RecoveryCodeRequest> requestRecoveryEmailCode() async {
    final result = await _callMap('requestStudentRecoveryEmailCode');
    final expires = result['expiresInSeconds'];
    return RecoveryCodeRequest(
      alreadyVerified: result['alreadyVerified'] == true,
      maskedEmail: asText(result['maskedEmail']),
      expiresInSeconds: expires is num ? expires.toInt() : 0,
    );
  }

  Future<void> confirmRecoveryEmailCode(String code) =>
      _call('confirmStudentRecoveryEmailCode', {'code': code});

  /// Asks for a password-reset link to the student's verified recovery email.
  /// The server answers identically for every Student ID.
  Future<void> requestPasswordResetForStudentId(String studentId) =>
      _call('requestStudentPasswordReset', {'studentId': studentId.trim()});

  // ----------------------------------------- student login by roster email

  /// Asks for a login email. The server answers identically for every Student ID.
  Future<void> requestStudentLogin(String studentId) =>
      _call('requestStudentLogin', {'studentId': studentId.trim()});

  /// Sets the permanent password on the server. The session that called it is
  /// revoked, so the caller signs in again with the new password afterwards.
  Future<void> completePasswordChange(String newPassword) =>
      _call('completeStudentPasswordChange', {'newPassword': newPassword});

  // ------------------------------------------------- student information

  Future<StudentInformation> getMyInformation() async =>
      StudentInformation.fromJson(await _callMap('getMyStudentInformation'));

  Future<void> savePersonalInfo(
    StudentPersonalInfo info, {
    required bool privacyConsent,
  }) async {
    await _call('saveStudentPersonalInfo', {
      'info': info.toJson(),
      'privacyConsent': privacyConsent,
    });
  }

  /// Returns the new request id.
  Future<String> requestCorrection({
    required String field,
    required String requestedValue,
    required String reason,
  }) async {
    final result = await _callMap('requestStudentCorrection', {
      'field': field,
      'requestedValue': requestedValue,
      'reason': reason,
    });
    return asText(result['requestId']);
  }

  Future<({StudentOfficialInfo official, StudentPersonalInfo? personal})>
  getStudentPersonalInfo(String userId) async {
    final result = await _callMap('getStudentPersonalInfo', {'userId': userId});
    final personal = result['personal'];
    return (
      official: StudentOfficialInfo.fromJson(asStringMap(result['official'])),
      personal: personal is Map ? StudentPersonalInfo.fromJson(personal) : null,
    );
  }

  Future<List<StudentCorrection>> listCorrections({
    bool pendingOnly = false,
  }) async {
    final result = await _callMap('listStudentCorrectionRequests', {
      if (pendingOnly) 'status': 'pending',
    });
    return [
      for (final r in asList(result['requests']))
        StudentCorrection.fromJson(asStringMap(r)),
    ];
  }

  /// Returns the resulting status (`approved` or `rejected`).
  Future<String> reviewCorrection(
    String requestId, {
    required bool approve,
    String? reason,
  }) async {
    final result = await _callMap('reviewStudentCorrection', {
      'requestId': requestId,
      'decision': approve ? 'approve' : 'reject',
      'reason': ?reason,
    });
    return asText(result['status']);
  }

  // ---------------------------------------------------------- import

  Future<({List<RosterPreviewRow> rows, Map<String, int> counts})>
  previewImport(String fileName, List<Map<String, String>> rows) async {
    final result = await _callMap('previewStudentRosterImport', {
      'fileName': fileName,
      'rows': rows,
    });
    return (
      rows: [
        for (final r in asList(result['rows']))
          RosterPreviewRow.fromJson(asStringMap(r)),
      ],
      counts: intMap(result['counts']),
    );
  }

  Future<RosterImportResult> commitImport(
    String fileName,
    List<Map<String, String>> rows,
  ) async {
    final result = await _callMap(
      'importStudentRoster',
      {'fileName': fileName, 'rows': rows},
      HttpsCallableOptions(timeout: const Duration(minutes: 10)),
    );
    final message = asText(result['message']);
    return RosterImportResult(
      status: result['status'] == 'partial'
          ? RosterImportStatus.partial
          : RosterImportStatus.complete,
      importId: asText(result['importId']),
      counts: intMap(result['counts']),
      codes: [
        for (final c in asList(result['codes']))
          IssuedActivationCode.fromJson(asStringMap(c)),
      ],
      failedRows: [
        for (final f in asList(result['failedRows']))
          RosterFailedRow(
            index: (asStringMap(f)['index'] as num?)?.toInt() ?? 0,
            studentNo: asText(asStringMap(f)['studentNo']),
          ),
      ],
      message: message.isEmpty ? null : message,
    );
  }

  Future<List<RosterImportRecord>> listImports() async {
    final result = await _callMap('listStudentRosterImports');
    return [
      for (final i in asList(result['imports']))
        RosterImportRecord.fromJson(asStringMap(i)),
    ];
  }

  // ---------------------------------------------------------- roster

  /// Releases the student's claim so they can set up the account again. No
  /// code is issued.
  Future<void> revokeActivation(String studentNo, String reason) => _call(
    'revokeStudentActivation',
    {'studentNo': studentNo, 'reason': reason},
  );

  Future<({List<RosterRowView> rows, String? nextPageToken})> listRoster({
    String? search,
    String? collegeId,
    String? courseId,
    String? yearLevel,
    String? status,
    String? pageToken,
  }) async {
    String? clean(String? v) => v == null || v.isEmpty ? null : v;
    final filters = {
      'search': clean(search),
      'collegeId': clean(collegeId),
      'courseId': clean(courseId),
      'yearLevel': clean(yearLevel),
      'status': clean(status),
      'pageToken': clean(pageToken),
    };
    final result = await _callMap('listStudentRoster', {
      for (final e in filters.entries)
        if (e.value != null) e.key: e.value,
    });
    final token = asText(result['nextPageToken']);
    return (
      rows: [
        for (final r in asList(result['rows']))
          RosterRowView.fromJson(asStringMap(r)),
      ],
      nextPageToken: token.isEmpty ? null : token,
    );
  }

  Future<List<LegacyStudent>> listLegacyNotInRoster() async {
    final result = await _callMap('listLegacyStudentsNotInRoster');
    return [
      for (final r in asList(result['rows']))
        LegacyStudent.fromJson(asStringMap(r)),
    ];
  }

  Future<void> updateRosterRecord(
    String studentNo,
    Map<String, String> fields,
  ) async {
    await _call('updateStudentRosterRecord', {
      'studentNo': studentNo,
      'fields': fields,
    });
  }

  Future<void> setRosterStatus(String studentNo, {required bool active}) async {
    await _call('setStudentRosterStatus', {
      'studentNo': studentNo,
      'status': active ? 'active' : 'deactivated',
    });
  }

  Future<void> resetActivationLock(String studentNo) async {
    await _call('resetStudentActivationLock', {'studentNo': studentNo});
  }

  Future<BackfillResult> backfillInfoRequirement() async {
    final result = await _callMap('backfillStudentInfoRequirement');
    return BackfillResult(
      flagged: (result['flagged'] as num?)?.toInt() ?? 0,
      notInRoster: (result['notInRoster'] as num?)?.toInt() ?? 0,
    );
  }
}
