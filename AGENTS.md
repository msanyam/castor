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
# bash tests/evals/test-stage-scenarios.sh      # paused with evals, see ## Evals
# bash tests/evals/test-summarize-baseline.sh
```

The LLM-driven suites (`tests/claude-code/test-subagent-driven-development*.sh`, `tests/claude-code/test-worktree-native-preference.sh`, `tests/explicit-skill-requests`) run only on request. Why: they run real Claude sessions in permissive modes and take 3–30+ minutes each.

## One-time setup

The `automated-issue-report` label must exist on msanyam/castor: `gh label create automated-issue-report --repo msanyam/castor`. Why: diagnose-castor's `gh issue create --label` aborts when the label is missing.

## Evals

Paused on 2026-11-08. A full baseline is projected at $30–70 on Bedrock, over the $2 eval budget. `scripts/evals/run-baseline` exits early, and the section below is commented out until evals get revisited at the end of the castor work.

<!--
Behavioral evals run the upstream harness ([superpowers-evals](https://github.com/prime-radiant-inc/superpowers-evals), CLI `quorum`) against castor. The harness lives in `evals/` (gitignored clone, never edited; `git pull` updates it). Castor's own glue is `scripts/evals/`.

One-time setup:

```bash
brew install oven-sh/bun/bun                       # bun >= 1.3.14
git clone https://github.com/prime-radiant-inc/superpowers-evals evals
(cd evals && bun install)
git clone https://github.com/prime-radiant-inc/gauntlet ~/.castor/gauntlet
(cd ~/.castor/gauntlet && bun install --ignore-scripts && bun link)
export PATH="$HOME/.bun/bin:$PATH"                 # add to your shell profile
brew install uv                                    # runs scripts/evals/bedrock-token
# AWS credentials: an AWS CLI profile with Bedrock access (AWS_PROFILE picks it)
```

`bun link` installs `gauntlet` into `~/.bun/bin`, which is not on PATH by default. Why: the runner's preflight fails on a missing `gauntlet` instead of fixing PATH for you, so a setup gap stays visible. Install Gauntlet with `--ignore-scripts`. Why: Gauntlet's `prepare` script runs `scripts/install-hooks.sh`, which writes a `bun run typecheck` pre-commit hook to `git rev-parse --git-path hooks`. With a global `core.hooksPath`, that resolves to the global hooks dir. The hook then overwrites the global pre-commit and blocks commits in every repo without a `typecheck` script. This happened on 2026-11-08. The runner mints a 12-hour Bedrock API key from your AWS profile before each trial (`scripts/evals/bedrock-token`, AWS's `aws-bedrock-token-generator`) and passes it in the run's environment, never in argv. The harness then writes it only to the run's private (0600) agent env file under `~/.castor/eval-runs/`. Why: the harness's Claude launcher clears the environment (`env -i`) and accepts only a Bedrock bearer key on Mantle, so `AWS_PROFILE` can't reach the agent directly. A key minted per trial can't expire partway through the run.

Run the baseline from the repo root:

```bash
scripts/evals/run-baseline                                       # sentinel tier, 3 trials, ~40 runs, 2-3 hours
scripts/evals/run-baseline --scenarios triggering-writing-plans --trials 1   # smoke run
```

Fixed (no flag overrides them): agent `claude`, credential `opus5_bedrock` (Opus 5 on Bedrock Mantle, `us-east-1`), grader `anthropic.claude-sonnet-5` on the same Mantle endpoint, tier `sentinel`, `--jobs 2`. The runner gives the agent the minted key as `AWS_BEARER_TOKEN_BEDROCK` and gives the grader the same key as `QUORUM_GRADER_ANTHROPIC_API_KEY`. It also sets `QUORUM_GRADER_SOURCE_MODE=appliance-scoped` and the Mantle base URL, so the grader reads only that name. Why: local `run-all` does not send the grader to Mantle on its own, and scoped mode stops a stray `ANTHROPIC_API_KEY` from sending it to the direct API. The runner stages the scenarios with `superpowers:<skill>` rewritten to `castor:<skill>` in each scenario's checks and story. Why: native `Skill` calls match by exact name, so unrewritten checks fail against castor. Run dirs (transcripts, verdicts) go to `~/.castor/eval-runs/<stamp>/`. Why: the repo is public and transcripts can hold sensitive tool output. Only the summary, `docs/evals/baseline-<date>.md` (scenario names and counts), enters the repo. A smoke run writes that file too, and the runner refuses to overwrite an existing one (it checks before the first trial). Why: a same-day smoke run would otherwise replace the committed baseline. Move or delete the smoke file before the real run.

- Both models bill to the AWS account of the active profile. Why: the human moved the baseline to Bedrock on 2026-11-08, after `claude setup-token` failed on their account, and asked for profile auth.
- The agent under test runs with `--dangerously-skip-permissions` in a throwaway `$HOME`; run it only on a machine where you accept that. Why: nothing else isolates it on a native host.
- Don't edit `skills/`, `hooks/` or `.claude-plugin/` while a baseline runs. Why: the worktree is the live plugin for the whole run, and a mid-run edit makes the numbers describe no single revision. The runner re-checks HEAD and those paths after the last trial and marks the baseline `dirty: yes` if they changed.
- Stop a run with Ctrl-C in its terminal, not `kill` on the runner. Why: bash defers the runner's trap until the foreground trial exits, so a plain `kill` leaves the current trial running and spending. After a stop, a new run refuses for about 150 seconds on the harness's live-spend lock (`~/.quorum/live-spend.lock.d`). Why: the harness reclaims a dead run's lock only once its heartbeat is stale (5 × 30 s, `evals/src/campaign/locks.ts`).
- Check `AWS_PROFILE` before a run. Why: the minted key carries that profile's account and permissions, so the run bills whichever account it names.
-->

## Design docs

Design docs live in `docs/castor/` (gitignored, local).
