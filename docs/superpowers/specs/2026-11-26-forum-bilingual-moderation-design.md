# Forum (Secret Chat) strict bilingual moderation

Status: approved by the owner on 2026-11-26. Baseline: `main` at `8f57dcc`.

## Intent

No profanity, slur, harassment or disguised version of them can be published in the
Forum, in English, Tagalog or Taglish. The server decides; the app only warns early.
Students can still talk honestly about depression, anxiety, self-harm or abuse.

## Today

- The app writes posts (`secret_chats`) and comments (`secret_chat_comments`) straight
  to Firestore. Rules check shape and length only.
- The only content check is the client `SecretChatSafetyValidator` (crisis redirect,
  personal info, off-topic, a short unsafe list).
- No titles, no replies (comments are flat), no user edits. Admins may update anything.
- Aliases are saved by the `saveSecretChatProfile` callable, without a content check.

## Approaches

1. **Server publishes (chosen).** Callables moderate, then write with the Admin SDK;
   rules deny client creates. Nothing unvalidated is ever visible.
2. Client writes `pending`, a trigger approves or rejects. Content is never visible
   unvalidated, but rejection arrives asynchronously and the draft is gone.
3. Client writes, a trigger hides bad content afterwards. Unvalidated content is briefly
   public. Rejected.

## Design

### Moderation engine (`functions/src/moderation/`)

- `forum_dictionary.ts`: versioned entries `{term, language, category, severity,
  kind: 'token' | 'phrase', affixes?: boolean}` plus contextual exceptions (for example
  "leche flan"). Categories: profanity, vulgar, sexual, discriminatory, harassment.
  Server-only; never shipped to the app.
- `normalize.ts`: NFKC; lower case; remove zero-width and invisible characters; strip
  combining marks; map confusable letters (Cyrillic, Greek) and leetspeak to Latin;
  tokenize on whitespace; strip symbols and emoji inside a token; collapse repeated
  letters. Also builds joined forms for spaced-out letters ("f u c k") and adjacent short
  token pairs ("fu ck"). Bounded: length is capped before processing, and there is no
  user-controlled regex and no backtracking pattern.
- `forum_moderation.ts`: `moderateForumText(text) → {allowed, categories, severity}`.
  Whole-token matches only; Filipino affix variants come from a fixed prefix list (ka,
  pinaka, naka, nakaka, mag, pag) and suffix list (mo, ka, ng, han, an, in) applied to
  entries marked `affixes`. Phrases match normalized token sequences. Mental-health words
  are never dictionary entries.
- Crisis language: the client's existing crisis list is mirrored on the server and returns
  the existing redirect to MindAid/PACC (not a profanity result).

### Publishing callables

- `createSecretChatPost({postId?, message, categories, safetyLabels})` and
  `addSecretChatComment({postId, commentId?, message, safetyLabels})`.
- Auth via `requireAuthenticatedUser` (includes the first-login gate). Same length,
  category and label limits as the old rules. Idempotent on the client-chosen ID: the
  same author retrying gets success, anyone else `already-exists`.
- Rate limits per user: 5 posts and 20 comments per 10 minutes.
- Rejection: `invalid-argument` with reason `inappropriate_language` and the message
  "MindMate is a safe and supportive community. Please revise your message using
  respectful language before publishing."; crisis: `failed-precondition` with reason
  `crisis_support`.
- Fail closed: any moderation error becomes `unavailable`; nothing is written.
- Audit: rejections write `_secret_chat_moderation_events` with user, kind, categories,
  severity and time. Never the text. No log line contains the text.
- `saveSecretChatProfile` moderates the alias the same way.

### Rules

- `secret_chats` and `secret_chat_comments`: `create: false` for clients.
- Admin updates limited to `moderationStatus`, `safetyLabels` and `updatedAt`, so no
  role can rewrite published text. Reads and deletes unchanged.

### App

- Repository calls the callables. Errors with reason `inappropriate_language` or
  `crisis_support` become the existing `SecretChatValidationException`.
- A small client subset (most common terms, same normalization) shows the warning as the
  user types and disables Post/Send. The full dictionary stays on the server.
- Drafts survive rejection: the thread screen restores the reply text on failure; the
  compose sheet already keeps it.
- An info icon on the composer explains the community language guideline in one line.

## Non-goals

- No edit or reply feature (none exists). The server is now the only writer, so a future
  edit flow must go through it.
- Personal-info and off-topic checks stay client-side as today.

## Release

- Deploy order: new APK, then the two callables and `saveSecretChatProfile`, then rules.
  Older APKs cannot post or comment once the rules are live.
- Rolling back the rules re-opens direct writes; roll back Functions and rules together.

## Limitations

No dictionary catches every variant; the adversarial test corpus defines what is
guaranteed. Context (sarcasm, coded language) is out of reach of token matching.
