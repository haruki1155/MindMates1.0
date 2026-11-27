import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/student_personal_info.dart';
import '../../../providers/assessment_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../repositories/student_roster_repository.dart';
import '../../../routes/route_names.dart';
import '../../authentication/auth_flow_routes.dart';
import '../student_info_validator.dart';
import '../widgets/correction_request_sheet.dart';

enum StudentInfoMode { onboarding, edit }

/// Collects the Student Information form. In [StudentInfoMode.onboarding] it
/// is the first-login gate (consent required, cannot be skipped); in
/// [StudentInfoMode.edit] it is opened from Profile.
class StudentInformationScreen extends StatefulWidget {
  const StudentInformationScreen({
    super.key,
    this.mode = StudentInfoMode.onboarding,
    this.repository,
  });

  final StudentInfoMode mode;

  /// Overridable for tests; defaults to the production repository.
  final StudentRosterRepository? repository;

  @override
  State<StudentInformationScreen> createState() =>
      _StudentInformationScreenState();
}

class _StudentInformationScreenState extends State<StudentInformationScreen> {
  static const _consentCopy =
      'I agree to the collection and processing of my personal information '
      'under the Data Privacy Act of 2012 (RA 10173).';
  static const _genericSaveError =
      "We couldn't save your information right now. Check your connection and try again.";

  static const _correctable = [
    ('surname', 'Surname'),
    ('firstName', 'First name'),
    ('middleName', 'Middle name'),
    ('dateOfBirth', 'Date of birth'),
    ('college', 'College'),
    ('course', 'Course'),
    ('yearLevel', 'Year level'),
  ];

  static const _addressParts = [
    ('number', 'Number'),
    ('street', 'Street'),
    ('barangay', 'Barangay'),
    ('cityTown', 'City / Town'),
    ('province', 'Province'),
    ('zipCode', 'Zip code'),
  ];

  late final StudentRosterRepository _repository =
      widget.repository ?? StudentRosterRepository();
  final Map<String, TextEditingController> _controllers = {};
  Map<String, String> _errors = {};
  StudentInformation? _information;
  String _sex = '';
  String _civilStatus = '';
  bool _loading = true;
  bool _loadFailed = false;
  bool _consent = false;
  bool _saving = false;
  String? _saveError;

  bool get _isOnboarding => widget.mode == StudentInfoMode.onboarding;

  /// Consent is collected on the first save, in either mode.
  bool get _needsConsent => _information?.personal == null;

