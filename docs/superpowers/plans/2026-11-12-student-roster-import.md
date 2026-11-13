# Student Roster Import & Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace student self-registration with an admin-imported roster that students activate, then let students complete and maintain the Student Information form, with personal data visible only to the student and (audited) to counselors/admins.

**Architecture:** Three stores — `student_roster/{studentNo}` (server-only), `users/{uid}` (existing shape plus two flags), `student_personal_info/{uid}` (owner-readable, server-written). All writes go through Cloud Functions v2 callables in new focused files; pure validation lives in one domain module so it can be unit-tested without emulators. Flutter adds an activation flow, a Student Information screen shared by the first-login gate and Profile, and an admin Student Roster page.

**Tech Stack:** Firebase Functions v2 (TypeScript, `node:test`), Firestore rules (`@firebase/rules-unit-testing`), Flutter (Provider, `cloud_functions`, `excel_plus`).

**Spec:** `docs/superpowers/specs/2026-11-12-student-roster-import-design.md`

## Global Constraints
- Student No. canonical key = `canonicalLoginId()` from `functions/src/account_recovery.ts` (uppercase, non-alphanumerics stripped, 3–40 chars). Never invent a second canonicalizer.
- Dates cross the wire as `"YYYY-MM-DD"` strings. Store `dateOfBirth` as a Firestore Timestamp at `00:00:00Z` of that date **and** `dateOfBirthKey: "YYYY-MM-DD"`; compare only keys (avoids timezone drift).
- Name matching: `normalizeName(s)` = NFD, strip combining marks, lowercase, remove all whitespace, `.` `-` `'`. "Dela Cruz", "DELA-CRUZ", "dela cruz" are equal; "Ñ" equals "N".
- Year level stored as `"1st Year" | "2nd Year" | "3rd Year" | "4th Year" | "5th Year"` (matches current signup values). Import accepts `1`, `1st`, `1st Year`, `Year 1`, `first year` (case-insensitive) for 1–5.
- Sex options: `Male`, `Female`. Saving personal info also writes `users/{uid}.gender` to the same value (existing `profileIsReady` requires `gender`).
- Civil Status options: `Single`, `Married`, `Widowed`, `Separated`. Spouse required iff `Married`, cleared otherwise.
- Cellphone: accept `09XXXXXXXXX`, `+639XXXXXXXXX`, `639XXXXXXXXX` (spaces/dashes ignored); store `09XXXXXXXXX`. Zip: exactly 4 digits when present. Text fields trimmed, max 160 chars.
- Privacy consent `policyVersion` constant: `"2026-11-ra10173-v1"`.
- Activation code (spec "Security review amendments" §1): alphabet `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, 10 chars, displayed `XXXXX-XXXXX`; input normalized by uppercasing and removing spaces/dashes; generated with `crypto.randomInt`; stored as `{hash, salt, issuedAt, expiresAt}` using `crypto.scrypt` (N=16384, keylen 32, 16-byte random salt, base64); compared with `crypto.timingSafeEqual`; expiry 60 days; issued only for new unlinked rows and by explicit regeneration/revoke; plain codes never logged or stored. Expired copy (exact): `This activation code has expired. Ask the PACC office for a new one.`
- Official name lives in `student_roster`; `users` name fields are written only when activation creates the profile. Imports and links never write `firstName`, `middleName`, `lastName`, `name` on `users`.
- `users.gender` is written from Sex only when currently empty.
- Activation lockout: 5 failures → locked 30 minutes. Generic mismatch copy exactly: `Those details don't match our records.`
- Copy (exact): already activated → `This account is already activated. Sign in or use Forgot password.`; student blocked at provisioning → `Students activate accounts through the roster. Tap 'Activate student account'.`
- Import: max 1,000 rows per call; all-or-nothing on any error row.
- Every security-relevant write goes through `writeAudit` (`functions/src/audit.ts`) with category `AUDIT_CATEGORIES.userManagement`, except views which use `AUDIT_CATEGORIES.security`. Action names: `STUDENT_ROSTER_IMPORTED`, `STUDENT_ACCOUNT_ACTIVATED`, `STUDENT_PERSONAL_INFO_VIEWED`, `STUDENT_CORRECTION_APPROVED`, `STUDENT_CORRECTION_REJECTED`, `STUDENT_ROSTER_RECORD_UPDATED`, `STUDENT_ROSTER_STATUS_CHANGED`, `STUDENT_ACTIVATION_LOCK_RESET`, `STUDENT_ACTIVATION_CODES_ISSUED` (metadata: count only), `STUDENT_ACTIVATION_REVOKED`.
- Admin = `requireSuperAdmin` semantics from `functions/src/index.ts` (move it to an exported helper in `functions/src/access.ts` if needed; do not duplicate role logic). Clinical = role in `counselor | admin` (`canAccessClinicalData`).
- Activation callable follows the existing pair convention: `activateStudentAccount` (`enforceAppCheck: true`) and `activateStudentAccountDev` (`false`), both wrapping one handler.
- No production deploy, real-data import, or push is part of this plan.

## Review Focus
1. **Excel date cells** — `excel_plus` yields `DateCellValue`/numeric serials as well as `"MM/DD/YYYY"` text; all three must produce the same `YYYY-MM-DD` key, otherwise every activation for that file fails. Pinned in Task 10 (`parseRosterDate` tests).
2. **Student No. formatting** — `2021-00123`, `2021 00123`, `202100123` must hit the same roster doc and the same `student_id_reservations` key used by login. Pinned in Task 1 and Task 4.
3. **Typed activation codes** — lowercase, spaces, missing/extra dash, and confusable characters (`0`/`O`, `1`/`I`) are how real students type slips; normalization must accept case/spacing/dash variants, and the alphabet excludes confusables so they cannot occur. Pinned in Task 1 and Task 4.
4. **Two devices activating the same Student No. simultaneously** — exactly one succeeds, the loser's Auth user is deleted. Pinned in Task 4.
5. **Blank trailing rows / duplicate Student No. across import chunks** — blank rows ignored; duplicates detected over the whole file client-side before chunking. Pinned in Task 10.

