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

  DateTime _now() => (widget.nowProvider ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    if (_isAdmin) {
      _loadYears();
    }
  }

  Future<void> _loadYears() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final years = await widget.repository.fetchAcademicYears();
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
    AcademicYearPeriodState.upcoming => 1,
    AcademicYearPeriodState.closed => 2,
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
    if (startText.isEmpty && endText.isEmpty) {
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
      (item) => item != null && !item.isClosed,
      orElse: () => _years.isNotEmpty ? _years.first : null,
    );

    final result = await showDialog<_CreateAcademicYearResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateAcademicYearDialog(
        copySourceYear: openSource?.schoolYear,
        onSubmit:
            ({
              required String schoolYear,
              String? startDate,
              String? endDate,
              String? copyFrom,
              required bool copyPopulation,
            }) async {
              setState(() => _submitting = true);
              try {
                final updated = await widget.repository.createAcademicYear(
                  schoolYear: schoolYear,
                  startDate: startDate,
                  endDate: endDate,
                  copyFrom: copyFrom,
                  copyPopulation: copyPopulation,
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
      _statusMessage = 'Academic year ${result.schoolYear} created.';
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
            return await widget.repository.closeAcademicYear(year.schoolYear);
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
                    ..._years.map(
                      (year) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AcademicYearRowCard(
                          year: year,
                          periodState: year.periodState(now: _now()),
                          compact: compact,
                          busy: _submitting,
                          onClose: () => _openCloseDialog(year),
                        ),
                      ),
                    ),
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
    final upcomingCount = _years
        .where(
          (y) => y.periodState(now: now) == AcademicYearPeriodState.upcoming,
        )
        .length;
    final closedCount = _years
        .where((y) => y.periodState(now: now) == AcademicYearPeriodState.closed)
        .length;

    final cards = [
      _SummaryTile(
        label: 'Current',
        count: currentCount,
        accent: AdminColors.success,
      ),
      _SummaryTile(
        label: 'Upcoming',
        count: upcomingCount,
        accent: AdminColors.accentStrong,
      ),
      _SummaryTile(
        label: 'Closed',
        count: closedCount,
        accent: AdminColors.muted,
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
        Expanded(child: cards[0]),
        const SizedBox(width: 12),
        Expanded(child: cards[1]),
        const SizedBox(width: 12),
        Expanded(child: cards[2]),
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
  });

  final String schoolYear;
  final List<AcademicYearRecord> years;
}

class _CreateAcademicYearDialog extends StatefulWidget {
  const _CreateAcademicYearDialog({
    required this.copySourceYear,
    required this.onSubmit,
  });

  final String? copySourceYear;
  final Future<List<AcademicYearRecord>> Function({
    required String schoolYear,
    String? startDate,
    String? endDate,
    String? copyFrom,
    required bool copyPopulation,
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
  bool _copyPopulation = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _schoolYearController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final schoolYear = _schoolYearController.text.trim();
    final startText = _startDateController.text.trim();
    final endText = _endDateController.text.trim();

    final validationError =
        _AcademicYearManagementPageState.validateCreateInputs(
          schoolYear: schoolYear,
          startText: startText,
          endText: endText,
        );
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

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
      );
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(_CreateAcademicYearResult(schoolYear: schoolYear, years: updated));
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
    return AlertDialog(
      title: const Text('Create academic year'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Define a consecutive academic year (YYYY-YYYY). Leave dates blank to use the standard June 1 – May 31 period.',
                style: TextStyle(
                  fontSize: 13,
                  color: AdminColors.muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _schoolYearController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'School year',
                  hintText: '2027-2028',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _startDateController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Start date (YYYY-MM-DD)',
                  hintText: '2027-06-01',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _endDateController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'End date (YYYY-MM-DD)',
                  hintText: '2028-05-31',
                ),
              ),
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Creating...' : 'Create'),
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
    required this.onClose,
  });

  final AcademicYearRecord year;
  final AcademicYearPeriodState periodState;
  final bool compact;
  final bool busy;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final (badgeText, badgeBg, badgeFg) = switch (periodState) {
      AcademicYearPeriodState.current => (
        'Current',
        const Color(0xFFEAF3EE),
        AdminColors.success,
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
      ],
    );

    final action = year.isClosed
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AdminColors.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AdminColors.border),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 15, color: AdminColors.muted),
                SizedBox(width: 6),
                Text(
                  'Locked · read-only',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AdminColors.muted,
                  ),
                ),
              ],
            ),
          )
        : OutlinedButton.icon(
            onPressed: busy ? null : onClose,
            icon: const Icon(Icons.lock_outline, size: 16),
            label: const Text('Close year'),
          );

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
