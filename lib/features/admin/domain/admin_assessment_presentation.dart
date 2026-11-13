import 'package:flutter/material.dart';

import '../../../repositories/admin_portal_repository.dart';
import '../theme/admin_theme.dart';

enum AssessmentView { quick, full }

/// This is presentation logic only; it never calculates a mental-health score.
class AssessmentStatusStyle {
  const AssessmentStatusStyle(this.label, this.foreground, this.background);

  final String label;
  final Color foreground;
  final Color background;

  static AssessmentStatusStyle fromStored(String? raw) {
    final value = (raw ?? '').trim();
    final key = value.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    switch (key) {
      case 'low':
        return const AssessmentStatusStyle(
          'Low',
          Color(0xFF226B4D),
          Color(0xFFE1F3E8),
        );
      case 'supported':
      case 'generallysupported':
      case 'wellbeingsupported':
      case 'stable':
        return const AssessmentStatusStyle(
          'Supported',
          Color(0xFF226B4D),
          Color(0xFFE1F3E8),
        );
      case 'mostlysupported':
      case 'generallysteady':
        return const AssessmentStatusStyle(
          'Mostly supported',
          Color(0xFF245D86),
          Color(0xFFE2EFF9),
        );
      case 'moderate':
        return const AssessmentStatusStyle(
          'Moderate',
          Color(0xFF815314),
          Color(0xFFFFEED1),
        );
      case 'somestrain':
      case 'someareasneedattention':
      case 'watchful':
        return const AssessmentStatusStyle(
          'Some areas need attention',
          Color(0xFF815314),
          Color(0xFFFFEED1),
        );
      case 'high':
        return const AssessmentStatusStyle(
          'High',
          Color(0xFF9A3B29),
          Color(0xFFFFE7DE),
        );
      case 'veryhigh':
        return const AssessmentStatusStyle(
          'Very high',
          Color(0xFF9A3B29),
          Color(0xFFFFE7DE),
        );
      case 'supportmayhelp':
      case 'elevated':
      case 'highsupport':
        return const AssessmentStatusStyle(
          'Support may help',
          Color(0xFF9A3B29),
          Color(0xFFFFE7DE),
        );
      case 'insufficientresponses':
      case 'resultunavailable':
      case '':
        return const AssessmentStatusStyle(
          'Result unavailable',
          AdminColors.muted,
          AdminColors.surfaceMuted,
        );
      default:
        return AssessmentStatusStyle(
          value.replaceAll('_', ' '),
          AdminColors.muted,
          AdminColors.surfaceMuted,
        );
    }
  }
}

class AssessmentParticipantInfo {
  const AssessmentParticipantInfo({
    required this.userId,
    required this.name,
    required this.role,
    required this.college,
  });

  final String userId;
  final String name;
  final String role;
  final String college;

  factory AssessmentParticipantInfo.fromJson(Map<String, dynamic> raw) =>
      AssessmentParticipantInfo(
        userId: (raw['userId'] ?? '').toString(),
        name: _nonempty(raw['name'], 'Name unavailable'),
        role: _nonempty(raw['role'], 'Unknown'),
        college: _nonempty(raw['college'], 'Unassigned'),
      );

  static String _nonempty(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}

class AssessmentParticipantCounts {
  const AssessmentParticipantCounts(
    this.studentsByCollege,
    this.personnelByRole,
  );

  final Map<String, int> studentsByCollege;
  final Map<String, int> personnelByRole;

  /// Counts *participants*, not submissions; each user is counted once.
  static AssessmentParticipantCounts fromRecords(
    Iterable<AdminAssessmentRecord> records,
    Map<String, AssessmentParticipantInfo> participants,
  ) {
    final users = <String>{};
    final students = <String, int>{};
    final personnel = <String, int>{};
    for (final record in records) {
      final uid = record.userId.trim();
      if (uid.isEmpty || !users.add(uid)) continue;
      final person = participants[uid];
      if (person == null) continue; // Missing profiles never get guessed roles.
      final role = person.role.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
      if (role == 'student') {
        final college = person.college.trim().isEmpty
            ? 'Unassigned'
            : person.college;
        students[college] = (students[college] ?? 0) + 1;
      } else {
        final label = switch (role) {
          'teaching' || 'faculty' || 'teachingpersonnel' => 'Teaching',
          'nonteaching' || 'staff' || 'nonteachingpersonnel' => 'Non-Teaching',
          _ => 'Other / Unknown',
        };
        personnel[label] = (personnel[label] ?? 0) + 1;
      }
    }
    return AssessmentParticipantCounts(students, personnel);
  }
}

bool matchesAssessmentView(AdminAssessmentRecord record, AssessmentView view) =>
    view == AssessmentView.quick
    ? record.isQuickAssessment
    : record.isMainAssessment;
