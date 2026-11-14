import '../../../models/admin_inquiry_model.dart';
import '../../../models/profile_roles.dart';

/// Which inquiries a signed-in portal user should see.
///
/// No server component assigns `assignedStaffId` on inquiries yet, so a
/// counselor must see the shared unassigned pool plus anything explicitly
/// assigned to them. Hiding the unassigned pool behind an equality filter on
/// a never-written field made every counselor inbox look empty while the
/// administrator view showed the same records. Firestore rules already permit
/// approved portal accounts to read inquiries; this only narrows the UI.
List<AdminInquiryModel> scopeInquiriesForRole(
  List<AdminInquiryModel> items, {
  required AccessRole role,
  required String? uid,
}) {
  if (role != AccessRole.counselor) return items;
  return items
      .where(
        (item) =>
            item.assignedStaffId == null ||
            (uid != null && item.assignedStaffId == uid),
      )
      .toList();
}
