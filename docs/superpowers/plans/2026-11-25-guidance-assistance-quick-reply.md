# Guidance Assistance Quick Reply Only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App users answer counselors only with nine fixed replies, enforced in UI, send path and Firestore rules, and both sides see Sending, Sent and Read on their own messages.

**Architecture:** A Dart catalog is the single client source of the nine texts, and the rules hold the same list, pinned by a parity test. The repository checks the catalog after its existing idempotency check, so delivered legacy drafts reconcile and undelivered ones are refused. Read state for the student comes from a new thread field `counselorReadAt`, written best-effort by the portal.

**Tech Stack:** Flutter (Dart), Cloud Firestore rules, `@firebase/rules-unit-testing` in `functions/`.

**Spec:** `docs/superpowers/specs/2026-11-25-guidance-assistance-quick-reply-design.md`

## Global Constraints

- Message document schema stays `senderId`, `senderRole`, `text`, `createdAt`; no migration.
- Canonical texts, exactly: `I understand.`, `Noted.`, `Thank you for your guidance.`, `I need clarification.`, `I am available.`, `I am not available.`, `I would like a follow-up session.`, `I need further assistance.`, `My concern has been addressed.`
- Info text, exactly: "Guidance Assistance allows you to receive instructions from your guidance counselor and respond using predefined Quick Replies. For concerns requiring detailed discussion, please request a counseling session."
- Do not modify `ServiceInquiryComposer`.
- Counselor rules, college scoping, receipts and badges keep current behaviour.
- The portal must work on both the old and new rules: `counselorReadAt` writes are best-effort and never inside the existing batches.
- No new dependencies; no deploys.
- Flutter tests run with `--dart-define=APP_ENV=staging`; Functions tests run inside the emulators (see Task 7).

## Review Focus

1. A modified client writes free text or a near-miss ("Noted" without the period, trailing space) → the rules refuse it. Pinned in Task 2.
2. A legacy free-text draft restored from the outbox after the update → it is never written; if it was already delivered it reconciles under its ID. Pinned in Tasks 3 and 4.
3. The portal on the old rules (thread update refused) → badges and reply sending still succeed. Pinned in Task 6.
4. A student message created before the counselor opened the thread versus after → Read only for the earlier one. Pinned in Tasks 5 and 6.
5. 360 px wide screen at 2x text scale → all nine replies reachable and Send visible. Pinned in Task 5.

---

### Task 1: Quick reply catalog

**Files:**
- Create: `lib/features/counseling/data/guidance_quick_replies.dart`
- Test: `test/features/counseling/guidance_quick_replies_test.dart`

**Interfaces:**
- Produces: `class GuidanceQuickReply {const GuidanceQuickReply(this.id, this.text); final String id; final String text;}`; `const List<GuidanceQuickReply> guidanceQuickReplies` (order as in the spec table); `bool isGuidanceQuickReplyText(String text)` (exact match, no trimming).

- [ ] **Step 1: Write the failing test** `catalog holds the nine approved replies in order`: IDs equal `['understand','noted','thank_you','clarification','available','unavailable','follow_up','further_assistance','resolved']`, texts equal the Global Constraints list; `isGuidanceQuickReplyText('Noted.')` true; `'Noted'`, `'Noted. '`, `'noted.'` false.
- [ ] **Step 2: Run** `flutter test test/features/counseling/guidance_quick_replies_test.dart --dart-define=APP_ENV=staging` → FAIL (file missing).
- [ ] **Step 3: Implement** the catalog file.
- [ ] **Step 4: Run** the test → PASS.
- [ ] **Step 5: Commit** `feat(counseling): add the Guidance Assistance quick reply catalog`.

### Task 2: Firestore rules and parity

**Files:**
- Modify: `firestore.rules` (counselor section, near `isApprovedCounselor`)
- Create: `functions/src/counselor_messaging_rules.rules.ts`
- Test: `test/features/counseling/guidance_quick_replies_test.dart` (parity case)

**Interfaces:**
- Consumes: `guidanceQuickReplies` (Task 1).
- Produces: rules function `guidanceQuickReplyTexts()` returning the list literal; thread field `counselorReadAt` (timestamp, counselor-written).

- [ ] **Step 1: Write the failing rules tests** in `counselor_messaging_rules.rules.ts` (same harness as `first_login_rules.rules.ts`; seed `users/s1` with `collegeId`, `users/s2`, and an approved counselor profile that satisfies `isApprovedCounselor()` with `email_verified`):
  - owner batch (thread create + message) with each of the nine texts → succeeds;
  - owner message with `"Hello"`, `"Noted"`, `"Noted. "` → fails;
  - owner message with `senderRole: 'counselor'` or an extra key → fails;
  - first-login session (`firstLoginPending: true`) sending `"Noted."` → fails;
  - `s2` writing into `s1`'s thread or reading its messages → fails;
  - approved counselor free-text reply with the existing thread update → succeeds;
  - a signed-in non-counselor writing `senderRole: 'counselor'` → fails;
  - approved counselor update `{counselorReadAt: serverTimestamp()}` alone → succeeds; with a client timestamp → fails; by the owner → fails;
  - an existing free-text message seeded with rules disabled → owner and counselor can still read it.
