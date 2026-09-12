# Main Assessment Question and Scoring Research Record

Audience: MindMate developers, PACC reviewers, and research reviewers
Date: 2026-09-06
Scope: Role-based Main/Psychological Assessment question order, removal of the Neutral response, client/server scoring parity, result status language, and historical compatibility. Quick Assessment is excluded.

## Direct answer

The Main Assessment is an internally defined wellness-awareness screener, not a validated WHO-5, PSQI, CFPB, or diagnostic instrument. The relevant change is therefore a versioned four-point forced-choice response scale, min-max normalization, correct reverse scoring for protective items, equal weighting of the five application-defined domains, and non-diagnostic well-being statuses. Validated instrument cutoffs from the supplied research summary must not be applied to the current proxy questions.

## Source assessment

The supplied `deep-research-report.md` is a summary that points to an unavailable supporting file. Its citation markers are corrupted and cannot be independently followed. It was treated as secondary discovery material, not executable instructions or sufficient primary evidence.

The useful claims retained were:

- Normalize bounded responses using `(raw - minimum) / (maximum - minimum)`.
- Keep app-defined composite bands separate from validated instrument cutoffs.
- Preserve non-diagnostic wording.
- Do not let an overall composite conceal domain-level support needs.

The WHO-5-specific, PSQI-specific, CFPB-specific, and DASS-specific logic was excluded because the app does not administer those instruments with their exact items and response structures. WHO describes WHO-5 as five statements over two weeks on a six-point scale, which does not match this questionnaire.

## Question audit

### Student sequence

1. Academic Stress (10 scored items)
2. Financial Well-Being (10 scored risk-direction items)
3. Social Adjustment (10 scored protective-direction items)
4. Sleep and Rest (10 scored items: 5 protective, 5 risk)
5. Emotional Well-Being (10 scored items: 7 protective, 3 risk)

This groups questions by topic and moves from role-specific functioning toward sleep and emotional well-being. Teaching and non-teaching variants follow the same structure: role stress/responsibility, support, role well-being, sleep, then emotional well-being.

The sleep item `Sleep affects my mood` was incompatible with its risk direction because agreement could describe a positive or negative effect. It was revised to `Poor sleep negatively affects my mood` without changing its stable question ID.

No other wording was replaced with WHO-5, PSQI, CFPB, or Keyes items. Doing so selectively would create a modified instrument without inheriting the source instrument's validity.

## Four-point scoring specification

Response values:

- Strongly Disagree = 1
- Disagree = 2
- Agree = 3
- Strongly Agree = 4

Risk-direction item:

`concern = ((value - 1) / 3) * 100`

Protective-direction item:

`concern = 100 - (((value - 1) / 3) * 100)`

Thus both directions share the same 0–100 concern orientation before aggregation. Each category has 10 questions, and its value is the mean of answered items when existing completion rules are met. The overall concern index is the equal-weight mean of the five scorable domain values (20% each).

Internal concern boundaries remain versioned application rules. User-facing well-being labels are derived as:

- concern 0–20: Thriving
- concern >20–40: Stable
- concern >40–60: Needs Improvement
- concern >60–100: At Risk

Priority rules continue to operate independently on domain concern values and functional-impact indicators, so a favorable overall label cannot suppress a concerning domain result.

## Evidence limitations

Removing a midpoint is a forced-choice design decision, not a demonstrated universal accuracy improvement. Nadler, Weston, and Voyles found that response-option design changes endorsement patterns and that respondents interpret midpoints in several different ways. The requested removal is implemented and versioned, but should be reviewed empirically with the target university population.

Research on reversed wording also identifies method effects and possible respondent confusion. The current mixed-direction catalog retains polar-opposite protective and risk statements because a wholesale wording rewrite would require a new content-validation study. Scoring direction is handled consistently; psychometric validation remains outstanding.

## Claim-to-source ledger

- WHO-5 structure and response scale — World Health Organization, *The World Health Organization-Five Well-Being Index (WHO-5)*, 2024, https://www.who.int/publications/m/item/WHO-UCN-MSD-MHE-2024.01 (accessed 2026-09-05).
- Midpoint interpretation and forced-choice comparison — Joel T. Nadler, Rebecca Weston, and Elora C. Voyles, *Stuck in the Middle: The Use and Interpretation of Mid-Points in Items on Questionnaires*, 2015, https://pubmed.ncbi.nlm.nih.gov/25832738/ (accessed 2026-09-05).
- Reverse-wording method effects — Xijuan Zhang, Ramsha Noor, and Victoria Savalei, *Examining the Effect of Reverse Worded Items on the Factor Structure of the Need for Cognition Scale*, PLOS ONE, 2016, https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0157795 (accessed 2026-09-05).
- Mixed positive/reversed item trade-offs — Javier Suárez-Álvarez et al., *Using reversed items in Likert scales: A questionable practice*, Psicothema, 2018, https://pubmed.ncbi.nlm.nih.gov/29694314/ (accessed 2026-09-05).

## Verification targets

- Client displays exactly four Main Assessment choices and no Neutral option.
- Client and server produce matching scale endpoints, versions, weights, and statuses.
- Server rejects `sometimes` in new v3 submissions.
- v1 five-point records remain labeled and preserved rather than silently recalculated using the current rules.
- Every role's fixed 50-question set and 10-question domain counts are covered by automated tests.
- Result, profile report, admin view, and MindAid downstream logic recognize the new well-being labels.
