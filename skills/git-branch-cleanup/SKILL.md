---
name: git-branch-cleanup
description: Use when the user wants to clean up, prune, or delete stale git branches — local branches whose remote is gone or whose PR was merged, and remote branches already merged — verifying each is safe and confirming before deleting
argument-hint: "[--dry-run] [--local] [--remote]"
disable-model-invocation: true
---

# Git Branch Cleanup

Find local and remote branches whose work is provably merged, show them, and delete them after confirmation. Local and remote are confirmed separately. Why: deleting a local branch is recoverable from the reflog for a while; deleting a remote branch is outward-facing and affects everyone who fetches.

**Core principle:** "remote is gone" does not mean "merged". A branch is deleted only when its exact tip is proven to be in the default branch, or in a merged PR. Everything else is reported and left alone.

## Flags

| Flag | Effect |
|---|---|
| `--dry-run` | Stop after the report. Change nothing. |
| `--local` | Local branches only. |
| `--remote` | Remote branches only. |

No scope flag means both. Flags: $ARGUMENTS

## Process

### 1. Orient

Separate read-only calls, run in parallel where independent:

- Default branch, first that works: `git symbolic-ref --short refs/remotes/origin/HEAD`, then `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, then `git ls-remote --symref origin HEAD`. Why: `origin/HEAD` is often unset, and guessing `main` misclassifies a `master` repo.
- `git fetch --prune origin`. Why: merge checks use `origin/<default>`, and `--prune` is what turns deleted remotes into `[gone]` upstreams.
- `git branch --show-current`, and `git worktree list --porcelain` for every branch checked out in any worktree.
- `git config user.email`.

**Protected, never candidates:** the default branch, `main master develop staging production`, `release/*`, the current branch, and any branch checked out in a worktree. Why: git itself refuses to delete a checked-out branch, and the rest are long-lived by convention. This skill never needs to `git checkout` anything, so it never disturbs your working tree.

### 2. Classify local branches

List with `git for-each-ref --format='%(refname:short)|%(objectname)|%(upstream:short)|%(upstream:track)|%(committerdate:relative)|%(subject)' refs/heads`. Why: the `track` field gives `[gone]` directly; grepping `git branch -vv` output breaks on branch names containing "gone" and on column wrapping.

For each non-protected branch, gather evidence in parallel:

| Evidence | Command |
|---|---|
| Ancestor of default | `git merge-base --is-ancestor <tip> origin/<default>` |
| PR merged with this exact tip | `gh pr list --head <branch> --state merged --json number,headRefOid` where `headRefOid` equals `<tip>` |
| Open PR | `gh pr list --head <branch> --state open --json number` |
| Upstream gone | `track` is `[gone]` |
| No upstream | `upstream` is empty |
| Unpushed commits | `track` contains `ahead` |

| Class | Condition | Proposed |
|---|---|---|
| `MERGED` | ancestor of default | delete |
| `SQUASH-MERGED` | merged PR whose `headRefOid` equals the tip | delete |
| `GONE-UNPROVEN` | upstream gone, neither proof above | **keep**, report |
| `OPEN-PR` | open PR | keep |
| `LOCAL-ONLY` | no upstream, not merged | keep |
| `AHEAD` | unpushed commits, not merged | keep |

Why the exact-tip match: if commits were added after the PR merged, the branch tip differs from `headRefOid` and those commits exist nowhere else. A bare "PR merged" check would delete them. Why `GONE-UNPROVEN` is kept: a remote branch can be deleted without merging (closed PR, manual cleanup), and force-deleting every `[gone]` branch is how unmerged work gets lost.

If `gh` is unavailable or unauthenticated, only the ancestor check runs; say so in the report, and `SQUASH-MERGED` branches show up as `GONE-UNPROVEN`.

### 3. Classify remote branches

List with `git for-each-ref --format='%(refname:short)|%(objectname)|%(authoremail)|%(committerdate:relative)' refs/remotes/origin`, skipping `origin/HEAD` and protected names.

| Class | Condition | Proposed |
|---|---|---|
| `MERGED` | ancestor of `origin/<default>` | delete if own |
| `SQUASH-MERGED` | merged PR whose `headRefOid` equals the remote tip | delete if own |
| `OPEN-PR` | open PR | keep |
| `OTHERS` | tip author email is not `git config user.email` | report only, never proposed |
| `STALE-UNMERGED` | not merged, no open PR | report with last-commit age, never proposed |

Why only your own branches: deleting a teammate's branch is outward-facing and was never asked for. Why stale-unmerged is report-only: age is not evidence the work is done. Many repos also enable GitHub's "automatically delete head branches", in which case the `MERGED` remote set is usually empty; say so when it is.

### 4. Report, then ask

Print everything before asking:

```
=== Branch Cleanup — <repo> (default: <default>, you: <email>) ===
LOCAL
  delete   feat/login       MERGED          9f3a1c2  merged into main
  delete   fix/typo         SQUASH-MERGED   41be07d  PR #52 merged
  keep     wip/spike        GONE-UNPROVEN   7c20aa1  remote deleted, no merge found
  keep     feat/new         OPEN-PR         e18d9b0  PR #60 open
REMOTE (origin)
  delete   origin/feat/login  MERGED         yours
  keep     origin/their/x     OTHERS         a@b.com, 40d ago
  keep     origin/old/y       STALE-UNMERGED yours, 120d ago, no PR
```

With `--dry-run`, stop here.

Otherwise ask with AskUserQuestion, **one question for the local set and a separate one for the remote set** (skip a question whose set is empty or whose scope flag excluded it). Name every branch in the question. Why: one blanket "yes" must never cover remote deletes the user didn't read.

### 5. Execute

**Before deleting anything**, print a restore line per branch using the SHA already collected: `git branch <name> <sha>` for local, `git push origin <sha>:refs/heads/<name>` for remote. Why: this is the only recovery path once the reflog entry expires or the remote branch is gone.

Delete one branch per call, so one failure doesn't hide the others:

- **Local:** `git branch -d <name>`. If git refuses because the branch is merged to the default branch but not to the current HEAD, or because it is `SQUASH-MERGED` (git cannot see squash merges), use `git branch -D <name>`. The tip was already proven merged in step 2, which is the check `-d` would have made. Why: using `-D` blindly is what the reference approach does, and it skips the only safety net.
- **Remote:** `git push origin --delete <name>`.

**If a delete is denied by the permission rules, stop.** Do not substitute an equivalent (`git update-ref -d`, `git push origin :<name>`, `git branch --delete --force`, editing `.git/refs`). Print the remaining approved commands as a copy-paste block and tell the user to run them. Why: a denial is the user's deliberate gate on destructive git, and a workaround defeats the gate rather than satisfying it. Some setups deny `git branch -d/-D` outright, so expect to land here.

### 6. Verify and report

Run `git fetch --prune origin`, then `git branch -vv` and `git branch -r`, and compare against the approved set.

```
Deleted local:   feat/login, fix/typo
Deleted remote:  origin/feat/login
Kept:            wip/spike (GONE-UNPROVEN), feat/new (OPEN-PR), 2 remote (OTHERS / STALE-UNMERGED)
Not run:         0 denied
Restore:         git branch feat/login 9f3a1c2 · git branch fix/typo 41be07d
```

If worktrees pin branches that would otherwise be deleted, say so and point at `/castor:git-worktree-cleanup`.

## Rules

| Rule | Why |
|---|---|
| Never delete the current branch, a protected branch, or one checked out in a worktree | Git refuses or the loss is large; none are stale by definition. |
| Never delete on `[gone]` alone | The remote may have been deleted unmerged; the local copy may be the last one. |
| Never delete a branch whose tip differs from the merged PR's `headRefOid` | Post-merge commits exist nowhere else. |
| Remote deletes need their own confirmation and cover only your own branches | Outward-facing, visible to the whole team. |
| No `git checkout`, no bare `git stash` | A checkout disturbs the working tree for no benefit here, and the stash stack is shared across worktrees. |
| No `cd <path> && git ...`; use `git -C <path>` | Keeps each call one command, so permission rules match it. |
