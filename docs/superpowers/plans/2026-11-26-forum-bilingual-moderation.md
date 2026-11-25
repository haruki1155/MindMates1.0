# Forum Bilingual Moderation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Forum post, comment and alias passes server-side bilingual moderation before it can be published, and clients cannot write around it.

**Architecture:** A pure TypeScript engine (normalize, dictionary, match) used by two new callables and the alias callable; rules deny client creates; the app calls the callables and shows early warnings from a small client subset.

**Tech Stack:** TypeScript (Cloud Functions v2, node:test), Firestore rules, Flutter.

**Spec:** `docs/superpowers/specs/2026-11-26-forum-bilingual-moderation-design.md`

## Global Constraints

- Warning text, exactly: "MindMate is a safe and supportive community. Please revise your message using respectful language before publishing."
- Limits as today: post 8–500 chars, comment 3–400, 1–3 categories from the existing set.
- Never log or store rejected text. Fail closed.
- No new dependencies. No deploys.

## Review Focus

1. A legitimate word containing a restricted substring ("class", "assessment", "putahe", "titig", "leche flan") is allowed. Pinned in Task 1.
2. A mental-health disclosure ("I was abused", "I want to kill myself", "nag-self-harm ako") is never a profanity result. Pinned in Task 1.
3. Very long input (10,000 chars, many tokens) finishes quickly. Pinned in Task 1.
4. A retry of the same post ID by the same author succeeds once; another user gets `already-exists`. Pinned in Task 2.
5. Old clients writing directly are refused by rules. Pinned in Task 3.

---

### Task 1: Moderation engine

**Files:** Create `functions/src/moderation/normalize.ts`, `forum_dictionary.ts`, `forum_moderation.ts`, `forum_moderation_cases.json`; Test `functions/src/moderation/forum_moderation.test.ts`.

**Interfaces — Produces:** `moderateForumText(text: string): {allowed: boolean; categories: string[]; severity: 'none'|'low'|'high'}`; `FORUM_DICTIONARY_VERSION: string`; `isCrisisDisclosure(text: string): boolean`.

- [ ] Write failing tests driven by the JSON corpus: `blocked` cases (direct, Tagalog, Taglish, misspelled, confusables, zero-width, symbols/emoji, repeats, leet, spaced, phrases, affixes) and `allowed` cases (substring-safe words, respectful disclosures, ordinary Taglish), plus a 10,000-char performance case under 200 ms.
- [ ] Run `node --test lib/moderation/forum_moderation.test.js` after `npm run build` → FAIL.
- [ ] Implement the three modules.
- [ ] Run → PASS. Commit `feat(moderation): bilingual forum moderation engine`.

### Task 2: Publishing callables and alias moderation

**Files:** Modify `functions/src/index.ts`; Create `functions/src/secret_chat_publish.ts`; Test `functions/src/secret_chat_publish_callable_emulator.test.ts`.

**Interfaces — Produces:** callables `createSecretChatPost`, `addSecretChatComment` returning `{postId}` / `{commentId}`.

- [ ] Write failing emulator tests: allowed post and comment publish with server fields; profanity rejected with reason `inappropriate_language` and nothing written; crisis rejected with `crisis_support`; idempotent retry; other-user ID collision; rate limit; inactive post refuses comments; first-login refused; profane alias refused; rejection audit row has no text.
- [ ] Run inside the emulator → FAIL.
- [ ] Implement; export from `index.ts`.
- [ ] Run → PASS. Commit `feat(forum): publish posts and comments through moderated callables`.

### Task 3: Rules

**Files:** Modify `firestore.rules`; Modify `functions/src/firebase_secret_chat_rules.rules.ts`.

- [ ] Write failing rules tests: client create of post and comment refused; admin cannot change `message`; admin can change `moderationStatus`.
- [ ] Run → FAIL. Implement. Run → PASS. Commit `feat(rules): forum content is written only by the server`.

### Task 4: App

**Files:** Modify `lib/repositories/secret_chat_repository.dart`, `lib/providers/secret_chat_provider.dart`, `lib/features/secret_chat/domain/secret_chat_safety_validator.dart`, `lib/features/secret_chat/screens/secret_chat_thread_screen.dart`, `lib/features/secret_chat/widgets/secret_chat_compose_sheet.dart`; Tests under `test/features/secret_chat/`.

- [ ] Write failing tests: repository calls the callables with the same fields; server rejection maps to `SecretChatValidationException` with the warning text; validator flags client-subset terms (including disguised) with the warning text and leaves disclosures allowed; thread screen keeps the reply text after rejection; composer info icon shows the guideline.
- [ ] Run → FAIL. Implement. Run → PASS. Commit `feat(forum): moderated publishing and early warnings in the app`.

### Task 5: Verification and review

- [ ] `flutter analyze`; full `flutter test --dart-define=APP_ENV=staging`; Functions build and full emulator suite; `git diff --check`; credential scan.
- [ ] Independent review; fix Critical and Important findings.
- [ ] Build the staging APK; push; report.
