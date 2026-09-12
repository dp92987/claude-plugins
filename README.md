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

### [jira-ticket-creator](plugins/jira-ticket-creator/)

Create a Jira ticket, filling exactly the fields you would fill by hand (project,
type, component, labels, story points on a built-in default scale the profile can
refine, epic in `Parent`, story linked as "split to", sprint by id or exact name),
leaving status, assignee and priority alone. Team specifics live in per-team
profiles under the plugin's data directory, picked by the repo's git remote and
created by `/jira-ticket-creator:setup`. The description is
shaped by the issue type: `Task` and `Bug` get two
layers — an intro paragraph for a human with a one-line `DOD:`, then a technical
spec (files, symbols, exemplar, traps, tests, base branch) an agent can start from
with no conversation context — while `Story` gets a paragraph plus its links,
`Research` a paragraph plus a `DOD:`, and the rest no template at all.
Section rules are grounded in named industry practice (INVEST, acceptance
criteria, Goals/Non-goals, bug-report anatomy). Every fact is verified in its
primary source first; the ticket is created straight away and the full text is
shown afterwards for correction.

Skills: `jira-ticket-creator`.

### [session-report-for-jira](plugins/session-report-for-jira/)

Post a "Claude Code session report" comment on a Jira ticket: what the session accomplished (task, PRs, review outcomes, deploy notes) plus session metadata — session link, cost, API/wall duration, code changes, and per-model token usage. Numbers come only from the user's pasted `/usage` output; the skill never estimates or fabricates them. Resolves the ticket from the branch name, previews the comment before posting, and never transitions the ticket. Requires the Atlassian MCP server.

Skills: `jira-session-report`.

### [github-pr-creator](plugins/github-pr-creator/)

Create a GitHub pull request from the current branch, filling only the title,
the body and the base branch — labels, reviewers, draft and assignee are left
alone. The title is conventional-commits with the Jira key from the branch
name; the body is the clickable ticket link, a short "what was done" written
from the diff, a "verified" line, and a mandatory rollout section: which
services, into which production clusters (read from each service's deploy
manifest at PR time), in what order, and which config keys and secrets must
exist before and after — names and paths, never values. A repository PR
template is followed strictly when present. Everything unknown is asked in one
round before creation, so the PR never carries an open question. The only
setting is a repo-to-Jira-site table the skill maintains itself. Requires `gh`.

Skills: `github-pr-creator`.

### [ticket-to-pr](plugins/ticket-to-pr/)

Take a Jira ticket to a pull request in one manual command:
`/ticket-to-pr:full <ticket>` runs every step the repo's profile enables with
no process questions, `/ticket-to-pr:partial <ticket>` shows a checklist first.
The pipeline is implement (in the current session) → adversarial pre-review by
a Claude subagent and/or Codex, with confirmed findings fixed and one re-check
→ commit → push → PR (via a PR-creating skill named in the profile) → summon
the team's PR reviewers (Copilot through the reviewers API, Claude through an
`@claude` comment). Open questions from the ticket and the code are asked in one
round before work starts; the answers go into the PR body. Team specifics live in per-team profiles
under the plugin's data directory, picked by git remote and created by
`/ticket-to-pr:setup`; an unmapped repo runs setup first. Requires `gh` and the
Atlassian MCP server; `codex` optional.

Skills: `ticket-to-pr`.
