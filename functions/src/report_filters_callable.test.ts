import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import "./index";
import {getReportAnalytics} from "./report_generation";

const emulated = Boolean(
  process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST,
);
const prefix = `rf-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const db = getFirestore();

type Callable = {
  run: (r: {auth?: {uid: string}; data?: Record<string, unknown>}) => Promise<{
    report: {
      filters: {
        schoolYear: string;
        periodLabel: string;
        userCategory: string;
        collegeKey: string;
        collegeLabel: string;
        programKey: string;
        programLabel: string;
        programOptions: Array<{key: string; label: string}>;
        programOptionsByCollege: Record<string, Array<{key: string; label: string}>>;
      };
      users: {overallActivePercentage: number; categories: Array<{key: string}>};
      appointments: {
        totalAppointments: number;
        uniqueStudentsServed: number;
        course: Array<{key: string; label: string; percentage: number}>;
      };
      emotionalActivity: {
        status: string;
        suppressed: boolean;
        valenceBreakdown: Array<{key: string; percentage: number | null; suppressed: boolean}>;
      };
    };
  }>;
};

const fetchReport = getReportAnalytics as unknown as Callable;

const collegeAId = `${prefix}-cas`;
const collegeBId = `${prefix}-coe`;
const collegeAName = `${prefix} College of Computing`;
const collegeBName = `${prefix} College of Engineering`;
const progA1 = `${prefix} BS Information Technology`;
const progA2 = `${prefix} BS Computer Science`;
const progB1 = `${prefix} BS Civil Engineering`;

const accounts: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  admin: {verified: true, profile: {accessRole: "admin", accountStatus: "active"}},
  "counselor-a": {
    verified: true,
    profile: {
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "active",
      assignedCollegeIds: [collegeAId],
    },
  },
  staff: {
    verified: true,
    profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active"},
  },
};

async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (e: unknown) => e instanceof HttpsError && e.code === code);
}

before(async () => {
  if (!emulated) return;
  await Promise.all([
    db.doc(`colleges/${collegeAId}`).set({name: collegeAName, code: "CCS", active: true}),
    db.doc(`colleges/${collegeBId}`).set({name: collegeBName, code: "COE", active: true}),
    db.doc(`courses/${prefix}-c-a1`).set({
      name: progA1,
      code: "BSIT",
      collegeId: collegeAId,
      active: true,
    }),
    db.doc(`courses/${prefix}-c-a2`).set({
      name: progA2,
      code: "BSCS",
      collegeId: collegeAId,
      active: true,
    }),
    db.doc(`courses/${prefix}-c-b1`).set({
      name: progB1,
      code: "BSCE",
      collegeId: collegeBId,
      active: true,
    }),
    db.doc("counseling_population/2037-2038").set({
      schoolYear: "2037-2038",
      startDate: "2037-06-01",
      endDate: "2038-05-31",
      status: "current",
      populations: {
        [collegeAName]: 100,
        [collegeBName]: 100,
      },
    }),
  ]);

  for (const [name, account] of Object.entries(accounts)) {
    await getAuth().createUser({
      uid: uid(name),
      email: `${uid(name)}@example.invalid`,
      emailVerified: account.verified,
    });
    await db.doc(`users/${uid(name)}`).set(account.profile);
  }

  // 10 BSIT students + 2 BSCS students + 1 teaching user in College A; 3 BSCE students in College B.
  for (let i = 1; i <= 10; i++) {
    const id = uid(`a1-${i}`);
    await db.doc(`users/${id}`).set({
      accessRole: "appUser",
      populationRole: "student",
      collegeId: collegeAId,
      department: collegeAName,
      course: progA1,
      lastActiveAt: Timestamp.fromDate(new Date("2037-09-15T04:00:00Z")),
    });
    await db.doc(`moodEntries/${prefix}-m-a1-${i}`).set({
      userId: id,
      level: 5,
      label: "Great",
      note: "CONFIDENTIAL_NOTE_A1",
      occurredAt: Timestamp.fromDate(new Date("2037-09-15T04:00:00Z")),
    });
    if (i <= 3) {
      await db.doc(`appointments/${prefix}-ap-a1-${i}`).set({
        userId: id,
        department: collegeAName,
        course: progA1,
        yearLevel: "2nd Year",
        status: "completed",
        academicYearId: "2037-2038",
        scheduledAt: Timestamp.fromDate(new Date("2037-09-15T04:00:00Z")),
      });
    }
  }

  for (let i = 1; i <= 2; i++) {
    const id = uid(`a2-${i}`);
    await db.doc(`users/${id}`).set({
      accessRole: "appUser",
      populationRole: "student",
      collegeId: collegeAId,
      department: collegeAName,
      course: progA2,
      lastActiveAt: Timestamp.fromDate(new Date("2037-09-15T04:00:00Z")),
    });
    await db.doc(`appointments/${prefix}-ap-a2-${i}`).set({
      userId: id,
      department: collegeAName,
      course: progA2,
      yearLevel: "1st Year",
      status: "completed",
      academicYearId: "2037-2038",
      scheduledAt: Timestamp.fromDate(new Date("2037-09-15T04:00:00Z")),
    });
  }

  const teachId = uid("teach-a");
  await db.doc(`users/${teachId}`).set({
    accessRole: "appUser",
    populationRole: "teaching",
    collegeId: collegeAId,
    department: collegeAName,
    lastActiveAt: Timestamp.fromDate(new Date("2037-09-15T04:00:00Z")),
  });
  await db.doc(`appointments/${prefix}-ap-teach`).set({
    userId: teachId,
    department: collegeAName,
    status: "pending",
    academicYearId: "2037-2038",
    scheduledAt: Timestamp.fromDate(new Date("2037-09-15T04:00:00Z")),
  });

  for (let i = 1; i <= 3; i++) {
    const id = uid(`b1-${i}`);
    await db.doc(`users/${id}`).set({
      accessRole: "appUser",
      populationRole: "student",
      collegeId: collegeBId,
      department: collegeBName,
      course: progB1,
    });
    await db.doc(`appointments/${prefix}-ap-b1-${i}`).set({
      userId: id,
      department: collegeBName,
      course: progB1,
      status: "completed",
      academicYearId: "2037-2038",
      scheduledAt: Timestamp.fromDate(new Date("2037-09-15T04:00:00Z")),
    });
  }
});

after(async () => {
  if (!emulated) return;
  await Promise.all(
    Object.keys(accounts).map((name) =>
      getAuth().deleteUser(uid(name)).catch(() => undefined),
    ),
  );
});

test(
  "combines college, program, category, year and date filters while enforcing permissions",
  {skip: !emulated},
  async () => {
    // Portal staff denied.
    await rejects(
      fetchReport.run({auth: {uid: uid("staff")}, data: {schoolYear: "2037-2038"}}),
      "permission-denied",
    );

    // Invalid date bounds rejected.
    await rejects(
      fetchReport.run({
        auth: {uid: uid("admin")},
        data: {
          schoolYear: "2037-2038",
          startDate: "2037-10-01T00:00:00Z",
          endDate: "2037-09-01T00:00:00Z",
        },
      }),
      "invalid-argument",
    );

    // Mismatched College A + College B program rejected.
    await rejects(
      fetchReport.run({
        auth: {uid: uid("admin")},
        data: {
          schoolYear: "2037-2038",
          appointmentDepartment: collegeAName,
          program: progB1,
        },
      }),
      "invalid-argument",
    );

    // Counselor A denied when attempting to pass a College B program even with department="all".
    await rejects(
      fetchReport.run({
        auth: {uid: uid("counselor-a")},
        data: {
          schoolYear: "2037-2038",
          appointmentDepartment: "all",
          program: progB1,
        },
      }),
      "permission-denied",
    );

    // Program list is limited strictly to College A when College A is selected.
    const res = await fetchReport.run({
      auth: {uid: uid("counselor-a")},
      data: {
        schoolYear: "2037-2038",
        userCategory: "student",
        appointmentDepartment: collegeAName,
        program: progA1,
        periodLabel: "1st semester",
        startDate: "2037-06-01T00:00:00+08:00",
        endDate: "2037-12-01T00:00:00+08:00",
        emotionalSource: "mood",
      },
    });

    assert.equal(res.report.filters.collegeLabel, collegeAName);
    assert.equal(res.report.filters.programLabel, progA1);
    assert.equal(res.report.filters.periodLabel, "1st semester");
    assert.ok(res.report.filters.programOptions.some((p) => p.label === progA1));
    assert.ok(!res.report.filters.programOptions.some((p) => p.label === progB1));

    // Only the 3 BSIT student appointments are included (BSCS and teaching excluded).
    assert.equal(res.report.appointments.totalAppointments, 3);
    assert.equal(res.report.appointments.uniqueStudentsServed, 3);
    // 10 BSIT students meet emotional privacy threshold (ready).
    assert.equal(res.report.emotionalActivity.status, "ready");

    // Empty date window yields clean empty sets & no_data.
    const emptyRes = await fetchReport.run({
      auth: {uid: uid("admin")},
      data: {
        schoolYear: "2037-2038",
        appointmentDepartment: collegeAName,
        program: progA2,
        startDate: "2038-01-01T00:00:00+08:00",
        endDate: "2038-02-01T00:00:00+08:00",
      },
    });
    assert.equal(emptyRes.report.appointments.totalAppointments, 0);
    assert.equal(emptyRes.report.emotionalActivity.status, "no_data");
    assert.ok(!JSON.stringify(res.report).includes("CONFIDENTIAL_NOTE"));
  },
);
