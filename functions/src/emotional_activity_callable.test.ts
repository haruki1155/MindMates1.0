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
const prefix = `emo-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const db = getFirestore();

type Callable = {
  run: (r: {auth?: {uid: string}; data?: Record<string, unknown>}) => Promise<{
    report: {
      emotionalActivity: {
        status: string;
        suppressed: boolean;
        suppressionThreshold: number;
        participationRate: number | null;
        valenceBreakdown: Array<{key: string; percentage: number | null; suppressed: boolean}>;
      };
      appointments: {
        departmentScopeLabel: string;
        department: Array<{label: string; percentage: number}>;
      };
    };
  }>;
};

const fetchReport = getReportAnalytics as unknown as Callable;

const collegeAId = `${prefix}-cas`;
const collegeBId = `${prefix}-coe`;
const collegeAName = `${prefix} College of Arts`;
const collegeBName = `${prefix} College of Engineering`;

const accounts: Record<string, {verified: boolean; profile: Record<string, unknown>}> = {
  "super-admin": {verified: true, profile: {accessRole: "admin", accountStatus: "active"}},
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
  "suspended-counselor": {
    verified: true,
    profile: {
      accessRole: "counselor",
      staffAccountStatus: "approved",
      accountStatus: "suspended",
      assignedCollegeIds: [collegeAId],
    },
  },
  staff: {
    verified: true,
    profile: {accessRole: "portalStaff", staffAccountStatus: "approved", accountStatus: "active"},
  },
  student: {
    verified: true,
    profile: {accessRole: "appUser", role: "student", accountStatus: "active"},
  },
};

async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (e: unknown) => e instanceof HttpsError && e.code === code);
}

let previousSuperAdmin: string | undefined;

before(async () => {
  if (!emulated) return;
  previousSuperAdmin = process.env.SUPER_ADMIN_UID;
  process.env.SUPER_ADMIN_UID = uid("super-admin");
  await Promise.all([
    db.doc(`colleges/${collegeAId}`).set({name: collegeAName, code: "CAS", active: true}),
    db.doc(`colleges/${collegeBId}`).set({name: collegeBName, code: "COE", active: true}),
    db.doc("counseling_population/2035-2036").set({
      schoolYear: "2035-2036",
      startDate: "2035-06-01",
      endDate: "2036-05-31",
      status: "current",
      populations: {
        "College of Accountancy and Business Administration": 100,
        "College of Arts and Sciences / College of Arts and Languages": 100,
        "College of Information and Technology Education / College of Computer Studies": 100,
        "College of Criminology": 100,
        "College of Education / College of Teacher Education": 100,
        "College of Engineering and Architecture": 100,
        "College of Law": 100,
        "College of Nursing": 100,
        "College of Pharmacy": 100,
        "College of Science and Mathematics": 100,
        "College of Social Work": 100,
        "Graduate School / Institute of Graduate and Advanced Studies": 100,
        "School of Hotel and Restaurant Services and Tourism Management": 100,
        "School of Midwifery": 100,
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
  // 10 students in College A (meets threshold) + 4 students in College B (below threshold).
  for (let i = 1; i <= 10; i++) {
    const suid = uid(`stud-a-${i}`);
    await db.doc(`users/${suid}`).set({
      accessRole: "appUser",
      populationRole: "student",
      verificationStatus: "verified",
      collegeId: collegeAId,
      department: collegeAName,
    });
    await db.doc(`moodEntries/${prefix}-m-a-${i}`).set({
      userId: suid,
      level: 5,
      label: "Great",
      note: "PRIVATE_NOTE_DO_NOT_LEAK",
      occurredAt: Timestamp.fromDate(new Date("2035-09-10T01:00:00Z")),
    });
  }
  for (let i = 1; i <= 4; i++) {
    const suid = uid(`stud-b-${i}`);
    await db.doc(`users/${suid}`).set({
      accessRole: "appUser",
      populationRole: "student",
      verificationStatus: "verified",
      collegeId: collegeBId,
      department: collegeBName,
    });
    await db.doc(`moodEntries/${prefix}-m-b-${i}`).set({
      userId: suid,
      level: 1,
      label: "Sad",
      note: "PRIVATE_NOTE_B",
      occurredAt: Timestamp.fromDate(new Date("2035-09-10T01:00:00Z")),
    });
  }
});

after(async () => {
  if (!emulated) return;
  if (previousSuperAdmin === undefined) delete process.env.SUPER_ADMIN_UID;
  else process.env.SUPER_ADMIN_UID = previousSuperAdmin;
  await Promise.all(
    Object.keys(accounts).map((name) =>
      getAuth().deleteUser(uid(name)).catch(() => undefined),
    ),
  );
});

test(
  "getReportAnalytics enforces role access and cross-college scope for counselors",
  {skip: !emulated},
  async () => {
    await rejects(fetchReport.run({data: {schoolYear: "2035-2036"}}), "unauthenticated");
    for (const denied of ["student", "staff", "suspended-counselor", "admin"]) {
      await rejects(
        fetchReport.run({auth: {uid: uid(denied)}, data: {schoolYear: "2035-2036"}}),
        "permission-denied",
      );
    }

    // Counselor assigned only to College A cannot query College B directly.
    await rejects(
      fetchReport.run({
        auth: {uid: uid("counselor-a")},
        data: {
          schoolYear: "2035-2036",
          appointmentDepartment: collegeBName,
        },
      }),
      "permission-denied",
    );

    // Counselor A querying "all" only sees College A cohort (10 Positive, zero College B Strained).
    const counselorARes = await fetchReport.run({
      auth: {uid: uid("counselor-a")},
      data: {schoolYear: "2035-2036", emotionalSource: "mood"},
    });
    assert.equal(counselorARes.report.emotionalActivity.status, "ready");
    assert.deepEqual(
      counselorARes.report.emotionalActivity.valenceBreakdown.map((b) => [b.key, b.percentage]),
      [["positive", 100]],
    );
    assert.ok(!JSON.stringify(counselorARes.report).includes("PRIVATE_NOTE"));

    // College A has 0 appointments in fixture; filtering by College A must preserve collegeAName.
    const zeroApptCollegeRes = await fetchReport.run({
      auth: {uid: uid("counselor-a")},
      data: {
        schoolYear: "2035-2036",
        appointmentDepartment: collegeAName,
        emotionalSource: "mood",
      },
    });
    assert.equal(zeroApptCollegeRes.report.appointments.departmentScopeLabel, collegeAName);

    // Super-admin querying small College B (<10 participants) gets suppressed result.
    const adminBRes = await fetchReport.run({
      auth: {uid: uid("super-admin")},
      data: {
        schoolYear: "2035-2036",
        appointmentDepartment: collegeBName,
        emotionalSource: "mood",
      },
    });
    assert.equal(adminBRes.report.emotionalActivity.status, "suppressed");
    assert.equal(adminBRes.report.emotionalActivity.suppressed, true);
    assert.deepEqual(adminBRes.report.emotionalActivity.valenceBreakdown, []);
  },
);
