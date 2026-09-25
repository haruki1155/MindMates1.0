import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/appointment_model.dart';
import '../../../providers/appointment_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../core/widgets/mindmate_bottom_navigation.dart';
import '../../home/screens/home_appointment_calendar_screen.dart';
import '../widgets/appointment_details_sheet.dart';
import '../widgets/appointment_list_view.dart';
import '../../notifications/screens/notifications_screen.dart';

class PaccCounselingScreen extends StatefulWidget {
  const PaccCounselingScreen({
    super.key,
    this.startBooking = false,
    this.initialConcern,
    this.initialAppointmentId,
    this.showBottomNavigation = true,
    DateTime Function()? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  final DateTime Function() _nowProvider;
  final bool startBooking;
  final String? initialConcern;
  final String? initialAppointmentId;
  final bool showBottomNavigation;

  @override
  State<PaccCounselingScreen> createState() => _PaccCounselingScreenState();
}

class _PaccCounselingScreenState extends State<PaccCounselingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleInitialController = TextEditingController();
  final _ageController = TextEditingController();
  final _addressController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _emailController = TextEditingController();
  final _facebookController = TextEditingController();
  final _concernController = TextEditingController();
  final _bestTimeController = TextEditingController();

  late _PaccAppointmentTab _tab;
  _PaccAppointmentStep _step = _PaccAppointmentStep.calendar;
  late DateTime _visibleMonth;
  DateTime? _selectedDate;
  String? _selectedTime;
  String? _sex;
  String? _course;
  String? _yearLevel;
  String? _preferredContactMethod;
  String? _therapyBefore;
  String? _prefilledUserId;
  String? _loadedUserId;
  bool _initialDetailsHandled = false;
  List<String> _availableTimes = const [];
  bool _loadingTimes = false;
  String? _parentAppointmentId;

  DateTime get _today => DateUtils.dateOnly(widget._nowProvider());

  @override
  void initState() {
    super.initState();
    _tab = widget.startBooking
        ? _PaccAppointmentTab.appointNew
        : _PaccAppointmentTab.myAppointments;
    final today = _today;
    _visibleMonth = DateTime(today.year, today.month);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = _readProviderOrNull<UserProvider>()?.user;
    if (user != null && _prefilledUserId != user.id) {
      _prefilledUserId = user.id;
      _lastNameController.text = user.lastName ?? '';
      _firstNameController.text = user.firstName ?? '';
      _middleInitialController.text = _initial(user.middleName);
      _ageController.clear();
      _addressController.clear();
      _contactNumberController.clear();
      _emailController.text = user.email;
      _facebookController.clear();
      _concernController.text = widget.initialConcern?.trim() ?? '';
      _bestTimeController.clear();
      _sex = null;
      _course = user.course?.trim().isEmpty ?? true ? null : user.course;
      _yearLevel = null;
      _preferredContactMethod = null;
      _therapyBefore = null;
      _selectedDate = null;
      _selectedTime = null;
    }
    final userId = _currentUserId();
    final provider = _readProviderOrNull<AppointmentProvider>();
    if (userId == null || provider == null || _loadedUserId == userId) return;
    _loadedUserId = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) provider.loadAppointments(userId);
    });
  }

  @override
  void dispose() {
    _lastNameController.dispose();
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _ageController.dispose();
    _addressController.dispose();
    _contactNumberController.dispose();
    _emailController.dispose();
    _facebookController.dispose();
    _concernController.dispose();
    _bestTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _watchProviderOrNull<AuthProvider>();
    _watchProviderOrNull<UserProvider>();
    _watchProviderOrNull<AppointmentProvider>();
    return Scaffold(
      backgroundColor: _PaccColors.background,
      bottomNavigationBar: widget.showBottomNavigation
          ? const MindMateBottomNavigation(
              active: MindMateNavDestination.appointments,
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _PaccHeader(
              unreadCount:
                  _watchProviderOrNull<NotificationProvider>()?.unreadCount ??
                  0,
              onNotificationsTap: _openNotifications,
            ),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  104 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  if (_tab == _PaccAppointmentTab.appointNew &&
                      _step != _PaccAppointmentStep.confirmation)
                    _BookingStepper(step: _step),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _buildBody(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final appointmentProvider = _watchProviderOrNull<AppointmentProvider>();
    _openInitialAppointmentIfReady(
      appointmentProvider?.appointments ?? const [],
    );
    if (_tab == _PaccAppointmentTab.myAppointments) {
      if (appointmentProvider?.isLoading == true) {
        return const _AppointmentLoading(key: ValueKey('appointmentLoading'));
      }
      if (appointmentProvider?.errorMessage != null) {
        return _AppointmentLoadError(
          key: const ValueKey('appointmentLoadError'),
          message: appointmentProvider!.errorMessage!,
          onRetry: _loadAppointments,
        );
      }
      return AppointmentListView(
        key: const ValueKey('myAppointments'),
        appointments: appointmentProvider?.appointments ?? const [],
        onView: _showAppointmentDetails,
        onCalendar: _openMindMateCalendar,
        onAccept: _acceptReschedule,
        onBook: _startNewAppointment,
        isSaving: appointmentProvider?.isSaving ?? false,
      );
    }

    return switch (_step) {
      _PaccAppointmentStep.calendar => _CalendarView(
        key: const ValueKey('calendar'),
        visibleMonth: _visibleMonth,
        minimumDate: _today,
        selectedDate: _selectedDate,
        onBack: () => setState(() => _tab = _PaccAppointmentTab.myAppointments),
        onPreviousMonth: () => setState(() {
          _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
        }),
        onNextMonth: () => setState(() {
          _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
        }),
        onDateSelected: _selectDate,
      ),
      _PaccAppointmentStep.time => _TimeSelectionView(
        key: const ValueKey('time'),
        selectedDate: _selectedDate,
        selectedTime: _selectedTime,
        availableTimes: _availableTimes,
        isSaving: (appointmentProvider?.isSaving ?? false) || _loadingTimes,
        onBack: () => setState(() => _step = _PaccAppointmentStep.calendar),
        onTimeSelected: (time) => setState(() => _selectedTime = time),
        onNext: () => setState(() => _step = _PaccAppointmentStep.intake),
      ),
      _PaccAppointmentStep.intake => _IntakeFormView(
        key: const ValueKey('intake'),
        formKey: _formKey,
        lastNameController: _lastNameController,
        firstNameController: _firstNameController,
        middleInitialController: _middleInitialController,
        ageController: _ageController,
        addressController: _addressController,
        contactNumberController: _contactNumberController,
        emailController: _emailController,
        facebookController: _facebookController,
        concernController: _concernController,
        bestTimeController: _bestTimeController,
        sex: _sex,
        course: _course,
        yearLevel: _yearLevel,
        preferredContactMethod: _preferredContactMethod,
        therapyBefore: _therapyBefore,
        onSexChanged: (value) => setState(() => _sex = value),
        onCourseChanged: (value) => setState(() => _course = value),
        onYearLevelChanged: (value) => setState(() => _yearLevel = value),
        onPreferredContactMethodChanged: (value) {
          setState(() => _preferredContactMethod = value);
        },
        onTherapyBeforeChanged: (value) {
          setState(() => _therapyBefore = value);
        },
        onBack: () => setState(() => _step = _PaccAppointmentStep.time),
        onNext: _validateIntakeForm,
      ),
      _PaccAppointmentStep.review => _BookingReviewView(
        key: const ValueKey('review'),
        selectedDate: _selectedDate,
        selectedTime: _selectedTime,
        concern: _concernController.text.trim(),
        isSaving: appointmentProvider?.isSaving ?? false,
        onBack: () => setState(() => _step = _PaccAppointmentStep.intake),
        onConfirm: _confirmAppointment,
      ),
      _PaccAppointmentStep.confirmation => _ConfirmationView(
        key: const ValueKey('confirmation'),
        selectedDate: _selectedDate,
        selectedTime: _selectedTime,
        onReturn: () => setState(() {
          _tab = _PaccAppointmentTab.myAppointments;
          _step = _PaccAppointmentStep.calendar;
        }),
      ),
    };
  }

  Future<void> _selectDate(DateTime date) async {
    setState(() {
      _selectedDate = date;
      _selectedTime = null;
      _availableTimes = const [];
      _loadingTimes = true;
      _step = _PaccAppointmentStep.time;
    });
    final slots =
        await _readProviderOrNull<AppointmentProvider>()?.getAvailableSlots(
          date,
        ) ??
        const [];
    if (!mounted || _selectedDate != date) return;
    setState(() {
      _availableTimes = slots.map((slot) => slot.label).toList(growable: false);
      _loadingTimes = false;
    });
  }

  @override
  void didUpdateWidget(covariant PaccCounselingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialAppointmentId != widget.initialAppointmentId) {
      _initialDetailsHandled = false;
    }
  }

  void _openInitialAppointmentIfReady(List<AppointmentModel> appointments) {
    final id = widget.initialAppointmentId;
    if (_initialDetailsHandled || id == null || id.isEmpty) return;
    final appointment = appointments.where((item) => item.id == id).firstOrNull;
    if (appointment == null) return;
    _initialDetailsHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showAppointmentDetails(appointment);
    });
  }

  void _startNewAppointment([AppointmentModel? priorAppointment]) {
    final appointments = _readProviderOrNull<AppointmentProvider>()?.appointments ??
        const <AppointmentModel>[];
    if (appointments.any((appointment) => appointment.isActive)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You already have an active appointment. Please complete your current appointment before booking another one.',
          ),
        ),
      );
      return;
    }
    final today = _today;
    setState(() {
      _tab = _PaccAppointmentTab.appointNew;
      _step = _PaccAppointmentStep.calendar;
      _selectedDate = null;
      _selectedTime = null;
      _visibleMonth = DateTime(today.year, today.month);
      _parentAppointmentId = priorAppointment?.hasAvailableFollowUpOffer == true
          ? priorAppointment?.id
          : null;
      if (priorAppointment != null) {
        _ageController.text = priorAppointment.age?.toString() ?? '';
        _addressController.text = priorAppointment.address ?? '';
        _contactNumberController.text = priorAppointment.contactNumber;
        _emailController.text = priorAppointment.email;
        _facebookController.text = priorAppointment.facebook ?? '';
        _concernController.text = priorAppointment.concern;
        _bestTimeController.text = priorAppointment.bestTime ?? '';
        _sex = priorAppointment.sex;
        _course = priorAppointment.course;
        _yearLevel = priorAppointment.yearLevel;
        _preferredContactMethod = priorAppointment.preferredContactMethod;
        _therapyBefore = priorAppointment.therapyBefore;
      }
    });
  }

  void _validateIntakeForm() {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid ||
        _sex == null ||
        _course == null ||
        _yearLevel == null ||
        _preferredContactMethod == null ||
        _therapyBefore == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields.')),
      );
      setState(() {});
      return;
    }

    setState(() => _step = _PaccAppointmentStep.review);
  }

  Future<void> _confirmAppointment() async {
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a date and time first.')),
      );
      return;
    }

    final userId = _currentUserId();
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to book an appointment.')),
      );
      return;
    }

    final provider = _readProviderOrNull<AppointmentProvider>();
    if (provider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save appointment.')),
      );
      return;
    }
    if (provider.isSaving) return;

    final appointment = AppointmentModel(
      id: '',
      userId: userId,
      fullName:
          '${_lastNameController.text.trim()}, ${_firstNameController.text.trim()} ${_middleInitialController.text.trim()}'
              .trim(),
      age: int.tryParse(_ageController.text.trim()),
      address: _addressController.text.trim(),
      contactNumber: _contactNumberController.text.trim(),
      email: _emailController.text.trim(),
      facebook: _facebookController.text.trim(),
      sex: _sex,
      course: _course,
      yearLevel: _yearLevel,
      preferredContactMethod: _preferredContactMethod!,
      therapyBefore: _therapyBefore,
      concern: _concernController.text.trim(),
      bestTime: _bestTimeController.text.trim(),
      scheduledAt: _scheduledAt(_selectedDate!, _selectedTime!),
      scheduledTime: _selectedTime!,
      location: 'PACC Office, 2nd Floor, Main Building',
      status: AppointmentStatus.requested.value,
      createdAt: DateTime.now(),
      parentAppointmentId: _parentAppointmentId,
    );

    final saved = await provider.createAppointment(appointment);
    if (!mounted) return;
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Unable to save appointment.'),
        ),
      );
      return;
    }
    setState(() => _step = _PaccAppointmentStep.confirmation);
  }

  void _showAppointmentDetails(AppointmentModel appointment) {
    showAppointmentDetailsSheet(
      context,
      appointment,
      onBookAppointment: () => _startNewAppointment(appointment),
    );
  }

  void _openMindMateCalendar(AppointmentModel appointment) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            HomeAppointmentCalendarScreen(initialDate: appointment.scheduledAt),
      ),
    );
  }

  Future<void> _acceptReschedule(AppointmentModel appointment) async {
    final provider = _readProviderOrNull<AppointmentProvider>();
    final saved = await provider?.acceptReschedule(appointment.id) ?? false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'New schedule confirmed.'
                : 'This proposed time is no longer available.',
          ),
        ),
      );
    }
  }

  Future<void> _loadAppointments() async {
    final userId = _currentUserId();
    final provider = _readProviderOrNull<AppointmentProvider>();
    if (userId != null && provider != null) {
      await provider.loadAppointments(userId);
    }
  }

  void _openNotifications() {
    final userId = _currentUserId();
    if (userId == null || userId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(userId: userId),
      ),
    );
  }

  String? _currentUserId() {
    final auth = _readProviderOrNull<AuthProvider>();
    final authId = auth?.userId ?? auth?.hydrateCurrentUser();
    if (authId != null && authId.isNotEmpty) return authId;
    return _readProviderOrNull<UserProvider>()?.user?.id;
  }

  static DateTime _scheduledAt(DateTime date, String time) {
    final parts = time.split(' ');
    final clock = parts.first.split(':');
    var hour = int.tryParse(clock.first) ?? 0;
    final minute = int.tryParse(clock.length > 1 ? clock[1] : '') ?? 0;
    final meridiem = parts.length > 1 ? parts[1].toUpperCase() : '';
    if (meridiem == 'PM' && hour != 12) hour += 12;
    if (meridiem == 'AM' && hour == 12) hour = 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  T? _readProviderOrNull<T>() {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  T? _watchProviderOrNull<T>() {
    try {
      return context.watch<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  String _initial(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '';
    return '${text[0].toUpperCase()}.';
  }
}

class _PaccHeader extends StatelessWidget {
  const _PaccHeader({
    required this.unreadCount,
    required this.onNotificationsTap,
  });

  final int unreadCount;
  final VoidCallback onNotificationsTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: const BoxDecoration(color: _PaccColors.background),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PACC Counseling', style: _PaccText.headerTitle),
                    SizedBox(height: 4),
                    Text(
                      'Your well-being matters',
                      style: _PaccText.headerSubtitle,
                    ),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: unreadCount == 0
                    ? 'Notifications'
                    : '$unreadCount unread notifications',
                child: IconButton(
                  tooltip: 'Notifications',
                  onPressed: onNotificationsTap,
                  icon: Badge.count(
                    isLabelVisible: unreadCount > 0,
                    count: unreadCount,
                    child: const Icon(Icons.notifications_none_rounded),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppointmentLoading extends StatelessWidget {
  const _AppointmentLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 80),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _AppointmentLoadError extends StatelessWidget {
  const _AppointmentLoadError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center, style: _PaccText.body),
          const SizedBox(height: 16),
          _YellowButton(label: 'Try again', onTap: onRetry),
        ],
      ),
    );
  }
}

// Legacy private composition retained temporarily while shared cards are used
// by [AppointmentListView].
// ignore: unused_element
class _MyAppointmentsView extends StatelessWidget {
  // ignore: unused_element_parameter
  const _MyAppointmentsView({
    required this.appointments,
    required this.onAppoint,
    required this.onViewDetails,
    required this.onAddToCalendar,
    required this.onCancel,
    required this.onAcceptReschedule,
    required this.onRequestReschedule,
    required this.onBookAgain,
  });

  final List<AppointmentModel> appointments;
  final VoidCallback onAppoint;
  final ValueChanged<AppointmentModel> onViewDetails;
  final ValueChanged<AppointmentModel> onAddToCalendar;
  final ValueChanged<AppointmentModel> onCancel;
  final ValueChanged<AppointmentModel> onAcceptReschedule;
  final ValueChanged<AppointmentModel> onRequestReschedule;
  final VoidCallback onBookAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _EmergencyHelpCard(),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text('Upcoming Appointments', style: _PaccText.title),
              ),
            ),
            TextButton.icon(
              onPressed: onAppoint,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New appointment'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (appointments.isEmpty)
          _EmptyAppointmentCard(onAppoint: onAppoint)
        else
          for (final appointment in appointments) ...[
            _AppointmentCard(
              appointment: appointment,
              onViewDetails: () => onViewDetails(appointment),
              onAddToCalendar: () => onAddToCalendar(appointment),
              onCancel: () => onCancel(appointment),
              onAcceptReschedule: () => onAcceptReschedule(appointment),
              onRequestReschedule: () => onRequestReschedule(appointment),
              onBookAgain: onBookAgain,
            ),
            const SizedBox(height: 14),
          ],
      ],
    );
  }
}

