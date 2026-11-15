import '../../../models/admin_inquiry_model.dart';
import '../../../models/profile_roles.dart';

/// Defensive client-side mirror of the Firestore inquiry rules.
///
/// Inquiries are routed server-side to the staff and counselors assigned to
/// the student's college (`assigneeIds`). Only those assignees and the
/// configured super-administrator may see an inquiry; the rules enforce this,
/// and the repository already queries with `assigneeIds array-contains uid`.
/// This filter only guarantees the UI never shows anything else.
List<AdminInquiryModel> scopeInquiriesForRole(
  List<AdminInquiryModel> items, {
  required AccessRole role,
  required String? uid,
  required bool isSuperAdmin,
}) {
  if (isSuperAdmin) return items;
  if (uid == null ||
      (role != AccessRole.counselor && role != AccessRole.portalStaff)) {
    return const [];
  }
  return items.where((item) => item.assigneeIds.contains(uid)).toList();
}
