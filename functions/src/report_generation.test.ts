import assert from "node:assert/strict";
import test from "node:test";
import {buildReportAnalytics, isReportableAppUser} from "./report_generation";

test("reports exclude portal accounts and expose percentages only", () => {
  const now = new Date("2026-09-10T00:00:00.000Z");
  const users = [
    {id: "s1", data: {accessRole: "appUser", populationRole: "student", department: "CAS", course: "BSIT", yearLevel: "1", lastActiveAt: "2026-09-09T00:00:00.000Z"}},
    {id: "s2", data: {accessRole: "appUser", populationRole: "student", department: "CAS", course: "BSIT", yearLevel: "2", lastActiveAt: "2026-01-01T00:00:00.000Z"}},
    {id: "t1", data: {accessRole: "appUser", populationRole: "teaching", department: "COE", lastActiveAt: "2026-09-01T00:00:00.000Z"}},
    {id: "admin", data: {accessRole: "admin", populationRole: "teaching", lastActiveAt: "2026-09-09T00:00:00.000Z"}},
    {id: "staff", data: {accessRole: "appUser", staffAccountStatus: "approved", populationRole: "nonTeaching"}},
  ];
  const appointments = [
    {userId: "s1", course: "BSIT", yearLevel: "1", scheduledAt: "2026-09-09T00:00:00.000Z"},
    {userId: "s2", course: "BSIT", yearLevel: "2", scheduledAt: "2026-09-08T00:00:00.000Z"},
    {userId: "t1", scheduledAt: "2026-09-01T00:00:00.000Z"},
    {userId: "admin", course: "Secret admin category", scheduledAt: "2026-09-09T00:00:00.000Z"},
  ];

  const report = buildReportAnalytics(users, appointments, now, {}, {
    schoolYear: "2026-2027",
    departments: ["CAS", "COE"],
    populations: {CAS: 3, COE: 3},
    configured: true,
    totalPopulation: 6,
    years: [],
  });
  assert.equal(report.users.overallActivePercentage, 66.7);
  assert.deepEqual(
    report.users.categories.map((item) => [item.key, item.populationPercentage, item.activePercentage]),
    [["student", 66.7, 50], ["teaching", 33.3, 100]],
  );
  assert.deepEqual(
    report.appointments.department.map((item) => [item.label, item.percentage]),
    [["CAS", 66.7], ["COE", 33.3]],
  );
  assert.ok(!JSON.stringify(report).includes("Secret admin category"));
  assert.ok(!Object.hasOwn(report.users, "total"));
});

test("department and population scopes return only selected report metrics", () => {
  const now = new Date("2026-09-10T00:00:00.000Z");
  const users = [
    {id: "n1", data: {accessRole: "appUser", populationRole: "student", department: "College of Nursing", course: "BSN", yearLevel: "1", lastActiveAt: "2026-09-09T00:00:00.000Z"}},
    {id: "n2", data: {accessRole: "appUser", populationRole: "student", department: "College of Nursing", course: "BSN", yearLevel: "2"}},
    {id: "e1", data: {accessRole: "appUser", populationRole: "teaching", department: "College of Engineering", course: "BSEE", lastActiveAt: "2026-09-08T00:00:00.000Z"}},
  ];
  const appointments = [
    {userId: "n1", scheduledAt: "2026-09-09T00:00:00.000Z"},
    {userId: "n2", scheduledAt: "2026-09-08T00:00:00.000Z"},
    {userId: "e1", scheduledAt: "2026-09-08T00:00:00.000Z"},
  ];

  const report = buildReportAnalytics(users, appointments, now, {
    userCategory: "student",
    appointmentDepartment: "college of nursing",
  }, {
    schoolYear: "2026-2027",
    departments: ["College of Nursing", "College of Engineering"],
    populations: {"College of Nursing": 2, "College of Engineering": 1},
    configured: true,
    totalPopulation: 3,
    years: [],
  });

  assert.equal(report.users.scopeKey, "student");
  assert.equal(report.users.overallActivePercentage, 50);
  assert.deepEqual(report.users.categories.map((item) => item.key), ["student"]);
  assert.deepEqual(
    report.appointments.department.map((item) => [item.label, item.percentage]),
    [["College of Nursing", 100]],
  );
  assert.deepEqual(
    report.appointments.course.map((item) => [item.label, item.percentage]),
    [["BSN", 100]],
  );
  assert.ok(!JSON.stringify(report.appointments.course).includes("BSEE"));
});

