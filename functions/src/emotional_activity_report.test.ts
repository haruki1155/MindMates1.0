import assert from "node:assert/strict";
import test from "node:test";

import {
  buildEmotionalActivityReport,
  MIN_EMOTIONAL_COHORT_SIZE,
} from "./emotional_activity_report";

type Rec = Record<string, unknown>;

function makeUsers(
  count: number,
  overrides: (index: number) => Rec = () => ({}),
): Array<{id: string; data: Rec}> {
  return Array.from({length: count}, (_, i) => ({
    id: `u-${i + 1}`,
    data: {
      accessRole: "appUser",
      populationRole: "student",
      department: "College of Computing",
      collegeId: "ccs",
      course: "BSIT",
      yearLevel: "2nd Year",
      ...overrides(i),
    },
  }));
}

function makeMoods(
  count: number,
  overrides: (index: number) => Rec = () => ({}),
): Rec[] {
  return Array.from({length: count}, (_, i) => ({
    userId: `u-${i + 1}`,
    level: i % 2 === 0 ? 5 : 2,
    label: i % 2 === 0 ? "Great" : "Stressed",
    note: `PRIVATE_JOURNAL_TEXT_${i + 1}`,
    expressionModelVersion: "justinshenk_fer_tflite_v1",
    photoUrl: `https://example.invalid/face-${i + 1}.jpg`,
    occurredAt: "2026-09-10T08:00:00.000Z",
    ...overrides(i),
  }));
}

test("MIN_EMOTIONAL_COHORT_SIZE is 10", () => {
  assert.equal(MIN_EMOTIONAL_COHORT_SIZE, 10);
});

test("returns no_data when no approved records match filters", () => {
  const report = buildEmotionalActivityReport({
    users: makeUsers(12),
    moodEntries: [],
    moods: [],
    assessments: [],
    range: {
      start: new Date("2026-06-01T00:00:00+08:00"),
      end: new Date("2027-06-01T00:00:00+08:00"),
      label: "Academic year 2026-2027",
    },
    schoolYear: "2026-2027",
  });

  assert.equal(report.status, "no_data");
  assert.equal(report.suppressed, false);
  assert.equal(report.participationRate, null);
  assert.deepEqual(report.valenceBreakdown, []);
  assert.deepEqual(report.moodBreakdown, []);
  assert.deepEqual(report.assessmentBreakdown, []);
  assert.deepEqual(report.periodTrends, []);
});

test("suppresses entire cohort when unique participants < 10 even with many repeated entries", () => {
  const repeatedSingleUserEntries = Array.from({length: 25}, (_, idx) => ({
    userId: "u-1",
    level: 1,
    label: "Sad",
    note: "SENSITIVE_NOTE_SHOULD_NEVER_LEAK",
    occurredAt: `2026-09-${String((idx % 20) + 1).padStart(2, "0")}T08:00:00.000Z`,
  }));
  const nineUsersEntries = makeMoods(9);

  for (const entries of [repeatedSingleUserEntries, nineUsersEntries]) {
    const report = buildEmotionalActivityReport({
      users: makeUsers(15),
      moodEntries: entries,
      moods: [],
      assessments: [],
      range: {
        start: new Date("2026-06-01T00:00:00+08:00"),
        end: new Date("2027-06-01T00:00:00+08:00"),
        label: "Academic year 2026-2027",
      },
      schoolYear: "2026-2027",
      configuredPopulation: 100,
    });

    assert.equal(report.status, "suppressed");
    assert.equal(report.suppressed, true);
    assert.equal(report.suppressionThreshold, 10);
    assert.equal(report.participationRate, null);
    assert.equal(report.dominantValenceLabel, null);
    assert.deepEqual(report.valenceBreakdown, []);
    assert.deepEqual(report.moodBreakdown, []);
    assert.deepEqual(report.assessmentBreakdown, []);
    assert.deepEqual(report.periodTrends, []);
    const serialized = JSON.stringify(report);
    assert.ok(!serialized.includes("SENSITIVE_NOTE"));
    assert.ok(!serialized.includes("PRIVATE_JOURNAL"));
    assert.ok(!serialized.includes("face-"));
    assert.ok(!serialized.includes("u-1"));
  }
});

