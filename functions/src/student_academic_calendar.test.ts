import assert from "node:assert/strict";
import {after, before, beforeEach, test} from "node:test";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  buildStudentAcademicCalendarYears,
  getStudentAcademicCalendar,
  getStudentAcademicCalendarDev,
  StudentAcademicYearCalendar,
} from "./student_academic_calendar";

const emulated = Boolean(
  process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST,
);
const prefix = `sac-${Date.now()}`;
const uid = (name: string) => `${prefix}-${name}`;
const db = getFirestore();

type Callable<T> = {
  run: (r: {auth?: {uid: string}; data?: unknown}) => Promise<T>;
};

const fetchCalendar = getStudentAcademicCalendar as unknown as Callable<{
  years: StudentAcademicYearCalendar[];
}>;
const fetchCalendarDev = getStudentAcademicCalendarDev as unknown as Callable<{
  years: StudentAcademicYearCalendar[];
}>;

test("pure builder omits voided, unknown, and malformed years and strips sensitive population fields", () => {
  const years = buildStudentAcademicCalendarYears([
    {
      id: "2026-2027",
      data: {
        schoolYear: "2026-2027",
        startDate: "2026-06-01",
        endDate: "2027-05-31",
        status: "current",
        revision: 3,
        createdBy: "admin-uid-secret",
        updatedBy: "admin-uid-secret",
        populations: {
          "College of Nursing": 450,
          "College of Engineering and Architecture": 820,
        },
        departments: ["College of Nursing"],
      },
    },
    {
      id: "2025-2026",
      data: {
        schoolYear: "2025-2026",
        startDate: "2025-06-01",
        endDate: "2026-05-31",
        status: "closed",
        populations: {"College of Law": 120},
      },
    },
    {
      id: "2027-2028",
      data: {
        schoolYear: "2027-2028",
        startDate: "2027-06-01",
        endDate: "2028-05-31",
        status: "voided",
        voidReason: "Created in error",
      },
    },
    {
      id: "2024-2025",
      data: {
        schoolYear: "2024-2025",
        startDate: "2024-06-01",
        endDate: "2025-05-31",
        status: "unknown_corrupted",
      },
    },
    {
      id: "2023-2024",
      data: {
        schoolYear: "2023-2024",
        // Missing startDate / endDate -> must fail closed and be omitted
        status: "closed",
      },
    },
    {
      id: "2022-2023",
      data: {
        schoolYear: "2022-2023",
        startDate: "2023-06-01",
        endDate: "2022-05-31", // inverted dates -> omitted
        status: "closed",
      },
    },
  ]);

  assert.equal(years.length, 2);
  assert.equal(years[0].schoolYear, "2026-2027");
  assert.equal(years[0].startDateKey, "2026-06-01");
  assert.equal(years[0].endExclusiveDateKey, "2027-06-01");
  assert.equal(years[0].status, "current");
  assert.equal(years[0].semesterRanges.length, 2);
  assert.deepEqual(years[0].semesterRanges[0], {
    id: "semester_1",
    label: "Semester 1 (report grouping)",
    startDateKey: "2026-06-01",
    endExclusiveDateKey: "2026-12-01",
    source: "reportGrouping",
  });
  assert.deepEqual(years[0].semesterRanges[1], {
    id: "semester_2",
    label: "Semester 2 (report grouping)",
    startDateKey: "2026-12-01",
    endExclusiveDateKey: "2027-06-01",
    source: "reportGrouping",
  });

  // Verify no sensitive fields leak onto the returned objects.
  for (const item of years) {
    assert.deepEqual(
      Object.keys(item).sort(),
      ["endExclusiveDateKey", "schoolYear", "semesterRanges", "startDateKey", "status"],
    );
    assert.equal("populations" in item, false);
    assert.equal("departments" in item, false);
    assert.equal("createdBy" in item, false);
    assert.equal("revision" in item, false);
  }
});

