# Academic catalogue import — decisions and follow-up backlog

Companion to the design spec (`docs/superpowers/specs/2026-11-13-academic-structure-import-and-layout-design.md`)
and the implementation plan (`docs/superpowers/plans/2026-11-13-academic-structure-import-and-layout.md`).

Recorded during implementation on `feat/student-roster-import`. The whole-branch review judged the
branch merge-ready; nothing below blocks a merge.

## Decisions taken during implementation

Each names what was decided and what it costs if the call was wrong.

- Ruling R1: the wire contract distinguishes an unmapped column from a blank cell. An **unmapped** role is ABSENT from the row map; a **mapped but empty** cell is present as `""`. So `department` absent → invent one per college (spec); `department: ""` → error row (spec). T6 builds rows this way, T4 reads them this way. — why: the spec gives these two cases different outcomes, so the wire must tell them apart — cost if wrong: blank cells silently become invented departments.
- Ruling R2: the JSON wire shape for a preview row is `{index, kind: "create"|"exists"|"error", errors: string[], warnings: string[], inventedDepartment?: string}`. TS builds it, Dart parses it into `CatalogRowResult`/`CatalogRowKind`. The TS-side internal union may differ but must serialise to exactly this. — why: two same-named types across languages invite silent drift — cost if wrong: Task 5/6 parsing rework.
- Ruling R3: `detectColumns` uses header text only. The spec's "a sample of the data" is for DISPLAY in the mapping step (showing a sample value per column), not an input to detection. — why: inferring roles from values is the silent guesswork the anti-goals forbid — cost if wrong: weaker auto-detection on files with unhelpful headers.
- Ruling R4: a `fileErrors` entry never blocks the import. The mapping step displays it prominently (e.g. "1 sheet could not be read: Notes"), and the admin imports whichever readable sheet they select. An unreadable sheet cannot be selected because it is absent from `sheets`. — why: registrar workbooks routinely carry cover/notes sheets, and refusing the whole file for one would be hostile; the message keeps it from being silent — cost if wrong: an admin could overlook a genuinely broken sheet. Carried into Task 6.
- Ruling R5: treating an archived COURSE under a matched department as an error row is correct, though the spec names only colleges and departments. The reason is the same in all three cases — an archived record still reserves its name within its parent, so the row is neither a clean create nor a true "exists". — why: consistency, and the alternative (silently skipping) would leave the admin thinking the course is live — cost if wrong: an admin must restore a course before re-importing it.
- Ruling R6: single-word ALL-CAPS names derived a one-letter code (NURSING → N, then N2, N3…) — a direct consequence of the round-1 rule I required, and poor output for a likely input. deriveCode now falls back to the first 4 characters when an all-caps name's initials come to fewer than 2 (NURSING → NURS). — why: codes are a matching key for the roster import and are permanent — cost if wrong: four-letter codes where someone wanted initials.
- Ruling R7: the root cause is one map serving two jobs. Separate them — (1) a reserved-codes set that derivation must avoid, holding stored records' file-given codes and nothing else; (2) a code-owner map holding only records that will actually WRITE the code (planned groups + stored records' own stored codes), which alone is consulted to attribute a collision. freeDerivedCode consults both; pass three blames owners only. Consequence: a stored ref's file-given code can NEVER error — only the "differs from the stored code" warning — because it is never persisted. This also fixes the case the re-reviewer called pre-existing/out-of-scope (new record given X + stored row naming X). — why: rounds 1 and 2 each moved the fault to a neighbouring case because reservation and ownership were conflated; separating them removes the whole class — cost if wrong: a genuinely conflicting stored code would warn instead of erroring, which is the safe direction since it is never written.
- Ruling R8: course-name uniqueness is scoped to the COLLEGE, not the department, in both writers. Verified the claim myself — student_roster_domain.ts:89 is `matches.find((c) => c.collegeId === college?.id)`: it resolves within the college and takes the first hit with no ambiguity check. The spec's justification ("resolves a course within its college" cited as supporting department scoping) misread that code; the user's decision was "allow repeats under different colleges", which college-scoping implements faithfully and department-scoping does not. — why: department scoping lets one college hold two identically-named courses, and the roster import then files students into an arbitrary one with the wrong departmentId and no warning — the exact silent-wrong-record outcome the spec lists as an anti-goal — cost if wrong: two colleges still share course names (the approved behaviour), only intra-college duplicates become errors.

