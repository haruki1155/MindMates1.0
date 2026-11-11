# Mood V2 Student Journey Implementation Plan

> **For agentic workers:** Execute locally with focused test-driven changes; preserve the existing dirty worktree and do not deploy.

**Goal:** Provide a calm, accurate personal mood check-in and journey while retaining multi-entry and retry semantics.

**Architecture:** Reuse the existing authenticated mood provider, normalized history, Manila calendar, and app routes. Keep research analytics and backend configuration outside this work.

**Tech Stack:** Flutter, existing Provider state and widget tests.

1. Baseline the existing Mood V2 logger, Home, and history tests. Preserve the feature flags and account guards.
2. Add failing widget tests for personal journey day grouping, labels, notes, and partial history; adapt the existing history panel and verify.
3. Add a dedicated journey screen using the existing provider, pagination and retry behavior, with correct Manila-day counts and coverage labels; exercise it with widget tests.
4. Wire the Home and confirmed-save actions to the journey and existing inSIGHT route; preserve the five-destination Home navigation and legacy path. Test navigation and multi-entry behavior.
5. Verify focused tests, formatting, analyzer, and relevant regression coverage; report manual checks and any unresolved limitations. Do not commit overlapping pre-existing work.