test("combined filters intersect userCategory, college, program, and Manila date bounds", () => {
  const now = new Date("2026-09-10T00:00:00.000Z");
  const users = [
    {id: "u1", data: {accessRole: "appUser", populationRole: "student", department: "CAS", course: "BA Psychology", lastActiveAt: "2026-09-05T08:00:00+08:00"}},
    {id: "u2", data: {accessRole: "appUser", populationRole: "student", department: "CAS", course: "BA English", lastActiveAt: "2026-09-05T08:00:00+08:00"}},
    {id: "u3", data: {accessRole: "appUser", populationRole: "teaching", department: "CAS", course: "BA Psychology", lastActiveAt: "2026-09-05T08:00:00+08:00"}},
  ];
  const appointments = [
    {userId: "u1", status: "completed", scheduledAt: "2026-09-05T08:00:00+08:00"},
    {userId: "u2", status: "completed", scheduledAt: "2026-09-05T08:00:00+08:00"},
    {userId: "u3", status: "completed", scheduledAt: "2026-09-05T08:00:00+08:00"},
  ];

  const filtered = buildReportAnalytics(
    users,
    appointments,
    now,
    {
      userCategory: "student",
      appointmentDepartment: "cas",
      program: "ba psychology",
      periodLabel: "1st semester",
      startDate: "2026-06-01T00:00:00+08:00",
      endDate: "2026-12-01T00:00:00+08:00",
    },
    {
      schoolYear: "2026-2027",
      departments: ["CAS"],
      populations: {CAS: 10},
      configured: true,
      totalPopulation: 10,
      years: [],
    },
  );

  assert.equal(filtered.filters.periodLabel, "1st semester");
  assert.equal(filtered.filters.programKey, "ba psychology");
  assert.equal(filtered.appointments.totalAppointments, 1);
  assert.equal(filtered.appointments.uniqueStudentsServed, 1);
  assert.equal(filtered.users.overallActivePercentage, 100);
});

test("isolates 2026-2027 vs 2028-2029 academic years, scopes whole-year activity, and excludes undated records", () => {
  // Now sits inside 2026-2027 (rolling 30d covers Oct 17..Nov 16 2026).
  const now = new Date("2026-11-16T04:00:00.000Z");
  const users = [
    // Active in Nov 2026 (2026-2027): must NOT count in 2028-2029.
    {id: "s1", data: {accessRole: "appUser", populationRole: "student", department: "CAS", lastActiveAt: "2026-11-15T04:00:00.000Z"}},
    // Active earlier in 2026-2027 (Aug 2026, >30d ago): counted in whole-year 2026-2027, NOT 2028-2029.
    {id: "s2", data: {accessRole: "appUser", populationRole: "student", department: "CAS", activeDateKeys: ["2026-08-15"]}},
    // Historical user active only in 2025-2026.
    {id: "s3", data: {accessRole: "appUser", populationRole: "student", department: "CAS", activeDateKeys: ["2025-09-10"]}},
    // Future cohort active only in 2028-2029.
    {id: "s4", data: {accessRole: "appUser", populationRole: "student", department: "CAS", activeDateKeys: ["2028-09-12"]}},
    ...Array.from({length: 6}, (_, idx) => ({
      id: `s-extra-${idx}`,
      data: {accessRole: "appUser", populationRole: "student", department: "CAS"},
    })),
  ];

  const appointments = [
    // Explicit 2026-2027 historical academicYearId record (even without timestamp).
    {userId: "s1", status: "completed", academicYearId: "2026-2027"},
    // Timestamped in 2026-2027 without academicYearId.
    {userId: "s2", status: "completed", scheduledAt: "2026-08-15T04:00:00.000Z"},
    // Timestamped in 2025-2026.
    {userId: "s3", status: "completed", academicYearId: "2025-2026", scheduledAt: "2025-09-10T04:00:00.000Z"},
    // Timestamped in 2028-2029.
    {userId: "s4", status: "completed", academicYearId: "2028-2029", scheduledAt: "2028-09-12T04:00:00.000Z"},
    // Undated record with no academicYearId: must NEVER appear in 2026-2027 or 2028-2029.
    {userId: "s1", status: "completed"},
  ];

  const moodEntries = [
    ...users.map((u) => ({
      userId: u.id,
      level: 5,
      label: "Great",
      occurredAt: "2026-09-15T04:00:00.000Z",
    })),
    {
      userId: "s4",
      level: 2,
      label: "Sad",
      occurredAt: "2028-09-12T04:00:00.000Z",
    },
  ];

  const report2627 = buildReportAnalytics(
    users,
    appointments,
    now,
    {emotionalSource: "mood"},
    {
      schoolYear: "2026-2027",
      startDate: "2026-06-01",
      endDate: "2027-05-31",
      departments: ["CAS"],
      populations: {CAS: 10},
      configured: true,
      totalPopulation: 10,
      years: [],
    },
    {moodEntries},
  );

  const report2829 = buildReportAnalytics(
    users,
    appointments,
    now,
    {emotionalSource: "mood"},
    {
      schoolYear: "2028-2029",
      startDate: "2028-06-01",
      endDate: "2029-05-31",
      departments: ["CAS"],
      populations: {CAS: 20},
      configured: true,
      totalPopulation: 20,
      years: [],
    },
    {moodEntries},
  );

  // 2026-2027 includes s1 (Nov 2026) and s2 (Aug 2026) -> 2 of 10 = 20%; 2 appointments (undated excluded).
  assert.equal(report2627.users.overallActivePercentage, 20);
  assert.equal(report2627.appointments.totalAppointments, 2);
  assert.equal(report2627.emotionalActivity.status, "ready");
  assert.equal(report2627.emotionalActivity.suppressed, false);

  // 2028-2029 includes only s4 -> 1 of 10 = 10%; 1 appointment (undated & 2026-2027 excluded).
  assert.equal(report2829.users.overallActivePercentage, 10);
  assert.equal(report2829.appointments.totalAppointments, 1);
  // 2028-2029 has only 1 mood participant -> preserves n < 10 privacy suppression.
  assert.equal(report2829.emotionalActivity.status, "suppressed");
  assert.equal(report2829.emotionalActivity.suppressed, true);
  assert.notEqual(report2627.users.overallActivePercentage, report2829.users.overallActivePercentage);
  assert.notEqual(report2627.appointments.totalAppointments, report2829.appointments.totalAppointments);
});

