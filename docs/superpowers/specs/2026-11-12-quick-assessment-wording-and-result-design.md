# Quick Assessment — Wording (Item 36) and Result Redesign (Item 37) — Design

**Date:** 2026-11-12 · **Branch:** `feat/quick-assessment-36-37` (from `main` @ `0d0b7c9`)
**Source:** thesis panel comments, items 36 and 37.

## 1. Intent and why

Panel items:
- **36.** *Quick Assessment Questions and Result: paraphrase the words and check grammar.*
- **37.** *Quick Assessment Result: redesign sections based on the importance of each section (bold, text size, etc.).*

The panel was **skeptical about the questions**: why these five, how they help, and what they are for. Rewording alone does not answer that. So the work must also:

1. Explain the **purpose of each question**, both while answering and on the result.
2. Make each **result indicator meaningful and tied to the user's own answer**: what they answered, what it means for them, and why that area matters.
3. Be **educational for the user first** (a student or employee) and still useful to PACC.

## 2. Goals, non-goals, anti-goals

**Goals**
- Clear, grammatical, plain-English wording for the 5 questions, their choices, and all result-screen text.
- A "Why we ask" line under every question.
- A result screen ordered by importance, with a clear typographic hierarchy.
- Each indicator shows: the user's answer, a personal meaning, and why the area matters.
- The same new result wording in the app **and** the Cloud Function, so Insights, the report and the counselor view match the result screen.
- A short rationale document the user can show the panel ("Why these five questions").

**Non-goals**
- No scoring, threshold, question ID, option ID, or option value changes. Old saved results stay valid.
- **Question-set version** changes from `quick_v2` to **`quick_v3`** (decided by the user on 2026-11-12) in both `functions/src/assessment/catalog.ts` and `quick_assessment_scoring.dart`. The new results then show which wording the user answered. Nothing in the app reads this label.
- No change to the role-selection screen.
- No change to the shared pattern labels ("Thriving patterns", "Balanced patterns", …) or support-priority labels. The Full Assessment uses them too.
- No change to the indicator (domain) names. They are stored data keys used by reports and icons.
- No change to which actions appear per level (Full Assessment / PACC / prompt rules stay as they are).

**Anti-goals** (failure even if it "works")
- Claiming the questions are clinically **validated**. The code itself records that no validation source exists. We say they are *based on* well-known screening areas.
- Wording that sounds like a diagnosis, or that alarms the user.
- The app and server showing different text for the same result.

## 3. Constraints
- Flutter app plus Firebase Cloud Functions (TypeScript) in the same repo. CI runs `flutter analyze`, `flutter test --dart-define=APP_ENV=staging`, an APK build, and `npm test` in `functions/`.
- **Where each copy of the wording is used:**
  - **Production:** the app writes its own computed result to Firestore, so the new wording arrives with the app release.
  - **Staging:** results are saved through the Cloud Function, so the server wording takes effect after the Functions are **deployed**, which a colleague with Firebase access does after merge.
  - **Existing results:** saved results keep the wording they were saved with.
- Option tiles currently show **1 line** with an ellipsis. Some new labels are longer, so the tiles allow 2 lines.
- Work on the branch only. Never push without the user's go-ahead.

## 4. Approaches (decided)

