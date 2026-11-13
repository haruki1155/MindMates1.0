# Academic Structure: catalogue import and two-pane layout — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an administrator load a whole registrar catalogue from one unfamiliar spreadsheet, and work with it in a two-pane page that scales past a long scroll.

**Architecture:** Parsing and column detection happen client-side in Dart (the file never leaves the browser un-inspected), exactly as the student roster import already does. Validation, code derivation and writing happen in two new admin-only callables. The page becomes master/detail: colleges left, the selected college's departments and courses right.

**Tech Stack:** Flutter web (admin portal), Firebase Functions v2 (TypeScript, `node:test`), Firestore, `excel_plus`, `archive`.

**Spec:** `docs/superpowers/specs/2026-11-13-academic-structure-import-and-layout-design.md`

## Global Constraints

- **Names are unique within their parent; codes stay globally unique within their collection.** College names are global (no parent); a department name is unique within its `collegeId`; a course name is unique within its `departmentId`. Codes remain collection-wide unique because the roster import matches by name **or** code.
- Name matching is case- and whitespace-insensitive. A match means **already exists** — skip the row, never update it. Re-running a file is a no-op.
- **Add-only.** No import archives, removes or renames anything.
- A row naming an **archived** college or department is an error row reading `archived — restore it first` plus the record name.
- **No Department column mapped:** create one department per college named after the college, flagged in the preview as invented.
- **Department column mapped but cell blank:** error row. Never inherit from the row above.
- **Codes from the file are used as given and never altered.** A file code colliding with a different record, or one code given to two different names, is an error row. Only *derived* codes get a digit appended.
- **Derived code:** initials of significant words, uppercased (`BS Information Technology` → `BSIT`, `College of Pharmacy` → `CP`); append a digit while taken.
- A file code that differs from an existing record's stored code is a **warning**, not an error; the row is skipped and the stored code left alone.
- **1,000 rows maximum for the whole file**, one preview call and one import call. No chunking. Over the cap: refuse with a message to split the file.
- Any error row blocks the whole import at preview. A failure partway through writing reports what was committed rather than claiming success.
- New callables are gated by `requireAdmin` (`functions/src/access.ts`) and audited with action `ACADEMIC_CATALOGUE_IMPORTED` recording file name and counts.
- Backend field limits already enforced by `saveOrganizationRecord`: name 2–120 characters, code 1–30 characters.
- Admin theme tokens only (`lib/features/admin/theme/admin_theme.dart`): `ink`, `muted`, `canvas`, `surface`, `surfaceMuted`, `border`, `accent`, `accentStrong`, `accentSoft`, `accentFaint`, `success`, `danger`.

## Review Focus

1. **Header row is not the first row** (registrar files often have a title or blank rows above it) — detection should locate the header row or say plainly it could not. Pinned in Task 3.
2. **The same course name twice under the same department in one file** — a genuine duplicate, which must error even though the same name under a *different* college is now allowed. Pinned in Task 4.
3. **A college in the file differing only by case or spacing from an existing one** (`college of pharmacy` vs `College of Pharmacy`) must match the existing record, not create a second. Pinned in Task 4.
4. **A sheet with headers but no data rows, or a completely empty file** — must report "nothing to import" rather than succeeding with zero counts or crashing. Pinned in Task 3.
5. **Names or codes beyond the backend limits** (121-character course name, 31-character code) must surface as an error row naming the field, not as a failed write partway through the import. Pinned in Task 4.

---

## File Structure

**Backend**
- Modify `functions/src/index.ts` — parent-scoped duplicate check in `saveOrganizationRecord` (~lines 1012–1016); export the two new callables.
- Create `functions/src/academic_import_domain.ts` — pure: normalisation, code derivation, row validation. No Firestore.
- Create `functions/src/academic_import.ts` — the two callables and the write path.
- Modify `functions/src/audit.ts` — add `ACADEMIC_CATALOGUE_IMPORTED` to `AUDIT_ACTIONS`.

**Client**
- Create `lib/features/admin/services/academic_catalog_parser.dart` — file → sheets → rows, plus column detection.
- Create `lib/models/academic_import_models.dart` — the wire types.
- Modify `lib/repositories/admin_portal_repository.dart` — two new methods.
- Create `lib/features/admin/screens/academic_catalog_import_dialog.dart` — sheet pick → mapping → preview → import.
- Modify `lib/features/admin/screens/academic_structure_page.dart` — two-pane layout, chips, counts, filter, corrected dialog labels, import entry point.

**Tests**
- `functions/src/organization_record.test.ts`, `functions/src/academic_import_domain.test.ts`, `functions/src/academic_import.test.ts`
- `test/features/admin/academic_catalog_parser_test.dart`, `test/features/admin/academic_catalog_import_test.dart`, `test/features/admin/academic_structure_page_test.dart` (exists; extend)
- `test/repositories/academic_import_repository_test.dart`

