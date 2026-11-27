import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/philippine_mobile_formatter.dart';
import '../../../core/utils/student_identity_formatter.dart';
import '../../../models/pacc_availability_model.dart';
import '../../../models/profile_roles.dart';
import '../../../models/student_inquiry_model.dart';
import '../../../models/testing_service_schedule.dart';
import '../../../models/user_model.dart';
import '../../../providers/user_provider.dart';
import '../../../repositories/inquiry_repository.dart';
import '../../../repositories/pacc_availability_repository.dart';
import '../../../services/firebase/firebase_error_message.dart';
import 'student_inquiries_screen.dart';

class _TestingColors {
  const _TestingColors._();
  static const background = Color(0xFFF7F8F4);
  static const ink = Color(0xFF1D343C);
  static const muted = Color(0xFF6B7D83);
  static const border = Color(0xFFE5EAE5);
  static const sun = Color(0xFFFFCD3A);
  static const sunSoft = Color(0xFFFFF5D8);
  static const greenBg = Color(0xFFE3F1E6);
  static const greenInk = Color(0xFF1F6B3A);
}

String _newTestingRequestId() {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List.generate(24, (_) => alphabet[random.nextInt(alphabet.length)])
      .join();
}

String _formatManilaDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
}

DateTime _nextAvailableTestingDate(DateTime now) =>
    nextSelectableTestingServiceDate(startingFrom: now);

typedef TestingDocumentPicker =
    Future<PendingTestingDocument?> Function(TestingDocumentKind kind);

/// 3-step Testing Service request wizard aligned with the UCU PACC Charter:
/// Step 1: Applicant & Document Upload (Endorsement Letter, Official Receipt PHP 250, Admission Requirements)
/// Step 2: Contact & Schedule Preferences (auto-formatted mobile for SMS, Mon-Sat 8 AM-5 PM availability)
/// Step 3: Pre-Testing Forms & Consent (Personal Data Sheet, Informed Consent, SMS 2-5 min review banner)
class TestingServiceInquiryScreen extends StatefulWidget {
  const TestingServiceInquiryScreen({
    super.key,
    this.user,
    this.repository,
    this.currentUserIdProvider,
    this.nowProvider = DateTime.now,
    this.pickFile,
    this.availabilityStream,
    this.myInquiriesStream,
  });

  final UserModel? user;
  final InquiryRepository? repository;
  final String? Function()? currentUserIdProvider;
  final DateTime Function() nowProvider;
  final TestingDocumentPicker? pickFile;
  final Stream<PaccAvailabilityModel?>? availabilityStream;
  final Stream<List<StudentInquiryRecord>>? myInquiriesStream;

  @override
  State<TestingServiceInquiryScreen> createState() =>
      _TestingServiceInquiryScreenState();
}

