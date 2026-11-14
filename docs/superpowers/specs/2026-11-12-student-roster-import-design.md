# Student roster import, activation and self-maintained Student Information

Status: approved; amended by the pre-implementation security review (see "Security review amendments").

## Purpose
Replace student self-registration with an administrator-imported roster. Students claim (activate) their pre-imported record, then complete and maintain the school's Student Information form inside the app. Teaching and Non-Teaching personnel keep self-registering through an employee-only Sign Up. Accounts underpin every feature and the form contains sensitive personal data (addresses, family, guardian, civil status), so authorization is enforced server-side and in Firestore rules, never only in UI.

## Decisions (agreed)
| Topic | Decision |
|---|---|
| First access | Activation/claim: no pre-created logins, no default passwords. Proof of identity = Student No. + one-time activation code (issued at import, distributed by the school) + date of birth. |
| Import contents | Registrar roster only: Student No., Surname, First, Middle Name, Date of Birth, College, Course, Year Level. Students fill in the rest. |
| Existing (self-registered) students | Keep and link by Student No.; refresh official fields; require the new form at next login; unmatched accounts flagged "Legacy – not in roster", not blocked. |
| Student editing | Official fields read-only with "Request correction" (admin approves); personal fields freely editable. |
| Who sees personal info | Counselors and admins only (`canAccessClinicalData`), every view audited. Portal staff never. |
| Employees | Sign Up stays, employee-only (`@ucu.edu.ph` + Employee ID). Server rejects any student self-provisioning. |
| Data layout | Three stores: `student_roster` (server-only), `users/{uid}` (unchanged shape), `student_personal_info/{uid}` (sensitive). |

## Data model
- `student_roster/{studentNo}` — doc ID is `canonicalLoginId(studentNo)` (same canonicalization as Student ID login). Fields: `studentNo` (as entered), `surname`, `firstName`, `middleName`, `dateOfBirth` (Timestamp, date only), `collegeId`, `college`, `courseId`, `course`, `departmentId`, `department`, `yearLevel`, `activated` (bool), `userId` (string|null), `status` (`active`|`deactivated`), `activationCode {hash, salt, issuedAt, expiresAt} | null`, `revokedUserIds` (string[]), `lastImportId`, `createdAt`, `updatedAt`, `updatedBy`. Rules: `read, write: if false`. The roster is the authoritative home of the official name.
- `student_roster_imports/{importId}` — `fileName`, `counts {new, updated, linked}`, `rowCount`, `importedBy`, `importedAt`. Rules: `false`.
- `student_activation_attempts/{studentNo}` — `failedCount`, `lockedUntil`, `updatedAt`. Rules: `false`.
- `users/{uid}` — existing shape. Name fields (`firstName`, `middleName`, `lastName`, `name`) are written from the roster **only when the profile is created at activation**; afterwards they remain the student's editable display/nickname fields and imports never touch them. Academic fields are written from the roster on activation, link and every import (`schoolId`, `dateOfBirth`, `collegeId`, `courseId`, `departmentId`, `department`, `course`, `yearLevel`, `populationRole: student`). New server-owned fields: `personalInfoRequired` (bool), `rosterLinked` (bool). None of these are added to `validSelfProfileUpdate`.
- `student_personal_info/{uid}` — `sex`, `civilStatus`, `spouse`, `nationality`, `placeOfBirth`, `cityAddress {number, street, barangay, cityTown, province, zipCode}`, `homeAddress {…same}`, `father`, `fatherOccupation`, `mother`, `motherOccupation`, `guardian`, `guardianRelationship`, `guardianAddress`, `telephone`, `cellphone`, `privacyConsent {acceptedAt, policyVersion}`, `createdAt`, `updatedAt`. Rules: `get` only if `isOwner(uid)`; `list, write: if false`.
- `student_correction_requests/{requestId}` — `userId`, `studentNo`, `field` (one of `surname|firstName|middleName|dateOfBirth|college|course|yearLevel`), `currentValue`, `requestedValue`, `reason`, `status` (`pending|approved|rejected`), `reviewedBy`, `reviewReason`, `createdAt`, `reviewedAt`. Rules: owner may `read` own; writes `false`.