---

## File Structure

**Functions (new)**
- `functions/src/student_roster_domain.ts` — pure: normalization, row validation, personal-info validation. No Firestore.
- `functions/src/access.ts` — `requireUid`, `requireAdmin`, `requireClinical`, returning actor data (moved/exported from `index.ts`).
- `functions/src/student_roster.ts` — import preview/commit, list, record update, status, lock reset, import history, backfill.
- `functions/src/student_activation.ts` — activation callable pair.
- `functions/src/student_personal_info.ts` — save/get personal info, correction request/review.
- Tests: `student_roster_domain.test.ts`, `student_roster.test.ts`, `student_activation.test.ts`, `student_personal_info.test.ts`, `student_roster_rules.rules.ts`.

**Functions (modify)** `index.ts` (exports, helper move), `account_integrity.ts` (student block), `package.json` (scripts), `firestore.rules`.

**Flutter (new)**
- `lib/models/student_personal_info.dart`, `lib/models/student_roster_models.dart`
- `lib/repositories/student_roster_repository.dart` (student + admin callables)
- `lib/features/student_info/student_info_validator.dart`, `lib/features/student_info/screens/student_information_screen.dart`, `lib/features/student_info/widgets/correction_request_sheet.dart`
- `lib/features/authentication/screens/student_activation_screen.dart`
- `lib/features/admin/screens/student_roster_page.dart`, `lib/features/admin/services/student_roster_file_parser.dart`
- `lib/features/counseling/widgets/student_personal_info_sheet.dart`

**Flutter (modify)** `user_model.dart`, `auth_repository.dart`, `auth_flow_routes.dart`, `route_names.dart`, `app_pages.dart`, `splash_screen.dart`, `email_verification_screen.dart`, `login_screen.dart`, `signup_screen.dart`, `profile_screen.dart`, `admin_portal.dart`, plus the counselor detail views that show a student.

**Test commands**
- Unit (no emulator): `npm --prefix functions run test:roster-unit`
- Rules: `npx firebase emulators:exec --only firestore --project demo-mindmate-roster "npm --prefix functions run test:roster-rules"`
- Callables: `npx firebase emulators:exec --only firestore,auth --project demo-mindmate-roster "npm --prefix functions run test:roster"`
- Flutter: `flutter test <path>`

---

### Task 1: Pure roster domain module

**Files:**
- Create: `functions/src/student_roster_domain.ts`
- Test: `functions/src/student_roster_domain.test.ts`
- Modify: `functions/package.json` (add `"test:roster-unit": "npm run build && node --test lib/student_roster_domain.test.js"`)

**Interfaces — Produces:**
```ts
export type AcademicIndex = {
  colleges: {id: string; name: string; code: string}[];
  courses: {id: string; name: string; code: string; collegeId: string; departmentId: string; departmentName: string}[];
};
export type RosterRowInput = {studentNo?: unknown; surname?: unknown; firstName?: unknown; middleName?: unknown;
  dateOfBirth?: unknown; college?: unknown; course?: unknown; yearLevel?: unknown};
export type OfficialFields = {studentNo: string; studentKey: string; surname: string; firstName: string; middleName: string;
  dateOfBirthKey: string; collegeId: string; college: string; courseId: string; course: string;
  departmentId: string; department: string; yearLevel: string};
export type RowResult = {index: number; ok: true; value: OfficialFields} | {index: number; ok: false; errors: string[]};
export function normalizeName(value: string): string;
export function normalizeYearLevel(value: unknown): string | null;
export function parseDateKey(value: unknown): string | null;            // accepts only "YYYY-MM-DD", real calendar date, year 1900..current
export function validateRosterRows(rows: RosterRowInput[], index: AcademicIndex): RowResult[];
export type PersonalInfo = {sex: "Male"|"Female"; civilStatus: string; spouse: string; nationality: string; placeOfBirth: string;
  cityAddress: Address | null; homeAddress: Address; father: string; fatherOccupation: string; mother: string;
  motherOccupation: string; guardian: string; guardianRelationship: string; guardianAddress: string;
  telephone: string; cellphone: string};
export type Address = {number: string; street: string; barangay: string; cityTown: string; province: string; zipCode: string};
export function validatePersonalInfo(input: unknown): {ok: true; value: PersonalInfo} | {ok: false; errors: Record<string, string>};
export function normalizeCellphone(value: unknown): string | null;
export const CORRECTABLE_FIELDS: readonly ["surname","firstName","middleName","dateOfBirth","college","course","yearLevel"];
export const PRIVACY_POLICY_VERSION = "2026-11-ra10173-v1";
export const ACTIVATION_CODE_TTL_DAYS = 60;
export type StoredActivationCode = {hash: string; salt: string; issuedAt: Date; expiresAt: Date};
export function generateActivationCode(): string;                       // "XXXXX-XXXXX"
export function normalizeActivationCode(value: unknown): string | null; // 10 valid chars or null
export async function hashActivationCode(code: string, now?: Date): Promise<StoredActivationCode>;
export async function verifyActivationCode(input: unknown, stored: StoredActivationCode | null | undefined): Promise<boolean>; // false for null/invalid; ignores expiry
```