test("pure builder handles short (<6 month) academic years, valid configured semesters, and fails closed on malformed configured semesters", () => {
  const years = buildStudentAcademicCalendarYears([
    {
      id: "2026-2027",
      data: {
        schoolYear: "2026-2027",
        startDate: "2026-06-01",
        endDate: "2026-10-31", // < 6 months -> no 6-month reportGrouping split
        status: "current",
      },
    },
    {
      id: "2025-2026",
      data: {
        schoolYear: "2025-2026",
        startDate: "2025-06-01",
        endDate: "2026-05-31",
        status: "closed",
        semesterRanges: [
          {
            id: "first_sem",
            label: "1st Semester",
            startDate: "2025-06-01",
            endDate: "2025-10-31",
          },
          {
            id: "second_sem",
            label: "2nd Semester",
            startDateKey: "2025-11-15",
            endExclusiveDateKey: "2026-04-01",
          },
        ],
      },
    },
    {
      id: "2024-2025",
      data: {
        schoolYear: "2024-2025",
        startDate: "2024-06-01",
        endDate: "2025-05-31",
        status: "closed",
        // Malformed configured semester (inverted dates) must fail closed to []
        // rather than silently inventing a 6-month reportGrouping split.
        semesterRanges: [
          {
            id: "bad_sem",
            label: "Broken Semester",
            startDateKey: "2024-12-01",
            endExclusiveDateKey: "2024-06-01",
          },
        ],
      },
    },
  ]);

  assert.equal(years.length, 3);
  // Short academic year (< 6 months) has empty semesterRanges (All year only).
  assert.equal(years[0].schoolYear, "2026-2027");
  assert.deepEqual(years[0].semesterRanges, []);

  // Valid configured semesters preserve configured source and convert inclusive endDate to endExclusiveDateKey.
  assert.equal(years[1].schoolYear, "2025-2026");
  assert.deepEqual(years[1].semesterRanges, [
    {
      id: "first_sem",
      label: "1st Semester",
      startDateKey: "2025-06-01",
      endExclusiveDateKey: "2025-11-01",
      source: "configured",
    },
    {
      id: "second_sem",
      label: "2nd Semester",
      startDateKey: "2025-11-15",
      endExclusiveDateKey: "2026-04-01",
      source: "configured",
    },
  ]);

  // Malformed configured semesters fail closed to [] (All year only).
  assert.equal(years[2].schoolYear, "2024-2025");
  assert.deepEqual(years[2].semesterRanges, []);
});

const accounts: Record<
  string,
  {verified: boolean; disabled?: boolean; profile: Record<string, unknown> | null}
> = {
  student: {
    verified: true,
    profile: {
      accessRole: "appUser",
      populationRole: "student",
      role: "student",
      accountStatus: "active",
    },
  },
  "suspended-student": {
    verified: true,
    profile: {
      accessRole: "appUser",
      populationRole: "student",
      accountStatus: "suspended",
    },
  },
  "unverified-student": {
    verified: false,
    profile: {
      accessRole: "appUser",
      populationRole: "student",
      accountStatus: "active",
    },
  },
  "disabled-student": {
    verified: true,
    disabled: true,
    profile: {
      accessRole: "appUser",
      populationRole: "student",
      accountStatus: "active",
    },
  },
  "pending-staff": {
    verified: true,
    profile: {
      accessRole: "appUser",
      role: "staff",
      staffAccountStatus: "pending",
      accountStatus: "pending",
    },
  },
  "missing-profile": {
    verified: true,
    profile: null,
  },
};

before(async () => {
  if (!emulated) return;
  for (const [name, account] of Object.entries(accounts)) {
    await getAuth().createUser({
      uid: uid(name),
      email: `${uid(name)}@example.invalid`,
      emailVerified: account.verified,
      disabled: account.disabled === true,
    });
    if (account.profile) {
      await db.doc(`users/${uid(name)}`).set(account.profile);
    }
  }
});

beforeEach(async () => {
  if (!emulated) return;
  const snap = await db.collection("counseling_population").get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
});

after(async () => {
  if (!emulated) return;
  await Promise.all(
    Object.keys(accounts).map((name) =>
      getAuth()
        .deleteUser(uid(name))
        .catch(() => undefined),
    ),
  );
});

test(
  "emulator: active student reads only safe academic calendar metadata; unauthorized and unauthenticated callers are denied",
  {skip: !emulated},
  async () => {
    await db.doc("counseling_population/2026-2027").set({
      schoolYear: "2026-2027",
      startDate: "2026-06-01",
      endDate: "2027-05-31",
      status: "current",
      createdBy: "super-admin-uid",
      populations: {"College of Nursing": 500},
    });
    await db.doc("counseling_population/2027-2028").set({
      schoolYear: "2027-2028",
      startDate: "2027-06-01",
      endDate: "2028-05-31",
      status: "voided",
      voidReason: "Voided test year",
    });

    await assert.rejects(
      fetchCalendar.run({}),
      (err: unknown) => err instanceof HttpsError && err.code === "unauthenticated",
    );

    for (const denied of [
      "suspended-student",
      "unverified-student",
      "disabled-student",
      "pending-staff",
      "missing-profile",
    ]) {
      await assert.rejects(
        fetchCalendar.run({auth: {uid: uid(denied)}}),
        (err: unknown) =>
          err instanceof HttpsError && err.code === "permission-denied",
      );
    }

    const res = await fetchCalendar.run({auth: {uid: uid("student")}});
    assert.equal(res.years.length, 1);
    assert.equal(res.years[0].schoolYear, "2026-2027");
    assert.equal(res.years[0].startDateKey, "2026-06-01");
    assert.equal(res.years[0].endExclusiveDateKey, "2027-06-01");
    assert.equal("populations" in (res.years[0] as Record<string, unknown>), false);

    const devRes = await fetchCalendarDev.run({auth: {uid: uid("student")}});
    assert.deepEqual(devRes, res);
  },
);