## Security review amendments
Agreed after the pre-implementation security and compatibility review; these override any conflicting text below.
1. **Activation code.** `importStudentRoster` issues a one-time code for every new, unlinked row (never re-issued on re-import, so distributed slips stay valid). Format: 10 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, shown as `XXXXX-XXXXX`. Stored only as a scrypt hash with a per-row random salt; expires 60 days after issue; cleared on successful activation. Plain codes are returned once in the import response (and by `issueStudentActivationCodes` for regeneration), are never logged or persisted in plain text, and the admin downloads them as an activation-slip file. Activation input becomes **Student No. + activation code + date of birth** (surname no longer used). Any mismatch, unknown Student No., deactivated row or missing code returns the generic mismatch error and counts toward the lockout; an expired code returns `This activation code has expired. Ask the PACC office for a new one.` only after Student No., code and date of birth all match.
2. **Official name source.** The official name lives in `student_roster`. The Student Information screen and the counselor view read official fields from the roster. `users` name fields are seeded once at activation and then belong to the student (nickname/profile editing keeps working). Linking a legacy account and re-importing never overwrite `users` name fields.
3. **Gender preservation.** Saving the form writes `users.gender` from Sex only when `gender` is empty.
4. **Revoke wrongful activation.** Admin action `revokeStudentActivation({studentNo, reason})`: disables the claimed Auth user, sets that `users` doc `accountStatus: "revoked"`, `rosterLinked: false`, deletes the `student_id_reservations` entry, sets the roster row `activated: false, userId: null`, appends the uid to `revokedUserIds`, issues a fresh activation code (returned once), and writes audit `STUDENT_ACTIVATION_REVOKED`. Data is retained, never deleted.
5. **Hardening.** Linking records previous academic values in the audit metadata. Counselor reads return an explicit field allowlist. `.xlsx` files using the 1904 date system are corrected; text dates accept only `MM/DD/YYYY` and `YYYY-MM-DD`; the preview shows every date spelled out (e.g. "Feb 3, 2005").

## 1. Admin roster import
- New admin-only "Student Roster" page in the admin portal next to User Management.
- Downloadable template with headers: `Student No. | Surname | First Name | Middle Name | Date of Birth (MM/DD/YYYY) | College | Course | Year Level`. Accept `.xlsx` and `.csv`; parse client-side with `excel_plus` and `pickAdminImportFile`.
- `previewStudentRosterImport({fileName, rows})` (admin only) validates every row and returns a per-row classification: **New**, **Update** (with changed-field diff), **Links existing account** (a `student_id_reservations` entry already exists), or **Error** (missing required field, invalid date, field too long, duplicate Student No. within the file, College/Course not matching an active `colleges`/`courses` record by name or code case-insensitively, or course not under that college). Nothing is written.
- `importStudentRoster({fileName, rows})` (admin only) re-validates server-side; if any row errors, the whole call is rejected (all-or-nothing). Max 1,000 rows per call; the client splits larger files into sequential chunks, each producing its own import record.
- Updates refresh official fields only; never alter `activated`, `userId`, `status`, or anything in `student_personal_info`. If linked, the same batch updates the official fields on `users/{uid}`.
- Students absent from a new file are left unchanged (never deleted).
- Linking: when a reservation exists for the Student No., set roster `activated: true, userId`, and on `users/{uid}` set official fields, `rosterLinked: true`, and `personalInfoRequired: true` unless a `student_personal_info/{uid}` already exists.
- Writes one `student_roster_imports` record and one audit event `STUDENT_ROSTER_IMPORTED` (counts, file name) per call.
- UI shows a summary: new / updated / linked counts.

## 2. Student activation
- Login screen: "Activate student account" link; "Sign up" becomes "Employee sign up".
- Step 1: Student No., Activation code, Date of Birth. Step 2: email + password (existing password rules). Step 3: existing `EmailVerificationScreen`; the app stays locked until verified.
- `activateStudentAccount({studentNo, activationCode, dateOfBirth, email, password})`, App Check enforced (plus a `…Dev` variant without enforcement, matching existing convention):
  1. Check lockout in `student_activation_attempts`; if locked, return the generic mismatch error.
  2. Load roster row; require `status: active`, a matching unexpired activation code (constant-time hash comparison), and exact date-of-birth match. Any mismatch or missing row increments `failedCount` and returns one generic error: "Those details don't match our records." 5 failures lock the Student No. for 30 minutes; success resets the counter.
  3. If already `activated`, return "This account is already activated. Sign in or use Forgot password." (only reachable after a correct identity match).
  4. Create the Firebase Auth user with the Admin SDK (`email-already-exists` → existing "email already registered" message).
  5. Transaction: re-read roster row (must still be unactivated) and reservation (must not exist for another user); create `users/{uid}` with official fields (name seeded once), `accessRole: appUser`, `verificationStatus: verified`, `verifiedBy: "roster-activation"`, `personalInfoRequired: true`, `rosterLinked: true`, and the same default activity/assessment fields `provisionAppUserProfile` sets today; create `student_id_reservations/{studentNo}`; mark roster `activated: true, userId`; write audit `STUDENT_ACCOUNT_ACTIVATED`.
  6. If the transaction fails, delete the Auth user created in step 4, then rethrow.
- Client then signs in with the new credentials and sends the verification email. Thereafter login (Student No. + password via `resolveSchoolIdAuthEmail`) and Forgot Password work unchanged.

## 3. Student Information form and editing
- Gate: when `users/{uid}.personalInfoRequired == true`, route to the form after email verification and before onboarding/quick assessment and the rest of the app.
- First screen of the form: Data Privacy (RA 10173) consent checkbox; stored as `privacyConsent {acceptedAt, policyVersion}`.
- Fields:

