# Assessment V4 staging acceptance

Accepted on: 2026-09-28 (Asia/Shanghai)

## Scope

Student, Teaching, and Non-Teaching V4 full-assessment paths were accepted in
`mindmate-staging`. Production was not changed.

## Deployed Functions

| Function | State | Revision | Source hash |
| --- | --- | --- | --- |
| `submitFullAssessment` | ACTIVE | `submitfullassessment-00012-dar` | `78014a31790b74588681d4319344ec978009d5eb` |
| `submitFullAssessmentDev` | ACTIVE | `submitfullassessmentdev-00016-dej` | `78014a31790b74588681d4319344ec978009d5eb` |

The staging APK routes to `submitFullAssessmentDev`; that function was
explicitly verified on the accepted V4 backend revision.

## APK evidence

Build command:

```powershell
flutter build apk --debug --flavor staging --dart-define=APP_ENV=staging
```

Artifact: `build/app/outputs/flutter-apk/app-staging-debug.apk`

SHA-256: `FB6828BE09DB1D1F4141E3FF37EE9EE8AB612C67F80D837301BDE89DEF9C6E15`

## End-to-end acceptance

| Role | Outcome |
| --- | --- |
| Student | Student V4 regression path passed: 50 responses, server-calculated V4 record, V4 profile, and Mental Health Summary. |
| Teaching | Teaching V4 passed: 50/50 responses submitted through `submitFullAssessmentDev`, V4 Work Well-Being Profile rendered, and Mental Health Summary read the V4 summary. |
| Non-Teaching | Non-Teaching V4 passed: 50/50 responses submitted through `submitFullAssessmentDev`; the profile rendered strengths, areas to explore, and suggested actions. |

The completion-lifecycle test also confirmed that a secondary report refresh
failure after a verified callable save does not replace the success profile
screen with a submission failure.

## Verified Firestore V4 record

The accepted Non-Teaching record contained:

- `schemaVersion: assessment_record_v4`
- `populationRole: nonTeaching`
- `questionSetVersion: non_teaching_workplace_reflection_v4`
- `serverAlgorithmVersion: non_teaching_profile_v4`
- nested instrument version and catalog hash
- server-calculated `result.profileStatus` and five `result.domainResults`
- `interpretation.userSummary`
- focus insights, strength insights, suggested actions, and follow-up guidance
- server-side item snapshot and verification/status metadata

Mental Health Summary displayed the record's V4 `interpretation.userSummary`,
including the workplace/job-performance disclaimer, with no V3 fallback.

## Validation commands

```powershell
flutter analyze
flutter test --dart-define=APP_ENV=staging test/features/student_assessment/student_v4_completion_test.dart test/features/student_assessment/workplace_v4_assessment_test.dart
npm.cmd --prefix functions run build
node --test functions/lib/assessment/student_v4_calculator.test.js functions/lib/assessment/workplace_v4_calculator.test.js
```

All commands passed during the staging acceptance run.

## Boundary

Production promotion: **NOT PERFORMED**.

This is a technical staging acceptance record. Local/pilot instrument
validation remains a separate product and psychometric gate before any
production promotion.

## Phase 8.1 local milestone and TECNO UX acceptance

Validated local checkpoint: `193d1eae7fd257d343114d223cc50bac14462f1b`
(`assessment-v4-phase8.1-local-193d1e`). This is a local milestone tag only;
it has not been pushed, merged, or deployed.

The complete staging Flutter regression run passed **552 tests**. The focused
TECNO CN5 staging build check confirmed the authenticated Student V4 path:

- the preview-loading view appears while a completed category is reviewed,
  rather than authorizing or saving a final submission;
- non-eligible category previews advance to the following category;
- eligible Social Adjustment and Emotional Well-Being previews show the
  optional activity decision, and declining safely continues the Assessment;
- the final review displays 50/50 answers, five completed categories, a
  collapsed **About this assessment** disclosure, and a distinct explicit
  **Submit assessment** action.

No final submission was selected during this acceptance check. The TECNO
device currently retains its synthetic, in-progress Review Assessment session
for separate disposition; this record does not authorize modifying it.

### Remaining Gate B acceptance work

The Phase 8.1 loading and final-review UX is physically accepted. The following
items remain open and must not be inferred from this milestone:

- complete physical verification of each intervention activity and its
  controls, including Walking sensor/fallback behavior;
- Teaching and Non-Teaching device acceptance;
- saved-result presentation and conditional PACC prompt lifecycle acceptance;
- final persistence and other-role acceptance evidence.

Assessment staging acceptance is not production readiness. Production
promotion remains **NOT PERFORMED**.
