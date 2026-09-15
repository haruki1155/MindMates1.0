# Assessment v4 Implementation Contract Audit

## Decision

**Not ready to implement the v4 question bank yet.** The positive-psychology
proposal defines content and broad presentation rules, but it does not yet define the
immutable data and algorithm contract needed to safely implement, audit, and preserve
assessment results.

This audit is based on the current Flutter app, Firestore rules, Cloud Functions, and
the existing `experimental_role_based_v3` contract.

## Current implementation: what already exists

| Area | Existing behavior | Audit result |
| --- | --- | --- |
| Question IDs | v3 has 50 non-conditional student IDs and a JSON ID contract. | Good starting point; IDs are not version-namespaced. |
| Main responses | Flutter stores `never`, `rarely`, `often`, `always` as 1–4. | Technically deterministic but semantically misleading because the UI displays agreement labels. |
| Domain calculation | Risk items rise 1→4; protective items reverse; each domain is averaged. | Duplicated in Flutter and Functions; can drift. |
| Results | Domain results, response quality, focus, strengths, actions, and an explanation object are stored. | Useful shape, but the fields and status vocabulary conflict with the v4 proposal. |
| Version field | `questionSetVersion` exists on records. | Insufficient: the active catalog is global, not resolved by version. |
| Historical records | Some legacy migration handling exists. | Unsafe for a v4 release because it validates/recalculates against the current catalog. |
| Summary UI | Completion and Mental Health Summary display strengths, areas to explore, domain cards, and support guidance. | Close to the target UI, but not bound to one immutable result contract. |

## Release-blocking findings

### 1. No production server authority — critical

In non-staging builds, `AssessmentRepository.saveStudentAssessment` calculates and
writes a result from the device directly to Firestore. The Cloud Function calculates
and verifies the same assessment only in staging. Firestore rules also permit an owner
to create an assessment document.

**Risk:** a modified client can write arbitrary scores, statuses, explanations, or
question versions. Flutter and TypeScript can also produce different results over time.

**Required decision:** Full and Quick submissions must go through one callable Cloud
Function in every production environment. Firestore clients may read their own result,
but must not create, update, or delete assessment-result documents. The server stores
the derived result and item snapshots.

### 2. The version field cannot select a historical catalog — critical

The function accepts answers only for the global active catalog. A request does not
carry an expected instrument version, and `validateFullAnswers` always validates the
current catalog. The migration path also recalculates non-v1 records using the current
catalog.

**Risk:** when v4 replaces v3, an old v3 payload cannot be reliably replayed; a
historical result may be recalculated with new wording, directions, or thresholds.

**Required decision:** create an immutable catalog registry. Every submission must
include `instrumentVersion`; the server must accept only the currently enabled version
for a *new* submission, while the renderer resolves historic records from the version
stored on that record. Never recalculate v3 as v4.

### 3. Answer codes and displayed labels disagree — high

The code maps `never/rarely/often/always` to 1–4 but displays those choices as
`Strongly Disagree/Disagree/Agree/Strongly Agree`. The proposed v4 statements are
agreement statements, so frequency code names must not remain in the data model.

**Required v4 response contract:**

| `responseCode` | Label | `responseValue` |
| --- | --- | ---: |
| `stronglyDisagree` | Strongly disagree | 1 |
| `disagree` | Disagree | 2 |
| `agree` | Agree | 3 |
| `stronglyAgree` | Strongly agree | 4 |

`responseCode`, not the label, is authoritative. The v3 mapper remains unchanged for
historic records.

### 4. Current status and priority logic conflict with v4 — high

Current code has three overlapping vocabularies: `Thriving/Stable/Needs
Improvement/At Risk`, concern bands `Low/Watchful/Moderate/Elevated/High`, and
response-pattern labels. Its hard-coded functional-impact IDs refer to v3 items.

The v4 proposal instead describes `Supported at present`, `Mostly supported; some
areas to explore`, `Some strain indicated`, and `Support may be helpful`. The exact
precedence, boundaries, and item-to-construct references are not yet encoded.

**Required decision:** v4 must have one user-facing domain-status enum and a separate
internal `priority` enum. Neither may use a clinical label or diagnosis.

### 5. Quick Assessment has no history and is not yet specified for v4 — high

Quick data uses one document ID, `quick_{uid}`. A different later response is rejected,
not stored as a new check-in. It uses a separate five-point/variable-option model and
still includes a Neutral choice for social connection.

**Required decision:** define Quick independently as `quick_checkin_v3` (or retain
`quick_v2` unchanged). If history is required, write one immutable document per
submission. Do not combine a Quick result mathematically with a Main result.