test("aggregates approved sources by percentages without exposing raw notes, responses, or PII", () => {
  const users = makeUsers(24, (i) => ({
    populationRole: i < 20 ? "student" : i < 22 ? "teaching" : "",
    department: i < 22 ? "College of Computing" : "",
  }));
  const moodEntries = makeMoods(20, (i) => ({
    level: i < 10 ? 5 : 2,
    label: i < 10 ? "Great" : "Custom Unsanitized Text PII",
  }));
  const legacyMoods = [
    // Archived & non-appUser entries must be ignored.
    {userId: "u-21", level: 4, label: "Okay", occurredAt: "2026-09-12T08:00:00Z"},
    {userId: "u-22", level: 4, label: "Okay", dateKey: "2026-09-15"},
    {userId: "u-23", level: 1, label: "Sad", archivedAt: "2026-09-15T00:00:00Z", createdAt: "2026-09-14T00:00:00Z"},
    {userId: "counselor-1", level: 1, label: "Angry", createdAt: "2026-09-14T00:00:00Z"},
  ];
  const assessments = Array.from({length: 20}, (_, i) => ({
    userId: `u-${i + 1}`,
    schemaVersion: "assessment_record_v4",
    verificationStatus: "verified",
    result: {
      profileStatus: i < 10 ? "generallySupported" : "supportMayHelp",
      domainResults: [
        {
          domainId: "emotionalWellbeing",
          status: i < 10 ? "supported" : "supportMayHelp",
          isScorable: true,
        },
      ],
    },
    responses: [{itemId: "q1", secretAnswer: "NEVER_LEAK"}],
    counselorSummary: "CLINICAL_TEXT_NEVER_LEAK",
    createdAt: "2026-09-18T09:00:00.000Z",
  }));
  // Unconsented & archived assessments must be excluded.
  assessments.push(
    {
      userId: "u-24",
      schemaVersion: "assessment_record_v4",
      verificationStatus: "verified",
      privacyOptOut: true,
      result: {profileStatus: "supportMayHelp", domainResults: []},
      responses: [],
      counselorSummary: "OPT_OUT_SECRET",
      createdAt: "2026-09-18T09:00:00.000Z",
    } as unknown as (typeof assessments)[number],
  );

  const report = buildEmotionalActivityReport({
    users,
    moodEntries,
    moods: legacyMoods,
    assessments,
    range: {
      start: new Date("2026-06-01T00:00:00+08:00"),
      end: new Date("2027-06-01T00:00:00+08:00"),
      label: "Academic year 2026-2027",
    },
    schoolYear: "2026-2027",
    configuredPopulation: 44,
    source: "all",
  });

  assert.equal(report.status, "ready");
  assert.equal(report.suppressed, false);
  assert.equal(report.hasMixedCategories, true);
  // 22 unique active app users matched (u-1..u-22); u-23 had only archived mood, u-24 opted out.
  assert.equal(report.participationRate, 50);
  assert.ok(report.valenceBreakdown.some((b) => b.key === "positive" && b.percentage !== null));
  const serialized = JSON.stringify(report);
  for (const forbidden of [
    "Custom Unsanitized Text PII",
    "NEVER_LEAK",
    "CLINICAL_TEXT_NEVER_LEAK",
    "OPT_OUT_SECRET",
    "PRIVATE_JOURNAL_TEXT",
    "counselor-1",
    "u-1",
  ]) {
    assert.ok(!serialized.includes(forbidden), `Leaked forbidden string: ${forbidden}`);
  }
});

