# MindMate Student Account Setup Without Activation Codes

Status: **Proposed — awaiting owner review**  
Decision date: 2026-11-20  
Baseline: `haruki1155/MindMates1.0` `main` at `ba652bb`  
Selected approach: **C — automatic self-claim using official roster attributes and student-selected personal email**

## 1. Intent

Remove manual activation-code issuance, downloads, distribution, entry, expiration, and replacement from ordinary student onboarding. PACC continues importing the official student roster. A student uses Student Number, full name, birth date, and a personal email they control to set up an account. A confirmation link verifies possession of the chosen email; the student sets their own password; a server transaction binds one Firebase Auth UID to one eligible roster record. The existing Student Information gate then runs before normal app navigation.

The student-facing wording is **Set up student account**, not "activate with code." The app must not display environment-specific explanatory banners or special-mode notices.

## 2. Existing implementation to preserve

- `functions/src/student_roster.ts`: admin preview/import, official academic fields, legacy-account linking, row updates, status, audit, revocation, and partial-import recovery.
- `functions/src/student_roster_domain.ts`: Student Number canonicalization, date parsing, name normalization, roster validations.
- `functions/src/student_activation.ts`: current code + DOB guarded callable, Auth creation, profile/reservation/roster transaction; replace its claim logic.
- `functions/src/account_integrity.ts`: employee-only sign-up restriction, cancellation cleanup; revise student cancellation.
- `functions/src/account_recovery.ts`: Student Number -> Firebase Auth email resolution and password reset.
- `lib/features/authentication/screens/student_activation_screen.dart`, `lib/providers/auth_provider.dart`, `lib/repositories/student_roster_repository.dart`: substitute the account-setup experience and repository calls.
- `lib/features/authentication/screens/email_verification_screen.dart`: reuse appropriate visual components and retry behavior, adapting for sign-in links and post-link password setup.
- `lib/features/admin/screens/student_roster_page.dart`, `lib/features/admin/services/student_roster_file_parser.dart`: retain roster operations, remove activation slips and code actions without changing the academic import columns.
- `lib/features/authentication/auth_flow_routes.dart`, splash/login routes, `firestore.rules`: preserve student information gate and server-only roster access.

Do not alter teaching/non-teaching registration, existing student UIDs, assessments, counseling records, appointments, mood, MindAid, or imported academic fields.

## 3. Confirmed decisions and constraints

1. There is **no registrar-confirmed email field**. The student enters a personal email during setup.
2. **No manually entered or issued activation code** in the student UI or PACC normal workflow.
3. PACC import creates `student_roster` records, not bulk Firebase Auth accounts or default passwords.
4. A student sets their **first password** after verifying the chosen email; there is no generated temporary password to change.
5. Existing student accounts linked to roster rows continue using their current credentials; do not re-claim, overwrite, or migrate their user data.
6. Keep account cancellation, correction, recovery, and administrative revocation workable without codes.
7. No visible special-mode labels in product screens.
8. Full-name and birthday matching are the selected school-record matching inputs, with Student Number identifying the candidate row.

### Known identity-assurance limitation

Student Number, name, and date of birth are **knowledge-based attributes**, not secrets. Verification of a student-selected personal email proves control of that email but **does not prove ownership of the UCU student record**. Someone who knows another student's record details could claim it first. Rate limits, App Check, and normalized matching reduce abuse but do not solve this threat. The resulting account must be internally identified as `claimMethod: "self-roster-match"` or equivalent, not as a school-officially verified identity. Do not describe this mechanism as strong identity verification in security or operational materials. Separate approval is required before enabling access to non-synthetic school-linked clinical histories.

## 4. Selected UX

