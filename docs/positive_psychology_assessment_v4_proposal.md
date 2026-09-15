# Positive Psychology-Informed Assessment v4 Proposal

## Decision status

**Draft only — do not release or describe as a validated psychological test.** This
document defines a proposed replacement question bank for the student Main
Assessment. It is suitable for expert review and a pilot, not for silently replacing
the current production instrument.

The source supplied for this review is *Positive Psychology: Theory, Research and
Applications* (Hefferon & Boniwell, McGraw-Hill, 2011). It is an academic source for
positive emotion, subjective and eudaimonic well-being, social connection, strengths,
and the context of financial well-being. It explicitly distinguishes reliability from
validity and lists content, construct, criterion, and factorial validity as necessary
questions for a questionnaire. It is **not** a validated five-domain, 50-item student
screening tool, and its copyrighted questionnaires must not be copied into the app.

The proposal therefore uses original, plain-language items informed by those
constructs. It must be called a *university well-being reflection profile* until the
validation work below is complete.

## What changes from v3

1. Keep exactly five student domains and exactly ten items per domain (50 total).
2. Rename **Financial Well-Being** to **Financial**. Its items assess practical
   study-related financial conditions; they do not claim to measure a person's whole
   financial well-being.
3. Remove cross-domain wording. For example, academic items no longer ask about
   sleep, and financial items no longer ask about emotional well-being.
4. Use one instruction before every domain: **“Think about the past 7 days. Choose
   the answer that best describes your experience.”**
5. Retain the existing forced four-choice response scale with no Neutral response:
   **Strongly disagree, Disagree, Agree, Strongly agree.**
6. Use new, versioned IDs (`student_v4_*`) and retain all v3 question text, answers,
   calculations, and reports unchanged for historical records.

## Proposed student item bank

Each statement belongs only to the domain shown. Items marked `P` are protective;
items marked `R` describe current strain. The marker is implementation metadata and
must not be shown to respondents.

### 1. Academic

1. `P` I could organize my academic tasks into a workable plan.
2. `P` I had enough time to complete the academic work I scheduled.
3. `R` I felt overwhelmed by the amount of academic work expected of me.
4. `R` I found it difficult to begin academic work I had planned to do.
5. `R` I found it difficult to keep up with academic deadlines.
6. `P` I could stay focused while doing academic work.
7. `P` I knew where to get academic help when I needed it.
8. `R` I felt pressure about my academic performance.
9. `P` I could regain my focus after an academic setback.
10. `R` Academic demands made it hard for me to stay motivated to learn.

### 2. Financial

1. `P` I could meet my essential study-related costs.
2. `P` I had access to the learning materials required for my studies.
3. `R` Unexpected study-related costs were hard for me to manage.
4. `P` I knew where to find financial-aid or payment-support information.
5. `P` I had a workable plan for upcoming education expenses.
6. `R` I worried that I might not be able to pay essential school fees.
7. `R` I had to delay or miss a study requirement because of cost.
8. `P` I could keep track of money set aside for school needs.
9. `P` I could cover the transport, data, food, or other basic costs needed for study.
10. `R` I found it hard to manage financial obligations related to school.

### 3. Social Adjustment

1. `P` I felt that I belonged in the university community.
2. `P` I had at least one peer at the university I could talk with if I chose to.
3. `P` I felt accepted by peers in my university setting.
4. `P` I was comfortable asking a peer for practical help when I needed it.
5. `P` I could communicate my needs or boundaries with peers.
6. `R` I avoided peer interaction because I expected that I would not fit in.
7. `P` I had opportunities to connect with peers in ways that suited me.
8. `R` I felt left out of peer or university activities that I wanted to join.
9. `P` I knew a person or university office I could approach for support.
10. `P` I could maintain social connections that mattered to me while studying.

### 4. Sleep and Rest

1. `P` I was able to fall asleep in a reasonable amount of time.
2. `R` I woke during sleep and found it difficult to return to sleep.
3. `P` I got enough sleep to feel rested the next day.
4. `P` I woke feeling refreshed.
5. `P` My sleep and wake times were close to the schedule I intended.
6. `R` I struggled to stay awake during the day because I had not slept enough.
7. `R` Worrying thoughts made it hard for me to fall asleep.
8. `P` I had enough opportunity to rest when I needed it.
9. `P` I was satisfied with the quality of my sleep.
10. `P` I was able to set aside time to wind down before sleep.

### 5. Emotional Well-Being

