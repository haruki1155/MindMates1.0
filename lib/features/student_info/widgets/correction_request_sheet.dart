import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../repositories/student_roster_repository.dart';

const _months = [
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

/// `2005-02-03` -> `Feb 3, 2005`. Returns [key] unchanged when unparseable.
String formatDateKey(String key) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  if (m == null) return key;
  final month = int.parse(m.group(2)!);
  if (month < 1 || month > 12) return key;
  return '${_months[month - 1]} ${int.parse(m.group(3)!)}, ${m.group(1)}';
}

const _yearLevels = [
  '1st Year',
  '2nd Year',
  '3rd Year',
  '4th Year',
  '5th Year',
];

/// Opens the correction request sheet. Resolves to true when a request was
/// submitted.
Future<bool> showCorrectionRequestSheet(
  BuildContext context, {
  required StudentRosterRepository repository,
  required String fieldKey,
  required String label,
  required String currentValue,
}) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CorrectionRequestSheet(
      repository: repository,
      fieldKey: fieldKey,
      label: label,
      currentValue: currentValue,
    ),
  );
  return submitted ?? false;
}

class CorrectionRequestSheet extends StatefulWidget {
  const CorrectionRequestSheet({
    super.key,
    required this.repository,
    required this.fieldKey,
    required this.label,
    required this.currentValue,
  });

  final StudentRosterRepository repository;
  final String fieldKey;
  final String label;
  final String currentValue;

  @override
  State<CorrectionRequestSheet> createState() => _CorrectionRequestSheetState();
}

class _CorrectionRequestSheetState extends State<CorrectionRequestSheet> {
  final _valueController = TextEditingController();
  final _reasonController = TextEditingController();
  String _dateKey = '';
  String? _yearLevel;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _valueController.addListener(_refresh);
    _reasonController.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _valueController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  String get _value => switch (widget.fieldKey) {
    'dateOfBirth' => _dateKey,
    'yearLevel' => _yearLevel ?? '',
    _ => _valueController.text.trim(),
  };

  bool get _canSubmit =>
      !_submitting &&
      _value.isNotEmpty &&
      _reasonController.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(today.year - 18, today.month, today.day),
      firstDate: DateTime(today.year - 120),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dateKey =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.requestCorrection(
        field: widget.fieldKey,
        requestedValue: _value,
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message?.trim().isNotEmpty == true
            ? error.message
            : 'We could not send your request. Try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'We could not send your request. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Request correction: ${widget.label}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Current value: ${widget.fieldKey == 'dateOfBirth' ? formatDateKey(widget.currentValue) : widget.currentValue}',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          _valueInput(),
          const SizedBox(height: 14),
          TextField(
            key: const Key('correction-reason'),
            controller: _reasonController,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Reason',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit request'),
          ),
        ],
      ),
    );
  }

  Widget _valueInput() {
    switch (widget.fieldKey) {
      case 'dateOfBirth':
        return InkWell(
          key: const Key('correction-value'),
          onTap: _pickDate,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Correct date of birth',
              border: OutlineInputBorder(),
            ),
            child: Text(
              _dateKey.isEmpty ? 'Select date' : formatDateKey(_dateKey),
            ),
          ),
        );
      case 'yearLevel':
        return DropdownButtonFormField<String>(
          key: const Key('correction-value'),
          initialValue: _yearLevel,
          decoration: const InputDecoration(
            labelText: 'Correct year level',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final y in _yearLevels)
              DropdownMenuItem(value: y, child: Text(y)),
          ],
          onChanged: (v) => setState(() => _yearLevel = v),
        );
      default:
        return TextField(
          key: const Key('correction-value'),
          controller: _valueController,
          maxLength: 160,
          decoration: InputDecoration(
            labelText: 'Correct ${widget.label.toLowerCase()}',
            border: const OutlineInputBorder(),
          ),
        );
    }
  }
}