- [ ] **Step 2: Write the failing Dart parity test** `rules allowlist equals the catalog`: read `firestore.rules`, extract the strings inside `function guidanceQuickReplyTexts()`, expect them to equal `guidanceQuickReplies.map((r) => r.text)`.
- [ ] **Step 3: Run** both (Functions via the emulator command in Task 7 with filter `counselor_messaging_rules`; Dart via `flutter test`) → FAIL.
- [ ] **Step 4: Implement the rules:** add `guidanceQuickReplyTexts()`; in `messages/{messageId}` create, keep all current conditions and add `(isApprovedCounselor() && !isOwner(userId)) || request.resource.data.text in guidanceQuickReplyTexts()` so owner text must match; in the thread update counselor branch allow `counselorReadAt` among the affected keys, requiring `== request.time`, and keep the message-linkage requirement only when the reply keys change.
- [ ] **Step 5: Run** both → PASS.
- [ ] **Step 6: Commit** `feat(rules): limit app-user guidance messages to approved quick replies`.

### Task 3: Repository enforcement and read watch

**Files:**
- Modify: `lib/features/counseling/repositories/counselor_chat_repository.dart`
- Test: `test/features/counseling/counselor_chat_repository_test.dart`

**Interfaces:**
- Consumes: `isGuidanceQuickReplyText` (Task 1).
- Produces: `class QuickReplyNotAllowedException implements Exception`; `CounselorChatRepository.watchCounselorReadAt(String uid) → Stream<DateTime?>` as a concrete default (`Stream.value(null)`) in the abstract class so existing fakes still compile; Firestore implementation reads `counselor_threads/{uid}.counselorReadAt`.

- [ ] **Step 1: Write failing tests** with the existing `TestFirestore` doubles:
  - `send rejects free text before any write`: `send('student','m1','Hello')` throws `QuickReplyNotAllowedException`; no document written.
  - `send writes an approved reply`: `send(..., 'Noted.')` writes the message with that text.
  - `a delivered legacy message reconciles without a new write`: seed `messages/m1` with `text: 'Hello'`, sender student; `send('student','m1','Hello')` completes; write count unchanged.
  - `a retried approved reply with the same ID is idempotent`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement:** move the catalog check inside the transaction, after the existing-document branch, and throw `QuickReplyNotAllowedException`; keep the empty and length guard; add `watchCounselorReadAt`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(counseling): enforce quick replies in the chat repository`.

### Task 4: Send controller

**Files:**
- Modify: `lib/features/counseling/controllers/counselor_send_controller.dart`
- Test: `test/features/counseling/counselor_messaging_test.dart` (update the existing `draft` tests to `select` and `sendSelected`)

**Interfaces:**
- Consumes: `GuidanceQuickReply` (Task 1), `QuickReplyNotAllowedException` (Task 3).
- Produces on `CounselorSendController`: `GuidanceQuickReply? selected`; `void select(GuidanceQuickReply reply)`; `Future<void> sendSelected()`; `bool get pendingNotAllowed`; `Future<void> discardPending()`. `draft` and `send()` are removed.

- [ ] **Step 1: Write failing tests:**
  - `sendSelected sends the canonical text once and clears the selection after acknowledgment`; a second call while sending is ignored.
  - `nothing is sent without a selection`.
  - `failure keeps the selection and pending ID; retry reuses the ID` (replaces the old failure test).
  - `a restored legacy draft that the repository refuses is not resent`: outbox holds `('legacy-1','Hello')`, repository throws `QuickReplyNotAllowedException`; after `retry()` `pendingNotAllowed` is true, `error` equals "This earlier message can't be sent under the new Guidance Assistance policy. Discard it and choose a quick reply.", a second `retry()` makes no call, `discardPending()` clears the outbox and `pending`.
  - Keep the logging, outbox-isolation and storage-failure tests, rewritten to use `select` and `sendSelected`.
- [ ] **Step 2: Run** `flutter test test/features/counseling/counselor_messaging_test.dart --dart-define=APP_ENV=staging` → FAIL.
- [ ] **Step 3: Implement** the controller changes; `retry()` returns immediately while `pendingNotAllowed`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(counseling): send only the selected quick reply`.