**Commands** — a shared Firestore+Auth emulator may already be running on `127.0.0.1:8380` / `127.0.0.1:9399`; never start or stop one. Prefix emulator runs with `FIRESTORE_EMULATOR_HOST=127.0.0.1:8380 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9399 GCLOUD_PROJECT=demo-mindmate-roster SUPER_ADMIN_UID=<uid the test seeds>`.

---

### Task 1: Parent-scoped name uniqueness

**Files:**
- Modify: `functions/src/index.ts` (`saveOrganizationRecord`, duplicate check ~1012–1016)
- Test: `functions/src/organization_record.test.ts` (create)

**Interfaces:**
- Produces: `saveOrganizationRecord` accepts a department or course name already used under a different parent; still refuses it under the same parent; still refuses a duplicate code anywhere in the collection.

- [ ] **Step 1: Write the failing tests** — emulator-backed, seeding two colleges and a department under each:
  - a department named `Information Technology` saves under college A and again under college B
  - a second `Information Technology` under college A is rejected `already-exists`
  - a course name repeats across two different departments, and is rejected within one department
  - a duplicate **code** is still rejected even across different parents
  - editing a record keeps its own name (the `doc.id !== recordId` exclusion still applies)
- [ ] **Step 2: Run to verify they fail** — `FIRESTORE_EMULATOR_HOST=… node --test functions/lib/organization_record.test.js`. Expected: the cross-parent cases fail with `already-exists`.
- [ ] **Step 3: Change the duplicate check.** Keep the code query collection-wide. Scope the name query: colleges unchanged; departments add `.where("collegeId", "==", collegeId)`; courses add `.where("departmentId", "==", departmentId)`. Keep the existing `doc.id !== recordId` exclusion and the existing error message.
- [ ] **Step 4: Run to verify they pass**, and re-run the existing admin function suites to confirm nothing else relied on global name uniqueness.
- [ ] **Step 5: Commit** `fix(admin): scope academic name uniqueness to the parent record`

---

### Task 2: Two-pane Academic Structure layout

**Files:**
- Modify: `lib/features/admin/screens/academic_structure_page.dart`
- Test: `test/features/admin/academic_structure_page_test.dart` (extend; 107 admin tests currently pass)

**Interfaces:**
- Consumes: `AdminPortalRepository.watchColleges() / watchDepartments() / watchCourses()`, existing `_edit` and `_toggle`.
- Produces: the page shell the import entry point attaches to in Task 6.

- [ ] **Step 1: Write the failing widget tests**
  - selecting a college on the left shows that college's departments and courses on the right, and no other college's
  - a college row shows its code and status as separate chips, and a count of **active** courses (`no courses` when none)
  - a college whose only course is archived still reads `no courses`
  - changing the status filter to one that excludes the selected college clears the selection and shows the right pane's empty state
  - an archived college is reachable when the filter is `Archived` or `All`, and its row menu still offers Restore
  - at a narrow width the page renders the single-column list rather than two panes
  - the Add Department dialog labels read `Department name` and `Department code` (sentence case)
  - existing behaviour: Edit, Archive/Restore, Add department and Add course still work from the row menus
- [ ] **Step 2: Run to verify they fail** — `flutter test test/features/admin/academic_structure_page_test.dart`
- [ ] **Step 3: Implement the layout** per the spec's layout section. Keep `_edit`/`_toggle` call signatures unchanged. Use a width breakpoint for the single-column fallback and the admin theme tokens listed in Global Constraints. Extract the two panes into private widgets in the same file, or a sibling file, if the file grows unwieldy.
- [ ] **Step 4: Run to verify they pass** — `flutter test test/features/admin` and `flutter analyze lib/features/admin test/features/admin`
- [ ] **Step 5: Commit** `feat(admin): rebuild academic structure as a two-pane layout`

---

### Task 3: Catalogue file parsing and column detection

**Files:**
- Create: `lib/features/admin/services/academic_catalog_parser.dart`
- Test: `test/features/admin/academic_catalog_parser_test.dart`

**Interfaces:**
- Consumes: `excel_plus`, `archive`, and the date/CSV handling approach in `lib/features/admin/services/student_roster_file_parser.dart` (read it; reuse its helpers where they fit rather than copying them).
- Produces:
```dart
enum CatalogRole { college, collegeCode, department, departmentCode, course, courseCode }
class CatalogSheet { final String name; final List<String> headers; final List<List<String>> rows; }
class CatalogParseResult { final List<CatalogSheet> sheets; final List<String> fileErrors; }
CatalogParseResult parseCatalogFile(String fileName, List<int> bytes);
Map<CatalogRole, int> detectColumns(List<String> headers);
const catalogTemplateHeaders = <String>['College', 'College Code', 'Department', 'Department Code', 'Course', 'Course Code'];
```

