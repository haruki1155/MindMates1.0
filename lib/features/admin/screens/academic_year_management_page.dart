import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../models/profile_roles.dart';
import '../../../repositories/admin_portal_repository.dart';
import '../domain/report_generation_models.dart';
import '../theme/admin_theme.dart';

/// Dedicated admin workspace for creating, viewing, and closing academic years.
class AcademicYearManagementPage extends StatefulWidget {
  const AcademicYearManagementPage({
    super.key,
    required this.repository,
    this.nowProvider,
  });

  final AdminPortalRepository repository;
  final DateTime Function()? nowProvider;

  @override
  State<AcademicYearManagementPage> createState() =>
      _AcademicYearManagementPageState();
}

class _AcademicYearManagementPageState
    extends State<AcademicYearManagementPage> {
  static final _schoolYearPattern = RegExp(r'^(\d{4})-(\d{4})$');
  static final _isoDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  bool _loading = false;
  bool _submitting = false;
  String? _loadError;
  String? _statusMessage;
  bool _statusIsError = false;
  List<AcademicYearRecord> _years = const [];

  bool get _isAdmin => widget.repository.currentAccessRole == AccessRole.admin;
  bool get _isSuperAdmin => widget.repository.isSuperAdmin;

  DateTime _now() => (widget.nowProvider ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    if (_isAdmin) {
      _loadYears();
    }
  }

  @override
  void didUpdateWidget(covariant AcademicYearManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository && _isAdmin) {
      _loadYears();
    }
  }

  Future<void> _loadYears() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final years = await widget.repository.fetchAcademicYears(
        includeVoided: true,
      );
      if (!mounted) return;
      setState(() {
        _years = _sortedYears(years);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _friendlyError(
          error,
          fallback: 'Please check your connection and retry.',
        );
      });
    }
  }

  List<AcademicYearRecord> _sortedYears(List<AcademicYearRecord> items) {
    final copy = List<AcademicYearRecord>.of(items);
    copy.sort((a, b) {
      final rankDiff = _stateRank(
        a.periodState(now: _now()),
      ).compareTo(_stateRank(b.periodState(now: _now())));
      if (rankDiff != 0) return rankDiff;
      return b.schoolYear.compareTo(a.schoolYear);
    });
    return copy;
  }

  int _stateRank(AcademicYearPeriodState state) => switch (state) {
    AcademicYearPeriodState.current => 0,
    AcademicYearPeriodState.planned => 1,
    AcademicYearPeriodState.upcoming => 2,
    AcademicYearPeriodState.closed => 3,
    AcademicYearPeriodState.voided => 4,
    AcademicYearPeriodState.unknown => 5,
  };

  static String _friendlyError(Object error, {required String fallback}) {
    if (error is FirebaseFunctionsException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
      return '$fallback (${error.code})';
    }
    final raw = error.toString().trim();
    if (raw.isEmpty || raw.startsWith('Bad state:')) {
      return fallback;
    }
    return fallback;
  }

  static String? validateCreateInputs({
    required String schoolYear,
    required String startText,
    required String endText,
    DateTime? now,
  }) {
    final match = _schoolYearPattern.firstMatch(schoolYear);
    if (match == null) {
      return 'School year must use consecutive years in YYYY-YYYY format (e.g. 2026-2027).';
    }
    final startYear = int.parse(match.group(1)!);
    final endYear = int.parse(match.group(2)!);
    if (endYear != startYear + 1 || startYear < 2000 || startYear > 2100) {
      return 'School year must be consecutive years starting between 2000 and 2100 (e.g. 2026-2027).';
    }
    final maxStartYear = manilaCurrentSchoolStartYear(now) + 1;
    if (startYear > maxStartYear) {
      return 'School year $schoolYear is too far in the future. Plan at most one year ahead (through $maxStartYear-${maxStartYear + 1}).';
    }
    final todayKey = manilaTodayDateKey(now);
    if (startText.isEmpty && endText.isEmpty) {
      final defaultEnd = '$endYear-05-31';
      if (defaultEnd.compareTo(todayKey) < 0) {
        return 'Default end date ($defaultEnd) has already passed in Asia/Manila ($todayKey).';
      }
      return null;
    }
    if (startText.isEmpty || endText.isEmpty) {
      return 'Provide both start and end dates, or leave both blank for default bounds.';
    }
    final parsedStart = _parseCalendarDate(startText);
    final parsedEnd = _parseCalendarDate(endText);
    if (parsedStart == null || parsedEnd == null) {
      return 'Dates must be valid calendar dates in YYYY-MM-DD format.';
    }
    if (!parsedStart.isBefore(parsedEnd)) {
      return 'Start date must be earlier than end date.';
    }
    final minBound = DateTime.utc(startYear, 1, 1);
    final maxBound = DateTime.utc(endYear, 12, 31);
    if (parsedStart.isBefore(minBound) || parsedEnd.isAfter(maxBound)) {
      return 'Dates must fall within $startYear-01-01 through $endYear-12-31.';
    }
    if (endText.compareTo(todayKey) < 0) {
      return 'End date ($endText) has already passed in Asia/Manila ($todayKey).';
    }
    return null;
  }

  static DateTime? _parseCalendarDate(String value) {
    final match = _isoDatePattern.firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime.utc(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  Future<void> _openCreateDialog() async {
    final openSource = _years.cast<AcademicYearRecord?>().firstWhere(
      (item) => item != null && (item.isCurrent || item.isPlanned),
      orElse: () => _years.cast<AcademicYearRecord?>().firstWhere(
        (item) => item != null && !item.isVoided && !item.isUnknown,
        orElse: () => null,
      ),
    );

    final result = await showDialog<_CreateAcademicYearResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateAcademicYearDialog(
        now: _now(),
        copySourceYear: openSource?.schoolYear,
        existingYears: _years,
        onSubmit:
            ({
              required String schoolYear,
              String? startDate,
              String? endDate,
              String? copyFrom,
              required bool copyPopulation,
              String? reinstateReason,
            }) async {
              setState(() => _submitting = true);
              try {
                final updated = await widget.repository.createAcademicYear(
                  schoolYear: schoolYear,
                  startDate: startDate,
                  endDate: endDate,
                  copyFrom: copyFrom,
                  copyPopulation: copyPopulation,
                  reinstateReason: reinstateReason,
                );
                return updated;
              } finally {
                if (mounted) {
                  setState(() => _submitting = false);
                }
              }
            },
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _years = _sortedYears(result.years);
      _statusIsError = false;
      _statusMessage = result.reinstated
          ? 'Academic year ${result.schoolYear} reinstated as planned.'
          : 'Academic year ${result.schoolYear} created.';
    });
  }

  Future<void> _openActivateDialog(AcademicYearRecord year) async {
    final updated = await showDialog<List<AcademicYearRecord>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ActivateAcademicYearDialog(
        schoolYear: year.schoolYear,
        onConfirm: () async {
          setState(() => _submitting = true);
          try {
            return await widget.repository.activateAcademicYear(
              year.schoolYear,
              expectedRevision: year.revision,
            );
          } finally {
            if (mounted) {
              setState(() => _submitting = false);
            }
          }
        },
      ),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _years = _sortedYears(updated);
      _statusIsError = false;
      _statusMessage = 'Academic year ${year.schoolYear} is now active.';
    });
  }

  Future<void> _openCloseDialog(AcademicYearRecord year) async {
    final updated = await showDialog<List<AcademicYearRecord>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CloseAcademicYearDialog(
        schoolYear: year.schoolYear,
        onConfirm: () async {
          setState(() => _submitting = true);
          try {
            return await widget.repository.closeAcademicYear(
              year.schoolYear,
              expectedRevision: year.revision,
            );
          } finally {
            if (mounted) {
              setState(() => _submitting = false);
            }
          }
        },
      ),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _years = _sortedYears(updated);
      _statusIsError = false;
      _statusMessage = 'Academic year ${year.schoolYear} closed and locked.';
    });
  }

  Future<void> _openVoidDialog(AcademicYearRecord year) async {
    if (!_isSuperAdmin) return;
    final updated = await showDialog<List<AcademicYearRecord>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VoidAcademicYearDialog(
        schoolYear: year.schoolYear,
        onConfirm: ({required String reason, required String confirmation}) async {
          setState(() => _submitting = true);
          try {
            return await widget.repository.voidAcademicYear(
              schoolYear: year.schoolYear,
              reason: reason,
              confirmationText: confirmation,
              expectedRevision: year.revision,
            );
          } finally {
            if (mounted) {
              setState(() => _submitting = false);
            }
          }
        },
      ),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _years = _sortedYears(updated);
      _statusIsError = false;
      _statusMessage =
          'Academic year ${year.schoolYear} voided (audit history preserved).';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_person_outlined,
                      size: 36,
                      color: AdminColors.muted,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Administrator access is required.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.ink,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Only verified portal administrators can create or close academic years.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AdminColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        final horizontalPadding = compact ? 16.0 : 28.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            24,
            horizontalPadding,
            32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(compact: compact),
                  const SizedBox(height: 20),
                  if (_statusMessage != null) ...[
                    _InlineMessageBanner(
                      message: _statusMessage!,
                      isError: _statusIsError,
                      onDismiss: () => setState(() => _statusMessage = null),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_loading)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (_loadError != null)
                    _buildErrorCard()
                  else if (_years.isEmpty)
                    _buildEmptyCard()
                  else ...[
                    _buildSummaryStrip(compact: compact),
                    const SizedBox(height: 20),
                    ..._years.map((year) {
                      final now = _now();
                      final periodState = year.periodState(now: now);
                      final hasActiveCurrent = _years.any((y) => y.isCurrent);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AcademicYearRowCard(
                          year: year,
                          periodState: periodState,
                          compact: compact,
                          busy: _submitting,
                          isSuperAdmin: _isSuperAdmin,
                          hasActiveCurrentYear: hasActiveCurrent,
                          todayManila: manilaTodayDateKey(now),
                          onActivate: () => _openActivateDialog(year),
                          onClose: () => _openCloseDialog(year),
                          onVoid: () => _openVoidDialog(year),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader({required bool compact}) {
    const titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Academic Year Management',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AdminColors.ink,
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Configure counseling academic periods, enforce single-active-year boundaries, and lock completed years for historical reporting.',
          style: TextStyle(
            fontSize: 13.5,
            color: AdminColors.muted,
            height: 1.4,
          ),
        ),
      ],
    );

    final createButton = FilledButton.icon(
      onPressed: _loading || _submitting ? null : _openCreateDialog,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Create academic year'),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [titleBlock, const SizedBox(height: 14), createButton],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(child: titleBlock),
        const SizedBox(width: 16),
        createButton,
      ],
    );
  }

  Widget _buildSummaryStrip({required bool compact}) {
    final now = _now();
    final currentCount = _years
        .where(
          (y) => y.periodState(now: now) == AcademicYearPeriodState.current,
        )
        .length;
    final plannedCount = _years.where((y) {
      final state = y.periodState(now: now);
      return state == AcademicYearPeriodState.planned ||
          state == AcademicYearPeriodState.upcoming;
    }).length;
    final closedCount = _years
        .where((y) => y.periodState(now: now) == AcademicYearPeriodState.closed)
        .length;
    final voidedCount = _years
        .where((y) => y.periodState(now: now) == AcademicYearPeriodState.voided)
        .length;

    final cards = [
      _SummaryTile(
        label: 'Current',
        count: currentCount,
        accent: AdminColors.success,
      ),
      _SummaryTile(
        label: 'Planned',
        count: plannedCount,
        accent: AdminColors.accentStrong,
      ),
      _SummaryTile(
        label: 'Closed',
        count: closedCount,
        accent: AdminColors.muted,
      ),
      _SummaryTile(
        label: 'Voided',
        count: voidedCount,
        accent: AdminColors.danger,
      ),
    ];

    if (compact) {
      return Column(
        children: cards
            .map(
              (card) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: card,
              ),
            )
            .toList(),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }

  Widget _buildErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline,
              size: 32,
              color: AdminColors.danger,
            ),
            const SizedBox(height: 10),
            const Text(
              'Could not load academic years',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AdminColors.ink,
              ),
            ),
            if (_loadError != null) ...[
              const SizedBox(height: 6),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AdminColors.muted),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadYears,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.date_range_outlined, size: 34, color: AdminColors.muted),
            SizedBox(height: 12),
            Text(
              'No academic years configured yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AdminColors.ink,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Use Create academic year above to configure the first period and begin tracking counseling reports.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AdminColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateAcademicYearResult {
  const _CreateAcademicYearResult({
    required this.schoolYear,
    required this.years,
    this.reinstated = false,
  });

  final String schoolYear;
  final List<AcademicYearRecord> years;
  final bool reinstated;
}

