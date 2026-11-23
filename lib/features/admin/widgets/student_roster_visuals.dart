import 'package:flutter/material.dart';

import '../../../repositories/student_roster_repository.dart';
import '../services/student_roster_file_parser.dart';
import '../theme/admin_theme.dart';

/// Animation duration honoring system/MediaQuery reduced-motion settings.
Duration rosterAnimDuration(
  BuildContext context, [
  Duration normal = const Duration(milliseconds: 220),
]) => MediaQuery.maybeDisableAnimationsOf(context) == true
    ? Duration.zero
    : normal;

enum RosterBadgeTone { green, amber, blue, red, neutral }

/// Compact semantic pill used for roster statuses, preview counts, and row
/// validation indicators.
class RosterSemanticPill extends StatelessWidget {
  const RosterSemanticPill({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.compact = false,
  });

  final String label;
  final RosterBadgeTone tone;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (tone) {
      RosterBadgeTone.green => (
        AdminColors.greenBg,
        AdminColors.greenFg,
        AdminColors.greenBorder,
      ),
      RosterBadgeTone.amber => (
        AdminColors.amberBg,
        AdminColors.amberFg,
        AdminColors.amberBorder,
      ),
      RosterBadgeTone.blue => (
        AdminColors.blueBg,
        AdminColors.blueFg,
        AdminColors.blueBorder,
      ),
      RosterBadgeTone.red => (
        AdminColors.redBg,
        AdminColors.redFg,
        AdminColors.redBorder,
      ),
      RosterBadgeTone.neutral => (
        AdminColors.neutralBg,
        AdminColors.neutralFg,
        AdminColors.neutralBorder,
      ),
    };

