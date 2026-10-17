# castor — Contributor Guide

## What castor is

castor is a team plugin in a public repo (github.com/msanyam/castor, marketplace at the repo root) for building features in existing codebases. It absorbed [superpowers](https://github.com/obra/superpowers) v7.0.0 (MIT, Jesse Vincent) with full git history, and adds git maintenance skills and a session-diagnosis skill. The workflow skills (brainstorming, planning, TDD, debugging, review) are upstream content. `diagnose-castor` is upstream's `diagnosing-superpowers` skill, renamed and retargeted to castor. The git cleanup skills and the plugin packaging are castor's own. Keep internal detail out of the repo. Why: it is public.

## Naming rule

Keep upstream names and conventions where castor carries upstream content; use castor names everywhere else. Why: every renamed or rewritten upstream file becomes a merge conflict on the next merge from superpowers, and the superpowers-evals scenarios check upstream paths (`.superpowers/sdd`, `docs/superpowers/specs`, `docs/superpowers/plans`).

| Keep upstream | Castor name |
|---|---|
| Upstream skill dirs and `name:`s | Plugin, marketplace, repo URLs |
| `superpowers:<name>` cross-references in upstream skill text (bridged by a one-line alias in hooks/session-start) | New skills and agents |
| Output paths in user projects (`docs/superpowers/specs`, `docs/superpowers/plans`, `.superpowers/sdd`) | Castor config/state (`.claude/castor.yaml`, `.claude/castor/<agent>.md`, `~/.castor/`) |
| hooks/session-start structure and the using-superpowers bootstrap | diagnose-castor |
| Upstream tests for kept code | AGENTS.md, README, issue template |

Edit an upstream file only when castor must behave differently, and keep the edit minimal. Why: each edit is a future merge conflict.

## Pulling upstream

```bash
git remote add superpowers https://github.com/obra/superpowers.git   # once
git fetch superpowers
git merge superpowers/main
```

Upstream files castor edits in place: hooks/session-start, skills/brainstorming/scripts/server.cjs, tests/brainstorm-server/branding.test.js, tests/hooks/test-session-start.sh, tests/claude-code/run-skill-tests.sh, skills/diagnose-castor/**, tests/diagnose-castor/**, `.github/ISSUE_TEMPLATE/diagnosis_report.md`, `.gitignore`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, README.md, AGENTS.md.

Conflict rules:

- Modify/delete on a file castor cut: `git rm` it. Why: a cut unit only conflicts when upstream edits it, and re-deleting it costs nothing.
- Content conflict in a castor-edited file: keep castor's version and re-apply the upstream change by hand. Why: taking upstream's side silently reverts castor's intended change.
- `.claude-plugin/*.json`: always keep castor's name (`castor`) and castor's version. Why: upstream bumps the version every release, and taking upstream's renames the plugin to superpowers, breaking every `castor:<name>`.
- README.md and AGENTS.md were replaced outright: drop upstream's changes to them.

After every merge, check what arrived without conflict, then re-run the tests. Why: new upstream files under cut paths and new upstream lines in diagnose-castor merge silently.

```bash
git grep -n -E "obra/superpowers|\.superpowers/diagnosing|diagnosing-superpowers" -- skills/diagnose-castor .github   # must return nothing
git diff --name-status --diff-filter=A ORIG_HEAD HEAD   # new files under cut paths (harness manifests, docs/superpowers/**, tests/<harness>/): git rm them
```

Why: a stray upstream URL in diagnose-castor would file castor users' session reports on upstream's public tracker.

## Tests

Run each line from the repo root.

```bash
claude plugin validate .
npm ci --prefix tests/brainstorm-server
npm test --prefix tests/brainstorm-server
bash tests/hooks/test-session-start.sh
bash tests/hooks/test-run-hook-cmd-windows.sh
bash tests/shell-lint/test-lint-shell.sh
bash tests/claude-code/test-sdd-workspace.sh
bash tests/claude-code/test-executing-plans-scripts.sh
bash tests/systematic-debugging/test-find-polluter.sh
bash tests/writing-skills/test-render-graphs.sh
bash tests/diagnose-castor/test-skill-structure.sh
```

The LLM-driven suites (`tests/claude-code/test-subagent-driven-development*.sh`, `tests/claude-code/test-worktree-native-preference.sh`, `tests/explicit-skill-requests`) run only on request. Why: they run real Claude sessions in permissive modes and take 3–30+ minutes each.

## One-time setup

The `automated-issue-report` label must exist on msanyam/castor: `gh label create automated-issue-report --repo msanyam/castor`. Why: diagnose-castor's `gh issue create --label` aborts when the label is missing.

## Design docs

Design docs live in `docs/castor/` (gitignored, local).