| Group | Fields | Rule |
|---|---|---|
| Official | Student No., Surname, First, Middle, Date of Birth, College, Course, Year Level | Read-only, from `users/{uid}` |
| Personal | Sex (dropdown), Civil Status (dropdown: Single, Married, Widowed, Separated), Nationality, Place of Birth | Required |
| | Spouse | Required only when Civil Status is Married; cleared otherwise |
| Urdaneta City Address | #/St, Brgy, City/Town, Province, Zip | Optional; if any part given, Brgy, City/Town and Province required |
| Home Address | #/St, Brgy, City/Town, Province, Zip | Brgy, City/Town, Province required; #/St and Zip optional |
| Family | Father, Father's Occupation, Mother, Mother's Occupation | Optional |
| Guardian | Name, Relationship, Address | Required |
| Contact | Cellphone No. | Required, PH mobile `09XXXXXXXXX` (normalize `+639…`) |
| | Tel. No. | Optional |
| | Email | Shown from account; not editable here |

- Zip codes: 4 digits when provided. Text fields trimmed, max 160 characters.
- `saveStudentPersonalInfo(payload)`: owner only, `populationRole == student`; validates all rules above server-side; writes `student_personal_info/{uid}` (create or replace personal fields, preserve `createdAt`); sets `users/{uid}.personalInfoRequired = false`; on first save requires consent.
- Profile gets a "Student Information" screen: same form, prefilled, personal fields editable anytime.
- Corrections: "Request correction" beside official fields → `requestStudentCorrection({field, requestedValue, reason})` creates a `pending` request (one pending request per field per student). Student No. is not correctable this way. Student sees request status. `reviewStudentCorrection({requestId, decision, reason})` (admin only): on approve, update `student_roster` and `users/{uid}` (College/Course validated against active records), audit `STUDENT_CORRECTION_APPROVED`/`REJECTED`.

## 4. Portal access, roster management, rules
- Counselors/admins: "View Student Information" button in existing student/appointment detail views. `getStudentPersonalInfo({userId})` requires `canAccessClinicalData`, writes audit `STUDENT_PERSONAL_INFO_VIEWED` (actor, target, time) before returning data. Portal staff neither see the button nor pass the check. The audit log page can filter by this action.
- Student Roster page (admin only):
  - Searchable list by Student No. or name; filters by college, course, year level and status (Not activated, Activated, Info incomplete, Legacy – not in roster). Served by an admin-only `listStudentRoster` callable with paging.
  - Row actions: Edit official fields (`updateStudentRosterRecord`, audited, syncs `users/{uid}` if linked); Reset activation lockout (clears `student_activation_attempts`); Deactivate/Reactivate (`setStudentRosterStatus`: sets roster `status`, disables/enables the linked Auth account; no data deletion).
  - Correction requests queue (approve/reject with reason).
  - Import history from `student_roster_imports`.
- Firestore rules as listed in Data model; `users/{uid}` rules unchanged.

## 5. Signup restriction, migration, rollout
- Sign Up screen: remove the student path; require `@ucu.edu.ph` email and Employee ID; Teaching/Non-Teaching selection as today.
- `provisionAppUserProfile` (and Dev variant) rejects any request whose resolved role is `student` with `failed-precondition`: "Students activate accounts through the roster. Tap 'Activate student account'." The federated (Google) setup path, which uses the same callable, is covered by the same check. `cancelPendingRegistration` and existing repair logic remain for employees.
- Migration: legacy students link automatically on import. Admin-only one-time `backfillStudentInfoRequirement` sets `personalInfoRequired: true` on every existing student `users` doc lacking `student_personal_info`, and reports the count of students with no roster row.
- Rollout order: (1) deploy rules, collections, callables and the Student Roster page; (2) admin imports the roster and reviews "Legacy – not in roster"; (3) release app update with activation, form and employee-only Sign Up; (4) deploy the student-provisioning block. No production deployment, import of real student data, or push is authorized by this design alone.

## Testing
- Rules tests: `student_roster`, imports, attempts — all client access denied; `student_personal_info` — owner can get, cannot write, other students and portal staff denied, list denied; correction requests — owner reads own only.
- Functions tests: preview classification (new/update/link/error cases incl. duplicates and bad college/course); import all-or-nothing, chunk limit, update preserves activation and personal info, linking sets flags; activation success, each mismatch path returns the same error, lockout after 5 and reset on success, already-activated, email in use, orphan Auth user removed on transaction failure, race between two activations; save validation (conditional spouse, address rules, cellphone format, consent on first save); view requires clinical role and writes audit; correction request/approve/reject; deactivation disables Auth; `provisionAppUserProfile` rejects students and still accepts employees.
- Flutter tests: activation flow states and generic errors; form conditional validation and read-only official fields; gate routing when `personalInfoRequired`; employee-only Sign Up.

## Out of scope
Bulk export of personal info, document/photo uploads, SMS activation, automatic registrar sync.