### 6. The report derives non-assessment mental-status fields — medium

The current Mental Health Summary UI primarily shows assessment explanations, but its
report generator and admin status also derive `mentalStatus` from mood, engagement,
and assessment fields. That conflicts with the requested assessment-only summary.

**Required decision:** the student Mental Health Summary must render the latest stored
assessment explanation verbatim (one full card and, separately, one quick card). It
must not create an additional overall mental-status label from mood or engagement.

## Required v4 Firestore contract

One document in `assessments/{assessmentId}` represents one immutable submission.
Fields under `result`, `interpretation`, and `itemSnapshot` are server-written only.

```text
assessmentId: "full_{uid}_{uuid}"
schemaVersion: "assessment_record_v4"
userId: string
assessmentKind: "full" | "quick"
populationRole: "student" | "teaching" | "nonTeaching"
submittedAt: server timestamp
createdAt: server timestamp

instrument: {
  family: "student_wellbeing_reflection"
  version: "student_wellbeing_v4"
  catalogHash: string                 // SHA-256 of canonical server catalog
  recallPeriodDays: 7
  responseScaleId: "agreement_4_no_neutral_v1"
  algorithmVersion: "student_profile_v4"
}

responses: [{
  itemId: "student_v4_academic_01"
  responseCode: "stronglyDisagree" | "disagree" | "agree" | "stronglyAgree"
  responseValue: 1 | 2 | 3 | 4
  skipped: boolean
}]

itemSnapshot: [{
  itemId: string
  domainId: "academic" | "financial" | "socialAdjustment" | "sleepRest" | "emotionalWellbeing"
  displayOrder: 1..50
  direction: "risk" | "protective"
  constructId: string
  text: string
}]

result: {
  profileStatus: "generallySupported" | "mostlySupported" | "someAreasNeedAttention" | "supportMayHelp" | "insufficientResponses"
  domainResults: [{
    domainId: string
    status: "supported" | "mostlySupported" | "someStrain" | "supportMayHelp" | "insufficientResponses"
    answeredCount: integer
    presentedCount: 10
    completionPercent: number
    isScorable: boolean
    internalConcern: number | null     // authorized staff only; never render to student
    focusConstructIds: string[]
    strengthConstructIds: string[]
  }]
  responseQuality: { answered, presented, skipped, completionPercent, confidence }
}

interpretation: {
  studentSummary: string
  rationale: string[]
  focusInsights: string[]
  strengthInsights: string[]
  suggestedActions: string[]
  followUpGuidance: "routine" | "monitor" | "considerSupport" | "timelySupport" | "moreResponsesNeeded"
  disclaimer: string
}

calculationAuthority: "server"
verificationStatus: "verified"
```

Do not store a user-facing status as the only output. Store the version, catalog hash,
answer codes, and item snapshot required to reproduce that exact historical result.

## Exact v4 item ID and ordering contract

```text
student_v4_academic_01 … student_v4_academic_10
student_v4_financial_01 … student_v4_financial_10
student_v4_social_adjustment_01 … student_v4_social_adjustment_10
student_v4_sleep_rest_01 … student_v4_sleep_rest_10
student_v4_emotional_wellbeing_01 … student_v4_emotional_wellbeing_10
```

The ordering is fixed by the proposal document. IDs never change, are never reused,
and must be stored with their `displayOrder`, `domainId`, direction, construct ID, and
text snapshot. v3 IDs and labels remain available in a `v3` catalog adapter.

## Exact v4 calculation contract

1. Reject a new full submission unless it contains exactly the 50 item IDs for
   `student_wellbeing_v4`, each once, with a legal response code or explicit skip.
2. Convert value: `stronglyDisagree=1`, `disagree=2`, `agree=3`,
   `stronglyAgree=4`.
3. Compute concern per answered item:
   - risk: `((value - 1) / 3) * 100`
   - protective: `100 - ((value - 1) / 3) * 100`
4. A domain is scorable only when at least 7 of its 10 items are answered. Its internal
   concern is the arithmetic mean of its answered items, rounded only for storage.
5. Domain status boundaries (provisional, pending pilot calibration):
   - `0–25`: `supported`
   - `>25–50`: `mostlySupported`
   - `>50–75`: `someStrain`
   - `>75–100`: `supportMayHelp`
6. Profile status must be rule-based, not the equal-weight mean:
   - any `supportMayHelp` → `supportMayHelp`
   - else two or more `someStrain` → `someAreasNeedAttention`
   - else one `someStrain` or any `mostlySupported` → `mostlySupported`
   - else all five `supported` → `generallySupported`
   - any unscorable domain → `insufficientResponses`; still show scorable domain cards.
