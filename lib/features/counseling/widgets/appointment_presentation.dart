import 'package:flutter/material.dart';

import '../../../models/appointment_model.dart';

/// Presentation only; lifecycle values and eligibility remain in the model.
abstract final class AppointmentVisuals {
  static const background = Color(0xFFF7F8F4);
  static const ink = Color(0xFF1D343C);
  static const muted = Color(0xFF73878E);
  static const teal = Color(0xFF285D59);
  static const gold = Color(0xFFF8BF3C);
  static const line = Color(0xFFE5EAE5);
  static const title = TextStyle(
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: ink,
    letterSpacing: -.7,
  );
  static const section = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w800,
    color: ink,
  );
  static const body = TextStyle(fontSize: 14, height: 1.5, color: muted);
  static BoxDecoration get card => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: line),
    boxShadow: const [
      BoxShadow(color: Color(0x04000000), offset: Offset(0, 3), blurRadius: 8),
    ],
  );
  static ButtonStyle get primary => FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(52),
    backgroundColor: gold,
    foregroundColor: ink,
    textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 14, fontWeight: FontWeight.w800),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
  );
}

String appointmentStatusLabel(AppointmentStatus status) => switch (status) {
  AppointmentStatus.requested ||
  AppointmentStatus.legacyRequested => 'Awaiting confirmation',
  AppointmentStatus.confirmed => 'Confirmed',
  AppointmentStatus.rescheduleProposed => 'Schedule Update Pending',
  AppointmentStatus.completed => 'Completed',
  AppointmentStatus.cancelled => 'Cancelled',
  AppointmentStatus.declined => 'Request Declined',
  AppointmentStatus.expired => 'Request Expired',
  AppointmentStatus.noShow => 'Did Not Attend',
  AppointmentStatus.unknown => 'Status unavailable',
};

class AppointmentStatusBadge extends StatelessWidget {
  const AppointmentStatusBadge({super.key, required this.status});
  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      AppointmentStatus.requested || AppointmentStatus.legacyRequested => (
        const Color(0xFFFFF3D7),
        const Color(0xFF91600B),
      ),
      AppointmentStatus.confirmed || AppointmentStatus.completed => (
        const Color(0xFFE7F5EF),
        const Color(0xFF187557),
      ),
      AppointmentStatus.cancelled || AppointmentStatus.declined => (
        const Color(0xFFFBECE9),
        const Color(0xFF9B4238),
      ),
      _ => (const Color(0xFFEEF1F3), const Color(0xFF526B79)),
    };
    return Semantics(
      key: ValueKey('appointment-status-${status.name}'),
      liveRegion: true,
      label: 'Appointment status: ${appointmentStatusLabel(status)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: foreground.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == AppointmentStatus.requested || status == AppointmentStatus.legacyRequested || status == AppointmentStatus.rescheduleProposed)
              const AppointmentProcessingIndicator()
            else Icon(status == AppointmentStatus.confirmed || status == AppointmentStatus.completed ? Icons.check_circle : Icons.info, size: 17, color: foreground),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                appointmentStatusLabel(status),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppointmentPageHeader extends StatelessWidget {
  const AppointmentPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.trailing,
    this.backTooltip = 'Back',
  });
  final String title, subtitle;
  final String backTooltip;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
    decoration: const BoxDecoration(
      color: Color(0xFFFAFCF9),
      border: Border(bottom: BorderSide(color: AppointmentVisuals.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (onBack != null) ...[
          IconButton(
            tooltip: backTooltip,
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left, color: AppointmentVisuals.ink),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PACC COUNSELING',
                style: TextStyle(
                  color: Color(0xFFA17720),
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(title, style: AppointmentVisuals.title),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: AppointmentVisuals.body.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class AppointmentDetailRow extends StatelessWidget {
  const AppointmentDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F6F2),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF658D81)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppointmentVisuals.body.copyWith(fontSize: 11),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: AppointmentVisuals.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A slow pulse, rather than flashing, for requests still being processed.
class AppointmentProcessingIndicator extends StatefulWidget {
  const AppointmentProcessingIndicator({super.key});
  @override
  State<AppointmentProcessingIndicator> createState() => _AppointmentProcessingIndicatorState();
}

class _AppointmentProcessingIndicatorState extends State<AppointmentProcessingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) { _controller.stop(); }
    else { _controller.repeat(reverse: true); }
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final dot = Container(
      key: reduced ? const ValueKey('processing-indicator-static') : null,
      width: 16, height: 16,
      decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFF8BF3C), border: Border.all(color: const Color(0xFF91600B), width: 2), boxShadow: const [BoxShadow(color: Color(0x40F8BF3C), blurRadius: 7, spreadRadius: 2)]),
    );
    return Semantics(label: 'Awaiting PACC review', child: reduced ? dot : FadeTransition(opacity: Tween<double>(begin: .45, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)), child: dot));
  }
}