class _EmergencyHelpCard extends StatelessWidget {
  const _EmergencyHelpCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: _PaccDecor.card(
        color: const Color(0xFFFFE58B),
        radius: 14,
        borderColor: const Color(0x33CC9800),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _PaccColors.sunButton,
                child: Icon(Icons.phone_in_talk_outlined, color: Colors.black),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Need immediate help?',
                  style: _PaccText.cardTitleLarge,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(left: 48),
            child: Text(
              'PACC Crisis Hotline available 24/7',
              style: _PaccText.body,
            ),
          ),
          SizedBox(height: 14),
          Padding(
            padding: EdgeInsets.only(left: 48),
            child: _ContactRow(
              icon: Icons.call_outlined,
              text: '+63 912 345 6789',
            ),
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(left: 48),
            child: _ContactRow(
              icon: Icons.mail_outline,
              text: 'pacc@ucu.edu.ph',
              underline: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.text,
    this.underline = false,
  });

  final IconData icon;
  final String text;
  final bool underline;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.black),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            decoration: underline ? TextDecoration.underline : null,
          ),
        ),
      ],
    );
  }
}

class _EmptyAppointmentCard extends StatelessWidget {
  const _EmptyAppointmentCard({required this.onAppoint});

  final VoidCallback onAppoint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 24),
      decoration: _PaccDecor.card(borderColor: _PaccColors.sunButton),
      child: Column(
        children: [
          const Icon(Icons.calendar_month, size: 56, color: Color(0xFFA66A6A)),
          const SizedBox(height: 8),
          const Text('No upcoming appointments', style: _PaccText.body),
          const SizedBox(height: 16),
          SizedBox(
            width: 164,
            child: _YellowButton(label: 'Appoint a Session', onTap: onAppoint),
          ),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.onViewDetails,
    required this.onAddToCalendar,
    required this.onCancel,
    required this.onAcceptReschedule,
    required this.onRequestReschedule,
    required this.onBookAgain,
  });

  final AppointmentModel appointment;
  final VoidCallback onViewDetails;
  final VoidCallback onAddToCalendar;
  final VoidCallback onCancel;
  final VoidCallback onAcceptReschedule;
  final VoidCallback onRequestReschedule;
  final VoidCallback onBookAgain;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: _PaccDecor.card(borderColor: _PaccColors.sunButton),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  appointment.fullName,
                  style: _PaccText.cardTitleLarge,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFDF7E),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  appointment.lifecycleStatus.label,
                  style: _PaccText.tinyBold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _DetailLine(
            icon: Icons.calendar_today_outlined,
            text: _formatFullDate(appointment.scheduledAt),
          ),
          _DetailLine(icon: Icons.schedule, text: appointment.scheduledTime),
          _DetailLine(icon: Icons.place_outlined, text: appointment.location),
          const Divider(height: 28),
          const Text('Concern', style: _PaccText.cardTitle),
          const SizedBox(height: 10),
          Text(appointment.concern, style: _PaccText.body),
          const SizedBox(height: 18),
          _AppointmentActions(
            appointment: appointment,
            onViewDetails: onViewDetails,
            onAddToCalendar: onAddToCalendar,
            onCancel: onCancel,
            onAcceptReschedule: onAcceptReschedule,
            onRequestReschedule: onRequestReschedule,
            onBookAgain: onBookAgain,
          ),
        ],
      ),
    );
  }
}