- [ ] **Step 1: Write failing tests** covering:
  - `normalizeName("Dela Cruz") === normalizeName("DELA-CRUZ") === normalizeName("dela cruz")`; `normalizeName("Peña") === normalizeName("PENA")`.
  - `normalizeYearLevel` maps `"1"`, `"1st"`, `"1st year"`, `"Year 1"`, `"First Year"` → `"1st Year"`; `"5"` → `"5th Year"`; `"6"` and `""` → `null`.
  - `parseDateKey("2005-02-29") === null`, `parseDateKey("2004-02-29") === "2004-02-29"`, `parseDateKey("02/15/2005") === null` (client converts), future date → `null`.
  - `validateRosterRows`: a valid row returns `studentKey` equal to `canonicalLoginId(studentNo)`; college matched by name or code case-insensitively; course whose `collegeId` differs from matched college → error `"Course is not under the selected college."`; duplicate `studentKey` in the same call → both rows error `"Duplicate Student No. in file."`; missing surname → error mentioning `Surname`; middleName optional.
  - activation codes: 1,000 generated codes all match `/^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$/` and contain no `0 O 1 I L`; `normalizeActivationCode(" abcde fghjk ")` === `"ABCDEFGHJK"`; `"ABCDE-FGHJ"` (9 chars) and `"ABCDE-FGHJ0"` → `null`; `verifyActivationCode` true for the issued code typed lowercase without dash, false for another code, false for `null` stored; `hashActivationCode` sets `expiresAt` exactly 60 days after `now` and two hashes of the same code differ (salted).
  - `validatePersonalInfo`: Married without spouse → `errors.spouse`; Single with spouse → value has `spouse: ""`; homeAddress missing barangay → `errors["homeAddress.barangay"]`; cityAddress all-empty → `cityAddress: null`; cityAddress with only street → errors for barangay, cityTown, province; zip `"240"` → error; cellphone `"+63 917 123 4567"` → `"09171234567"`; cellphone `"0817..."` → error; guardian missing → error; 161-char field → error; unknown keys ignored.
- [ ] **Step 2:** Run `npm --prefix functions run test:roster-unit` — expect FAIL (module missing).
- [ ] **Step 3:** Implement `student_roster_domain.ts`. Import `canonicalLoginId` from `./account_recovery` (wrap its throw into a row error). No Firestore imports.
- [ ] **Step 4:** Re-run — expect PASS.
- [ ] **Step 5:** Commit `feat(roster): add pure roster and personal info validation`.

---

### Task 2: Shared access helpers and Firestore rules

**Files:**
- Create: `functions/src/access.ts`
- Modify: `functions/src/index.ts` (replace local `requireAuthenticatedUser`/`requireSuperAdmin` bodies with imports; behavior unchanged)
- Modify: `firestore.rules`
- Create: `functions/src/student_roster_rules.rules.ts`
- Modify: `functions/package.json` (`"test:roster-rules": "npm run build && node --test lib/student_roster_rules.rules.js"`)

**Interfaces — Produces:**
```ts
export function requireUid(request: {auth?: {uid: string} | null}): string;
export async function requireAdmin(uid: string): Promise<FirebaseFirestore.DocumentData>;     // same checks as current requireSuperAdmin
export async function requireClinical(uid: string): Promise<FirebaseFirestore.DocumentData>;  // accessRole or legacy role in counselor|admin
export function roleOf(data: FirebaseFirestore.DocumentData): string;
```

- [ ] **Step 1: Write failing rules tests** (pattern: `functions/src/profile_rules.rules.ts`):
  - `student_roster/X`, `student_roster_imports/X`, `student_activation_attempts/X`: get/list/set denied for owner, counselor, admin contexts.
  - `student_personal_info/u1`: `getDoc` as `u1` succeeds; as `u2`, as a portalStaff user, and as a counselor user fails; `setDoc`/`updateDoc` as `u1` fails; collection `getDocs` as `u1` fails.
  - `student_correction_requests/r1` with `userId: "u1"`: `getDoc` as `u1` succeeds, as `u2` fails; any write fails.
  - `users/u1` owner update of `personalInfoRequired`, `rosterLinked`, `yearLevel`, `dateOfBirthKey` fails.
- [ ] **Step 2:** Run the rules command — expect FAIL on the `student_personal_info` owner-read and correction-request owner-read cases (default deny is already in effect for the rest).
- [ ] **Step 3:** Add rules:
```
match /student_roster/{id} { allow read, write: if false; }
match /student_roster_imports/{id} { allow read, write: if false; }
match /student_activation_attempts/{id} { allow read, write: if false; }
match /student_personal_info/{userId} { allow get: if isOwner(userId); allow list, write: if false; }
match /student_correction_requests/{id} { allow get: if signedIn() && resource.data.userId == request.auth.uid;
  allow list: if signedIn() && resource.data.userId == request.auth.uid; allow write: if false; }
```
  Leave `validSelfProfileUpdate` unchanged. Create `access.ts`, switch `index.ts` to it.
- [ ] **Step 4:** Run rules tests (PASS) and `npm --prefix functions run build` (no type errors).
- [ ] **Step 5:** Commit `feat(roster): lock down roster collections and share access helpers`.

---

### Task 3: Roster import callables

**Files:**
- Create: `functions/src/student_roster.ts`
- Test: `functions/src/student_roster.test.ts`
- Modify: `functions/src/index.ts` (export), `functions/package.json` (`"test:roster": "npm run build && node --test --test-concurrency=1 lib/student_roster.test.js lib/student_activation.test.js lib/student_personal_info.test.js"`)