test("enforces per-cell suppression and secondary suppression against subtraction inference", () => {
  // 10 Positive users + 2 Strained users => total 12 >= 10, so cohort is ready,
  // but Strained cell (<10) AND Positive cell (secondary suppression) are both suppressed!
  const moodEntries = [
    ...Array.from({length: 10}, (_, i) => ({
      userId: `u-${i + 1}`,
      level: 5,
      label: "Great",
      occurredAt: "2026-10-01T08:00:00Z",
    })),
    ...Array.from({length: 2}, (_, i) => ({
      userId: `u-${i + 11}`,
      level: 1,
      label: "Sad",
      occurredAt: "2026-10-02T08:00:00Z",
    })),
  ];

  const report = buildEmotionalActivityReport({
    users: makeUsers(12),
    moodEntries,
    moods: [],
    assessments: [],
    range: {
      start: new Date("2026-06-01T00:00:00+08:00"),
      end: new Date("2027-06-01T00:00:00+08:00"),
      label: "Academic year 2026-2027",
    },
    schoolYear: "2026-2027",
    source: "mood",
  });

  assert.equal(report.status, "ready");
  assert.equal(report.valenceBreakdown.length, 2);
  assert.ok(report.valenceBreakdown.every((bucket) => bucket.suppressed && bucket.percentage === null));
});

test("filters strictly by college/department, source, userCategory, and academic year without leakage", () => {
  const users = [
    ...Array.from({length: 10}, (_, i) => ({
      id: `n-${i + 1}`,
      data: {
        accessRole: "appUser",
        populationRole: "student",
        department: "College of Nursing",
        collegeId: "con",
      },
    })),
    ...Array.from({length: 10}, (_, i) => ({
      id: `e-${i + 1}`,
      data: {
        accessRole: "appUser",
        populationRole: "teaching",
        department: "College of Engineering",
        collegeId: "coe",
      },
    })),
  ];
  const moodEntries = [
    ...Array.from({length: 10}, (_, i) => ({
      userId: `n-${i + 1}`,
      level: 5,
      label: "Great",
      occurredAt: "2025-09-10T08:00:00Z",
    })),
    ...Array.from({length: 10}, (_, i) => ({
      userId: `e-${i + 1}`,
      level: 1,
      label: "Sad",
      occurredAt: "2026-09-10T08:00:00Z",
    })),
  ];

  const historicalNursing = buildEmotionalActivityReport({
    users,
    moodEntries,
    moods: [],
    assessments: [],
    range: {
      start: new Date("2025-06-01T00:00:00+08:00"),
      end: new Date("2026-06-01T00:00:00+08:00"),
      label: "Academic year 2025-2026",
    },
    schoolYear: "2025-2026",
    department: "college of nursing",
    userCategory: "student",
    source: "mood",
    configuredPopulation: 50,
  });

  assert.equal(historicalNursing.status, "ready");
  assert.equal(historicalNursing.participationRate, 20);
  assert.deepEqual(
    historicalNursing.valenceBreakdown.map((b) => [b.key, b.percentage]),
    [["positive", 100]],
  );
  // Engineering strained entries must never appear in Nursing report.
  assert.ok(!historicalNursing.moodBreakdown.some((b) => b.key === "sad"));
});