1. Login: button **Set Up Student Account** instead of **Activate student account**.
2. **Find Your Student Record**: Student Number, First Name, Middle Name (optional), Last Name, Date of Birth. Use field labels already used by the roster template where possible.
3. **Your Email**: enter and confirm personal email; no account password on this step. A single action **Send verification link**.
4. **Check Your Email**: neutral copy; resend cooldown, correct email, go back, and link-expired recovery. Avoid showing whether an unknown student number exists. A corrected email begins a fresh request; an unfinished attempt does not reserve the roster record.
5. After a valid Firebase email sign-in link is opened: **Create Password**, confirm, strong password guidance; allow safe retry.
6. **Finish Setup**: call the server to verify email-authenticated UID and roster identifiers, and atomically create the profile, reservation, and roster link.
7. Run existing Student Information gate, then normal onboarding/home.

For cross-device links, request the personal email again as Firebase requires; never put the email, birthday, or other PII in the link URL or logs. Do not expose canonical student ID existence through error copy.

## 5. State and data contract

Keep the existing `student_roster/{canonicalStudentNo}` structure, `student_id_reservations`, `users/{uid}`, and independent `status: "active" | "deactivated"`.

| Stage | Roster | Firebase Auth | User profile |
| --- | --- | --- | --- |
| Imported | `activated:false`, `userId:null`, no new code | None | None |
| Link requested | Still unclaimed | Possibly none or temporary email-link auth | None |
| Email link completed | Still unclaimed | `emailVerified:true` for claimant | None |
| Password set and final claim succeeds | `activated:true`, `userId:uid` | Verified address, student-set password | `users/{uid}` created; official roster fields copied and `personalInfoRequired:true` |
| Admin deactivates | `status:"deactivated"` | Disabled if linked | Retained |
| Admin revokes a wrongful claim | `activated:false`, `userId:null` | Old UID disabled/revoked | Old profile/clinical history retained and inaccessible to a new claimant |

Keep `activated` as a compatibility field meaning **claim completed**, not merely "roster import completed"; never set it true during import. New rows must be inserted without an `activationCode`; older code fields can remain temporarily for migration but must not be issued or accepted by the new path.

Store email ownership separately from school identity assurance: `auth.emailVerified` and `claimMethod:"self-roster-match"`. If older downstream code depends on `verificationStatus:"verified"`, audit its meaning and affected services before using it for these claims; do not silently treat a personal-email link as authoritative school identity.

## 6. Server-side design

- Create a rate-limited, App Check-protected `startStudentAccountSetup` callable. It accepts normalized Student Number/name/date, performs **server-side** roster matching and status checks, and returns neutral messaging. It must not disclose name, DOB, course, or roster existence.
- Use Firebase Authentication email-link sign-in for the student-selected personal address. The sign-in link both authenticates and verifies address ownership. Configure Firebase Hosting action links and Android App Links; the current app has email/password + verification email, but no email-link handler or Android link intent filter.
- Do not trust an `emailVerified` boolean sent by the client. On final `completeStudentAccountSetup` (App Check, authenticated), refresh/check Auth server user emailVerified and email; reject missing email, existing foreign profile, another student reservation, revoked/deactivated row, or malformed/expired state.
- Re-evaluate Student Number/name/DOB on final claim to prevent stale prechecks, then atomically `create` `users/{uid}`, reserve Student Number, set roster `activated:true,userId:uid`, and write an auditable `STUDENT_ACCOUNT_CLAIMED` action. Only one concurrent claimant may win. A failed transaction must leave roster and reservation unchanged.
- Password setting after email-link sign-in must be completed before final link; if the signed-in session expires or updatePassword requires recent reauthentication, offer a new email sign-in link.
- Keep public error copy generic, e.g. **We couldn't verify these details. Check them and try again.** Rate-limit by canonical Student Number and request source with bounded retention; do not disclose which field failed.
- All database writes to roster, reservations, and claim audit remain Admin SDK only. Do not weaken Firestore rules to permit client writes.
- Handle authenticated users with no completed student profile in a setup route, not the ordinary home/profile route. Prevent access to school-linked data before the final server transaction.
- Use authenticated, logged admin revocation without issuing another code. Do not automatically attach previous UID's sensitive history to a newly claimed UID.

## 7. Email corrections and resilience