**Interfaces:**
- Consumes: Task 1 `validateRosterRows`, `AcademicIndex`; Task 2 `requireUid`, `requireAdmin`.
- Produces:
```ts
export async function loadAcademicIndex(): Promise<AcademicIndex>;  // active colleges/courses + department names
export const previewStudentRosterImport: CallableFunction; // data {fileName, rows: RosterRowInput[]} -> {rows: PreviewRow[], counts: {new, update, link, error}}
export const importStudentRoster: CallableFunction;        // same input -> {importId, counts: {new, updated, linked}, codes: IssuedCode[]}
type IssuedCode = {studentNo: string; name: string; college: string; course: string; yearLevel: string; code: string; expiresAt: string};
export async function issueCodesFor(keys: string[], actorId: string): Promise<IssuedCode[]>; // reused by Task 6
type PreviewRow = {index: number; studentNo: string; kind: "new"|"update"|"link"|"error"; changes?: Record<string,{from:string;to:string}>; errors?: string[]};
```

- [ ] **Step 1: Write failing emulator tests** (pattern: `functions/src/appointment_callable.test.ts`, call `.run({auth, data})`; seed an admin `users` doc, one active college/department/course, and a student `users` doc + `student_id_reservations/{key}` for the link case):
  - non-admin caller → `permission-denied`; 0 rows or 1,001 rows → `invalid-argument`.
  - preview classifies: unseen Student No. → `new`; existing roster row with changed year level → `update` with `changes.yearLevel = {from:"2nd Year", to:"3rd Year"}`; reservation exists → `link`; bad course → `error`. Preview writes nothing (roster count unchanged).
  - import with one error row → `invalid-argument`, nothing written.
  - successful import: roster doc at canonical key with `activated:false, userId:null, status:"active"`, Timestamp `dateOfBirth` + `dateOfBirthKey`; import record with counts; one `admin_audit_logs` entry `STUDENT_ROSTER_IMPORTED`.
  - new rows: response `codes` has one entry per new row; roster doc has `activationCode.hash/salt` and no plain code anywhere in the doc, the import record, or the audit metadata (assert by JSON-searching each for the returned code).
  - link case: roster `activated:true, userId`, `activationCode: null`, no code returned for it; `users/{uid}` gets academic fields, `rosterLinked:true`, `personalInfoRequired:true`, and its existing `firstName`/`lastName`/`name` are unchanged; audit metadata holds the previous academic values; if `student_personal_info/{uid}` already exists then `personalInfoRequired` stays `false`.
  - re-import of a still-unactivated row keeps the same `activationCode.hash` and returns no new code for it.
  - re-import of an activated row changes only official fields; `activated`, `userId`, `status`, and `student_personal_info` untouched; linked `users` doc gets new `yearLevel`.
- [ ] **Step 2:** Run the callables command — expect FAIL.
- [ ] **Step 3:** Implement. Shared `classify(rows)` reads existing roster docs and reservations with `db.getAll` (chunks of 300) and is used by both callables. `importStudentRoster` writes in batches of ≤ 450 operations; the audit entry goes in the first batch via a transaction-free `admin_audit_logs` doc with the same shape `writeAudit` produces (add a `writeAuditBatch(batch, db, event)` sibling in `audit.ts`). Academic fields written to linked `users` (never name fields): `schoolId` (=studentNo as entered), `dateOfBirth`, `dateOfBirthKey`, `collegeId`, `courseId`, `departmentId`, `department`, `course`, `yearLevel`, `populationRole:"student"`, `updatedAt`. Roster docs additionally store `studentKey` and `surnameNormalized: normalizeName(surname)` (used by Task 6 search).
- [ ] **Step 4:** Run — expect PASS.
- [ ] **Step 5:** Commit `feat(roster): add admin roster import preview and commit`.

---

### Task 4: Student activation callable

**Files:**
- Create: `functions/src/student_activation.ts`
- Test: `functions/src/student_activation.test.ts`
- Modify: `functions/src/index.ts` (export both)

**Interfaces:**
- Consumes: Task 1 `verifyActivationCode`, `parseDateKey`; `canonicalLoginId`; roster docs from Task 3.
- Produces: `activateStudentAccount`, `activateStudentAccountDev`; data `{studentNo, activationCode, dateOfBirth: "YYYY-MM-DD", email, password}` → `{ok: true, email}`. Errors: `not-found` + mismatch copy; `deadline-exceeded` + expired copy; `already-exists` + already-activated copy; `already-exists` "This email address is already registered."; `invalid-argument` for bad email / password shorter than 8.

- [ ] **Step 1: Write failing emulator tests** (seed roster rows directly with Admin SDK):
  - success: Auth user exists with email; `users/{uid}` has roster official fields, `accessRole:"appUser"`, `verificationStatus:"verified"`, `verifiedBy:"roster-activation"`, `personalInfoRequired:true`, `rosterLinked:true`, `profileVersion:3`, `quickAssessmentCompleted:false`, `profileSetupCompleted:false`; `student_id_reservations/{key}.userId === uid`; roster `activated:true, userId`; audit `STUDENT_ACCOUNT_ACTIVATED`.
  - `users/{uid}` name fields equal the roster names (seeded once); roster `activationCode` is `null` after success.
  - studentNo `"2021-00123"` activates roster key `202100123`; code typed lowercase without dash is accepted.
  - wrong code, wrong DOB, unknown Student No., roster row with `activationCode: null`, and `status:"deactivated"` all reject with the identical message and identical error code;
  - expired code with correct Student No. + DOB → expired copy; expired code with wrong DOB → generic mismatch (expiry never revealed before a full match). attempts doc `failedCount` increments (not for unknown IDs: key the attempts doc by canonical key regardless of existence).
  - 5 failures then correct details → still mismatch error; set `lockedUntil` to the past → correct details succeed and attempts doc is deleted.
  - already activated → already-activated copy.
  - email used by another Auth user → email error, no roster change.
  - orphan cleanup: pre-create `student_id_reservations/{key}` owned by `"someone-else"` → call rejects and `getAuth().getUserByEmail(email)` throws `auth/user-not-found`.
  - race: two `Promise.allSettled` activations with different emails → exactly one fulfilled; the rejected one's email has no Auth user.