test("gates source share split at >= 10 users per source and omits draft/unscorable edge cases cleanly", () => {
  const users = makeUsers(12, (i) => ({
    populationRole: i < 10 ? "student" : "",
    department: i < 10 ? "College of Nursing" : "",
  }));
  const moodEntries = makeMoods(12, () => ({level: 5, label: "Great"}));
  // Only 3 users have assessments (<10), plus a draft and unscorable domain result.
  const assessments = [
    {
      userId: "u-1",
      schemaVersion: "assessment_record_v4",
      verificationStatus: "verified",
      result: {
        profileStatus: "generallySupported",
        domainResults: [{domainId: "emotionalWellbeing", status: "supportMayHelp", isScorable: false}],
      },
      createdAt: "2026-09-10T08:00:00Z",
    },
    {
      userId: "u-2",
      schemaVersion: "assessment_record_v4",
      status: "draft",
      result: {profileStatus: "supportMayHelp"},
      createdAt: "2026-09-10T08:00:00Z",
    },
    {
      userId: "u-3",
      schemaVersion: "assessment_record_v4",
      verificationStatus: "rejected",
      result: {profileStatus: "supportMayHelp"},
      createdAt: "2026-09-10T08:00:00Z",
    },
  ];

  const report = buildEmotionalActivityReport({
    users,
    moodEntries,
    moods: [],
    assessments,
    range: {
      start: new Date("2026-06-01T00:00:00+08:00"),
      end: new Date("2027-06-01T00:00:00+08:00"),
      label: "Academic year 2026-2027",
    },
    schoolYear: "2026-2027",
    source: "all",
  });

  assert.equal(report.status, "ready");
  // Fewer than 10 assessment users -> source shares and sub-source bucket labels are omitted.
  assert.equal(report.moodCheckInShare, null);
  assert.equal(report.assessmentShare, null);
  assert.ok(report.departmentCoverageNote.includes("unspecified role or college"));
  assert.deepEqual(report.assessmentBreakdown, []);

  // When >= 10 verified assessments are present, draft/rejected assessments remain excluded.
  const tenVerifiedAssessments = Array.from({length: 10}, (_, idx) => ({
    userId: `u-${idx + 1}`,
    schemaVersion: "assessment_record_v4",
    verificationStatus: "verified",
    result: {profileStatus: "generallySupported", domainResults: []},
    createdAt: "2026-09-10T08:00:00Z",
  }));
  const reportWithTenAssessments = buildEmotionalActivityReport({
    users,
    moodEntries,
    moods: [],
    assessments: [
      ...tenVerifiedAssessments,
      assessments[1], // draft u-2 (supportMayHelp)
      assessments[2], // rejected u-3 (supportMayHelp)
    ],
    range: {
      start: new Date("2026-06-01T00:00:00+08:00"),
      end: new Date("2027-06-01T00:00:00+08:00"),
      label: "Academic year 2026-2027",
    },
    schoolYear: "2026-2027",
    source: "all",
  });
  assert.deepEqual(
    reportWithTenAssessments.assessmentBreakdown.map((b) => [b.key, b.percentage]),
    [["supported", 100]],
  );
});

test("omits sub-source breakdown labels when sub-source unique users < 10 while keeping ready cohort status", () => {
  const users = makeUsers(12);
  const moodEntries = makeMoods(10, () => ({level: 5, label: "Great"}));
  const assessments = [
    {
      userId: "u-11",
      schemaVersion: "assessment_record_v4",
      verificationStatus: "verified",
      result: {profileStatus: "supportMayHelp", domainResults: []},
      createdAt: "2026-09-10T08:00:00Z",
    },
  ];

  const report = buildEmotionalActivityReport({
    users,
    moodEntries,
    moods: [],
    assessments,
    range: {
      start: new Date("2026-06-01T00:00:00+08:00"),
      end: new Date("2027-06-01T00:00:00+08:00"),
      label: "Academic year 2026-2027",
    },
    schoolYear: "2026-2027",
    source: "all",
  });

  assert.equal(report.status, "ready");
  assert.equal(report.assessmentShare, null);
  assert.equal(report.moodCheckInShare, null);
  assert.deepEqual(report.assessmentBreakdown, []);
  assert.ok(!JSON.stringify(report.assessmentBreakdown).includes("Support May Help"));
});

test("excludes staff and admin role token variants from emotional activity aggregation", () => {
  const users = [
    ...makeUsers(10),
    {id: "staff-space", data: {role: "portal staff", populationRole: "student"}},
    {id: "staff-hyphen", data: {role: "portal-staff", populationRole: "student"}},
    {id: "super-admin", data: {role: "super_admin", populationRole: "student"}},
    {id: "conflict-admin", data: {accessRole: "appUser", role: "admin", populationRole: "student"}},
  ];
  const moodEntries = [
    ...makeMoods(10, () => ({level: 5, label: "Great"})),
    {userId: "staff-space", level: 1, label: "Sad", occurredAt: "2026-09-10T08:00:00.000Z"},
    {userId: "staff-hyphen", level: 1, label: "Sad", occurredAt: "2026-09-10T08:00:00.000Z"},
    {userId: "super-admin", level: 1, label: "Sad", occurredAt: "2026-09-10T08:00:00.000Z"},
    {userId: "conflict-admin", level: 1, label: "Sad", occurredAt: "2026-09-10T08:00:00.000Z"},
  ];

  const report = buildEmotionalActivityReport({
    users,
    moodEntries,
    moods: [],
    assessments: [],
    range: {
      start: new Date("2026-06-01T00:00:00+08:00"),
      end: new Date("2027-06-01T00:00:00+08:00"),
      label: "Academic year 2026-2027",
    },
    schoolYear: "2026-2027",
    source: "mood",
  });

  assert.equal(report.status, "ready");
  assert.deepEqual(
    report.valenceBreakdown.map((b) => [b.key, b.percentage]),
    [["positive", 100]],
  );
});