class _CreateAcademicYearDialog extends StatefulWidget {
  const _CreateAcademicYearDialog({
    required this.now,
    required this.copySourceYear,
    required this.existingYears,
    required this.onSubmit,
  });

  final DateTime now;
  final String? copySourceYear;
  final List<AcademicYearRecord> existingYears;
  final Future<List<AcademicYearRecord>> Function({
    required String schoolYear,
    String? startDate,
    String? endDate,
    String? copyFrom,
    required bool copyPopulation,
    String? reinstateReason,
  })
  onSubmit;

  @override
  State<_CreateAcademicYearDialog> createState() =>
      _CreateAcademicYearDialogState();
}

class _CreateAcademicYearDialogState extends State<_CreateAcademicYearDialog> {
  final _schoolYearController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  final _reinstateReasonController = TextEditingController();
  bool _copyPopulation = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _schoolYearController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _reinstateReasonController.dispose();
    super.dispose();
  }

  AcademicYearRecord? get _matchingExistingYear {
    final target = _schoolYearController.text.trim();
    for (final item in widget.existingYears) {
      if (item.schoolYear == target) return item;
    }
    return null;
  }

  String? get _liveValidationHint {
    final schoolYear = _schoolYearController.text.trim();
    final startText = _startDateController.text.trim();
    final endText = _endDateController.text.trim();
    if (schoolYear.isEmpty && startText.isEmpty && endText.isEmpty) {
      return null;
    }
    final formatError = _AcademicYearManagementPageState.validateCreateInputs(
      schoolYear: schoolYear,
      startText: startText,
      endText: endText,
      now: widget.now,
    );
    if (formatError != null) return formatError;
    final existing = _matchingExistingYear;
    if (existing != null && !existing.isVoided) {
      return 'Academic year ${existing.schoolYear} already exists (${existing.status}).';
    }
    return null;
  }

  Future<void> _submit() async {
    final schoolYear = _schoolYearController.text.trim();
    final startText = _startDateController.text.trim();
    final endText = _endDateController.text.trim();
    final reinstateReason = _reinstateReasonController.text.trim();

    final validationError =
        _AcademicYearManagementPageState.validateCreateInputs(
          schoolYear: schoolYear,
          startText: startText,
          endText: endText,
          now: widget.now,
        );
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    final existing = _matchingExistingYear;
    if (existing != null && !existing.isVoided) {
      setState(
        () => _error =
            'Academic year ${existing.schoolYear} already exists (${existing.status}).',
      );
      return;
    }
    final isReinstating = existing?.isVoided == true;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updated = await widget.onSubmit(
        schoolYear: schoolYear,
        startDate: startText.isEmpty ? null : startText,
        endDate: endText.isEmpty ? null : endText,
        copyFrom: _copyPopulation ? widget.copySourceYear : null,
        copyPopulation: _copyPopulation && widget.copySourceYear != null,
        reinstateReason:
            isReinstating && reinstateReason.isNotEmpty
            ? reinstateReason
            : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        _CreateAcademicYearResult(
          schoolYear: schoolYear,
          years: updated,
          reinstated: isReinstating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _AcademicYearManagementPageState._friendlyError(
          error,
          fallback: 'Could not create academic year.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReinstating = _matchingExistingYear?.isVoided == true;
    final liveHint = _liveValidationHint;
    final currentStart = manilaCurrentSchoolStartYear(widget.now);
    return AlertDialog(
      title: Text(
        isReinstating ? 'Reinstate academic year' : 'Create academic year',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Define a consecutive academic year up to ${currentStart + 1}-${currentStart + 2}. Leave dates blank for June 1 – May 31 (Asia/Manila). Future years are created as Planned until activated.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminColors.muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _schoolYearController,
                enabled: !_saving,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'School year',
                  hintText: '${currentStart + 1}-${currentStart + 2}',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _startDateController,
                enabled: !_saving,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Start date (YYYY-MM-DD)',
                  hintText: '${currentStart + 1}-06-01',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _endDateController,
                enabled: !_saving,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'End date (YYYY-MM-DD)',
                  hintText: '${currentStart + 2}-05-31',
                ),
              ),
              if (isReinstating) ...[
                const SizedBox(height: 12),
                _InlineMessageBanner(
                  message:
                      'This school year was previously voided. Reinstating creates a Planned record while preserving past void audit history.',
                  isError: false,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _reinstateReasonController,
                  enabled: !_saving,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Reinstatement note (optional)',
                    hintText: 'Why this period is being re-planned',
                  ),
                ),
              ],
              if (widget.copySourceYear != null) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _copyPopulation,
                  enabled: !_saving,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'Copy college population targets from ${widget.copySourceYear}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  onChanged: (value) =>
                      setState(() => _copyPopulation = value ?? false),
                ),
              ],
              if (_error != null || liveHint != null) ...[
                const SizedBox(height: 12),
                _InlineMessageBanner(
                  message: _error ?? liveHint!,
                  isError: true,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(
            _saving
                ? 'Creating...'
                : isReinstating
                ? 'Reinstate'
                : 'Create',
          ),
        ),
      ],
    );
  }
}