- [ ] **Step 2:** Run — expect FAIL.
- [ ] **Step 3:** Implement per spec §2 steps 1–6. Lockout read/update happens in its own transaction before identity check. Default profile fields copy the list in `provisionAppUserProfileHandler` (`functions/src/account_integrity.ts:322-334`); extract them into an exported `defaultActivityFields()` there and reuse it from both places.
- [ ] **Step 4:** Run — expect PASS.
- [ ] **Step 5:** Commit `feat(roster): add student account activation`.

---

### Task 5: Personal info save/view and correction callables

**Files:**
- Create: `functions/src/student_personal_info.ts`
- Test: `functions/src/student_personal_info.test.ts`
- Modify: `functions/src/index.ts` (exports)

**Interfaces — Produces:**
```ts
saveStudentPersonalInfo     // data {info: PersonalInfo-like, privacyConsent?: true} -> {ok: true}
getMyStudentInformation     // data {} -> {official: OfficialFieldsView, personal: PersonalInfo | null, corrections: CorrectionView[]}
getStudentPersonalInfo      // data {userId} -> {official, personal}   (clinical only, audited)
requestStudentCorrection    // data {field, requestedValue, reason} -> {requestId}
reviewStudentCorrection     // data {requestId, decision: "approve"|"reject", reason} -> {status}
listStudentCorrectionRequests // data {status?: "pending"} -> {requests: CorrectionView[]}  (admin)
type OfficialFieldsView = {studentNo, surname, firstName, middleName, dateOfBirth: "YYYY-MM-DD", college, course, yearLevel, email};
type CorrectionView = {id, userId, studentNo, studentName, field, currentValue, requestedValue, reason, status, reviewReason, createdAt: string};
```
(`getMyStudentInformation` exists so the client reads official + personal + corrections in one call instead of three listeners.)

- [ ] **Step 1: Write failing emulator tests:**
  - save: non-student `populationRole` → `permission-denied`; first save without `privacyConsent:true` → `failed-precondition`; invalid payload → `invalid-argument` with `details.errors` from `validatePersonalInfo`; valid save writes doc with `privacyConsent.policyVersion === "2026-11-ra10173-v1"`, sets `users.personalInfoRequired:false` and `users.gender:"Female"` when gender was empty; a user whose `gender` is `"Prefer not to say"` keeps it; second save keeps `createdAt` and original `privacyConsent`.
  - `getMyStudentInformation` and `getStudentPersonalInfo` take official name fields from `student_roster` (seed `users.firstName` with a nickname and assert the response still shows the roster first name); for a legacy student with no roster row, official fields fall back to `users`.
  - counselor response contains only allowlisted keys (assert exact key set of `official` and `personal`; no `privacyConsent` internals, no `activationCode`, no `revokedUserIds`).
  - get (clinical): portalStaff caller → `permission-denied`; counselor gets data and exactly one `STUDENT_PERSONAL_INFO_VIEWED` audit with `targetId === userId`; audit is written even when `personal` is `null`.
  - corrections: `field:"studentNo"` → `invalid-argument`; second pending request for same field → `already-exists`; admin approve of `yearLevel:"4"` updates roster and `users` to `"4th Year"` and writes `STUDENT_CORRECTION_APPROVED`; approve of a college/course pair not under one another → `failed-precondition`, request stays pending; reject stores `reviewReason` and writes `STUDENT_CORRECTION_REJECTED`; non-admin review → `permission-denied`.
- [ ] **Step 2:** Run — expect FAIL.
- [ ] **Step 3:** Implement. College/course corrections: `requestedValue` is the record id; validate with `loadAcademicIndex()` from Task 3. Approval writes roster + users + request + audit in one transaction; name-field corrections (`surname`, `firstName`, `middleName`) update the roster only, never `users` name fields (add a test asserting this).
- [ ] **Step 4:** Run — expect PASS.
- [ ] **Step 5:** Commit `feat(roster): add student information and correction callables`.

---

### Task 6: Roster management callables, backfill, and student signup block

**Files:**
- Modify: `functions/src/student_roster.ts`, `functions/src/account_integrity.ts`, `functions/src/index.ts`
- Test: extend `functions/src/student_roster.test.ts`, `functions/src/account_integrity.test.ts`

**Interfaces — Produces:**
```ts
listStudentRoster          // {search?, collegeId?, courseId?, yearLevel?, status?: "notActivated"|"activated"|"infoIncomplete"|"deactivated", pageToken?} -> {rows: RosterRowView[], nextPageToken: string|null}  page size 50
listLegacyStudentsNotInRoster // {} -> {rows: {userId, schoolId, name}[]}
updateStudentRosterRecord  // {studentNo, fields: Partial<official>} -> {ok}
setStudentRosterStatus     // {studentNo, status: "active"|"deactivated"} -> {ok}   disables/enables linked Auth user
resetStudentActivationLock // {studentNo} -> {ok}
listStudentRosterImports   // {} -> {imports: {id, fileName, counts, importedByName, importedAt: string}[]}
backfillStudentInfoRequirement // {} -> {flagged: number, notInRoster: number}
issueStudentActivationCodes // {studentNos: string[]} (1..1000, unactivated active rows only) -> {codes: IssuedCode[], skipped: {studentNo, reason}[]}
revokeStudentActivation    // {studentNo, reason} -> {code: IssuedCode}
type RosterRowView = {studentNo, name, college, course, yearLevel, activated: boolean, status, personalInfoComplete: boolean, userId: string|null};
```