- [ ] **Step 1: Write the failing tests**
  - an `.xlsx` with three sheets returns all three in `sheets`, named, in workbook order (today's roster parser silently keeps only the first — this must not)
  - a `.csv` returns exactly one sheet
  - **header row is not row 1**: two blank rows above the headers are skipped and the headers are still found; a file with no recognisable header row reports a `fileErrors` entry naming the problem
  - `detectColumns` maps `College`, `College Code`, `Department`, `Department Code`, `Course`, `Course Code` regardless of case, surrounding spaces and column order
  - it also maps the synonyms `Program` and `Course Name` to `course`, and `Program Code` to `courseCode`
  - a header it cannot place is simply absent from the map (no exception)
  - **headers but no data rows** yields a sheet with empty `rows`; a zero-byte file yields a `fileErrors` entry
  - blank trailing rows and fully blank rows are dropped
- [ ] **Step 2: Run to verify they fail** — `flutter test test/features/admin/academic_catalog_parser_test.dart`
- [ ] **Step 3: Implement the parser and detector.** Detection is header-text based; pick the first unused column whose normalised header matches a known synonym, preferring an exact match over a prefix match. Codes are never inferred from data shape.
- [ ] **Step 4: Run to verify they pass**, plus `flutter analyze` on the two paths.
- [ ] **Step 5: Commit** `feat(admin): parse catalogue files and detect their columns`

---

### Task 4: Server-side validation and import callables

**Files:**
- Create: `functions/src/academic_import_domain.ts`, `functions/src/academic_import.ts`
- Modify: `functions/src/audit.ts` (add `ACADEMIC_CATALOGUE_IMPORTED`), `functions/src/index.ts` (export both callables)
- Test: `functions/src/academic_import_domain.test.ts`, `functions/src/academic_import.test.ts`

**Interfaces:**
- Consumes: `requireUid`, `requireAdmin` (`functions/src/access.ts`); `writeAudit` / `writeAuditBatch` (`functions/src/audit.ts`).
- Produces:
```ts
export function normalizeKey(value: string): string;              // lowercase, collapse whitespace
export function deriveCode(name: string): string;                 // initials of significant words, uppercased
export type CatalogRow = {college: string; collegeCode?: string; department?: string;
  departmentCode?: string; course: string; courseCode?: string};
export type CatalogRowResult =
  | {index: number; ok: true; kind: "create" | "exists"; warnings: string[];
     invented?: {department: string}}
  | {index: number; ok: false; errors: string[]};
export const previewAcademicCatalogImport: CallableFunction;  // {fileName, sheetName, rows} -> {rows: CatalogRowResult[], counts}
export const importAcademicCatalog: CallableFunction;         // same input -> {importId, counts: {colleges, departments, courses}, status: "complete"|"partial", message?}
```

- [ ] **Step 1: Write the failing domain tests** (`academic_import_domain.test.ts`, no emulator):
  - `normalizeKey('  College   of  Pharmacy ')` equals `normalizeKey('college of pharmacy')`
  - `deriveCode('BS Information Technology') === 'BSIT'`; `deriveCode('College of Pharmacy') === 'CP'` (stop words `of`, `and`, `in`, `the` dropped)
- [ ] **Step 2: Write the failing callable tests** (`academic_import.test.ts`, emulator-backed):
  - non-admin caller gets `permission-denied`; 0 rows and 1,001 rows get `invalid-argument`
  - preview writes nothing; a clean 3-row file previews as 3 `create` rows with the right counts
  - **a college differing only by case or extra spaces from an existing one** resolves to `exists`, and no second college is created by the import
  - a department name already used under a *different* college previews as `create`; **the same course name twice under the same department within the file** is an error row
  - an archived college named by the file is an error row whose message contains `archived — restore it first` and the college name
  - no Department column: one department per college is created, named after the college, and each such row carries `invented.department`
  - Department column mapped but blank on one row: that row is an error, and the error names both fixes
  - a file code colliding with a different existing record is an error; a file code differing from an existing record's stored code is a **warning** and the stored code is unchanged
  - derived codes collide into `BSIT`, `BSIT2`
  - **a 121-character course name and a 31-character code** are error rows naming the field, with nothing written
  - any error row makes `importAcademicCatalog` refuse the whole file
  - a clean import creates colleges, departments and courses with `active: true`, `status: "ACTIVE"`, correct `collegeId`/`departmentId`, `normalizedName`/`normalizedCode`, and writes exactly one `ACADEMIC_CATALOGUE_IMPORTED` audit with the file name and counts
  - re-running the same file afterwards previews every row as `exists` and creates nothing
- [ ] **Step 3: Run both to verify they fail.**
- [ ] **Step 4: Implement.** Resolve existing records once per call into lookup maps keyed by `normalizeKey` and parent id, then validate rows against those maps plus the rows already seen in this file. Write parents before children in batches of at most 450 operations, reporting committed counts on a mid-way failure as `student_roster.ts` does.
- [ ] **Step 5: Run both to verify they pass**, then the whole functions suite to confirm no regression.
- [ ] **Step 6: Commit** `feat(admin): add catalogue import preview and commit callables`

---

### Task 5: Client models and repository methods

**Files:**
- Create: `lib/models/academic_import_models.dart`
- Modify: `lib/repositories/admin_portal_repository.dart`
- Test: `test/repositories/academic_import_repository_test.dart`

**Interfaces:**
- Consumes: Task 4's two callables and their response shapes.
- Produces:
```dart
enum CatalogRowKind { create, exists, error }
class CatalogRowResult { final int index; final CatalogRowKind kind;
  final List<String> errors; final List<String> warnings; final String? inventedDepartment; }
class CatalogPreview { final List<CatalogRowResult> rows; final Map<String, int> counts; }
class CatalogImportResult { final String importId; final Map<String, int> counts;
  final String status; final String? message; }
// on AdminPortalRepository:
Future<CatalogPreview> previewCatalogImport({required String fileName, required String sheetName,
  required List<Map<String, String>> rows});
Future<CatalogImportResult> importCatalog({required String fileName, required String sheetName,
  required List<Map<String, String>> rows});
```

- [ ] **Step 1: Write the failing tests** — inject a fake callable invoker the way `test/repositories/student_roster_repository_test.dart` does: a preview response maps to the right `CatalogRowKind`s with warnings and `inventedDepartment` preserved; an import response maps `status` and `counts`; responses arriving as `Map<Object?, Object?>` are handled.
- [ ] **Step 2: Run to verify they fail** — `flutter test test/repositories/academic_import_repository_test.dart`
- [ ] **Step 3: Implement** the models and the two methods, following the existing repository's callable and parsing conventions.
- [ ] **Step 4: Run to verify they pass**, plus `flutter test test/repositories` and `flutter analyze`.
- [ ] **Step 5: Commit** `feat(admin): add catalogue import models and repository methods`

---

### Task 6: Import flow UI

**Files:**
- Create: `lib/features/admin/screens/academic_catalog_import_dialog.dart`
- Modify: `lib/features/admin/screens/academic_structure_page.dart` (toolbar entry point)
- Test: `test/features/admin/academic_catalog_import_test.dart`

**Interfaces:**
- Consumes: Task 3's parser and `detectColumns`, Task 5's repository methods, Task 2's page shell, and `pickAdminImportFile()` from `lib/features/admin/services/admin_import_file_picker.dart`.
- Produces: this task owns the conversion step — it applies the administrator's confirmed `Map<CatalogRole, int>` to each `CatalogSheet.rows` entry to build the `List<Map<String, String>>` the repository sends, keyed by `CatalogRole.name` (`college`, `collegeCode`, `department`, `departmentCode`, `course`, `courseCode`). An unmapped role is simply absent from the map; values are trimmed. Both repository calls receive rows built this way, so preview and import always see identical input.

- [ ] **Step 1: Write the failing widget tests**
  - the toolbar shows **Import catalogue**; it opens the flow
  - a three-sheet workbook shows a sheet chooser stating three sheets were found, defaulting to the first
  - the mapping step lists the six roles with the detected column and a sample value, and lets a column be changed or cleared
  - **Continue is disabled until College and Course are both mapped**; the code columns and Department may stay unmapped
  - the preview shows per-row create / exists / error with each error's message, and invented departments are called out
  - **Import is disabled while any row is in error**
  - a successful import shows the created counts and closes back to the page
  - a `partial` result shows its message and the counts actually committed
  - a file over 1,000 rows is refused before any call, telling the user to split it
- [ ] **Step 2: Run to verify they fail** — `flutter test test/features/admin/academic_catalog_import_test.dart`
- [ ] **Step 3: Implement** the flow, injecting the parser, picker and repository so the tests can fake them. Use the admin theme tokens; keep the step sequence sheet → mapping → preview → result.
- [ ] **Step 4: Run to verify they pass** — `flutter test test/features/admin` and `flutter analyze lib/features/admin test/features/admin`
- [ ] **Step 5: Commit** `feat(admin): add the catalogue import flow`