## Follow-up backlog (reviewed, deliberately deferred)

None of these block the merge. Grouped as the reviewers triaged them.

### Raised by the final whole-branch review (highest value first)

- **The college-level analogue of the course bug remains.** The roster matcher resolves a college with
  `.find` and colleges are deduplicated on lowercase plus whitespace only, so two colleges differing by
  punctuation (`St. Mary College` / `St Mary College`) can coexist and are indistinguishable to the
  matcher, which picks the first. This is the same failure fixed for courses, one level up, and is
  pre-existing rather than introduced here. The course fix added an ambiguity guard; colleges have none.
- **An "exists" course can silently plan an empty department.** When a row names a department the college
  does not have but the course already exists elsewhere in that college, the preview reports "exists"
  while still planning the new department, which is then created with nothing under it. Add-only and
  non-destructive, but the preview understates what it will do.
- **The importer and the single-record dialog agree on scope but not on equality.** The importer compares
  course names with the roster's normalisation (which strips `.`, `-`, `'`); `saveOrganizationRecord`
  still compares on lowercase only. So an administrator can hand-create `B.S. Nursing` beside a stored
  `BS Nursing` in one college, which the importer would refuse. The roster ambiguity guard means the
  consequence is a refused student row rather than a misfiled one.
- Two parsers now feed the same roster matcher: the catalogue parser reimplemented ~55 lines of CSV
  handling because the roster parser's helpers are file-private. Extracting one shared helper would
  remove the drift risk.
- A failed final batch loses the import's audit entry while records are already written. Same exposure
  as the shipped student roster import; one ticket should cover both.

### Carried from task reviews

- **Task 1** — edit-self test doesn't prove a collision was possible; no test for moving a department to a college that already has that name.
- **Task 2** — search matches child text in two-pane but only college name/code in single-column (same query, different results by width); left count includes active courses under an archived department; _selectedCollegeId assigned during build.
- **Task 3** — formula/date/bool cells via toString() (same as roster parser); header search depth 20 rows not mentioned in the error text; rows above the header discarded silently; 55 lines of CSV parsing duplicated from the roster parser (its helpers are file-private) — extracting a shared CSV helper later would remove the drift risk.
- **Task 3** — xlsx title-row test and `College of Arts` data-row test both pass against the old code, so only the CSV test actually guards the fix; residual narrow case — a one-exact-match header followed by a data row with two exact matches would still lose (very unlikely).
- **Task 4** — preview counts can overstate planned colleges/departments when error rows exist (never in a state where the import proceeds); a file code owned by a same-named record under a different parent only warns (compares owner name, should compare id); `active === true || status === "ACTIVE"` is tolerant of a contradictory record; fileName not required yet reaches the audit; a failed final batch loses the audit while records are written (same exposure as student_roster); unused `planned` parameter in fillStoredColleges.
- **Task 4** — a derived code reserved by a row that later fails stays reserved (plan can show CP2 with no CP — cosmetic, codes stay unique); the emulator derived-collision test now computes its expectation via deriveCode, so a deriveCode regression wouldn't fail it (domain tests still assert literals); when two rows give one group different codes, the first mention wins and only the dissenting row errors (import blocked either way).
- **Task 4** — a stored record named with two different codes across rows reserves both, over-reserving against new records.
- **Task 4** — writer-side analogue of the fixed bug — a NEW record's given code claims ownership even when its row later fails, so it can block derivation and be named as owner for a record that will never exist (pre-existing in shape; the failed-row guard covers only the stored side).
- **Task 5** — R1 absent-vs-blank covered only implicitly (expected payload is the same object instance; a second row with an absent role + containsKey assertion would pin it); unknown `status` coerces to "complete" and a missing `index` to 0, so a malformed response reads as clean success.
- **Task 6** — cap wording is per-sheet vs the constraint's per-file (harmless — only the selected sheet is ever sent and the backend enforces the same limit); nothing prevents mapping two roles to the same column; single-sheet files still show the chooser (deliberate — it is where fileErrors live).
