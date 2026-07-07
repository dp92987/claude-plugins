# claude-plugins

Personal Claude Code plugin marketplace by dp92987.

## Install

Add the marketplace in Claude Code:

```
/plugin marketplace add dp92987/claude-plugins
```

Then install a plugin:

```
/plugin install <plugin>@dp92987-claude-plugins
```

## Plugins

### [learning-loop](plugins/learning-loop/)

Self-learning loop that captures personal engineering style — code style, architecture decisions, naming, testing preferences, things rejected in review — into memory files (`~/.claude/learning-loop-memory/`). Claude Code consumes them via `@` imports in `~/.claude/CLAUDE.md`; Codex and other agents via the `~/.claude/AGENTS.md` pointer. Bundles a SessionEnd hook (disabled by default) for automatic extraction from finished sessions.

Skills: `learning-loop`.

### [codex-tandem](plugins/codex-tandem/)

Claude orchestrates, Codex codes. A SessionStart hook routes bounded implementation work to the OpenAI Codex CLI by default: Claude does requirements, research, planning, briefs, and verification; Codex writes the code. Review is built in — every Codex diff gets Claude's contextual review plus an independent `codex-review`; substantial Claude-authored code is Codex-reviewed too, with an adversarial whole-branch gate before PRs. Requires an installed and authenticated `codex` CLI.

Skills: `codex-implementation`, `codex-review`.

### [jira-session-report](plugins/jira-session-report/)

Post a "Claude Code session report" comment on a Jira ticket: what the session accomplished (task, PRs, review outcomes, deploy notes) plus session metadata — session link, cost, API/wall duration, code changes, and per-model token usage. Numbers come only from the user's pasted `/usage` output; the skill never estimates or fabricates them. Resolves the ticket from the branch name, previews the comment before posting, and never transitions the ticket. Requires the Atlassian MCP server.

Skills: `jira-session-report`.