- [ ] **Step 1: Write failing tests:**
  - all are admin-only (`permission-denied` for counselor).
  - `listStudentRoster` search by `"dela"` matches surname; `status:"infoIncomplete"` returns activated rows whose user has `personalInfoRequired:true`.
  - `setStudentRosterStatus` deactivated → `getAuth().getUser(uid).disabled === true`, then active → `false`; audit `STUDENT_ROSTER_STATUS_CHANGED`. Deactivated row with no user still succeeds.
  - `updateStudentRosterRecord` validates via `validateRosterRows`, syncs linked `users`, audits.
  - `backfillStudentInfoRequirement`: student user without `student_personal_info` gets `personalInfoRequired:true`; one with it is untouched; teaching user untouched; returns counts; idempotent on second run.
  - `issueStudentActivationCodes`: replaces the hash (old code no longer verifies, new one does); activated rows land in `skipped`; audit metadata has the count only.
  - `revokeStudentActivation`: Auth user disabled; `users/{uid}` has `accountStatus:"revoked"`, `rosterLinked:false` and is otherwise retained; reservation deleted; roster `activated:false, userId:null`, `revokedUserIds` contains uid; a new code is returned and activating with it creates a different uid; `resolveSchoolIdAuthEmail` for that Student No. then returns the new user's email; revoking an unactivated row → `failed-precondition`; reason required.
  - `account_integrity.test.ts`: export `assertSelfProvisioningAllowed(role)`; `"student"` throws `failed-precondition` with the exact blocked copy; `"teaching"` passes.
- [ ] **Step 2:** Run unit + callables commands — expect FAIL.
- [ ] **Step 3:** Implement. Call `assertSelfProvisioningAllowed(assignedRole)` at the top of `provisionAppUserProfileHandler` after role resolution. Search: query by `surnameNormalized` prefix (written by Task 3) or exact `studentKey`; add the needed composite indexes to `firestore.indexes.json`.
- [ ] **Step 4:** Run — expect PASS. Also run full `npm --prefix functions test` under emulators to confirm nothing else regressed.
- [ ] **Step 5:** Commit `feat(roster): add roster management, backfill, and block student self-provisioning`.

---

### Task 7: Flutter models and repository

**Files:**
- Create: `lib/models/student_personal_info.dart`, `lib/models/student_roster_models.dart`, `lib/repositories/student_roster_repository.dart`
- Modify: `lib/models/user_model.dart` (add `personalInfoRequired` bool default `false`, `rosterLinked` bool default `false`, parsed in `fromMap`, included in `copyWith`)
- Test: `test/models/student_personal_info_test.dart`, `test/repositories/student_roster_repository_test.dart`, extend `test/models/user_model_test.dart`

**Interfaces — Produces (Dart):**
```dart
class StudentAddress { final String number, street, barangay, cityTown, province, zipCode; Map<String, Object?> toJson(); factory StudentAddress.fromJson(Map); bool get isEmpty; }
class StudentPersonalInfo { /* fields mirror Task 1 PersonalInfo; cityAddress nullable */ Map<String, Object?> toJson(); factory StudentPersonalInfo.fromJson(Map); }
class StudentOfficialInfo { final String studentNo, surname, firstName, middleName, dateOfBirth, college, course, yearLevel, email; }
class StudentCorrection { final String id, field, currentValue, requestedValue, reason, status, reviewReason; final DateTime createdAt; /* admin view adds userId, studentNo, studentName */ }
class StudentInformation { final StudentOfficialInfo official; final StudentPersonalInfo? personal; final List<StudentCorrection> corrections; }
class RosterPreviewRow { final int index; final String studentNo; final RosterPreviewKind kind; final Map<String, ({String from, String to})> changes; final List<String> errors; }
enum RosterPreviewKind { newRow, update, link, error }
class IssuedActivationCode { final String studentNo, name, college, course, yearLevel, code; final DateTime expiresAt; }
class RosterRowView { ... per Task 6 ... }
class StudentRosterRepository {
  StudentRosterRepository({FirebaseFunctions? functions});
  Future<String> activate({required String studentNo, required String activationCode, required String dateOfBirthKey, required String email, required String password}); // returns email
  Future<StudentInformation> getMyInformation();
  Future<void> savePersonalInfo(StudentPersonalInfo info, {required bool privacyConsent});
  Future<String> requestCorrection({required String field, required String requestedValue, required String reason});
  Future<({StudentOfficialInfo official, StudentPersonalInfo? personal})> getStudentPersonalInfo(String userId);
  Future<({List<RosterPreviewRow> rows, Map<String,int> counts})> previewImport(String fileName, List<Map<String, String>> rows);
  Future<({Map<String,int> counts, List<IssuedActivationCode> codes})> commitImport(String fileName, List<Map<String, String>> rows);
  Future<({List<IssuedActivationCode> codes, List<({String studentNo, String reason})> skipped})> issueActivationCodes(List<String> studentNos);
  Future<IssuedActivationCode> revokeActivation(String studentNo, String reason);
  Future<({List<RosterRowView> rows, String? nextPageToken})> listRoster({String? search, String? collegeId, String? courseId, String? yearLevel, String? status, String? pageToken});
  // plus thin wrappers for every remaining Task 5/6 callable, same names minus the "Student" noise:
  // listLegacyNotInRoster, updateRosterRecord, setRosterStatus, resetActivationLock, listImports, listCorrections, reviewCorrection, backfillInfoRequirement
}
```
Activation uses `routedCallable('activateStudentAccount')` (the router picks the `Dev` variant as it does for existing pairs).