7. Completion confidence is separate from status: `high` at 90–100% completed,
   `usableWithCaution` at 70–89%, otherwise `limited`.

The proposed status bands are presentation policy, not validated clinical cutoffs. The
record must mark them `provisional_pending_local_validation` until the release gate in
the v4 proposal is complete.

## Exact focus and strength extraction contract

The catalog must attach one `constructId` to each item (for example,
`academic_deadlines`, `financial_school_costs`, `sleep_daytime_alertness`). Never show
raw answer text as a student insight.

1. **Focus candidates:** risk item concern ≥66.67, or protective item concern ≥66.67
   after reverse scoring. Group by domain and `constructId`.
2. **Strength candidates:** protective item concern ≤33.33. Group by domain and
   `constructId`.
3. Per domain, select the construct with the highest mean concern for focus and the
   lowest mean concern for strength. Resolve ties by lower `displayOrder`.
4. Across domains, select at most three focus insights ordered by domain concern
   descending, then domain display order; select at most two strengths ordered by
   domain concern ascending, then domain display order.
5. Do not show a strength and focus insight for the same construct. Use approved
   templates keyed by `(domainId, constructId, status)`, reviewed by PACC.
6. Suggested actions are template-based, optional, non-diagnostic, and must never
   claim that an appointment was created or a counselor was notified.

## Exact student-facing Summary UI contract

Use the existing card-based design. Replace only data/text bindings.

1. **Hero:** “Assessment complete” → “Your well-being profile” → profile-status chip.
   No numeric score, ring percentage, severity, or diagnosis.
2. **How this was formed:** “Based on your answers from the past 7 days. We gave
   added attention to [up to three focus domains] because their responses showed
   [domain statuses]. [strength domains] showed supportive patterns.”
3. **Response confidence:** answered/presented and confidence label; explain that
   skipped questions are excluded.
4. **Your strengths:** at most two template-based strengths.
5. **Areas to explore:** at most three template-based focus insights.
6. **Well-being areas:** five cards in fixed order. Each shows the domain label,
   domain-status chip, one interpretation, and one optional practical action. No bar
   whose length implies a score.
7. **Support options:** optional appointment decision shown before the result is
   unlocked; a refusal never blocks the result.
8. **Disclaimer:** “This is a 7-day reflection profile, not a diagnosis. It is meant
   to support reflection and a conversation with a qualified professional if desired.”
9. **Mental Health Summary:** render the latest immutable Full result and latest
   immutable Quick result as separate cards, including date, instrument version, recall
   period, summary, strengths, focus, rationale, and domain/indicator statuses. It
   must not recompute them from current code or merge their scores.

## Historical handling and migration contract

- Retain every v1/v3 record exactly as submitted and display it with its original
  version label and stored explanation.
- Do not rename v3 `Financial Well-Being` inside historical records; v4 alone uses
  `Financial`.
- Do not backfill v4 fields into v3 records and do not run v3 records through the v4
  calculator.
- Add `catalogHash` and item snapshots only for new v4 submissions; legacy records
  are marked `historical_unversioned` or their known historic version.
- Migration must be idempotent and append migration metadata; it must never overwrite
  raw responses or prior result fields.
- Admin history must display `submittedAt`, assessment kind, instrument version,
  verification status, and the original stored result.

## Required implementation tests

1. Flutter and Functions share one canonical catalog fixture and produce identical v4
   domain/profile statuses for every response combination used in tests.
2. Reject a duplicate/missing/unknown/out-of-version item ID and a response code/value
   mismatch.
3. Test every risk/protective conversion, all status boundaries, 7/10 completion,
   skips, tie ordering, focus/strength exclusions, and each profile-status rule.
4. Verify v3 record rendering remains unchanged after v4 is enabled.
5. Verify only the server can create v4 assessment results and tampered client result
   fields are ignored.
6. Verify full and quick histories each retain multiple submissions, and the Mental
   Health Summary selects their latest documents by server timestamp.
7. Verify the completion screen and Mental Health Summary display no score,
   percentage ring, diagnostic language, or combined quick/full calculation.

## Files that must change after approval

- `functions/src/assessment/catalog.ts`
- `functions/src/assessment/calculator.ts`
- `functions/src/assessment/submissions.ts`
- `functions/src/assessment/migrate.ts`
- `firestore.rules`
- `contracts/assessment_question_ids.v4.json` (new canonical contract)
- Flutter assessment models, catalog, calculator, repository, result screen, report
  repository/model, admin assessment detail, and contract/unit/widget tests.

No code changes should begin until the response vocabulary, provisional v4 statuses,
Quick-history decision, and server-only submission rule are approved.
