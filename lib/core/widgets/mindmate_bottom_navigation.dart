import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../routes/route_names.dart';

enum MindMateNavDestination {
  home,
  services,
  appointments,
  secretChat,
  message,
}

class MindMateBottomNavigation extends StatelessWidget {
  const MindMateBottomNavigation({super.key, required this.active});

  final MindMateNavDestination? active;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 68,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A111827),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            _item(
              context,
              MindMateNavDestination.home,
              Icons.home_outlined,
              'Home',
            ),
            _item(
              context,
              MindMateNavDestination.services,
              PhosphorIcons.briefcase(PhosphorIconsStyle.regular),
              'Services',
            ),
            _item(
              context,
              MindMateNavDestination.appointments,
              Icons.event_available_outlined,
              'Appointment',
            ),
            _item(
              context,
              MindMateNavDestination.secretChat,
              Icons.forum_outlined,
              'Secret Chat',
            ),
            _item(
              context,
              MindMateNavDestination.message,
              Icons.chat_bubble_outline,
              'Message',
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    MindMateNavDestination destination,
    IconData icon,
    String label,
  ) {
    final selected = active == destination;
    return Expanded(
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: selected ? null : () => _navigate(context, destination),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: selected ? 36 : 30,
                  height: selected ? 34 : 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFFFD75C)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 20, color: const Color(0xFF111827)),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigate(BuildContext context, MindMateNavDestination destination) {
    final route = switch (destination) {
      MindMateNavDestination.home ||
      MindMateNavDestination.appointments => RouteNames.home,
      MindMateNavDestination.services => RouteNames.services,
      MindMateNavDestination.secretChat => RouteNames.secretChat,
      MindMateNavDestination.message => RouteNames.mindAid,
    };
    Navigator.of(context).pushNamedAndRemoveUntil(
      route,
      (route) => false,
      arguments: destination == MindMateNavDestination.appointments,
    );
  }
}