test("computes weekly Manila Monday-Sunday trends, flags elevated Stressed mood vs rolling baseline, and never exposes notes", () => {
  const users = makeUsers(25);
  const moodEntries: Array<Record<string, unknown>> = [];

  // Week 1 (Nov 2-8, 2026): 15 Great (60%), 10 Stressed (40%)
  for (let i = 0; i < 25; i++) {
    moodEntries.push({
      userId: `u-${i + 1}`,
      clientRequestId: `w1-u-${i + 1}`,
      label: i < 15 ? "Great" : "Stressed",
      level: i < 15 ? 5 : 2,
      entryMethod: i < 15 ? "manual" : "expression_assisted",
      expressionAssistUsed: i >= 15,
      note: "Private sensitive journal note must never leak",
      occurredAt: "2026-11-04T09:00:00+08:00", // Wed
    });
  }

  // Week 2 (Nov 9-15, 2026): 15 Great (60%), 10 Stressed (40%)
  for (let i = 0; i < 25; i++) {
    moodEntries.push({
      userId: `u-${i + 1}`,
      clientRequestId: `w2-u-${i + 1}`,
      label: i < 15 ? "Great" : "Stressed",
      level: i < 15 ? 5 : 2,
      entryMethod: "manual",
      occurredAt: "2026-11-11T09:00:00+08:00", // Wed
    });
  }

  // Week 3 (Nov 16-22, 2026): 10 Great (40%), 15 Stressed (60% -> +20.0 pp vs 40% baseline => elevated!)
  for (let i = 0; i < 25; i++) {
    moodEntries.push({
      userId: `u-${i + 1}`,
      clientRequestId: `w3-u-${i + 1}`,
      label: i < 10 ? "Great" : "Stressed",
      level: i < 10 ? 5 : 2,
      entryMethod: "manual",
      occurredAt: "2026-11-18T09:00:00+08:00", // Wed
    });
  }

  // Duplicate entry in legacy moods with same clientRequestId must be deduplicated.
  const duplicateLegacy = [
    {
      userId: "u-1",
      clientRequestId: "w3-u-1",
      label: "Great",
      level: 5,
      occurredAt: "2026-11-18T09:00:00+08:00",
    },
  ];

  const report = buildEmotionalActivityReport({
    users,
    moodEntries,
    moods: duplicateLegacy,
    assessments: [],
    range: {
      start: new Date("2026-11-01T00:00:00+08:00"),
      end: new Date("2026-11-30T00:00:00+08:00"),
      label: "November 2026",
    },
    schoolYear: "2026-2027",
    source: "mood",
  });

  assert.equal(report.status, "ready");
  assert.equal(report.weeklyTrends.length, 3);
  assert.deepEqual(
    report.weeklyTrends.map((w) => w.weekKey),
    ["2026-11-02", "2026-11-09", "2026-11-16"],
  );
  assert.equal(report.weeklyTrends[0].dominantMoodLabel, "Great");
  assert.equal(report.weeklyTrends[2].dominantMoodLabel, "Stressed");
  assert.equal(report.weeklyTrends[2].strainedShare, 60);

  const stressedSignal = report.elevatedMoodSignals.find((s) => s.key === "stressed");
  assert.ok(stressedSignal);
  assert.equal(stressedSignal.severity, "elevated");
  assert.equal(stressedSignal.currentPercentage, 60);
  assert.equal(stressedSignal.baselinePercentage, 40);
  assert.equal(stressedSignal.deltaPoints, 20);
  assert.equal(stressedSignal.weekOverWeekDelta, 20);

  // Deduplication kept exact 3.0 check-ins per participant (75 / 25), not 76 / 25.
  assert.ok(report.moodEngagement);
  assert.equal(report.moodEngagement.avgCheckInsPerParticipant, 3);
  assert.equal(report.moodEngagement.repeatParticipantRate, 100);
  assert.equal(report.moodEngagement.entryMethodBreakdown.length, 2);

  // Weekday breakdown captures Wednesday with unsuppressed strained share.
  const wed = report.weekdayBreakdown.find((d) => d.key === "3_wed");
  assert.ok(wed);
  assert.equal(wed.suppressed, false);
  assert.equal(wed.activityShare, 100);

  // Actionable insights populated and raw journal note never appears anywhere in report JSON.
  assert.ok(report.actionableInsights.length >= 2);
  assert.ok(!JSON.stringify(report).includes("Private sensitive journal note"));
});

