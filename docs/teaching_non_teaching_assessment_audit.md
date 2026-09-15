# Teaching and Non-Teaching Assessment Audit

## Outcome

**Do not revise or relabel these as validated mental-health assessments.** Both are
currently experimental, role-specific workplace well-being reflections. They share the
same implementation and historical-record gaps identified in the student v4 contract
audit, and they add employee privacy and workplace-power risks that require a separate
release gate.

## Current active assessment structure

Both roles have 50 active questions: five domains with ten items each. The ten older
“deeper” workplace questions remain in source files but are conditional and excluded
from the active 50-item assessment and its score.

| Role | Active domain 1 | Active domain 2 | Active domain 3 | Shared domain 4 | Shared domain 5 |
| --- | --- | --- | --- | --- |
| Teaching Personnel | Workplace Stress | Professional Support | Professional Well-Being | Sleep and Rest | Emotional Well-Being |
| Non-Teaching Personnel | Workplace Responsibilities | Workplace Support | Workplace Well-Being | Sleep and Rest | Emotional Well-Being |

The active v3 IDs are:

```text
Teaching:
faculty_workplace_core_01…10
faculty_support_01…10
faculty_wellbeing_01…10
common_sleep_01…10
common_emotional_01…10

Non-Teaching:
staff_responsibility_core_01…10
staff_support_01…10
staff_wellbeing_01…10
common_sleep_01…10
common_emotional_01…10
```

The client, Cloud Functions, and v3 ID contract presently agree on the count and
ordering. They are still maintained in separate source files, so parity is tested but
not structurally guaranteed.

## Audit findings

### A. Question-bank and construct audit

| Finding | Teaching Personnel | Non-Teaching Personnel | Severity |
| --- | --- | --- | --- |
| No stated recall period | The UI does not tell respondents whether to answer for today, the last week, or the last 14 days, although the interpretation says 14 days. | Same. | High |
| Mixed constructs in workplace-pressure domain | Workload, administration, work–life balance, personal life, exhaustion, sleep, and feeling valued are averaged as one score. | Workload, pace, personal life, physical/mental exhaustion, sleep, and worry are averaged as one score. | High |
| Overlap with emotional and sleep domains | `mentally exhausted after work`, `workplace concerns affect my sleep`, and work–life balance overlap with the shared Sleep/Emotional domains. | The same overlap, plus physical exhaustion. | High |
| Well-being domain overlap | Stress management, emotional balance, energy, recovery, and overall health duplicate the shared Emotional and Sleep domains. | Same. | High |
| Support domain is broad | Department support, respect, recognition, policy, leadership, peers, resources, feedback, and help-seeking are all treated as one construct. | Supervisor/coworker support, voice, respect, resources/training, feedback, and help-seeking are treated as one construct. | Medium |
| No “not applicable” response | A forced agreement answer is required for policies, leadership, feedback, resources, team support, and work–life items even when the statement cannot apply. A Neutral response is not required, but an explicit non-scored `notApplicable`/skip choice must be considered. | Same. | High |
| Vague or double-barrelled statements | “My workload is manageable,” “I maintain work-life balance,” and “My work routine supports my overall health” leave the construct and time frame open. | “Workplace demands affect my well-being,” “My work routine supports my overall health,” and similar items are broad. | Medium |
| Dead conditional item bank | Ten conditional items are retained but never presented by the active catalog, despite trigger code existing in Flutter. | Same. | Medium |

### B. Scoring and result audit

The shared full-assessment calculation is technically deterministic:

```text
answer values: never=1, rarely=2, often=3, always=4
risk concern:       ((value - 1) / 3) * 100
protective concern:  100 - ((value - 1) / 3) * 100
domain:              mean of answered active items
overall:             equal 20% mean of all five domains
```

However, the UI displays the same four codes as **Strongly Disagree, Disagree, Agree,
Strongly Agree**. The stored frequency code names and shown agreement labels conflict.

The current result uses:

| Internal concern | Current status | Current student-facing response pattern |
| ---: | --- | --- |
| 0–20 | Thriving | Thriving patterns |
| >20–40 | Stable | Balanced patterns |
| >40–60 | Needs Improvement | Areas to strengthen |
| >60 | At Risk | Support may be useful |

These are internal product thresholds; there is no documented validation source for
the role-specific question wording, equal weights, score boundaries, or follow-up
rules. For employees, labels such as **At Risk** should not be used as workplace or
performance conclusions.

Specific scoring issues:

1. A domain is eligible with only 7 of 10 responses, but the overall result is
   unavailable if any of the five domains is ineligible. The UI must clearly distinguish
   an unavailable overall profile from the available domain cards.
2. Functional-impact priority flags are hard-coded to selected workplace-core and
   shared sleep IDs. The support and role-well-being domains do not contribute
   functional flags, even where they indicate a serious workplace concern.