class _CloseAcademicYearDialog extends StatefulWidget {
  const _CloseAcademicYearDialog({
    required this.schoolYear,
    required this.onConfirm,
  });

  final String schoolYear;
  final Future<List<AcademicYearRecord>> Function() onConfirm;

  @override
  State<_CloseAcademicYearDialog> createState() =>
      _CloseAcademicYearDialogState();
}

class _CloseAcademicYearDialogState extends State<_CloseAcademicYearDialog> {
  final _confirmController = TextEditingController();
  bool _closing = false;
  String? _error;

  String get _expectedPhrase => 'CLOSE ${widget.schoolYear}';

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_confirmController.text.trim() != _expectedPhrase) return;
    setState(() {
      _closing = true;
      _error = null;
    });
    try {
      final updated = await widget.onConfirm();
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _closing = false;
        _error = _AcademicYearManagementPageState._friendlyError(
          error,
          fallback: 'Could not close academic year.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final matchesPhrase = _confirmController.text.trim() == _expectedPhrase;
    return AlertDialog(
      title: Text('Close academic year ${widget.schoolYear}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Closing ${widget.schoolYear} marks the period read-only while preserving historical counseling reports and population snapshots. Type "$_expectedPhrase" to confirm.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminColors.muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _confirmController,
                enabled: !_closing,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Confirmation',
                  hintText: _expectedPhrase,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _InlineMessageBanner(message: _error!, isError: true),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _closing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _closing || !matchesPhrase ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: AdminColors.danger),
          child: Text(_closing ? 'Locking...' : 'Lock year'),
        ),
      ],
    );
  }
}