class _AppointmentActions extends StatelessWidget {
  const _AppointmentActions({
    required this.appointment,
    required this.onViewDetails,
    required this.onAddToCalendar,
    required this.onCancel,
    required this.onAcceptReschedule,
    required this.onRequestReschedule,
    required this.onBookAgain,
  });
  final AppointmentModel appointment;
  final VoidCallback onViewDetails;
  final VoidCallback onAddToCalendar;
  final VoidCallback onCancel;
  final VoidCallback onAcceptReschedule;
  final VoidCallback onRequestReschedule;
  final VoidCallback onBookAgain;

  @override
  Widget build(BuildContext context) {
    final status = appointment.lifecycleStatus;
    final actions = <Widget>[
      _SmallYellowButton(label: 'View Details', onTap: onViewDetails),
    ];
    if (status == AppointmentStatus.confirmed) {
      actions.addAll([
        _SmallYellowButton(label: 'Add to Calendar', onTap: onAddToCalendar),
      ]);
    } else if (status == AppointmentStatus.requested ||
        status == AppointmentStatus.legacyRequested) {
    } else if (status == AppointmentStatus.rescheduleProposed) {
      actions.addAll([
        _SmallYellowButton(
          label: 'Accept New Schedule',
          onTap: onAcceptReschedule,
        ),
      ]);
    } else if (status == AppointmentStatus.cancelled) {
      actions.add(_SmallYellowButton(label: 'Book Again', onTap: onBookAgain));
    } else if (status == AppointmentStatus.completed &&
        appointment.followUpRecommended) {
      actions.add(
        _SmallYellowButton(label: 'Book Follow-up', onTap: onBookAgain),
      );
    } else if (status == AppointmentStatus.noShow) {
      actions.add(
        _SmallYellowButton(
          label: 'Book Another Appointment',
          onTap: onBookAgain,
        ),
      );
    } else if (status == AppointmentStatus.declined) {
      actions.add(
        _SmallYellowButton(
          label: 'Request New Appointment',
          onTap: onBookAgain,
        ),
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: actions
          .map((action) => SizedBox(width: 150, child: action))
          .toList(),
    );
  }
}

class _CalendarView extends StatelessWidget {
  const _CalendarView({
    super.key,
    required this.visibleMonth,
    required this.minimumDate,
    required this.selectedDate,
    required this.onBack,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onDateSelected,
  });