### Task 5: Student screen, composer and indicators

**Files:**
- Create: `lib/features/counseling/widgets/guidance_quick_reply_composer.dart`
- Modify: `lib/features/counseling/screens/counselor_chat_screen.dart`
- Modify: `lib/features/counseling/widgets/counselor_message_timeline.dart` (bubble gains `bool read`; timeline gains `DateTime? counterpartReadAt`)
- Test: `test/features/counseling/counselor_messaging_test.dart`

**Interfaces:**
- Consumes: Tasks 1, 3, 4.
- Produces: `GuidanceQuickReplyComposer({required GuidanceQuickReply? selected, required ValueChanged<GuidanceQuickReply> onSelected, required VoidCallback? onSend, required bool sending, required bool collapsed, required VoidCallback onExpand, required VoidCallback onRequestSession, required VoidCallback onUrgentSupport})`; `CounselorMessageTimeline(... DateTime? counterpartReadAt)`; `CounselorMessageBubble(... bool read = false)` showing `Icons.done_all` with tooltip `Read` when read, else the existing `Sent` check.

- [ ] **Step 1: Write failing widget tests:**
  - `no text field; nine replies; Send disabled until one is selected` (`find.byType(TextField)` none).
  - `selecting then Send writes that reply and collapses the selector`; tapping `Reply` expands it.
  - `info icon shows the Guidance Assistance explanation` (exact text from Global Constraints).
  - `Request a counseling session` and `Urgent support` push `PaccCounselingScreen` (`startBooking` true for the first).
  - `own message shows Read only when counselorReadAt is at or after createdAt` (two messages either side of the watermark).
  - `legacy draft shows the policy message and a Discard button`.
  - Replace the small-screen test: 360×640 at text scale 2 → every reply chip reachable by scrolling and `Send` hit-testable, no exceptions.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the composer (`ChoiceChip`s in a `Wrap` inside a height-capped scroll area, Send `FilledButton`, the two `TextButton.icon` actions), wire it in place of `ServiceInquiryComposer`, add the app-bar info `IconButton` (tooltip `About Guidance Assistance`) opening a dialog, stream `watchCounselorReadAt` into the timeline.
- [ ] **Step 4: Run** the counseling tests → PASS.
- [ ] **Step 5: Commit** `feat(counseling): quick reply composer with sent and read indicators`.

### Task 6: Counselor portal read state and indicators

**Files:**
- Modify: `lib/features/counseling/widgets/counselor_unread_badges.dart` (`markThreadRead`, `sendCounselorReply`)
- Modify: `lib/features/admin/screens/counselor_messages_page.dart` (own-message status)
- Test: `test/features/counseling/counselor_unread_badges_test.dart`, `test/features/admin/` counselor page test if present

**Interfaces:**
- Produces: private `_touchCounselorReadAt(FirebaseFirestore db, String studentId)` doing `update({'counselorReadAt': FieldValue.serverTimestamp()})` and swallowing errors with `debugPrint('COUNSELOR_READ_AT_SKIPPED')`; portal bubble status `Sending` / `Sent` / `Read` where Read means thread `studentReadAt` ≥ message `createdAt`.

- [ ] **Step 1: Write failing tests:**
  - `markThreadRead also stamps counselorReadAt after the receipt`.
  - `a refused counselorReadAt update leaves the receipt and badge state intact` (fake throws `permission-denied` on that update only).
  - `sendCounselorReply commits the batch even when counselorReadAt is refused`.
  - portal: `own message shows Read once studentReadAt passes its createdAt`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement**, calling `_touchCounselorReadAt` after the awaited receipt write and after `batch.commit()`; never inside the batch.
- [ ] **Step 4: Run** → PASS, plus the existing badge tests.
- [ ] **Step 5: Commit** `feat(admin): read state and indicators for counselor messages`.

### Task 7: Verification and review

- [ ] `flutter analyze` → "No issues found!".
- [ ] `flutter test --dart-define=APP_ENV=staging` → all pass.
- [ ] Functions: `npm run build --prefix functions`, then with `SUPER_ADMIN_UID=functions-ci-super-admin` in the env and in `functions/.env.local`, run `firebase emulators:exec --config firebase.mood-v2.emulators.json --project demo-mindmate-mood-v2 --only auth,firestore,functions,storage "cd functions && npm test"` → 0 failed.
- [ ] `flutter build apk --debug --flavor staging --dart-define=APP_ENV=staging`; record path and SHA-256.
- [ ] `git diff --check origin/main...HEAD`; scan the diff for credentials.
- [ ] Independent review of the branch (superpowers:requesting-code-review), security focus on the rules; fix Critical and Important findings.
- [ ] Push, open the PR, record CI results.