test("department population lookup is case-insensitive and unconfigured population omits department rates", () => {
  const now = new Date("2026-09-10T00:00:00.000Z");
  const users = [
    {
      id: "n1",
      data: {
        accessRole: "appUser",
        populationRole: "student",
        department: "college of nursing",
        course: "BSN",
        yearLevel: "1st Year",
      },
    },
  ];
  const appointments = [
    {
      userId: "n1",
      department: "college of nursing",
      course: "BSN",
      yearLevel: "1st Year",
      scheduledAt: "2026-09-09T00:00:00.000Z",
    },
  ];

  const configuredReport = buildReportAnalytics(users, appointments, now, {}, {
    schoolYear: "2026-2027",
    departments: ["College of Nursing"],
    populations: {"College of Nursing": 10},
    configured: true,
    totalPopulation: 10,
    years: [],
  });
  assert.equal(configuredReport.appointments.department.length, 1);
  assert.equal(configuredReport.appointments.department[0].percentage, 10);

  const unconfiguredReport = buildReportAnalytics(users, appointments, now, {}, {
    schoolYear: "2026-2027",
    departments: ["College of Nursing"],
    populations: {},
    configured: false,
    totalPopulation: 0,
    years: [],
  });
  assert.deepEqual(unconfiguredReport.appointments.department, []);
  assert.deepEqual(unconfiguredReport.appointments.course, []);
  assert.deepEqual(unconfiguredReport.appointments.yearLevel, []);
});

test("includes legacy appUsers without accessRole while excluding legacy portalStaff", () => {
  const now = new Date("2026-09-10T00:00:00.000Z");
  const users = [
    {
      id: "leg-1",
      data: {
        role: "student",
        populationRole: "student",
        department: "CAS",
        lastActiveAt: "2026-09-09T00:00:00.000Z",
      },
    },
    {
      id: "leg-staff",
      data: {
        role: "portalStaff",
        lastActiveAt: "2026-09-09T00:00:00.000Z",
      },
    },
  ];
  const appointments = [
    {userId: "leg-1", department: "CAS", course: "BSIT", yearLevel: "1", scheduledAt: "2026-09-09T00:00:00.000Z"},
    {userId: "leg-staff", department: "CAS", course: "Secret staff", scheduledAt: "2026-09-09T00:00:00.000Z"},
  ];

  const report = buildReportAnalytics(users, appointments, now, {}, {
    schoolYear: "2026-2027",
    departments: ["CAS"],
    populations: {CAS: 10},
    configured: true,
    totalPopulation: 10,
    years: [],
  });

  assert.equal(report.users.overallActivePercentage, 100);
  assert.deepEqual(report.users.categories.map((c) => c.key), ["student"]);
  assert.equal(report.appointments.totalAppointments, 1);
  assert.ok(!JSON.stringify(report).includes("Secret staff"));
});