- [ ] **Step 1: Write failing tests:** JSON round-trip for `StudentPersonalInfo` incl. `cityAddress: null`; `UserModel.fromMap` reads both flags and defaults them to `false` when absent; repository maps a fake callable response into `RosterPreviewRow` kinds (inject a fake `FirebaseFunctions` the way `test/repositories/` tests already do).
- [ ] **Step 2:** `flutter test test/models test/repositories/student_roster_repository_test.dart` — FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Re-run — PASS.
- [ ] **Step 5:** Commit `feat(roster): add student roster models and repository`.

---

### Task 8: Activation screen, login links, employee-only Sign Up

**Files:**
- Create: `lib/features/authentication/screens/student_activation_screen.dart`
- Modify: `lib/routes/route_names.dart` (`studentActivation = '/activate'`, `studentInformation = '/student-information'`), `lib/routes/app_pages.dart`, `lib/features/authentication/screens/login_screen.dart`, `lib/features/authentication/screens/signup_screen.dart`, `lib/providers/auth_provider.dart` (add `Future<void> activateStudentAccount(...)` = repository activate → existing email sign-in → `sendEmailVerification`)
- Test: `test/features/authentication/student_activation_screen_test.dart`, extend existing signup screen test

- [ ] **Step 1: Write failing widget tests:**
  - Step 1 form requires Student No., Activation code (hint `XXXXX-XXXXX`, auto-uppercase), Date of Birth (date picker, stored as `YYYY-MM-DD`); Continue disabled until all present. Helper text: `Your activation code is on the slip from the PACC office.`
  - repository throwing `deadline-exceeded` shows the expired copy.
  - Step 2 requires valid email and matching passwords (≥ 8 chars).
  - repository throwing `not-found` shows exactly `Those details don't match our records.`; `already-exists` with the activated copy shows that copy plus a "Sign in" button.
  - success navigates to `RouteNames.emailVerification`.
  - login screen shows "Activate student account" and "Employee sign up"; no "Create account" text.
  - signup screen has no Student option; non-`@ucu.edu.ph` email shows an error and does not submit.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement. Reuse the existing signup screen's colors/field widgets for visual parity. Remove the student branch from `SignupScreen` and from `AuthRepository.signUp` callers (leave `registrationRoleForEmail` logic for employees).
- [ ] **Step 4:** Run — PASS.
- [ ] **Step 5:** Commit `feat(auth): add student activation and make sign up employee-only`.

---

### Task 9: Student Information screen, first-login gate, Profile entry

**Files:**
- Create: `lib/features/student_info/student_info_validator.dart`, `lib/features/student_info/screens/student_information_screen.dart`, `lib/features/student_info/widgets/correction_request_sheet.dart`
- Modify: `lib/features/authentication/auth_flow_routes.dart`, `lib/features/splash/screens/splash_screen.dart`, `lib/features/authentication/screens/email_verification_screen.dart`, `lib/features/authentication/screens/login_screen.dart`, `lib/features/profile/screens/profile_screen.dart`
- Test: `test/features/student_info/student_info_validator_test.dart`, `test/features/student_info/student_information_screen_test.dart`, extend `test/features/authentication/` routing test

**Interfaces — Produces:**
```dart
// auth_flow_routes.dart
String? gateRouteForUser(UserModel user); // RouteNames.studentInformation if student && personalInfoRequired; else RouteNames.profileSetup if (profileVersion>=3 && (!isProfileComplete || !profileSetupCompleted)); else null
class StudentInformationScreen extends StatefulWidget { const StudentInformationScreen({super.key, this.mode = StudentInfoMode.onboarding}); }
enum StudentInfoMode { onboarding, edit }
class StudentInfoValidator { static Map<String, String> validate(StudentPersonalInfo info); } // same keys/rules as Task 1 validatePersonalInfo
```

- [ ] **Step 1: Write failing tests:**
  - validator mirrors Task 1 cases (spouse, address parts, zip, cellphone normalization, guardian required).
  - `gateRouteForUser`: student with `personalInfoRequired` → `/student-information` even if profile setup is also incomplete; teaching user with flag `true` → not the info route.
  - screen in `onboarding` mode shows the privacy consent checkbox and Save is disabled until checked; official fields render read-only with a "Request correction" action on each except Student No.; Spouse field appears only when Civil Status is Married; server `invalid-argument` `details.errors` render under the matching fields; success in onboarding mode navigates via `gateRouteForUser` on the reloaded user (→ profile setup), in edit mode pops with a SnackBar `Student information saved.`
  - correction sheet: submitting calls `requestCorrection` with the field key; pending corrections render with status chips.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement. Replace the inline profile-setup checks in splash, email verification (both `pushNamedAndRemoveUntil(RouteNames.profileSetup…)` sites), and login with `gateRouteForUser`. Add a "Student Information" tile on Profile for students only, opening `mode: edit`.
- [ ] **Step 4:** Run — PASS, then `flutter test test/features/authentication test/features/profile`.
- [ ] **Step 5:** Commit `feat(student-info): add student information form and first-login gate`.

---

### Task 10: Admin Student Roster page

**Files:**
- Create: `lib/features/admin/services/student_roster_file_parser.dart`, `lib/features/admin/screens/student_roster_page.dart`
- Modify: `lib/features/admin/screens/admin_portal.dart` (add `AdminPortalPage.studentRoster` after `users`, admin-only, label "Student Roster")
- Test: `test/features/admin/student_roster_file_parser_test.dart`, `test/features/admin/student_roster_page_test.dart`

