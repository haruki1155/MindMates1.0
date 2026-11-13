# Academic Structure: catalogue import and two-pane layout

Status: approved in conversation; awaiting written-design approval.

## Intent and why

MindMate's admin portal can only create colleges one at a time, and until 2026-11-13 could not create
departments or courses at all. Staging proved the consequence: 10 colleges, zero departments, zero
courses — and the student roster import rejects every row whose course is not in the catalogue, because
it only reads `active == true` records.

The catalogue itself belongs to the registrar, and the team does not hold that spreadsheet; the client
does. So the importer must accept a file nobody has seen yet, and must not assume a layout.

Two pieces of work, one page:

1. **Import a catalogue file** that may contain colleges, departments and courses together, and create
   all three levels from it.
2. **Rebuild the page layout** so an administrator can work with a full university catalogue without
   scrolling through a single long column.

## Goals

- One file creates colleges, departments and courses, with the hierarchy inferred from the file.
- Work with an unknown column layout: detect what each column is, and let the administrator correct
  that reading before anything is written.
- Re-running the same file is safe and changes nothing.
- An administrator can see, at a glance, which colleges have no departments or courses.
- Creating and editing stay available for single records; the import is an addition, not a replacement.

## Non-goals

- Deleting academic records. Archive and Restore already exist and stay as they are.
- Syncing: the import never archives or removes anything absent from the file.
- Editing student data. This page only touches `colleges`, `departments` and `courses`.
- Importing students. That is the separate, already-built student roster import.

## Anti-goals

Things that would make this a failure even if it technically worked:

- Silently importing a misread file. An unattended wrong guess is worse than refusing the file.
- Creating duplicate colleges or courses because a name was matched too strictly.
- A layout that needs horizontal scrolling or breaks on the laptop screens the PACC office uses.

## Constraints

- `saveOrganizationRecord` (existing, super-admin only) requires a **code** on every record, 1–30
  characters, unique within its collection by normalised value. Codes are therefore mandatory, and the
  importer must supply one for every record it creates.
- Courses must carry both `collegeId` and `departmentId`; the data model has no course without a
  department.
- The roster import matches a college or course by **name or code**, so codes are a real matching key,
  not decoration. A code that matches the registrar's own is more useful than a generated one.
- Existing colleges use registrar numbering (`002`–`010`), which generated codes will not resemble.
- The portal is a Flutter web app deployed from `main` to Vercel; it talks to Firebase only through
  callables. No direct Firestore writes from the client.
- Archive already refuses to archive a college with active departments or courses, and a department
  with active courses. The importer must respect the same parent/child integrity.

## Approaches considered

**For the importer:**

- **A — Strict headers.** Accept a fixed set of header spellings, reject anything else. Cheap, but
  against a file nobody has seen it mostly fails, which defeats the purpose.
- **B — Detect, then confirm the mapping (chosen).** Read the file, guess which column is College,
  Department, Course and any codes, show the administrator that reading, let them correct any column,
  then preview and import. The confirm step is what makes it versatile rather than fragile.
- **C — Guess silently.** The most "automatic", and the one that quietly creates the wrong catalogue.
  Rejected against the anti-goal above.

**For the layout:**

- **A — Refined hierarchy list.** Today's expanding list with counts, aligned columns and chips.
  Familiar and quicker to build, but a full catalogue becomes one very long page.
- **B — Two-pane master/detail (chosen).** Colleges on the left, the selected college's departments and
  courses on the right. Scales to a full catalogue and keeps each action next to what it acts on.

The user chose B in both cases, after seeing both layouts rendered in the admin palette.

## The import, as decided

**Entry point.** An "Import catalogue" action on the Academic Structure page, beside "Add college".

**Accepted files.** `.xlsx` and `.csv`, reusing the parsing approach already built for the student
roster import (BOM stripping, quoted commas and newlines, mixed line endings, Excel serial and 1904
dates).

**Sheets.** The roster parser reads only the first sheet of a workbook and silently ignores the rest.
That is the anti-goal above, so the mapping step states how many sheets the file contains and lets the
administrator choose which one to import, defaulting to the first. Importing several sheets in one pass
is out of scope: run the import once per sheet.

**Shape.** One row per course, with the college and department repeated on each row. The hierarchy is
inferred from repeated values rather than declared:

```
College, College Code, Department, Department Code, Course, Course Code
College of Information and Technology Education, 010, Information Technology, ITE, BS Information Technology, BSIT
College of Information and Technology Education, 010, Information Technology, ITE, BS Computer Science, BSCS
```

**Step 1 — detect and confirm the mapping.** The client reads the header row and a sample of the data,
proposes a column for each of the six roles (College, College Code, Department, Department Code, Course,
Course Code), and shows that reading with a sample value from each column. The administrator can change
any column or mark it absent. Only College and Course are required; the three code columns and
Department may be absent.

**Step 2 — preview.** With the mapping confirmed, the server validates every row and returns a per-row
outcome, mirroring the roster import's preview: what will be created, what already exists, and what is
in error, with the reason. Nothing is written.

**Step 3 — import.** Creates the records, parents before children, and reports what it made.

**Decisions taken (marked T where the user decided, otherwise mine):**