  TextEditingController _controller(String path) =>
      _controllers.putIfAbsent(path, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool keepForm = false}) async {
    if (!keepForm) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      final information = await _repository.getMyInformation();
      if (!mounted) return;
      setState(() {
        _information = information;
        if (!keepForm) _prefill(information.personal);
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = _information == null;
      });
    }
  }

  void _prefill(StudentPersonalInfo? p) {
    if (p == null) return;
    _sex = p.sex;
    _civilStatus = p.civilStatus;
    final values = <String, String>{
      'spouse': p.spouse,
      'nationality': p.nationality,
      'placeOfBirth': p.placeOfBirth,
      'father': p.father,
      'fatherOccupation': p.fatherOccupation,
      'mother': p.mother,
      'motherOccupation': p.motherOccupation,
      'guardian': p.guardian,
      'guardianRelationship': p.guardianRelationship,
      'guardianAddress': p.guardianAddress,
      'telephone': p.telephone,
      'cellphone': p.cellphone,
    };
    final city = p.cityAddress?.toJson() ?? const {};
    final home = p.homeAddress.toJson();
    for (final (part, _) in _addressParts) {
      values['cityAddress.$part'] = (city[part] ?? '').toString();
      values['homeAddress.$part'] = (home[part] ?? '').toString();
    }
    values.forEach((path, v) => _controller(path).text = v);
  }

  String _text(String path) => _controller(path).text.trim();

  StudentAddress _address(String key) => StudentAddress(
    number: _text('$key.number'),
    street: _text('$key.street'),
    barangay: _text('$key.barangay'),
    cityTown: _text('$key.cityTown'),
    province: _text('$key.province'),
    zipCode: _text('$key.zipCode'),
  );

  StudentPersonalInfo _collect() {
    final city = _address('cityAddress');
    return StudentPersonalInfo(
      sex: _sex,
      civilStatus: _civilStatus,
      spouse: _civilStatus == 'Married' ? _text('spouse') : '',
      nationality: _text('nationality'),
      placeOfBirth: _text('placeOfBirth'),
      cityAddress: city.isEmpty ? null : city,
      homeAddress: _address('homeAddress'),
      father: _text('father'),
      fatherOccupation: _text('fatherOccupation'),
      mother: _text('mother'),
      motherOccupation: _text('motherOccupation'),
      guardian: _text('guardian'),
      guardianRelationship: _text('guardianRelationship'),
      guardianAddress: _text('guardianAddress'),
      telephone: _text('telephone'),
      cellphone: _text('cellphone'),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final info = _collect();
    final clientErrors = StudentInfoValidator.validate(info);
    if (clientErrors.isNotEmpty) {
      setState(() {
        _errors = clientErrors;
        _saveError = 'Please correct the highlighted fields.';
      });
      return;
    }
    setState(() {
      _errors = {};
      _saveError = null;
      _saving = true;
    });
    try {
      await _repository.savePersonalInfo(info, privacyConsent: _consent);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      final details = error.details;
      final serverErrors = <String, String>{};
      if (error.code == 'invalid-argument' && details is Map) {
        final raw = details['errors'];
        if (raw is Map) {
          raw.forEach((k, v) => serverErrors[k.toString()] = v.toString());
        }
      }
      setState(() {
        _saving = false;
        _errors = serverErrors;
        _saveError = serverErrors.isNotEmpty
            ? 'Please correct the highlighted fields.'
            // A revoked or non-student account comes back as permission-denied
            // with copy that explains why; "check your connection" would send
            // the student looking in the wrong place.
            : ((error.code == 'failed-precondition' ||
                      error.code == 'permission-denied') &&
                  (error.message ?? '').isNotEmpty)
            ? error.message
            : _genericSaveError;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = _genericSaveError;
      });
      return;
    }
    if (!mounted) return;
    await _afterSave();
  }

  Future<void> _afterSave() async {
    final userProvider = context.read<UserProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final uid = userProvider.user?.id;
    final reloaded = uid != null && await userProvider.loadProfile(uid);
    if (!mounted) return;

    if (!_isOnboarding) {
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Student information saved.')),
        );
      return;
    }
    final user = userProvider.user;
    if (!reloaded || user == null) {
      setState(() {
        _saving = false;
        _saveError =
            'Your information was saved, but we could not refresh your '
            'account. Tap Save again to continue.';
      });
      return;
    }
    var destination = gateRouteForUser(user);
    if (destination == null) {
      final completed = await context
          .read<AssessmentProvider>()
          .ensureQuickAssessmentCompletion(user.id);
      if (!mounted) return;
      destination = destinationAfterAuthentication(
        hasCompletedQuickAssessment: completed,
      );
    }
    navigator.pushNamedAndRemoveUntil(destination, (route) => false);
  }

  Future<void> _requestCorrection(
    String key,
    String label,
    String current, {
    String currentCollege = '',
  }) async {
    final sent = await showCorrectionRequestSheet(
      context,
      repository: _repository,
      fieldKey: key,
      label: label,
      currentValue: current,
      currentCollege: currentCollege,
    );
    if (!sent || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Correction request sent.')));
    await _load(keepForm: true);
  }

  Future<void> _signOut() async {
    final auth = context.read<AuthProvider>();
    final users = context.read<UserProvider>();
    final navigator = Navigator.of(context);
    try {
      await auth.signOut();
    } catch (_) {
      // Fall through: the session is cleared locally as far as possible.
    }
    users.setUser(null);
    navigator.pushNamedAndRemoveUntil(RouteNames.login, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isOnboarding,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: !_isOnboarding,
          foregroundColor: AppColors.textPrimary,
          title: const Text(
            'Student Information',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          actions: [
            if (_isOnboarding)
              TextButton(
                key: const Key('sign-out'),
                onPressed: _saving ? null : _signOut,
                child: const Text('Sign out'),
              ),
          ],
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final information = _information;
    if (_loadFailed || information == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFDDE7E3)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 36,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "We couldn't load your student information.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final canSave = !_saving && (!_needsConsent || _consent);
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isOnboarding) _onboardingBanner(),
              if (_needsConsent) _consentCard(),
              _officialSection(information),
              if (information.corrections.isNotEmpty)
                _correctionsSection(information.corrections),
              _personalSection(),
              if (_saveError != null) _saveErrorBanner(_saveError!),
              const SizedBox(height: 4),
              FilledButton(
                onPressed: canSave ? _save : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
              if (_needsConsent && !_consent)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Agree to the Data Privacy Consent above to enable Save.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _onboardingBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.assignment_ind_outlined,
            color: AppColors.primary,
            size: 22,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Complete your student profile',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Review your official record and fill in the required details below.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _consentCard() {
    final borderColor = _consent ? AppColors.primary : AppColors.secondary;
    final tint = _consent
        ? AppColors.primary.withValues(alpha: 0.06)
        : AppColors.secondary.withValues(alpha: 0.10);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.verified_user_outlined,
                      size: 18,
                      color: _consent
                          ? AppColors.primary
                          : const Color(0xFF9A6B00),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Data Privacy Consent',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  _BadgeChip(
                    label: 'Required',
                    color: _consent
                        ? AppColors.primary
                        : const Color(0xFF9A6B00),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.primary,
                value: _consent,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _consent = v ?? false),
                title: const Text(
                  _consentCopy,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(
    String title,
    List<Widget> children, {
    String? subtitle,
    IconData? icon,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE7E3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _officialSection(StudentInformation information) {
    final o = information.official;
    final pending = {
      for (final c in information.corrections)
        if (c.status == 'pending') c.field,
    };
    final rows = <(String, String, String, String?)>[
      ('studentNo', 'Student No.', o.studentNo, null),
      ('surname', 'Surname', o.surname, 'surname'),
      ('firstName', 'First name', o.firstName, 'firstName'),
      ('middleName', 'Middle name', o.middleName, 'middleName'),
      (
        'dateOfBirth',
        'Date of birth',
        formatDateKey(o.dateOfBirth),
        'dateOfBirth',
      ),
      ('email', 'Email', o.email, null),
      ('college', 'College', o.college, 'college'),
      ('course', 'Course', o.course, 'course'),
      ('yearLevel', 'Year level', o.yearLevel, 'yearLevel'),
    ];
    return _card(
      'Official record',
      [
        for (var i = 0; i < rows.length; i++) ...[
          _officialRow(
            fieldKey: rows[i].$1,
            label: rows[i].$2,
            value: rows[i].$3,
            correctableField: rows[i].$4,
            hasPending: rows[i].$4 != null && pending.contains(rows[i].$4),
            official: o,
          ),
          if (i < rows.length - 1)
            const Divider(height: 16, color: Color(0xFFEAF0EE)),
        ],
      ],
      icon: Icons.school_outlined,
      subtitle:
          'Synced from PACC records. Request a correction if anything is inaccurate.',
    );
  }

  Widget _officialRow({
    required String fieldKey,
    required String label,
    required String value,
    required String? correctableField,
    required bool hasPending,
    required StudentOfficialInfo official,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value.isEmpty ? '-' : value,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (correctableField != null && !hasPending) ...[
          const SizedBox(width: 8),
          TextButton(
            key: Key('correct-$fieldKey'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              backgroundColor: AppColors.primary.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () => _requestCorrection(
              correctableField,
              label,
              _rawOfficial(official, correctableField),
              currentCollege: official.college,
            ),
            child: const Text('Request correction'),
          ),
        ] else if (correctableField == null) ...[
          const SizedBox(width: 8),
          const _BadgeChip(label: 'Read-only', color: AppColors.textMuted),
        ],
      ],
    );
  }

  String _rawOfficial(StudentOfficialInfo o, String field) => switch (field) {
    'surname' => o.surname,
    'firstName' => o.firstName,
    'middleName' => o.middleName,
    'dateOfBirth' => o.dateOfBirth,
    'yearLevel' => o.yearLevel,
    'college' => o.college,
    'course' => o.course,
    _ => '',
  };

  Widget _correctionsSection(List<StudentCorrection> corrections) {
    String labelOf(String field) {
      for (final (key, label) in _correctable) {
        if (key == field) return label;
      }
      return switch (field) {
        'college' => 'College',
        'course' => 'Course',
        _ => field,
      };
    }

    return _card('Correction requests', [
      for (var i = 0; i < corrections.length; i++)
        Container(
          margin: EdgeInsets.only(bottom: i < corrections.length - 1 ? 10 : 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDDE7E3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labelOf(corrections[i].field),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'To: ${corrections[i].requestedValue}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    if (corrections[i].status == 'rejected' &&
                        corrections[i].reviewReason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        corrections[i].reviewReason,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: corrections[i].status),
            ],
          ),
        ),
    ], icon: Icons.edit_note_outlined);
  }

  Widget _personalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          'Basic details',
          [
            _pairedFields(
              _dropdown(
                'sex',
                'Sex',
                StudentInfoValidator.sexOptions,
                _sex,
                (v) => _sex = v,
              ),
              _dropdown(
                'civilStatus',
                'Civil status',
                StudentInfoValidator.civilStatuses,
                _civilStatus,
                (v) => _civilStatus = v,
              ),
            ),
            if (_civilStatus == 'Married') _field('spouse', 'Spouse'),
            _pairedFields(
              _field('nationality', 'Nationality'),
              _field('placeOfBirth', 'Place of birth'),
            ),
          ],
          icon: Icons.person_outline_rounded,
          trailing: const _BadgeChip(
            label: 'Required',
            color: AppColors.primary,
          ),
        ),
        _card(
          'Home address',
          [
            _pairedFields(
              _field('homeAddress.number', 'Number'),
              _field('homeAddress.street', 'Street'),
            ),
            _pairedFields(
              _field('homeAddress.barangay', 'Barangay'),
              _field('homeAddress.cityTown', 'City / Town'),
            ),
            _pairedFields(
              _field('homeAddress.province', 'Province'),
              _field('homeAddress.zipCode', 'Zip code'),
            ),
          ],
          icon: Icons.home_outlined,
          trailing: const _BadgeChip(
            label: 'Required',
            color: AppColors.primary,
          ),
        ),
        _card(
          'City address (optional)',
          [
            _pairedFields(
              _field('cityAddress.number', 'Number'),
              _field('cityAddress.street', 'Street'),
            ),
            _pairedFields(
              _field('cityAddress.barangay', 'Barangay'),
              _field('cityAddress.cityTown', 'City / Town'),
            ),
            _pairedFields(
              _field('cityAddress.province', 'Province'),
              _field('cityAddress.zipCode', 'Zip code'),
            ),
          ],
          icon: Icons.location_city_outlined,
          subtitle:
              'Only fill this if you stay at a different address during school.',
          trailing: const _BadgeChip(
            label: 'Optional',
            color: AppColors.textMuted,
          ),
        ),
        _card('Guardian & family', [
          _subLabel('Guardian (Required)'),
          _field('guardian', 'Guardian'),
          _field('guardianRelationship', 'Relationship to guardian'),
          _field('guardianAddress', 'Guardian address'),
          const Divider(height: 20, color: Color(0xFFEAF0EE)),
          _subLabel('Parents (Optional)'),
          _field('father', "Father's name (optional)"),
          _field('fatherOccupation', "Father's occupation (optional)"),
          _field('mother', "Mother's name (optional)"),
          _field('motherOccupation', "Mother's occupation (optional)"),
        ], icon: Icons.family_restroom_outlined),
        _card('Contact information', [
          _field(
            'cellphone',
            'Cellphone',
            keyboard: TextInputType.phone,
            prefixIcon: Icons.smartphone_outlined,
          ),
          _field(
            'telephone',
            'Telephone (optional)',
            keyboard: TextInputType.phone,
            prefixIcon: Icons.call_outlined,
          ),
        ], icon: Icons.phone_outlined),
      ],
    );
  }

  Widget _pairedFields(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Widget _subLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
        color: AppColors.textSecondary,
      ),
    ),
  );

  InputDecoration _inputDecoration(
    String label, {
    String? errorText,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      errorText: errorText,
      errorMaxLines: 3,
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
      filled: true,
      fillColor: const Color(0xFFF9FBFA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD0DDD8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD0DDD8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
    );
  }

  Widget _field(
    String path,
    String label, {
    TextInputType? keyboard,
    IconData? prefixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: Key('field-$path'),
        controller: _controller(path),
        keyboardType: keyboard,
        enabled: !_saving,
        decoration: _inputDecoration(
          label,
          errorText: _errors[path],
          prefixIcon: prefixIcon,
        ),
        onChanged: (_) {
          if (_errors.containsKey(path)) {
            setState(() => _errors = {..._errors}..remove(path));
          }
        },
      ),
    );
  }

  Widget _dropdown(
    String path,
    String label,
    List<String> options,
    String current,
    void Function(String) assign,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: Key('field-$path'),
        initialValue: options.contains(current) ? current : null,
        isExpanded: true,
        decoration: _inputDecoration(label, errorText: _errors[path]),
        items: [
          for (final o in options)
            DropdownMenuItem(
              value: o,
              child: Text(o, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: _saving
            ? null
            : (v) => setState(() {
                if (v != null) assign(v);
                _errors = {..._errors}..remove(path);
              }),
      ),
    );
  }

  Widget _saveErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              key: const Key('save-error'),
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'approved' => ('Approved', AppColors.primary),
      'rejected' => ('Rejected', AppColors.error),
      _ => ('Pending', const Color(0xFF9A6B00)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
