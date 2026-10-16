---
name: git-worktree-cleanup
description: Use when the user wants to clean up, prune, or remove stale git worktrees or Conductor workspaces — finds merged, abandoned, and orphaned worktrees, shows disk usage, and removes only what is provably safe after confirmation
argument-hint: "[--dry-run] [--all]"
disable-model-invocation: true
---

# Git Worktree Cleanup

Inventory every worktree, classify it from evidence, and remove only the ones whose work is provably safe elsewhere. Worktrees only: branches are left alone and handled by `/castor:git-branch-cleanup`. Why: one skill per reason to change, and a removed worktree frees its branch for that skill to judge.

**Core principle:** read-only inventory first, one confirmation, then removal without `--force`. A worktree holds uncommitted files, ignored files, and sometimes the only copy of commits; none of that is recoverable once the directory is gone.

## Flags

| Flag | Effect |
|---|---|
| `--dry-run` | Stop after the report. Change nothing. |
| `--all` | After the safe set, also walk unmerged-but-clean worktrees one at a time, asking keep/remove for each. Dirty worktrees are never offered. |

Flags: $ARGUMENTS

There is deliberately no `--force`. Why: it is the flag that turns a dirty worktree into lost work, and a user who wants it can run `git worktree remove --force` themselves.

## Process

### 1. Orient

Run as separate calls (they don't depend on each other):

- `git worktree list --porcelain` — path, HEAD, branch, `locked`, `prunable`, `detached` per entry.
- `git rev-parse --show-toplevel` — the worktree you are standing in.
- Default branch, first that works: `git symbolic-ref --short refs/remotes/origin/HEAD`, then `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, then `git ls-remote --symref origin HEAD`. Why: `origin/HEAD` is unset in repos that were `git init`ed then given a remote, and guessing `main` misclassifies everything on a `master`/`develop` repo.
- `git fetch --prune origin`. Why: "merged" is judged against `origin/<default>`; a stale local ref reports merged work as unmerged, or the reverse.

### 2. Exclude, never touch

Drop these from the candidate set and list them as kept, with the reason:

| Entry | Why it is never removed |
|---|---|
| First entry in the list (main checkout) | It owns the `.git` directory every other worktree points at. |
| The worktree you are in (`--show-toplevel`) | Removing your own cwd breaks the session mid-run. |
| `locked` | The lock is someone's explicit "do not remove"; the reason is shown by `git worktree list --porcelain`. |
| Branch is the default or a protected name (`main master develop staging production release/*`) | Long-lived; removing the checkout is rarely intended. |

### 3. Gather evidence per worktree

Run these for all candidates in parallel; they are independent read-only calls.

- **Missing directory** (`prunable` in the porcelain output) → class `ORPHAN`. Needs no further evidence.
- **Dirty:** `git -C <path> status --porcelain` — any output (modified or untracked) → class `DIRTY`.
- **Ignored files worth keeping:** `git -C <path> status --porcelain --ignored`, then look for a non-empty `.context/` and for `.env*`. Report them as a warning on the row. Why: gitignored files are invisible to every merge check but are often the only copy of agent notes and local config.
- **Unpushed commits:** `git -C <path> rev-list --count @{u}..HEAD`; with no upstream, `git -C <path> rev-list --count origin/<default>..HEAD`.
- **Merged**, any one of:
  1. branch tip is an ancestor of `origin/<default>` (`git merge-base --is-ancestor <tip> origin/<default>`);
  2. `gh pr list --head <branch> --state merged --json number,headRefOid` returns a PR whose `headRefOid` equals the branch tip. Why: squash and rebase merges never make the tip an ancestor, and ancestry alone would keep nearly every PR branch forever. The tip must match so commits added after the merge are not mistaken for merged work.
- **Detached HEAD:** `git -C <path> branch --contains HEAD` empty and HEAD not an ancestor of `origin/<default>` → class `DETACHED-UNREACHABLE` (keep, warn). Why: those commits are reachable from nowhere else.
- **Disk usage:** `du -sk <path>` per worktree. Why: reclaimed space is the report's headline number, and `node_modules` is real disk.

### 4. Classify

| Class | Condition | Action |
|---|---|---|
| `ORPHAN` | directory missing | `git worktree prune` |
| `MERGED` | merged, not dirty, 0 unpushed | remove (proposed) |
| `UNMERGED-CLEAN` | not merged, not dirty | keep; with `--all`, ask per worktree |
| `DIRTY` | uncommitted or untracked changes | keep, report what is dirty |
| `DETACHED-UNREACHABLE` | see above | keep, warn |

When evidence is missing (no `gh`, offline, no PR found), fall back to the ancestry check alone and downgrade to `UNMERGED-CLEAN`. Why: an unproven "merged" is a guess, and the cost of a wrong guess is deleted work.

### 5. Report, then ask

Print the table before asking anything:

```
=== Worktree Cleanup — <repo> (default: <default>) ===
PATH                      BRANCH          CLASS            SIZE    NOTES
../bern                   feat/x          (current)        120M    kept: you are here
../oslo                   fix/login       MERGED           340M    PR #41 merged
../lima                   feat/y          UNMERGED-CLEAN   210M    3 commits ahead, last 12d ago
../rome                   wip/z           DIRTY            90M     4 modified, .context/ non-empty
../paris                  —               ORPHAN           0       directory missing

Would remove: 1 worktree (340M) · prune: 1 orphan
```

With `--dry-run`, stop here.

Otherwise ask once (AskUserQuestion) with the `MERGED` set pre-selected and the paths named. Why: removal is irreversible, and the user can see in one place everything that will go.

**Conductor workspaces.** Worktrees under `~/conductor/workspaces/` are tracked by Conductor. Say so in the question and recommend archiving those from the Conductor UI instead. Why: `git worktree remove` deletes the directory but leaves Conductor listing a workspace that no longer exists.

### 6. Execute

Per approved worktree, one call each so a failure doesn't abort the rest:

1. `git worktree remove <path>` — **no `--force`**. If git refuses (dirty, locked, submodules), report the refusal and move on; do not retry with `--force`. Why: git's refusal is the same check as step 3 catching something this run missed.
2. After all removals, `git worktree prune`.
3. `git worktree list` to confirm the final state.

Do not delete branches here. If a removed worktree's branch is now unused, say so and point at `/castor:git-branch-cleanup`.

### 7. Final report

```
Removed:   oslo (fix/login) 340M
Pruned:    1 orphan
Kept:      bern (current), lima (UNMERGED-CLEAN), rome (DIRTY)
Reclaimed: 340M · Worktrees remaining: 3
Next:      branch fix/login can now be cleaned with /castor:git-branch-cleanup
```

## Rules

| Rule | Why |
|---|---|
| Never `git worktree remove --force` or `rm -rf` a worktree | Both skip the dirty/locked checks and leave dangling metadata (`rm -rf`) or lose uncommitted work (`--force`). |
| Never read or touch the main checkout's files | The main checkout is another session's working directory; only `git worktree` metadata commands cross it. |
| Never use bare `git stash` | The stash stack is shared across all worktrees; another session's changes can be popped. |
| No `cd <path> && git ...`; use `git -C <path>` | Keeps each call one command, so permission rules match it and a failed `cd` can't run git in the wrong repo. |
| One confirmation covers only the set that was shown | Anything discovered afterwards goes back to the user. |
