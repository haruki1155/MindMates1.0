enum PopulationRole {
  student,
  teaching,
  nonTeaching;

  String get storedValue => name;

  String get label => switch (this) {
    PopulationRole.student => 'Student',
    PopulationRole.teaching => 'Teaching',
    PopulationRole.nonTeaching => 'Non-Teaching',
  };

  static PopulationRole? parse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase().replaceAll(
      RegExp(r'[\s_-]+'),
      '',
    );
    return switch (normalized) {
      'student' => PopulationRole.student,
      'faculty' || 'teaching' || 'teachingpersonnel' => PopulationRole.teaching,
      'staff' ||
      'nonteaching' ||
      'nonteachingpersonnel' => PopulationRole.nonTeaching,
      _ => null,
    };
  }
}

enum AccessRole {
  appUser,
  portalStaff,
  counselor,
  admin;

  String get storedValue => name;
  bool get canUsePortal => this != AccessRole.appUser;
  bool get canReviewProfiles => canUsePortal;
  bool get canAccessClinicalData =>
      this == AccessRole.counselor || this == AccessRole.admin;
  bool get canManageAccess => this == AccessRole.admin;

  static AccessRole parse(Object? value, {Object? legacyRole}) {
    final normalized = value?.toString().trim().toLowerCase().replaceAll(
      RegExp(r'[\s_-]+'),
      '',
    );
    // Keep older staff records compatible with the role-specific portal.
    // Earlier staging data used values such as `staff` and `PAACC Staff`
    // before `portalStaff` became the canonical value.
    if (normalized == 'portalstaff' ||
        normalized == 'staff' ||
        normalized == 'paaccstaff' ||
        normalized == 'paccstaff') {
      return AccessRole.portalStaff;
    }
    if (normalized == 'counselor' || normalized == 'counsellor') {
      return AccessRole.counselor;
    }
    if (normalized == 'admin') return AccessRole.admin;
    final legacy = legacyRole?.toString().trim().toLowerCase();
    if (legacy == 'admin') return AccessRole.admin;
    if (legacy == 'counselor' || legacy == 'counsellor') {
      return AccessRole.counselor;
    }
    return AccessRole.appUser;
  }
}

enum VerificationStatus {
  pending,
  verified,
  rejected,
  needsReview;

  String get storedValue => name;
  String get label => switch (this) {
    VerificationStatus.pending => 'Pending verification',
    VerificationStatus.verified => 'Verified',
    VerificationStatus.rejected => 'Verification rejected',
    VerificationStatus.needsReview => 'Needs review',
  };

  static VerificationStatus parse(Object? value, {bool legacy = false}) {
    final normalized = value?.toString().trim().toLowerCase().replaceAll(
      RegExp(r'[\s_-]+'),
      '',
    );
    return switch (normalized) {
      'pending' => VerificationStatus.pending,
      'verified' => VerificationStatus.verified,
      'rejected' => VerificationStatus.rejected,
      'needsreview' => VerificationStatus.needsReview,
      _ => legacy ? VerificationStatus.needsReview : VerificationStatus.pending,
    };
  }
}