1. `P` I felt cheerful or in good spirits.
2. `P` I felt calm and settled.
3. `P` I felt interested in my day-to-day activities.
4. `P` I felt able to handle everyday frustrations.
5. `P` I could recognize what I was feeling.
6. `P` I felt hopeful about the near future.
7. `R` I felt emotionally drained.
8. `R` I felt overwhelmed by everyday emotional demands.
9. `P` I could regain emotional balance after an ordinary setback.
10. `P` I felt satisfied with my current emotional well-being.

## Summary-generation design

The app should use the numbers only internally. It should never show a score,
percentage, diagnosis, or clinical cutoff to a student.

### Domain status

For implementation, convert each answer to a concern value: `R` items use
`0, 33.33, 66.67, 100`; `P` items use the reverse. Average the ten answered items
only after the agreed completion rule is met. Until calibration, translate the internal
result into these non-diagnostic descriptions:

| Internal concern band | Student-facing domain status |
| --- | --- |
| 0–25 | Supported at present |
| >25–50 | Mostly supported; some areas to explore |
| >50–75 | Some strain indicated |
| >75–100 | Support may be helpful |

These are provisional presentation bands, not norms or clinical severity levels.
They must be reviewed after piloting; a forced four-choice scale cannot be claimed to
have validated cutoffs merely because it has no Neutral option.

### Overall profile

Do **not** call an equal-weight average a mental-health score. Generate a profile
from the domain statuses instead:

1. If any domain is `Support may be helpful`, show **“Support may be helpful right
   now.”**
2. Otherwise, if two or more domains show `Some strain indicated`, show **“Some
   areas may benefit from attention.”**
3. Otherwise, if one domain shows `Some strain indicated` or any domain is `Mostly
   supported`, show **“Mostly supported, with an area to explore.”**
4. Otherwise, show **“Well-being appears generally supported.”**

The existing Summary UI can keep its cards and visual hierarchy, but its explanation
must state the evidence in plain language:

> This is a snapshot of the past 7 days, based on the areas you answered. Your
> current profile gives added attention to **[domain names]** because responses in
> those areas showed **[status]**. **[strength domains]** showed supportive patterns.
> This is not a diagnosis.

Show at most three focus domains and two strengths. Under each focus domain, name
the construct—not the raw score—for example “deadlines and workload planning” or
“access to study-related costs.” The counsellor/admin result may show the version,
completion, domain status, item IDs, and response pattern; it must not infer a disorder.

### Quick Assessment

The Quick Assessment should remain a separate, explicitly labelled 5-item check-in.
It must not be mathematically combined with a Main Assessment. Its result can say
“quick check-in pattern” and name the domains it flagged; the Mental Health Summary
should label whether its current profile comes from a Quick Assessment or a Main
Assessment, with the completed date and questionnaire version.

## Required validation and release gate

1. Obtain written review of content, language, response options, referral wording,
   and data handling from PACC/counselling, a qualified psychologist, student
   representatives, and the university ethics/privacy owner.
2. Conduct cognitive interviews with target users to test whether every statement is
   understood as intended and is culturally appropriate.
3. Pilot the versioned instrument before making decisions from it. Assess missingness,
   floor/ceiling effects, reliability, factor structure, and associations with suitable
   established measures; predefine how bands will be revised.
4. Do not apply WHO-5, PROMIS, PSQI, CFPB, DASS, or another instrument's items,
   thresholds, or interpretation to this custom bank. Their wording, recall period,
   response scale, population, and scoring must be retained exactly if they are used.
5. Preserve v3 history. New completions use `student_wellbeing_v4`; reports display
   their original questionnaire version and are never recalculated as v4.
6. For each release, test client/server catalog parity, 50 ordered IDs, response
   direction, status mapping, historical rendering, admin history, and the appointment
   prompt. Do not activate crisis or self-harm screening without the separate approved
   safety protocol.

## Sources used

- Hefferon, K. & Boniwell, I. (2011), *Positive Psychology: Theory, Research and
  Applications*, supplied PDF: theory, constructs, measurement cautions, and
  strengths-based framing.
- [WHO-5 official publication](https://www.who.int/publications/m/item/WHO-UCN-MSD-MHE-2024.01): an example of a distinct validated well-being measure with five
  exact statements, a two-week recall period, and a six-point scale—not a cutoff to
  copy into this proposal.
- [HealthMeasures PROMIS electronic administration guidance](https://www.healthmeasures.net/explore-measurement-systems/promis/obtain-administer-measures): an
  example of why validated measures require approved digital presentation and their
  own scoring.
- [COSMIN content-validity methodology](https://www.cosmin.nl/wp-content/uploads/COSMIN-methodology-for-content-validity-user-manual-v1.pdf): framework for
  relevance, comprehensiveness, and comprehensibility review.
