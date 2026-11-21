import 'package:flutter/material.dart';

import '../domain/admin_status_presentation.dart';

/// Accessible pill badge displaying semantic color, icon, and text label.
class AdminStatusBadge extends StatelessWidget {
  const AdminStatusBadge({
    super.key,
    required this.presentation,
    this.compact = false,
  });

  factory AdminStatusBadge.fromStatus({
    Key? key,
    required AdminStatusDomain domain,
    required String? status,
    String? labelOverride,
    bool compact = false,
  }) => AdminStatusBadge(
    key: key,
    presentation: resolveAdminStatus(
      domain,
      status,
      labelOverride: labelOverride,
    ),
    compact: compact,
  );

  final AdminStatusPresentation presentation;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    label: presentation.label,
    child: Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: presentation.backgroundColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: presentation.borderColor.withValues(alpha: 0.65),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            presentation.icon,
            size: compact ? 13 : 14,
            color: presentation.foregroundColor,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              presentation.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: presentation.foregroundColor,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 11.5 : 12,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