    return AnimatedContainer(
      duration: rosterAnimDuration(context, const Duration(milliseconds: 180)),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 13 : 14, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: compact ? 11.5 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive KPI summary strip for the currently loaded roster page.
class RosterSummaryMetricsStrip extends StatelessWidget {
  const RosterSummaryMetricsStrip({
    super.key,
    required this.totalLoaded,
    required this.activatedCount,
    required this.notActivatedCount,
    required this.selectedCount,
    required this.activeStatusFilter,
    required this.onToggleStatusFilter,
  });

  final int totalLoaded;
  final int activatedCount;
  final int notActivatedCount;
  final int selectedCount;
  final String activeStatusFilter;
  final ValueChanged<String> onToggleStatusFilter;

  @override
  Widget build(BuildContext context) {
    final anim = rosterAnimDuration(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _MetricTile(
          label: 'Loaded records',
          value: totalLoaded,
          icon: Icons.groups_outlined,
          tone: RosterBadgeTone.neutral,
          selected: activeStatusFilter.isEmpty,
          duration: anim,
          onTap: () => onToggleStatusFilter(''),
        ),
        _MetricTile(
          label: 'Active accounts',
          value: activatedCount,
          icon: Icons.verified_user_outlined,
          tone: RosterBadgeTone.green,
          selected: activeStatusFilter == 'activated',
          duration: anim,
          onTap: () => onToggleStatusFilter(
            activeStatusFilter == 'activated' ? '' : 'activated',
          ),
        ),
        _MetricTile(
          label: 'Awaiting activation',
          value: notActivatedCount,
          icon: Icons.schedule_outlined,
          tone: RosterBadgeTone.amber,
          selected: activeStatusFilter == 'notActivated',
          duration: anim,
          onTap: () => onToggleStatusFilter(
            activeStatusFilter == 'notActivated' ? '' : 'notActivated',
          ),
        ),
        if (selectedCount > 0)
          _MetricTile(
            label: 'Selected for codes',
            value: selectedCount,
            icon: Icons.vpn_key_outlined,
            tone: RosterBadgeTone.blue,
            selected: true,
            duration: anim,
            onTap: null,
          ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final RosterBadgeTone tone;
  final bool selected;
  final Duration duration;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = switch (tone) {
      RosterBadgeTone.green => AdminColors.greenFg,
      RosterBadgeTone.amber => AdminColors.amberFg,
      RosterBadgeTone.blue => AdminColors.blueFg,
      RosterBadgeTone.red => AdminColors.redFg,
      RosterBadgeTone.neutral => AdminColors.ink,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: duration,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AdminColors.accentFaint : AdminColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AdminColors.accentStrong : AdminColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 8),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: value.toDouble()),
                duration: duration,
                builder: (_, v, _) => Text(
                  v.round().toString(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AdminColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Interactive step indicator showing where the admin is in the import flow.
class ImportPipelineSteps extends StatelessWidget {
  const ImportPipelineSteps({
    super.key,
    required this.hasPreparedRows,
    required this.hasPreview,
    required this.hasImported,
    required this.isBusy,
  });

  final bool hasPreparedRows;
  final bool hasPreview;
  final bool hasImported;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final currentStep = hasImported
        ? 3
        : hasPreview
        ? 2
        : hasPreparedRows
        ? 1
        : 0;
    final progress = switch (currentStep) {
      0 => 0.16,
      1 => 0.48,
      2 => 0.82,
      _ => 1.0,
    };
    final duration = rosterAnimDuration(
      context,
      const Duration(milliseconds: 280),
    );

    const steps = [
      (title: '1. Prepare roster', icon: Icons.table_rows_outlined),
      (title: '2. Preview & verify', icon: Icons.fact_check_outlined),
      (title: '3. Import & issue codes', icon: Icons.vpn_key_outlined),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (var i = 0; i < steps.length; i++)
                _StepPill(
                  title: steps[i].title,
                  icon: steps[i].icon,
                  done:
                      (i == 0 && (hasPreview || hasImported)) ||
                      (i == 1 && hasImported) ||
                      (i == 2 && hasImported),
                  active:
                      (i == 0 && !hasPreview && !hasImported) ||
                      (i == 1 && hasPreview && !hasImported) ||
                      (i == 2 && hasImported),
                  duration: duration,
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 6,
              width: double.infinity,
              color: AdminColors.surfaceMuted,
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: progress),
                duration: duration,
                curve: Curves.easeOutCubic,
                builder: (_, factor, _) => FractionallySizedBox(
                  widthFactor: factor.clamp(0.0, 1.0),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: isBusy
                          ? AdminColors.blueFg
                          : hasImported
                          ? AdminColors.success
                          : AdminColors.accentStrong,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({
    required this.title,
    required this.icon,
    required this.done,
    required this.active,
    required this.duration,
  });

  final String title;
  final IconData icon;
  final bool done;
  final bool active;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final bg = done
        ? AdminColors.greenBg
        : active
        ? AdminColors.accentSoft
        : AdminColors.surfaceMuted;
    final fg = done
        ? AdminColors.greenFg
        : active
        ? AdminColors.ink
        : AdminColors.muted;
    final border = done
        ? AdminColors.greenBorder
        : active
        ? AdminColors.accentStrong
        : AdminColors.border;

    return AnimatedContainer(
      duration: duration,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border.withValues(alpha: 0.75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_circle_rounded : icon, size: 15, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12.5,
                fontWeight: active || done ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum RosterImportMode { file, manual }

/// Animated mode switcher between File Upload and Bulk Manual Input.
class ImportSourceModeToggle extends StatelessWidget {
  const ImportSourceModeToggle({
    super.key,
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final RosterImportMode mode;
  final bool enabled;
  final ValueChanged<RosterImportMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final duration = rosterAnimDuration(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AdminColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _ModeOption(
            label: 'Upload file',
            subtitle: '.xlsx or .csv',
            icon: Icons.upload_file_outlined,
            selected: mode == RosterImportMode.file,
            enabled: enabled,
            duration: duration,
            onTap: () => onChanged(RosterImportMode.file),
          ),
          _ModeOption(
            label: 'Bulk manual input',
            subtitle: 'Grid or spreadsheet paste',
            icon: Icons.edit_note_rounded,
            selected: mode == RosterImportMode.manual,
            enabled: enabled,
            duration: duration,
            onTap: () => onChanged(RosterImportMode.manual),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: duration,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AdminColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? AdminColors.accentStrong : Colors.transparent,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AdminColors.ink.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AdminColors.ink : AdminColors.muted,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? AdminColors.ink : AdminColors.muted,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AdminColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Interactive row controllers for a single student entry matching
/// [rosterTemplateHeaders].
class ManualRosterRowControllers {
  ManualRosterRowControllers({Map<String, String>? initial})
    : studentNo = TextEditingController(text: initial?['studentNo'] ?? ''),
      surname = TextEditingController(text: initial?['surname'] ?? ''),
      firstName = TextEditingController(text: initial?['firstName'] ?? ''),
      middleName = TextEditingController(text: initial?['middleName'] ?? ''),
      dateOfBirth = TextEditingController(
        text: initial != null
            ? displayRosterDateMmDdYyyy(initial['dateOfBirth'] ?? '')
            : '',
      ),
      college = TextEditingController(text: initial?['college'] ?? ''),
      course = TextEditingController(text: initial?['course'] ?? ''),
      yearLevel = TextEditingController(text: initial?['yearLevel'] ?? '');

  final TextEditingController studentNo;
  final TextEditingController surname;
  final TextEditingController firstName;
  final TextEditingController middleName;
  final TextEditingController dateOfBirth;
  final TextEditingController college;
  final TextEditingController course;
  final TextEditingController yearLevel;

  Map<String, String> toDraftMap() => {
    'studentNo': studentNo.text,
    'surname': surname.text,
    'firstName': firstName.text,
    'middleName': middleName.text,
    'dateOfBirth': dateOfBirth.text,
    'college': college.text,
    'course': course.text,
    'yearLevel': yearLevel.text,
  };

  void dispose() {
    studentNo.dispose();
    surname.dispose();
    firstName.dispose();
    middleName.dispose();
    dateOfBirth.dispose();
    college.dispose();
    course.dispose();
    yearLevel.dispose();
  }
}

/// Interactive bulk manual entry panel using the exact Student Roster
/// template columns (`Student No.`, `Surname`, `First Name`, `Middle Name`,
/// `Date of Birth (MM/DD/YYYY)`, `College`, `Course`, `Year Level`).
class ManualBulkImportPanel extends StatefulWidget {
  const ManualBulkImportPanel({
    super.key,
    required this.rows,
    required this.validation,
    required this.academicOptions,
    required this.yearLevels,
    required this.busy,
    required this.onRowsChanged,
    required this.onAddRow,
    required this.onAddFiveRows,
    required this.onDuplicateRow,
    required this.onRemoveRow,
    required this.onClearAll,
    required this.onApplyBulkPaste,
    required this.onDownloadTemplate,
    required this.onPreview,
  });

  final List<ManualRosterRowControllers> rows;
  final ManualRosterValidation validation;
  final AcademicOptions? academicOptions;
  final List<String> yearLevels;
  final bool busy;
  final VoidCallback onRowsChanged;
  final VoidCallback onAddRow;
  final VoidCallback onAddFiveRows;
  final ValueChanged<int> onDuplicateRow;
  final ValueChanged<int> onRemoveRow;
  final VoidCallback onClearAll;
  final ({bool ok, String? error, int addedCount}) Function(
    String rawText, {
    required bool replaceExisting,
  })
  onApplyBulkPaste;
  final VoidCallback onDownloadTemplate;
  final VoidCallback onPreview;

  @override
  State<ManualBulkImportPanel> createState() => _ManualBulkImportPanelState();
}

class _ManualBulkImportPanelState extends State<ManualBulkImportPanel> {
  final _pasteController = TextEditingController();
  bool _pasteOpen = false;
  bool _replaceOnPaste = false;
  String? _pasteError;
  String? _pasteSuccess;

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  void _applyPaste() {
    final res = widget.onApplyBulkPaste(
      _pasteController.text,
      replaceExisting: _replaceOnPaste,
    );
    setState(() {
      if (res.ok) {
        _pasteError = null;
        _pasteSuccess = 'Loaded ${res.addedCount} row(s) into the manual grid.';
        _pasteController.clear();
        _pasteOpen = false;
      } else {
        _pasteSuccess = null;
        _pasteError = res.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.validation;
    final ratio = v.nonEmptyCount == 0 ? 0.0 : v.readyCount / v.nonEmptyCount;
    final duration = rosterAnimDuration(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bulk manual input (Template format)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Enter multiple student rows directly or paste rows '
                          'copied from Excel / Google Sheets or CSV.',
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('toggle_bulk_paste_button'),
                          onPressed: widget.busy
                              ? null
                              : () => setState(() {
                                  _pasteOpen = !_pasteOpen;
                                  _pasteError = null;
                                  _pasteSuccess = null;
                                }),
                          icon: Icon(
                            _pasteOpen
                                ? Icons.expand_less
                                : Icons.content_paste_go_outlined,
                          ),
                          label: Text(
                            _pasteOpen
                                ? 'Hide paste box'
                                : 'Paste rows (Excel / CSV)',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: widget.onDownloadTemplate,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Download template'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Exact template header strip for instant visual reference.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AdminColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AdminColors.border),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Template columns:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AdminColors.ink,
                        ),
                      ),
                      for (var i = 0; i < rosterTemplateHeaders.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AdminColors.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AdminColors.border),
                          ),
                          child: Text(
                            i == 3
                                ? '${rosterTemplateHeaders[i]} (opt.)'
                                : '${rosterTemplateHeaders[i]} *',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AdminColors.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Live validation readiness meter + status counters.
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          RosterSemanticPill(
                            label: 'Ready ${v.readyCount}/${v.nonEmptyCount}',
                            tone: v.nonEmptyCount == 0
                                ? RosterBadgeTone.neutral
                                : v.hasBlockingIssues
                                ? RosterBadgeTone.amber
                                : RosterBadgeTone.green,
                            icon: v.hasBlockingIssues
                                ? Icons.pending_actions_outlined
                                : Icons.check_circle_outline,
                          ),
                          if (v.incompleteCount > 0)
                            RosterSemanticPill(
                              label: 'Missing fields ${v.incompleteCount}',
                              tone: RosterBadgeTone.amber,
                              icon: Icons.warning_amber_rounded,
                            ),
                          if (v.invalidDateCount > 0)
                            RosterSemanticPill(
                              label: 'Invalid DOB ${v.invalidDateCount}',
                              tone: RosterBadgeTone.red,
                              icon: Icons.event_busy_outlined,
                            ),
                          if (v.duplicateCount > 0)
                            RosterSemanticPill(
                              label:
                                  'Duplicate Student No. ${v.duplicateCount}',
                              tone: RosterBadgeTone.red,
                              icon: Icons.content_copy_outlined,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 6,
                    width: double.infinity,
                    color: AdminColors.surfaceMuted,
                    alignment: Alignment.centerLeft,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: ratio),
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      builder: (_, factor, _) => FractionallySizedBox(
                        widthFactor: factor.clamp(0.0, 1.0),
                        child: Container(
                          height: 6,
                          color: v.hasBlockingIssues
                              ? AdminColors.amberBorder
                              : AdminColors.success,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_pasteSuccess != null) ...[
                  const SizedBox(height: 10),
                  RosterSemanticPill(
                    label: _pasteSuccess!,
                    tone: RosterBadgeTone.green,
                    icon: Icons.check_circle_outline,
                  ),
                ],
                AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _pasteOpen
                      ? _buildPasteDrawer()
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < widget.rows.length; i++)
          _ManualRowCard(
            key: ObjectKey(widget.rows[i]),
            index: i,
            controllers: widget.rows[i],
            errors: v.rowErrors[i] ?? const [],
            isBlank: !v.nonEmptyIndices.contains(i),
            academicOptions: widget.academicOptions,
            yearLevels: widget.yearLevels,
            canRemove: widget.rows.length > 1 && !widget.busy,
            busy: widget.busy,
            onChanged: widget.onRowsChanged,
            onDuplicate: () => widget.onDuplicateRow(i),
            onRemove: () => widget.onRemoveRow(i),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.busy ? null : widget.onAddRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Add row'),
                ),
                TextButton.icon(
                  onPressed: widget.busy ? null : widget.onAddFiveRows,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Add 5 rows'),
                ),
                TextButton(
                  onPressed: widget.busy ? null : widget.onClearAll,
                  child: const Text('Clear all'),
                ),
              ],
            ),
            FilledButton.icon(
              key: const Key('manual_preview_button'),
              onPressed: v.hasBlockingIssues || widget.busy
                  ? null
                  : widget.onPreview,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPasteDrawer() {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminColors.accentFaint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AdminColors.accentStrong.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste tab-separated (Excel / Google Sheets) or CSV lines',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Order: Student No., Surname, First Name, Middle Name, Date of Birth (MM/DD/YYYY), College, Course, Year Level (header row optional).',
            style: TextStyle(fontSize: 12.5, color: AdminColors.muted),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('bulk_paste_textfield'),
            controller: _pasteController,
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(
              hintText:
                  '2021-001\tSantos\tAna\tM\t02/15/2005\tCITE\tBSIT\t1st Year\n'
                  '2021-002,Reyes,Carlo,,07/21/2004,CBA,BSBA,2nd Year',
            ),
          ),
          if (_pasteError != null) ...[
            const SizedBox(height: 8),
            Text(
              _pasteError!,
              style: const TextStyle(
                color: AdminColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                key: const Key('apply_bulk_paste_button'),
                onPressed: _applyPaste,
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('Apply pasted rows'),
              ),
              FilterChip(
                label: const Text('Replace existing rows'),
                selected: _replaceOnPaste,
                onSelected: (v) => setState(() => _replaceOnPaste = v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ManualRowCard extends StatelessWidget {
  const _ManualRowCard({
    super.key,
    required this.index,
    required this.controllers,
    required this.errors,
    required this.isBlank,
    required this.academicOptions,
    required this.yearLevels,
    required this.canRemove,
    required this.busy,
    required this.onChanged,
    required this.onDuplicate,
    required this.onRemove,
  });

  final int index;
  final ManualRosterRowControllers controllers;
  final List<String> errors;
  final bool isBlank;
  final AcademicOptions? academicOptions;
  final List<String> yearLevels;
  final bool canRemove;
  final bool busy;
  final VoidCallback onChanged;
  final VoidCallback onDuplicate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasErrors = errors.isNotEmpty;
    final tone = isBlank
        ? RosterBadgeTone.neutral
        : hasErrors
        ? RosterBadgeTone.red
        : RosterBadgeTone.green;
    final statusLabel = isBlank
        ? 'Blank'
        : hasErrors
        ? 'Needs fix'
        : 'Ready';
    final statusIcon = isBlank
        ? Icons.edit_outlined
        : hasErrors
        ? Icons.error_outline
        : Icons.check_circle_outline;
    final borderColor = hasErrors
        ? AdminColors.redBorder
        : isBlank
        ? AdminColors.border
        : AdminColors.greenBorder.withValues(alpha: 0.75);

    final colleges = academicOptions?.colleges ?? const <AcademicOption>[];
    final enteredCollege = controllers.college.text.trim().toLowerCase();
    final matchedCollege = colleges.where(
      (c) => c.name.toLowerCase() == enteredCollege,
    );
    final selectedCollegeId = matchedCollege.isNotEmpty
        ? matchedCollege.first.id
        : null;
    final allCourses = academicOptions?.courses ?? const <AcademicOption>[];
    final filteredCourses = selectedCollegeId == null
        ? allCourses
        : allCourses.where((c) => c.collegeId == selectedCollegeId).toList();

    return AnimatedContainer(
      key: Key('manual_row_$index'),
      duration: rosterAnimDuration(context, const Duration(milliseconds: 180)),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: hasErrors ? 1.3 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AdminColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Row ${index + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AdminColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                RosterSemanticPill(
                  label: statusLabel,
                  tone: tone,
                  icon: statusIcon,
                  compact: true,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Duplicate row ${index + 1}',
                  onPressed: busy ? null : onDuplicate,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Remove row ${index + 1}',
                  onPressed: canRemove ? onRemove : null,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (_, constraints) {
                final w = constraints.maxWidth;
                final cols = w >= 880
                    ? 4
                    : w >= 540
                    ? 2
                    : 1;
                final fieldWidth = cols == 1 ? w : (w - (cols - 1) * 10) / cols;

                Widget cell(Widget child) =>
                    SizedBox(width: fieldWidth, child: child);

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    cell(
                      _field(
                        controller: controllers.studentNo,
                        label: '${rosterTemplateHeaders[0]} *',
                        hint: '2021-001',
                      ),
                    ),
                    cell(
                      _field(
                        controller: controllers.surname,
                        label: '${rosterTemplateHeaders[1]} *',
                        hint: 'Santos',
                      ),
                    ),
                    cell(
                      _field(
                        controller: controllers.firstName,
                        label: '${rosterTemplateHeaders[2]} *',
                        hint: 'Ana',
                      ),
                    ),
                    cell(
                      _field(
                        controller: controllers.middleName,
                        label: rosterTemplateHeaders[3],
                        hint: 'Optional',
                      ),
                    ),
                    cell(
                      _field(
                        controller: controllers.dateOfBirth,
                        label: '${rosterTemplateHeaders[4]} *',
                        hint: '02/15/2005',
                      ),
                    ),
                    cell(
                      _pickerField(
                        controller: controllers.college,
                        label: '${rosterTemplateHeaders[5]} *',
                        hint: 'CITE',
                        options: [for (final c in colleges) c.name],
                      ),
                    ),
                    cell(
                      _pickerField(
                        controller: controllers.course,
                        label: '${rosterTemplateHeaders[6]} *',
                        hint: 'BSIT',
                        options: [for (final c in filteredCourses) c.name],
                      ),
                    ),
                    cell(
                      _pickerField(
                        controller: controllers.yearLevel,
                        label: '${rosterTemplateHeaders[7]} *',
                        hint: '1st Year',
                        options: yearLevels,
                      ),
                    ),
                  ],
                );
              },
            ),
            if (hasErrors) ...[
              const SizedBox(height: 8),
              for (final err in errors)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 14,
                        color: AdminColors.danger,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          err,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AdminColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) => TextField(
    controller: controller,
    enabled: !busy,
    onChanged: (_) => onChanged(),
    decoration: InputDecoration(labelText: label, hintText: hint),
  );

  Widget _pickerField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required List<String> options,
  }) {
    final deduped = <String>{
      for (final o in options)
        if (o.trim().isNotEmpty) o.trim(),
    }.toList();
    return TextField(
      controller: controller,
      enabled: !busy,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: deduped.isEmpty
            ? null
            : PopupMenuButton<String>(
                tooltip: 'Choose $label',
                enabled: !busy,
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (value) {
                  controller.text = value;
                  onChanged();
                },
                itemBuilder: (_) => [
                  for (final option in deduped)
                    PopupMenuItem(value: option, child: Text(option)),
                ],
              ),
      ),
    );
  }
}
