# castor

Claude Code plugin for building features in existing codebases: a brainstorm, plan, TDD, debug, and review workflow, plus git maintenance skills for the team.

## Skills

**Git maintenance** (user-invoked only; start with `--dry-run` to see the report without changing anything):

| Command | What it does |
|---|---|
| `/castor:git-worktree-cleanup [--dry-run] [--all]` | Finds merged, orphaned, and stale git worktrees (including Conductor workspaces), reports disk usage, and removes only what is provably safe after one confirmation. |
| `/castor:git-branch-cleanup [--dry-run] [--local] [--remote]` | Finds local and remote branches whose exact tip is merged (including squash merges), and deletes them after separate local and remote confirmations. |

**Workflow skills** (absorbed from superpowers): invoked as `castor:<name>` and auto-triggered by the SessionStart bootstrap.

| Skill | When it applies |
|---|---|
| `castor:brainstorming` | Before any creative work: turn an idea into a design. |
| `castor:writing-plans` | A spec exists and a multi-step task needs a plan. |
| `castor:executing-plans` | Execute a plan yourself in the current session. |
| `castor:subagent-driven-development` | Execute a plan with independent tasks via subagents. |
| `castor:dispatching-parallel-agents` | Two or more independent tasks with no shared state. |
| `castor:test-driven-development` | Any feature or bugfix, before writing implementation code. |
| `castor:systematic-debugging` | Any bug, test failure, or unexpected behavior. |
| `castor:verification-before-completion` | Before claiming work is done, fixed, or passing. |
| `castor:requesting-code-review` | After completing tasks or major features. |
| `castor:receiving-code-review` | Before acting on review feedback. |
| `castor:using-git-worktrees` | Feature work that needs isolation from the current workspace. |
| `castor:finishing-a-development-branch` | Implementation is done and tests pass; decide how to integrate. |
| `castor:writing-skills` | Creating or editing skills. |
| `castor:using-superpowers` | The bootstrap that teaches the session to find and use skills. |

**Diagnosis:** `/castor:diagnose-castor` explains why a castor session went wrong (repeated work, ignored plans, a skill that did not fire, cost) and can build a bug report for the maintainers.

If superpowers is installed, disable it: both plugins inject the same bootstrap.

## Install

Pick a scope. The plugin is identical in all three; scope only decides who gets it.

| Scope | Who gets it | Where it is recorded |
|---|---|---|
| `user` | You, in every project | `~/.claude/settings.json` |
| `project` | Everyone who clones a repo, prompted to install on trust | `.claude/settings.json` (commit it) |
| `local` | You, in one project only | `.claude/settings.local.json` (gitignored) |

### Globally (all your projects)

```bash
claude plugin marketplace add msanyam/castor
claude plugin install castor@castor --scope user
```

Or inside a session: `/plugin marketplace add msanyam/castor`, then `/plugin install castor@castor`.

### Locally (one project, just you)

Run from inside that project:

```bash
claude plugin marketplace add msanyam/castor
claude plugin install castor@castor --scope local
```

### For a whole team's repo (shared, committed)

```bash
claude plugin marketplace add msanyam/castor
claude plugin install castor@castor --scope project
```

Commit the resulting `.claude/settings.json`, and check it contains both entries below; add `extraKnownMarketplaces` by hand if it is missing. Teammates are then prompted to install the plugin the first time they open the repo in Claude Code and trust it.

```json
{
  "extraKnownMarketplaces": {
    "castor": { "source": { "source": "github", "repo": "msanyam/castor" } }
  },
  "enabledPlugins": { "castor@castor": true }
}
```

Restart Claude Code after installing, then type `/castor:` to see the commands.

### Update and remove

```bash
claude plugin marketplace update castor
claude plugin update castor@castor
claude plugin uninstall castor@castor --scope <user|project|local>
```

## Develop

Load the plugin straight from a checkout, without installing:

```bash
claude --plugin-dir /path/to/castor
claude plugin validate /path/to/castor
```

Layout:

```
.claude-plugin/plugin.json        plugin manifest (name = command prefix)
.claude-plugin/marketplace.json   makes this repo installable as a marketplace
skills/<name>/SKILL.md            one directory per skill
```

Contributor rules, upstream merge steps, and tests are in `AGENTS.md`.

To release, bump `version` in both `plugin.json` and `marketplace.json` (`claude plugin tag` checks they agree). Users only receive updates when the version changes.

## Safety model

- Nothing is deleted without a confirmation that lists the exact items.
- Worktrees are removed without `--force`; branches are deleted only when their exact tip is proven merged.
- Remote deletes need their own confirmation and cover only your own branches.
- If your permission rules deny a delete (for example `git branch -d`), the skill stops and prints the commands for you to run instead of working around the denial.

Built on [superpowers](https://github.com/obra/superpowers) by Jesse Vincent, MIT; see LICENSE.