| | Approach | Trade-off |
|---|---|---|
| **A, chosen** | Explain-your-answers. Same new wording in the app and the Cloud Function. | Needs a Functions deploy after merge. |
| B | App only. | No deploy, but the report and counselor view keep the old sentences, so a panelist could see two different texts. |
| C | Like A, but explanations are hidden behind "Learn more". | Shorter screen, but the purpose (the panel's concern) is hidden by default. |

The user approved **A** on 2026-11-12.

## 5. New wording (exact copy)

### 5.1 Questions, choices, and "Why we ask"

The time frame stays in every prompt because each question is shown on its own. IDs and values are unchanged.

| ID | New prompt | Choices (in order; values unchanged) | Why we ask |
|---|---|---|---|
| `calm_relaxed` | In the past two weeks, how often have you felt calm and relaxed? | All of the time · Most of the time · More than half of the time · Less than half of the time · At no time | Feeling calm is a sign that your mind has room to rest and recover. It is one of the clearest everyday signs of overall well-being. |
| `overwhelmed` | In the past two weeks, how often have you felt overwhelmed by everything you had to do? | Never · Rarely · Sometimes · Fairly often · Very often | Feeling that tasks are piling up is an early sign of stress. Noticing it early makes it easier to plan, prioritize, or ask for help. |
| `connected` | In the past two weeks, how connected have you felt to the people around you at school or work? | Very connected · Somewhat connected · Neither connected nor disconnected · Somewhat disconnected · Very disconnected | Feeling supported by others protects against stress and loneliness. Strong connections make hard days easier to get through. |
| `little_interest` | In the past two weeks, how often have you had little interest or pleasure in doing things you usually enjoy? | Not at all · Several days · More than half the days · Nearly every day | Losing interest in things you usually enjoy can be a sign that your mood or energy is running low. It is an important signal to notice early. |
| `stress_affecting_life` | In the past two weeks, how often has stress from school or work made it hard to handle your daily life? | Never · Rarely · Sometimes · Often · Always | This shows whether stress is starting to affect everyday things like sleep, studies, or work, which is when extra support helps most. |

Notes:
- **Q1** follows the WHO-5 answer scale ("…half **of** the time").
- **Q2** keeps the Perceived Stress Scale scale ("Fairly often").
- **Q4** keeps the PHQ-2 core phrase. Its third choice becomes the standard "More than half the days", which also matches "Several days".
- **Q3**'s "Neutral" becomes the clearer "Neither connected nor disconnected".

### 5.2 Indicator meanings (shown under each indicator on the result)

The same five indicator names are kept. The "Why it matters" line reuses that question's "Why we ask" text. The personal meaning depends on the user's own answer:
- **Going well:** the indicator's concern score ≤ 40. This is the existing strengths threshold.
- **Worth a closer look:** the concern score > 40.

| Indicator | Going well | Worth a closer look |
|---|---|---|
| Emotional calm | You have often felt calm, which suggests you are finding time to rest and recover. | You have not felt calm very often lately. Short breaks, slow breathing, or a MindMate breathing exercise may help. |
| Stress load | Your tasks feel manageable right now. Keep the routines that help you stay on top of things. | Your tasks have felt overwhelming. Breaking work into smaller steps or talking to someone you trust can lighten the load. |
| Social connection | You feel connected to the people around you. These relationships are a strong source of support. | You have felt less connected lately. Reaching out to a friend, classmate, or co-worker can make a real difference. |
| Motivation and interest | You are still enjoying the things you like to do, which is a healthy sign for your mood and energy. | You have had less interest in things you usually enjoy. If this continues, it is worth talking to someone, such as a PACC counselor. |
| Daily coping | Stress has not been getting in the way of your daily life. You seem to be coping well. | Stress has been affecting your daily life. This is a good time to look for support before it builds up. |

### 5.3 Overall summary (both app and server, by overall response pattern)

| Pattern | Summary |
|---|---|
| wellBeingSupported | Your answers show healthy patterns in most areas. Keep doing what helps you feel well. |
| generallySteady | Your answers show a generally steady balance, with a few areas worth keeping an eye on. |
| someStrain | Your answers show some areas that may be adding strain right now. Take a closer look at them below. |
| supportMayHelp | Your answers show several areas where things may feel hard right now. Support can help, and you do not have to handle this alone. |

**Focus sentence** (both app and server). It is appended to the summary to form `userSummary` and is also the `rationale`. Areas are the indicators **in the "Worth a closer look" group (score > 40)**, highest first, maximum 3. The names are lower-cased and joined in plain English (`a`, `a and b`, `a, b, and c`):

> *Builder-check call (author's):* the focus sentence uses the same > 40 split as the result sections. Otherwise a 4-choice answer like Q4 "Several days" (score 33.3) would sit under "What's going well" and also be named as "worth a closer look". The stored `topConcernAreas` field and all thresholds stay unchanged (≥ 30). Only which list the sentence reads from changes.
>
> *Builder-check call (author's):* when scores tie, both sides order by **score descending, then indicator name A–Z**. This is what the server already does; the app is aligned to it, so app and server text always match.
- With areas: **"Areas worth a closer look: stress load and daily coping."**
- Without: **"None of your answers stood out as needing attention right now."**

**Strength / focus insights** (both app and server, used in the report and the counselor view): `"<Indicator>: <Going well text>"` for each indicator with score ≤ 40, and `"<Indicator>: <Worth a closer look text>"` for each with score > 40. Ordering and limits are unchanged: up to 3 each, sorted by score descending as today.

### 5.4 Next-step guidance (app only; same levels and actions as today)

| Level | Heading | Guidance |
|---|---|---|
| low | Keep up your healthy habits | Your answers suggest you are doing well. Keep noticing what helps you feel steady, and check in again anytime. |
| moderate | Get a fuller picture | The Full Assessment looks at more areas of your well-being and gives you more personalized insights. |
| high | Consider extra support | The Full Assessment can give you a deeper look, and you can also book a confidential appointment with PACC. |
| veryHigh | Support is here for you | You can book a confidential appointment with a PACC counselor. The Full Assessment is also available whenever you are ready. |

Other result-screen text:
- **Full Assessment note:** "You can take the full {role} assessment now for deeper insights, or later from your dashboard."
- **PACC prompt dialog body:** "Your answers suggest that extra support may help. Would you like to request a confidential counseling appointment with PACC?" The title and buttons are unchanged.
- **Support level line** (inside the next-step card, small): "Support level: {existing priority label}". This replaces "Support option: …".
- **Legend title:** "What the colors mean".
- **Footnote:** "This brief check-in looks at five areas of well-being. It is not a diagnosis. For a complete picture, take the Full Assessment."
- **Hero caption:** "{Role} · Quick check-in result".

## 6. Result screen layout (Item 37)

The order is by importance. The role icon shrinks to an 18 px caption and is no longer the top element.

```
Student · Quick check-in result            12 / w600 / muted (with 18px role icon)
        [illustration 96px]
Balanced patterns                          24 / w900   ← primary result
Your answers show a generally steady …     15 / w500 / 1.45   (userSummary)

┌ What to do next ─────────────────────┐   card, accent border
│ Get a fuller picture                 │   18 / w800
│ The Full Assessment looks at …       │   14 / w500
│ Support level: Continue monitoring   │   12 / w600 / muted
│ Full Assessment note (when shown)    │   13
│ [Take Full Assessment]               │   primary button (when shown)
│ [Book a PACC appointment]            │   outlined button (when shown)
└──────────────────────────────────────┘

What's going well                          16 / w800   (hidden if empty)
  ✿ Emotional calm          ● Thriving patterns     name 15 / w700 + existing chip
    You answered: Most of the time                 13 / w600
    You have often felt calm, which suggests …     13 / w400
    Why it matters: Feeling calm is a sign …       12 / w400 / muted

Worth a closer look                        16 / w800   (hidden if empty; same row layout)

What the colors mean  (existing legend)    12
This brief check-in looks at five areas …  12 / muted
[Continue to Home]                         text button
```

- Indicators are grouped into the two sections by the ≤ 40 / > 40 rule. Within a section the order is the existing one (score descending).
- The old separate lists ("Your strengths", "Areas to explore") and the old 27 px heading are removed. That content now lives in the indicator rows and the next-step card.
- The PACC prompt dialog behaviour, the button rules and their actions are unchanged.

## 7. Rationale document for the panel
Add `docs/quick_assessment_rationale.md` with one section per question: the question, what it measures, why it matters, and the well-known screening area it is based on (WHO-5, the Perceived Stress Scale, social connectedness, PHQ-2, functional impact). Include an explicit note that the items are **not formally validated** and PACC should review them. Plain language; no new claims beyond this document.

## 8. Where the code changes (for the builder)
- `lib/features/quick_assessment/models/quick_assessment_models.dart`: add a `purpose` field to `QuickAssessmentQuestion`.
- `lib/features/quick_assessment/data/quick_assessment_questions.dart`: new prompts, labels and purposes (§5.1).
- New `lib/features/quick_assessment/data/quick_indicator_copy.dart`: indicator → going-well / closer-look text (§5.2), plus the questionId ↔ indicator lookup.
- `lib/features/quick_assessment/services/quick_assessment_scoring.dart`: summary, focus sentence, and insights (§5.3).
- `lib/features/quick_assessment/services/quick_assessment_action_policy.dart`: headings and guidance (§5.4).
- `lib/features/quick_assessment/screens/quick_assessment_question_screen.dart`: show "Why we ask"; option tiles allow 2 lines.
- `lib/features/quick_assessment/screens/quick_assessment_category_screen.dart`, plus a new widget file for the next-step card and indicator rows: the layout in §6.
- `functions/src/assessment/calculator.ts` (`calculateQuick` only): summary, focus and insights text, identical to §5.3.
- Tests on both sides pin the exact strings. Existing tests that pin the old headings are updated.

## 9. Left to the builder
- The exact padding and colors inside the new card and rows, kept consistent with `QuickAssessmentPalette`.
- How the "Why we ask" line is styled on the question screen (small, muted, under the prompt).
