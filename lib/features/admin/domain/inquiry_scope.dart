import '../../../models/admin_inquiry_model.dart';
import '../../../models/profile_roles.dart';

/// Defensive client-side mirror of the Firestore inquiry and operational
/// status projection rules.
///
/// Raw `inquiries` are scoped exclusively to assigned active verified
/// counselors (`assigneeIds`) and the super-administrator. Operational
/// `portalStaff` receive ONLY sanitized `inquiry_statuses` projections scoped
/// by explicit `monitoringStaffIds` (never raw `inquiries`).
List<AdminInquiryModel> scopeInquiriesForRole(
  List<AdminInquiryModel> items, {
  required AccessRole role,
  required String? uid,
  required bool isSuperAdmin,
}) {
  if (isSuperAdmin) return items;
  if (uid == null) return const [];
  if (role == AccessRole.counselor) {
    return items
        .where(
          (item) =>
              !item.isOperationalProjection && item.assigneeIds.contains(uid),
        )
        .toList();
  }
  if (role == AccessRole.portalStaff) {
    return items
        .where(
          (item) =>
              item.isOperationalProjection &&
              item.monitoringStaffIds.contains(uid),
        )
        .toList();
  }
  return const [];
}