  final DateTime visibleMonth;
  final DateTime minimumDate;
  final DateTime? selectedDate;
  final VoidCallback onBack;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(
      visibleMonth.year,
      visibleMonth.month,
    );
    final firstWeekday = DateTime(
      visibleMonth.year,
      visibleMonth.month,
    ).weekday;
    final leadingSlots = firstWeekday % 7;
    final totalSlots = leadingSlots + daysInMonth;
    final monthLabel = _formatMonth(visibleMonth);

    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      decoration: _PaccDecor.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to intake form',
                onPressed: onBack,
                icon: const Icon(Icons.chevron_left, color: Colors.black),
              ),
              const Expanded(
                child: Text('Appointment Schedule', style: _PaccText.title),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _RoundIconButton(
                icon: Icons.chevron_left,
                onTap: onPreviousMonth,
                tooltip: 'Previous month',
              ),
              Expanded(
                child: Center(
                  child: Text(monthLabel, style: _PaccText.monthTitle),
                ),
              ),
              _RoundIconButton(
                icon: Icons.chevron_right,
                onTap: onNextMonth,
                tooltip: 'Next month',
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              _WeekdayLabel('S'),
              _WeekdayLabel('M'),
              _WeekdayLabel('T'),
              _WeekdayLabel('W'),
              _WeekdayLabel('Th'),
              _WeekdayLabel('Sat'),
              _WeekdayLabel('S'),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ((totalSlots + 6) ~/ 7) * 7,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 10,
              crossAxisSpacing: 8,
              childAspectRatio: 1.05,
            ),
            itemBuilder: (context, index) {
              final day = index - leadingSlots + 1;
              if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
              final date = DateTime(visibleMonth.year, visibleMonth.month, day);
              final enabled = !date.isBefore(DateUtils.dateOnly(minimumDate));
              final selected =
                  selectedDate != null &&
                  DateUtils.isSameDay(selectedDate, date);
              final suggested = enabled && (day == 28 || day == 30);
              return _CalendarDayButton(
                day: day,
                selected: selected,
                suggested: suggested,
                enabled: enabled,
                onTap: () => onDateSelected(date),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TimeSelectionView extends StatelessWidget {
  const _TimeSelectionView({
    super.key,
    required this.selectedDate,
    required this.selectedTime,
    required this.availableTimes,
    required this.isSaving,
    required this.onBack,
    required this.onTimeSelected,
    required this.onNext,
  });

  final DateTime? selectedDate;
  final String? selectedTime;
  final List<String> availableTimes;
  final bool isSaving;
  final VoidCallback onBack;
  final ValueChanged<String> onTimeSelected;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back to calendar',
              onPressed: onBack,
              icon: const Icon(Icons.chevron_left, color: Colors.black),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose Time', style: _PaccText.title),
                Text(
                  selectedDate == null
                      ? 'Choose a date'
                      : _formatWeekdayMonthDay(selectedDate!),
                  style: _PaccText.subtitle,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth >= 430
                ? (constraints.maxWidth - 24) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 24,
              runSpacing: 20,
              children: [
                for (final time in availableTimes)
                  SizedBox(
                    width: itemWidth,
                    child: _TimeCard(
                      time: time,
                      selected: selectedTime == time,
                      onTap: () => onTimeSelected(time),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 34),
        const _ReminderCard(),
        const SizedBox(height: 34),
        Center(
          child: SizedBox(
            width: 230,
            child: _YellowButton(
              label: isSaving ? 'Saving...' : 'Continue to Details',
              onTap: onNext,
              enabled: selectedTime != null && !isSaving,
            ),
          ),
        ),
      ],
    );
  }
}

class _TimeCard extends StatelessWidget {
  const _TimeCard({
    required this.time,
    required this.selected,
    required this.onTap,
  });

  final String time;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFFF2BC) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 104,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? _PaccColors.sunButton : const Color(0xFFE5C24D),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.schedule, size: 22),
              const SizedBox(height: 8),
              Text(time, style: _PaccText.cardTitle),
              const SizedBox(height: 2),
              const Text('Available', style: _PaccText.body),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4CC),
        border: Border.all(color: const Color(0xFFE6BE42)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Confidentiality Reminder: All counseling sessions are confidential and protected under professional ethics. Your privacy is our priority.',
        style: _PaccText.body,
      ),
    );
  }
}

