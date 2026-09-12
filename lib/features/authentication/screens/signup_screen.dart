import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../quick_assessment/models/quick_assessment_models.dart';
import '../../../models/user_model.dart';
import '../../../models/profile_roles.dart';
import '../../../core/widgets/mindmate_terms_and_conditions.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../repositories/auth_repository.dart';
import '../data/registration_organization_catalog.dart';
import '../../../routes/route_names.dart';
import '../auth_flow_routes.dart';

class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _SignupColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            _BubbleCluster(top: -27, left: -14, mirror: false),
            _BubbleCluster(top: -16, right: -12, mirror: true),
            _SignupBody(),
          ],
        ),
      ),
    );
  }
}

class _SignupBody extends StatefulWidget {
  const _SignupBody();

  @override
  State<_SignupBody> createState() => _SignupBodyState();
}

class _SignupBodyState extends State<_SignupBody> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _schoolIdController = TextEditingController();
  final _yearLevelController = TextEditingController();
  final _positionController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _selectedDepartment;
  String? _selectedCourse;
  String? _selectedSector;
  String? _selectedGender;
  bool _acceptedTerms = false;
  DateTime? _dateOfBirth;
  bool _googleDefaultsApplied = false;

  bool get _isGoogleProfileSetup {
    final email = context.read<AuthProvider>().currentUserEmail ?? '';
    return email.isNotEmpty && !email.endsWith('@mindmate.local');
  }

  AssessmentRole get _registrationRole =>
      AuthRepository.registrationRoleForEmail(_emailController.text);

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_handleEmailChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showRegistrationInstructions();
    });
  }

  void _handleEmailChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _showRegistrationInstructions() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.how_to_reg_outlined),
        title: const Text('Before you create an account'),
        content: const Text(
          'Student accounts use a valid personal email address and Student ID.\n\n'
          'Teaching personnel must use their official UCU email (for example, '
          'juandelacruz@ucu.edu.ph). The form will automatically change to '
          'Teaching and ask for an Employee ID.\n\n'
          'Non-teaching registration remains unchanged while a reliable '
          'verification method is being prepared. There is no manual account-type selector.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleTermsChanged() async {
    if (_acceptedTerms) {
      setState(() => _acceptedTerms = false);
      return;
    }

    final accepted = await showMindMateTermsAndConditions(
      context,
      requireAcceptance: true,
    );
    if (mounted && accepted) setState(() => _acceptedTerms = true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_googleDefaultsApplied || !_isGoogleProfileSetup) return;
    _googleDefaultsApplied = true;
    _emailController.text = context.read<AuthProvider>().currentUserEmail ?? '';
    final displayName =
        context.read<AuthProvider>().currentUserDisplayName ?? '';
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      _firstNameController.text = parts.first;
      if (parts.length > 1) {
        _lastNameController.text = parts.sublist(1).join(' ');
      }
    }
  }

  Future<void> _pickDateOfBirth() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _dateOfBirth ?? DateTime(today.year - 18, today.month, today.day),
      firstDate: DateTime(today.year - 120),
      lastDate: today,
    );
    if (picked != null && mounted) setState(() => _dateOfBirth = picked);
  }

  @override
  void dispose() {
    _emailController.removeListener(_handleEmailChanged);
    _emailController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _schoolIdController.dispose();
    _yearLevelController.dispose();
    _positionController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? value, String field) {
    if (value == null || value.trim().isEmpty) {
      return '$field is required';
    }
    return null;
  }

  String? _confirmPasswordValidator(String? value) {
    final requiredError = _requiredValidator(value, 'Confirm password');
    if (requiredError != null) {
      return requiredError;
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _handleSignUp() async {
    FocusScope.of(context).unfocus();
    final formIsValid = _formKey.currentState?.validate() ?? false;

    if (!formIsValid || !_acceptedTerms) {
      if (!_acceptedTerms) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Please read and accept the Terms and Conditions.'),
            ),
          );
      }
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();
    authProvider.setRegistrationEmail(_emailController.text);
    final role = _registrationRole;
    final birthDate = _dateOfBirth;
    if (birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Date of birth is required.')),
      );
      return;
    }
    final userId = _isGoogleProfileSetup
        ? await authProvider.completeGoogleProfile(
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
            schoolId: _schoolIdController.text,
            department: _selectedDepartment ?? '',
            course: _selectedCourse ?? '',
            yearLevel: _yearLevelController.text,
            dateOfBirth: birthDate,
            middleName: _middleNameController.text,
            employeeId: role == AssessmentRole.faculty
                ? _schoolIdController.text
                : null,
            position: _positionController.text,
            role: role,
            gender: _selectedGender,
          )
        : await authProvider.signUp(
            password: _passwordController.text,
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
            schoolId: _schoolIdController.text,
            department: _selectedDepartment ?? '',
            course: _selectedCourse ?? '',
            yearLevel: _yearLevelController.text,
            middleName: _middleNameController.text,
            employeeId: role == AssessmentRole.faculty
                ? _schoolIdController.text
                : null,
            position: _positionController.text,
            role: role,
            dateOfBirth: birthDate,
            gender: _selectedGender,
          );

    if (!mounted) return;

    if (userId == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              authProvider.errorMessage ?? 'Unable to create account.',
            ),
          ),
        );
      return;
    }

    userProvider.setUser(
      _localProfileFromRegistration(userId: userId, role: role),
    );
    final profileLoaded = await userProvider.loadProfile(userId);
    if (!profileLoaded) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userProvider.errorMessage ??
                'Your profile could not be loaded. Please try again.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final provider = context.read<AuthProvider>();
    final destination = provider.currentUserEmail?.isNotEmpty != true
        ? destinationAfterAuthentication(hasCompletedQuickAssessment: false)
        : provider.currentUserEmailVerified
        ? RouteNames.profileSetup
        : RouteNames.emailVerification;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(destination, (route) => false);
  }

  UserModel _localProfileFromRegistration({
    required String userId,
    required AssessmentRole? role,
  }) {
    final usesSector = role == AssessmentRole.staff;
    final isStudent = role == AssessmentRole.student;
    final populationRole = role?.populationRole;
    return UserModel(
      id: userId,
      email:
          context.read<AuthProvider>().currentUserEmail ??
          AuthRepository.authEmailForSchoolId(_schoolIdController.text),
      firstName: _firstNameController.text.trim(),
      middleName: _middleNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      schoolId: _schoolIdController.text.trim(),
      employeeId: isStudent ? null : _schoolIdController.text.trim(),
      department: usesSector ? null : _selectedDepartment?.trim(),
      course: isStudent ? _selectedCourse?.trim() : null,
      yearLevel: isStudent ? _yearLevelController.text.trim() : null,
      sector: usesSector ? _selectedSector?.trim() : null,
      position: isStudent ? null : _positionController.text.trim(),
      role: role?.name,
      populationRole: populationRole,
      declaredRole: populationRole,
      accessRole: AccessRole.appUser,
      verificationStatus: VerificationStatus.verified,
      verifiedAt: DateTime.now(),
      verifiedBy: 'automatic-registration',
      profileVersion: 3,
      createdAt: DateTime.now(),
      dayStreak: 0,
      dateOfBirth: _dateOfBirth,
      gender: _selectedGender,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(6, screenHeight < 760 ? 22 : 54, 6, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Column(
            children: [
              const _LogoHeader(),
              const SizedBox(height: 16),
              Consumer<AuthProvider>(
                builder: (context, authProvider, _) {
                  return _SignupFormCard(
                    formKey: _formKey,
                    role: _registrationRole,
                    isGoogleProfileSetup: _isGoogleProfileSetup,
                    dateOfBirth: _dateOfBirth,
                    onPickDateOfBirth: _pickDateOfBirth,
                    emailController: _emailController,
                    firstNameController: _firstNameController,
                    middleNameController: _middleNameController,
                    lastNameController: _lastNameController,
                    schoolIdController: _schoolIdController,
                    yearLevelController: _yearLevelController,
                    positionController: _positionController,
                    passwordController: _passwordController,
                    confirmPasswordController: _confirmPasswordController,
                    selectedDepartment: _selectedDepartment,
                    selectedCourse: _selectedCourse,
                    selectedSector: _selectedSector,
                    selectedGender: _selectedGender,
                    acceptedTerms: _acceptedTerms,
                    isLoading: authProvider.isLoading,
                    onDepartmentChanged: (value) {
                      setState(() {
                        _selectedDepartment = value;
                        _selectedCourse = null;
                      });
                    },
                    onCourseChanged: (value) {
                      setState(() => _selectedCourse = value);
                    },
                    onSectorChanged: (value) {
                      setState(() => _selectedSector = value);
                    },
                    onGenderChanged: (value) {
                      setState(() => _selectedGender = value);
                    },
                    onTermsTap: _handleTermsChanged,
                    onSignUp: _handleSignUp,
                    requiredValidator: _requiredValidator,
                    confirmPasswordValidator: _confirmPasswordValidator,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoHeader extends StatelessWidget {
  const _LogoHeader();

  static const _logoPath = 'assets/images/APP LOGO/MindMate_LOGO.jpg';

  @override
  Widget build(BuildContext context) {
    return Image.asset(_logoPath, width: 150, height: 150, fit: BoxFit.contain);
  }
}

class _SignupFormCard extends StatelessWidget {
  const _SignupFormCard({
    required this.formKey,
    required this.role,
    required this.firstNameController,
    required this.middleNameController,
    required this.lastNameController,
    required this.schoolIdController,
    required this.yearLevelController,
    required this.positionController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.selectedDepartment,
    required this.selectedCourse,
    required this.selectedSector,
    required this.selectedGender,
    required this.acceptedTerms,
    required this.isLoading,
    required this.onDepartmentChanged,
    required this.onCourseChanged,
    required this.onSectorChanged,
    required this.onGenderChanged,
    required this.onTermsTap,
    required this.onSignUp,
    required this.requiredValidator,
    required this.confirmPasswordValidator,
    required this.isGoogleProfileSetup,
    required this.dateOfBirth,
    required this.onPickDateOfBirth,
    required this.emailController,
  });

  final GlobalKey<FormState> formKey;
  final AssessmentRole? role;
  final TextEditingController firstNameController;
  final TextEditingController middleNameController;
  final TextEditingController lastNameController;
  final TextEditingController schoolIdController;
  final TextEditingController yearLevelController;
  final TextEditingController positionController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final String? selectedDepartment;
  final String? selectedCourse;
  final String? selectedSector;
  final String? selectedGender;
  final bool acceptedTerms;
  final bool isLoading;
  final ValueChanged<String?> onDepartmentChanged;
  final ValueChanged<String?> onCourseChanged;
  final ValueChanged<String?> onSectorChanged;
  final ValueChanged<String?> onGenderChanged;
  final VoidCallback onTermsTap;
  final Future<void> Function() onSignUp;
  final String? Function(String?, String) requiredValidator;
  final String? Function(String?) confirmPasswordValidator;
  final bool isGoogleProfileSetup;
  final DateTime? dateOfBirth;
  final Future<void> Function() onPickDateOfBirth;
  final TextEditingController emailController;

  @override
  Widget build(BuildContext context) {
    final selectedCourses = registrationCoursesForDepartment(
      selectedDepartment,
    );
    final usesSector = role == AssessmentRole.staff;
    final isStudent = role == AssessmentRole.student;

    return Container(
      width: 346,
      padding: const EdgeInsets.fromLTRB(20, 25, 19, 56),
      decoration: BoxDecoration(
        color: _SignupColors.card,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(50),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SignupField(
              controller: emailController,
              label: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              readOnly: isGoogleProfileSetup,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Email address is required';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: 7),
            _AccountTypeNotice(isTeaching: !isStudent),
            const SizedBox(height: 7),
            _SignupField(
              controller: firstNameController,
              label: 'First Name',
              icon: Icons.person_outline,
              textInputAction: TextInputAction.next,
              validator: (value) => requiredValidator(value, 'First name'),
            ),
            const SizedBox(height: 7),
            _SignupField(
              controller: middleNameController,
              label: 'Middle Name',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 7),
            _SignupField(
              controller: lastNameController,
              label: 'Last Name',
              textInputAction: TextInputAction.next,
              validator: (value) => requiredValidator(value, 'Last name'),
            ),
            const SizedBox(height: 7),
            _SignupField(
              controller: schoolIdController,
              label: isStudent ? 'Student ID' : 'Employee ID',
              icon: Icons.badge_outlined,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              validator: (value) => requiredValidator(
                value,
                isStudent ? 'Student ID' : 'Employee ID',
              ),
            ),
            const SizedBox(height: 7),
            InkWell(
              onTap: onPickDateOfBirth,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date of Birth',
                  prefixIcon: Icon(Icons.cake_outlined),
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  dateOfBirth == null
                      ? 'Select date'
                      : '${dateOfBirth!.month}/${dateOfBirth!.day}/${dateOfBirth!.year}',
                ),
              ),
            ),
            const SizedBox(height: 7),
            if (usesSector) ...[
              _SignupDropdownField(
                label: 'Sector',
                icon: Icons.business_center_outlined,
                value: selectedSector,
                items: staffDepartmentOptions,
                onChanged: onSectorChanged,
                validator: (value) => requiredValidator(value, 'Sector'),
              ),
            ] else ...[
              _SignupDropdownField(
                label: 'College or Department',
                icon: Icons.account_balance_outlined,
                value: selectedDepartment,
                items: registrationCollegeCourseOptions
                    .map((option) => option.department)
                    .toList(growable: false),
                onChanged: onDepartmentChanged,
                validator: (value) =>
                    requiredValidator(value, 'College or department'),
              ),
              if (isStudent) ...[
                const SizedBox(height: 7),
                _SignupDropdownField(
                  label: 'Course or Program',
                  icon: Icons.school_outlined,
                  value: selectedCourse,
                  items: selectedCourses,
                  onChanged: selectedDepartment == null
                      ? null
                      : onCourseChanged,
                  validator: (value) =>
                      requiredValidator(value, 'Course or program'),
                ),
              ],
            ],
            const SizedBox(height: 7),
            if (isStudent)
              _SignupDropdownField(
                label: 'Year Level',
                icon: Icons.timeline_outlined,
                value: yearLevelController.text.isEmpty
                    ? null
                    : yearLevelController.text,
                items: const ['1st Year', '2nd Year', '3rd Year', '4th Year'],
                onChanged: (value) => yearLevelController.text = value ?? '',
                validator: (value) => requiredValidator(value, 'Year level'),
              )
            else
              _SignupField(
                controller: positionController,
                label: 'Position or Designation',
                icon: Icons.work_outline,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    requiredValidator(value, 'Position or designation'),
              ),
            const SizedBox(height: 7),
            _SignupDropdownField(
              label: 'Sex / Gender',
              icon: Icons.wc_outlined,
              value: selectedGender,
              items: const [
                'Male',
                'Female',
                'Non-binary',
                'Prefer not to say',
              ],
              onChanged: onGenderChanged,
              validator: (value) => requiredValidator(value, 'Sex / gender'),
            ),
            const SizedBox(height: 7),
            if (!isGoogleProfileSetup) ...[
              _SignupField(
                controller: passwordController,
                label: 'Password',
                icon: Icons.lock_outline,
                obscureText: true,
                textInputAction: TextInputAction.next,
                validator: (value) => requiredValidator(value, 'Password'),
              ),
              const SizedBox(height: 7),
              _SignupField(
                controller: confirmPasswordController,
                label: 'Confirm Password',
                icon: Icons.lock_outline,
                obscureText: true,
                textInputAction: TextInputAction.done,
                validator: confirmPasswordValidator,
              ),
            ],
            const SizedBox(height: 9),
            _TermsCheckbox(acceptedTerms: acceptedTerms, onTap: onTermsTap),
            const SizedBox(height: 23),
            _SignUpButton(onPressed: isLoading ? null : onSignUp),
          ],
        ),
      ),
    );
  }
}

class _AccountTypeNotice extends StatelessWidget {
  const _AccountTypeNotice({required this.isTeaching});

  final bool isTeaching;

  @override
  Widget build(BuildContext context) {
    final title = isTeaching
        ? 'Teaching personnel account detected'
        : 'Student account';
    final message = isTeaching
        ? 'Official UCU email confirmed. Your Employee ID and work details are required.'
        : 'Use your student details below. Teaching personnel must enter an @ucu.edu.ph email.';
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: isTeaching ? const Color(0xFFE8F5EF) : const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isTeaching ? Icons.verified_outlined : Icons.school_outlined,
            size: 18,
            color: _SignupColors.text,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _SignupColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    color: _SignupColors.text,
                    fontSize: 10,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignupField extends StatelessWidget {
  const _SignupField({
    required this.controller,
    required this.label,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.validator,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final String? Function(String?)? validator;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final iconData = icon;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 11, bottom: 5),
          child: Text(
            label,
            style: const TextStyle(
              color: _SignupColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          obscureText: obscureText,
          readOnly: readOnly,
          validator: validator,
          cursorColor: _SignupColors.button,
          style: const TextStyle(
            color: _SignupColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            hintText: label,
            hintStyle: const TextStyle(
              color: _SignupColors.hintText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            prefixIcon: iconData == null
                ? null
                : _SignupFieldIcon(icon: iconData),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            errorStyle: const TextStyle(
              fontSize: 9,
              height: 0.9,
              fontWeight: FontWeight.w700,
              color: _SignupColors.error,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _SignupColors.fieldBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _SignupColors.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: _SignupColors.button,
                width: 1.2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _SignupColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: _SignupColors.error,
                width: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SignupDropdownField extends StatelessWidget {
  const _SignupDropdownField({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.validator,
  });

  final String label;
  final IconData icon;
  final String? value;
  final List<String> items;
  final ValueChanged<String?>? onChanged;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) {
    final effectiveValue = items.contains(value) ? value : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 11, bottom: 5),
          child: Text(
            label,
            style: const TextStyle(
              color: _SignupColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: effectiveValue,
          isExpanded: true,
          items: [
            for (final item in items)
              DropdownMenuItem<String>(
                value: item,
                child: Text(item, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
          validator: validator,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          style: const TextStyle(
            color: _SignupColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: onChanged == null
                ? const Color(0xFFF7F1E6)
                : Colors.white,
            hintText: onChanged == null ? 'Select college first' : label,
            hintStyle: const TextStyle(
              color: _SignupColors.hintText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            prefixIcon: Icon(icon, size: 18, color: _SignupColors.text),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            errorStyle: const TextStyle(
              fontSize: 9,
              height: 0.9,
              fontWeight: FontWeight.w700,
              color: _SignupColors.error,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _SignupColors.fieldBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _SignupColors.fieldBorder),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _SignupColors.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: _SignupColors.button,
                width: 1.2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _SignupColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: _SignupColors.error,
                width: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SignupFieldIcon extends StatelessWidget {
  const _SignupFieldIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      child: Icon(icon, size: 18, color: _SignupColors.text),
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  const _TermsCheckbox({required this.acceptedTerms, required this.onTap});

  final bool acceptedTerms;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: acceptedTerms,
      label: 'Read and accept the Terms and Conditions',
      child: InkWell(
        key: const Key('registration-terms-control'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: Checkbox(
                      value: acceptedTerms,
                      onChanged: (_) {},
                      activeColor: _SignupColors.button,
                      checkColor: _SignupColors.text,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: const BorderSide(
                        color: _SignupColors.text,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'I have read and accept the Terms and Conditions',
                  style: TextStyle(
                    color: _SignupColors.text,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const Icon(Icons.open_in_new_rounded, size: 15),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignUpButton extends StatelessWidget {
  const _SignUpButton({required this.onPressed});

  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _SignupColors.button,
          foregroundColor: _SignupColors.text,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
        child: onPressed == null
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _SignupColors.text,
                ),
              )
            : const Text('Sign Up'),
      ),
    );
  }
}

class _BubbleCluster extends StatelessWidget {
  const _BubbleCluster({this.top, this.left, this.right, required this.mirror});

  final double? top;
  final double? left;
  final double? right;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    const bubbles = [
      _BubbleSpec(23, 0, 30, _SignupColors.bubbleYellow),
      _BubbleSpec(52, 29, 29, _SignupColors.bubbleGray),
      _BubbleSpec(9, 30, 23, _SignupColors.bubbleYellow),
      _BubbleSpec(66, 38, 24, _SignupColors.bubbleYellow),
      _BubbleSpec(35, 52, 20, _SignupColors.bubbleGray),
      _BubbleSpec(0, 62, 26, _SignupColors.bubbleGray),
      _BubbleSpec(53, 73, 24, _SignupColors.bubbleYellow),
      _BubbleSpec(82, 80, 14, _SignupColors.bubbleYellow),
      _BubbleSpec(28, 98, 17, _SignupColors.bubbleGray),
      _BubbleSpec(51, 127, 20, _SignupColors.bubbleYellow),
    ];

    return Positioned(
      top: top,
      left: left,
      right: right,
      child: Transform.scale(
        scaleX: mirror ? -1 : 1,
        child: SizedBox(
          width: 118,
          height: 153,
          child: Stack(
            clipBehavior: Clip.none,
            children: [for (final bubble in bubbles) _Bubble(spec: bubble)],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.spec});

  final _BubbleSpec spec;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: spec.left,
      top: spec.top,
      child: Container(
        width: spec.size,
        height: spec.size,
        decoration: BoxDecoration(
          color: spec.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(40),
              blurRadius: 7,
              offset: const Offset(4, 5),
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleSpec {
  const _BubbleSpec(this.left, this.top, this.size, this.color);

  final double left;
  final double top;
  final double size;
  final Color color;
}

class _SignupColors {
  const _SignupColors._();

  static const background = Color(0xFFFEFEFE);
  static const card = Color(0xFFFFE9AC);
  static const button = Color(0xFFFFBE0A);
  static const text = Color(0xFF050505);
  static const hintText = Color(0xFF6C6250);
  static const fieldBorder = Color(0xFF8A7350);
  static const error = Color(0xFFB3261E);
  static const bubbleYellow = Color(0xFFFFCF52);
  static const bubbleGray = Color(0xFFD9D9D9);
}
