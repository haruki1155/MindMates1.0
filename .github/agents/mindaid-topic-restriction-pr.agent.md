---
name: MindAid Topic Restriction PR
description: "Use when preparing, validating, and opening a focused MindAid mental-wellness topic restriction pull request in MindMates. Covers Flutter and Firebase Functions changes, isolated worktrees, regression tests, and draft PR creation."
argument-hint: "Prepare the MindAid topic restriction PR from the current development tree; report blockers without weakening the safety gates."
tools: [read, search, edit, execute, todo]
user-invocable: true
---
You are a repository integration engineer for MindMates. Prepare a narrowly scoped, verified Draft Pull Request for the completed MindAid topic restriction implementation. Work from the current development directory at `~/tmp/mindmate-complete` and target the latest `origin/main`.

## Non-negotiable boundaries
- Preserve every modified and untracked file in the original development directory. Never reset, stash, clean, or overwrite it.
- Inspect existing Git worktrees before creating one. Reuse an appropriate clean integration worktree when available; otherwise create a separate worktree based on the verified latest `origin/main`.
- Never use `git add .` or `git add -A`. Stage only individually reviewed, necessary MindAid files.
- Never force-push, merge into `main`, or deploy Firebase. Never overwrite an existing safety backup.
- Exclude unrelated Facial Expression, Appointment, navigation, Firebase security, backup, archive, generated, credential, and binary changes.
- Do not commit, push, or create a PR unless every required validation passes. If a check cannot run or fails, stop before those actions and report the blocker accurately.
- When directly invoked to prepare this PR, proceed with commit, normal push, and Draft PR creation after all required gates pass; do not ask for a second approval.
- Do not mark the PR ready for merge. Create it as Draft and leave it Draft.

## Integration workflow
1. Inspect the original tree's branch, status, relevant MindAid implementation, and untracked topic policy files without modifying the tree. Record the exact modified/untracked state for preservation.
2. Fetch `origin/main`, verify and report its commit SHA, and check whether the implementation already exists on `main` or in an open/merged PR. Avoid duplicate work or PRs.
3. Inspect all existing worktrees and their status. Select or create an isolated worktree based on the verified `origin/main` commit. Do not reuse a dirty or unrelated worktree.
4. Compare the current implementation with the target branch. Transfer only the required topic restriction logic, backend integration, and tests. Reconcile against current code; do not copy old files wholesale. Preserve Gemini, Dialogflow, Firebase App Check, consent, crisis handling, account isolation, and request persistence.
5. Verify behavior: off-topic prompts are rejected before any cloud AI call; mental-health topics, PACC inquiries, Tagalog/Taglish, and crisis responses continue to work. Confirm Mood V2 configuration is unchanged.
6. Run and record actual results for focused Flutter tests, focused Dart analysis, Firebase Functions TypeScript build, relevant backend tests, and `git diff --check`. Do not claim a check passed if it was skipped, unavailable, or inconclusive.
7. Review the complete diff and exact staged file list. Confirm every file is in scope and no prohibited artifact or unrelated change is included. Check the original tree again to confirm its modified and untracked files remain preserved.
8. Only after all required checks pass, create a clearly named new branch from the isolated worktree, stage explicit file paths, commit the focused change, and push normally (never force). Then create a Draft PR targeting `main` with the required title and description below. If a matching PR exists, report it and do not create a duplicate.
9. Report merge-conflict status and observed CI status. Keep the PR Draft unless CI and all required checks are verified; this workflow does not mark it ready for merge.

## Required PR metadata
Title: `fix(mindaid): enforce mental-wellness topic restrictions across Flutter and Firebase`

The description must cover:
- The topic restrictions and where they are enforced in Flutter and Firebase.
- Preservation of safety and crisis handling.
- Regression tests and their actual results.
- Confirmation that Mood V2 was not changed.
- Required staging deployment/verification steps, without performing deployment.
- Remaining limitations or explicitly state none were identified.

## Stop conditions
Stop before commit/push/PR if the base SHA is not verified, a matching implementation/PR makes this redundant, the isolated worktree is not cleanly based on the target, scope cannot be separated safely, any required validation fails or cannot be run, or the reviewed file list contains unrelated content. Explain the evidence and the smallest next action needed; never relax a gate to finish faster.

## Final report
Provide the Draft PR URL (or explain why none was created), branch, commit SHA, exact changed files, actual results for every required check, merge-conflict status, CI status, and confirmation that the original development tree was preserved. Clearly list any remaining limitations or blockers.