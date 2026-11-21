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
      case 'normal':
      case 'healthy':
        return AssessmentStatusStyle(
          key == 'low'
              ? 'Low'
              : key == 'normal'
              ? 'Normal'
              : 'Healthy',
          AdminColors.greenFg,
          AdminColors.greenBg,
        );
      case 'supported':
      case 'generallysupported':
      case 'wellbeingsupported':
      case 'stable':
        return const AssessmentStatusStyle(
          'Supported',
          AdminColors.greenFg,
          AdminColors.greenBg,
        );
      case 'mostlysupported':
      case 'generallysteady':
      case 'mild':
        return AssessmentStatusStyle(
          key == 'mild' ? 'Mild' : 'Mostly supported',
          AdminColors.blueFg,
          AdminColors.blueBg,
        );
      case 'moderate':
        return const AssessmentStatusStyle(
          'Moderate',
          AdminColors.amberFg,
          AdminColors.amberBg,
        );
      case 'somestrain':
      case 'someareasneedattention':
      case 'needsattention':
      case 'watchful':
        return const AssessmentStatusStyle(
          'Some areas need attention',
          AdminColors.amberFg,
          AdminColors.amberBg,
        );
      case 'high':
        return const AssessmentStatusStyle(
          'High',
          AdminColors.redFg,
          AdminColors.redBg,
        );
      case 'veryhigh':
      case 'severe':
      case 'extremelysevere':
        return AssessmentStatusStyle(
          key == 'veryhigh'
              ? 'Very high'
              : key == 'severe'
              ? 'Severe'
              : 'Extremely severe',
          AdminColors.redFg,
          AdminColors.redBg,
        );
      case 'supportmayhelp':
      case 'elevated':
      case 'highsupport':
      case 'prioritysupport':
      case 'atrisk':
        return const AssessmentStatusStyle(
          'Support may help',
          AdminColors.redFg,
          AdminColors.redBg,
        );
      case 'completed':
      case 'submitted':
        return AssessmentStatusStyle(
          key == 'completed' ? 'Completed' : 'Submitted',
          AdminColors.violetFg,
          AdminColors.violetBg,
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