class _ActivateAcademicYearDialog extends StatefulWidget {
  const _ActivateAcademicYearDialog({
    required this.schoolYear,
    required this.onConfirm,
  });

  final String schoolYear;
  final Future<List<AcademicYearRecord>> Function() onConfirm;

  @override
  State<_ActivateAcademicYearDialog> createState() =>
      _ActivateAcademicYearDialogState();
}

class _ActivateAcademicYearDialogState
    extends State<_ActivateAcademicYearDialog> {
  final _confirmController = TextEditingController();
  bool _activating = false;
  String? _error;

  String get _expectedPhrase => 'ACTIVATE ${widget.schoolYear}';

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_confirmController.text.trim() != _expectedPhrase) return;
    setState(() {
      _activating = true;
      _error = null;
    });
    try {
      final updated = await widget.onConfirm();
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _activating = false;
        _error = _AcademicYearManagementPageState._friendlyError(
          error,
          fallback: 'Could not activate academic year.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final matchesPhrase = _confirmController.text.trim() == _expectedPhrase;
    return AlertDialog(
      title: Text('Activate academic year ${widget.schoolYear}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Activating ${widget.schoolYear} switches it from Planned to the sole Current academic year for reporting and population denominators. Type "$_expectedPhrase" to confirm.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminColors.muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _confirmController,
                enabled: !_activating,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Confirmation',
                  hintText: _expectedPhrase,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _InlineMessageBanner(message: _error!, isError: true),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _activating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _activating || !matchesPhrase ? null : _submit,
          child: Text(_activating ? 'Activating...' : 'Activate year'),
        ),
      ],
    );
  }
}