test("program filter scopes appointments.department rates to matching program only", () => {
  const now = new Date("2026-09-10T00:00:00.000Z");
  const users = [
    ...Array.from({length: 5}, (_, i) => ({
      id: `bsn-${i}`,
      data: {
        accessRole: "appUser",
        populationRole: "student",
        department: "College of Nursing",
        course: "BSN",
      },
    })),
    ...Array.from({length: 15}, (_, i) => ({
      id: `mid-${i}`,
      data: {
        accessRole: "appUser",
        populationRole: "student",
        department: "College of Nursing",
        course: "Midwifery",
      },
    })),
  ];
  const appointments = [
    ...Array.from({length: 5}, (_, i) => ({
      userId: `bsn-${i}`,
      department: "College of Nursing",
      course: "BSN",
      scheduledAt: "2026-09-09T00:00:00.000Z",
    })),
    ...Array.from({length: 15}, (_, i) => ({
      userId: `mid-${i}`,
      department: "College of Nursing",
      course: "Midwifery",
      scheduledAt: "2026-09-09T00:00:00.000Z",
    })),
  ];

  const report = buildReportAnalytics(
    users,
    appointments,
    now,
    {appointmentDepartment: "college of nursing", program: "bsn"},
    {
      schoolYear: "2026-2027",
      departments: ["College of Nursing"],
      populations: {"College of Nursing": 100},
      configured: true,
      totalPopulation: 100,
      years: [],
    },
  );

  assert.equal(report.appointments.totalAppointments, 5);
  assert.equal(report.appointments.appointmentRate, 5);
  assert.deepEqual(report.appointments.department, [
    {key: "college of nursing", label: "College of Nursing", percentage: 5},
  ]);
});

test("college alias and collegeId filters resolve appointments.department and filters.programOptions", () => {
  const now = new Date("2026-09-10T00:00:00.000Z");
  const collegeNameById = new Map([["con-id", "College of Nursing"]]);
  const courseNameById = new Map([["bsn-id", "BS Nursing"]]);
  const users = Array.from({length: 6}, (_, i) => ({
    id: `n-${i}`,
    data: {
      accessRole: "appUser",
      populationRole: "student",
      verificationStatus: "verified",
      collegeId: "con-id",
      department: "CON",
      course: "BS Nursing",
    },
  }));
  const appointments = Array.from({length: 6}, (_, i) => ({
    userId: `n-${i}`,
    collegeId: "con-id",
    department: "CON",
    course: "BS Nursing",
    scheduledAt: "2026-09-09T00:00:00.000Z",
  }));
  const population = {
    schoolYear: "2026-2027",
    departments: ["College of Nursing"],
    populations: {"College of Nursing": 100},
    configured: true,
    totalPopulation: 100,
    years: [],
  };
  const emotionalInput = {
    collegeNameById,
    courseNameById,
    programOptionsByCollege: {
      "college of nursing": [{key: "bs nursing", label: "BS Nursing"}],
    },
  };

  const byCanonical = buildReportAnalytics(
    users,
    appointments,
    now,
    {appointmentDepartment: "college of nursing"},
    population,
    emotionalInput,
  );
  assert.deepEqual(byCanonical.appointments.department, [
    {key: "college of nursing", label: "College of Nursing", percentage: 6},
  ]);
  assert.deepEqual(byCanonical.filters.programOptions, [
    {key: "bs nursing", label: "BS Nursing"},
  ]);

  const byId = buildReportAnalytics(
    users,
    appointments,
    now,
    {appointmentDepartment: "con-id"},
    population,
    emotionalInput,
  );
  assert.deepEqual(byId.appointments.department, [
    {key: "college of nursing", label: "College of Nursing", percentage: 6},
  ]);
  assert.deepEqual(byId.filters.programOptions, [
    {key: "bs nursing", label: "BS Nursing"},
  ]);
});

test("isReportableAppUser normalizes staff/admin role tokens and rejects conflicting legacy role", () => {
  assert.equal(isReportableAppUser({role: "portal staff"}), false);
  assert.equal(isReportableAppUser({role: "portal-staff"}), false);
  assert.equal(isReportableAppUser({role: "super_admin"}), false);
  assert.equal(isReportableAppUser({accessRole: "appUser", role: "admin"}), false);
  assert.equal(isReportableAppUser({role: "student"}), true);
  assert.equal(isReportableAppUser({accessRole: "appUser"}), true);
});