3. The priority rules, domain status, response pattern, and concern band are four
   overlapping ways of describing the same result. This makes summaries hard to audit.
4. The server and Flutter both calculate results. In non-staging production, the
   client can write its result directly to Firestore; the server is not the sole
   calculation authority.
5. `recallPeriodDays` is stored as 14 in the calculated interpretation, but the
   question screen does not show that recall period.

### C. Summary and presentation audit

The existing result screen has the right basic components: overall profile, response
confidence, support option, strengths, focus areas, domain cards, disclaimer, and an
appointment prompt. The shared role implementation nevertheless has these gaps:

- Role summaries use generic fallback narratives for workplace domains rather than
  approved role-specific explanations.
- Focus/strength text is derived from raw item direction and broad score thresholds;
  it has no construct map such as `workload`, `role_clarity`, `supervisory_support`,
  or `recovery`.
- The Mental Health Summary can show latest full and quick assessments, but report
  generation still calculates a separate `mentalStatus` from mood and engagement.
  That must not become an employee mental-health label.
- The summary does not show the instrument version to the employee or administrator.
- Old and new results would share current labels if the catalog changes, rather than
  being rendered from a stored historical item/result snapshot.

## Employee privacy and governance: critical requirements

Teaching and non-teaching results require a stronger boundary than student wellness
reflections. A university or supervisor must never use individual results for
performance management, discipline, promotion, workload allocation, or employment
decisions.

Before release, require written approval for:

1. Purpose limitation: the assessment is an optional well-being reflection, not an
   employee evaluation or diagnostic screen.
2. Informed consent: explain what is collected, who can see it, the purpose, retention
   period, whether participation is voluntary, and that non-participation has no work
   consequence.
3. Access control: direct supervisors, department heads, and HR performance users
   must not see identifiable individual answers/results. Only named wellbeing/counsel
   staff with a documented need should have access.
4. Aggregation: leaders may receive only small-cell-suppressed, de-identified trend
   reports after privacy review—not row-level data.
5. Confidential referral: optional support must not notify a manager, and appointment
   booking must be separate from workplace reporting.
6. Data protection: retention, deletion, audit log, breach handling, and an access
   review schedule must be explicitly defined.

## Required role-specific v4 contract

Apply the server-only, immutable-record, catalog-hash, response-code, and historical
version requirements from `assessment_v4_implementation_contract_audit.md` to these
two instruments. Do not reuse `student_wellbeing_v4`.

Use separate instrument identities:

```text
teaching_workplace_reflection_v4
non_teaching_workplace_reflection_v4
```

Each has its own catalog hash, item IDs, approved wording, recall period, and summary
templates. A record must state its role and instrument version; common sleep/emotional
text may be shared only as copied item revisions with role-specific IDs, not as an
unversioned global ID.

### Recommended clean domain model for review

This is a construct map for expert review, not a proposed validated instrument:

| Teaching Personnel | Non-Teaching Personnel |
| --- | --- |
| Teaching Workload and Role Demands | Workload and Role Demands |
| Organizational and Colleague Support | Supervisor, Team, and Organizational Support |
| Professional Engagement and Recovery | Work Engagement and Recovery |
| Sleep and Rest | Sleep and Rest |
| Emotional Well-Being | Emotional Well-Being |

Each domain should contain only items that measure its named construct. For example,
sleep should not be part of workload scoring, and emotional balance should not be
scored both under work well-being and emotional well-being.

## Required before any implementation

1. Approve an employee privacy/governance protocol and role-based access matrix.
2. Decide whether `notApplicable` is an explicit non-scored response or an optional
   skip, and update domain completion rules accordingly.
3. Choose one visible recall period, ideally the same throughout the role instrument.
4. Approve the v4 construct map and revised, single-construct role-specific questions.
5. Replace current status labels with non-diagnostic workplace reflection statuses.
6. Make the Cloud Function the only writer of assessment results; lock down Firestore
   client writes.
7. Store immutable response/item/result snapshots and never recalculate old versions.
8. Conduct content review with teaching/non-teaching representatives, PACC/qualified
   psychology reviewers, HR/privacy, and ethics/governance stakeholders before a
   pilot.
9. Pilot separately by role; do not assume student, teaching, and non-teaching
   wording or thresholds perform the same way.

## Verification required after approval

- 50 active items exactly, five fixed domains, ten items per domain, in fixed order.
- No active item contributes to two domain scores.
- Client/server catalog parity and canonical-contract tests.
- Boundary, skip/not-applicable, priority, focus/strength, and historical-version
  tests for both roles.
- Tests proving a manager cannot read individual employee assessment documents.
- Tests proving the employee-facing Mental Health Summary renders stored results only
  and does not derive an additional workforce mental-status label.