test("suppresses weekly rows with fewer than 10 unique participants and supports pre-range lookback baseline", () => {
  const users = makeUsers(22);
  const moodEntries: Array<Record<string, unknown>> = [];

  // Lookback week before range.start (Nov 2-8): 12 Great, 10 Stressed (45.5% Stressed).
  for (let i = 0; i < 22; i++) {
    moodEntries.push({
      userId: `u-${i + 1}`,
      label: i < 12 ? "Great" : "Stressed",
      level: i < 12 ? 5 : 2,
      occurredAt: "2026-11-04T10:00:00+08:00",
    });
  }

  // In-range Week A (Nov 9-15): only 5 unique users -> MUST be suppressed!
  for (let i = 0; i < 5; i++) {
    moodEntries.push({
      userId: `u-${i + 1}`,
      label: "Angry",
      level: 1,
      occurredAt: "2026-11-11T10:00:00+08:00",
    });
  }

  // In-range Week B (Nov 16-22): 10 Great, 12 Stressed (54.5% Stressed -> +9.0 pp vs lookback).
  for (let i = 0; i < 22; i++) {
    moodEntries.push({
      userId: `u-${i + 1}`,
      label: i < 10 ? "Great" : "Stressed",
      level: i < 10 ? 5 : 2,
      occurredAt: "2026-11-18T10:00:00+08:00",
    });
  }

  const report = buildEmotionalActivityReport({
    users,
    moodEntries,
    moods: [],
    assessments: [],
    range: {
      start: new Date("2026-11-09T00:00:00+08:00"),
      end: new Date("2026-11-23T00:00:00+08:00"),
      label: "Nov 9–22, 2026",
    },
    schoolYear: "2026-2027",
    source: "mood",
  });

  assert.equal(report.status, "ready");
  assert.equal(report.weeklyTrends.length, 2);
  assert.equal(report.weeklyTrends[0].suppressed, true);
  assert.equal(report.weeklyTrends[0].dominantMoodLabel, null);
  assert.deepEqual(report.weeklyTrends[0].moodBreakdown, []);
  // Secondary suppression hides Week B's activityShare too so Week A cannot be subtracted,
  // while Week B's own internal moodBreakdown remains reportable (n = 22 >= 10).
  assert.equal(report.weeklyTrends[1].suppressed, false);
  assert.equal(report.weeklyTrends[1].activityShare, null);
  assert.equal(report.weeklyTrends[1].dominantMoodLabel, "Stressed");

  // Elevation signal uses lookback week (Nov 2-8) cleanly without leaking suppressed Week A ("Angry").
  assert.ok(!report.elevatedMoodSignals.some((s) => s.key === "angry"));
  const stressedSignal = report.elevatedMoodSignals.find((s) => s.key === "stressed");
  assert.ok(stressedSignal);
  assert.equal(stressedSignal.severity, "elevated");
});
