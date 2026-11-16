import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../models/case_remarks_model.dart';
import '../theme/admin_theme.dart';

/// Loads the current remarks for one case.
typedef CaseRemarksLoader = Future<CaseRemarks> Function();

/// Saves [text] (blank is valid) if the stored revision is still
/// [expectedRevision]; returns the stored view.
typedef CaseRemarksSaver =
    Future<CaseRemarks> Function(String text, int expectedRevision);

/// Same limit as the server (functions/src/case_remarks.ts).
const maxCaseRemarksLength = 10000;

/// Optional, manually typed transcript / remarks for one case. Access is
/// decided by the server; this widget never caches text across instances.
class CaseRemarksEditor extends StatefulWidget {
  const CaseRemarksEditor({super.key, required this.load, required this.save});

  final CaseRemarksLoader load;
  final CaseRemarksSaver save;

  @override
  State<CaseRemarksEditor> createState() => _CaseRemarksEditorState();
}

enum _State { loading, ready, denied, failed }

class _CaseRemarksEditorState extends State<CaseRemarksEditor> {
  final _controller = TextEditingController();
  var _state = _State.loading;
  CaseRemarks? _remarks;
  bool _saving = false;
  String? _error;
  bool _conflict = false;

  /// The text a counselor had typed when a conflict forced a reload.
  String? _unsavedDraft;

  static const _notAuthorized =
      'You are not authorized to view or edit remarks for this case.';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _dirty =>
      _remarks != null && _controller.text.trim() != _remarks!.text.trim();

  Future<void> _load({bool keepDraft = false}) async {
    final draft = _controller.text;
    setState(() {
      _state = _State.loading;
      _error = null;
    });
    try {
      final remarks = await widget.load();
      if (!mounted) return;
      setState(() {
        _remarks = remarks;
        _controller.text = remarks.text;
        if (keepDraft && draft.trim() != remarks.text.trim()) {
          _unsavedDraft = draft;
        }
        _conflict = false;
        _state = _State.ready;
      });
    } catch (error) {
      if (!mounted) return;
      final denied =
          error is FirebaseFunctionsException &&
          error.code == 'permission-denied';
      setState(() => _state = denied ? _State.denied : _State.failed);
    }
  }

  Future<void> _save() async {
    final remarks = _remarks;
    if (remarks == null || _saving || !_dirty) return;
    if (remarks.hasRemarks && _controller.text.trim().isEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clear saved remarks?'),
          content: const Text(
            'This will clear the current remarks for this case. Previous '
            'versions remain available in the version history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear remarks'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _conflict = false;
    });
    try {
      final saved = await widget.save(_controller.text, remarks.revision);
      if (!mounted) return;
      setState(() {
        _remarks = saved;
        _controller.text = saved.text;
        _unsavedDraft = null;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      // The typed text stays in the field: a failed save never discards it.
      setState(() {
        _saving = false;
        _conflict =
            error is FirebaseFunctionsException && error.code == 'aborted';
        _error = _saveError(error);
      });
    }
  }

  String _saveError(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'aborted':
          return 'These remarks were changed by someone else. Reload the '
              'latest version; your text will be kept below so you can copy '
              'it.';
        case 'permission-denied':
          return 'You are no longer authorized to edit these remarks. Your '
              'text was not saved.';
        case 'invalid-argument':
          final message = error.message?.trim() ?? '';
          return message.isNotEmpty
              ? message
              : 'These remarks cannot be saved.';
      }
    }
    return 'Remarks were not saved. Your text is still here; try again.';
  }

  @override
  Widget build(BuildContext context) => switch (_state) {
    _State.loading => const Padding(
      padding: EdgeInsets.all(12),
      child: Center(child: CircularProgressIndicator()),
    ),
    _State.denied => const _Notice(text: _notAuthorized),
    _State.failed => _Notice(
      text: 'We could not load the remarks for this case.',
      action: TextButton(onPressed: _load, child: const Text('Retry')),
    ),
    _State.ready => _editor(),
  };

  Widget _editor() {
    final remarks = _remarks!;
    final status = _saving
        ? 'Saving…'
        : _dirty
        ? 'Unsaved changes'
        : remarks.revision == 0
        ? 'No remarks saved yet.'
        : 'Last saved'
              '${remarks.authorName.isEmpty ? '' : ' by ${remarks.authorName}'}'
              '${remarks.updatedAt == null ? '' : ' · ${_dateTime(remarks.updatedAt!)}'}'
              ' · revision ${remarks.revision}';
    final older = remarks.versions
        .where((version) => version.revision != remarks.revision)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('case-remarks-field'),
          controller: _controller,
          enabled: !_saving,
          minLines: 4,
          maxLines: 12,
          maxLength: maxCaseRemarksLength,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: 'Transcript / Remarks (optional)',
            helperText:
                'Optional. Typed by the counselor; nothing is recorded or '
                'transcribed automatically. Only counselors responsible for '
                'this student can see it.',
            helperMaxLines: 3,
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: _dirty && !_saving ? _save : null,
              child: const Text('Save remarks'),
            ),
            Text(
              status,
              style: const TextStyle(color: AdminColors.muted, fontSize: 12),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_conflict)
            TextButton(
              onPressed: () => _load(keepDraft: true),
              child: const Text('Reload latest'),
            ),
        ],
        if (_unsavedDraft != null) ...[
          const SizedBox(height: 8),
          const Text(
            'Your unsaved text',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: AdminColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(_unsavedDraft!),
          ),
        ],
        if (older.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Previous versions (${older.length})'),
            children: [
              for (final version in older)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Revision ${version.revision}'
                        '${version.authorName.isEmpty ? '' : ' · ${version.authorName}'}'
                        '${version.savedAt == null ? '' : ' · ${_dateTime(version.savedAt!)}'}',
                        style: const TextStyle(
                          color: AdminColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        version.text.isEmpty ? '(cleared)' : version.text,
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(text, style: const TextStyle(color: AdminColors.muted)),
        ?action,
      ],
    ),
  );
}
