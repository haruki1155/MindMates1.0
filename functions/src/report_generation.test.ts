import assert from "node:assert/strict";
import test from "node:test";
import {buildReportAnalytics} from "./report_generation";

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
    {userId: "s1", course: "BSIT", yearLevel: "1"},
    {userId: "s2", course: "BSIT", yearLevel: "2"},
    {userId: "t1"},
    {userId: "admin", course: "Secret admin category"},
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
    {userId: "n1"},
    {userId: "n2"},
    {userId: "e1"},
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
