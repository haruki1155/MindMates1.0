import 'package:flutter/material.dart';

import '../../../models/pacc_availability_model.dart';
import '../theme/admin_theme.dart';

/// Explicit office-hour choice. There is no ambiguous "Office open" toggle.
class PaccOfficeHoursSelector extends StatelessWidget {
  const PaccOfficeHoursSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: const InputDecoration(labelText: 'Office Hours'),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<bool>(
        value: value,
        isExpanded: true,
        items: const [
          DropdownMenuItem(value: true, child: Text('Open')),
          DropdownMenuItem(value: false, child: Text('Closed')),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    ),
  );
}

/// Returns 24-hour HH:mm to preserve the existing Firestore contract.
String paccTimeOfDayValue(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

TimeOfDay paccParseTimeOfDay(String text) {
  final parts = text.split(':');
  final hours = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
  final minutes = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (hours == null ||
      minutes == null ||
      hours < 0 ||
      hours > 23 ||
      minutes < 0 ||
      minutes > 59) {
    return const TimeOfDay(hour: 8, minute: 0);
  }
  return TimeOfDay(hour: hours, minute: minutes);
}

class PaccTimePickerField extends StatelessWidget {
  const PaccTimePickerField({
    super.key,
    this.fieldKey,
    required this.controller,
    required this.label,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    readOnly: true,
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: const Icon(Icons.access_time_outlined),
    ),
    onTap: () async {
      final picked = await showTimePicker(
        context: context,
        initialTime: paccParseTimeOfDay(controller.text),
      );
      if (picked != null && context.mounted) {
        controller.text = paccTimeOfDayValue(picked);
      }
    },
  );
}

/// Weekly schedule shown as five explicit columns; horizontal-scrollable on narrow screens.
class PaccWeeklyScheduleTable extends StatelessWidget {
  const PaccWeeklyScheduleTable({
    super.key,
    required this.days,
    required this.readOnly,
    required this.onEditDay,
  });

  final Map<int, PaccDaySchedule> days;
  final bool readOnly;
  final ValueChanged<int> onEditDay;
  static const _names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
  ];

  String _time(String value) {
    final time = paccParseTimeOfDay(value);
    final h = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m ${time.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Scrollbar(
      thumbVisibility: false,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
            headingRowHeight: 52,
            dataRowMinHeight: 58,
            dataRowMaxHeight: 78,
            horizontalMargin: 12,
            columnSpacing: 20,
            columns: const [
              DataColumn(label: Text('Day')),
              DataColumn(label: Text('Opening Time')),
              DataColumn(label: Text('Closing Time')),
              DataColumn(label: Text('Office Status')),
              DataColumn(label: Text('Action')),
            ],
            rows: List.generate(5, (index) {
              final day = index + 1;
              final schedule = days[day] ?? PaccDaySchedule.closed;
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      _names[index],
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  DataCell(
                    Text(schedule.enabled ? _time(schedule.opensAt) : '—'),
                  ),
                  DataCell(
                    Text(schedule.enabled ? _time(schedule.closesAt) : '—'),
                  ),
                  DataCell(
                    Tooltip(
                      message: schedule.enabled
                          ? schedule.presence.label
                          : 'Office is closed',
                      child: Chip(
                        backgroundColor: schedule.enabled
                            ? const Color(0xFFE5F6EB)
                            : AdminColors.surfaceMuted,
                        label: Text(schedule.enabled ? 'Open' : 'Closed'),
                      ),
                    ),
                  ),
                  DataCell(
                    readOnly
                        ? const Text('View only')
                        : OutlinedButton.icon(
                            key: Key('edit-day-$day'),
                            onPressed: () => onEditDay(day),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: Text('Edit ${_names[index]}'),
                          ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    ),
  );
}