Before email ownership verification: user may change typoed email, restart sign-in-link request, resend after cooldown, or cancel. Unverified attempts must not mark the roster claimed. A link for an earlier email cannot authorize a later address. Avoid unbounded orphaned Auth users; use a safe age-limited cleanup/reconciliation strategy for unlinked email-link users.

If Auth sign-in succeeds and profile transaction fails, keep the verified session and offer an idempotent retry; do **not** show setup as complete. If the claim was already completed by the same UID, return success idempotently; if by another UID, return a generic conflict with recovery route.

Already-claimed Student Numbers follow normal Student Number + password login and Forgot Password; existing profiles remain intact. If a legacy email conflicts with the personal email typed, avoid merging another account or changing roles automatically.

## 8. Admin portal changes

- Preserve template download, preview, partial imports, student search/filters, academic updates, deactivation, correction requests, legacy linking, and audit history.
- Remove issuing, downloading, protecting, and reissuing activation codes; remove orphaned "codes shown once" unload guards and associated tests.
- Change row labels to **Ready to Set Up**, **Account Active**, **Information Incomplete**, **Deactivated**; remove **Issue activation code** and **Reset activation lock** actions.
- Replace **Revoke activation** with **Revoke account claim**, requiring a reason, disabling the old Auth UID, releasing the roster/reservation transactionally, and not minting a code. Keep old records/audits.
- Document that student email is selected during setup and is **not imported or editable as a roster field**.

## 9. Migration and rollout

1. Build new callables alongside existing code behind controlled release routing; test without live collection changes.
2. Preserve already-activated roster rows, their UIDs, and all personal/clinical records.
3. New import rows no longer mint activation codes. Updated unclaimed rows must not silently invalidate a still-used old activation flow before client cutover.
4. Update Flutter UI/providers/routes and admin management in coordinated releases.
5. Disable/remove the old activation callable and issuance endpoints at cutover so no duplicate claim mechanisms remain. Older clients must be told to update; no cross-version code bypass.
6. Do not silently set emailVerified or identity-assurance claims from client input.

## 10. Testing / acceptance

- Unit: name normalization, exact date validation, canonical Student Number, invalid/duplicate/missing fields.
- Backend + emulator: new import with no codes; valid claim; invalid name/DOB; unknown ID; inactive row; concurrent double claim; existing legacy reservation; duplicate email/UID; retry after partial failure; expired link; wrong email; wrong-client account; revocation/reclaim; no previous clinical data inherited; no bypass of roster/firestore rules.
- Flutter: registration steps, field validation, correcting email, resend cooldown, link handling, password mismatch, interrupted setup, final claims and existing-student login.
- Existing suites: `functions/src/student_roster.test.ts`, `student_activation.test.ts` (replace with claim tests), `student_roster_domain.test.ts`, `student_personal_info.test.ts`, roster Rules tests; Flutter authentication/admin roster tests; `dart analyze`; Functions TypeScript build.
- Emulator: use fictional addresses and emitted email action links, not bulk mailbox creation. Confirm the physical device's real action-link return route separately, because the Authentication Emulator's mobile email-link behavior differs from deployed hosting.
- Verify Firebase email action quota and Hosting link configuration for the target project before enabling broad access.

## 11. Alternatives considered

| Approach | Benefit | Tradeoff |
| --- | --- | --- |
| Official-roster email binding | Stronger correspondence between email and student | Registrar does not provide reliable email data |
| Student personal email + separate institutional confirmation | Stronger protection of official identities | Adds a separate confirmation step |
| **Chosen: self-roster match + personal email link** | No code slips, no approved-email import, low-friction setup | Knowledge-based matching cannot establish official identity; wrongful first claim remains possible |

## 12. What the builder may decide

- Exact names of new functions, constants and classes; internal appearance within existing MindMate style.
- Whether to reuse or replace the current `student_activation_attempts` collection, as long as attempts are rate-limited and expired safely.
- Local state-storage mechanism for same-device email-link completion and safe retries.
- Naming and location of tests, as long as security and cross-version compatibility scenarios are covered.

**Owner approval is required for this design before product implementation.**