class _IntakeFormView extends StatelessWidget {
  const _IntakeFormView({
    super.key,
    required this.formKey,
    required this.lastNameController,
    required this.firstNameController,
    required this.middleInitialController,
    required this.ageController,
    required this.addressController,
    required this.contactNumberController,
    required this.emailController,
    required this.facebookController,
    required this.concernController,
    required this.bestTimeController,
    required this.sex,
    required this.course,
    required this.yearLevel,
    required this.preferredContactMethod,
    required this.therapyBefore,
    required this.onSexChanged,
    required this.onCourseChanged,
    required this.onYearLevelChanged,
    required this.onPreferredContactMethodChanged,
    required this.onTherapyBeforeChanged,
    required this.onBack,
    required this.onNext,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController lastNameController;
  final TextEditingController firstNameController;
  final TextEditingController middleInitialController;
  final TextEditingController ageController;
  final TextEditingController addressController;
  final TextEditingController contactNumberController;
  final TextEditingController emailController;
  final TextEditingController facebookController;
  final TextEditingController concernController;
  final TextEditingController bestTimeController;
  final String? sex;
  final String? course;
  final String? yearLevel;
  final String? preferredContactMethod;
  final String? therapyBefore;
  final ValueChanged<String?> onSexChanged;
  final ValueChanged<String?> onCourseChanged;
  final ValueChanged<String?> onYearLevelChanged;
  final ValueChanged<String?> onPreferredContactMethodChanged;
  final ValueChanged<String?> onTherapyBeforeChanged;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        key: key,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to date and time',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              const Expanded(
                child: Text('Appointment Details', style: _PaccText.title),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            decoration: _PaccDecor.card(borderColor: _PaccColors.sunButton),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Counseling Details', style: _PaccText.title),
                SizedBox(height: 8),
                Text(
                  'Please fill out all required fields (*) to schedule your counseling session with the PACC office.',
                  style: _PaccText.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _FormSection(
            number: 1,
            title: 'Personal Information',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel('Full Name*'),
                Row(
                  children: [
                    Expanded(
                      child: _PaccTextField(
                        controller: lastNameController,
                        hint: 'Last Name',
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PaccTextField(
                        controller: firstNameController,
                        hint: 'First Name',
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: _PaccTextField(
                        controller: middleInitialController,
                        hint: 'M.I.',
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _FieldLabel('Age*'),
                _PaccTextField(
                  controller: ageController,
                  hint: 'e.g. 20',
                  keyboardType: TextInputType.number,
                  validator: _required,
                ),
                const SizedBox(height: 14),
                _RadioGroup(
                  label: 'Sex*',
                  value: sex,
                  options: const [
                    'Female',
                    'Male',
                    'Prefer not to say',
                    'Other',
                  ],
                  onChanged: onSexChanged,
                ),
                const SizedBox(height: 14),
                const _FieldLabel('Complete Address*'),
                _PaccTextField(
                  controller: addressController,
                  hint: 'Your answer',
                  validator: _required,
                ),
                const SizedBox(height: 14),
                const _FieldLabel('Contact Number*'),
                _PaccTextField(
                  controller: contactNumberController,
                  hint: 'Your answer',
                  keyboardType: TextInputType.phone,
                  validator: _required,
                ),
                const SizedBox(height: 14),
                const _FieldLabel('Email Address*'),
                _PaccTextField(
                  controller: emailController,
                  hint: 'Your answer',
                  keyboardType: TextInputType.emailAddress,
                  validator: _emailRequired,
                ),
                const SizedBox(height: 14),
                const _FieldLabel('Facebook Account Name and Link*'),
                _PaccTextField(
                  controller: facebookController,
                  hint: 'Your answer',
                  validator: _required,
                ),
                const SizedBox(height: 14),
                const _FieldLabel('Course*'),
                _PaccDropdown(
                  value: course,
                  hint: 'Select course',
                  options: const [
                    'BS Information Technology',
                    'BS Computer Science',
                    'BS Business Administration',
                    'BS Hospitality Management',
                    'BS Tourism Management',
                    'BS Education',
                    'Other',
                  ],
                  onChanged: onCourseChanged,
                ),
                const SizedBox(height: 14),
                _RadioGroup(
                  label: 'Year Level*',
                  value: yearLevel,
                  options: const [
                    'First Year',
                    'Second Year',
                    'Third Year',
                    'Fourth Year',
                    'Fifth Year',
                    'Irregular',
                  ],
                  onChanged: onYearLevelChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          _FormSection(
            number: 2,
            title: 'Counseling Details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RadioGroup(
                  label: 'Preferred Contact Method*',
                  value: preferredContactMethod,
                  options: const [
                    'Phone',
                    'Email',
                    'Facebook Messenger',
                    'Other',
                  ],
                  onChanged: onPreferredContactMethodChanged,
                ),
                const SizedBox(height: 18),
                _RadioGroup(
                  label: 'Have you ever been in therapy before?*',
                  value: therapyBefore,
                  options: const ['Yes', 'No'],
                  onChanged: onTherapyBeforeChanged,
                ),
                const SizedBox(height: 18),
                const _FieldLabel('What brings you to seek help?*'),
                const Text(
                  'Please tell in your own words what brings you to seek help.',
                  style: _PaccText.muted,
                ),
                const SizedBox(height: 8),
                _PaccTextField(
                  controller: concernController,
                  hint: 'Share what you are experiencing...',
                  maxLines: 5,
                  validator: _required,
                ),
                const SizedBox(height: 14),
                const _FieldLabel('Best Time to Contact You*'),
                _PaccTextField(
                  controller: bestTimeController,
                  hint: 'e.g. Weekend mornings 9 AM - 12 PM',
                  validator: _required,
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: _YellowButton(
                    label: 'Review Appointment',
                    onTap: onNext,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }

  static String? _emailRequired(String? value) {
    final required = _required(value);
    if (required != null) return required;
    return value!.contains('@') ? null : 'Enter a valid email';
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.number,
    required this.title,
    required this.child,
  });

  final int number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _PaccDecor.card(radius: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: const BoxDecoration(
                color: _PaccColors.sun,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    child: Text('$number', style: _PaccText.cardTitleLarge),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(title, style: _PaccText.title)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 26),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingReviewView extends StatelessWidget {
  const _BookingReviewView({
    super.key,
    required this.selectedDate,
    required this.selectedTime,
    required this.concern,
    required this.isSaving,
    required this.onBack,
    required this.onConfirm,
  });

  final DateTime? selectedDate;
  final String? selectedTime;
  final String concern;
  final bool isSaving;
  final VoidCallback onBack;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final date = selectedDate == null
        ? 'Not selected'
        : _formatFullDate(selectedDate!);
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back to appointment details',
              onPressed: isSaving ? null : onBack,
              icon: const Icon(Icons.arrow_back),
            ),
            const Expanded(
              child: Text('Confirm Appointment', style: _PaccText.title),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: _PaccDecor.card(radius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReviewInfoRow(Icons.calendar_today_outlined, 'Date', date),
              _ReviewInfoRow(
                Icons.schedule_outlined,
                'Time',
                selectedTime ?? 'Not selected',
              ),
              const _ReviewInfoRow(
                Icons.place_outlined,
                'Location',
                'PACC Office, 2nd Floor, Main Building',
              ),
              const _ReviewInfoRow(
                Icons.person_outline,
                'Counselor',
                'To be assigned',
              ),
              if (concern.isNotEmpty) ...[
                const Divider(height: 32),
                const Text('Concern', style: _PaccText.cardTitle),
                const SizedBox(height: 6),
                Text(concern, style: _PaccText.body),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: _YellowButton(
            label: isSaving ? 'Confirming...' : 'Confirm Appointment',
            enabled: !isSaving,
            onTap: onConfirm,
          ),
        ),
      ],
    );
  }
}

class _BookingStepper extends StatelessWidget {
  const _BookingStepper({required this.step});

  final _PaccAppointmentStep step;

  @override
  Widget build(BuildContext context) {
    final active = switch (step) {
      _PaccAppointmentStep.calendar || _PaccAppointmentStep.time => 0,
      _PaccAppointmentStep.intake => 1,
      _PaccAppointmentStep.review => 2,
      _PaccAppointmentStep.confirmation => 2,
    };
    const labels = ['Date & Time', 'Details', 'Confirm'];
    return Semantics(
      label: 'Booking progress: step ${active + 1} of 3',
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            Expanded(
              child: Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: index <= active
                          ? _PaccColors.sunButton
                          : const Color(0xFFE5E7EB),
                      shape: BoxShape.circle,
                    ),
                    child: Text('${index + 1}', style: _PaccText.tinyBold),
                  ),
                  const SizedBox(height: 6),
                  Text(labels[index], style: _PaccText.body),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewInfoRow extends StatelessWidget {
  const _ReviewInfoRow(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _PaccText.body),
              const SizedBox(height: 2),
              Text(value, style: _PaccText.subtitle),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ConfirmationView extends StatelessWidget {
  const _ConfirmationView({
    super.key,
    required this.selectedDate,
    required this.selectedTime,
    required this.onReturn,
  });

  final DateTime? selectedDate;
  final String? selectedTime;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: key,
      alignment: Alignment.center,
      padding: const EdgeInsets.only(top: 80),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 34, 24, 30),
        decoration: BoxDecoration(
          color: const Color(0xFFD9D9D9),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                color: _PaccColors.sun,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 12,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.check, size: 70, color: Colors.black),
            ),
            const SizedBox(height: 22),
            const Text(
              'Appointment Request Sent!',
              style: _PaccText.confirmTitle,
            ),
            const SizedBox(height: 12),
            const Text(
              "Your appointment request has been sent to PACC Counseling. We'll notify you once your schedule has been confirmed.",
              textAlign: TextAlign.center,
              style: _PaccText.body,
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: _PaccDecor.card(radius: 16),
              child: Column(
                children: [
                  _DetailLine(
                    icon: Icons.calendar_today_outlined,
                    text: selectedDate == null
                        ? ''
                        : _formatFullDate(selectedDate!),
                  ),
                  _DetailLine(
                    icon: Icons.schedule_outlined,
                    text: selectedTime ?? '',
                  ),
                  const _DetailLine(
                    icon: Icons.place_outlined,
                    text: 'PACC Office, 2nd Floor, Main Building',
                  ),
                  const _DetailLine(
                    icon: Icons.person_outline,
                    text: 'Counselor: To be assigned',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: _YellowButton(
                label: 'Back to Appointments',
                onTap: onReturn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: _PaccText.cardTitle),
    );
  }
}

class _PaccTextField extends StatelessWidget {
  const _PaccTextField({
    required this.controller,
    required this.hint,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: _PaccText.input,
      decoration: _PaccDecor.input(hint),
      validator: validator,
    );
  }
}

class _PaccDropdown extends StatelessWidget {
  const _PaccDropdown({
    required this.value,
    required this.hint,
    required this.options,
    required this.onChanged,
  });

  final String? value;
  final String hint;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: options.contains(value) ? value : null,
      isExpanded: true,
      hint: Text(hint, style: _PaccText.inputHint),
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option,
            child: Text(option, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
      validator: (value) => value == null ? 'Required' : null,
      decoration: _PaccDecor.input(''),
    );
  }
}

class _RadioGroup extends StatelessWidget {
  const _RadioGroup({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: value,
      validator: (_) => value == null ? 'Required' : null,
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _PaccText.cardTitle),
            const SizedBox(height: 6),
            for (final option in options)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  onChanged(option);
                  field.didChange(option);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      _ChoiceCircle(selected: value == option),
                      const SizedBox(width: 10),
                      Expanded(child: Text(option, style: _PaccText.body)),
                    ],
                  ),
                ),
              ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  field.errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ChoiceCircle extends StatelessWidget {
  const _ChoiceCircle({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black87, width: 1.2),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: _PaccColors.sunButton,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

class _YellowButton extends StatelessWidget {
  const _YellowButton({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? _PaccColors.sunButton : const Color(0xFFD1C8AD),
      borderRadius: BorderRadius.circular(999),
      elevation: enabled ? 5 : 0,
      shadowColor: const Color(0x33000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallYellowButton extends StatelessWidget {
  const _SmallYellowButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFD45B),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: 34,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: _PaccText.smallButton),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, color: Colors.black),
          ),
        ),
      ),
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(child: Text(label, style: _PaccText.tinyBold)),
    );
  }
}

class _CalendarDayButton extends StatelessWidget {
  const _CalendarDayButton({
    required this.day,
    required this.selected,
    required this.suggested,
    required this.enabled,
    required this.onTap,
  });

  final int day;
  final bool selected;
  final bool suggested;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? const Color(0xFFE8E4DA)
        : selected
        ? _PaccColors.sunButton
        : suggested
        ? const Color(0xFFFFE58B)
        : const Color(0xFFC8C8CB);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Center(
          child: Text(
            '$day',
            style: _PaccText.tinyBold.copyWith(
              color: enabled ? Colors.black : const Color(0xFF9A9488),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.black),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: _PaccText.body)),
        ],
      ),
    );
  }
}

enum _PaccAppointmentTab { myAppointments, appointNew }

enum _PaccAppointmentStep { calendar, time, intake, review, confirmation }

class _PaccColors {
  const _PaccColors._();

  static const background = Color(0xFFFAF5E8);
  static const sun = Color(0xFFFFD447);
  static const sunButton = Color(0xFFFFB800);
}

class _PaccText {
  const _PaccText._();

  static const headerTitle = TextStyle(
    color: Color(0xFF111827),
    fontSize: 22,
    fontWeight: FontWeight.w800,
  );

  static const headerSubtitle = TextStyle(
    color: Color(0xFF4B5563),
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static const title = TextStyle(
    color: Colors.black,
    fontSize: 16,
    fontWeight: FontWeight.w900,
  );

  static const subtitle = TextStyle(
    color: Colors.black,
    fontSize: 15,
    fontWeight: FontWeight.w500,
  );

  static const monthTitle = TextStyle(
    color: Colors.black,
    fontSize: 16,
    fontWeight: FontWeight.w900,
  );

  static const confirmTitle = TextStyle(
    color: Colors.black,
    fontSize: 19,
    fontWeight: FontWeight.w900,
  );

  static const cardTitleLarge = TextStyle(
    color: Colors.black,
    fontSize: 16,
    fontWeight: FontWeight.w900,
  );

  static const cardTitle = TextStyle(
    color: Colors.black,
    fontSize: 13,
    fontWeight: FontWeight.w900,
  );

  static const body = TextStyle(
    color: Colors.black,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );

  static const muted = TextStyle(
    color: Color(0xFF918979),
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  static const tinyBold = TextStyle(
    color: Colors.black,
    fontSize: 11,
    fontWeight: FontWeight.w900,
  );

  static const smallButton = TextStyle(
    color: Colors.black,
    fontSize: 12,
    fontWeight: FontWeight.w900,
  );

  static const input = TextStyle(
    color: Colors.black,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  static const inputHint = TextStyle(
    color: Color(0xFF9A927F),
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );
}

class _PaccDecor {
  const _PaccDecor._();

  static BoxDecoration card({
    Color color = Colors.white,
    Color? borderColor,
    double radius = 12,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: borderColor == null ? null : Border.all(color: borderColor),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 12,
          offset: Offset(0, 6),
        ),
      ],
    );
  }

  static InputDecoration input(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: _PaccText.inputHint,
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFFFF4CC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _PaccColors.sunButton),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _PaccColors.sunButton),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _PaccColors.sunButton, width: 1.5),
      ),
    );
  }
}

String _formatMonth(DateTime date) {
  return '${_monthName(date.month)} ${date.year}';
}

String _formatWeekdayMonthDay(DateTime date) {
  return '${_weekdayName(date.weekday)}, ${_monthName(date.month)} ${date.day}';
}

String _formatFullDate(DateTime date) {
  return '${_weekdayName(date.weekday)}, ${_monthName(date.month)} ${date.day}, ${date.year}';
}

String _monthName(int month) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return months[month - 1];
}

String _weekdayName(int weekday) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return weekdays[weekday - 1];
}
