import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../providers/reminder_preferences_provider.dart';
import '../models/reminder_preferences.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({
    super.key,
    required this.userId,
    this.focusMoodSection = false,
    this.notificationPermissionGranted,
    this.openDeviceSettings,
    this.pickTime,
  });

  final String userId;
  final bool focusMoodSection;
  final Future<bool> Function()? notificationPermissionGranted;
  final Future<bool> Function()? openDeviceSettings;
  final Future<TimeOfDay?> Function(TimeOfDay initialTime)? pickTime;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen>
    with WidgetsBindingObserver {
  bool? _pushPermissionGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ReminderPreferencesProvider>().load(widget.userId);
      _refreshPermission();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    try {
      final permissionCheck = widget.notificationPermissionGranted;
      final granted = permissionCheck == null
          ? (await Permission.notification.status).isGranted
          : await permissionCheck();
      if (mounted) setState(() => _pushPermissionGranted = granted);
    } catch (_) {
      if (mounted) setState(() => _pushPermissionGranted = false);
    }
  }

  Future<void> _openDeviceSettings() async {
    final openSettings = widget.openDeviceSettings;
    if (openSettings == null) {
      await openAppSettings();
    } else {
      await openSettings();
    }
    await _refreshPermission();
  }

  Future<void> _save(
    ReminderPreferencesProvider provider,
    ReminderPreferences preferences,
  ) async {
    try {
      await provider.save(widget.userId, preferences);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save reminders. Please try again.'),
        ),
      );
    }
  }

  Future<void> _chooseTime({
    required ReminderPreferencesProvider provider,
    required ReminderPreferences preferences,
    required bool mood,
  }) async {
    final value = mood
        ? preferences.moodDailyTime
        : preferences.breathingDailyTime;
    final parts = value.split(':').map(int.parse).toList(growable: false);
    final initialTime = TimeOfDay(hour: parts[0], minute: parts[1]);
    final picker = widget.pickTime;
    final selected = picker == null
        ? await showTimePicker(context: context, initialTime: initialTime)
        : await picker(initialTime);
    if (!mounted || selected == null) return;

    final time =
        '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
    await _save(
      provider,
      mood
          ? preferences.copyWith(moodDailyTime: time)
          : preferences.copyWith(breathingDailyTime: time),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reminders')),
    body: Consumer<ReminderPreferencesProvider>(
      builder: (context, provider, _) {
        final preferences = provider.preferences;
        if (provider.isLoading && preferences == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (preferences == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Unable to load reminder settings.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => provider.load(widget.userId),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose which reminders work for you.',
                style: TextStyle(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 8),
              const Text(
                'Daily reminder times use Philippine time (Asia/Manila).',
                key: ValueKey('reminder-time-zone-label'),
                style: TextStyle(color: Color(0xFF686868), fontSize: 13),
              ),
              const SizedBox(height: 20),
              if (_pushPermissionGranted == false) ...[
                _PermissionNotice(onOpenSettings: _openDeviceSettings),
                const SizedBox(height: 20),
              ],
              if (!widget.focusMoodSection) ...[
                _appointmentCard(provider, preferences),
                const SizedBox(height: 16),
              ],
              _selfCareCard(context, provider, preferences),
              if (widget.focusMoodSection) ...[
                const SizedBox(height: 16),
                _appointmentCard(provider, preferences),
              ],
            ],
          ),
        );
      },
    ),
  );

  Widget _appointmentCard(
    ReminderPreferencesProvider provider,
    ReminderPreferences preferences,
  ) => _PreferenceCard(
    title: 'Appointment reminders',
    children: [
      SwitchListTile(
        key: const ValueKey('appointment-24-hour-switch'),
        contentPadding: EdgeInsets.zero,
        title: const Text('24-hour reminder'),
        subtitle: const Text('The day before your appointment'),
        value: preferences.appointment24HourEnabled,
        onChanged: (value) => _save(
          provider,
          preferences.copyWith(appointment24HourEnabled: value),
        ),
      ),
      SwitchListTile(
        key: const ValueKey('appointment-1-hour-switch'),
        contentPadding: EdgeInsets.zero,
        title: const Text('1-hour reminder'),
        subtitle: const Text('About an hour before your appointment'),
        value: preferences.appointment1HourEnabled,
        onChanged: (value) => _save(
          provider,
          preferences.copyWith(appointment1HourEnabled: value),
        ),
      ),
    ],
  );

  Widget _selfCareCard(
    BuildContext context,
    ReminderPreferencesProvider provider,
    ReminderPreferences preferences,
  ) => _PreferenceCard(
    title: 'Daily self-care reminders',
    children: [
      KeyedSubtree(
        key: const ValueKey('mood-reminders-section'),
        child: Column(
          children: [
            SwitchListTile(
              key: const ValueKey('mood-reminder-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Mood check-in'),
              subtitle: const Text('A gentle prompt to log how you feel'),
              value: preferences.moodDailyEnabled,
              onChanged: (value) => _save(
                provider,
                preferences.copyWith(moodDailyEnabled: value),
              ),
            ),
            if (preferences.moodDailyEnabled)
              _TimeTile(
                key: const ValueKey('mood-reminder-time'),
                label: 'Mood reminder time',
                time: _formatTime(context, preferences.moodDailyTime),
                onTap: () => _chooseTime(
                  provider: provider,
                  preferences: preferences,
                  mood: true,
                ),
              ),
          ],
        ),
      ),
      SwitchListTile(
        key: const ValueKey('breathing-reminder-switch'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Mindful breathing'),
        subtitle: const Text('A reminder to take a short breathing break'),
        value: preferences.breathingDailyEnabled,
        onChanged: (value) =>
            _save(provider, preferences.copyWith(breathingDailyEnabled: value)),
      ),
      if (preferences.breathingDailyEnabled)
        _TimeTile(
          key: const ValueKey('breathing-reminder-time'),
          label: 'Breathing reminder time',
          time: _formatTime(context, preferences.breathingDailyTime),
          onTap: () => _chooseTime(
            provider: provider,
            preferences: preferences,
            mood: false,
          ),
        ),
    ],
  );

  String _formatTime(BuildContext context, String value) {
    final parts = value.split(':').map(int.parse).toList(growable: false);
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay(hour: parts[0], minute: parts[1]));
  }
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: const Color(0xFFFFFFFF),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFE8E4DC)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    super.key,
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.only(left: 12, right: 4),
    title: Text(label),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(time, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        const Icon(Icons.access_time),
      ],
    ),
    onTap: onTap,
  );
}

class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E6),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE9D5A7)),
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Notifications are off for this device. Reminders will still appear in your MindMate inbox.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Open device settings'),
        ),
      ],
    ),
  );
}