- **(T) Names are unique per college, not globally.** Two colleges may each have a department called
  "Information Technology", or a course of the same name. This reflects how universities name things.
  A **course name is unique within its college**, not within its department: `student_roster_domain.ts`
  resolves a course inside the college it matched and takes the one candidate it finds there, so two
  same-named courses in one college — which two department spellings of that college would produce —
  could not be told apart, and every student in that programme would be filed under an arbitrary one of
  them with the wrong `departmentId`. A course's department remains its write parent; only the
  uniqueness scope is the college.
  **Consequence:** `saveOrganizationRecord`'s duplicate check is currently collection-wide
  (`functions/src/index.ts`, the `normalizedName` query) and must become college-scoped — a department
  against others in its college, a course against others in its college — so that the single-record
  dialog and the importer agree. Without that change an administrator could not hand-create what the
  import creates. Colleges remain globally unique, having no parent.
- **Codes stay globally unique within their collection.** The roster import matches a course or college
  by name **or code**, so a repeated code would make that lookup ambiguous. Only the name rule relaxes.
- **(T) Archived records named by the file are an error row**, reading "archived — restore it first"
  and naming the record. The administrator restores it in the portal and re-runs. This keeps the import
  strictly add-only, and avoids the backend's refusal to attach a course to an inactive college
  producing a confusing downstream failure instead.
- **Missing Department column.** The data model requires one, so the importer creates a single
  department per college, named after the college, and the preview flags each one explicitly as
  something it invented. Rejecting the file instead would block the common case of a registrar list
  that only has programs.
- **Blank Department cell when the column is mapped** is an error row, not an inference. The message
  offers both fixes: fill the cell, or unmap the Department column to group that college's programs
  under one department. Inheriting the value from the row above is the silent guesswork the anti-goals
  forbid, even though registrar spreadsheets often do leave repeated cells blank.
- **Codes from the file are never altered.** When the code column is mapped, its value is used as given.
  If a code the file gives for a record being **created** collides with a different record, or the file
  gives one code to two different names, that row is an error — appending a digit would falsify the
  registrar's own numbering, which is the part worth keeping. Only *derived* codes get a digit appended
  to resolve a collision. A code the file gives for a record that **already exists** is never persisted
  (the stored code is kept, per Ruling R7), so it cannot collide with anything and can only warn.
- **Derived codes.** When no code column is mapped: initials of the significant words, uppercased
  (`BS Information Technology` → `BSIT`, `College of Pharmacy` → `CP`), with a digit appended if taken.
  Every code stays editable afterwards.
- **A code that differs from an existing record's code is a warning, not an error.** The row already
  exists by name, so it is skipped and the stored code is left alone; the preview reports the
  difference so the administrator can decide. The roster import's `PreviewRow` already carries a
  warning channel for exactly this kind of report.
- **Matching existing records.** Case- and whitespace-insensitive on the name, scoped to the parent.
  A match means "already exists" and the row is skipped, never updated, which makes re-running a file
  a no-op.
- **Add-only.** Nothing is archived, removed or renamed by an import, ever.
- **Scope cap: 1,000 rows for the whole file, in one preview call and one import call.** No chunking.
  A university catalogue is hundreds of rows, not thousands, and chunking would mean later chunks are
  previewed against facts that earlier chunks have already changed. A larger file is refused with a
  message to split it.
- **Atomicity.** An error in any row blocks the whole import at preview. A failure partway through
  writing reports exactly what was committed rather than claiming success, as the roster import does.
- **Authorisation.** A new callable gated by `requireAdmin`, which is the same super-admin gate every
  other admin callable uses (`functions/src/access.ts`), and audited with a new action recording the
  file name and the counts created.
- **Preview and commit** reuse the roster import's established shape directly; no new pattern.

## The layout, as decided

Two panes, built from the chosen mockup:

- **Left — colleges.** Searchable list, each row showing the college name, its code, and a count of
  what it contains ("010 · 7 courses", or "008 · no courses"). The selected college is marked with the
  accent rule.
- **Right — the selected college.** Its departments, each with its courses beneath, and the add actions
  placed next to what they create: "+ Course" on each department, "+ Add department" at the foot.
- **Chips, not run-together text.** `010 • Active` becomes a code chip and a status chip.
- **Empty states are visible, not inferred.** A college with no departments says so and offers the
  action inline, rather than hiding it in the overflow menu.
- **The Active / Inactive / All filter stays**, in the toolbar, applying to both panes. It is the only
  route to an archived record in order to Restore it, so it must remain reachable. When a filter change
  removes the selected college from the left pane, the selection clears and the right pane shows its
  empty state.
- **Left-pane counts count active children only**, and the row says so plainly ("7 courses", "no
  courses"). Counting archived children would make a college that is effectively empty look populated,
  defeating the goal of spotting gaps at a glance.
- **Narrow screens** fall back to the single-column list rather than squeezing two panes.
- **Dialog labels are corrected** to sentence case ("department name" → "Department name"), which is the
  inconsistency visible in the current build.
- Edit, Archive and Restore keep their current behaviour and placement in the row menu.

## What is left to the builder

- Where the detection and preview state lives, and how the mapping step is composed with the existing
  page (a dialog, a route, or an inline panel) — whichever fits the page's existing patterns.
- The exact detection heuristics: header synonyms and any value-shape signals used to propose a column.
- Widget decomposition. The page file is already sizeable; splitting the panes and the import flow into
  their own widgets is expected.
- The code-derivation function's precise rules for stop words and length, within the stated shape.
- Test composition, following the admin suite's existing fakes and injection patterns.

## Note on an existing behaviour this changes

Relaxing `saveOrganizationRecord`'s duplicate check from collection-wide to parent-scoped changes an
existing rule: names that the dialog refuses today will be accepted afterwards. That is the intent of
the decision above, but it is a change to shipped behaviour rather than purely new code, so it needs
its own regression test — a department name that already exists under a *different* college must save,
while the same name under the *same* college must still be refused.
