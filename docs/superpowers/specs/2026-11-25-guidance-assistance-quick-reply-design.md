# Guidance Assistance: Quick Reply Only (PR A)

Status: approved by the owner on 2026-11-25 (Option A, Fixed Quick Replies, plus
sent and read indicators on both sides). Baseline: `main` at `e32b427`.

## Intent

Guidance Assistance becomes a counselor-led channel. Counselors keep writing
personalised instructions in free text. Students and other mobile app users answer
only with nine fixed replies. Anything that needs a real conversation goes to a
counseling session; anything urgent goes to the existing PACC crisis resources.

Both sides also see whether each of their messages was sent and whether the other
side has read it.

## Goals

- The nine approved replies are the only text an app user can send, enforced by the
  UI, the send path and the Firestore rules.
- Counselor free-text messaging, college scoping, read receipts and unread badges keep
  working as they do now.
- Each own message shows Sending, Sent or Read on both the app and the counselor portal.
- An undelivered legacy free-text draft is never sent, and a delivered one is
  reconciled under its existing ID, never duplicated.

## Non-goals

- No change to the message document schema (`senderId`, `senderRole`, `text`,
  `createdAt`) and no data migration. Historical messages stay as they are and remain
  readable.
- `ServiceInquiryComposer` and the other PACC service inquiry flows are not changed.
- No change to MindAid (that is PR B) or to counselor permissions.
- No deployment in this PR.

## Anti-goals

- A student able to send free text by a modified client or a direct Firestore write.
- Read indicators that break counselor unread badges when the Admin Web ships before
  the new rules.
- Any wording that suggests Guidance Assistance is monitored around the clock or suited
  to emergencies.

## Approaches considered

1. **Fixed replies validated on exact text, schema unchanged (chosen).** The rules keep
   an allowlist of the nine canonical strings. No migration, and old messages remain
   valid. The cost is that the text is duplicated in Dart and in the rules, so a test
   pins them together.
2. **Store a reply ID instead of text.** Cleaner data, but it changes the schema, needs
   every reader (portal, badges, backup export) to map IDs, and old clients would break.
3. **Server callable for student sends.** Strongest validation, but it adds a backend
   deploy and loses the offline-safe transaction path the app already uses.

## Design

### Reply catalog

`lib/features/counseling/data/guidance_quick_replies.dart` defines `GuidanceQuickReply`
(`id`, `text`) and the ordered list:

| ID | Text |
|---|---|
| understand | I understand. |
| noted | Noted. |
| thank_you | Thank you for your guidance. |
| clarification | I need clarification. |
| available | I am available. |
| unavailable | I am not available. |
| follow_up | I would like a follow-up session. |
| further_assistance | I need further assistance. |
| resolved | My concern has been addressed. |

A Flutter test reads `firestore.rules` and checks its allowlist equals the catalog texts,
in the same order.

### Firestore rules

`counselor_threads/{userId}/messages/{messageId}` create is split by sender:

- **Thread owner (app user):** as today, plus `text in guidanceQuickReplyTexts()`.
  Sender ID and role, the key set, `createdAt == request.time` and the thread linkage are
  unchanged. `signedIn()` keeps the first-login restriction.
- **Approved counselor:** unchanged (free text, 1 to 1,600 characters).

`counselor_threads/{userId}` update gains one counselor-only path: setting
`counselorReadAt` to `request.time`, alone or together with the existing reply keys. No
other role gains access. Reads, immutability and the receipt collection are unchanged.

### App send path

- `CounselorSendController` gains `selected` (a `GuidanceQuickReply?`), `select(reply)`
  and `sendSelected()`. It sends only the selected reply's canonical text. The text
  field and `draft` controller are removed.
- `CounselorChatRepository.send` keeps the same signature. Inside the transaction it
  first checks for an existing message with that ID (delivered: return, as today). Only
  then does it reject text that is not in the catalog, with a typed
  `QuickReplyNotAllowedException`. So a delivered legacy draft reconciles, and an
  undelivered one is refused without a write.
- On that exception the controller keeps the draft out of the outbox flow and shows:
  "This earlier message can't be sent under the new Guidance Assistance policy. Discard
  it and choose a quick reply." `discardPending()` clears the outbox entry.
- Existing behaviour stays: encrypted outbox per project and user, save-before-write,
  idempotent message IDs, retry, the account-switch guard.

### Student screen

`CounselorChatScreen` replaces `ServiceInquiryComposer` with a new
`GuidanceQuickReplyComposer`:

- Nine choice chips; one selected at a time; an explicit Send button, disabled while
  nothing is selected, while sending or while a message is pending.
- Sending shows progress; the timeline marks the message Sent only after the write
  is acknowledged; a failure keeps the reply with Retry.
- The selector collapses after a successful send behind a "Reply" button, and expands
  again on tap.
- Below it: "Request a counseling session" opens `PaccCounselingScreen(startBooking: true)`,
  the same entry the Home calendar uses, and "Urgent support" opens `PaccCounselingScreen`,
  whose "Need immediate help?" card holds the crisis contacts.
- An info icon in the app bar shows the owner's wording: "Guidance Assistance allows you
  to receive instructions from your guidance counselor and respond using predefined
  Quick Replies. For concerns requiring detailed discussion, please request a counseling
  session."
- The existing notice "Not a live emergency service." stays.

### Sent and read indicators

- **App, own message:** Sending (pending write), Sent (server-acknowledged), Read (the
  thread's `counselorReadAt` is at or after the message's `createdAt`).
  The repository adds `watchCounselorReadAt(uid)` on the thread document.
- **Portal, own message:** Sending, Sent, Read (the thread's `studentReadAt` is at or
  after the message's `createdAt`). The portal already holds thread documents.
- **Writing `counselorReadAt`:** after the existing receipt write in `markThreadRead`
  and `sendCounselorReply`, the portal sets `counselorReadAt` with a separate
  best-effort update. A failure is ignored, so badges keep working on the old rules
  until the new rules are deployed. On old rules, students simply see Sent instead of
  Read.
- "Read" means any approved counselor has opened the thread.

## Constraints

- No new dependencies. No deploys, merges or IAM changes.
- Rules change is additive and backward-compatible for counselors and readers.
- The Admin Web redeploys on merge; the rules do not. The portal therefore must work
  on both old and new rules.

## Release notes for later (Phase 4)

- After the rules deploy, older APKs still show a text box; their sends fail with the
  existing "check your account permissions" message. Release the new APK first, then the
  rules, inside a short announced window.
- Rolling the rules back restores unrestricted student text, so a rollback must re-apply
  the reply allowlist rather than restore the old ruleset.
- The PACC crisis card shows `+63 912 345 6789`, which looks like a placeholder. The
  owner must supply the real number; this PR does not change it.

## Builder's calls

- Collapse after a successful send; reopen by tapping "Reply".
- "Urgent support" opens the PACC counseling screen rather than dialling.
- The rules allowlist lives in a function `guidanceQuickReplyTexts()` near the counselor
  rules.
- Tests: a new `functions/src/counselor_messaging_rules.rules.ts` for the rules, and
  extensions to the existing counseling Flutter tests.
