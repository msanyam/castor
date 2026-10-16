# castor

Claude Code plugin with git maintenance skills for the team.

| Command | What it does |
|---|---|
| `/castor:git-worktree-cleanup [--dry-run] [--all]` | Finds merged, orphaned, and stale git worktrees (including Conductor workspaces), reports disk usage, and removes only what is provably safe after one confirmation. |
| `/castor:git-branch-cleanup [--dry-run] [--local] [--remote]` | Finds local and remote branches whose exact tip is merged (including squash merges), and deletes them after separate local and remote confirmations. |

Both skills are user-invoked only. Start with `--dry-run` to see the report without changing anything.

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
skills/<name>/SKILL.md            one directory per command
```

To release, bump `version` in both `plugin.json` and `marketplace.json` (`claude plugin tag` checks they agree). Users only receive updates when the version changes.

## Safety model

- Nothing is deleted without a confirmation that lists the exact items.
- Worktrees are removed without `--force`; branches are deleted only when their exact tip is proven merged.
- Remote deletes need their own confirmation and cover only your own branches.
- If your permission rules deny a delete (for example `git branch -d`), the skill stops and prints the commands for you to run instead of working around the denial.
