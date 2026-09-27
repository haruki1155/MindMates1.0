# Full Assessment Result V4 design

## Purpose and scope

Extend the staging V4 Full Assessment result for Student, Teaching, and
Non-Teaching users. The result must explain a completed 50-question,
five-domain assessment from the server-authoritative V4 record, without
changing scoring, persistence authority, or any appointment, report, Mental
Health Summary, counselor, or production behavior.

The screen is a **Full Assessment Result**, not merely a profile. Its main
title is **Your Full Well-Being Assessment Result**.

## Boundaries

The server calculates and persists interpretation fields. Flutter renders the
returned record only; it must not rescore answers, derive domain statuses, or
reconstruct historical questions from the current catalog.

Historical response review joins immutable `itemSnapshot` and `responses` by
`itemId`, groups records by saved `domainId`, and sorts by saved
`displayOrder`.

Existing Student `studentSummary` remains for compatibility. The UI resolves
`userSummary ?? studentSummary`. Existing response normalization, domain
thresholds, profile precedence, focus and strength selection, completion
rules, server persistence, and V4 question sets remain unchanged.

## Server result contract

All three V4 calculators will retain their current result fields and add:

- `instrument.referenceSetVersion: mindmate_wellbeing_refs_v1`
- `interpretation.userSummary`
- `interpretation.overallResponseSummary`
- `interpretation.domainSummaries`

`domainSummaries` always has five entries, in stored role-specific domain
order. Each entry has `domainId`, `domainLabel`, `status`, `summary`,
`focusInsight`, `strengthInsight`, and `suggestedAction`; optional insight and
action values may be null.

The server creates the new summaries deterministically from the existing
`profileStatus`, `domainResults`, focus and strength patterns,
`responseQuality`, and population role. It does not use raw-answer prose,
current time, a remote service, or generative AI. The overall summary explains
the cross-domain pattern and response completeness rather than repeating the
status label.

Teaching and Non-Teaching summaries retain role-specific language and the
non-performance framing. Student summaries remain non-diagnostic.

## Result UI

The completion screen renders the saved callable payload in this order:

1. Overall Well-Being Status
2. Assessment Summary
3. What Your Responses Suggest Overall
4. Well-Being Areas with five domain summaries
5. Strengths
6. Areas to Explore
7. Suggested Next Steps
8. Assessment Responses
9. Response Completeness
10. How This Result Was Created
11. References & Resources
12. Non-Clinical Disclaimer

The header identifies completion date, role-aware assessment label, and the
seven-day recall period. The normal user interface never exposes internal
concern values, raw response values, risk/protective direction, catalog hash,
or any numeric overall score.

Response review uses accessible expandable domain sections. It maps response
codes to human-readable labels and renders skipped responses as **Not
answered**. It has no scoring logic and is reusable without adding Counselor
or Admin integration in this scope.

Methodology reveals 50 questions, five domains, seven-day recall period,
four-point agreement scale, server-authoritative deterministic calculation,
instrument version, algorithm version, and `assessment_record_v4`. It states
that generative AI is not used to determine the result.

References identify Hefferon and Boniwell (2011), *Positive Psychology:
Theory, Research and Applications*, Open University Press, as a conceptual
and questionnaire-design reference. They explicitly state that MindMate V4 is
a custom university well-being reflection and make no clinical-validation
claim. The final disclaimer stays non-clinical; employee roles additionally
state that the result is not a job-performance or fitness-for-work evaluation.

## Proposed file map

| File | Responsibility |
| --- | --- |
| `functions/src/assessment/student_v4_calculator.ts` | Add deterministic Student interpretation and reference metadata. |
| `functions/src/assessment/workplace_v4_calculator.ts` | Add deterministic Teaching/Non-Teaching interpretation and reference metadata. |
| `lib/features/student_assessment/screens/student_assessment_complete_screen.dart` | Render the complete server-authoritative result hierarchy. |
| `lib/features/student_assessment/widgets/v4_assessment_response_review.dart` | Render snapshot-plus-response review with grouping, order, and label mapping only. |
| `functions/src/assessment/student_v4_calculator.test.ts` | Test Student contract completeness and determinism. |
| `functions/src/assessment/workplace_v4_calculator.test.ts` | Test workplace role labels, contract completeness, and determinism. |
| `test/features/student_assessment/student_v4_completion_test.dart` | Extend result-screen coverage. |
| `test/features/student_assessment/workplace_v4_assessment_test.dart` | Add teaching/non-teaching result rendering and response-review coverage. |
| `test/features/student_assessment/v4_assessment_response_review_test.dart` | Verify snapshot join, ordering, grouping, labels, skipped state, and historical text. |

No report, appointment, authentication, Mental Health Summary, counselor, or
production files are in scope.

## Acceptance and validation

Focused tests will prove each calculator produces exactly five deterministic
domain summaries, preserves Student compatibility fields, and keeps
role-specific labels. Widget tests will cover all required sections, all three
roles, response-review expansion, historical snapshot text, readable labels,
and absence of forbidden score/risk language.

Validation will run focused Functions tests, the Functions TypeScript build,
focused Flutter tests, and `flutter analyze`. A separate final staging APK
verification will use Student, Teaching, and Non-Teaching accounts. Production
will not be deployed.
