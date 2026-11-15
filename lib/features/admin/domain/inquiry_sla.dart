import '../../../models/admin_inquiry_model.dart';

/// Response target options PACC may choose from (hours).
const inquirySlaHourOptions = [24, 48, 72];

/// The configured response target and the overdue projection derived from it.
///
/// This is a view over inquiries the super-administrator can already read;
/// it grants no access. Policy: an inquiry is overdue when it is not
/// resolved, has no authored reply yet, and the target has elapsed since it
/// was submitted (exactly at the deadline counts). An acknowledgement receipt
/// is not a reply. With no target configured nothing is flagged.
class InquirySla {
  const InquirySla({required this.hours});

  /// Null when the super-administrator has not chosen a target yet.
  final int? hours;

  bool get isConfigured => hours != null;

  factory InquirySla.fromJson(Map<String, dynamic>? json) {
    final value = json?['hours'];
    final hours = value is num ? value.toInt() : null;
    return InquirySla(
      hours: hours != null && inquirySlaHourOptions.contains(hours)
          ? hours
          : null,
    );
  }

  DateTime? deadlineFor(AdminInquiryModel inquiry) =>
      hours == null ? null : inquiry.createdAt.add(Duration(hours: hours!));

  bool isOverdue(AdminInquiryModel inquiry, DateTime now) {
    final deadline = deadlineFor(inquiry);
    if (deadline == null) return false;
    if (inquiry.status == InquiryStatus.resolved) return false;
    if (inquiry.firstResponseAt != null) return false;
    return !now.isBefore(deadline);
  }

  Duration ageOf(AdminInquiryModel inquiry, DateTime now) =>
      now.difference(inquiry.createdAt);

  /// Overdue inquiries, oldest first.
  List<AdminInquiryModel> overdue(
    Iterable<AdminInquiryModel> inquiries,
    DateTime now,
  ) =>
      inquiries.where((inquiry) => isOverdue(inquiry, now)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
}