**Interfaces — Produces:**
```dart
class RosterParseResult { final List<Map<String, String>> rows; final List<String> fileErrors; final Map<String, List<int>> duplicateStudentNos; }
RosterParseResult parseRosterFile(String fileName, List<int> bytes); // .xlsx via excel_plus, .csv via simple RFC-4180 parser
String? parseRosterDate(Object? cell, {bool date1904 = false}); // DateTime / DateCellValue / Excel serial (num) / "MM/DD/YYYY" / "YYYY-MM-DD" -> "YYYY-MM-DD"; 1904 adds 1,462 days to serials and to DateTimes excel_plus decoded with the 1900 epoch
bool workbookUses1904(List<int> xlsxBytes); // reads `date1904` on <workbookPr> in xl/workbook.xml via package:archive
String spelledDate(String dateKey); // "2005-02-03" -> "Feb 3, 2005" (preview display)
List<int> buildActivationSlipsXlsx(List<IssuedActivationCode> codes); // columns: Student No., Name, College, Course, Year Level, Activation Code, Expires
List<List<Map<String, String>>> chunkRows(List<Map<String, String>> rows, {int size = 1000});
const rosterTemplateHeaders = ['Student No.', 'Surname', 'First Name', 'Middle Name', 'Date of Birth (MM/DD/YYYY)', 'College', 'Course', 'Year Level'];
```

- [ ] **Step 1: Write failing tests:**
  - 1904: `workbookUses1904` true for a fixture workbook.xml with `<workbookPr date1904="1"/>`, false without; `parseRosterDate(36926, date1904: true)` === `parseRosterDate(38388)` (both `"2005-02-03"`); `spelledDate("2005-02-03") == "Feb 3, 2005"`.
  - slips: after import the page shows "Download activation slips (N)" and warns `Codes are shown only once. Download them before leaving this page.`; leaving with undownloaded codes asks for confirmation; slips xlsx contains every issued code exactly once across all chunks; codes are never written to debug logs.
  - row actions include "Issue new activation code" (unactivated rows; bulk via selection) and "Revoke activation" (activated rows; requires reason + confirm; shows the new code with a download).
  - parser: headers matched case-insensitively and in any order; missing header → `fileErrors` names it; fully blank rows skipped; `parseRosterDate` returns `"2005-02-15"` for `DateTime(2005,2,15)`, Excel serial `38398`, `"02/15/2005"`, `"2005-02-15"`; `"13/01/2005"` → `null`; duplicate canonical Student No. (`"2021-001"` and `"2021001"`) reported in `duplicateStudentNos` with both row numbers; 2,500 rows → 3 chunks.
  - page: file with duplicates or `fileErrors` shows them and disables Preview; preview table shows New / Update / Links account / Error counts and per-row changes; any error row disables Import; Import calls `commitImport` once per chunk and shows the summary `N new · N updated · N linked`; roster list filters call `listRoster` with the chosen status; row actions (Edit, Reset activation lock, Deactivate/Reactivate with confirm dialog) call their repository methods; Corrections tab approve/reject requires a reason for reject; Import history tab lists imports; "Legacy – not in roster" tab lists `listLegacyNotInRoster` results; "Download template" produces a file with `rosterTemplateHeaders`.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement using `pickAdminImportFile` and existing `AdminTheme` widgets; follow `UserManagementPage` layout. Template download reuses the export path in `report_generation_page.dart`.
- [ ] **Step 4:** Run — PASS, plus `flutter test test/features/admin`.
- [ ] **Step 5:** Commit `feat(admin): add student roster import and management page`.

---

### Task 11: Counselor/admin "View Student Information"

**Files:**
- Create: `lib/features/counseling/widgets/student_personal_info_sheet.dart`
- Modify: the portal views that show a single student — `lib/features/admin/screens/counselor_workflow_page.dart`, `lib/features/admin/screens/staff_appointments_page.dart` appointment detail, `lib/features/admin/screens/profile_management_page.dart` (find the student detail panel in each with `grep -n "studentId\|userId" <file>`)
- Test: `test/features/admin/student_personal_info_sheet_test.dart`

- Also modify: the admin audit log view (find with `grep -rn "getAuditLogPage" lib`) — add `STUDENT_PERSONAL_INFO_VIEWED` to its action filter options with label "Student information viewed"; if the page has no action filter, add a single dropdown filter passed through to `getAuditLogPage` (extend the callable's query with `where("action","==",…)` only when provided).

- [ ] **Step 1: Write failing tests:** audit log filter offers "Student information viewed" and passes the action to the repository; button "View Student Information" is shown when `currentAccessRole.canAccessClinicalData` and hidden for `portalStaff`; hidden when the appointment has no `userId` (walk-in imports); tapping calls `getStudentPersonalInfo(userId)` only on tap (never pre-fetched); `personal == null` shows `This student hasn't completed their Student Information yet.`; sheet shows a footer `Access to this record is logged.`
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run — PASS; then full `flutter test` and `flutter analyze`.
- [ ] **Step 5:** Commit `feat(counseling): let counselors view audited student information`.

---

### Task 12: Final verification and rollout notes

**Files:** Modify `docs/superpowers/specs/2026-11-12-student-roster-import-design.md` only if implementation forced a spec deviation (record it under a "Deviations" heading).

- [ ] **Step 1:** Run all suites: functions unit, rules, callables (under emulators), `flutter analyze`, `flutter test`. Expected: all green; record counts.
- [ ] **Step 2:** Manual emulator walkthrough: import a 5-row xlsx (one legacy-linked) → activate one student → verify email via emulator link → complete form → edit later → request correction → admin approves → counselor views (audit entry present) → portal staff cannot see button → old signup path with student email rejected.
- [ ] **Step 3:** Commit any fixes; push nothing and deploy nothing without explicit approval. Rollout order is spec §5 (rules+functions+admin page → import → app release → confirm block is live).