class _TestingServiceInquiryScreenState
    extends State<TestingServiceInquiryScreen> {
  final _mobileController = TextEditingController();
  final _preferredNoteController = TextEditingController();
  final _messageController = TextEditingController(
    text: 'Good day! I would like to request a Testing Service schedule.',
  );
  final _pdsNameController = TextEditingController();
  final _pdsEmailController = TextEditingController();
  final _pdsIdController = TextEditingController();
  final _pdsOfficeController = TextEditingController();
  final _pdsCourseController = TextEditingController();
  final _scrollController = ScrollController();

  late InquiryRepository _repository;
  int _step = 0;
  bool _defaultsSeeded = false;
  TestingServiceClientType? _clientType;
  bool _isStudentForOjt = false;
  PendingTestingDocument? _endorsementDoc;
  PendingTestingDocument? _receiptDoc;
  final List<PendingTestingDocument> _admissionDocs = [];
  late DateTime _preferredDate;
  int _preferredHour = 9;
  bool _pdsConfirmed = false;
  bool _informedConsentConfirmed = false;
  bool _pickingFile = false;
  bool _submitting = false;
  String? _submitProgressLabel;
  String? _requestId;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        InquiryRepository(currentUserIdProvider: widget.currentUserIdProvider);
    _preferredDate = _nextAvailableTestingDate(widget.nowProvider());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _seedDefaultsIfNeeded(_resolveUser(context));
  }

  @override
  void didUpdateWidget(covariant TestingServiceInquiryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.currentUserIdProvider != widget.currentUserIdProvider) {
      _repository =
          widget.repository ??
          InquiryRepository(
            currentUserIdProvider: widget.currentUserIdProvider,
          );
    }
    if (oldWidget.user != widget.user) {
      _defaultsSeeded = false;
      _seedDefaultsIfNeeded(_resolveUser(context));
    }
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _preferredNoteController.dispose();
    _messageController.dispose();
    _pdsNameController.dispose();
    _pdsEmailController.dispose();
    _pdsIdController.dispose();
    _pdsOfficeController.dispose();
    _pdsCourseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  UserModel? _resolveUser(BuildContext context) {
    if (widget.user != null) return widget.user;
    try {
      return context.watch<UserProvider>().user;
    } on ProviderNotFoundException {
      return null;
    }
  }

  void _seedDefaultsIfNeeded(UserModel? user) {
    if (_defaultsSeeded || user == null) return;
    _defaultsSeeded = true;
    final pop = user.effectivePopulationRole;
    if (pop == PopulationRole.student) {
      _clientType = TestingServiceClientType.studentForOjt;
    } else if (pop == PopulationRole.teaching ||
        pop == PopulationRole.nonTeaching) {
      _clientType = TestingServiceClientType.ucuEmployee;
    }
    if (_pdsNameController.text.isEmpty && user.displayName.trim().isNotEmpty) {
      _pdsNameController.text = user.displayName.trim();
    }
    if (_pdsEmailController.text.isEmpty) {
      _pdsEmailController.text = visibleContactEmail(user.email);
    }
    if (_pdsIdController.text.isEmpty) {
      _pdsIdController.text = pop == PopulationRole.student
          ? (user.schoolId?.trim() ?? '')
          : (user.employeeId?.trim() ?? '');
    }
    if (_pdsOfficeController.text.isEmpty) {
      _pdsOfficeController.text =
          (user.department ?? user.sector ?? '').trim();
    }
    if (_pdsCourseController.text.isEmpty) {
      _pdsCourseController.text = pop == PopulationRole.student
          ? (user.course?.trim() ?? '')
          : (user.position?.trim() ?? '');
    }
  }

  String? _resolveUid(UserModel? user) {
    final fromProvider = widget.currentUserIdProvider?.call()?.trim();
    if (fromProvider != null && fromProvider.isNotEmpty) return fromProvider;
    final fromRepo = _repository.currentUserId?.trim();
    if (fromRepo != null && fromRepo.isNotEmpty) return fromRepo;
    if (Firebase.apps.isNotEmpty) {
      final authUid = FirebaseAuth.instance.currentUser?.uid.trim();
      if (authUid != null && authUid.isNotEmpty) return authUid;
    }
    final fromUser = user?.id.trim();
    return fromUser != null && fromUser.isNotEmpty ? fromUser : null;
  }

  Future<PendingTestingDocument?> _defaultPickFile(
    TestingDocumentKind kind,
  ) async {
    const typeGroup = XTypeGroup(
      label: 'Images or PDF',
      extensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    final selected = await openFile(acceptedTypeGroups: [typeGroup]);
    if (selected == null) return null;
    final mime = testingDocumentMimeType(selected.name);
    if (mime == null) {
      throw const FormatException('Please select a JPG, PNG, or PDF file.');
    }
    final bytes = await selected.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('The selected file is empty.');
    }
    if (bytes.length > testingDocumentMaxBytes) {
      throw const FormatException('Selected file exceeds the 5 MB limit.');
    }
    return PendingTestingDocument(
      name: standardizedTestingDocumentFileName(kind, selected.name),
      contentType: mime,
      bytes: bytes,
      kind: kind,
    );
  }

  Future<void> _handlePickFile(TestingDocumentKind kind) async {
    if (_pickingFile || _submitting) return;
    if (kind == TestingDocumentKind.admissionRequirement &&
        _admissionDocs.length >= testingDocumentMaxAdmissionFiles) {
      _showSnackBar(
        'You can attach up to $testingDocumentMaxAdmissionFiles admission requirement files.',
      );
      return;
    }
    setState(() => _pickingFile = true);
    try {
      final picker = widget.pickFile ?? _defaultPickFile;
      final picked = await picker(kind);
      if (!mounted || picked == null) return;
      if (picked.size <= 0 || picked.size > testingDocumentMaxBytes) {
        _showSnackBar('Documents must be 5 MB or smaller.');
        return;
      }
      setState(() {
        switch (kind) {
          case TestingDocumentKind.endorsementLetter:
            _endorsementDoc = picked;
          case TestingDocumentKind.officialReceipt:
            _receiptDoc = picked;
          case TestingDocumentKind.admissionRequirement:
            _admissionDocs.add(picked);
        }
      });
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(
        error is FormatException
            ? error.message
            : 'Unable to select this file right now.',
      );
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _nextStep(
    TestingServiceClientEligibility eligibility, [
    PaccAvailabilityModel? availability,
  ]) {
    FocusScope.of(context).unfocus();
    if (_step == 0) {
      if (eligibility.requiresOjtConfirmation && !_isStudentForOjt) {
        _showSnackBar(
          'Please confirm that you are availing Testing Service for OJT.',
        );
        return;
      }
      if (_endorsementDoc == null || _receiptDoc == null) {
        _showSnackBar(
          'Please upload both required documents: Endorsement Letter and Official Receipt (PHP 250.00).',
        );
        return;
      }
    } else if (_step == 1) {
      if (!isValidPhilippineMobile(_mobileController.text)) {
        _showSnackBar(
          'Enter a valid Philippine mobile number (e.g. +63 917 123 4567).',
        );
        return;
      }
      final preferredInstant = testingServiceInstantFromManila(
        year: _preferredDate.year,
        month: _preferredDate.month,
        day: _preferredDate.day,
        hour: _preferredHour,
      );
      final slots = testingServiceSlotsForDate(
        _preferredDate,
        availability: availability,
        now: widget.nowProvider(),
      );
      final isSelectable = slots.any(
        (slot) => slot.available && slot.instant == preferredInstant,
      );
      if (!isSelectable) {
        _showSnackBar(
          availability != null
              ? 'Choose a future open date & time slot based on PACC schedule.'
              : 'Choose a future preferred date & time (Monday–Saturday, 8:00 AM–5:00 PM).',
        );
        return;
      }
    }
    setState(() => _step++);
    _scrollToTop();
  }

  void _previousStep() {
    if (_submitting) return;
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step--);
    _scrollToTop();
  }

  Future<void> _pickPreferredDate(PaccAvailabilityModel? availability) async {
    final manilaToday = widget.nowProvider().toUtc().add(
      const Duration(hours: 8),
    );
    final firstDate = DateTime(
      manilaToday.year,
      manilaToday.month,
      manilaToday.day,
    );
    var initialDate = _preferredDate.isBefore(firstDate)
        ? firstDate
        : _preferredDate;
    final now = widget.nowProvider();
    if (!isTestingServiceDateSelectable(
      initialDate,
      availability: availability,
      now: now,
    )) {
      initialDate = nextSelectableTestingServiceDate(
        startingFrom: firstDate,
        availability: availability,
      );
    }
    if (!isTestingServiceDateSelectable(
      initialDate,
      availability: availability,
      now: now,
    )) {
      _showSnackBar('No open Testing Service dates are currently scheduled.');
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 180)),
      selectableDayPredicate: (date) => isTestingServiceDateSelectable(
        date,
        availability: availability,
        now: now,
      ),
    );
    if (picked != null && mounted) {
      final slots = testingServiceSlotsForDate(
        picked,
        availability: availability,
        now: now,
      ).where((slot) => slot.available).toList(growable: false);
      setState(() {
        _preferredDate = picked;
        if (slots.isNotEmpty &&
            !slots.any(
              (slot) =>
                  slot.instant.toUtc().add(const Duration(hours: 8)).hour ==
                  _preferredHour,
            )) {
          _preferredHour = slots.first.instant
              .toUtc()
              .add(const Duration(hours: 8))
              .hour;
        }
      });
    }
  }

  Future<void> _submit(
    TestingServiceClientEligibility eligibility,
    String uid,
  ) async {
    if (_submitting) return;
    final pdsName = _pdsNameController.text.trim();
    final pdsEmail = _pdsEmailController.text.trim();
    if (isSyntheticStudentEmail(pdsEmail)) {
      _showSnackBar(
        'Enter a personal or institutional email address instead of an internal login alias.',
      );
      return;
    }
    if (pdsName.isEmpty ||
        (pdsEmail.isNotEmpty &&
            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(pdsEmail))) {
      _showSnackBar(
        'Please complete your Full Name and valid Email on the Personal Data Sheet.',
      );
      return;
    }
    if (!_pdsConfirmed || !_informedConsentConfirmed) {
      _showSnackBar(
        'Please agree to both the Personal Data Sheet and Informed Consent statements.',
      );
      return;
    }
    final endorsement = _endorsementDoc;
    final receipt = _receiptDoc;
    if (endorsement == null || receipt == null) {
      _showSnackBar('Please upload your Endorsement Letter and Official Receipt.');
      return;
    }

    _requestId ??= _newTestingRequestId();
    setState(() {
      _submitting = true;
      _submitProgressLabel = 'Uploading documents…';
    });
    try {
      final uploadedEndorsement =
          endorsement.uploadedRef ??
          await _repository.uploadTestingServiceDocument(file: endorsement);
      _endorsementDoc = endorsement.copyWithUploaded(uploadedEndorsement);

      final uploadedReceipt =
          receipt.uploadedRef ??
          await _repository.uploadTestingServiceDocument(file: receipt);
      _receiptDoc = receipt.copyWithUploaded(uploadedReceipt);

      final uploadedAdmissions = <TestingServiceDocumentRef>[];
      for (var i = 0; i < _admissionDocs.length; i++) {
        final item = _admissionDocs[i];
        final ref =
            item.uploadedRef ??
            await _repository.uploadTestingServiceDocument(file: item);
        _admissionDocs[i] = item.copyWithUploaded(ref);
        uploadedAdmissions.add(ref);
      }

      if (!mounted) return;
      setState(() => _submitProgressLabel = 'Submitting request…');

      final preferredInstant = testingServiceInstantFromManila(
        year: _preferredDate.year,
        month: _preferredDate.month,
        day: _preferredDate.day,
        hour: _preferredHour,
      );

      final inquiryId = await _repository.submitTestingServiceInquiry(
        isStudentForOjt: eligibility.requiresOjtConfirmation
            ? _isStudentForOjt
            : false,
        endorsementLetterConfirmed: true,
        officialReceiptConfirmed: true,
        mobileNumber: formatPhilippineMobile(_mobileController.text),
        endorsementLetter: uploadedEndorsement,
        officialReceipt: uploadedReceipt,
        admissionRequirements: uploadedAdmissions,
        preferredScheduleAt: preferredInstant,
        personalDataSheet: PersonalDataSheetInput(
          fullName: pdsName,
          email: pdsEmail,
          idNumber: _pdsIdController.text.trim(),
          officeOrCollege: _pdsOfficeController.text.trim(),
          courseOrPosition: _pdsCourseController.text.trim(),
        ),
        personalDataSheetConfirmed: _pdsConfirmed,
        informedConsentConfirmed: _informedConsentConfirmed,
        message: _messageController.text.trim(),
        preferredScheduleNote: _preferredNoteController.text.trim(),
        requestId: _requestId,
      );
      if (!mounted) return;
      _requestId = null;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => StudentInquiryDetailScreen(
            inquiryId: inquiryId,
            userId: uid,
            repository: _repository,
            currentUserIdProvider: widget.currentUserIdProvider,
            showTestingSubmissionBanner: true,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(
        FirebaseErrorMessage.describe(
          error,
          fallback: 'Unable to submit your Testing Service request right now.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitProgressLabel = null;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  void _showImagePreview(
    PendingTestingDocument doc, {
    int? admissionIndex,
  }) {
    final displayName = doc.displayFileName(admissionIndex: admissionIndex);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  tooltip: 'Close preview',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420, maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Image.memory(doc.bytes, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _resolveUser(context);
    final uid = _resolveUid(user);
    final eligibility = evaluateTestingServiceClientEligibility(user);
    final availabilityStream =
        widget.availabilityStream ??
        (Firebase.apps.isNotEmpty
            ? PaccAvailabilityRepository().watchCurrent()
            : null);
    final inquiriesStream =
        widget.myInquiriesStream ??
        (uid != null && Firebase.apps.isNotEmpty
            ? _repository.watchMyInquiries(uid)
            : null);

    return Scaffold(
      backgroundColor: _TestingColors.background,
      appBar: AppBar(
        backgroundColor: _TestingColors.sun,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _previousStep,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Testing Service Request',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
      body: !eligibility.isEligible || uid == null
          ? SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
              child: _IneligibleBanner(
                message:
                    eligibility.ineligibleReason ??
                    'Sign in with an eligible account to request Testing Service.',
              ),
            )
          : StreamBuilder<List<StudentInquiryRecord>>(
              stream: inquiriesStream,
              builder: (context, inquirySnap) {
                final activeRequest = (inquirySnap.data ?? const [])
                    .where((inq) => inq.isActiveTestingService)
                    .cast<StudentInquiryRecord?>()
                    .firstWhere((item) => item != null, orElse: () => null);
                if (activeRequest != null) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                    child: _ActiveTestingRequestLockBanner(
                      inquiry: activeRequest,
                      onOpenInquiries: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => MyInquiriesScreen(
                            userId: uid,
                            repository: _repository,
                            currentUserIdProvider: widget.currentUserIdProvider,
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return StreamBuilder<PaccAvailabilityModel?>(
                  stream: availabilityStream,
                  builder: (context, availSnap) {
                    final availability = availSnap.data;
                    return Column(
                      children: [
                        _WizardProgressHeader(step: _step),
                        Expanded(
                          child: SingleChildScrollView(
                            key: PageStorageKey('testing-wizard-step-$_step'),
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                            child: switch (_step) {
                              0 => _buildStep1(eligibility),
                              1 => _buildStep2(eligibility, availability),
                              _ => _buildStep3(eligibility, uid),
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildStep1(TestingServiceClientEligibility eligibility) {
    final isStudent = _clientType == TestingServiceClientType.studentForOjt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoCard(
          title: 'Client Type',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<TestingServiceClientType>(
                groupValue: _clientType,
                onChanged: (value) {
                  if (value != null && !eligibility.requiresOjtConfirmation &&
                      value == TestingServiceClientType.ucuEmployee) {
                    setState(() => _clientType = value);
                  }
                },
                child: Column(
                  children: [
                    RadioListTile<TestingServiceClientType>(
                      key: const ValueKey('testing-client-employee'),
                      contentPadding: EdgeInsets.zero,
                      value: TestingServiceClientType.ucuEmployee,
                      enabled: !eligibility.requiresOjtConfirmation,
                      title: const Text(
                        'UCU Employee',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Teaching or Non-Teaching personnel (Endorsement from Human Capital Management Office)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    RadioListTile<TestingServiceClientType>(
                      key: const ValueKey('testing-client-ojt'),
                      contentPadding: EdgeInsets.zero,
                      value: TestingServiceClientType.studentForOjt,
                      enabled: eligibility.requiresOjtConfirmation,
                      title: const Text(
                        'Student for OJT',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'OJT internship testing (Endorsement from College Internship Coordinator)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              if (isStudent) ...[
                const Divider(height: 16),
                CheckboxListTile(
                  key: const ValueKey('testing-ojt-checkbox'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _isStudentForOjt,
                  onChanged: _submitting
                      ? null
                      : (value) =>
                          setState(() => _isStudentForOjt = value == true),
                  title: const Text(
                    'I am a student availing Testing Service for OJT',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _TestingColors.ink,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _InfoCard(
          title: 'Required Document Uploads',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DocumentUploadSlot(
                slotKey: const ValueKey('testing-upload-endorsement'),
                title: 'Endorsement Letter *',
                subtitle: isStudent
                    ? 'From your College Internship Coordinator (JPG, PNG, or PDF, max 5 MB)'
                    : 'From the Human Capital Management Office (JPG, PNG, or PDF, max 5 MB)',
                document: _endorsementDoc,
                busy: _pickingFile || _submitting,
                onPick: () =>
                    _handlePickFile(TestingDocumentKind.endorsementLetter),
                onPreviewImage: _showImagePreview,
                onRemove: () => setState(() => _endorsementDoc = null),
              ),
              const Divider(height: 24),
              _DocumentUploadSlot(
                slotKey: const ValueKey('testing-upload-receipt'),
                title: 'Official Receipt (PHP 250.00) *',
                subtitle:
                    'Proof of payment for the PHP 250.00 testing fee (JPG, PNG, or PDF, max 5 MB)',
                document: _receiptDoc,
                busy: _pickingFile || _submitting,
                onPick: () =>
                    _handlePickFile(TestingDocumentKind.officialReceipt),
                onPreviewImage: _showImagePreview,
                onRemove: () => setState(() => _receiptDoc = null),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _InfoCard(
          title: 'Admission Requirements (Optional Pre-Screening)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Upload digital scans of the original and 2 photocopies if applicable (up to 3 files, max 5 MB each).',
                style: TextStyle(fontSize: 12, color: _TestingColors.muted),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('testing-upload-admission'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  minimumSize: const Size(0, 44),
                ),
                onPressed:
                    _pickingFile ||
                        _submitting ||
                        _admissionDocs.length >=
                            testingDocumentMaxAdmissionFiles
                    ? null
                    : () => _handlePickFile(
                        TestingDocumentKind.admissionRequirement,
                      ),
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  _admissionDocs.isEmpty
                      ? 'Add Admission Requirement Scan'
                      : 'Add Another Scan (${_admissionDocs.length}/$testingDocumentMaxAdmissionFiles)',
                ),
              ),
              for (var i = 0; i < _admissionDocs.length; i++) ...[
                const SizedBox(height: 10),
                _UploadedFilePreviewTile(
                  document: _admissionDocs[i],
                  admissionIndex: i + 1,
                  onPreviewImage: () => _showImagePreview(
                    _admissionDocs[i],
                    admissionIndex: i + 1,
                  ),
                  onRemove: () => setState(() => _admissionDocs.removeAt(i)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        _WizardPrimaryButton(
          buttonKey: const ValueKey('testing-step1-next'),
          label: 'Continue to Contact & Schedule',
          icon: const Icon(Icons.arrow_forward_rounded, size: 19),
          onPressed: () => _nextStep(eligibility),
        ),
      ],
    );
  }

  Widget _buildStep2(
    TestingServiceClientEligibility eligibility, [
    PaccAvailabilityModel? availability,
  ]) {
    final now = widget.nowProvider();
    var displayDate = _preferredDate;
    if (availability != null &&
        !isTestingServiceDateSelectable(
          displayDate,
          availability: availability,
          now: now,
        )) {
      final nextDate = nextSelectableTestingServiceDate(
        startingFrom: displayDate,
        availability: availability,
      );
      if (isTestingServiceDateSelectable(
        nextDate,
        availability: availability,
        now: now,
      )) {
        displayDate = nextDate;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _preferredDate != nextDate) {
            setState(() => _preferredDate = nextDate);
          }
        });
      }
    }
    final slots = testingServiceSlotsForDate(
      displayDate,
      availability: availability,
      now: now,
    ).where((slot) => slot.available).toList(growable: false);
    final selectedHour = slots.any(
      (slot) =>
          slot.instant.toUtc().add(const Duration(hours: 8)).hour ==
          _preferredHour,
    )
        ? _preferredHour
        : (slots.isNotEmpty
              ? slots.first.instant.toUtc().add(const Duration(hours: 8)).hour
              : _preferredHour);
    if (slots.isNotEmpty && selectedHour != _preferredHour) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _preferredHour = selectedHour);
        }
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoCard(
          title: 'Mobile Number for SMS Updates *',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The Psychometrician-in-charge sends your testing schedule via SMS to this number (and via MindMate in-app notifications).',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: _TestingColors.muted,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('testing-mobile-input'),
                controller: _mobileController,
                keyboardType: TextInputType.phone,
                inputFormatters: const [PhilippineMobileInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                  hintText: '+63 917 123 4567',
                  prefixIcon: Icon(Icons.sms_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _InfoCard(
          title: 'Preferred Availability',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                availability != null
                    ? 'Slots follow the active PACC Admin schedule (Asia/Manila).'
                    : 'Testing Service hours: Monday–Saturday, 8:00 AM–5:00 PM (PHT).',
                style: const TextStyle(fontSize: 12, color: _TestingColors.muted),
              ),
              if (availability != null && availability.notice.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  availability.notice,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _TestingColors.ink,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('testing-preferred-date'),
                    onPressed: () => _pickPreferredDate(availability),
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(_formatManilaDate(displayDate)),
                  ),
                  if (slots.isNotEmpty)
                    DropdownButton<int>(
                      key: const ValueKey('testing-preferred-time'),
                      value: selectedHour,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _preferredHour = value);
                        }
                      },
                      items: [
                        for (final slot in slots)
                          DropdownMenuItem<int>(
                            value: slot.instant
                                .toUtc()
                                .add(const Duration(hours: 8))
                                .hour,
                            child: Text('${slot.label} (PHT)'),
                          ),
                      ],
                    )
                  else
                    const Text(
                      'No open PACC time slots on this date.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9E2A2B),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('testing-preferred-note'),
                controller: _preferredNoteController,
                maxLines: 2,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Preferred schedule note (optional)',
                  hintText: 'e.g. Available weekday mornings',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WizardPrimaryButton(
              buttonKey: const ValueKey('testing-step2-next'),
              label: 'Continue to Forms & Consent',
              icon: const Icon(Icons.arrow_forward_rounded, size: 19),
              onPressed: () => _nextStep(eligibility, availability),
            ),
            const SizedBox(height: 10),
            _WizardSecondaryButton(
              buttonKey: const ValueKey('testing-step2-back'),
              label: 'Back',
              onPressed: _previousStep,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep3(
    TestingServiceClientEligibility eligibility,
    String uid,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _InfoCard(
        title: 'Personal Data Sheet (Pre-Testing Form)',
        child: Column(
          children: [
            TextField(
              key: const ValueKey('testing-pds-name'),
              controller: _pdsNameController,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('testing-pds-email'),
              controller: _pdsEmailController,
              enabled: !_submitting,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Personal / Contact Email (Optional)',
                hintText: 'e.g. name@ucu.edu.ph',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('testing-pds-id'),
              controller: _pdsIdController,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Student / Employee ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('testing-pds-office'),
              controller: _pdsOfficeController,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'College / Office / Sector',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('testing-pds-course'),
              controller: _pdsCourseController,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Course / Position',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _InfoCard(
        title: 'Digital Agreements & Message',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('testing-message'),
              controller: _messageController,
              enabled: !_submitting,
              minLines: 2,
              maxLines: 3,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Request message',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const ValueKey('testing-pds-consent'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _pdsConfirmed,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _pdsConfirmed = v == true),
              title: const Text(
                'Personal Data Sheet Confirmation',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'I certify that the Personal Data Sheet information above is accurate for PACC testing records.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('testing-informed-consent'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _informedConsentConfirmed,
              onChanged: _submitting
                  ? null
                  : (v) =>
                      setState(() => _informedConsentConfirmed = v == true),
              title: const Text(
                'Informed Consent for Psychological Testing',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'I consent to psychological assessment and confidential processing of my test battery and test report by PACC.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Material(
        key: const ValueKey('testing-sms-confirmation-banner'),
        color: _TestingColors.greenBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: _TestingColors.greenInk.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.sms_outlined, color: _TestingColors.greenInk),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'After submission, the Psychometrician-in-charge will review your uploaded documents (2–5 minutes processing time) and send your confirmed testing schedule via SMS to ${formatPhilippineMobile(_mobileController.text)} and through MindMate in-app notifications.',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: _TestingColors.greenInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WizardPrimaryButton(
            buttonKey: const ValueKey('testing-submit-button'),
            label: _submitProgressLabel ?? 'Submit Testing Service Request',
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.send_outlined, size: 18),
            onPressed: _submitting ? null : () => _submit(eligibility, uid),
          ),
          const SizedBox(height: 10),
          _WizardSecondaryButton(
            buttonKey: const ValueKey('testing-step3-back'),
            label: 'Back',
            onPressed: _submitting ? null : _previousStep,
          ),
        ],
      ),
    ],
  );
}

class _WizardProgressHeader extends StatelessWidget {
  const _WizardProgressHeader({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Applicant & Docs',
      'Contact & Schedule',
      'Forms & Consent',
    ];
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'STEP ${step + 1} OF 3',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF8A6810),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  labels[step],
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _TestingColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (step + 1) / 3,
              minHeight: 6,
              backgroundColor: _TestingColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(_TestingColors.sun),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        i < step
                            ? Icons.check_circle
                            : i == step
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 15,
                        color: i <= step
                            ? const Color(0xFF8A6810)
                            : _TestingColors.muted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: i == step
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: i <= step
                                ? _TestingColors.ink
                                : _TestingColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DocumentUploadSlot extends StatelessWidget {
  const _DocumentUploadSlot({
    required this.slotKey,
    required this.title,
    required this.subtitle,
    required this.document,
    required this.busy,
    required this.onPick,
    required this.onPreviewImage,
    required this.onRemove,
  });

  final Key slotKey;
  final String title;
  final String subtitle;
  final PendingTestingDocument? document;
  final bool busy;
  final VoidCallback onPick;
  final ValueChanged<PendingTestingDocument> onPreviewImage;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: _TestingColors.ink,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: _TestingColors.muted),
      ),
      const SizedBox(height: 10),
      if (document == null)
        OutlinedButton.icon(
          key: slotKey,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            minimumSize: const Size(0, 44),
          ),
          onPressed: busy ? null : onPick,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Choose File (JPG, PNG, PDF)'),
        )
      else ...[
        _UploadedFilePreviewTile(
          document: document!,
          onPreviewImage: () => onPreviewImage(document!),
          onRemove: onRemove,
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          key: slotKey,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: busy ? null : onPick,
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('Replace file'),
        ),
      ],
    ],
  );
}

class _UploadedFilePreviewTile extends StatelessWidget {
  const _UploadedFilePreviewTile({
    required this.document,
    required this.onPreviewImage,
    required this.onRemove,
    this.admissionIndex,
  });

  final PendingTestingDocument document;
  final VoidCallback onPreviewImage;
  final VoidCallback onRemove;
  final int? admissionIndex;

  @override
  Widget build(BuildContext context) {
    final sizeKb = max(1, (document.size / 1024).round());
    final displayName = document.displayFileName(admissionIndex: admissionIndex);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _TestingColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _TestingColors.border),
      ),
      child: Row(
        children: [
          if (document.isImage)
            InkWell(
              onTap: onPreviewImage,
              borderRadius: BorderRadius.circular(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  document.bytes,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(Icons.image_outlined),
                  ),
                ),
              ),
            )
          else
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _TestingColors.sunSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.picture_as_pdf_outlined,
                color: Color(0xFF8A6810),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _TestingColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${document.isPdf ? 'PDF' : 'Image'} · $sizeKb KB · Ready',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _TestingColors.greenInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (document.isImage)
            IconButton(
              tooltip: 'Preview $displayName',
              padding: EdgeInsets.zero,
              alignment: Alignment.center,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              iconSize: 20,
              onPressed: onPreviewImage,
              icon: const Icon(Icons.visibility_outlined),
            ),
          IconButton(
            tooltip: 'Remove $displayName',
            padding: EdgeInsets.zero,
            alignment: Alignment.center,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            iconSize: 20,
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _WizardPrimaryButton extends StatelessWidget {
  const _WizardPrimaryButton({
    required this.buttonKey,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      key: buttonKey,
      style: FilledButton.styleFrom(
        backgroundColor: _TestingColors.sun,
        foregroundColor: Colors.black,
        disabledBackgroundColor: _TestingColors.sun.withValues(alpha: 0.55),
        disabledForegroundColor: Colors.black54,
        minimumSize: const Size(double.infinity, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        alignment: Alignment.center,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}

class _WizardSecondaryButton extends StatelessWidget {
  const _WizardSecondaryButton({
    required this.buttonKey,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      key: buttonKey,
      style: OutlinedButton.styleFrom(
        foregroundColor: _TestingColors.ink,
        minimumSize: const Size(double.infinity, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        alignment: Alignment.center,
        side: const BorderSide(color: _TestingColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: _TestingColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _TestingColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    ),
  );
}

class _ActiveTestingRequestLockBanner extends StatelessWidget {
  const _ActiveTestingRequestLockBanner({
    required this.inquiry,
    required this.onOpenInquiries,
  });

  final StudentInquiryRecord inquiry;
  final VoidCallback onOpenInquiries;

  @override
  Widget build(BuildContext context) {
    final statusLabel =
        inquiry.testingSchedule?.status.label ?? inquiry.status.label;
    return Container(
      key: const ValueKey('testing-active-request-lock-banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _TestingColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_clock_outlined, color: _TestingColors.ink),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ongoing Testing Service Request ($statusLabel)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _TestingColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Only one Testing Service schedule request may be active at a time. You can submit a new request once PACC marks your current schedule as Completed.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: _TestingColors.muted,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('testing-lock-view-inquiries'),
              style: FilledButton.styleFrom(
                backgroundColor: _TestingColors.sun,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onPressed: onOpenInquiries,
              icon: const Icon(Icons.inbox_outlined),
              label: const Text(
                'View My Inquiries',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IneligibleBanner extends StatelessWidget {
  const _IneligibleBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5B8B8)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline, color: Color(0xFF9E2A2B)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: _TestingColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}