class _VoidAcademicYearDialog extends StatefulWidget {
  const _VoidAcademicYearDialog({
    required this.schoolYear,
    required this.onConfirm,
  });

  final String schoolYear;
  final Future<List<AcademicYearRecord>> Function({
    required String reason,
    required String confirmation,
  })
  onConfirm;

  @override
  State<_VoidAcademicYearDialog> createState() =>
      _VoidAcademicYearDialogState();
}

class _VoidAcademicYearDialogState extends State<_VoidAcademicYearDialog> {
  final _reasonController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _voiding = false;
  String? _error;

  String get _expectedPhrase => 'VOID ${widget.schoolYear}';

  @override
  void dispose() {
    _reasonController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    final confirmation = _confirmController.text.trim();
    if (reason.length < 10 || confirmation != _expectedPhrase) return;
    setState(() {
      _voiding = true;
      _error = null;
    });
    try {
      final updated = await widget.onConfirm(
        reason: reason,
        confirmation: confirmation,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _voiding = false;
        _error = _AcademicYearManagementPageState._friendlyError(
          error,
          fallback: 'Could not void academic year.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reasonLength = _reasonController.text.trim().length;
    final canSubmit =
        !_voiding &&
        reasonLength >= 10 &&
        reasonLength <= 500 &&
        _confirmController.text.trim() == _expectedPhrase;
    return AlertDialog(
      title: Text('Void academic year ${widget.schoolYear}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Voiding ${widget.schoolYear} hides this unreferenced period from operational reporting while preserving immutable audit snapshots. It does NOT physically delete records. Enter a reason (10–500 characters) and type "$_expectedPhrase" to confirm.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminColors.muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _reasonController,
                enabled: !_voiding,
                maxLines: 3,
                maxLength: 500,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Void reason (required)',
                  hintText: 'Explain why this academic year is being voided',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirmController,
                enabled: !_voiding,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Confirmation',
                  hintText: _expectedPhrase,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _InlineMessageBanner(message: _error!, isError: true),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _voiding ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
          style: FilledButton.styleFrom(backgroundColor: AdminColors.danger),
          child: Text(_voiding ? 'Voiding...' : 'Void year'),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.count,
    required this.accent,
  });

  final String label;
  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 28,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AdminColors.muted,
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AdminColors.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AcademicYearRowCard extends StatelessWidget {
  const _AcademicYearRowCard({
    required this.year,
    required this.periodState,
    required this.compact,
    required this.busy,
    required this.isSuperAdmin,
    required this.hasActiveCurrentYear,
    required this.todayManila,
    required this.onActivate,
    required this.onClose,
    required this.onVoid,
  });

  final AcademicYearRecord year;
  final AcademicYearPeriodState periodState;
  final bool compact;
  final bool busy;
  final bool isSuperAdmin;
  final bool hasActiveCurrentYear;
  final String todayManila;
  final VoidCallback onActivate;
  final VoidCallback onClose;
  final VoidCallback onVoid;

  String? _activationDisabledReason() {
    if (hasActiveCurrentYear) {
      return 'Close the active current academic year before activating ${year.schoolYear}.';
    }
    if (year.startDate.isNotEmpty && todayManila.compareTo(year.startDate) < 0) {
      return 'Activation opens on ${year.startDate} (Asia/Manila: $todayManila).';
    }
    return null;
  }

  Widget _buildStatusPill(IconData icon, String label, {bool danger = false}) {
    final fg = danger ? AdminColors.danger : AdminColors.muted;
    final bg = danger ? const Color(0xFFFEF2F2) : AdminColors.surfaceMuted;
    final border = danger ? const Color(0xFFFECACA) : AdminColors.border;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final voidButton = isSuperAdmin
        ? OutlinedButton.icon(
            onPressed: busy ? null : onVoid,
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminColors.danger,
              side: const BorderSide(color: Color(0xFFFCA5A5)),
            ),
            icon: const Icon(Icons.block_outlined, size: 16),
            label: const Text('Void year'),
          )
        : null;

    if (periodState == AcademicYearPeriodState.closed) {
      return _buildStatusPill(Icons.lock_outline, 'Locked · read-only');
    }
    if (periodState == AcademicYearPeriodState.voided) {
      return _buildStatusPill(
        Icons.history_toggle_off,
        'Voided · audit preserved',
        danger: true,
      );
    }
    if (periodState == AcademicYearPeriodState.unknown) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildStatusPill(
            Icons.warning_amber_rounded,
            'Unknown status · blocked',
            danger: true,
          ),
          ?voidButton,
        ],
      );
    }
    if (periodState == AcademicYearPeriodState.planned) {
      final disabledReason = _activationDisabledReason();
      return Column(
        crossAxisAlignment:
            compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: busy || disabledReason != null ? null : onActivate,
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text('Activate year'),
              ),
              ?voidButton,
            ],
          ),
          if (disabledReason != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                disabledReason,
                textAlign: compact ? TextAlign.left : TextAlign.right,
                style: const TextStyle(fontSize: 12, color: AdminColors.muted),
              ),
            ),
          ],
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: busy ? null : onClose,
          icon: const Icon(Icons.lock_outline, size: 16),
          label: const Text('Close year'),
        ),
        ?voidButton,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final (badgeText, badgeBg, badgeFg) = switch (periodState) {
      AcademicYearPeriodState.current => (
        'Current',
        const Color(0xFFEAF3EE),
        AdminColors.success,
      ),
      AcademicYearPeriodState.planned => (
        'Planned',
        const Color(0xFFE0F2FE),
        const Color(0xFF075985),
      ),
      AcademicYearPeriodState.upcoming => (
        'Upcoming',
        AdminColors.accentSoft,
        AdminColors.ink,
      ),
      AcademicYearPeriodState.closed => (
        'Closed',
        AdminColors.surfaceMuted,
        AdminColors.muted,
      ),
      AcademicYearPeriodState.voided => (
        'Voided',
        const Color(0xFFFEE2E2),
        AdminColors.danger,
      ),
      AcademicYearPeriodState.unknown => (
        'Unknown',
        const Color(0xFFFEE2E2),
        AdminColors.danger,
      ),
    };

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              year.schoolYear,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AdminColors.ink,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: badgeFg,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Period: ${year.startDate} to ${year.endDate}',
          style: const TextStyle(fontSize: 13, color: AdminColors.muted),
        ),
        if (periodState == AcademicYearPeriodState.upcoming) ...[
          const SizedBox(height: 4),
          const Text(
            'Future-dated active record: does not reflect today in Asia/Manila.',
            style: TextStyle(fontSize: 12, color: AdminColors.muted),
          ),
        ],
        if (periodState == AcademicYearPeriodState.voided &&
            year.voidReason.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Void reason: ${year.voidReason}',
            style: const TextStyle(fontSize: 12, color: AdminColors.danger),
          ),
        ],
      ],
    );

    final action = _buildActions();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [details, const SizedBox(height: 12), action],
            )
          : Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: 16),
                action,
              ],
            ),
    );
  }
}

class _InlineMessageBanner extends StatelessWidget {
  const _InlineMessageBanner({
    required this.message,
    required this.isError,
    this.onDismiss,
  });

  final String message;
  final bool isError;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final bg = isError ? const Color(0xFFFBEAEA) : const Color(0xFFEAF3EE);
    final fg = isError ? AdminColors.danger : AdminColors.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close, size: 16, color: fg),
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
