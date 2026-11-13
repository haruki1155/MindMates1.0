# MindMate Repository Agent Instructions

## REPOCHECK — safe Git repository status inspection

<!-- REPOCHECK_WORKFLOW_BEGIN -->

**Trigger:** When the user's entire message, after trimming surrounding whitespace, is `REPOCHECK` (case-insensitive), immediately execute this workflow using terminal access in the **currently active Git repository**. Do not merely print suggested commands. This instruction applies in future Codex sessions that load this repository's `AGENTS.md`.

**Purpose:** Report local Git status and retrieve up-to-date remote *metadata*. `REPOCHECK` does **not** synchronize the working files or change branches. If terminal or network permission is needed, request the required authorization. If tools are unavailable, report that the check could not be executed; never fabricate a result.

1. **Identify the repository.** Run `git rev-parse --show-toplevel`. If not in a Git repository, stop and report that. In the verified repository, inspect the current branch with `git branch --show-current` and identify the remote repository using `git remote -v`. Do not assume a branch or remote exists.
2. **Inspect the working tree.** Run `git status --short --branch` and distinguish staged, unstaged/modified, deleted, and untracked files. Do not modify them.
3. **Refresh remote metadata only.** Run `git fetch --all`. Never merge, rebase, pull, or otherwise apply fetched changes. If fetching fails, show the actual error and mark all remote tracking information and ahead/behind comparisons as **potentially stale**. If it succeeds, say **remote tracking metadata fetched**—not that working code was updated.
4. **Inspect remotes, tracking, and history.** Run `git remote -v`, `git branch -vv`, and `git log -5 --oneline --decorate`. If there are fewer than five local commits, report only those available.
5. **Compare upstream only if it exists.** Check for an upstream using `git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'`. If it succeeds, run `git rev-list --left-right --count 'HEAD...@{upstream}'` and `git log --oneline --max-count=10 'HEAD..@{upstream}'`. For `HEAD...@{upstream}`, the **first count is local ahead** (HEAD-only commits) and the **second is remote behind** (upstream-only commits). Show incoming commits when present. If there is no upstream, explicitly say **No upstream configured** and do not invent a comparison or infer it from `origin/main`.
6. **Summarize local changes.** Run `git diff --stat` and `git diff --cached --stat` to separately show unstaged and staged changes, without changing any files.
7. **Report concisely.** Include repository name/root, branch (or detached HEAD), remotes, fetch success/error, working-tree status, local ahead and remote behind counts if an upstream exists, latest five local commits, up to ten incoming upstream commits, staged/unstaged diff summaries, and whether a pull **may** be needed. If the fetch failed, flag comparisons as potentially stale. If the working tree is dirty, call that out before suggesting any future synchronization. Report only what commands actually confirmed.

**Safety rules for REPOCHECK:**

- Never run `git pull`, `git merge`, `git rebase`, `git reset`, `git checkout`, `git switch`, `git stash`, `git push`, `git commit`, `git clean`, or file deletion as part of this keyword.
- Never overwrite local changes or alter application source files, configuration files, or repository documentation.
- Never claim local files or the repository have been synchronized or updated merely because `git fetch --all` succeeded. Only remote tracking metadata may have changed.
- Never assume an upstream branch exists, and never invent ahead/behind counts.
- Ask for authorization if terminal access, credentials, or network access require it; report any denied permissions.
- `REPOCHECK` is status inspection plus remote fetch only; it is **not** local-code synchronization.
- Prefer noninteractive output (for example, `GIT_PAGER=cat`) so command results do not get stuck in a pager.

<!-- REPOCHECK_WORKFLOW_END -->
