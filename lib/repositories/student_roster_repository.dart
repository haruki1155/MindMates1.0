// ignore_for_file: prefer_initializing_formals
import 'package:cloud_functions/cloud_functions.dart';

import '../models/student_personal_info.dart';
import '../models/student_roster_models.dart';
import '../services/firebase/firebase_callable_router.dart';

/// Invokes a callable by its protected name and returns the response data.
typedef StudentRosterCallableInvoker =
    Future<Object?> Function(String name, Map<String, Object?> data);

class StudentRosterRepository {
  StudentRosterRepository({
    FirebaseFunctions? functions,
    StudentRosterCallableInvoker? invoker,
  }) : _functions = functions,
       _invoker = invoker;

  final FirebaseFunctions? _functions;
  final StudentRosterCallableInvoker? _invoker;

  Future<Object?> _call(String name, [Map<String, Object?> data = const {}]) {
    final invoker = _invoker;
    if (invoker != null) return invoker(name, data);
    final functions =
        _functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
    return functions
        .routedCallable(name)
        .call<Object?>(data)
        .then((result) => result.data);
  }

  Future<Map<String, Object?>> _callMap(
    String name, [
    Map<String, Object?> data = const {},
  ]) async => asStringMap(await _call(name, data));

  // ---------------------------------------------------------- activation

  /// Returns the email the account was created with.
  Future<String> activate({
    required String studentNo,
    required String activationCode,
    required String dateOfBirthKey,
    required String email,
    required String password,
  }) async {
    try {
      final result = await _callMap('activateStudentAccount', {
        'studentNo': studentNo,
        'activationCode': activationCode,
        'dateOfBirth': dateOfBirthKey,
        'email': email,
        'password': password,
      });
      final returned = asText(result['email']);
      return returned.isEmpty ? email : returned;
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      throw StudentActivationException(
        StudentActivationFailure.parse(
          details is Map ? details['reason'] : null,
        ),
        message: error.message,
      );
    }
  }

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
    final result = await _callMap('getStudentPersonalInfo', {
      'userId': userId,
    });
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
    final result = await _callMap('importStudentRoster', {
      'fileName': fileName,
      'rows': rows,
    });
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

  Future<
    ({
      List<IssuedActivationCode> codes,
      List<({String studentNo, String reason})> skipped,
    })
  >
  issueActivationCodes(List<String> studentNos) async {
    final result = await _callMap('issueStudentActivationCodes', {
      'studentNos': studentNos,
    });
    return (
      codes: [
        for (final c in asList(result['codes']))
          IssuedActivationCode.fromJson(asStringMap(c)),
      ],
      skipped: [
        for (final s in asList(result['skipped']))
          (
            studentNo: asText(asStringMap(s)['studentNo']),
            reason: asText(asStringMap(s)['reason']),
          ),
      ],
    );
  }

  Future<IssuedActivationCode> revokeActivation(
    String studentNo,
    String reason,
  ) async {
    final result = await _callMap('revokeStudentActivation', {
      'studentNo': studentNo,
      'reason': reason,
    });
    return IssuedActivationCode.fromJson(asStringMap(result['code']));
  }

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
