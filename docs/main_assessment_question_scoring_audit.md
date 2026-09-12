# Main Assessment Question and Scoring Audit

Date: September 6, 2026

## Outcome

The Main Assessment now uses a versioned four-choice scale without Neutral, correct 1–4 min-max normalization, direction-aware scoring, equal domain weights, and explicit overall and per-sector well-being statuses.

The supplied research was applied selectively. The app's questions are custom wellness proxies, so WHO-5, PSQI, CFPB, and DASS scoring or clinical cutoffs were not copied into this assessment. The [WHO-5 specification](https://www.who.int/publications/m/item/WHO-UCN-MSD-MHE-2024.01), for example, uses five exact statements and a six-point frequency scale; applying its cutoff to this different questionnaire would be invalid.

## Question sequence

The student assessment is presented in this order:

1. Academic Stress
2. Financial Well-Being
3. Social Adjustment
4. Sleep and Rest
5. Emotional Well-Being

Teaching and non-teaching assessments follow the equivalent sequence: role-specific pressure, support, role well-being, sleep, then emotional well-being. Every assessment now has exactly 10 questions in each of its five topics, for a fixed total of 50 questions.

One ambiguous risk item was corrected from “Sleep affects my mood” to “Poor sleep negatively affects my mood.” Stable IDs were retained so stored history remains traceable.

## Updated scale and logic

| Choice | Stored value | Risk-item concern | Protective-item concern |
|---|---:|---:|---:|
| Strongly Disagree | 1 | 0 | 100 |
| Disagree | 2 | 33.33 | 66.67 |
| Agree | 3 | 66.67 | 33.33 |
| Strongly Agree | 4 | 100 | 0 |

Each sector is the mean of its 10 eligible answered items. Every role has five sectors weighted at 20% each. Numbers remain internal for deterministic aggregation and priority rules; the displayed result is:

| Internal concern | Well-being status |
|---:|---|
| 0–20 | Thriving |
| >20–40 | Stable |
| >40–60 | Needs Improvement |
| >60–100 | At Risk |

The summary begins with the exact overall well-being status, and every sector carries its own status. Priority and functional-impact rules remain separate, allowing a sector requiring attention to be highlighted even when the composite is more favorable.

## Research caveats

A four-point scale is a forced-choice format. The midpoint study by [Nadler, Weston, and Voyles](https://pubmed.ncbi.nlm.nih.gov/25832738/) found that midpoint meanings vary and response options can change endorsement. Therefore, removing Neutral should not be described as automatically increasing validity; it is the requested product design and requires validation with the target population.

Research also warns that mixing positive and reversed wording may introduce method effects or confusion ([Zhang et al., PLOS ONE](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0157795); [Suárez-Álvarez et al., PubMed](https://pubmed.ncbi.nlm.nih.gov/29694314/)). The implementation ensures the math is directionally correct, but it does not claim that the custom question bank is psychometrically validated.

Historical five-point records retain their v1 version and results. They are not silently recalculated using the new four-point v3 rules.
